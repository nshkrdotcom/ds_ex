# File: test/concurrent/stress_test.exs
defmodule DSPEx.Concurrent.StressTest do
  use ExUnit.Case, async: false

  alias DSPEx.{Client, Predict, Program, Example}
  alias DSPEx.Test.MockProvider
  alias DSPEx.Teleprompter.BootstrapFewShot

  @moduletag :stress
  @moduletag :concurrent
  @moduletag timeout: 300_000  # 5 minutes for stress tests

  setup_all do
    {:ok, _mock} = MockProvider.start_link(
      mode: :contextual,
      latency_simulation: false  # Disable for stress testing
    )

    defmodule StressTestSignature do
      use DSPEx.Signature, "question -> answer"
    end

    %{signature: StressTestSignature}
  end

  describe "high-volume concurrent program execution" do
    test "1000+ concurrent program executions", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}

      # Set up mock responses for high volume
      MockProvider.setup_evaluation_mocks(
        Enum.map(1..1000, fn _i -> :rand.uniform() end)
      )

      start_time = System.monotonic_time()

      # Execute 1000 concurrent requests
      results = Task.async_stream(1..1000, fn i ->
        inputs = %{question: "Stress test question #{i}"}
        Program.forward(program, inputs)
      end, max_concurrency: 100, timeout: 60_000)
      |> Enum.to_list()

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Count successes
      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Calculate throughput
      throughput = successes / (duration_ms / 1000)

      # Assertions
      assert successes >= 950, "Expected ≥950 successes, got #{successes}"
      assert throughput >= 10, "Throughput too low: #{throughput} req/sec"
      assert duration_ms < 120_000, "Execution too slow: #{duration_ms}ms"

      IO.puts("\n🚀 Stress Test Results:")
      IO.puts("   Successes: #{successes}/1000 (#{successes/10}%)")
      IO.puts("   Duration: #{duration_ms}ms")
      IO.puts("   Throughput: #{:erlang.float_to_binary(throughput, decimals: 2)} req/sec")
    end

    test "sustained load over extended period", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}

      # Run for 30 seconds with constant load
      test_duration_ms = 30_000
      requests_per_second = 20
      total_expected = div(test_duration_ms * requests_per_second, 1000)

      MockProvider.setup_evaluation_mocks(
        Enum.map(1..total_expected, fn _i -> 0.8 end)
      )

      start_time = System.monotonic_time()
      end_time = start_time + System.convert_time_unit(test_duration_ms, :millisecond, :native)

      # Generator process that creates requests at steady rate
      generator_pid = spawn_link(fn ->
        generate_steady_load(program, end_time, requests_per_second)
      end)

      # Wait for test completion
      ref = Process.monitor(generator_pid)
      receive do
        {:DOWN, ^ref, :process, ^generator_pid, :normal} -> :ok
        {:DOWN, ^ref, :process, ^generator_pid, reason} ->
          flunk("Generator failed: #{inspect(reason)}")
      after
        test_duration_ms + 5000 ->
          Process.exit(generator_pid, :kill)
          flunk("Sustained load test timed out")
      end

      # Check memory usage didn't grow excessively
      :erlang.garbage_collect()
      final_memory = :erlang.memory()[:total]
      memory_mb = final_memory / (1024 * 1024)

      assert memory_mb < 500, "Memory usage too high: #{memory_mb}MB"

      IO.puts("\n⏱️  Sustained Load Results:")
      IO.puts("   Duration: #{test_duration_ms}ms")
      IO.puts("   Target Rate: #{requests_per_second} req/sec")
      IO.puts("   Memory Usage: #{:erlang.float_to_binary(memory_mb, decimals: 1)}MB")
    end

    test "burst traffic handling", %{signature: signature} do
      program = %Predict{signature: signature, client: :test}

      # Simulate burst traffic: periods of high load followed by quiet
      burst_size = 200
      num_bursts = 5

      MockProvider.setup_evaluation_mocks(
        Enum.map(1..(burst_size * num_bursts), fn _i -> 0.9 end)
      )

      total_successes = 0

      for burst <- 1..num_bursts do
        IO.puts("Executing burst #{burst}/#{num_bursts}")

        # High-intensity burst
        burst_results = Task.async_stream(1..burst_size, fn i ->
          inputs = %{question: "Burst #{burst} request #{i}"}
          Program.forward(program, inputs)
        end, max_concurrency: 50, timeout: 30_000)
        |> Enum.to_list()

        burst_successes = Enum.count(burst_results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

        total_successes = total_successes + burst_successes

        # Brief pause between bursts
        Process.sleep(1000)
      end

      expected_total = burst_size * num_bursts
      success_rate = total_successes / expected_total

      assert success_rate >= 0.95, "Success rate too low: #{success_rate * 100}%"

      IO.puts("\n💥 Burst Traffic Results:")
      IO.puts("   Total Requests: #{expected_total}")
      IO.puts("   Successes: #{total_successes}")
      IO.puts("   Success Rate: #{:erlang.float_to_binary(success_rate * 100, decimals: 1)}%")
    end
  end

  describe "teleprompter optimization under stress" do
    test "concurrent teleprompter optimizations", %{signature: signature} do
      # Run multiple teleprompter optimizations concurrently
      num_optimizations = 10

      trainset = create_stress_trainset(20)
      metric_fn = fn _example, _prediction -> :rand.uniform() end

      # Set up enough mock responses for all optimizations
      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..(20 * num_optimizations), fn i ->
          %{content: "Response #{i}"}
        end)
      )

      start_time = System.monotonic_time()

      # Run concurrent optimizations
      results = Task.async_stream(1..num_optimizations, fn i ->
        student = %Predict{signature: signature, client: :"test_#{i}"}
        teacher = %Predict{signature: signature, client: :"teacher_#{i}"}

        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 5
        )
      end, max_concurrency: 5, timeout: 120_000)
      |> Enum.to_list()

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Count successful optimizations
      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes >= 8, "Expected ≥8 successful optimizations, got #{successes}"
      assert duration_ms < 180_000, "Concurrent optimizations too slow: #{duration_ms}ms"

      IO.puts("\n🧠 Concurrent Optimization Results:")
      IO.puts("   Successful: #{successes}/#{num_optimizations}")
      IO.puts("   Duration: #{duration_ms}ms")
      IO.puts("   Avg per optimization: #{div(duration_ms, num_optimizations)}ms")
    end

    test "optimization with large training sets", %{signature: signature} do
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}

      # Very large training set
      large_trainset = create_stress_trainset(500)
      metric_fn = fn _example, _prediction -> 0.8 end

      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..500, fn i -> %{content: "Large response #{i}"} end)
      )

      memory_before = :erlang.memory()[:total]
      start_time = System.monotonic_time()

      # Should handle large trainset efficiently
      result = BootstrapFewShot.compile(
        student,
        teacher,
        large_trainset,
        metric_fn,
        max_bootstrapped_demos: 10,
        max_concurrency: 20
      )

      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      :erlang.garbage_collect()
      memory_after = :erlang.memory()[:total]
      memory_growth_mb = (memory_after - memory_before) / (1024 * 1024)

      assert {:ok, _optimized} = result
      assert duration_ms < 300_000, "Large trainset optimization too slow: #{duration_ms}ms"
      assert memory_growth_mb < 200, "Memory growth too high: #{memory_growth_mb}MB"

      IO.puts("\n📊 Large Trainset Results:")
      IO.puts("   Trainset Size: 500 examples")
      IO.puts("   Duration: #{duration_ms}ms")
      IO.puts("   Memory Growth: #{:erlang.float_to_binary(memory_growth_mb, decimals: 1)}MB")
    end
  end

  describe "race condition resistance" do
    test "concurrent access to shared resources", %{signature: signature} do
      # Test concurrent access to ConfigManager, MockProvider, etc.

      # Concurrent config access
      config_tasks = Task.async_stream(1..100, fn _i ->
        DSPEx.Services.ConfigManager.get([:providers, :gemini])
      end, max_concurrency: 20)
      |> Enum.to_list()

      # All should succeed without race conditions
      config_successes = Enum.count(config_tasks, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert config_successes >= 95, "Config access race conditions detected"

      # Concurrent mock provider access
      mock_tasks = Task.async_stream(1..100, fn i ->
        MockProvider.setup_evaluation_mocks([0.5])
        Client.request([%{role: "user", content: "Race test #{i}"}], %{provider: :test})
      end, max_concurrency: 20)
      |> Enum.to_list()

      mock_successes = Enum.count(mock_tasks, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert mock_successes >= 95, "Mock provider race conditions detected"

      IO.puts("\n🏁 Race Condition Test Results:")
      IO.puts("   Config Access: #{config_successes}/100")
      IO.puts("   Mock Provider: #{mock_successes}/100")
    end

    test "program state isolation under concurrent load", %{signature: signature} do
      # Create programs with shared signature but isolated state
      programs = Enum.map(1..20, fn i ->
        %Predict{signature: signature, client: :"client_#{i}", demos: []}
      end)

      # Concurrent modifications should not interfere
      modification_tasks = Task.async_stream(programs, fn program ->
        # Simulate state modifications
        modified = %{program | demos: [create_test_example()]}

        # Use the modified program
        Program.forward(modified, %{question: "Isolation test"})
      end, max_concurrency: 10)
      |> Enum.to_list()

      successes = Enum.count(modification_tasks, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes >= 18, "Program state isolation failed: #{successes}/20"
    end
  end

  describe "resource exhaustion handling" do
    test "graceful degradation under memory pressure" do
      # Simulate memory pressure by creating large data structures
      initial_memory = :erlang.memory()[:total]

      # Create memory pressure
      large_data = Enum.map(1..1000, fn i ->
        %{
          id: i,
          data: String.duplicate("x", 1000),
          nested: %{
            more_data: Enum.map(1..100, fn j -> "item_#{j}" end)
          }
        }
      end)

      # Verify system still functions under memory pressure
      results = Task.async_stream(1..50, fn i ->
        # Keep reference to large_data to maintain memory pressure
        _ref = large_data

        Client.request([%{role: "user", content: "Memory pressure test #{i}"}],
                      %{provider: :test})
      end, max_concurrency: 10)
      |> Enum.to_list()

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      # Clean up
      large_data = nil
      :erlang.garbage_collect()

      final_memory = :erlang.memory()[:total]

      assert successes >= 45, "System failed under memory pressure: #{successes}/50"

      # Memory should be recoverable
      memory_recovery = (initial_memory - final_memory) / initial_memory
      assert memory_recovery > -0.5, "Memory not properly recovered"

      IO.puts("\n💾 Memory Pressure Results:")
      IO.puts("   Successes under pressure: #{successes}/50")
      IO.puts("   Memory recovery: #{:erlang.float_to_binary(memory_recovery * 100, decimals: 1)}%")
    end

    test "handling process limit stress" do
      # Test behavior when approaching BEAM process limits

      # Spawn many processes to simulate high process count
      process_pids = Enum.map(1..1000, fn i ->
        spawn(fn ->
          # Simulate work
          Process.sleep(i * 10)
          receive do
            :stop -> :ok
          after
            30_000 -> :ok
          end
        end)
      end)

      # Verify system still functions with many processes
      results = Task.async_stream(1..20, fn i ->
        Client.request([%{role: "user", content: "Process stress #{i}"}],
                      %{provider: :test})
      end, max_concurrency: 5, timeout: 10_000)
      |> Enum.to_list()

      # Clean up processes
      Enum.each(process_pids, fn pid ->
        if Process.alive?(pid) do
          send(pid, :stop)
        end
      end)

      successes = Enum.count(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

      assert successes >= 18, "System failed under process stress: #{successes}/20"

      IO.puts("\n⚡ Process Stress Results:")
      IO.puts("   Background processes: 1000")
      IO.puts("   Client successes: #{successes}/20")
    end
  end

  # Helper functions
  defp generate_steady_load(program, end_time, requests_per_second) do
    interval_ms = div(1000, requests_per_second)

    generate_steady_load_loop(program, end_time, interval_ms, 0)
  end

  defp generate_steady_load_loop(program, end_time, interval_ms, count) do
    current_time = System.monotonic_time()

    if current_time >= end_time do
      IO.puts("Generated #{count} requests total")
      exit(:normal)
    else
      # Generate request
      Task.start(fn ->
        inputs = %{question: "Sustained load #{count}"}
        Program.forward(program, inputs)
      end)

      # Wait for next interval
      Process.sleep(interval_ms)

      generate_steady_load_loop(program, end_time, interval_ms, count + 1)
    end
  end

  defp create_stress_trainset(size) do
    Enum.map(1..size, fn i ->
      %Example{
        data: %{
          question: "Stress test question #{i}",
          answer: "Answer #{i}"
        },
        input_keys: MapSet.new([:question])
      }
    end)
  end

  defp create_test_example() do
    %Example{
      data: %{question: "Test", answer: "Response"},
      input_keys: MapSet.new([:question])
    }
  end
end
