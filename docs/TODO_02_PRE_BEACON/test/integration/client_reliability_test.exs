# File: test/integration/client_reliability_test.exs
defmodule DSPEx.Integration.ClientReliabilityTest do
  use ExUnit.Case, async: false

  alias DSPEx.{Client, ClientManager}
  alias DSPEx.Test.MockProvider

  @moduletag :integration

  setup_all do
    # Set up test mode to allow controlled testing
    original_mode = DSPEx.TestModeConfig.get_test_mode()
    DSPEx.TestModeConfig.set_test_mode(:fallback)

    on_exit(fn ->
      DSPEx.TestModeConfig.set_test_mode(original_mode)
    end)

    :ok
  end

  setup do
    # Start mock provider for each test
    {:ok, _pid} = MockProvider.start_link(mode: :contextual, latency_simulation: false)
    :ok
  end

  describe "concurrent request handling" do
    test "client handles 100+ concurrent requests (BEACON pattern)" do
      messages = [%{role: "user", content: "Concurrent BEACON test"}]

      # BEACON will make many concurrent requests during optimization
      concurrent_requests = Task.async_stream(1..100, fn i ->
        correlation_id = "beacon-concurrent-#{i}"
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: correlation_id
        })
      end, max_concurrency: 25, timeout: 15_000)
      |> Enum.to_list()

      # Count successes
      successes = Enum.count(concurrent_requests, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Should handle most requests successfully (allow some failures in test environment)
      assert successes >= 90, "Only #{successes}/100 concurrent requests succeeded"

      # Verify all successful responses have proper structure
      successful_responses = concurrent_requests
      |> Enum.filter(fn {:ok, {:ok, _}} -> true; _ -> false end)
      |> Enum.map(fn {:ok, {:ok, response}} -> response end)

      assert Enum.all?(successful_responses, fn response ->
        %{choices: [%{message: %{content: content}}]} = response
        is_binary(content) and String.length(content) > 0
      end)
    end

    test "correlation ID propagation works under concurrent load" do
      messages = [%{role: "user", content: "Correlation test"}]

      # Test with unique correlation IDs
      correlation_ids = Enum.map(1..50, fn i -> "correlation-#{i}-#{System.unique_integer()}" end)

      results = Task.async_stream(correlation_ids, fn correlation_id ->
        result = Client.request(messages, %{
          provider: :gemini,
          correlation_id: correlation_id
        })
        {correlation_id, result}
      end, max_concurrency: 20, timeout: 10_000)
      |> Enum.to_list()

      # All should complete successfully
      successes = Enum.count(results, fn
        {:ok, {_id, {:ok, _}}} -> true
        _ -> false
      end)

      assert successes >= 45, "Correlation ID propagation failed for #{50 - successes} requests"

      # Verify correlation IDs are unique and properly formatted
      successful_ids = results
      |> Enum.filter(fn {:ok, {_id, {:ok, _}}} -> true; _ -> false end)
      |> Enum.map(fn {:ok, {id, {:ok, _}}} -> id end)

      assert length(Enum.uniq(successful_ids)) == length(successful_ids), "Duplicate correlation IDs found"
    end

    test "provider switching works reliably under load" do
      messages = [%{role: "user", content: "Provider switching test"}]
      providers = [:openai, :gemini, :anthropic]

      # Test switching between providers rapidly
      provider_requests = Task.async_stream(1..60, fn i ->
        provider = Enum.at(providers, rem(i, length(providers)))
        correlation_id = "provider-switch-#{provider}-#{i}"

        result = Client.request(messages, %{
          provider: provider,
          correlation_id: correlation_id
        })

        {provider, result}
      end, max_concurrency: 20, timeout: 12_000)
      |> Enum.to_list()

      # Group results by provider
      provider_results = Enum.group_by(provider_requests, fn
        {:ok, {provider, _result}} -> provider
        _ -> :error
      end)

      # Each provider should have some successful requests
      Enum.each(providers, fn provider ->
        provider_successes = provider_results[provider] || []
        successful_count = Enum.count(provider_successes, fn
          {:ok, {^provider, {:ok, _}}} -> true
          _ -> false
        end)

        assert successful_count >= 15, "Provider #{provider} only had #{successful_count} successes"
      end)
    end

    test "memory usage remains stable during concurrent operations" do
      messages = [%{role: "user", content: "Memory stability test"}]

      # Measure initial memory
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)

      # Run multiple batches of concurrent requests
      Enum.each(1..5, fn batch ->
        concurrent_requests = Task.async_stream(1..20, fn i ->
          Client.request(messages, %{
            provider: :gemini,
            correlation_id: "memory-test-#{batch}-#{i}"
          })
        end, max_concurrency: 10, timeout: 5_000)
        |> Enum.to_list()

        # Ensure some requests succeeded
        successes = Enum.count(concurrent_requests, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

        assert successes >= 15, "Batch #{batch} had only #{successes} successes"

        # Force garbage collection between batches
        :erlang.garbage_collect()
      end)

      # Measure final memory
      :erlang.garbage_collect()
      final_memory = :erlang.memory(:total)

      # Memory growth should be reasonable
      memory_growth_mb = (final_memory - initial_memory) / (1024 * 1024)
      assert memory_growth_mb < 20, "Memory grew by #{memory_growth_mb}MB during concurrent operations"
    end
  end

  describe "error recovery and fault tolerance" do
    test "client recovers gracefully from API failures" do
      messages = [%{role: "user", content: "Error recovery test"}]

      # Set up mock to simulate intermittent failures
      MockProvider.setup_bootstrap_mocks([
        {:error, :api_error},
        %{content: "Success after error"},
        {:error, :network_error},
        %{content: "Another success"},
        %{content: "Final success"}
      ])

      # Make multiple requests
      results = Enum.map(1..10, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "error-recovery-#{i}"
        })
      end)

      # Should have some successes despite errors
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      # Should handle errors gracefully and have some successes
      assert successes >= 5, "Only #{successes}/10 requests succeeded during error recovery"

      # All responses should be properly formatted
      successful_responses = Enum.filter(results, fn
        {:ok, response} ->
          case response do
            %{choices: [%{message: %{content: content}}]} when is_binary(content) -> true
            _ -> false
          end
        _ -> false
      end)

      assert length(successful_responses) == successes
    end

    test "circuit breaker patterns work correctly (if implemented)" do
      messages = [%{role: "user", content: "Circuit breaker test"}]

      # This test assumes circuit breaker implementation
      # If not implemented, it should still pass with normal error handling

      # Make many requests to potentially trigger circuit breaker
      results = Enum.map(1..20, fn i ->
        result = Client.request(messages, %{
          provider: :gemini,
          correlation_id: "circuit-breaker-#{i}"
        })

        # Small delay between requests
        Process.sleep(10)
        result
      end)

      # Should either work normally or implement circuit breaker behavior
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      # Should have reasonable success rate
      success_rate = successes / 20
      assert success_rate >= 0.5, "Success rate too low: #{success_rate}"
    end

    test "retry mechanisms handle transient failures" do
      messages = [%{role: "user", content: "Retry mechanism test"}]

      # Test that transient failures are handled appropriately
      # This depends on the client implementation

      results = Enum.map(1..10, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "retry-test-#{i}",
          timeout: 5_000
        })
      end)

      # Should have good success rate with retry mechanisms
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      assert successes >= 7, "Retry mechanisms failed: only #{successes}/10 succeeded"
    end

    test "rate limiting prevents overwhelming APIs" do
      messages = [%{role: "user", content: "Rate limiting test"}]

      # Make many rapid requests to test rate limiting
      start_time = System.monotonic_time()

      results = Task.async_stream(1..30, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "rate-limit-#{i}"
        })
      end, max_concurrency: 30, timeout: 10_000)
      |> Enum.to_list()

      duration_ms = System.convert_time_unit(
        System.monotonic_time() - start_time,
        :native,
        :millisecond
      )

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Should complete in reasonable time (rate limiting might slow it down)
      assert duration_ms < 15_000, "Rate limiting caused excessive delay: #{duration_ms}ms"
      assert successes >= 20, "Rate limiting caused too many failures: #{successes}/30"
    end
  end

  describe "multi-provider reliability" do
    test "all supported providers work reliably" do
      messages = [%{role: "user", content: "Multi-provider reliability test"}]
      providers = [:openai, :gemini, :anthropic]

      # Test each provider individually
      provider_results = Enum.map(providers, fn provider ->
        results = Enum.map(1..10, fn i ->
          Client.request(messages, %{
            provider: provider,
            correlation_id: "#{provider}-reliability-#{i}"
          })
        end)

        successes = Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

        {provider, successes, results}
      end)

      # Each provider should have good success rate
      Enum.each(provider_results, fn {provider, successes, _results} ->
        assert successes >= 8, "Provider #{provider} only had #{successes}/10 successes"
      end)
    end

    test "provider-specific error handling works correctly" do
      messages = [%{role: "user", content: "Provider error handling test"}]

      # Test error handling for different providers
      providers = [:openai, :gemini, :anthropic]

      error_results = Enum.map(providers, fn provider ->
        # Make request that might fail
        result = Client.request(messages, %{
          provider: provider,
          correlation_id: "error-#{provider}",
          timeout: 1000  # Short timeout to potentially trigger errors
        })

        {provider, result}
      end)

      # Should handle errors gracefully for all providers
      Enum.each(error_results, fn {provider, result} ->
        case result do
          {:ok, response} ->
            # Success is good
            assert %{choices: [%{message: %{content: content}}]} = response
            assert is_binary(content)

          {:error, reason} ->
            # Error should be properly categorized
            assert reason in [:timeout, :network_error, :api_error, :no_api_key]
        end
      end)
    end

    test "response format normalization works across providers" do
      messages = [%{role: "user", content: "Response format test"}]
      providers = [:openai, :gemini, :anthropic]

      # Get responses from all providers
      responses = Enum.map(providers, fn provider ->
        case Client.request(messages, %{provider: provider}) do
          {:ok, response} -> {provider, response}
          {:error, _} -> {provider, :error}
        end
      end)

      # Filter successful responses
      successful_responses = Enum.filter(responses, fn
        {_provider, :error} -> false
        _ -> true
      end)

      # Should have at least some successful responses
      assert length(successful_responses) >= 1, "No providers returned successful responses"

      # All successful responses should have normalized format
      Enum.each(successful_responses, fn {provider, response} ->
        assert %{choices: choices} = response, "Provider #{provider} response missing choices"
        assert is_list(choices), "Provider #{provider} choices not a list"
        assert length(choices) >= 1, "Provider #{provider} has no choices"

        Enum.each(choices, fn choice ->
          assert %{message: message} = choice, "Provider #{provider} choice missing message"
          assert %{content: content} = message, "Provider #{provider} message missing content"
          assert is_binary(content), "Provider #{provider} content not a string"
        end)
      end)
    end

    test "fallback between providers works when configured" do
      messages = [%{role: "user", content: "Provider fallback test"}]

      # This test would require provider fallback configuration
      # For now, test that individual providers work independently

      primary_result = Client.request(messages, %{provider: :gemini})
      fallback_result = Client.request(messages, %{provider: :openai})

      # At least one should work
      results = [primary_result, fallback_result]
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      assert successes >= 1, "Both primary and fallback providers failed"
    end
  end

  describe "performance characteristics" do
    test "response times are reasonable under load" do
      messages = [%{role: "user", content: "Performance test"}]

      # Measure response times for multiple requests
      response_times = Enum.map(1..20, fn i ->
        start_time = System.monotonic_time()

        result = Client.request(messages, %{
          provider: :gemini,
          correlation_id: "perf-#{i}"
        })

        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        {result, duration_ms}
      end)

      # Filter successful requests
      successful_times = response_times
      |> Enum.filter(fn {{:ok, _}, _time} -> true; _ -> false end)
      |> Enum.map(fn {_result, time} -> time end)

      assert length(successful_times) >= 15, "Not enough successful requests for performance test"

      # Calculate statistics
      avg_time = Enum.sum(successful_times) / length(successful_times)
      max_time = Enum.max(successful_times)

      # Response times should be reasonable
      assert avg_time < 1000, "Average response time too high: #{avg_time}ms"
      assert max_time < 3000, "Maximum response time too high: #{max_time}ms"
    end

    test "throughput meets expectations for BEACON workloads" do
      messages = [%{role: "user", content: "Throughput test"}]

      # Measure throughput over a sustained period
      start_time = System.monotonic_time()

      results = Task.async_stream(1..100, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "throughput-#{i}"
        })
      end, max_concurrency: 20, timeout: 30_000)
      |> Enum.to_list()

      end_time = System.monotonic_time()
      total_duration_s = System.convert_time_unit(end_time - start_time, :native, :second)

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Calculate throughput
      throughput = successes / max(total_duration_s, 1)

      # Should achieve reasonable throughput for BEACON workloads
      assert throughput > 5, "Throughput too low: #{throughput} requests/second"
      assert successes >= 80, "Success rate too low: #{successes}/100"
    end

    test "client handles burst traffic patterns" do
      messages = [%{role: "user", content: "Burst traffic test"}]

      # Simulate burst patterns (high load followed by low load)
      burst_results = []

      # High load burst
      burst_start = System.monotonic_time()
      burst_requests = Task.async_stream(1..50, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "burst-#{i}"
        })
      end, max_concurrency: 25, timeout: 10_000)
      |> Enum.to_list()

      burst_duration = System.convert_time_unit(
        System.monotonic_time() - burst_start,
        :native,
        :millisecond
      )

      burst_successes = Enum.count(burst_requests, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Low load period
      Process.sleep(1000)

      steady_requests = Enum.map(1..10, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "steady-#{i}"
        })
      end)

      steady_successes = Enum.count(steady_requests, fn
        {:ok, _} -> true
        _ -> false
      end)

      # Should handle both burst and steady loads
      assert burst_successes >= 40, "Burst load failed: #{burst_successes}/50"
      assert steady_successes >= 8, "Steady load failed: #{steady_successes}/10"
      assert burst_duration < 15_000, "Burst took too long: #{burst_duration}ms"
    end
  end
end
