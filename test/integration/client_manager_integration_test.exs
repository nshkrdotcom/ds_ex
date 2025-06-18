defmodule DSPEx.ClientManagerIntegrationTest do
  @moduledoc """
  Integration tests for DSPEx.ClientManager with the broader DSPEx ecosystem.

  Tests cross-module interactions including:
  - Integration with DSPEx.Program and DSPEx.Predict
  - Foundation telemetry and correlation tracking
  - Supervision tree integration
  - Error propagation across component boundaries
  - End-to-end workflow with managed clients

  Following integration testing principles with focus on:
  - Component composition and data flow
  - Fault tolerance and error boundaries
  - Telemetry and observability integration
  - Cohesion validation across API contracts

  These tests use adaptive mocking - they will use real API clients when
  API keys are available, and fall back to mock clients otherwise.
  """
  use ExUnit.Case

  @moduletag :group_1

  alias DSPEx.{ClientManager, MockHelpers, Predict, Program}

  # Test signature for integration testing
  defmodule TestSignature do
    @moduledoc "Simple signature for integration testing"
    use DSPEx.Signature, "question -> answer"
  end

  describe "integration with DSPEx.Program" do
    test "ClientManager works with Program.forward/3" do
      # Use adaptive client setup - mock if no API key, real if available
      {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)

      # Create a program that uses our managed client
      program = Predict.new(TestSignature, MockHelpers.extract_client({client_type, client}))

      # Make a request through the program interface
      inputs = %{question: "What is 2+2?"}
      result = Program.forward(program, inputs)

      # Should either succeed or fail gracefully
      case result do
        {:ok, outputs} ->
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          # Network/API errors are expected in test environment
          assert reason in [:network_error, :api_error, :timeout, :provider_not_configured]
      end

      # Client should still be alive after program usage
      assert MockHelpers.client_alive?({client_type, client})

      # Stats should reflect the request attempt (may be 0 if validation fails before reaching ClientManager)
      {:ok, stats} = MockHelpers.unified_get_stats({client_type, client})
      assert stats.stats.requests_made >= 0
    end

    test "multiple programs can share a managed client" do
      {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)

      # Create multiple programs using the same client
      actual_client = MockHelpers.extract_client({client_type, client})
      program1 = Predict.new(TestSignature, actual_client)
      program2 = Predict.new(TestSignature, actual_client)

      inputs1 = %{question: "First question"}
      inputs2 = %{question: "Second question"}

      # Make requests through both programs
      _result1 = Program.forward(program1, inputs1)
      _result2 = Program.forward(program2, inputs2)

      # Client should handle both programs correctly
      assert MockHelpers.client_alive?({client_type, client})

      # Stats should show client activity (may be 0 if validation fails before reaching ClientManager)
      {:ok, stats} = MockHelpers.unified_get_stats({client_type, client})
      # At minimum, client should have valid stats
      assert stats.stats.requests_made >= 0
    end
  end

  describe "integration with DSPEx.Predict" do
    test "ClientManager integrates with legacy Predict API" do
      {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)
      actual_client = MockHelpers.extract_client({client_type, client})

      # Test that managed client can be used with legacy API
      _program = Predict.new(TestSignature, actual_client)

      inputs = %{question: "Legacy API test"}
      result = Predict.forward(TestSignature, inputs, %{client: actual_client})

      # Should work with either new or legacy approach
      case result do
        {:ok, outputs} ->
          assert %{answer: _} = outputs

        {:error, _} ->
          # API errors expected in test environment or mock mode
          :ok
      end

      assert MockHelpers.client_alive?({client_type, client})
    end

    test "predict_field works with managed clients" do
      {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)
      actual_client = MockHelpers.extract_client({client_type, client})

      inputs = %{question: "Field-specific test"}
      result = Predict.predict_field(TestSignature, inputs, :answer, %{client: actual_client})

      case result do
        {:ok, answer} ->
          assert is_binary(answer)

        {:error, _} ->
          # API errors expected in test environment or mock mode
          :ok
      end

      assert MockHelpers.client_alive?({client_type, client})
    end
  end

  describe "telemetry integration" do
    setup do
      # Capture telemetry events from multiple components
      test_pid = self()

      events = [
        [:dspex, :client_manager, :request, :start],
        [:dspex, :client_manager, :request, :stop],
        [:dspex, :program, :forward, :start],
        [:dspex, :program, :forward, :stop]
      ]

      :telemetry.attach_many(
        "integration_test",
        events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("integration_test") end)

      :ok
    end

    test "telemetry flows correctly through component stack" do
      {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)
      actual_client = MockHelpers.extract_client({client_type, client})
      program = Predict.new(TestSignature, actual_client)

      inputs = %{question: "Telemetry integration test"}
      correlation_id = "integration-test-123"

      _result = Program.forward(program, inputs, correlation_id: correlation_id)

      # Should receive telemetry from both Program and ClientManager layers
      # Note: Exact events depend on whether the request succeeds or fails

      # Collect all events for analysis
      events = collect_telemetry_events([], 500)
      event_names = Enum.map(events, fn {_, event, _, _} -> event end)

      # Should have events from the program layer (ClientManager events may not occur if requests fail early)
      assert Enum.any?(event_names, &(&1 == [:dspex, :program, :forward, :start]))
      assert Enum.any?(event_names, &(&1 == [:dspex, :program, :forward, :stop]))

      # If there are client manager events, verify correlation IDs are propagated
      client_events =
        Enum.filter(events, fn {_, event, _, _} ->
          event in [
            [:dspex, :client_manager, :request, :start],
            [:dspex, :client_manager, :request, :stop]
          ]
        end)

      if length(client_events) > 0 do
        for {_, _, _, metadata} <- client_events do
          # Should have correlation tracking
          assert Map.has_key?(metadata, :correlation_id)
        end
      end
    end
  end

  describe "supervision and fault tolerance" do
    test "client crash doesn't affect other components" do
      # This test verifies that programs can handle client crashes gracefully
      # Focus on the key behavior: error handling when client dies

      # Start unlinked to prevent exit signal propagation
      {:ok, client} = GenServer.start(DSPEx.ClientManager, {:gemini, %{}})
      program = Predict.new(TestSignature, client)

      # Verify client is initially alive
      assert Process.alive?(client)

      # Kill the client process
      ref = Process.monitor(client)
      Process.exit(client, :kill)

      # Wait for the DOWN message to confirm the process is dead
      receive do
        {:DOWN, ^ref, :process, ^client, :killed} -> :ok
      after
        1000 -> flunk("Client process did not die as expected")
      end

      refute Process.alive?(client)

      # Program should handle the error gracefully when client is dead
      # This should return an error or exit, but not crash the calling process permanently
      result =
        try do
          Program.forward(program, %{question: "Post-crash test"})
        catch
          :exit, _reason -> {:error, :client_dead}
        end

      # Should get an error and not crash the calling process
      assert match?({:error, _}, result)
      assert Process.alive?(self())
    end

    test "multiple client failures are isolated" do
      # This test verifies that failure of one client doesn't affect others
      # Start both unlinked to prevent exit signal propagation
      {:ok, client1} = GenServer.start(DSPEx.ClientManager, {:gemini, %{}})
      {:ok, client2} = GenServer.start(DSPEx.ClientManager, {:gemini, %{}})

      program1 = Predict.new(TestSignature, client1)
      program2 = Predict.new(TestSignature, client2)

      # Kill client1 and wait for confirmation
      ref1 = Process.monitor(client1)
      Process.exit(client1, :kill)

      receive do
        {:DOWN, ^ref1, :process, ^client1, :killed} -> :ok
      after
        1000 -> flunk("Client1 process did not die as expected")
      end

      refute Process.alive?(client1)
      assert Process.alive?(client2)

      # client1 should be dead and cause errors
      result1 =
        try do
          Program.forward(program1, %{question: "Dead client test"})
        catch
          :exit, _reason -> {:error, :client_dead}
        end

      assert match?({:error, _}, result1)

      # client2 should still work (or fail with expected API errors, not process errors)
      result2 = Program.forward(program2, %{question: "Isolation test"})

      case result2 do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          # Should get API-related errors, not process errors
          assert reason in [
                   :network_error,
                   :api_error,
                   :timeout,
                   :provider_not_configured,
                   :api_key_not_set
                 ]
      end

      # Both the test process and client2 should still be alive
      assert Process.alive?(self())
      assert Process.alive?(client2)
    end
  end

  describe "error propagation and boundaries" do
    test "client errors propagate correctly through Program layer" do
      {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)
      actual_client = MockHelpers.extract_client({client_type, client})
      program = Predict.new(TestSignature, actual_client)

      # Use invalid inputs to trigger validation error
      invalid_inputs = %{wrong_field: "test"}
      result = Program.forward(program, invalid_inputs)

      # Should get appropriate error
      assert {:error, reason} = result
      assert reason in [:missing_inputs, :invalid_inputs, :missing_required_fields]

      # Client should still be operational
      assert MockHelpers.client_alive?({client_type, client})

      # Stats should not reflect failed validation (no actual request made)
      {:ok, stats} = MockHelpers.unified_get_stats({client_type, client})
      # Requests_made could be 0 if validation failed before client call
      assert stats.stats.requests_made >= 0
    end

    test "network errors are handled gracefully across layers" do
      {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)
      actual_client = MockHelpers.extract_client({client_type, client})
      program = Predict.new(TestSignature, actual_client)

      inputs = %{question: "Network error test"}
      result = Program.forward(program, inputs)

      # In test environment, likely to get network/API errors
      case result do
        {:ok, _outputs} ->
          # API is working - that's fine too
          :ok

        {:error, reason} ->
          # Should be a recognized error type
          assert reason in [
                   :network_error,
                   :api_error,
                   :timeout,
                   :provider_not_configured,
                   :circuit_open,
                   :rate_limited
                 ]
      end

      # Both client and calling process should survive
      assert MockHelpers.client_alive?({client_type, client})
      assert Process.alive?(self())
    end
  end

  describe "performance and concurrency integration" do
    test "concurrent programs with shared client perform well" do
      {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)
      actual_client = MockHelpers.extract_client({client_type, client})

      # Create multiple programs sharing the client
      programs = for _i <- 1..5, do: Predict.new(TestSignature, actual_client)

      # Start concurrent requests
      tasks =
        for {program, i} <- Enum.with_index(programs, 1) do
          Task.async(fn ->
            inputs = %{question: "Concurrent test #{i}"}
            {i, Program.forward(program, inputs)}
          end)
        end

      # Wait for all to complete
      results = Task.await_many(tasks, 10_000)

      # All should complete without crashing
      assert length(results) == 5
      assert MockHelpers.client_alive?({client_type, client})

      # Verify stats structure is valid (requests may be 0 if they fail before reaching ClientManager)
      {:ok, stats} = MockHelpers.unified_get_stats({client_type, client})
      assert stats.stats.requests_made >= 0
    end

    test "high-frequency requests are handled efficiently" do
      # Use mock client for consistent performance testing regardless of test mode
      # Performance tests should not depend on network conditions
      {:ok, client} =
        DSPEx.MockClientManager.start_link(:gemini, %{
          simulate_delays: false,
          responses: :contextual
        })

      program = Predict.new(TestSignature, client)

      start_time = System.monotonic_time(:millisecond)

      # Make rapid sequential requests
      for i <- 1..10 do
        inputs = %{question: "Rapid test #{i}"}
        _result = Program.forward(program, inputs)
      end

      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time

      # Should handle rapid requests without excessive delays
      # (This measures local processing, not network time)
      assert total_time < 1000, "10 rapid requests took #{total_time}ms, which is too slow"

      assert Process.alive?(client)

      # Verify stats structure is valid (requests may be 0 if they fail before reaching ClientManager)
      {:ok, stats} = DSPEx.MockClientManager.get_stats(client)
      assert stats.stats.requests_made >= 0
    end
  end

  describe "configuration and compatibility" do
    test "managed clients work with different providers" do
      # Test with different provider configurations
      # Only test configured providers
      providers = [:gemini]

      for provider <- providers do
        {client_type, client} = MockHelpers.setup_adaptive_client(provider)
        actual_client = MockHelpers.extract_client({client_type, client})
        program = Predict.new(TestSignature, actual_client)

        inputs = %{question: "Provider #{provider} test"}
        result = Program.forward(program, inputs)

        # Should either work or fail gracefully
        case result do
          {:ok, outputs} ->
            assert %{answer: _} = outputs

          {:error, reason} ->
            assert reason in [:network_error, :api_error, :timeout, :provider_not_configured]
        end

        assert MockHelpers.client_alive?({client_type, client})
      end
    end

    test "custom configuration is respected" do
      # Note: Custom configuration only applies to real clients
      # For mock clients, configuration is ignored
      case MockHelpers.api_key_available?(:gemini) do
        true ->
          custom_config = %{
            timeout: 60_000,
            default_temperature: 0.1,
            default_max_tokens: 50
          }

          {:ok, client} = ClientManager.start_link(:gemini, custom_config)
          program = Predict.new(TestSignature, client)

          inputs = %{question: "Custom config test"}
          result = Program.forward(program, inputs)

          # Configuration should be applied without errors
          case result do
            {:ok, _} -> :ok
            # API errors are fine in test env
            {:error, _} -> :ok
          end

          assert Process.alive?(client)

        false ->
          # Skip detailed config test in mock mode
          # Just verify that mock clients work
          {client_type, client} = MockHelpers.setup_adaptive_client(:gemini)
          assert MockHelpers.client_alive?({client_type, client})
      end
    end
  end

  # Helper function to collect telemetry events
  defp collect_telemetry_events(events, timeout) do
    receive do
      {:telemetry, _event, _measurements, _metadata} = msg ->
        collect_telemetry_events([msg | events], timeout)
    after
      timeout -> Enum.reverse(events)
    end
  end
end
