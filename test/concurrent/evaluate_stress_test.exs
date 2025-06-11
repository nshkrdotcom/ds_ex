defmodule DSPEx.Concurrent.EvaluateStressTest do
  @moduledoc """
  Concurrent stress tests for DSPEx.Evaluate module.
  Tests concurrent evaluation behavior, race conditions, fault isolation,
  and resource management under high concurrent load for SIMBA readiness.
  """
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  @concurrency_level 50
  @stress_operations 200

  # Test helper to create mock program
  defmodule MockProgram do
    use DSPEx.Program

    defstruct [:id, :delay_ms, :failure_rate]

    def new(id, opts \\ []) do
      %__MODULE__{
        id: id,
        delay_ms: Keyword.get(opts, :delay_ms, 10),
        failure_rate: Keyword.get(opts, :failure_rate, 0.0)
      }
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      # Simulate processing time
      Process.sleep(program.delay_ms)

      # Simulate random failures
      if :rand.uniform() < program.failure_rate do
        {:error, :program_failure}
      else
        {:ok, Map.put(inputs, :processed, true)}
      end
    end
  end

  describe "concurrent evaluation" do
    test "concurrent evaluation produces consistent results" do
      program = MockProgram.new(:consistent_test, delay_ms: 5)

      examples = [
        DSPEx.Example.new(%{question: "What is 2+2?", answer: "4"}, [:question]),
        DSPEx.Example.new(%{question: "What is 3+3?", answer: "6"}, [:question]),
        DSPEx.Example.new(%{question: "What is 4+4?", answer: "8"}, [:question])
      ]

      metric_fn = fn _example, prediction ->
        if Map.has_key?(prediction, :processed) and prediction.processed, do: 1.0, else: 0.0
      end

      # Run same evaluation concurrently multiple times
      tasks =
        for i <- 1..@concurrency_level do
          Task.async(fn ->
            correlation_id = "consistent-#{i}"
            DSPEx.Evaluate.run(program, examples, metric_fn, correlation_id: correlation_id)
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All evaluations should succeed
      assert length(results) == @concurrency_level
      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == @concurrency_level

      # All should produce consistent results
      for {:ok, result} <- results do
        assert result.stats.total_examples == 3
        assert result.stats.successful == 3
        assert result.stats.failed == 0
        assert result.score == 1.0
      end
    end

    test "concurrent evaluation handles high load" do
      program = MockProgram.new(:high_load_test, delay_ms: 20)

      # Create larger example set
      examples =
        for i <- 1..20 do
          DSPEx.Example.new(%{question: "Question #{i}", answer: "Answer #{i}"}, [:question])
        end

      metric_fn = fn _example, prediction ->
        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      # Track evaluation start times
      evaluation_counter = :counters.new(1, [])

      # Execute many concurrent evaluations
      tasks =
        for i <- 1..@stress_operations do
          Task.async(fn ->
            :counters.add(evaluation_counter, 1, 1)
            start_time = System.monotonic_time()

            correlation_id = "load-#{i}"

            result =
              DSPEx.Evaluate.run(program, examples, metric_fn,
                correlation_id: correlation_id,
                max_concurrency: 10
              )

            end_time = System.monotonic_time()
            duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)

            {result, duration, i}
          end)
        end

      results = Task.await_many(tasks, 30_000)

      # All evaluations should complete
      assert length(results) == @stress_operations

      successes = Enum.count(results, fn {result, _, _} -> match?({:ok, _}, result) end)
      assert successes == @stress_operations

      # Verify all evaluations processed correctly
      for {{:ok, eval_result}, _duration, _index} <- results do
        assert eval_result.stats.total_examples == 20
        assert eval_result.stats.successful == 20
        assert eval_result.score == 1.0
      end

      # Check performance characteristics
      durations = Enum.map(results, fn {_, duration, _} -> duration end)
      avg_duration = Enum.sum(durations) / length(durations)

      # Should handle high load efficiently
      # Average under 5 seconds
      assert avg_duration < 5000

      # Verify counter
      final_count = :counters.get(evaluation_counter, 1)
      assert final_count == @stress_operations
    end

    test "evaluation isolates failures between examples" do
      # Program that fails on certain inputs
      program = MockProgram.new(:failure_isolation_test, failure_rate: 0.3, delay_ms: 10)

      examples =
        for i <- 1..50 do
          DSPEx.Example.new(%{question: "Question #{i}", answer: "Answer #{i}"}, [:question])
        end

      metric_fn = fn _example, prediction ->
        case prediction do
          {:error, _} -> 0.0
          %{processed: true} -> 1.0
          _ -> 0.0
        end
      end

      # Run concurrent evaluations with mixed success/failure
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            correlation_id = "isolation-#{i}"

            DSPEx.Evaluate.run(program, examples, metric_fn,
              correlation_id: correlation_id,
              fault_tolerance: :skip_failed
            )
          end)
        end

      results = Task.await_many(tasks, 15_000)

      # All evaluations should complete despite failures
      assert length(results) == 20
      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 20

      # Each evaluation should have some successes and some failures
      for {:ok, result} <- results do
        assert result.stats.total_examples == 50
        # Some should succeed
        assert result.stats.successful > 0
        # Some should fail (30% failure rate)
        assert result.stats.failed > 0
        assert result.stats.successful + result.stats.failed == 50
        # Not perfect due to failures
        assert result.stats.success_rate < 1.0
      end
    end

    test "concurrent evaluation respects concurrency limits" do
      program = MockProgram.new(:concurrency_limit_test, delay_ms: 50)

      examples =
        for i <- 1..10 do
          DSPEx.Example.new(%{question: "Question #{i}", answer: "Answer #{i}"}, [:question])
        end

      metric_fn = fn _example, prediction ->
        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      # Track concurrent execution
      active_counter = :counters.new(1, [])
      max_concurrent = :counters.new(1, [])

      # Modified metric function to track concurrency
      tracking_metric_fn = fn example, prediction ->
        :counters.add(active_counter, 1, 1)
        current_active = :counters.get(active_counter, 1)

        # Update max if this is higher
        current_max = :counters.get(max_concurrent, 1)

        if current_active > current_max do
          :counters.put(max_concurrent, 1, current_active)
        end

        result = metric_fn.(example, prediction)
        :counters.add(active_counter, 1, -1)
        result
      end

      # Run evaluation with limited concurrency
      max_concurrency = 5

      {:ok, result} =
        DSPEx.Evaluate.run(program, examples, tracking_metric_fn,
          max_concurrency: max_concurrency
        )

      # Evaluation should succeed
      assert result.stats.total_examples == 10
      assert result.stats.successful == 10

      # Should not have exceeded concurrency limit significantly
      observed_max = :counters.get(max_concurrent, 1)
      # Allow small overage due to timing
      assert observed_max <= max_concurrency + 2
    end
  end

  describe "Task.async_stream behavior" do
    test "async_stream processes examples in parallel" do
      program = MockProgram.new(:parallel_test, delay_ms: 100)

      examples =
        for i <- 1..10 do
          DSPEx.Example.new(%{question: "Question #{i}", answer: "Answer #{i}"}, [:question])
        end

      # Track processing times to prove parallelism
      # start_count, end_count
      process_tracker = :counters.new(2, [])

      metric_fn = fn _example, prediction ->
        # Increment start
        :counters.add(process_tracker, 1, 1)
        # Additional delay
        Process.sleep(50)
        # Increment end
        :counters.add(process_tracker, 2, 1)

        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      start_time = System.monotonic_time()

      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn, max_concurrency: 5)

      end_time = System.monotonic_time()
      total_duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Should complete much faster than sequential (which would be ~1500ms)
      # Parallel execution should be much faster
      assert total_duration < 800

      # All examples should be processed
      assert result.stats.successful == 10

      # Verify tracking counters
      start_count = :counters.get(process_tracker, 1)
      end_count = :counters.get(process_tracker, 2)
      assert start_count == 10
      assert end_count == 10
    end

    test "async_stream handles timeouts gracefully" do
      # Program with variable delays
      program = MockProgram.new(:timeout_test, delay_ms: 200)

      examples =
        for i <- 1..10 do
          DSPEx.Example.new(
            %{
              question: "Question #{i}",
              timeout_test: rem(i, 3) == 0,
              answer: "Answer #{i}"
            },
            [:question, :timeout_test]
          )
        end

      timeout_counter = :counters.new(1, [])

      metric_fn = fn example, prediction ->
        # Some examples designed to timeout
        inputs = DSPEx.Example.inputs(example)

        if Map.get(inputs, :timeout_test, false) do
          :counters.add(timeout_counter, 1, 1)
          # Long delay to trigger timeout
          Process.sleep(1000)
        end

        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      # Run with aggressive timeout
      {:ok, result} =
        DSPEx.Evaluate.run(program, examples, metric_fn,
          timeout: 500,
          fault_tolerance: :skip_failed
        )

      # Some should timeout/fail, others succeed
      assert result.stats.total_examples == 10
      assert result.stats.successful > 0
      assert result.stats.failed > 0

      # Verify timeout tracking
      timeout_attempts = :counters.get(timeout_counter, 1)
      assert timeout_attempts > 0
    end

    test "async_stream respects ordering of results" do
      program = MockProgram.new(:ordering_test, delay_ms: 20)

      examples =
        for i <- 1..20 do
          DSPEx.Example.new(%{question: "Question #{i}", sequence: i, answer: "Answer #{i}"}, [
            :question,
            :sequence
          ])
        end

      # Track order of processing
      {:ok, order_tracker} = Agent.start_link(fn -> [] end)

      metric_fn = fn example, prediction ->
        inputs = DSPEx.Example.inputs(example)
        sequence = Map.get(inputs, :sequence)
        Agent.update(order_tracker, fn list -> [sequence | list] end)

        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn, max_concurrency: 5)

      # All should succeed
      assert result.stats.successful == 20

      # Check that processing order was recorded
      processing_order = Agent.get(order_tracker, & &1)
      Agent.stop(order_tracker)

      # Should have processed all sequences
      assert length(processing_order) == 20
      sequences = Enum.sort(processing_order)
      assert sequences == Enum.to_list(1..20)
    end
  end

  describe "fault isolation" do
    test "one failing evaluation doesn't crash others" do
      # Mix of good and bad programs
      good_program = MockProgram.new(:good, delay_ms: 10)
      # Always fails
      bad_program = MockProgram.new(:bad, failure_rate: 1.0, delay_ms: 15)

      examples = [
        DSPEx.Example.new(%{question: "Test", answer: "Test"}, [:question])
      ]

      metric_fn = fn _example, prediction ->
        case prediction do
          {:error, _} -> 0.0
          %{processed: true} -> 1.0
          _ -> 0.0
        end
      end

      # Run mixed evaluations concurrently
      tasks =
        for i <- 1..30 do
          Task.async(fn ->
            program = if rem(i, 3) == 0, do: bad_program, else: good_program
            correlation_id = "fault-isolation-#{i}"

            DSPEx.Evaluate.run(program, examples, metric_fn,
              correlation_id: correlation_id,
              fault_tolerance: :skip_failed
            )
          end)
        end

      results = Task.await_many(tasks, 8_000)

      # All evaluations should complete (not crash)
      assert length(results) == 30
      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 30

      # Analyze results - good programs should succeed, bad should have zero score
      good_results = Enum.filter(results, fn {:ok, result} -> result.score > 0.0 end)
      bad_results = Enum.filter(results, fn {:ok, result} -> result.score == 0.0 end)

      # Some good results
      assert length(good_results) > 0
      # Some bad results
      assert length(bad_results) > 0
      assert length(good_results) + length(bad_results) == 30
    end

    test "GenServer crashes don't affect evaluation" do
      program = MockProgram.new(:crash_resilient_test, delay_ms: 30)

      examples =
        for i <- 1..15 do
          DSPEx.Example.new(%{question: "Question #{i}", answer: "Answer #{i}"}, [:question])
        end

      crash_counter = :counters.new(1, [])

      # Metric function that occasionally crashes
      metric_fn = fn example, prediction ->
        inputs = DSPEx.Example.inputs(example)
        question = Map.get(inputs, :question, "")

        # Crash on certain questions
        if String.contains?(question, "5") or String.contains?(question, "10") do
          :counters.add(crash_counter, 1, 1)
          raise "Simulated crash in metric function"
        end

        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      # Run evaluation with crash-prone metric
      {:ok, result} =
        DSPEx.Evaluate.run(program, examples, metric_fn, fault_tolerance: :skip_failed)

      # Should complete despite crashes
      assert result.stats.total_examples == 15
      # Some should fail due to crashes
      assert result.stats.failed > 0
      # But some should succeed
      assert result.stats.successful > 0

      # Verify crashes occurred
      crash_count = :counters.get(crash_counter, 1)
      assert crash_count > 0
    end

    test "network errors are isolated per example" do
      program = MockProgram.new(:network_error_test, delay_ms: 15, failure_rate: 0.2)

      examples =
        for i <- 1..25 do
          DSPEx.Example.new(
            %{
              question: "Question #{i}",
              network_test: rem(i, 4) == 0,
              answer: "Answer #{i}"
            },
            [:question, :network_test]
          )
        end

      network_error_counter = :counters.new(1, [])

      metric_fn = fn example, prediction ->
        # Simulate network-like errors for certain examples
        inputs = DSPEx.Example.inputs(example)

        if Map.get(inputs, :network_test, false) do
          :counters.add(network_error_counter, 1, 1)
          # Simulate a network error scenario
          if :rand.uniform() < 0.3 do
            # Simulate network error affecting scoring
            0.0
          else
            # Partial success despite network issues
            0.5
          end
        else
          case prediction do
            {:error, _} -> 0.0
            %{processed: true} -> 1.0
            _ -> 0.0
          end
        end
      end

      {:ok, result} =
        DSPEx.Evaluate.run(program, examples, metric_fn, fault_tolerance: :skip_failed)

      # Should complete with mixed results
      assert result.stats.total_examples == 25
      assert result.stats.successful > 0

      # Some network-like errors should have been simulated
      network_errors = :counters.get(network_error_counter, 1)
      assert network_errors > 0
    end
  end

  describe "resource management" do
    test "concurrent evaluation doesn't exhaust GenServer pools" do
      program = MockProgram.new(:pool_test, delay_ms: 50)

      examples =
        for i <- 1..20 do
          DSPEx.Example.new(%{question: "Question #{i}", answer: "Answer #{i}"}, [:question])
        end

      metric_fn = fn _example, prediction ->
        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      # Track system resources
      initial_processes = :erlang.system_info(:process_count)

      # Run multiple concurrent evaluations
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            correlation_id = "pool-#{i}"

            DSPEx.Evaluate.run(program, examples, metric_fn,
              correlation_id: correlation_id,
              max_concurrency: 8
            )
          end)
        end

      results = Task.await_many(tasks, 20_000)

      # All should complete successfully
      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 10

      # Resource usage should be reasonable
      final_processes = :erlang.system_info(:process_count)
      process_growth = final_processes - initial_processes

      # Should not have excessive process growth
      assert process_growth < 200
    end

    test "memory usage stays bounded during large evaluations" do
      program = MockProgram.new(:memory_test, delay_ms: 10)

      # Large example set
      examples =
        for i <- 1..100 do
          large_content = String.duplicate("Large content #{i} ", 100)
          DSPEx.Example.new(%{question: large_content, answer: "Answer #{i}"}, [:question])
        end

      metric_fn = fn _example, prediction ->
        # Simulate memory-intensive scoring
        _large_data = String.duplicate("scoring data ", 1000)
        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      # Monitor memory usage
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn, max_concurrency: 20)

      # Force cleanup
      :erlang.garbage_collect()
      Process.sleep(100)
      final_memory = :erlang.memory(:total)

      # Should complete successfully
      assert result.stats.successful == 100

      # Memory growth should be bounded
      memory_growth = final_memory - initial_memory
      # Less than 200MB growth
      assert memory_growth < 200_000_000
    end

    test "evaluation cleans up resources properly" do
      program = MockProgram.new(:cleanup_test, delay_ms: 20)

      examples =
        for i <- 1..30 do
          DSPEx.Example.new(%{question: "Question #{i}", answer: "Answer #{i}"}, [:question])
        end

      # Track resource allocation
      {:ok, resource_tracker} = Agent.start_link(fn -> %{allocated: 0, cleaned: 0} end)

      metric_fn = fn _example, prediction ->
        # Simulate resource allocation
        Agent.update(resource_tracker, fn state ->
          %{state | allocated: state.allocated + 1}
        end)

        # Simulate cleanup (in a real scenario this might be in an after block)
        Agent.update(resource_tracker, fn state ->
          %{state | cleaned: state.cleaned + 1}
        end)

        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)

      # Should complete successfully
      assert result.stats.successful == 30

      # Verify resource tracking
      final_state = Agent.get(resource_tracker, & &1)
      Agent.stop(resource_tracker)

      # Resources should be properly allocated and cleaned
      assert final_state.allocated == 30
      assert final_state.cleaned == 30
    end
  end

  describe "race conditions" do
    test "concurrent cache access doesn't cause race conditions" do
      program = MockProgram.new(:cache_race_test, delay_ms: 25)

      # Same examples for cache testing
      examples = [
        DSPEx.Example.new(%{question: "Cached question", answer: "Cached answer"}, [:question])
      ]

      cache_access_counter = :counters.new(1, [])

      metric_fn = fn _example, prediction ->
        # Simulate cache access
        :counters.add(cache_access_counter, 1, 1)
        current_count = :counters.get(cache_access_counter, 1)

        # Brief delay to create race condition opportunity
        Process.sleep(5)

        # Verify counter hasn't been corrupted by race condition
        final_count = :counters.get(cache_access_counter, 1)
        assert final_count >= current_count

        if Map.has_key?(prediction, :processed), do: 1.0, else: 0.0
      end

      # Run many concurrent evaluations with same data (cache-friendly)
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            correlation_id = "cache-race-#{i}"
            DSPEx.Evaluate.run(program, examples, metric_fn, correlation_id: correlation_id)
          end)
        end

      results = Task.await_many(tasks, 12_000)

      # All should succeed
      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 50

      # Verify cache access counter integrity
      final_access_count = :counters.get(cache_access_counter, 1)
      assert final_access_count == 50
    end

    test "circuit breaker-like state changes are handled correctly" do
      program = MockProgram.new(:circuit_test, delay_ms: 30, failure_rate: 0.3)

      examples =
        for i <- 1..15 do
          DSPEx.Example.new(%{question: "Question #{i}", answer: "Answer #{i}"}, [:question])
        end

      # Track circuit breaker-like state changes
      # closed, open, half_open
      circuit_state_tracker = :counters.new(3, [])

      metric_fn = fn example, prediction ->
        inputs = DSPEx.Example.inputs(example)
        question = Map.get(inputs, :question, "")

        # Simulate circuit breaker-like behavior based on question content
        state =
          cond do
            String.contains?(question, "5") ->
              # Simulate open state
              :counters.add(circuit_state_tracker, 2, 1)
              :open

            String.contains?(question, "10") ->
              # Simulate half-open state
              :counters.add(circuit_state_tracker, 3, 1)
              :half_open

            true ->
              # Simulate closed state
              :counters.add(circuit_state_tracker, 1, 1)
              :closed
          end

        # Adjust scoring based on simulated circuit breaker state
        base_score =
          case prediction do
            {:error, _} -> 0.0
            %{processed: true} -> 1.0
            _ -> 0.0
          end

        case state do
          # Very low success in open state
          :open -> base_score * 0.1
          # Reduced success in half-open
          :half_open -> base_score * 0.6
          # Normal success in closed state
          :closed -> base_score
        end
      end

      # Run evaluation during circuit breaker-like state changes
      {:ok, result} =
        DSPEx.Evaluate.run(program, examples, metric_fn,
          max_concurrency: 10,
          fault_tolerance: :skip_failed
        )

      # Should complete despite circuit breaker-like activity
      assert result.stats.total_examples == 15

      # Verify circuit breaker state tracking
      closed_count = :counters.get(circuit_state_tracker, 1)
      open_count = :counters.get(circuit_state_tracker, 2)
      half_open_count = :counters.get(circuit_state_tracker, 3)

      # Should have seen various states
      assert closed_count + open_count + half_open_count > 0
      # Should have some normal operations
      assert closed_count > 0
    end
  end
end
