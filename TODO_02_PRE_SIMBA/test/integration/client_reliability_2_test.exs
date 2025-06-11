defmodule DSPEx.Integration.ClientReliabilityTest do
  @moduledoc """
  Integration tests for DSPEx client reliability under load.

  CRITICAL: SIMBA will make 100+ concurrent requests during optimization.
  This test validates that the client architecture can handle SIMBA's
  concurrent load patterns without failures or memory leaks.
  """
  use ExUnit.Case, async: false

  alias DSPEx.{Client, ClientManager}

  @moduletag :integration_2

  setup_all do
    # Set test mode to allow controlled testing without requiring API keys
    original_mode = DSPEx.TestModeConfig.get_test_mode()
    DSPEx.TestModeConfig.set_test_mode(:fallback)

    on_exit(fn ->
      DSPEx.TestModeConfig.set_test_mode(original_mode)
    end)

    :ok
  end

  describe "concurrent request handling - SIMBA usage pattern" do
    test "handles 100+ concurrent requests without failures" do
      # This simulates SIMBA's bootstrap generation phase
      messages = [%{role: "user", content: "Generate bootstrap demonstration"}]

      # SIMBA makes many concurrent teacher requests during bootstrap
      concurrent_count = 100

      results = Task.async_stream(1..concurrent_count, fn i ->
        correlation_id = "simba-bootstrap-#{i}"

        Client.request(messages, %{
          provider: :gemini,
          correlation_id: correlation_id,
          temperature: 0.7
        })
      end, max_concurrency: 50, timeout: 30_000)
      |> Enum.to_list()

      # Count successful requests
      successes = Enum.count(results, fn
        {:ok, {:ok, _response}} -> true
        _ -> false
      end)

      # SIMBA needs high reliability - should succeed most of the time
      success_rate = successes / concurrent_count
      assert success_rate >= 0.9, "Success rate too low: #{success_rate * 100}%"

      IO.puts("✅ Concurrent reliability test: #{successes}/#{concurrent_count} succeeded (#{Float.round(success_rate * 100, 1)}%)")
    end

    test "rapid provider switching under concurrent load" do
      # SIMBA switches between providers for teacher/student programs
      messages = [%{role: "user", content: "Provider switching test"}]
      providers = [:openai, :gemini]

      results = Task.async_stream(1..50, fn i ->
        provider = Enum.at(providers, rem(i, length(providers)))
        correlation_id = "provider-switch-#{i}"

        Client.request(messages, %{
          provider: provider,
          correlation_id: correlation_id
        })
      end, max_concurrency: 25, timeout: 30_000)
      |> Enum.to_list()

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Should handle rapid provider switching
      assert successes >= 45, "Provider switching failed: #{successes}/50"
    end

    test "correlation_id propagation under load" do
      # SIMBA heavily uses correlation IDs for tracking optimization progress
      messages = [%{role: "user", content: "Correlation tracking test"}]

      # Use unique correlation IDs to verify tracking
      correlation_ids = Enum.map(1..20, fn i ->
        "simba-optimization-#{System.unique_integer()}-#{i}"
      end)

      results = Task.async_stream(correlation_ids, fn correlation_id ->
        result = Client.request(messages, %{
          provider: :gemini,
          correlation_id: correlation_id
        })

        {correlation_id, result}
      end, max_concurrency: 10, timeout: 30_000)
      |> Enum.to_list()

      # All should succeed and maintain correlation
      successes = Enum.count(results, fn
        {:ok, {_corr_id, {:ok, _response}}} -> true
        _ -> false
      end)

      assert successes >= 18, "Correlation tracking failed: #{successes}/20"
    end

    test "memory stability during sustained concurrent load" do
      # SIMBA runs optimization for extended periods
      messages = [%{role: "user", content: "Memory stability test"}]

      initial_memory = :erlang.memory(:total)

      # Run multiple rounds of concurrent requests
      for round <- 1..5 do
        Task.async_stream(1..20, fn i ->
          correlation_id = "memory-test-#{round}-#{i}"

          Client.request(messages, %{
            provider: :gemini,
            correlation_id: correlation_id
          })
        end, max_concurrency: 10, timeout: 30_000)
        |> Enum.to_list()

        # Force garbage collection between rounds
        :erlang.garbage_collect()
      end

      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      memory_growth_mb = memory_growth / (1024 * 1024)

      # Memory growth should be minimal
      assert memory_growth_mb < 20, "Excessive memory growth: #{memory_growth_mb}MB"

      IO.puts("📊 Memory stability: #{Float.round(memory_growth_mb, 2)}MB growth over sustained load")
    end
  end

  describe "error recovery and resilience" do
    test "recovers gracefully from temporary failures" do
      # SIMBA needs robust error recovery during long optimizations
      messages = [%{role: "user", content: "Error recovery test"}]

      # Mix of requests that might fail and succeed
      results = Task.async_stream(1..30, fn i ->
        correlation_id = "error-recovery-#{i}"

        # Some requests with potentially problematic configurations
        opts = case rem(i, 3) do
          0 -> %{provider: :gemini, correlation_id: correlation_id}
          1 -> %{provider: :openai, correlation_id: correlation_id, temperature: 2.0}  # High temp
          2 -> %{provider: :gemini, correlation_id: correlation_id, max_tokens: 1}      # Low tokens
        end

        Client.request(messages, opts)
      end, max_concurrency: 15, timeout: 30_000)
      |> Enum.to_list()

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Should have reasonable success rate even with problematic configs
      success_rate = successes / 30
      assert success_rate >= 0.7, "Error recovery insufficient: #{success_rate * 100}%"
    end

    test "handles provider failures without cascading" do
      # Test that failure of one provider doesn't affect others
      messages = [%{role: "user", content: "Provider isolation test"}]

      # Try requests to different providers simultaneously
      provider_tests = [
        {:gemini, "provider-isolation-gemini"},
        {:openai, "provider-isolation-openai"},
        {:gemini, "provider-isolation-gemini-2"},  # Multiple of same provider
      ]

      results = Task.async_stream(provider_tests, fn {provider, correlation_id} ->
        Client.request(messages, %{
          provider: provider,
          correlation_id: correlation_id
        })
      end, max_concurrency: 3, timeout: 30_000)
      |> Enum.to_list()

      # At least some providers should work
      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes >= 2, "Provider isolation failed: #{successes}/3"
    end

    test "timeout handling under concurrent load" do
      # SIMBA needs predictable timeout behavior
      messages = [%{role: "user", content: "Timeout test with longer content to potentially trigger timeouts in some scenarios"}]

      # Use very short timeout to test timeout handling
      short_timeout = 100  # 100ms

      results = Task.async_stream(1..10, fn i ->
        correlation_id = "timeout-test-#{i}"

        Client.request(messages, %{
          provider: :gemini,
          correlation_id: correlation_id,
          timeout: short_timeout
        })
      end, max_concurrency: 5, timeout: 5_000)
      |> Enum.to_list()

      # Some might timeout, but should handle gracefully
      completed = Enum.count(results, fn
        {:ok, _} -> true  # Either success or error, but completed
        {:exit, _} -> false  # Task timeout
      end)

      # Most should complete (either success or graceful failure)
      assert completed >= 8, "Timeout handling failed: #{completed}/10 completed"
    end
  end

  describe "managed client architecture" do
    test "ClientManager handles concurrent clients" do
      # SIMBA might use managed clients for better resource control

      # Start multiple managed clients
      {:ok, client1} = ClientManager.start_link(:gemini)
      {:ok, client2} = ClientManager.start_link(:openai)

      messages = [%{role: "user", content: "Managed client test"}]

      # Make concurrent requests through managed clients
      results = Task.async_stream([client1, client2, client1, client2], fn client ->
        ClientManager.request(client, messages, %{
          correlation_id: "managed-#{inspect(client)}"
        })
      end, max_concurrency: 4, timeout: 30_000)
      |> Enum.to_list()

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes >= 3, "Managed client concurrency failed: #{successes}/4"

      # Clean up
      ClientManager.shutdown(client1)
      ClientManager.shutdown(client2)
    end

    test "managed client statistics tracking" do
      # SIMBA uses statistics for optimization decisions
      {:ok, client} = ClientManager.start_link(:gemini)

      messages = [%{role: "user", content: "Statistics test"}]

      # Make several requests
      for i <- 1..5 do
        ClientManager.request(client, messages, %{
          correlation_id: "stats-test-#{i}"
        })
      end

      # Check statistics
      {:ok, stats} = ClientManager.get_stats(client)

      assert stats.stats.requests_made >= 5
      assert is_number(stats.stats.successful_requests)
      assert is_number(stats.stats.failed_requests)

      ClientManager.shutdown(client)
    end

    test "managed client recovery from failures" do
      {:ok, client} = ClientManager.start_link(:gemini)

      messages = [%{role: "user", content: "Recovery test"}]

      # Make requests that might fail
      results = for i <- 1..10 do
        ClientManager.request(client, messages, %{
          correlation_id: "recovery-#{i}",
          # Some with problematic parameters
          temperature: if(rem(i, 3) == 0, do: -1.0, else: 0.7)
        })
      end

      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      # Should handle problematic requests gracefully
      assert successes >= 7, "Managed client recovery failed: #{successes}/10"

      ClientManager.shutdown(client)
    end
  end

  describe "performance characteristics under load" do
    test "request throughput meets SIMBA requirements" do
      # SIMBA needs sufficient throughput for optimization efficiency
      messages = [%{role: "user", content: "Throughput test"}]

      request_count = 50
      start_time = System.monotonic_time()

      results = Task.async_stream(1..request_count, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "throughput-#{i}"
        })
      end, max_concurrency: 25, timeout: 30_000)
      |> Enum.to_list()

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Calculate throughput
      throughput = successes / (duration_ms / 1000)  # requests per second

      # SIMBA needs reasonable throughput for optimization efficiency
      assert throughput >= 5.0, "Throughput too low: #{Float.round(throughput, 2)} req/sec"

      IO.puts("⚡ Throughput test: #{Float.round(throughput, 2)} req/sec (#{successes}/#{request_count} succeeded)")
    end

    test "latency distribution under concurrent load" do
      # SIMBA optimization needs predictable latency
      messages = [%{role: "user", content: "Latency test"}]

      latencies = Task.async_stream(1..20, fn i ->
        start_time = System.monotonic_time()

        result = Client.request(messages, %{
          provider: :gemini,
          correlation_id: "latency-#{i}"
        })

        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        {result, duration_ms}
      end, max_concurrency: 10, timeout: 30_000)
      |> Enum.to_list()
      |> Enum.map(fn {:ok, {_result, latency}} -> latency end)

      # Calculate latency statistics
      avg_latency = Enum.sum(latencies) / length(latencies)
      max_latency = Enum.max(latencies)
      min_latency = Enum.min(latencies)

      # Latency should be reasonable for SIMBA optimization
      assert avg_latency < 5000, "Average latency too high: #{avg_latency}ms"
      assert max_latency < 10000, "Max latency too high: #{max_latency}ms"

      IO.puts("🕒 Latency stats: avg=#{Float.round(avg_latency, 1)}ms, min=#{min_latency}ms, max=#{max_latency}ms")
    end

    test "resource usage remains stable under extended load" do
      # SIMBA runs optimizations for extended periods
      messages = [%{role: "user", content: "Extended load test"}]

      initial_process_count = length(Process.list())
      initial_memory = :erlang.memory(:total)

      # Run extended load test
      for round <- 1..10 do
        Task.async_stream(1..10, fn i ->
          Client.request(messages, %{
            provider: :gemini,
            correlation_id: "extended-#{round}-#{i}"
          })
        end, max_concurrency: 5, timeout: 30_000)
        |> Enum.to_list()

        # Brief pause between rounds
        Process.sleep(100)
      end

      # Force cleanup
      :erlang.garbage_collect()
      Process.sleep(1000)

      final_process_count = length(Process.list())
      final_memory = :erlang.memory(:total)

      process_growth = final_process_count - initial_process_count
      memory_growth_mb = (final_memory - initial_memory) / (1024 * 1024)

      # Resource growth should be minimal
      assert process_growth < 50, "Too many processes created: #{process_growth}"
      assert memory_growth_mb < 30, "Excessive memory growth: #{memory_growth_mb}MB"

      IO.puts("📈 Resource usage: +#{process_growth} processes, +#{Float.round(memory_growth_mb, 2)}MB memory")
    end
  end

  describe "edge cases and stress testing" do
    test "handles malformed requests gracefully" do
      # SIMBA might generate edge case requests during optimization

      malformed_requests = [
        # Empty messages
        {[], %{provider: :gemini}},
        # Invalid message format
        {[%{invalid: "format"}], %{provider: :gemini}},
        # Very long content
        {[%{role: "user", content: String.duplicate("test ", 1000)}], %{provider: :gemini}},
        # Invalid options
        {[%{role: "user", content: "test"}], %{provider: :nonexistent}},
      ]

      results = Task.async_stream(malformed_requests, fn {messages, opts} ->
        Client.request(messages, opts)
      end, max_concurrency: 4, timeout: 30_000)
      |> Enum.to_list()

      # Should handle all gracefully (either success or proper error)
      completed = Enum.count(results, fn
        {:ok, _} -> true  # Either success or error response
        {:exit, _} -> false  # Task crash
      end)

      assert completed == length(malformed_requests), "Malformed request handling failed"
    end

    test "stress test with burst traffic" do
      # SIMBA might create burst traffic during certain optimization phases
      messages = [%{role: "user", content: "Burst traffic test"}]

      # Create sudden burst of requests
      burst_size = 100

      start_time = System.monotonic_time()

      results = Task.async_stream(1..burst_size, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "burst-#{i}"
        })
      end, max_concurrency: burst_size, timeout: 30_000)  # High concurrency
      |> Enum.to_list()

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      success_rate = successes / burst_size

      # Should handle burst traffic reasonably well
      assert success_rate >= 0.7, "Burst traffic handling failed: #{success_rate * 100}%"
      assert duration_ms < 60_000, "Burst traffic took too long: #{duration_ms}ms"

      IO.puts("💥 Burst test: #{successes}/#{burst_size} in #{duration_ms}ms (#{Float.round(success_rate * 100, 1)}%)")
    end

    test "recovery after system stress" do
      # Verify system recovers after stress testing
      messages = [%{role: "user", content: "Recovery verification"}]

      # Normal requests after stress should work fine
      recovery_results = Task.async_stream(1..10, fn i ->
        Client.request(messages, %{
          provider: :gemini,
          correlation_id: "recovery-verify-#{i}"
        })
      end, max_concurrency: 5, timeout: 30_000)
      |> Enum.to_list()

      recovery_successes = Enum.count(recovery_results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Should have high success rate after recovery
      recovery_rate = recovery_successes / 10
      assert recovery_rate >= 0.9, "System did not recover properly: #{recovery_rate * 100}%"
    end
  end

  describe "SIMBA-specific usage patterns" do
    test "teacher-student concurrent pattern" do
      # SIMBA uses teacher and student programs concurrently
      teacher_messages = [%{role: "user", content: "Teacher: Generate demonstration"}]
      student_messages = [%{role: "user", content: "Student: Learn from demonstration"}]

      # Simulate teacher generating demonstrations while student processes them
      results = Task.async_stream(1..20, fn i ->
        if rem(i, 2) == 0 do
          # Teacher request
          Client.request(teacher_messages, %{
            provider: :openai,  # SIMBA might use different providers
            correlation_id: "teacher-#{i}"
          })
        else
          # Student request
          Client.request(student_messages, %{
            provider: :gemini,
            correlation_id: "student-#{i}"
          })
        end
      end, max_concurrency: 10, timeout: 30_000)
      |> Enum.to_list()

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes >= 18, "Teacher-student pattern failed: #{successes}/20"
    end

    test "optimization iteration pattern" do
      # SIMBA runs multiple optimization iterations
      messages = [%{role: "user", content: "Optimization iteration"}]

      # Simulate multiple optimization rounds
      iteration_results = for iteration <- 1..5 do
        round_results = Task.async_stream(1..10, fn candidate ->
          Client.request(messages, %{
            provider: :gemini,
            correlation_id: "iteration-#{iteration}-candidate-#{candidate}",
            temperature: 0.1 + (candidate * 0.1)  # Varying parameters
          })
        end, max_concurrency: 5, timeout: 30_000)
        |> Enum.to_list()

        successes = Enum.count(round_results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

        {iteration, successes}
      end

      # All iterations should be mostly successful
      total_successes = Enum.sum(Enum.map(iteration_results, fn {_iter, successes} -> successes end))
      total_attempts = 5 * 10  # 5 iterations × 10 candidates

      success_rate = total_successes / total_attempts
      assert success_rate >= 0.8, "Optimization iteration pattern failed: #{success_rate * 100}%"

      IO.puts("🔄 Optimization iterations: #{total_successes}/#{total_attempts} (#{Float.round(success_rate * 100, 1)}%)")
    end
  end
end
