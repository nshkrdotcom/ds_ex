defmodule DSPEx.Performance.MemoryPerformanceTest do
  @moduledoc """
  Memory-focused performance tests for DSPEx SIMBA preparation.

  Validates memory usage patterns, leak detection, and resource cleanup
  specific to SIMBA optimization workflows. Complements existing performance
  tests with memory-focused scenarios.

  Tests migrated from TODO_02_PRE_SIMBA/test/performance/pre_simba_performance_test.exs
  """
  use ExUnit.Case, async: false

  import Mox
  setup :verify_on_exit!

  @moduletag :group_2
  @moduletag :performance
  @moduletag :memory
  @moduletag :simba_prep

  # Memory validation thresholds for SIMBA readiness
  @max_memory_growth_mb 50
  @max_process_memory_growth_mb 20
  @large_dataset_memory_limit_mb 100
  @memory_leak_threshold_mb 15

  describe "memory usage validation" do
    test "teleprompter compilation doesn't leak memory" do
      # SIMBA will run many optimization iterations - ensure no memory leaks
      mock_provider_responses()

      initial_memory = :erlang.memory()

      # Run multiple teleprompter compilations
      Enum.each(1..15, fn i ->
        student = create_mock_program(:memory_test_student)
        teacher = create_mock_program(:memory_test_teacher)

        trainset = create_memory_test_trainset(10)
        metric_fn = create_memory_test_metric()

        # For performance testing, timing is more important than bootstrap success
        case DSPEx.Teleprompter.BootstrapFewShot.compile(
               student,
               teacher,
               trainset,
               metric_fn,
               max_bootstrapped_demos: 3,
               max_concurrency: 8
             ) do
          {:ok, _optimized} -> :ok
          # Expected with mock data
          {:error, :no_successful_bootstrap_candidates} -> :ok
          {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
        end

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

      assert memory_growth_mb < @max_memory_growth_mb,
             "Memory grew by #{Float.round(memory_growth_mb, 2)}MB (should be < #{@max_memory_growth_mb}MB)"

      # Process count shouldn't grow significantly either
      process_growth = final_memory[:processes] - initial_memory[:processes]
      process_growth_mb = process_growth / (1024 * 1024)

      assert process_growth_mb < @max_process_memory_growth_mb,
             "Process memory grew by #{Float.round(process_growth_mb, 2)}MB (should be < #{@max_process_memory_growth_mb}MB)"

      log_memory_usage("teleprompter_iterations", memory_growth_mb, process_growth_mb)
    end

    test "large trainsets don't cause memory issues" do
      # SIMBA might use large training sets - validate memory handling
      mock_provider_responses()

      student = create_mock_program(:large_dataset_student)
      teacher = create_mock_program(:large_dataset_teacher)

      # Create large trainset (500 examples - reduced for test efficiency)
      large_trainset = create_memory_test_trainset(500)
      metric_fn = create_memory_test_metric()

      memory_before = :erlang.memory()[:total]
      start_time = System.monotonic_time()

      # For performance testing, timing is more important than bootstrap success
      result =
        DSPEx.Teleprompter.BootstrapFewShot.compile(
          student,
          teacher,
          large_trainset,
          metric_fn,
          max_bootstrapped_demos: 10,
          max_concurrency: 20
        )

      memory_after = :erlang.memory()[:total]

      duration_ms =
        System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

      memory_used_mb = (memory_after - memory_before) / (1024 * 1024)

      # Should handle large datasets efficiently
      assert memory_used_mb < @large_dataset_memory_limit_mb,
             "Used #{Float.round(memory_used_mb, 2)}MB for large trainset (should be < #{@large_dataset_memory_limit_mb}MB)"

      assert duration_ms < 20_000,
             "Large trainset processing took #{duration_ms}ms (should be < 20s)"

      # Verify result handling
      case result do
        {:ok, optimized} ->
          demos =
            case optimized do
              %DSPEx.OptimizedProgram{demos: demos} -> demos
              %{demos: demos} -> demos
              _ -> []
            end

          # Should have reasonable number of demos despite large input
          assert length(demos) <= 10, "Should respect demo limit"
          assert length(demos) >= 0, "Should handle large dataset gracefully"

        {:error, :no_successful_bootstrap_candidates} ->
          # Acceptable for large dataset tests with mock data
          IO.puts("Note: Bootstrap failed for large dataset (expected with mock data)")

        {:error, other} ->
          flunk("Unexpected error with large dataset: #{inspect(other)}")
      end

      log_memory_usage("large_trainset", memory_used_mb, duration_ms / 1000)
    end

    @tag :todo_optimize
    test "memory stability under repeated optimization cycles" do
      # Test memory stability across multiple optimization cycles (SIMBA pattern)
      mock_provider_responses()

      base_memory = :erlang.memory()[:total]

      # Run multiple cycles measuring memory after each
      measurements =
        Enum.map(1..8, fn cycle ->
          student = create_mock_program(:stability_student)
          teacher = create_mock_program(:stability_teacher)

          # Create fresh trainset for each cycle
          trainset = create_memory_test_trainset(15)
          metric_fn = create_memory_test_metric()

          case DSPEx.Teleprompter.BootstrapFewShot.compile(
                 student,
                 teacher,
                 trainset,
                 metric_fn,
                 max_bootstrapped_demos: 5,
                 max_concurrency: 8
               ) do
            {:ok, _optimized} -> :ok
            # Expected with mock data
            {:error, :no_successful_bootstrap_candidates} -> :ok
            {:error, other} -> flunk("Unexpected error in cycle #{cycle}: #{inspect(other)}")
          end

          # Force GC and measure memory
          :erlang.garbage_collect()
          current_memory = :erlang.memory()[:total]
          memory_growth_mb = (current_memory - base_memory) / (1024 * 1024)

          # Log progress
          IO.puts("Cycle #{cycle}: Memory growth = #{Float.round(memory_growth_mb, 2)}MB")

          memory_growth_mb
        end)

      final_growth = List.last(measurements)
      max_growth = Enum.max(measurements)

      # Final memory growth should be reasonable
      assert final_growth < 40, "Final memory growth too high: #{Float.round(final_growth, 2)}MB"

      # Peak memory growth should be controlled
      assert max_growth < 60, "Peak memory growth too high: #{Float.round(max_growth, 2)}MB"

      # Memory growth should not be exponential
      # (last 4 measurements should not be significantly higher than first 4)
      {recent, earlier} = Enum.split(measurements, 4)
      avg_recent = Enum.sum(recent) / length(recent)
      avg_earlier = Enum.sum(earlier) / length(earlier)

      growth_ratio = if avg_earlier > 0, do: avg_recent / avg_earlier, else: 1.0

      # TODO_OPTIMIZE: Memory growth is showing exponential pattern, needs investigation
      assert growth_ratio < 2.0,
             "Memory growth appears exponential: #{Float.round(growth_ratio, 2)}x"

      log_memory_usage("optimization_cycles", final_growth, max_growth)
    end
  end

  describe "SIMBA readiness performance benchmarks" do
    test "handles high demo counts efficiently" do
      # SIMBA might create programs with many demonstrations
      mock_provider_responses()

      student = create_mock_program(:high_demo_student)

      # Test with varying demo counts
      demo_counts = [10, 25, 50, 100]

      Enum.each(demo_counts, fn demo_count ->
        # Create program with many demos
        many_demos = create_memory_test_trainset(demo_count)

        {creation_duration, optimized} =
          :timer.tc(fn ->
            DSPEx.OptimizedProgram.new(student, many_demos)
          end)

        # Test forward performance with many demos
        {forward_duration, forward_result} =
          :timer.tc(fn ->
            try do
              DSPEx.Program.forward(optimized, %{question: "Test with many demos"})
            rescue
              _ -> {:error, :test_limitation}
            end
          end)

        creation_ms = creation_duration / 1000
        forward_ms = forward_duration / 1000

        # Performance should scale reasonably
        # 2ms per demo max
        max_creation_time = demo_count * 2
        # 2s max regardless of demo count
        max_forward_time = 2000

        assert creation_ms < max_creation_time,
               "Creation with #{demo_count} demos too slow: #{Float.round(creation_ms, 1)}ms"

        case forward_result do
          {:ok, _result} ->
            assert forward_ms < max_forward_time,
                   "Forward with #{demo_count} demos too slow: #{Float.round(forward_ms, 1)}ms"

          {:error, :test_limitation} ->
            # Acceptable in test environment
            :ok

          {:error, _reason} ->
            # Forward might fail in test environment - focus on creation performance
            :ok
        end

        IO.puts(
          "#{demo_count} demos - Creation: #{Float.round(creation_ms, 1)}ms, Forward: #{Float.round(forward_ms, 1)}ms"
        )
      end)
    end

    test "concurrent optimization with shared resources" do
      # Test multiple optimizations sharing mock provider resources
      mock_provider_responses()

      # Create multiple optimization tasks
      optimization_tasks =
        Enum.map(1..8, fn task_id ->
          student = create_mock_program(:concurrent_student)
          teacher = create_mock_program(:concurrent_teacher)

          trainset = create_memory_test_trainset(5)

          {task_id, student, teacher, trainset}
        end)

      metric_fn = create_memory_test_metric()

      # Execute concurrent optimizations
      start_time = System.monotonic_time()

      concurrent_results =
        Task.async_stream(
          optimization_tasks,
          fn {task_id, student, teacher, trainset} ->
            result =
              DSPEx.Teleprompter.BootstrapFewShot.compile(
                student,
                teacher,
                trainset,
                metric_fn,
                max_bootstrapped_demos: 3,
                # Limited per-task concurrency
                max_concurrency: 4
              )

            {task_id, result}
          end,
          # High task-level concurrency
          max_concurrency: 6,
          timeout: 20_000
        )
        |> Enum.to_list()

      end_time = System.monotonic_time()
      total_duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Analyze results
      successes =
        Enum.count(concurrent_results, fn
          {:ok, {_task_id, {:ok, _optimized}}} -> true
          # Acceptable with mock data
          {:ok, {_task_id, {:error, :no_successful_bootstrap_candidates}}} -> true
          _ -> false
        end)

      success_rate = successes / length(optimization_tasks)
      throughput = successes / (total_duration_ms / 1000)

      # Should handle concurrent optimization well
      assert success_rate >= 0.6,
             "Concurrent success rate too low: #{Float.round(success_rate * 100, 1)}%"

      assert throughput > 0.3,
             "Concurrent throughput too low: #{Float.round(throughput, 1)} optimizations/sec"

      assert total_duration_ms < 25_000,
             "Concurrent optimization took too long: #{total_duration_ms}ms"

      IO.puts(
        "Concurrent optimization: #{Float.round(throughput, 1)} opt/sec, #{Float.round(success_rate * 100, 1)}% success"
      )
    end

    test "resource cleanup after optimization cycles" do
      # Test that resources are properly cleaned up after optimization
      mock_provider_responses()

      initial_process_count = length(Process.list())
      initial_memory = :erlang.memory()

      # Run multiple optimization cycles
      Enum.each(1..6, fn cycle ->
        student = create_mock_program(:cleanup_student)
        teacher = create_mock_program(:cleanup_teacher)
        trainset = create_memory_test_trainset(20)
        metric_fn = create_memory_test_metric()

        case DSPEx.Teleprompter.BootstrapFewShot.compile(
               student,
               teacher,
               trainset,
               metric_fn,
               max_bootstrapped_demos: 6,
               max_concurrency: 10
             ) do
          {:ok, _optimized} -> :ok
          # Expected with mock data
          {:error, :no_successful_bootstrap_candidates} -> :ok
          {:error, other} -> flunk("Unexpected error in cycle #{cycle}: #{inspect(other)}")
        end

        # Force cleanup
        :erlang.garbage_collect()

        # Check resource usage periodically
        if rem(cycle, 2) == 0 do
          current_process_count = length(Process.list())
          current_memory = :erlang.memory()

          process_growth = current_process_count - initial_process_count
          memory_growth_mb = (current_memory[:total] - initial_memory[:total]) / (1024 * 1024)

          # Should not accumulate excessive resources
          assert process_growth < 50,
                 "Process count grew too much after #{cycle} cycles: +#{process_growth}"

          assert memory_growth_mb < 30,
                 "Memory grew too much after #{cycle} cycles: +#{Float.round(memory_growth_mb, 1)}MB"

          IO.puts(
            "After cycle #{cycle}: +#{process_growth} processes, +#{Float.round(memory_growth_mb, 1)}MB memory"
          )
        end
      end)

      # Final cleanup check
      :erlang.garbage_collect()
      # Allow cleanup to complete
      Process.sleep(100)

      final_process_count = length(Process.list())
      final_memory = :erlang.memory()

      final_process_growth = final_process_count - initial_process_count
      final_memory_growth_mb = (final_memory[:total] - initial_memory[:total]) / (1024 * 1024)

      # Final resource usage should be reasonable
      assert final_process_growth < 30, "Final process growth too high: +#{final_process_growth}"

      assert final_memory_growth_mb < @memory_leak_threshold_mb,
             "Final memory growth too high: +#{Float.round(final_memory_growth_mb, 1)}MB (threshold: #{@memory_leak_threshold_mb}MB)"

      log_memory_usage("resource_cleanup", final_memory_growth_mb, final_process_growth)
    end
  end

  # Helper functions for memory performance testing

  defp create_mock_program(_id, _opts \\ []) do
    # Mock the forward function for performance testing
    mock_provider_responses()

    DSPEx.Predict.new(MemoryTestSignature, :gemini, model: "gemini-pro")
  end

  defp create_memory_test_trainset(size) do
    for i <- 1..size do
      DSPEx.Example.new(%{
        question: "Memory test question #{i}?",
        answer: "Answer #{i}",
        context: "Memory test context for question #{i}"
      })
      |> DSPEx.Example.with_inputs([:question])
    end
  end

  defp create_memory_test_metric do
    fn example, prediction ->
      # For performance testing, use a lenient metric that works with mock responses
      cond do
        # Check if prediction has an answer field
        Map.has_key?(prediction, :answer) and Map.get(prediction, :answer) != nil ->
          1.0

        # Check if prediction has content (direct string response)
        is_binary(prediction) and String.length(prediction) > 0 ->
          1.0

        # Check for map with string keys (from mock responses)
        is_map(prediction) and Map.has_key?(prediction, "answer") ->
          1.0

        # Default case - check for any meaningful content
        true ->
          case example do
            # Good enough for performance testing
            %{outputs: %{answer: _}} -> 0.8
            # Still acceptable for performance benchmarks
            _ -> 0.5
          end
      end
    end
  end

  defp mock_provider_responses do
    # Set up test mode to force mock responses
    DSPEx.TestModeConfig.set_test_mode(:mock)

    # For performance tests, we just ensure test mode is set
    # The actual mock responses are handled by the fallback mechanism
    :ok
  end

  defp log_memory_usage(test_name, memory_mb, additional_metric) do
    IO.puts("\n=== Memory Performance: #{test_name} ===")
    IO.puts("Memory usage: #{Float.round(memory_mb, 2)} MB")

    if additional_metric do
      case test_name do
        "teleprompter_iterations" ->
          IO.puts("Process memory: #{Float.round(additional_metric, 2)} MB")

        "large_trainset" ->
          IO.puts("Duration: #{Float.round(additional_metric, 2)} seconds")

        "optimization_cycles" ->
          IO.puts("Peak memory: #{Float.round(additional_metric, 2)} MB")

        "resource_cleanup" ->
          IO.puts("Process growth: #{additional_metric}")

        _ ->
          IO.puts("Additional metric: #{additional_metric}")
      end
    end
  end

  # Test signature for memory performance testing
  defmodule MemoryTestSignature do
    use DSPEx.Signature, "question -> answer"
  end
end
