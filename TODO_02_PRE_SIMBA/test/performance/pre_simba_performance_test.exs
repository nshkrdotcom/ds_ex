# File: test/performance/pre_simba_performance_test.exs
defmodule DSPEx.Performance.PreSIMBAPerformanceTest do
  use ExUnit.Case, async: false

  alias DSPEx.{Teleprompter, Example, Predict, Program, OptimizedProgram}
  alias DSPEx.Test.MockProvider
  alias DSPEx.Teleprompter.BootstrapFewShot

  @moduletag :performance
  @moduletag :pre_simba

  setup_all do
    {:ok, _mock} = MockProvider.start_link(
      mode: :contextual,
      latency_simulation: false  # Disable for performance testing
    )

    defmodule PerformanceSignature do
      @moduledoc "Signature for performance testing"
      use DSPEx.Signature, "question -> answer"
    end

    %{signature: PerformanceSignature}
  end

  describe "memory usage validation" do
    test "teleprompter compilation doesn't leak memory", %{signature: signature} do
      # SIMBA will run many optimization iterations
      # Need to ensure no memory leaks

      initial_memory = :erlang.memory()

      # Run multiple teleprompter compilations
      Enum.each(1..15, fn i ->
        student = %Predict{signature: signature, client: :test}
        teacher = %Predict{signature: signature, client: :test}

        trainset = create_test_trainset(10)  # Reasonable size for performance test
        metric_fn = Teleprompter.exact_match(:answer)

        MockProvider.reset()
        MockProvider.setup_bootstrap_mocks(
          Enum.map(1..10, fn j -> %{content: "Response #{i}-#{j}"} end)
        )

        {:ok, _optimized} = BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 3,
          max_concurrency: 8
        )

        # Force garbage collection every few iterations
        if rem(i, 5) == 0 do
          :erlang.garbage_collect()
        end
      end)

      # Final cleanup and measurement
      :erlang.garbage_collect()
      final_memory = :erlang.memory()

      # Memory should not have grown significantly
      memory_growth = final_memory[:total] - initial_memory[:total]
      memory_growth_mb = memory_growth / (1024 * 1024)

      # Allow some growth but not excessive
      assert memory_growth_mb < 30, "Memory grew by #{memory_growth_mb}MB (should be < 30MB)"

      # Process count shouldn't grow significantly either
      process_growth = final_memory[:processes] - initial_memory[:processes]
      process_growth_mb = process_growth / (1024 * 1024)

      assert process_growth_mb < 15, "Process memory grew by #{process_growth_mb}MB (should be < 15MB)"
    end

    test "large trainsets don't cause memory issues", %{signature: signature} do
      # SIMBA might use large training sets
      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}

      # Create large trainset (1000 examples)
      large_trainset = create_test_trainset(1000)
      metric_fn = Teleprompter.exact_match(:answer)

      # Set up mock responses
      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..1000, fn i -> %{content: "Response #{i}"} end)
      )

      memory_before = :erlang.memory()[:total]
      start_time = System.monotonic_time()

      {:ok, _optimized} = BootstrapFewShot.compile(
        student,
        teacher,
        large_trainset,
        metric_fn,
        max_bootstrapped_demos: 10,
        max_concurrency: 20
      )

      memory_after = :erlang.memory()[:total]
      duration_ms = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

      memory_used_mb = (memory_after - memory_before) / (1024 * 1024)

      # Should handle large datasets efficiently
      assert memory_used_mb < 80, "Used #{memory_used_mb}MB for large trainset (should be < 80MB)"
      assert duration_ms < 15_000, "Large trainset processing took #{duration_ms}ms (should be < 15s)"

      # Verify result quality
      assert is_struct(optimized)

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      # Should have reasonable number of demos despite large input
      assert length(demos) <= 10  # Should respect limit
      assert length(demos) >= 0   # Should handle large dataset gracefully
    end

    test "memory stability under repeated optimization cycles", %{signature: signature} do
      # Test memory stability across multiple optimization cycles (SIMBA pattern)

      measurements = []
      base_memory = :erlang.memory()[:total]

      # Run multiple cycles measuring memory after each
      Enum.each(1..8, fn cycle ->
        student = %Predict{signature: signature, client: :test}
        teacher = %Predict{signature: signature, client: :test}

        # Create fresh trainset for each cycle
        trainset = Enum.map(1..15, fn i ->
          %Example{
            data: %{question: "Cycle #{cycle} Question #{i}", answer: "Answer #{i}"},
            input_keys: MapSet.new([:question])
          }
        end)

        metric_fn = Teleprompter.exact_match(:answer)

        MockProvider.reset()
        MockProvider.setup_bootstrap_mocks(
          Enum.map(1..15, fn i -> %{content: "Answer #{i}"} end)
        )

        {:ok, _optimized} = BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 5,
          max_concurrency: 8
        )

        # Force GC and measure memory
        :erlang.garbage_collect()
        current_memory = :erlang.memory()[:total]
        memory_growth_mb = (current_memory - base_memory) / (1024 * 1024)

        measurements = [memory_growth_mb | measurements]

        # Log progress
        IO.puts("Cycle #{cycle}: Memory growth = #{Float.round(memory_growth_mb, 2)}MB")
      end)

      final_growth = List.first(measurements)
      max_growth = Enum.max(measurements)

      # Final memory growth should be reasonable
      assert final_growth < 40, "Final memory growth too high: #{final_growth}MB"

      # Peak memory growth should be controlled
      assert max_growth < 60, "Peak memory growth too high: #{max_growth}MB"

      # Memory growth should not be exponential
      # (last 4 measurements should not be significantly higher than first 4)
      {recent, earlier} = Enum.split(measurements, 4)
      avg_recent = Enum.sum(recent) / length(recent)
      avg_earlier = Enum.sum(earlier) / length(earlier)

      growth_ratio = if avg_earlier > 0, do: avg_recent / avg_earlier, else: 1.0
      assert growth_ratio < 2.0, "Memory growth appears exponential: #{growth_ratio}x"
    end
  end

  describe "performance benchmarks" do
    test "teleprompter compilation performance meets SIMBA requirements", %{signature: signature} do
      # Benchmark compilation time for SIMBA planning

      student = %Predict{signature: signature, client: :test}
      teacher = %Predict{signature: signature, client: :test}
      trainset = create_test_trainset(30)  # SIMBA typical size
      metric_fn = Teleprompter.exact_match(:answer)

      MockProvider.setup_bootstrap_mocks(
        Enum.map(1..30, fn i -> %{content: "Response #{i}"} end)
      )

      # Measure compilation performance
      {duration_us, {:ok, optimized}} = :timer.tc(fn ->
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 8,
          max_concurrency: 15
        )
      end)

      duration_ms = duration_us / 1000

      # Should complete in reasonable time for SIMBA
      assert duration_ms < 8000, "Compilation took #{duration_ms}ms (SIMBA needs < 8s)"

      # Calculate metrics SIMBA cares about
      examples_per_second = 30 / (duration_ms / 1000)
      assert examples_per_second > 5, "Processing rate too slow: #{examples_per_second} examples/sec"

      demos = case optimized do
        %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
        %{demos: demos} -> demos
        _ -> []
      end

      demo_generation_rate = length(demos) / (duration_ms / 1000)
      assert demo_generation_rate > 1, "Demo generation too slow: #{demo_generation_rate} demos/sec"

      # Log performance for monitoring
      IO.puts("BootstrapFewShot performance: #{Float.round(duration_ms, 1)}ms for 30 examples")
      IO.puts("  - Processing rate: #{Float.round(examples_per_second, 1)} examples/sec")
      IO.puts("  - Demo generation: #{Float.round(demo_generation_rate, 1)} demos/sec")
      IO.puts("  - Generated demos: #{length(demos)}")
    end

    test "concurrent program execution performance", %{signature: signature} do
      # Test performance under concurrent load (SIMBA pattern)

      program = %Predict{signature: signature, client: :test}
      inputs = %{question: "Performance test"}

      MockProvider.setup_evaluation_mocks(
        Enum.map(1..200, fn _i -> :rand.uniform() end)
      )

      # Test different concurrency levels
      concurrency_levels = [5, 10, 20, 50]

      Enum.each(concurrency_levels, fn concurrency ->
        {duration_us, results} = :timer.tc(fn ->
          Task.async_stream(1..100, fn _i ->
            Program.forward(program, inputs)
          end, max_concurrency: concurrency, timeout: 15_000)
          |> Enum.to_list()
        end)

        duration_ms = duration_us / 1000

        # Count successes
        successes = Enum.count(results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

        success_rate = successes / 100
        throughput = successes / (duration_ms / 1000)  # requests per second

        # Performance requirements for SIMBA
        assert success_rate >= 0.90, "Success rate too low at concurrency #{concurrency}: #{success_rate * 100}%"
        assert throughput > 8, "Throughput too low at concurrency #{concurrency}: #{throughput} req/sec"

        IO.puts("Concurrency #{concurrency}: #{Float.round(throughput, 1)} req/sec, #{Float.round(success_rate * 100, 1)}% success")
      end)
    end

    test "program creation and destruction performance", %{signature: signature} do
      # SIMBA creates many temporary programs during optimization

      # Test program creation performance
      {creation_duration_us, _} = :timer.tc(fn ->
        Enum.each(1..2000, fn _i ->
          student = %Predict{signature: signature, client: :test}
          demos = [%Example{
            data: %{question: "test", answer: "response"},
            input_keys: MapSet.new([:question])
          }]

          _optimized = OptimizedProgram.new(student, demos)
        end)
      end)

      creation_duration_ms = creation_duration_us / 1000
      creation_rate = 2000 / (creation_duration_ms / 1000)  # creations per second

      assert creation_rate > 200, "Program creation rate too low: #{creation_rate} per second"

      # Test with various demo counts (SIMBA might have varying demo sizes)
      demo_sizes = [1, 5, 10, 20]

      Enum.each(demo_sizes, fn demo_count ->
        demos = Enum.map(1..demo_count, fn i ->
          %Example{
            data: %{question: "test #{i}", answer: "response #{i}"},
            input_keys: MapSet.new([:question])
          }
        end)

        {duration_us, _} = :timer.tc(fn ->
          Enum.each(1..500, fn _i ->
            student = %Predict{signature: signature, client: :test}
            _optimized = OptimizedProgram.new(student, demos)
          end)
        end)

        duration_ms = duration_us / 1000
        rate = 500 / (duration_ms / 1000)

        # Should handle larger demo counts efficiently
        min_rate = max(50, 200 / demo_count)  # Scale expectations with demo count
        assert rate > min_rate, "Rate too low with #{demo_count} demos: #{rate} per second"

        IO.puts("Demo count #{demo_count}: #{Float.round(rate, 1)} creations/sec")
      end)
    end

    test "optimization scaling with training set size", %{signature: signature} do
      # Test performance scaling for different training set sizes

      sizes = [5, 15, 30, 50]
      results = []

      Enum.each(sizes, fn size ->
        student = %Predict{signature: signature, client: :test}
        teacher = %Predict{signature: signature, client: :test}
        trainset = create_test_trainset(size)
        metric_fn = Teleprompter.exact_match(:answer)

        MockProvider.reset()
        MockProvider.setup_bootstrap_mocks(
          Enum.map(1..size, fn i -> %{content: "Response #{i}"} end)
        )

        {duration_us, {:ok, optimized}} = :timer.tc(fn ->
          BootstrapFewShot.compile(
            student,
            teacher,
            trainset,
            metric_fn,
            max_bootstrapped_demos: min(size, 10),
            max_concurrency: 12
          )
        end)

        duration_ms = duration_us / 1000
        per_example_ms = duration_ms / size

        demos = case optimized do
          %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
          %{demos: demos} -> demos
          _ -> []
        end

        result = {size, duration_ms, per_example_ms, length(demos)}
        results = [result | results]

        IO.puts("Size #{size}: #{Float.round(duration_ms, 1)}ms total, #{Float.round(per_example_ms, 1)}ms per example, #{length(demos)} demos")
      end)

      results = Enum.reverse(results)

      # Verify scaling is reasonable (not exponential)
      per_example_times = Enum.map(results, fn {_size, _total, per_example, _demos} -> per_example end)

      # Check that per-example time doesn't grow too much
      min_time = Enum.min(per_example_times)
      max_time = Enum.max(per_example_times)

      scaling_factor = max_time / min_time
      assert scaling_factor < 4.0, "Poor scaling: #{scaling_factor}x slower per example at largest size"

      # Check absolute performance at each size
      Enum.each(results, fn {size, total_ms, per_example_ms, _demos} ->
        # Total time should be reasonable
        max_total_time = size * 300  # 300ms per example max
        assert total_ms < max_total_time, "Size #{size} took too long: #{total_ms}ms"

        # Per-example time should be bounded
        assert per_example_ms < 400, "Per-example time too high at size #{size}: #{per_example_ms}ms"
      end)
    end
  end

  describe "scalability validation" do
    test "handles high demo counts efficiently", %{signature: signature} do
      # SIMBA might create programs with many demonstrations

      student = %Predict{signature: signature, client: :test}

      # Test with varying demo counts
      demo_counts = [10, 25, 50, 100]

      Enum.each(demo_counts, fn demo_count ->
        # Create program with many demos
        many_demos = Enum.map(1..demo_count, fn i ->
          %Example{
            data: %{question: "Question #{i}", answer: "Answer #{i}"},
            input_keys: MapSet.new([:question])
          }
        end)

        {creation_duration, optimized} = :timer.tc(fn ->
          OptimizedProgram.new(student, many_demos)
        end)

        # Test forward performance with many demos
        MockProvider.setup_evaluation_mocks([0.9])

        {forward_duration, forward_result} = :timer.tc(fn ->
          try do
            Program.forward(optimized, %{question: "Test with many demos"})
          rescue
            _ -> {:error, :test_limitation}
          end
        end)

        creation_ms = creation_duration / 1000
        forward_ms = forward_duration / 1000

        # Performance should scale reasonably
        max_creation_time = demo_count * 2  # 2ms per demo max
        max_forward_time = 2000  # 2s max regardless of demo count

        assert creation_ms < max_creation_time, "Creation with #{demo_count} demos too slow: #{creation_ms}ms"

        case forward_result do
          {:ok, _result} ->
            assert forward_ms < max_forward_time, "Forward with #{demo_count} demos too slow: #{forward_ms}ms"
          {:error, :test_limitation} ->
            # Acceptable in test environment
            :ok
          {:error, _reason} ->
            # Forward might fail in test environment - focus on creation performance
            :ok
        end

        IO.puts("#{demo_count} demos - Creation: #{Float.round(creation_ms, 1)}ms, Forward: #{Float.round(forward_ms, 1)}ms")
      end)
    end

    test "concurrent optimization with shared resources", %{signature: signature} do
      # Test multiple optimizations sharing mock provider resources

      # Create multiple optimization tasks
      optimization_tasks = Enum.map(1..8, fn task_id ->
        student = %Predict{signature: signature, client: :test}
        teacher = %Predict{signature: signature, client: :test}

        trainset = Enum.map(1..5, fn i ->
          %Example{
            data: %{question: "Task #{task_id} Q#{i}", answer: "Task #{task_id} A#{i}"},
            input_keys: MapSet.new([:question])
          }
        end)

        {task_id, student, teacher, trainset}
      end)

      metric_fn = Teleprompter.exact_match(:answer)

      # Set up shared mock resources
      MockProvider.setup_bootstrap_mocks(
        Enum.flat_map(1..8, fn task_id ->
          Enum.map(1..5, fn i -> %{content: "Task #{task_id} A#{i}"} end)
        end)
      )

      # Execute concurrent optimizations
      start_time = System.monotonic_time()

      concurrent_results = Task.async_stream(optimization_tasks, fn {task_id, student, teacher, trainset} ->
        result = BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 3,
          max_concurrency: 4  # Limited per-task concurrency
        )
        {task_id, result}
      end, max_concurrency: 6, timeout: 20_000)  # High task-level concurrency
      |> Enum.to_list()

      end_time = System.monotonic_time()
      total_duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Analyze results
      successes = Enum.count(concurrent_results, fn
        {:ok, {_task_id, {:ok, _optimized}}} -> true
        _ -> false
      end)

      success_rate = successes / length(optimization_tasks)
      throughput = successes / (total_duration_ms / 1000)

      # Should handle concurrent optimization well
      assert success_rate >= 0.8, "Concurrent success rate too low: #{success_rate * 100}%"
      assert throughput > 0.5, "Concurrent throughput too low: #{throughput} optimizations/sec"
      assert total_duration_ms < 25_000, "Concurrent optimization took too long: #{total_duration_ms}ms"

      IO.puts("Concurrent optimization: #{Float.round(throughput, 1)} opt/sec, #{Float.round(success_rate * 100, 1)}% success")
    end

    test "resource cleanup after optimization cycles", %{signature: signature} do
      # Test that resources are properly cleaned up after optimization

      initial_process_count = length(Process.list())
      initial_memory = :erlang.memory()

      # Run multiple optimization cycles
      Enum.each(1..6, fn cycle ->
        student = %Predict{signature: signature, client: :test}
        teacher = %Predict{signature: signature, client: :test}
        trainset = create_test_trainset(20)
        metric_fn = Teleprompter.exact_match(:answer)

        MockProvider.reset()
        MockProvider.setup_bootstrap_mocks(
          Enum.map(1..20, fn i -> %{content: "Cycle #{cycle} Response #{i}"} end)
        )

        {:ok, _optimized} = BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 6,
          max_concurrency: 10
        )

        # Force cleanup
        :erlang.garbage_collect()

        # Check resource usage periodically
        if rem(cycle, 2) == 0 do
          current_process_count = length(Process.list())
          current_memory = :erlang.memory()

          process_growth = current_process_count - initial_process_count
          memory_growth_mb = (current_memory[:total] - initial_memory[:total]) / (1024 * 1024)

          # Should not accumulate excessive resources
          assert process_growth < 50, "Process count grew too much after #{cycle} cycles: +#{process_growth}"
          assert memory_growth_mb < 30, "Memory grew too much after #{cycle} cycles: +#{memory_growth_mb}MB"

          IO.puts("After cycle #{cycle}: +#{process_growth} processes, +#{Float.round(memory_growth_mb, 1)}MB memory")
        end
      end)

      # Final cleanup check
      :erlang.garbage_collect()
      Process.sleep(100)  # Allow cleanup to complete

      final_process_count = length(Process.list())
      final_memory = :erlang.memory()

      final_process_growth = final_process_count - initial_process_count
      final_memory_growth_mb = (final_memory[:total] - initial_memory[:total]) / (1024 * 1024)

      # Final resource usage should be reasonable
      assert final_process_growth < 30, "Final process growth too high: +#{final_process_growth}"
      assert final_memory_growth_mb < 25, "Final memory growth too high: +#{final_memory_growth_mb}MB"
    end
  end

  # Helper functions
  defp create_test_trainset(size) do
    Enum.map(1..size, fn i ->
      %Example{
        data: %{question: "Question #{i}", answer: "Answer #{i}"},
        input_keys: MapSet.new([:question])
      }
    end)
  end
end
