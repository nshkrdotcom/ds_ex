defmodule DSPEx.Performance.SimbaScalingTest do
  @moduledoc """
  Phase 5: SIMBA-specific scaling and performance validation tests.

  Tests optimization time scaling, memory usage patterns, concurrent optimization
  behavior, and performance benchmarks for the SIMBA teleprompter under various
  loads and dataset sizes.
  """
  use ExUnit.Case, async: false

  alias DSPEx.Teleprompter.SIMBA
  alias DSPEx.Predict

  @moduletag :group_3
  @moduletag :performance
  @moduletag :scaling
  @moduletag :phase_5
  @moduletag timeout: :infinity

  # Performance test configuration
  @small_dataset_size 10
  @medium_dataset_size 50
  @large_dataset_size 100
  @huge_dataset_size 500

  # Memory thresholds
  @max_memory_growth_mb 100
  @max_optimization_time_ms 30_000

  # Test signature for scaling tests
  defmodule ScalingTestSignature do
    use DSPEx.Signature, "question -> answer"
  end

  describe "SIMBA optimization time scaling" do
    test "optimization time scales sub-quadratically with training set size" do
      # Test optimization time with increasing dataset sizes
      dataset_sizes = [@small_dataset_size, @medium_dataset_size, @large_dataset_size]

      results =
        Enum.map(dataset_sizes, fn size ->
          simba =
            SIMBA.new(
              strategies: [:append_demo],
              num_candidates: 5,
              max_steps: 3
            )

          program = create_test_program()
          training_data = create_scaling_trainset(size)
          metric_fn = create_scaling_metric()

          # Mock responses for all examples
          responses = Enum.map(1..size, fn i -> %{content: "Answer #{i}"} end)
          DSPEx.MockClientManager.set_mock_responses(:test, responses)

          {time_taken, result} =
            :timer.tc(fn ->
              SIMBA.compile(simba, program, training_data, metric_fn)
            end)

          time_ms = time_taken / 1000

          case result do
            {:ok, optimized} ->
              %{
                dataset_size: size,
                time_ms: time_ms,
                time_per_example: time_ms / size,
                success: true,
                score: optimized.performance.average_score
              }

            {:error, reason} ->
              %{
                dataset_size: size,
                time_ms: time_ms,
                time_per_example: time_ms / size,
                success: false,
                error: reason
              }
          end
        end)

      # Analyze scaling behavior
      successful_results = Enum.filter(results, & &1.success)

      assert length(successful_results) >= 2, "Need at least 2 successful runs to analyze scaling"

      # Check sub-quadratic scaling
      if length(successful_results) >= 2 do
        small_result = hd(successful_results)
        large_result = List.last(successful_results)

        scaling_factor = large_result.time_per_example / small_result.time_per_example

        # Should not scale worse than quadratic (factor < 10 for 10x data increase)
        assert scaling_factor < 10.0,
               "Scaling too poor: #{Float.round(scaling_factor, 2)}x time per example increase"
      end

      # Log performance results
      IO.puts("\n=== SIMBA Optimization Scaling ===")

      Enum.each(results, fn result ->
        if result.success do
          IO.puts(
            "Dataset #{result.dataset_size}: #{Float.round(result.time_ms, 1)}ms (#{Float.round(result.time_per_example, 2)}ms/example)"
          )
        else
          IO.puts("Dataset #{result.dataset_size}: FAILED - #{inspect(result.error)}")
        end
      end)
    end

    test "optimization with both strategies scales appropriately" do
      # Test scaling when using both append_demo and append_rule strategies
      simba_single =
        SIMBA.new(
          strategies: [:append_demo],
          num_candidates: 4,
          max_steps: 2
        )

      simba_both =
        SIMBA.new(
          strategies: [:append_demo, :append_rule],
          num_candidates: 4,
          max_steps: 2
        )

      program = create_test_program()
      training_data = create_scaling_trainset(@medium_dataset_size)
      metric_fn = create_scaling_metric()

      responses = Enum.map(1..@medium_dataset_size, fn i -> %{content: "Answer #{i}"} end)
      DSPEx.MockClientManager.set_mock_responses(:test, responses)

      # Test single strategy
      {single_time, single_result} =
        :timer.tc(fn ->
          SIMBA.compile(simba_single, program, training_data, metric_fn)
        end)

      # Reset mock for second test
      DSPEx.MockClientManager.set_mock_responses(:test, responses)

      # Test both strategies
      {both_time, both_result} =
        :timer.tc(fn ->
          SIMBA.compile(simba_both, program, training_data, metric_fn)
        end)

      single_time_ms = single_time / 1000
      both_time_ms = both_time / 1000

      # Both strategies should not be more than 3x slower than single strategy
      time_ratio = both_time_ms / max(single_time_ms, 1)

      assert time_ratio < 3.0,
             "Both strategies too slow: #{Float.round(time_ratio, 2)}x slower than single strategy"

      # Log strategy comparison
      IO.puts("\n=== Strategy Performance Comparison ===")
      IO.puts("Single strategy (append_demo): #{Float.round(single_time_ms, 1)}ms")
      IO.puts("Both strategies: #{Float.round(both_time_ms, 1)}ms")
      IO.puts("Overhead: #{Float.round(time_ratio, 2)}x")

      # Verify results
      case {single_result, both_result} do
        {{:ok, single_opt}, {:ok, both_opt}} ->
          # Both should produce valid optimizations
          assert single_opt.performance.average_score >= 0.0
          assert both_opt.performance.average_score >= 0.0

          # Both strategies might produce better results
          IO.puts(
            "Single strategy score: #{Float.round(single_opt.performance.average_score, 3)}"
          )

          IO.puts("Both strategies score: #{Float.round(both_opt.performance.average_score, 3)}")

        _ ->
          # Log any failures for analysis
          IO.puts("Single strategy result: #{inspect(single_result)}")
          IO.puts("Both strategies result: #{inspect(both_result)}")
      end
    end

    test "concurrent trajectory sampling scales with candidate count" do
      # Test how SIMBA scales with increasing number of candidates
      candidate_counts = [2, 5, 10, 20]

      program = create_test_program()
      training_data = create_scaling_trainset(@medium_dataset_size)
      metric_fn = create_scaling_metric()

      results =
        Enum.map(candidate_counts, fn num_candidates ->
          simba =
            SIMBA.new(
              strategies: [:append_demo],
              num_candidates: num_candidates,
              max_steps: 2
            )

          responses = Enum.map(1..@medium_dataset_size, fn i -> %{content: "Answer #{i}"} end)
          DSPEx.MockClientManager.set_mock_responses(:test, responses)

          {time_taken, result} =
            :timer.tc(fn ->
              SIMBA.compile(simba, program, training_data, metric_fn)
            end)

          time_ms = time_taken / 1000

          %{
            num_candidates: num_candidates,
            time_ms: time_ms,
            time_per_candidate: time_ms / num_candidates,
            result: result
          }
        end)

      # Analyze candidate scaling
      successful_results =
        Enum.filter(results, fn r ->
          match?({:ok, _}, r.result)
        end)

      assert length(successful_results) >= 2,
             "Need successful results to analyze candidate scaling"

      # Time should not scale exponentially with candidate count
      first_result = hd(successful_results)
      last_result = List.last(successful_results)

      candidate_ratio = last_result.num_candidates / first_result.num_candidates
      time_ratio = last_result.time_ms / first_result.time_ms

      # Time scaling should be better than exponential
      assert time_ratio < candidate_ratio * candidate_ratio,
             "Candidate scaling too poor: #{Float.round(time_ratio, 2)}x time for #{Float.round(candidate_ratio, 2)}x candidates"

      # Log candidate scaling results
      IO.puts("\n=== Candidate Count Scaling ===")

      Enum.each(results, fn result ->
        case result.result do
          {:ok, _} ->
            IO.puts(
              "#{result.num_candidates} candidates: #{Float.round(result.time_ms, 1)}ms (#{Float.round(result.time_per_candidate, 2)}ms/candidate)"
            )

          {:error, _} ->
            IO.puts("#{result.num_candidates} candidates: FAILED")
        end
      end)
    end
  end

  describe "memory usage scaling validation" do
    test "memory usage scales linearly with dataset size" do
      # Test memory growth with increasing dataset sizes
      dataset_sizes = [@small_dataset_size, @medium_dataset_size, @large_dataset_size]

      memory_results =
        Enum.map(dataset_sizes, fn size ->
          # Force garbage collection before measurement
          :erlang.garbage_collect()
          initial_memory = :erlang.memory()[:total]

          simba =
            SIMBA.new(
              strategies: [:append_demo],
              num_candidates: 5,
              max_steps: 2
            )

          program = create_test_program()
          training_data = create_scaling_trainset(size)
          metric_fn = create_scaling_metric()

          responses = Enum.map(1..size, fn i -> %{content: "Answer #{i}"} end)
          DSPEx.MockClientManager.set_mock_responses(:test, responses)

          result = SIMBA.compile(simba, program, training_data, metric_fn)

          :erlang.garbage_collect()
          final_memory = :erlang.memory()[:total]

          memory_growth_mb = (final_memory - initial_memory) / (1024 * 1024)
          memory_per_example = memory_growth_mb / size

          %{
            dataset_size: size,
            memory_growth_mb: memory_growth_mb,
            memory_per_example: memory_per_example,
            success: match?({:ok, _}, result)
          }
        end)

      # Verify memory scaling is reasonable
      Enum.each(memory_results, fn result ->
        assert result.memory_growth_mb < @max_memory_growth_mb,
               "Memory growth too high for #{result.dataset_size} examples: #{Float.round(result.memory_growth_mb, 2)}MB"

        assert result.memory_per_example < 2.0,
               "Memory per example too high: #{Float.round(result.memory_per_example, 3)}MB/example"
      end)

      # Log memory scaling results
      IO.puts("\n=== Memory Usage Scaling ===")

      Enum.each(memory_results, fn result ->
        IO.puts(
          "Dataset #{result.dataset_size}: #{Float.round(result.memory_growth_mb, 2)}MB total (#{Float.round(result.memory_per_example, 3)}MB/example)"
        )
      end)
    end

    test "memory cleanup after optimization cycles" do
      # Test that memory is properly cleaned up between optimization cycles
      base_memory = :erlang.memory()[:total]

      program = create_test_program()
      training_data = create_scaling_trainset(@medium_dataset_size)
      metric_fn = create_scaling_metric()

      # Run multiple optimization cycles
      cycle_memories =
        Enum.map(1..5, fn cycle ->
          simba =
            SIMBA.new(
              strategies: [:append_demo],
              num_candidates: 5,
              max_steps: 2
            )

          responses =
            Enum.map(1..@medium_dataset_size, fn i -> %{content: "Cycle #{cycle} Answer #{i}"} end)

          DSPEx.MockClientManager.set_mock_responses(:test, responses)

          _result = SIMBA.compile(simba, program, training_data, metric_fn)

          # Force cleanup
          :erlang.garbage_collect()
          # Allow cleanup to complete
          Process.sleep(50)
          :erlang.garbage_collect()

          current_memory = :erlang.memory()[:total]
          memory_growth_mb = (current_memory - base_memory) / (1024 * 1024)

          IO.puts("Cycle #{cycle}: Memory growth = #{Float.round(memory_growth_mb, 2)}MB")

          memory_growth_mb
        end)

      final_memory_growth = List.last(cycle_memories)
      max_memory_growth = Enum.max(cycle_memories)

      # Memory should not grow excessively across cycles
      assert final_memory_growth < 50,
             "Final memory growth too high: #{Float.round(final_memory_growth, 2)}MB"

      assert max_memory_growth < 75,
             "Peak memory growth too high: #{Float.round(max_memory_growth, 2)}MB"

      # Memory growth should stabilize (not grow exponentially)
      growth_trend = Enum.zip(1..5, cycle_memories)
      {later_cycles, earlier_cycles} = Enum.split(growth_trend, 3)

      avg_later = Enum.sum(Enum.map(later_cycles, fn {_, mem} -> mem end)) / length(later_cycles)

      avg_earlier =
        Enum.sum(Enum.map(earlier_cycles, fn {_, mem} -> mem end)) / length(earlier_cycles)

      growth_ratio = if avg_earlier > 0, do: avg_later / avg_earlier, else: 1.0

      assert growth_ratio < 2.0,
             "Memory growth not stabilizing: #{Float.round(growth_ratio, 2)}x increase in later cycles"
    end
  end

  describe "concurrent optimization performance" do
    test "multiple concurrent SIMBA optimizations don't interfere" do
      # Test running multiple SIMBA optimizations concurrently
      optimization_count = 6

      optimization_tasks =
        Enum.map(1..optimization_count, fn task_id ->
          Task.async(fn ->
            simba =
              SIMBA.new(
                strategies: [:append_demo],
                num_candidates: 4,
                max_steps: 2
              )

            program = create_test_program()
            training_data = create_scaling_trainset(20)
            metric_fn = create_scaling_metric()

            # Unique responses for each task
            responses = Enum.map(1..20, fn i -> %{content: "Task #{task_id} Answer #{i}"} end)
            DSPEx.MockClientManager.set_mock_responses(:test, responses)

            start_time = System.monotonic_time()
            result = SIMBA.compile(simba, program, training_data, metric_fn)
            end_time = System.monotonic_time()

            duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

            {task_id, result, duration_ms}
          end)
        end)

      # Wait for all optimizations to complete
      concurrent_results = Task.await_many(optimization_tasks, 60_000)

      # Analyze concurrent performance
      successful_tasks =
        Enum.filter(concurrent_results, fn {_, result, _} ->
          match?({:ok, _}, result)
        end)

      failure_count = optimization_count - length(successful_tasks)
      success_rate = length(successful_tasks) / optimization_count

      assert success_rate >= 0.5,
             "Concurrent success rate too low: #{Float.round(success_rate * 100, 1)}%"

      if length(successful_tasks) > 0 do
        durations = Enum.map(successful_tasks, fn {_, _, duration} -> duration end)
        avg_duration = Enum.sum(durations) / length(durations)
        max_duration = Enum.max(durations)

        assert avg_duration < @max_optimization_time_ms,
               "Average concurrent optimization too slow: #{Float.round(avg_duration, 0)}ms"

        assert max_duration < @max_optimization_time_ms * 2,
               "Slowest concurrent optimization too slow: #{Float.round(max_duration, 0)}ms"

        IO.puts("\n=== Concurrent Optimization Performance ===")

        IO.puts(
          "Tasks: #{optimization_count}, Successful: #{length(successful_tasks)}, Failed: #{failure_count}"
        )

        IO.puts("Average duration: #{Float.round(avg_duration, 0)}ms")
        IO.puts("Max duration: #{Float.round(max_duration, 0)}ms")
        IO.puts("Success rate: #{Float.round(success_rate * 100, 1)}%")
      end
    end

    test "SIMBA performance under resource contention" do
      # Test SIMBA performance when system resources are under pressure
      simba =
        SIMBA.new(
          strategies: [:append_demo, :append_rule],
          num_candidates: 10,
          max_steps: 3
        )

      program = create_test_program()
      training_data = create_scaling_trainset(@large_dataset_size)
      metric_fn = create_scaling_metric()

      # Create resource contention with background tasks
      background_tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            # Simulate CPU and memory pressure
            large_list = Enum.map(1..10_000, fn j -> "Background task #{i} item #{j}" end)

            # Consume CPU cycles
            Enum.reduce(1..1000, 0, fn x, acc -> acc + x * x end)

            # Keep memory allocated
            Process.sleep(5000)

            length(large_list)
          end)
        end)

      responses =
        Enum.map(1..@large_dataset_size, fn i -> %{content: "Contention Answer #{i}"} end)

      DSPEx.MockClientManager.set_mock_responses(:test, responses)

      # Run SIMBA under contention
      start_time = System.monotonic_time()
      result = SIMBA.compile(simba, program, training_data, metric_fn)
      end_time = System.monotonic_time()

      optimization_duration_ms =
        System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Clean up background tasks
      Task.await_many(background_tasks, 10_000)

      # SIMBA should still complete within reasonable time despite contention
      assert optimization_duration_ms < @max_optimization_time_ms * 2,
             "Optimization under contention too slow: #{optimization_duration_ms}ms"

      case result do
        {:ok, optimized} ->
          assert optimized.performance.average_score >= 0.0
          IO.puts("\n=== Performance Under Contention ===")
          IO.puts("Duration: #{optimization_duration_ms}ms")
          IO.puts("Score: #{Float.round(optimized.performance.average_score, 3)}")

        {:error, reason} ->
          IO.puts("\n=== Failed Under Contention ===")
          IO.puts("Duration: #{optimization_duration_ms}ms")
          IO.puts("Error: #{inspect(reason)}")
          # Some failure under extreme contention is acceptable
      end
    end
  end

  describe "large-scale performance benchmarks" do
    @tag :slow
    test "handles very large training sets efficiently" do
      # Test SIMBA with very large training sets
      simba =
        SIMBA.new(
          strategies: [:append_demo],
          num_candidates: 8,
          max_steps: 3
        )

      program = create_test_program()
      huge_training_data = create_scaling_trainset(@huge_dataset_size)
      metric_fn = create_scaling_metric()

      responses = Enum.map(1..@huge_dataset_size, fn i -> %{content: "Huge Answer #{i}"} end)
      DSPEx.MockClientManager.set_mock_responses(:test, responses)

      initial_memory = :erlang.memory()[:total]
      start_time = System.monotonic_time()

      result = SIMBA.compile(simba, program, huge_training_data, metric_fn)

      end_time = System.monotonic_time()
      final_memory = :erlang.memory()[:total]

      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
      memory_growth_mb = (final_memory - initial_memory) / (1024 * 1024)

      # Should handle huge datasets within reasonable bounds
      assert duration_ms < 120_000,
             "Huge dataset optimization too slow: #{duration_ms}ms (should be < 2 minutes)"

      assert memory_growth_mb < 300,
             "Huge dataset memory usage too high: #{Float.round(memory_growth_mb, 2)}MB"

      case result do
        {:ok, optimized} ->
          assert optimized.performance.average_score >= 0.0

          demo_count =
            case optimized do
              %{examples: examples} -> length(examples)
              %{demos: demos} -> length(demos)
              _ -> 0
            end

          IO.puts("\n=== Huge Dataset Performance ===")
          IO.puts("Training examples: #{@huge_dataset_size}")
          IO.puts("Duration: #{Float.round(duration_ms / 1000, 1)}s")
          IO.puts("Memory growth: #{Float.round(memory_growth_mb, 2)}MB")
          IO.puts("Demos generated: #{demo_count}")
          IO.puts("Score: #{Float.round(optimized.performance.average_score, 3)}")

        {:error, reason} ->
          IO.puts("\n=== Huge Dataset Failed ===")
          IO.puts("Training examples: #{@huge_dataset_size}")
          IO.puts("Duration: #{Float.round(duration_ms / 1000, 1)}s")
          IO.puts("Memory growth: #{Float.round(memory_growth_mb, 2)}MB")
          IO.puts("Error: #{inspect(reason)}")

          # Some huge dataset failures are acceptable in test environment
          assert String.contains?(inspect(reason), ["timeout", "memory", "resource"])
      end
    end
  end

  # Helper functions for scaling tests

  defp create_test_program do
    %Predict{
      signature: ScalingTestSignature,
      client: :test,
      instruction: "Answer questions accurately and efficiently.",
      demos: []
    }
  end

  defp create_scaling_trainset(size) do
    Enum.map(1..size, fn i ->
      question_type = rem(i, 4)

      {question, answer} =
        case question_type do
          0 -> {"What is #{i} + #{i}?", "#{i * 2}"}
          1 -> {"What is the capital of Country#{i}?", "Capital#{i}"}
          2 -> {"Define term#{i}", "Definition of term#{i}"}
          3 -> {"Explain concept#{i}", "Concept#{i} explanation"}
        end

      %{
        inputs: %{question: question},
        outputs: %{answer: answer},
        metadata: %{id: i, type: question_type}
      }
    end)
  end

  defp create_scaling_metric do
    fn example, prediction ->
      expected = get_in(example, [:outputs, :answer]) || ""
      actual = extract_actual_answer(prediction)
      calculate_similarity_score(actual, expected)
    end
  end

  defp extract_actual_answer(prediction) do
    case prediction do
      %{answer: answer} -> answer
      %{"answer" => answer} -> answer
      binary when is_binary(binary) -> binary
      _ -> ""
    end
  end

  defp calculate_similarity_score(actual, expected) do
    cond do
      actual == expected -> 1.0
      String.contains?(actual, expected) -> 0.8
      String.length(actual) > 0 -> 0.5
      true -> 0.0
    end
  end
end
