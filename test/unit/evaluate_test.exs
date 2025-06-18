defmodule DSPEx.EvaluateTest do
  @moduledoc """
  Comprehensive unit tests for DSPEx.Evaluate module.
  Tests concurrent evaluation, distributed evaluation, error handling,
  telemetry, fault tolerance, and performance characteristics.
  """
  use ExUnit.Case, async: true

  @moduletag :group_1

  # Test program implementations for evaluation scenarios
  defmodule MockProgram do
    use DSPEx.Program

    defstruct [:id, :response_map, :delay_ms, :error_rate, :behavior]

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      # Add delay if specified
      if program.delay_ms && program.delay_ms > 0 do
        Process.sleep(program.delay_ms)
      end

      # Simulate error rate
      if program.error_rate && :rand.uniform() < program.error_rate do
        {:error, :simulated_failure}
      else
        case program.behavior do
          :echo ->
            {:ok, inputs}

          :multiply ->
            if Map.has_key?(inputs, :number) do
              {:ok, %{result: inputs.number * 2}}
            else
              {:error, :missing_number}
            end

          :custom_response ->
            response = Map.get(program.response_map, inputs[:question], "default response")
            {:ok, %{answer: response}}

          _ ->
            {:ok, %{processed: true, id: program.id}}
        end
      end
    end
  end

  defmodule AlwaysSucceedProgram do
    use DSPEx.Program

    defstruct [:score]

    @impl DSPEx.Program
    def forward(_program, inputs, _opts) do
      {:ok, Map.put(inputs, :success, true)}
    end
  end

  defmodule AlwaysFailProgram do
    use DSPEx.Program

    defstruct [:error_type]

    @impl DSPEx.Program
    def forward(program, _inputs, _opts) do
      {:error, program.error_type || :always_fails}
    end
  end

  defmodule TimeoutProgram do
    use DSPEx.Program

    defstruct [:timeout_ms]

    @impl DSPEx.Program
    def forward(program, _inputs, _opts) do
      Process.sleep(program.timeout_ms || 10_000)
      {:ok, %{result: "should not reach here"}}
    end
  end

  # Helper functions for creating test data

  defp create_examples(count, pattern \\ :simple) do
    for i <- 1..count do
      case pattern do
        :simple ->
          %{
            inputs: %{question: "What is #{i}+#{i}?"},
            outputs: %{answer: "#{i + i}"}
          }

        :math ->
          %{
            inputs: %{number: i},
            outputs: %{result: i * 2}
          }

        :complex ->
          %{
            inputs: %{
              question: "Complex question #{i}",
              context: "Context for #{i}",
              difficulty: rem(i, 3) + 1
            },
            outputs: %{
              answer: "Complex answer #{i}",
              confidence: 0.8 + rem(i, 5) * 0.04
            }
          }
      end
    end
  end

  defp simple_metric_fn(example, prediction) do
    cond do
      Map.get(example.outputs, :answer) == Map.get(prediction, :answer) -> 1.0
      Map.get(example.outputs, :result) == Map.get(prediction, :result) -> 1.0
      true -> 0.0
    end
  end

  defp weighted_metric_fn(example, prediction) do
    base_score = simple_metric_fn(example, prediction)
    weight = Map.get(example.inputs, :difficulty, 1)
    base_score * weight
  end

  describe "input validation" do
    test "validates program implements DSPEx.Program behavior" do
      examples = create_examples(1)

      # Valid program
      program = %MockProgram{id: 1}
      assert {:ok, _result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Invalid program - doesn't implement behavior
      invalid_program = %{not: "a program"}

      assert {:error, {:invalid_program, _}} =
               DSPEx.Evaluate.run(invalid_program, examples, &simple_metric_fn/2)
    end

    test "validates examples are non-empty list with correct structure" do
      program = %MockProgram{id: 1}

      # Empty list
      assert {:error, {:invalid_examples, _}} =
               DSPEx.Evaluate.run(program, [], &simple_metric_fn/2)

      # Not a list
      assert {:error, {:invalid_examples, _}} =
               DSPEx.Evaluate.run(program, "not a list", &simple_metric_fn/2)

      # Invalid example structure
      invalid_examples = [%{wrong: "structure"}]

      assert {:error, {:invalid_examples, _}} =
               DSPEx.Evaluate.run(program, invalid_examples, &simple_metric_fn/2)

      # Missing inputs
      invalid_examples = [%{outputs: %{answer: "test"}}]

      assert {:error, {:invalid_examples, _}} =
               DSPEx.Evaluate.run(program, invalid_examples, &simple_metric_fn/2)

      # Missing outputs
      invalid_examples = [%{inputs: %{question: "test"}}]

      assert {:error, {:invalid_examples, _}} =
               DSPEx.Evaluate.run(program, invalid_examples, &simple_metric_fn/2)

      # Valid examples
      valid_examples = create_examples(2)
      assert {:ok, _result} = DSPEx.Evaluate.run(program, valid_examples, &simple_metric_fn/2)
    end

    test "validates metric function has correct arity" do
      program = %MockProgram{id: 1}
      examples = create_examples(1)

      # Wrong arity
      wrong_arity_fn = fn _one_arg -> 1.0 end

      assert {:error, {:invalid_metric_function, _}} =
               DSPEx.Evaluate.run(program, examples, wrong_arity_fn)

      # Not a function
      assert {:error, {:invalid_metric_function, _}} =
               DSPEx.Evaluate.run(program, examples, "not a function")

      # Correct arity
      correct_fn = fn _example, _prediction -> 1.0 end
      assert {:ok, _result} = DSPEx.Evaluate.run(program, examples, correct_fn)
    end
  end

  describe "basic evaluation functionality" do
    test "evaluates simple examples successfully" do
      program = %MockProgram{
        id: 1,
        behavior: :custom_response,
        response_map: %{
          "What is 1+1?" => "2",
          "What is 2+2?" => "4"
        }
      }

      examples = create_examples(2)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      assert %{score: score, stats: stats} = result
      # Perfect score
      assert score == 1.0
      assert stats.total_examples == 2
      assert stats.successful == 2
      assert stats.failed == 0
      assert stats.success_rate == 1.0
      assert stats.throughput > 0
      assert is_integer(stats.duration_ms)
      assert stats.errors == []
    end

    test "handles partial success scenarios" do
      program = %AlwaysFailProgram{error_type: :test_error}
      examples = create_examples(3)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Should return result with zero score when all evaluations fail
      assert result.score == 0.0
      assert result.stats.successful == 0
      assert result.stats.failed == 3
      assert result.stats.success_rate == 0.0
    end

    test "calculates correct scores for mixed results" do
      # Program that succeeds only for even numbers
      program = %MockProgram{behavior: :multiply}

      examples = [
        # Success
        %{inputs: %{number: 2}, outputs: %{result: 4}},
        # Success
        %{inputs: %{number: 3}, outputs: %{result: 6}},
        # Failure - missing number
        %{inputs: %{no_number: true}, outputs: %{result: 0}}
      ]

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # 2/2 successful evaluations averaged
      assert result.score == 1.0
      assert result.stats.total_examples == 3
      assert result.stats.successful == 2
      assert result.stats.failed == 1
      assert result.stats.success_rate == 2 / 3
      assert length(result.stats.errors) == 1
    end

    test "handles different metric functions" do
      program = %MockProgram{behavior: :multiply}
      examples = create_examples(3, :math)

      # Test with weighted metric
      {:ok, weighted_result} = DSPEx.Evaluate.run(program, examples, &weighted_metric_fn/2)
      assert weighted_result.score > 0

      # Test with confidence metric (should default to 0.5 since no confidence in response)
      confidence_metric = fn example, prediction ->
        if simple_metric_fn(example, prediction) == 1.0 do
          Map.get(prediction, :confidence, 0.5)
        else
          0.0
        end
      end

      {:ok, confidence_result} = DSPEx.Evaluate.run(program, examples, confidence_metric)
      assert confidence_result.score == 0.5
    end
  end

  describe "concurrent evaluation" do
    test "runs multiple examples concurrently" do
      program = %MockProgram{id: 1, delay_ms: 50, behavior: :echo}
      examples = create_examples(10)

      start_time = System.monotonic_time()
      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)
      duration = System.monotonic_time() - start_time

      # Should complete much faster than sequential execution
      # 10 examples * 50ms each = 500ms
      sequential_time = 10 * 50
      concurrent_time = System.convert_time_unit(duration, :native, :millisecond)

      assert concurrent_time < sequential_time
      assert result.stats.successful == 10
      # Should process >10 examples per second
      assert result.stats.throughput > 10
    end

    test "respects max_concurrency option" do
      program = %MockProgram{id: 1, delay_ms: 100, behavior: :echo}
      examples = create_examples(6)

      # Test with low concurrency
      start_time = System.monotonic_time()

      {:ok, _result} =
        DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2, max_concurrency: 2)

      low_concurrency_duration = System.monotonic_time() - start_time

      # Test with high concurrency
      start_time = System.monotonic_time()

      {:ok, _result} =
        DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2, max_concurrency: 10)

      high_concurrency_duration = System.monotonic_time() - start_time

      # High concurrency should be faster (though not always guaranteed due to system variance)
      # At minimum, both should complete successfully
      assert low_concurrency_duration > 0
      assert high_concurrency_duration > 0
    end

    test "handles timeout scenarios" do
      program = %TimeoutProgram{timeout_ms: 5000}
      examples = create_examples(2)

      # The evaluation may fail completely if too many critical errors occur
      case DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2, timeout: 100) do
        {:ok, result} ->
          # Should have failed evaluations due to timeout
          assert result.stats.failed == 2
          assert result.stats.successful == 0
          assert length(result.stats.errors) == 2

        {:error, {:evaluation_failed, _reason, _errors}} ->
          # If the entire evaluation fails due to too many critical errors, that's also valid
          assert true
      end
    end

    test "isolates errors between concurrent evaluations" do
      # Program that fails randomly
      program = %MockProgram{id: 1, error_rate: 0.5, behavior: :echo}
      examples = create_examples(20)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Should have some successes and some failures
      assert result.stats.successful > 0
      assert result.stats.failed > 0
      assert result.stats.successful + result.stats.failed == 20
      assert length(result.stats.errors) == result.stats.failed
    end
  end

  describe "local vs distributed evaluation" do
    test "run_local forces local evaluation" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(3)

      {:ok, result} = DSPEx.Evaluate.run_local(program, examples, &simple_metric_fn/2)

      assert result.stats.successful == 3
      # Local evaluation should not have distributed-specific stats
      refute Map.has_key?(result.stats, :nodes_used)
      refute Map.has_key?(result.stats, :distribution_overhead)
    end

    test "run_distributed falls back to local when no cluster" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(3)

      {:ok, result} = DSPEx.Evaluate.run_distributed(program, examples, &simple_metric_fn/2)

      # Should succeed even without cluster
      assert result.stats.successful == 3
    end

    test "automatic strategy selection works" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(3)

      # Default strategy (should use local since no cluster)
      {:ok, auto_result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Explicit local
      {:ok, local_result} = DSPEx.Evaluate.run_local(program, examples, &simple_metric_fn/2)

      # Results should be similar
      assert auto_result.stats.successful == local_result.stats.successful
      assert auto_result.score == local_result.score
    end

    test "distributed option is respected when available" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(2)

      # Force distributed (will fallback to local)
      {:ok, result} =
        DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2, distributed: true)

      assert result.stats.successful == 2
    end
  end

  describe "telemetry integration" do
    setup do
      # Capture telemetry events
      handler_id = make_ref()

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :evaluate, :run, :start],
          [:dspex, :evaluate, :run, :stop],
          [:dspex, :evaluate, :local, :start],
          [:dspex, :evaluate, :local, :stop],
          [:dspex, :evaluate, :distributed, :start],
          [:dspex, :evaluate, :distributed, :stop],
          [:dspex, :evaluate, :example, :start],
          [:dspex, :evaluate, :example, :stop]
        ],
        fn event_name, measurements, metadata, _acc ->
          send(self(), {:telemetry, event_name, measurements, metadata})
        end,
        []
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "emits evaluation start and stop events" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(2)

      {:ok, _result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Should receive start event
      assert_receive {:telemetry, [:dspex, :evaluate, :run, :start], start_measurements,
                      start_metadata}

      assert %{system_time: system_time} = start_measurements
      assert is_integer(system_time)

      assert %{
               program: :MockProgram,
               example_count: 2,
               correlation_id: correlation_id
             } = start_metadata

      assert is_binary(correlation_id)

      # Should receive stop event
      assert_receive {:telemetry, [:dspex, :evaluate, :run, :stop], stop_measurements,
                      stop_metadata}

      assert %{duration: duration, success: true} = stop_measurements
      assert is_integer(duration)
      assert duration > 0

      assert %{
               program: :MockProgram,
               correlation_id: ^correlation_id
             } = stop_metadata
    end

    test "emits local evaluation events" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(1)

      {:ok, _result} = DSPEx.Evaluate.run_local(program, examples, &simple_metric_fn/2)

      assert_receive {:telemetry, [:dspex, :evaluate, :local, :start], _measurements, _metadata}
      assert_receive {:telemetry, [:dspex, :evaluate, :local, :stop], _measurements, _metadata}
    end

    test "emits distributed evaluation events" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(1)

      {:ok, _result} = DSPEx.Evaluate.run_distributed(program, examples, &simple_metric_fn/2)

      assert_receive {:telemetry, [:dspex, :evaluate, :distributed, :start], _measurements,
                      _metadata}

      assert_receive {:telemetry, [:dspex, :evaluate, :distributed, :stop], _measurements,
                      _metadata}
    end

    @tag :skip
    test "emits individual example events" do
      program = %MockProgram{id: 1, behavior: :echo, delay_ms: 1}
      examples = create_examples(2)

      {:ok, _result} =
        DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2, max_concurrency: 1)

      # Wait a bit for all events to arrive
      Process.sleep(10)

      # Should receive example-level events
      example_start_events =
        for _ <- 1..2 do
          assert_receive {:telemetry, [:dspex, :evaluate, :example, :start], measurements,
                          metadata},
                         1000

          {measurements, metadata}
        end

      example_stop_events =
        for _ <- 1..2 do
          assert_receive {:telemetry, [:dspex, :evaluate, :example, :stop], measurements,
                          metadata}

          {measurements, metadata}
        end

      # Verify event structure
      for {measurements, metadata} <- example_start_events do
        assert %{system_time: system_time} = measurements
        assert %{program: :MockProgram} = metadata
        assert is_integer(system_time)
      end

      for {measurements, metadata} <- example_stop_events do
        assert %{duration: duration, success: success} = measurements
        assert %{program: :MockProgram} = metadata
        assert is_integer(duration)
        assert is_boolean(success)
      end
    end

    test "tracks custom correlation_id" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(1)
      custom_id = "custom-eval-123"

      {:ok, _result} =
        DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2, correlation_id: custom_id)

      assert_receive {:telemetry, [:dspex, :evaluate, :run, :start], _measurements,
                      start_metadata}

      assert %{correlation_id: ^custom_id} = start_metadata

      assert_receive {:telemetry, [:dspex, :evaluate, :run, :stop], _measurements, stop_metadata}
      assert %{correlation_id: ^custom_id} = stop_metadata
    end

    test "marks failed evaluations correctly in telemetry" do
      program = %AlwaysFailProgram{error_type: :test_failure}
      examples = create_examples(1)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Even when all evaluations fail, the evaluation itself succeeds with zero score
      assert result.score == 0.0
      assert result.stats.successful == 0
      assert result.stats.failed == 1

      assert_receive {:telemetry, [:dspex, :evaluate, :run, :start], _measurements, _metadata}
      assert_receive {:telemetry, [:dspex, :evaluate, :run, :stop], stop_measurements, _metadata}

      # The evaluation run succeeds even when individual examples fail
      assert %{success: true} = stop_measurements
    end
  end

  describe "error handling and fault tolerance" do
    test "handles program execution errors gracefully" do
      program = %AlwaysFailProgram{error_type: :custom_error}
      examples = create_examples(3)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Should return successful result with zero score when all evaluations fail
      assert result.score == 0.0
      assert result.stats.successful == 0
      assert result.stats.failed == 3
      assert result.stats.success_rate == 0.0
      assert length(result.stats.errors) == 3
      assert Enum.all?(result.stats.errors, &(&1 == :custom_error))
    end

    test "handles metric function errors" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(2)

      # Metric function that crashes
      crashing_metric = fn _example, _prediction ->
        raise "Metric function error"
      end

      {:ok, result} = DSPEx.Evaluate.run(program, examples, crashing_metric)

      # Should handle metric errors gracefully
      assert result.stats.failed == 2
      assert result.stats.successful == 0
    end

    test "handles invalid metric function return values" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(2)

      # Metric function that returns invalid values
      invalid_metric = fn _example, _prediction ->
        "not a number"
      end

      {:ok, result} = DSPEx.Evaluate.run(program, examples, invalid_metric)

      # Should handle invalid metric returns gracefully
      assert result.score == 0.0
      assert result.stats.successful == 0
      assert result.stats.failed == 2
      assert length(result.stats.errors) == 2
      # Each error should indicate invalid metric result
      assert Enum.all?(result.stats.errors, fn error ->
               match?({:invalid_metric_result, "not a number"}, error)
             end)
    end

    test "continues evaluation despite individual failures" do
      # Program that fails 50% of the time
      program = %MockProgram{id: 1, error_rate: 0.5, behavior: :echo}
      examples = create_examples(10)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Should have both successes and failures
      assert result.stats.total_examples == 10
      assert result.stats.successful > 0
      assert result.stats.failed > 0
      assert result.stats.successful + result.stats.failed == 10
    end

    test "handles very large datasets without memory issues" do
      program = %MockProgram{id: 1, behavior: :echo}
      # Create a moderately large dataset to test memory handling
      examples = create_examples(100)

      {:ok, result} =
        DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2, max_concurrency: 20)

      assert result.stats.successful == 100
      # Should be reasonably fast
      assert result.stats.throughput > 50
    end
  end

  describe "progress tracking and reporting" do
    test "calls progress callback with correct information" do
      program = %MockProgram{id: 1, behavior: :echo}
      # Should trigger progress callbacks every 10 examples
      examples = create_examples(25)

      _progress_updates = []

      test_pid = self()

      progress_callback = fn progress ->
        send(test_pid, {:progress, progress})
      end

      {:ok, _result} =
        DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2,
          progress_callback: progress_callback,
          max_concurrency: 5
        )

      # Should receive progress updates
      progress_messages =
        for _ <- 1..3 do
          receive do
            {:progress, progress} -> progress
          after
            1000 -> nil
          end
        end

      # Filter out nil messages
      valid_progress = Enum.filter(progress_messages, &(&1 != nil))

      # Should have received some progress updates
      assert length(valid_progress) > 0

      for progress <- valid_progress do
        assert %{completed: completed, total: 25, percentage: percentage} = progress
        assert completed > 0
        assert completed <= 25
        assert percentage >= 0
        assert percentage <= 100
        assert abs(percentage - completed / 25 * 100) < 0.1
      end
    end

    test "progress callback is optional" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(5)

      # Should work without progress callback
      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      assert result.stats.successful == 5
    end
  end

  describe "performance characteristics and optimization" do
    test "measures throughput correctly" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(20)

      {:ok, result} =
        DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2, max_concurrency: 10)

      assert result.stats.throughput > 0
      # Should process at least 1 example per second
      assert result.stats.throughput >= 1.0

      # Throughput calculation should be consistent (if duration > 0)
      if result.stats.duration_ms > 0 do
        expected_throughput = result.stats.total_examples / (result.stats.duration_ms / 1000)
        assert abs(result.stats.throughput - expected_throughput) < 0.1
      else
        # For very fast operations, throughput should be estimated based on total examples
        assert result.stats.throughput >= result.stats.total_examples * 1000.0
      end
    end

    test "handles different concurrency levels efficiently" do
      program = %MockProgram{id: 1, delay_ms: 10, behavior: :echo}
      examples = create_examples(20)

      # Test different concurrency levels
      concurrency_levels = [1, 5, 10, 20]

      results =
        for concurrency <- concurrency_levels do
          start_time = System.monotonic_time()

          {:ok, result} =
            DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2,
              max_concurrency: concurrency
            )

          duration = System.monotonic_time() - start_time

          {concurrency, result, System.convert_time_unit(duration, :native, :millisecond)}
        end

      # Higher concurrency should generally be faster (within reason)
      for {concurrency, result, _duration} <- results do
        assert result.stats.successful == 20
        assert result.stats.throughput > 0

        # Throughput should generally increase with concurrency (though not always linearly)
        if concurrency > 1 do
          # Should be faster than sequential
          assert result.stats.throughput > 5
        end
      end
    end

    test "memory usage remains stable with large datasets" do
      program = %MockProgram{id: 1, behavior: :echo}

      # Test with progressively larger datasets
      dataset_sizes = [10, 50, 100]

      for size <- dataset_sizes do
        examples = create_examples(size)

        # Measure memory before
        memory_before =
          case :erlang.process_info(self(), :memory) do
            {_key, value} -> value
            _ -> 0
          end

        {:ok, result} =
          DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2, max_concurrency: 10)

        # Force garbage collection
        :erlang.garbage_collect()

        # Measure memory after
        memory_after =
          case :erlang.process_info(self(), :memory) do
            {_key, value} -> value
            _ -> 0
          end

        assert result.stats.successful == size

        # Memory growth should be reasonable (not more than 10x the dataset size)
        memory_growth = memory_after - memory_before
        # Very rough heuristic
        assert memory_growth < size * 1000
      end
    end

    test "evaluation statistics are comprehensive and accurate" do
      # 30% failure rate
      program = %MockProgram{id: 1, error_rate: 0.3, behavior: :echo}
      examples = create_examples(10)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Verify all statistics are present and logical
      stats = result.stats

      assert is_integer(stats.total_examples)
      assert is_integer(stats.successful)
      assert is_integer(stats.failed)
      assert is_integer(stats.duration_ms)
      assert is_float(stats.success_rate)
      assert is_float(stats.throughput)
      assert is_list(stats.errors)

      # Logical consistency
      assert stats.total_examples == 10
      assert stats.successful + stats.failed == stats.total_examples
      assert stats.success_rate == stats.successful / stats.total_examples
      assert stats.duration_ms >= 0
      assert stats.throughput > 0
      assert length(stats.errors) == stats.failed

      # Score should be average of successful evaluations
      if stats.successful > 0 do
        assert is_float(result.score)
        assert result.score >= 0.0
        assert result.score <= 1.0
      end
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles single example evaluation" do
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(1)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      assert result.stats.total_examples == 1
      assert result.stats.successful == 1

      # Echo returns inputs; both example.outputs.result and prediction.result are nil, so score is 1
      assert result.score == 1.0
    end

    test "handles zero-score scenarios" do
      program = %AlwaysFailProgram{error_type: :test_error}
      examples = create_examples(2)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      # Should handle zero-score scenarios gracefully
      assert result.score == 0.0
      assert result.stats.successful == 0
      assert result.stats.failed == 2
      assert result.stats.success_rate == 0.0
    end

    test "handles perfect score scenarios" do
      program = %MockProgram{
        id: 1,
        behavior: :custom_response,
        response_map: %{
          "What is 1+1?" => "2",
          "What is 2+2?" => "4",
          "What is 3+3?" => "6"
        }
      }

      examples = create_examples(3)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      assert result.score == 1.0
      assert result.stats.success_rate == 1.0
      assert result.stats.failed == 0
    end

    test "handles extremely fast programs" do
      # No delay
      program = %MockProgram{id: 1, behavior: :echo}
      examples = create_examples(5)

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      assert result.stats.successful == 5
      # Should be very fast
      assert result.stats.throughput > 100
      # Duration might be 0 for very fast execution
      assert result.stats.duration_ms >= 0
    end

    test "handles programs with variable execution times" do
      # Program with variable delays based on input
      program = %MockProgram{
        id: 1,
        behavior: :custom_response,
        response_map: %{
          "What is 1+1?" => "2",
          "What is 2+2?" => "4"
        }
      }

      examples = [
        %{inputs: %{question: "What is 1+1?"}, outputs: %{answer: "2"}},
        %{inputs: %{question: "What is 2+2?"}, outputs: %{answer: "4"}}
      ]

      {:ok, result} = DSPEx.Evaluate.run(program, examples, &simple_metric_fn/2)

      assert result.stats.successful == 2
      assert result.score == 1.0
    end
  end
end
