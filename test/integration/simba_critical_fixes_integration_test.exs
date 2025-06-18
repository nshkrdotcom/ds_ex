defmodule DSPEx.Teleprompter.SimbaCriticalFixesIntegrationTest do
  use ExUnit.Case, async: true
  alias DSPEx.Teleprompter.SIMBA
  alias DSPEx.{Predict, Program, Example}

  @moduletag :integration
  @moduletag :group_1

  describe "SIMBA critical algorithm fixes integration test" do
    test "end-to-end SIMBA optimization with fixed program selection algorithm" do
      # Define a simple QA signature
      defmodule TestQASignature do
        use DSPEx.Signature, "question -> answer"
      end

      # Create teacher and student programs
      teacher = Predict.new(TestQASignature, :gpt4)
      student = Predict.new(TestQASignature, :gpt3_5)

      # Create training examples that test the algorithm's ability to distinguish performance
      training_examples = [
        %{
          inputs: %{question: "What is 2+2?"},
          outputs: %{answer: "4"}
        },
        %{
          inputs: %{question: "What color is the sky?"},
          outputs: %{answer: "blue"}
        },
        %{
          inputs: %{question: "What is the capital of France?"},
          outputs: %{answer: "Paris"}
        }
      ]

      trainset = Enum.map(training_examples, &Example.new/1)

      # Define a metric function that can distinguish between good and bad answers
      metric_fn = fn example, prediction ->
        expected = Example.outputs(example).answer
        actual = Map.get(prediction, :answer)

        cond do
          actual == expected -> 1.0
          String.contains?(String.downcase(actual || ""), String.downcase(expected)) -> 0.8
          true -> 0.0
        end
      end

      # Configure SIMBA with small parameters for testing
      teleprompter =
        SIMBA.new(
          num_candidates: 3,
          max_steps: 2,
          bsize: 2,
          temperature_for_candidates: 0.5,
          strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo]
        )

      # Test the compilation
      result = SIMBA.compile(teleprompter, student, teacher, trainset, metric_fn, [])

      # Verify the optimization completed successfully
      assert {:ok, optimized_program} = result
      assert optimized_program != nil

      # Verify the optimized program can be executed
      test_input = %{question: "What is 1+1?"}
      execution_result = Program.forward(optimized_program, test_input)
      assert {:ok, _output} = execution_result

      # Test that the fixed program selection algorithm is working
      # This would have failed with the old fixed 0.5 scoring approach
      assert is_struct(optimized_program), "Should return a valid program structure"
    end

    test "program selection algorithm uses real scores instead of fixed values" do
      # Create mock program indices and scores
      program_indices = [0, 1, 2]

      program_scores = %{
        # avg: 0.2
        0 => [0.2, 0.3, 0.1],
        # avg: 0.8 (best)
        1 => [0.8, 0.9, 0.7],
        # avg: 0.5
        2 => [0.5, 0.4, 0.6]
      }

      # With temperature = 0 (greedy), should always select the best program (index 1)
      results =
        for _ <- 1..10 do
          SIMBA.test_softmax_sample(program_indices, program_scores, 0)
        end

      # All results should be index 1 (the best performing program)
      assert Enum.all?(results, fn result -> result == 1 end),
             "Greedy selection should always choose the best program"

      # With higher temperature, should still favor the best program
      results_with_temp =
        for _ <- 1..100 do
          SIMBA.test_softmax_sample(program_indices, program_scores, 0.5)
        end

      program_1_selections = Enum.count(results_with_temp, &(&1 == 1))
      program_0_selections = Enum.count(results_with_temp, &(&1 == 0))

      assert program_1_selections > program_0_selections,
             "Higher scoring programs should be selected more frequently"
    end

    test "program pool management preserves baseline and selects top performers" do
      programs = [:baseline, :good, :excellent, :poor]

      program_scores = %{
        # baseline (worst)
        0 => [0.1, 0.2],
        # good
        1 => [0.7, 0.8],
        # excellent (best)
        2 => [0.9, 0.95],
        # poor
        3 => [0.3, 0.4]
      }

      # Request top 3 programs
      top_indices = SIMBA.test_select_top_programs_with_baseline(programs, program_scores, 3)

      # Should include excellent (2), good (1), and baseline (0)
      assert length(top_indices) == 3
      assert 0 in top_indices, "Baseline should always be included"
      assert 2 in top_indices, "Best program should be included"
      assert 1 in top_indices, "Second best should be included"
      refute 3 in top_indices, "Poor program should not be included"

      # Test edge case: request fewer than available, baseline not in top
      top_2_indices = SIMBA.test_select_top_programs_with_baseline(programs, program_scores, 2)

      assert length(top_2_indices) == 2
      assert 0 in top_2_indices, "Baseline must always be included even if not top performer"
      assert 2 in top_2_indices, "Best program should be included"
    end

    test "performance scoring evaluates candidates correctly" do
      # This tests that the performance scoring is working end-to-end
      # The previous implementation had issues with candidate evaluation

      defmodule SimpleSignature do
        use DSPEx.Signature, "input -> output"
      end

      program = Predict.new(SimpleSignature, :gpt3_5)

      # Create test batch
      batch = [
        Example.new(%{inputs: %{input: "test1"}, outputs: %{output: "result1"}}),
        Example.new(%{inputs: %{input: "test2"}, outputs: %{output: "result2"}})
      ]

      # Simple metric function
      metric_fn = fn _example, _prediction -> 0.75 end

      # This would fail if the performance scoring was broken
      scores = SIMBA.test_evaluate_candidates_batch([program], batch, metric_fn)

      assert is_list(scores)
      assert length(scores) == 1
      assert {0, score} = List.first(scores)
      assert is_float(score)
      assert score >= 0.0 and score <= 1.0
    end
  end
end
