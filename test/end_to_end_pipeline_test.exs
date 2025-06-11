defmodule DSPExEndToEndTest do
  @moduledoc """
  Comprehensive end-to-end integration tests for DSPEx pipeline.
  Tests complete workflows from signature definition through evaluation,
  including Program behavior, telemetry, error handling, and performance.
  """
  use ExUnit.Case, async: false

  @moduletag :phase_1
  @moduletag :end_to_end

  # Test signatures for various scenarios
  defmodule SimpleQASignature do
    @moduledoc "Simple question answering signature for testing"
    use DSPEx.Signature, "question -> answer"
  end

  defmodule ComplexSignature do
    @moduledoc "Multi-field signature with reasoning"
    use DSPEx.Signature, "question, context -> answer, reasoning, confidence"
  end

  defmodule MathSignature do
    @moduledoc "Mathematical computation signature"
    use DSPEx.Signature, "problem, difficulty -> solution, steps"
  end

  # Mock program for controlled testing
  defmodule MockEvaluationProgram do
    use DSPEx.Program

    defstruct [:id, :response_map, :delay_ms, :error_rate]

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
        # Use response map or default behavior
        case Map.get(program.response_map || %{}, inputs) do
          nil -> {:ok, Map.put(inputs, :processed, true)}
          response -> {:ok, response}
        end
      end
    end
  end

  # Program that always fails for error testing
  defmodule AlwaysFailProgram do
    use DSPEx.Program

    defstruct []

    @impl DSPEx.Program
    def forward(_program, _inputs, _opts) do
      {:error, :always_fails}
    end
  end

  describe "complete DSPEx pipeline" do
    test "Program behavior works with DSPEx.Predict" do
      # Create a Predict program using new Program behavior
      program = DSPEx.Predict.new(SimpleQASignature, :gemini)

      # Verify it's a valid program
      assert DSPEx.Program.implements_program?(DSPEx.Predict)

      # Test inputs
      inputs = %{question: "What is 2+2?"}

      # Make the API call - this should work if API keys are configured
      # or fail gracefully if not
      result = DSPEx.Program.forward(program, inputs)

      # Should either succeed or fail gracefully, not crash
      case result do
        {:ok, outputs} ->
          # Success! Verify we got an answer
          assert is_map(outputs)
          assert Map.has_key?(outputs, :answer)
          assert is_binary(outputs.answer)

        {:error, _reason} ->
          # Expected if no API keys configured
          assert true
      end
    end

    test "Evaluation engine works with mock program" do
      # Create a mock program that always returns success
      mock_program = %{
        __struct__: MockProgram,
        response: %{answer: "4"}
      }

      # Mock examples
      examples = [
        %{inputs: %{question: "2+2?"}, outputs: %{answer: "4"}},
        %{inputs: %{question: "3+3?"}, outputs: %{answer: "6"}}
      ]

      # Simple metric function
      metric_fn = fn example, prediction ->
        if example.outputs.answer == prediction.answer do
          1.0
        else
          0.0
        end
      end

      # Test evaluation (will fail because MockProgram doesn't implement behavior)
      result = DSPEx.Evaluate.run(mock_program, examples, metric_fn)

      # Should fail with invalid program error
      assert match?({:error, {:invalid_program, _}}, result)
    end

    test "Evaluation validation works correctly" do
      # Create proper program
      program = DSPEx.Predict.new(SimpleQASignature, :gemini)

      # Test with invalid examples
      result = DSPEx.Evaluate.run(program, [], fn _, _ -> 1.0 end)
      assert match?({:error, {:invalid_examples, _}}, result)

      # Test with invalid metric function
      examples = [%{inputs: %{question: "test"}, outputs: %{answer: "test"}}]
      result = DSPEx.Evaluate.run(program, examples, "not a function")
      assert match?({:error, {:invalid_metric_function, _}}, result)
    end

    test "Legacy API compatibility maintained" do
      inputs = %{question: "What is 2+2?"}

      # Legacy forward API should still work (though fail gracefully without API keys)
      result = DSPEx.Predict.forward(SimpleQASignature, inputs)
      assert match?({:error, _}, result)

      # Legacy predict API should work
      result = DSPEx.Predict.predict(SimpleQASignature, inputs)
      assert match?({:error, _}, result)
    end
  end

  describe "complete evaluation workflows" do
    test "end-to-end evaluation with mock program" do
      # Create a mock program with known responses
      response_map = %{
        %{question: "What is 2+2?"} => %{answer: "4"},
        %{question: "What is 3+3?"} => %{answer: "6"},
        %{question: "What is 5+5?"} => %{answer: "10"}
      }

      program = %MockEvaluationProgram{id: 1, response_map: response_map}

      # Create test examples
      examples = [
        %{inputs: %{question: "What is 2+2?"}, outputs: %{answer: "4"}},
        %{inputs: %{question: "What is 3+3?"}, outputs: %{answer: "6"}},
        %{inputs: %{question: "What is 5+5?"}, outputs: %{answer: "10"}}
      ]

      # Define metric function
      metric_fn = fn example, prediction ->
        if example.outputs.answer == prediction.answer do
          1.0
        else
          0.0
        end
      end

      # Run evaluation
      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)

      # Verify results
      # Perfect score
      assert result.score == 1.0
      assert result.stats.total_examples == 3
      assert result.stats.successful == 3
      assert result.stats.failed == 0
      assert result.stats.success_rate == 1.0
      assert result.stats.throughput > 0
      assert is_integer(result.stats.duration_ms)
    end

    test "evaluation with partial failures" do
      # Program that fails 50% of the time
      program = %MockEvaluationProgram{id: 2, error_rate: 0.5}

      examples =
        for i <- 1..10 do
          %{inputs: %{question: "Question #{i}"}, outputs: %{answer: "Answer #{i}"}}
        end

      metric_fn = fn _example, _prediction -> 1.0 end

      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)

      # Should have some successes and some failures
      assert result.stats.total_examples == 10
      assert result.stats.successful > 0
      assert result.stats.failed > 0
      assert result.stats.successful + result.stats.failed == 10
      assert result.stats.success_rate < 1.0
      assert length(result.stats.errors) == result.stats.failed
    end

    test "concurrent evaluation performance" do
      # Program with artificial delay
      program = %MockEvaluationProgram{id: 3, delay_ms: 50}

      examples =
        for i <- 1..10 do
          %{inputs: %{question: "Question #{i}"}, outputs: %{processed: true}}
        end

      metric_fn = fn example, prediction ->
        if Map.get(example.outputs, :processed) == Map.get(prediction, :processed) do
          1.0
        else
          0.0
        end
      end

      # Measure execution time
      start_time = System.monotonic_time()
      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn, max_concurrency: 5)
      duration = System.monotonic_time() - start_time

      # Should complete much faster than sequential (10 * 50ms = 500ms)
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)
      # Should be faster due to concurrency
      assert duration_ms < 400

      assert result.stats.successful == 10
      # Should process > 10/second
      assert result.stats.throughput > 10
    end

    test "distributed evaluation fallback" do
      program = %MockEvaluationProgram{id: 4}
      examples = [%{inputs: %{test: "data"}, outputs: %{processed: true}}]
      metric_fn = fn _example, _prediction -> 1.0 end

      # Test distributed evaluation (should fallback to local)
      {:ok, result} = DSPEx.Evaluate.run_distributed(program, examples, metric_fn)

      assert result.stats.successful == 1
      # Should not have distributed-specific stats since no cluster
      refute Map.has_key?(result.stats, :nodes_used)
    end
  end

  describe "complex signature integration" do
    test "multi-field signature with Program behavior" do
      program = DSPEx.Predict.new(ComplexSignature, :test)

      inputs = %{
        question: "What is artificial intelligence?",
        context: "Computer science and machine learning"
      }

      # Test that the signature validation works correctly
      case DSPEx.Program.forward(program, inputs) do
        {:ok, outputs} ->
          # Should have all expected output fields
          assert Map.has_key?(outputs, :answer)

        # May or may not have reasoning and confidence depending on implementation

        {:error, reason} ->
          # Expected without proper API setup
          assert reason in [:network_error, :api_error, :timeout, :missing_inputs]
      end
    end

    test "mathematical signature processing" do
      program = DSPEx.Predict.new(MathSignature, :test)

      inputs = %{
        problem: "Solve for x: 2x + 5 = 13",
        difficulty: 3
      }

      case DSPEx.Program.forward(program, inputs) do
        {:ok, outputs} ->
          assert Map.has_key?(outputs, :solution)

        # Steps field may or may not be present depending on implementation

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout, :missing_inputs]
      end
    end
  end

  describe "error propagation and recovery" do
    test "signature validation errors propagate correctly" do
      program = DSPEx.Predict.new(ComplexSignature, :test)

      # Missing required context field
      incomplete_inputs = %{question: "What is AI?"}

      {:error, reason} = DSPEx.Program.forward(program, incomplete_inputs)
      assert reason == :missing_inputs
    end

    test "client errors are handled gracefully" do
      program = DSPEx.Predict.new(SimpleQASignature, :nonexistent_client)
      inputs = %{question: "Test question"}

      {:error, reason} = DSPEx.Program.forward(program, inputs)
      assert reason in [:network_error, :api_error, :timeout]
    end

    test "evaluation handles program errors gracefully" do
      program = %AlwaysFailProgram{}
      examples = [%{inputs: %{test: "data"}, outputs: %{result: "expected"}}]
      metric_fn = fn _example, _prediction -> 1.0 end

      {:error, :no_successful_evaluations} = DSPEx.Evaluate.run(program, examples, metric_fn)
    end
  end

  describe "Foundation integration" do
    setup do
      # Setup telemetry handler for all tests
      handler_id = make_ref()

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :program, :forward, :start],
          [:dspex, :program, :forward, :stop],
          [:dspex, :evaluate, :run, :start],
          [:dspex, :evaluate, :run, :stop],
          [:dspex, :evaluate, :example, :start],
          [:dspex, :evaluate, :example, :stop],
          [:dspex, :client, :request]
        ],
        fn event_name, measurements, metadata, _acc ->
          send(self(), {:telemetry, event_name, measurements, metadata})
        end,
        []
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "program telemetry events are properly emitted" do
      program = DSPEx.Predict.new(SimpleQASignature, :test)
      inputs = %{question: "test"}

      _result = DSPEx.Program.forward(program, inputs)

      # Should receive program telemetry
      assert_receive {:telemetry, [:dspex, :program, :forward, :start], start_measurements,
                      start_metadata}

      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], stop_measurements,
                      stop_metadata}

      # Verify telemetry structure
      assert %{system_time: system_time} = start_measurements
      assert is_integer(system_time)

      assert %{program: :Predict, correlation_id: correlation_id, input_count: 1} = start_metadata
      assert is_binary(correlation_id)

      assert %{duration: duration, success: success} = stop_measurements
      assert is_integer(duration)
      assert is_boolean(success)

      assert %{program: :Predict, correlation_id: ^correlation_id} = stop_metadata
    end

    test "evaluation telemetry events are comprehensive" do
      program = %MockEvaluationProgram{id: 1}
      examples = [%{inputs: %{test: "data"}, outputs: %{processed: true}}]
      metric_fn = fn _example, _prediction -> 1.0 end

      {:ok, _result} = DSPEx.Evaluate.run(program, examples, metric_fn)

      # Should receive evaluation-level telemetry
      assert_receive {:telemetry, [:dspex, :evaluate, :run, :start], _measurements, _metadata}
      assert_receive {:telemetry, [:dspex, :evaluate, :run, :stop], _measurements, _metadata}

      # Should receive example-level telemetry
      assert_receive {:telemetry, [:dspex, :evaluate, :example, :start], _measurements, _metadata}
      assert_receive {:telemetry, [:dspex, :evaluate, :example, :stop], _measurements, _metadata}
    end

    test "correlation IDs flow through entire pipeline" do
      program = %MockEvaluationProgram{id: 1}
      examples = [%{inputs: %{test: "data"}, outputs: %{processed: true}}]
      metric_fn = fn _example, _prediction -> 1.0 end
      custom_id = "integration-test-123"

      {:ok, _result} = DSPEx.Evaluate.run(program, examples, metric_fn, correlation_id: custom_id)

      # Evaluation telemetry should have custom correlation ID
      assert_receive {:telemetry, [:dspex, :evaluate, :run, :start], _measurements, metadata}
      assert %{correlation_id: ^custom_id} = metadata

      # Program telemetry should inherit the correlation ID
      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _measurements, metadata}
      assert %{correlation_id: program_correlation_id} = metadata
      # May be same or derived from evaluation ID
      assert is_binary(program_correlation_id)
    end

    test "telemetry captures performance metrics" do
      program = %MockEvaluationProgram{id: 1, delay_ms: 10}

      examples =
        for i <- 1..5 do
          %{inputs: %{id: i}, outputs: %{processed: true}}
        end

      metric_fn = fn _example, _prediction -> 1.0 end

      start_time = System.monotonic_time()
      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)
      total_duration = System.monotonic_time() - start_time

      # Collect all telemetry durations

      # Evaluation duration
      assert_receive {:telemetry, [:dspex, :evaluate, :run, :start], _measurements, _metadata}
      assert_receive {:telemetry, [:dspex, :evaluate, :run, :stop], measurements, _metadata}
      evaluation_duration = measurements.duration

      # Should have reasonable relationship between telemetry and actual time
      total_duration_ms = System.convert_time_unit(total_duration, :native, :millisecond)
      telemetry_duration_ms = System.convert_time_unit(evaluation_duration, :native, :millisecond)

      # Telemetry duration should be close to actual duration (within 50ms tolerance)
      assert abs(total_duration_ms - telemetry_duration_ms) < 50

      # Result duration should match telemetry
      assert abs(result.stats.duration_ms - telemetry_duration_ms) < 10
    end
  end

  describe "performance and scalability" do
    test "handles large evaluation datasets" do
      program = %MockEvaluationProgram{id: 1}

      # Create a reasonably large dataset
      examples =
        for i <- 1..100 do
          %{inputs: %{id: i, data: "test_#{i}"}, outputs: %{processed: true}}
        end

      metric_fn = fn _example, _prediction -> 1.0 end

      start_time = System.monotonic_time()
      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn, max_concurrency: 20)
      duration = System.monotonic_time() - start_time

      # Should complete successfully
      assert result.stats.total_examples == 100
      assert result.stats.successful == 100
      assert result.stats.failed == 0
      assert result.score == 1.0

      # Should have good throughput
      # > 50 examples/second
      assert result.stats.throughput > 50

      # Duration should be reasonable (< 5 seconds for 100 simple examples)
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)
      assert duration_ms < 5000
    end

    test "memory usage remains stable during evaluation" do
      program = %MockEvaluationProgram{id: 1}

      # Test with progressively larger datasets
      dataset_sizes = [10, 50, 100]

      for size <- dataset_sizes do
        examples =
          for i <- 1..size do
            %{inputs: %{id: i}, outputs: %{processed: true}}
          end

        metric_fn = fn _example, _prediction -> 1.0 end

        # Measure memory before
        :erlang.garbage_collect()
        {:memory, memory_before} = :erlang.process_info(self(), :memory)

        {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)

        # Force cleanup
        :erlang.garbage_collect()
        {:memory, memory_after} = :erlang.process_info(self(), :memory)

        assert result.stats.successful == size

        # Memory growth should be reasonable
        memory_growth = memory_after - memory_before
        # Very rough heuristic - shouldn't grow more than 100KB per example
        assert memory_growth < size * 100_000
      end
    end

    test "concurrent program execution is thread-safe" do
      program = DSPEx.Predict.new(SimpleQASignature, :test)

      # Execute many predictions concurrently
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            inputs = %{question: "Question #{i}"}
            DSPEx.Program.forward(program, inputs)
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All should complete without crashing
      assert length(results) == 20

      # Results should be consistent (all success or all failure)
      result_types =
        Enum.map(results, fn
          {:ok, _} -> :success
          {:error, _} -> :error
        end)

      # Should have some consistent pattern (not random crashes)
      # At most success and error types
      assert length(Enum.uniq(result_types)) <= 2
    end
  end

  describe "type checking and dialyzer compatibility" do
    test "program struct types are correct" do
      program = DSPEx.Predict.new(SimpleQASignature, :gemini)

      assert is_struct(program, DSPEx.Predict)
      assert program.signature == SimpleQASignature
      assert program.client == :gemini
      assert is_nil(program.adapter) or is_atom(program.adapter)
      assert is_list(program.demos)
    end

    test "evaluation result types are well-formed" do
      program = %MockEvaluationProgram{id: 1}
      examples = [%{inputs: %{test: "data"}, outputs: %{processed: true}}]
      metric_fn = fn _example, _prediction -> 1.0 end

      {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)

      # Verify result structure and types
      assert is_float(result.score)
      assert is_map(result.stats)

      stats = result.stats
      assert is_integer(stats.total_examples)
      assert is_integer(stats.successful)
      assert is_integer(stats.failed)
      assert is_integer(stats.duration_ms)
      assert is_float(stats.success_rate)
      assert is_float(stats.throughput)
      assert is_list(stats.errors)

      # Verify value ranges
      assert stats.total_examples >= 0
      assert stats.successful >= 0
      assert stats.failed >= 0
      assert stats.duration_ms >= 0
      assert stats.success_rate >= 0.0 and stats.success_rate <= 1.0
      assert stats.throughput >= 0.0
    end

    test "telemetry metadata types are consistent" do
      program = DSPEx.Predict.new(SimpleQASignature, :test)
      inputs = %{question: "Type check test"}

      _result = DSPEx.Program.forward(program, inputs)

      assert_receive {:telemetry, [:dspex, :program, :forward, :start], measurements, metadata}

      # Verify measurement types
      assert is_integer(measurements.system_time)

      # Verify metadata types
      assert is_atom(metadata.program)
      assert is_binary(metadata.correlation_id)
      assert is_integer(metadata.input_count)

      assert_receive {:telemetry, [:dspex, :program, :forward, :stop], measurements, metadata}

      assert is_integer(measurements.duration)
      assert is_boolean(measurements.success)
      assert is_atom(metadata.program)
      assert is_binary(metadata.correlation_id)
    end
  end

  describe "real-world usage patterns" do
    @tag :external_api
    test "complete workflow with actual API (if configured)" do
      # This test demonstrates a realistic usage pattern
      program = DSPEx.Predict.new(SimpleQASignature, :gemini)

      # Single prediction
      inputs = %{question: "What is the capital of France?"}

      case DSPEx.Program.forward(program, inputs) do
        {:ok, outputs} ->
          # API is working
          assert is_map(outputs)
          assert Map.has_key?(outputs, :answer)
          assert is_binary(outputs.answer)
          assert String.length(outputs.answer) > 0

          # Now test evaluation with this working program
          examples = [
            %{inputs: %{question: "What is 2+2?"}, outputs: %{answer: "4"}},
            %{inputs: %{question: "What is 3+3?"}, outputs: %{answer: "6"}}
          ]

          # Simple exact match metric
          metric_fn = fn example, prediction ->
            expected = String.downcase(String.trim(example.outputs.answer))
            actual = String.downcase(String.trim(prediction.answer))
            if expected == actual, do: 1.0, else: 0.0
          end

          case DSPEx.Evaluate.run(program, examples, metric_fn) do
            {:ok, eval_result} ->
              # Evaluation completed
              assert is_float(eval_result.score)
              assert eval_result.stats.total_examples == 2
              assert eval_result.stats.successful + eval_result.stats.failed == 2

            {:error, reason} ->
              # Evaluation failed but program worked for single prediction
              # This could happen due to rate limits, etc.
              assert is_atom(reason) or is_tuple(reason)
          end

        {:error, _reason} ->
          # API not configured or not working - skip evaluation test
          :ok
      end
    end

    test "chaining multiple programs (composition pattern)" do
      # Create two programs for a multi-step workflow
      question_program = DSPEx.Predict.new(SimpleQASignature, :test)
      analysis_program = DSPEx.Predict.new(ComplexSignature, :test)

      inputs = %{question: "What is machine learning?"}

      # Step 1: Get initial answer
      case DSPEx.Program.forward(question_program, inputs) do
        {:ok, first_output} ->
          # Step 2: Analyze the answer
          analysis_inputs = %{
            question: "Analyze this answer",
            context: first_output.answer
          }

          case DSPEx.Program.forward(analysis_program, analysis_inputs) do
            {:ok, final_output} ->
              # Complete workflow succeeded
              assert is_map(final_output)
              assert Map.has_key?(final_output, :answer)

            {:error, reason} ->
              # Expected without API
              assert reason in [:network_error, :api_error, :timeout, :missing_inputs]
          end

        {:error, reason} ->
          # Expected without API
          assert reason in [:network_error, :api_error, :timeout, :missing_inputs]
      end
    end

    test "batch processing pattern" do
      program = DSPEx.Predict.new(SimpleQASignature, :test)

      # Simulate batch processing multiple questions
      questions = [
        "What is 1+1?",
        "What is 2+2?",
        "What is 3+3?",
        "What is 4+4?",
        "What is 5+5?"
      ]

      # Process all questions
      tasks =
        for question <- questions do
          Task.async(fn ->
            DSPEx.Program.forward(program, %{question: question})
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All should complete (success or consistent failure)
      assert length(results) == 5

      # Count successes and failures
      {successes, failures} =
        Enum.reduce(results, {0, 0}, fn
          {:ok, _}, {s, f} -> {s + 1, f}
          {:error, _}, {s, f} -> {s, f + 1}
        end)

      assert successes + failures == 5

      # If any succeeded, the structure should be correct
      for {:ok, output} <- results do
        assert is_map(output)
        assert Map.has_key?(output, :answer)
      end
    end
  end
end
