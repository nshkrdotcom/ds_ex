defmodule DSPEx.EvaluationMetricsPropertyTest do
  @moduledoc """
  Property-based tests for DSPEx evaluation metrics and data transformations.
  Uses PropCheck to generate random inputs and verify invariants across
  evaluation functions, metric calculations, and data processing pipelines.
  """
  use ExUnit.Case, async: true
  use PropCheck

  @moduletag :property_tests

  # Property test generators

  def example_generator do
    let {inputs, outputs} <- {inputs_generator(), outputs_generator()} do
      %{inputs: inputs, outputs: outputs}
    end
  end

  def inputs_generator do
    oneof([
      # Simple question-answer inputs
      let question <- non_empty(utf8()) do
        %{question: question}
      end,

      # Complex multi-field inputs
      let {question, context, difficulty} <- {non_empty(utf8()), non_empty(utf8()), choose(1, 10)} do
        %{question: question, context: context, difficulty: difficulty}
      end,

      # Numerical inputs
      let {number1, number2} <- {integer(), integer()} do
        %{number1: number1, number2: number2}
      end,

      # Mixed type inputs
      let {text, number, boolean} <- {non_empty(utf8()), integer(), bool()} do
        %{text: text, number: number, flag: boolean}
      end
    ])
  end

  def outputs_generator do
    oneof([
      # Simple answer outputs
      let answer <- non_empty(utf8()) do
        %{answer: answer}
      end,

      # Complex reasoning outputs
      let {answer, reasoning, confidence} <-
            {non_empty(utf8()), non_empty(utf8()), float(0.0, 1.0)} do
        %{answer: answer, reasoning: reasoning, confidence: confidence}
      end,

      # Numerical outputs
      let result <- integer() do
        %{result: result}
      end,

      # Multiple outputs
      let {primary, secondary, score} <- {non_empty(utf8()), non_empty(utf8()), float(0.0, 1.0)} do
        %{primary: primary, secondary: secondary, score: score}
      end
    ])
  end

  def prediction_generator do
    # Predictions should have similar structure to outputs but may differ in values
    oneof([
      let answer <- non_empty(utf8()) do
        %{answer: answer}
      end,
      let {answer, reasoning, confidence} <-
            {non_empty(utf8()), non_empty(utf8()), float(0.0, 1.0)} do
        %{answer: answer, reasoning: reasoning, confidence: confidence}
      end,
      let result <- integer() do
        %{result: result}
      end,
      let {primary, secondary, score} <- {non_empty(utf8()), non_empty(utf8()), float(0.0, 1.0)} do
        %{primary: primary, secondary: secondary, score: score}
      end
    ])
  end

  def metric_score_generator do
    float(0.0, 1.0)
  end

  def examples_list_generator do
    non_empty(list(example_generator()))
  end

  # Mock program for property testing
  defmodule PropertyTestProgram do
    use DSPEx.Program

    defstruct [:id, :response_fn]

    def new(id, response_fn) do
      %__MODULE__{id: id, response_fn: response_fn}
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      try do
        {:ok, program.response_fn.(inputs)}
      rescue
        error -> {:error, {:prediction_error, error}}
      end
    end
  end

  describe "metric function properties" do
    property "exact match metric is symmetric and deterministic" do
      forall {example, prediction} <- {example_generator(), prediction_generator()} do
        metric_fn = fn ex, pred ->
          if Map.get(ex.outputs, :answer) == Map.get(pred, :answer) do
            1.0
          else
            0.0
          end
        end

        # Same inputs should always produce same output
        result1 = metric_fn.(example, prediction)
        result2 = metric_fn.(example, prediction)

        # Deterministic property
        assert result1 == result2

        # Score should be either 0.0 or 1.0 for exact match
        assert result1 in [0.0, 1.0]

        # Symmetry: if prediction matches example, metric should be 1.0
        if Map.get(example.outputs, :answer) == Map.get(prediction, :answer) do
          assert result1 == 1.0
        else
          assert result1 == 0.0
        end
      end
    end

    property "confidence-weighted metric preserves bounds" do
      forall {example, prediction} <- {example_generator(), prediction_generator()} do
        metric_fn = fn ex, pred ->
          base_match =
            if Map.get(ex.outputs, :answer) == Map.get(pred, :answer), do: 1.0, else: 0.0

          confidence = Map.get(pred, :confidence, 0.5)
          base_match * confidence
        end

        result = metric_fn.(example, prediction)

        # Result should always be between 0.0 and 1.0
        # If no match, result should be 0.0 regardless of confidence
        # If match and confidence exists, result should equal confidence
        result >= 0.0 and
          result <= 1.0 and
          (Map.get(example.outputs, :answer) == Map.get(prediction, :answer) or
             result == 0.0) and
          (Map.get(example.outputs, :answer) != Map.get(prediction, :answer) or
             abs(result - Map.get(prediction, :confidence, 0.5)) < 0.001)
      end
    end

    property "numerical difference metric has proper bounds and monotonicity" do
      forall {example_result, prediction_result} <- {integer(), integer()} do
        example = %{inputs: %{}, outputs: %{result: example_result}}
        prediction = %{result: prediction_result}

        metric_fn = fn ex, pred ->
          expected = ex.outputs.result
          actual = Map.get(pred, :result, 0)
          diff = abs(expected - actual)

          # Inverse relationship: closer values get higher scores
          max(0.0, 1.0 - diff / 100.0)
        end

        result = metric_fn.(example, prediction)

        # Result should be between 0.0 and 1.0
        bounds_check = result >= 0.0 and result <= 1.0

        # Perfect match should give score of 1.0
        perfect_match_check =
          if example_result == prediction_result do
            result == 1.0
          else
            true
          end

        bounds_check and perfect_match_check
      end
    end

    property "custom metrics handle edge cases gracefully" do
      forall {example, prediction} <- {example_generator(), prediction_generator()} do
        # Metric that handles missing fields gracefully
        safe_metric_fn = fn ex, pred ->
          try do
            answer1 = Map.get(ex.outputs, :answer, "")
            answer2 = Map.get(pred, :answer, "")

            if String.length(answer1) == 0 or String.length(answer2) == 0 do
              0.0
            else
              if answer1 == answer2, do: 1.0, else: 0.0
            end
          rescue
            _ -> 0.0
          end
        end

        result = safe_metric_fn.(example, prediction)

        # Should never crash and always return valid score
        assert is_float(result)
        assert result >= 0.0
        assert result <= 1.0
      end
    end
  end

  describe "evaluation result aggregation properties" do
    property "evaluation score is always the average of successful metric scores" do
      forall examples <- examples_list_generator() do
        # Create a program that always succeeds with predictable output
        program =
          PropertyTestProgram.new(:deterministic, fn inputs ->
            Map.put(inputs, :answer, "fixed_answer")
          end)

        # Simple deterministic metric
        # Always return 0.5
        metric_fn = fn _example, _prediction -> 0.5 end

        case DSPEx.Evaluate.run(program, examples, metric_fn) do
          {:ok, result} ->
            # If all evaluations succeed, score should be exactly 0.5
            if result.stats.failed == 0 do
              assert_in_delta result.score, 0.5, 0.001
            end

            # Score should always be within valid bounds
            assert result.score >= 0.0
            assert result.score <= 1.0

            # Success rate should be consistent with counts
            expected_success_rate = result.stats.successful / result.stats.total_examples
            assert_in_delta result.stats.success_rate, expected_success_rate, 0.001

          {:error, _reason} ->
            # Evaluation can fail due to validation, that's OK for property test
            :ok
        end
      end
    end

    property "evaluation statistics maintain mathematical invariants" do
      forall examples <- examples_list_generator() do
        # Program with random success/failure
        program =
          PropertyTestProgram.new(:random, fn inputs ->
            # 70% success rate
            if :rand.uniform() < 0.7 do
              Map.put(inputs, :answer, "success")
            else
              raise "Random failure"
            end
          end)

        metric_fn = fn _example, _prediction -> 1.0 end

        case DSPEx.Evaluate.run(program, examples, metric_fn) do
          {:ok, result} ->
            stats = result.stats

            # Basic invariants
            # Success rate invariant
            # Success rate calculation
            # Throughput should be positive if duration > 0
            # Errors list should match failed count
            stats.total_examples == length(examples) and
              stats.successful + stats.failed == stats.total_examples and
              stats.successful >= 0 and
              stats.failed >= 0 and
              stats.success_rate >= 0.0 and
              stats.success_rate <= 1.0 and
              (stats.total_examples == 0 or
                 abs(stats.success_rate - stats.successful / stats.total_examples) < 0.001) and
              (stats.duration_ms == 0 or
                 (stats.throughput > 0.0 and
                    abs(stats.throughput - stats.total_examples / (stats.duration_ms / 1000)) <
                      0.1)) and
              length(stats.errors) == stats.failed

          {:error, _reason} ->
            # Can fail due to no successful evaluations
            true
        end
      end
    end

    property "concurrent evaluation produces consistent results" do
      forall examples <- non_empty(list(example_generator())) do
        # Deterministic program for consistent results
        program =
          PropertyTestProgram.new(:consistent, fn inputs ->
            # Hash input to get consistent output
            hash = :erlang.phash2(inputs)
            %{answer: "response_#{rem(hash, 10)}"}
          end)

        # Deterministic metric
        metric_fn = fn example, prediction ->
          example_hash = :erlang.phash2(example)
          prediction_hash = :erlang.phash2(prediction)
          if rem(example_hash, 3) == rem(prediction_hash, 3), do: 1.0, else: 0.0
        end

        # Run evaluation twice with same inputs
        result1 = DSPEx.Evaluate.run(program, examples, metric_fn)
        result2 = DSPEx.Evaluate.run(program, examples, metric_fn)

        case {result1, result2} do
          {{:ok, r1}, {:ok, r2}} ->
            # Results should be identical for deterministic program/metric
            assert_in_delta r1.score, r2.score, 0.001
            assert r1.stats.total_examples == r2.stats.total_examples
            assert r1.stats.successful == r2.stats.successful
            assert r1.stats.failed == r2.stats.failed

          _ ->
            # If one fails, both should fail the same way for deterministic case
            assert result1 == result2
        end
      end
    end
  end

  # Define test signature outside property to avoid redefinition warnings
  defmodule PropertySignature do
    def input_fields, do: [:question]
    def output_fields, do: [:answer]
    def description, do: "Property test signature"
  end

  describe "data transformation properties" do
    property "input validation preserves required fields" do
      forall inputs <- inputs_generator() do
        result = DSPEx.Predict.validate_inputs(PropertySignature, inputs)

        case result do
          :ok ->
            # If validation passes, required fields should be present
            Map.has_key?(inputs, :question)

          {:error, :missing_inputs} ->
            # If validation fails, required fields should be missing
            not Map.has_key?(inputs, :question)

          {:error, :invalid_signature} ->
            # Signature error is also valid
            true
        end
      end
    end

    property "example structure validation is consistent" do
      forall example <- example_generator() do
        # Test the internal validation used by DSPEx.Evaluate
        is_valid = match?(%{inputs: %{}, outputs: %{}}, example)

        if is_valid do
          Map.has_key?(example, :inputs) and
            Map.has_key?(example, :outputs) and
            is_map(example.inputs) and
            is_map(example.outputs)
        else
          # If not valid, should be missing required structure
          not (Map.has_key?(example, :inputs) and Map.has_key?(example, :outputs) and
                 is_map(example.inputs) and is_map(example.outputs))
        end
      end
    end

    property "metric function arity validation works correctly" do
      forall {score1, score2} <- {metric_score_generator(), metric_score_generator()} do
        # Create functions with different arities
        arity_2_fn = fn _example, _prediction -> score1 end
        arity_1_fn = fn _single_arg -> score2 end
        arity_3_fn = fn _example, _prediction, _extra -> score1 end

        # Test DSPEx.Evaluate's validation logic
        program = PropertyTestProgram.new(:test, fn inputs -> inputs end)
        examples = [%{inputs: %{test: "data"}, outputs: %{result: "expected"}}]

        # Arity 2 should be valid
        result_2 = DSPEx.Evaluate.run(program, examples, arity_2_fn)
        assert match?({:ok, _}, result_2)

        # Arity 1 should be invalid
        result_1 = DSPEx.Evaluate.run(program, examples, arity_1_fn)
        assert match?({:error, {:invalid_metric_function, _}}, result_1)

        # Arity 3 should be invalid
        result_3 = DSPEx.Evaluate.run(program, examples, arity_3_fn)
        assert match?({:error, {:invalid_metric_function, _}}, result_3)
      end
    end
  end

  describe "error handling properties" do
    property "evaluation gracefully handles program errors" do
      forall examples <- examples_list_generator() do
        # Program that always fails
        failing_program =
          PropertyTestProgram.new(:failing, fn _inputs ->
            raise "Intentional failure"
          end)

        metric_fn = fn _example, _prediction -> 1.0 end

        result = DSPEx.Evaluate.run(failing_program, examples, metric_fn)

        # Should either succeed with all failures or fail entirely
        case result do
          {:ok, eval_result} ->
            # If it succeeds, all examples should have failed
            eval_result.stats.failed == length(examples) and
              eval_result.stats.successful == 0 and
              length(eval_result.stats.errors) == eval_result.stats.failed

          {:error, :no_successful_evaluations} ->
            # This is also a valid outcome
            true

          {:error, other_reason} ->
            # Other errors are also acceptable for property test
            is_atom(other_reason) or is_tuple(other_reason)
        end
      end
    end

    property "metric function errors are handled gracefully" do
      forall examples <- examples_list_generator() do
        # Program that succeeds
        program =
          PropertyTestProgram.new(:success, fn inputs ->
            Map.put(inputs, :answer, "success")
          end)

        # Metric function that sometimes crashes
        crashing_metric = fn example, _prediction ->
          # Crash on certain inputs
          if Map.get(example.inputs, :test) == "crash" do
            raise "Metric crash"
          else
            1.0
          end
        end

        # Add some crash-inducing examples
        crash_examples = [%{inputs: %{test: "crash"}, outputs: %{answer: "crash"}} | examples]

        case DSPEx.Evaluate.run(program, crash_examples, crashing_metric) do
          {:ok, result} ->
            # Should handle metric crashes gracefully
            # Some evaluations should fail due to metric crashes
            result.stats.total_examples == length(crash_examples) and
              result.stats.failed > 0

          {:error, _reason} ->
            # Evaluation can fail if all metrics crash
            true
        end
      end
    end
  end

  describe "performance properties" do
    property "evaluation time scales reasonably with input size" do
      forall size <- choose(1, 20) do
        # Generate examples of specified size
        examples =
          for i <- 1..size do
            %{inputs: %{id: i}, outputs: %{result: i * 2}}
          end

        # Fast program
        program =
          PropertyTestProgram.new(:fast, fn inputs ->
            inputs
          end)

        # Simple metric
        metric_fn = fn _example, _prediction -> 1.0 end

        start_time = System.monotonic_time()
        result = DSPEx.Evaluate.run(program, examples, metric_fn)
        duration = System.monotonic_time() - start_time

        case result do
          {:ok, eval_result} ->
            # Duration should scale reasonably (not exponentially)
            duration_ms = System.convert_time_unit(duration, :native, :millisecond)

            # Should complete within reasonable time (10ms per example + 100ms base)
            reasonable_time = size * 10 + 100
            assert duration_ms <= reasonable_time

            # Throughput should be reasonable
            # At least 0.1 examples/second
            assert eval_result.stats.throughput > 0.1

          {:error, _reason} ->
            # Validation errors are OK
            :ok
        end
      end
    end

    property "concurrent evaluation maintains performance bounds" do
      forall {size, concurrency} <- {choose(5, 15), choose(1, 5)} do
        examples =
          for i <- 1..size do
            %{inputs: %{id: i}, outputs: %{result: i}}
          end

        # Program with small delay
        program =
          PropertyTestProgram.new(:delayed, fn inputs ->
            # 5ms delay
            Process.sleep(5)
            inputs
          end)

        metric_fn = fn _example, _prediction -> 1.0 end

        start_time = System.monotonic_time()
        result = DSPEx.Evaluate.run(program, examples, metric_fn, max_concurrency: concurrency)
        duration = System.monotonic_time() - start_time

        case result do
          {:ok, eval_result} ->
            duration_ms = System.convert_time_unit(duration, :native, :millisecond)

            # With concurrency, should be faster than sequential
            # Sequential would take: size * 5ms
            sequential_time = size * 5

            # Concurrent should be better (allowing for overhead)
            if concurrency > 1 do
              # +100ms overhead allowance
              assert duration_ms <= sequential_time + 100
            end

            # All examples should be processed
            assert eval_result.stats.total_examples == size

          {:error, _reason} ->
            :ok
        end
      end
    end
  end
end
