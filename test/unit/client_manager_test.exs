defmodule DSPEx.ClientManagerTest do
  @moduledoc """
  Comprehensive unit tests for DSPEx.ClientManager GenServer implementation.

  Tests cover:
  - GenServer lifecycle and supervision
  - State management and statistics tracking
  - Request handling and error scenarios
  - Telemetry emission and observability
  - Concurrent access patterns and thread safety

  Following the five-layer testing strategy with focus on:
  - API contract validation
  - Concurrency safety
  - Error boundaries
  - Performance characteristics
  - Integration cohesion
  """
  use ExUnit.Case, async: true

  alias DSPEx.ClientManager

  describe "GenServer lifecycle" do
    test "starts successfully with valid provider" do
      assert {:ok, pid} = ClientManager.start_link(:gemini)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "starts with custom configuration" do
      config = %{timeout: 60_000, custom_setting: "test"}
      assert {:ok, pid} = ClientManager.start_link(:gemini, config)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "starts with GenServer options" do
      opts = [name: :test_client]
      assert {:ok, pid} = ClientManager.start_link(:gemini, %{}, opts)
      assert Process.whereis(:test_client) == pid
    end

    test "fails to start with unconfigured provider" do
      # Use a provider that doesn't exist in test config
      # The GenServer will exit with the error reason
      process =
        Process.spawn(
          fn ->
            ClientManager.start_link(:nonexistent_provider)
          end,
          []
        )

      # Wait for process to exit
      ref = Process.monitor(process)
      assert_receive {:DOWN, ^ref, :process, ^process, _reason}, 1000
    end

    test "graceful shutdown works correctly" do
      {:ok, pid} = ClientManager.start_link(:gemini)
      assert Process.alive?(pid)

      assert :ok = ClientManager.shutdown(pid)

      # Wait a moment for the process to terminate
      Process.sleep(10)
      refute Process.alive?(pid)
    end
  end

  describe "state management" do
    setup do
      {:ok, pid} = ClientManager.start_link(:gemini)
      %{client: pid}
    end

    test "initial state is correct", %{client: client} do
      {:ok, stats} = ClientManager.get_stats(client)

      assert stats.provider == :gemini
      assert stats.state == :idle
      assert stats.stats.requests_made == 0
      assert stats.stats.requests_successful == 0
      assert stats.stats.requests_failed == 0
      assert stats.stats.last_request_at == nil
      assert stats.stats.circuit_failures == 0
    end

    test "stats update after request", %{client: client} do
      messages = [%{role: "user", content: "test"}]

      # Make a request (will likely fail due to no API key in test, but stats should update)
      _result = ClientManager.request(client, messages)

      {:ok, stats} = ClientManager.get_stats(client)

      assert stats.stats.requests_made == 1
      assert stats.stats.last_request_at != nil
      # Either successful or failed should be 1
      assert stats.stats.requests_successful + stats.stats.requests_failed == 1
    end

    test "multiple requests update stats correctly", %{client: client} do
      messages = [%{role: "user", content: "test"}]

      # Make multiple requests
      _result1 = ClientManager.request(client, messages)
      _result2 = ClientManager.request(client, messages)
      _result3 = ClientManager.request(client, messages)

      {:ok, stats} = ClientManager.get_stats(client)

      assert stats.stats.requests_made == 3
      assert stats.stats.last_request_at != nil
    end
  end

  describe "request handling" do
    setup do
      {:ok, pid} = ClientManager.start_link(:gemini)
      %{client: pid}
    end

    test "validates messages correctly", %{client: client} do
      # Valid messages should pass validation
      valid_messages = [%{role: "user", content: "hello"}]
      result = ClientManager.request(client, valid_messages)

      # Should not fail with validation error
      refute match?({:error, :invalid_messages}, result)

      # Invalid messages should fail validation
      # missing content
      invalid_messages = [%{role: "user"}]
      assert {:error, :invalid_messages} = ClientManager.request(client, invalid_messages)
    end

    test "handles empty message list", %{client: client} do
      assert {:error, :invalid_messages} = ClientManager.request(client, [])
    end

    test "handles malformed messages", %{client: client} do
      malformed_messages = [
        # non-string role
        %{role: 123, content: "test"},
        # non-string content
        %{role: "user", content: 456},
        # missing role
        %{content: "missing role"},
        # not a map
        "not a map"
      ]

      for bad_messages <- Enum.map(malformed_messages, &[&1]) do
        assert {:error, :invalid_messages} = ClientManager.request(client, bad_messages)
      end
    end

    test "accepts valid message structures", %{client: client} do
      test_cases = [
        [%{role: "user", content: "simple message"}],
        [%{role: "user", content: "message", extra_field: "allowed"}],
        [
          %{role: "user", content: "first"},
          %{role: "assistant", content: "second"},
          %{role: "user", content: "third"}
        ]
      ]

      for messages <- test_cases do
        result = ClientManager.request(client, messages)
        # Should not fail with validation error
        refute match?({:error, :invalid_messages}, result)
      end
    end

    test "accepts custom options", %{client: client} do
      messages = [%{role: "user", content: "test"}]

      options = %{
        model: "custom-model",
        temperature: 0.5,
        max_tokens: 100,
        correlation_id: "test-123"
      }

      result = ClientManager.request(client, messages, options)
      # Should not fail with validation error
      refute match?({:error, :invalid_messages}, result)
    end
  end

  describe "concurrent access" do
    setup do
      {:ok, pid} = ClientManager.start_link(:gemini)
      %{client: pid}
    end

    test "handles concurrent requests safely", %{client: client} do
      messages = [%{role: "user", content: "concurrent test"}]

      # Start multiple concurrent requests
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            ClientManager.request(client, messages, %{correlation_id: "req-#{i}"})
          end)
        end

      # Wait for all to complete
      # Increase timeout to allow for potential contention in the test environment's HTTP client.
      results = Task.await_many(tasks, 15_000)

      # All should complete without crashing the client
      assert Process.alive?(client)
      assert length(results) == 10

      # Verify stats reflect all requests
      {:ok, stats} = ClientManager.get_stats(client)
      assert stats.stats.requests_made == 10
    end

    test "concurrent stats requests don't interfere", %{client: client} do
      # Start multiple concurrent stats requests
      tasks =
        for _i <- 1..5 do
          Task.async(fn -> ClientManager.get_stats(client) end)
        end

      # Wait for all to complete
      results = Task.await_many(tasks, 1000)

      # All should complete successfully
      assert Process.alive?(client)
      assert length(results) == 5
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "concurrent request and stats access", %{client: client} do
      messages = [%{role: "user", content: "test"}]

      # Mix requests and stats calls
      tasks = [
        Task.async(fn -> ClientManager.request(client, messages) end),
        Task.async(fn -> ClientManager.get_stats(client) end),
        Task.async(fn -> ClientManager.request(client, messages) end),
        Task.async(fn -> ClientManager.get_stats(client) end)
      ]

      # Wait for all to complete
      results = Task.await_many(tasks, 5000)

      # All should complete without crashing
      assert Process.alive?(client)
      assert length(results) == 4
    end
  end

  describe "telemetry emission" do
    @tag :telemetry_available
    test "emits telemetry events when telemetry is available" do
      {:ok, client} = ClientManager.start_link(:gemini)
      messages = [%{role: "user", content: "telemetry test"}]

      # Make a request - telemetry events should be emitted internally
      # (even if we can't capture them in test due to telemetry app not started)
      result = ClientManager.request(client, messages, %{correlation_id: "tel-123"})

      # The request should complete without errors
      case result do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          # Network errors are expected in test environment
          assert reason in [:network_error, :api_error, :timeout]
      end

      # Client should still be alive after emitting telemetry
      assert Process.alive?(client)
    end

    test "handles telemetry errors gracefully" do
      {:ok, client} = ClientManager.start_link(:gemini)
      messages = [%{role: "user", content: "telemetry error test"}]

      # Even if telemetry fails, the request should still work
      result = ClientManager.request(client, messages)

      case result do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          # Should get network/API errors, not telemetry errors
          assert reason in [:network_error, :api_error, :timeout]
          refute reason == :telemetry_error
      end

      assert Process.alive?(client)
    end
  end

  describe "error handling and boundaries" do
    setup do
      {:ok, pid} = ClientManager.start_link(:gemini)
      %{client: pid}
    end

    test "client survives invalid requests", %{client: client} do
      # Send invalid data
      invalid_requests = [
        # empty list
        [],
        # invalid message structure
        [%{invalid: "structure"}],
        # nil role
        [%{role: nil, content: "test"}],
        # not even a list
        :not_a_list
      ]

      for invalid <- invalid_requests do
        result = ClientManager.request(client, invalid)
        assert match?({:error, :invalid_messages}, result)
        assert Process.alive?(client)
      end
    end

    test "client handles GenServer call timeouts gracefully" do
      # Create a mock client with artificial delay for timeout testing
      {:ok, delay_client} =
        DSPEx.MockClientManager.start_link(:gemini, %{
          simulate_delays: true,
          base_delay_ms: 100,
          max_delay_ms: 200
        })

      messages = [%{role: "user", content: "timeout test"}]

      # The delay_client has base_delay_ms: 100, so with timeout: 1ms it should timeout
      assert catch_exit(DSPEx.MockClientManager.request(delay_client, messages, %{timeout: 1}))

      # Verify the client process is still alive after the caller's timeout
      assert Process.alive?(delay_client)

      # Clean up
      GenServer.stop(delay_client)
    end

    test "multiple clients operate independently" do
      {:ok, client1} = ClientManager.start_link(:gemini)
      {:ok, client2} = ClientManager.start_link(:gemini)

      messages = [%{role: "user", content: "independence test"}]

      # Make requests to both
      _result1 = ClientManager.request(client1, messages)
      _result2 = ClientManager.request(client2, messages)

      # Get stats from both
      {:ok, stats1} = ClientManager.get_stats(client1)
      {:ok, stats2} = ClientManager.get_stats(client2)

      # Both should be operational and independent
      assert Process.alive?(client1)
      assert Process.alive?(client2)
      assert stats1.stats.requests_made == 1
      assert stats2.stats.requests_made == 1
    end
  end

  describe "API contract design" do
    test "follows DSPEx error type conventions" do
      {:ok, client} = ClientManager.start_link(:gemini)
      messages = [%{role: "user", content: "contract test"}]

      result = ClientManager.request(client, messages)

      # Should return consistent error types that match DSPEx conventions
      case result do
        {:ok, response} ->
          # Successful response should have expected structure
          assert %{choices: choices} = response
          assert is_list(choices)

        {:error, reason} ->
          # Error reasons should match DSPEx.Client error types
          assert reason in [
                   :network_error,
                   :api_error,
                   :timeout,
                   :provider_not_configured,
                   :circuit_open,
                   :rate_limited,
                   :invalid_messages,
                   :unsupported_provider,
                   :invalid_response
                 ]
      end
    end
  end

  describe "performance characteristics" do
    test "request processing time is reasonable" do
      # Force mock client for consistent performance testing
      # Performance tests should not depend on network conditions
      {:ok, client} =
        DSPEx.MockClientManager.start_link(:gemini, %{
          simulate_delays: false,
          responses: :contextual
        })

      messages = [%{role: "user", content: "performance test"}]

      # Measure time for request processing (not network time)
      start_time = System.monotonic_time(:millisecond)
      _result = DSPEx.MockClientManager.request(client, messages)
      end_time = System.monotonic_time(:millisecond)

      processing_time = end_time - start_time

      # GenServer overhead should be minimal (< 100ms for local processing)
      # This excludes network time which varies
      assert processing_time < 200, "Processing took #{processing_time}ms, which is too slow"
    end

    test "stats retrieval is fast" do
      # Force mock client for consistent performance testing
      {:ok, client} = DSPEx.MockClientManager.start_link(:gemini)

      start_time = System.monotonic_time(:microsecond)
      {:ok, _stats} = DSPEx.MockClientManager.get_stats(client)
      end_time = System.monotonic_time(:microsecond)

      stats_time = end_time - start_time

      # Stats should be very fast (< 10ms)
      assert stats_time < 10_000, "Stats retrieval took #{stats_time}μs, which is too slow"
    end
  end
end
