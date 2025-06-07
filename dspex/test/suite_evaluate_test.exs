defmodule DSPEx.EvaluateTest do
  use ExUnit.Case, async: false

  defmodule QASignature do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule MockProgram do
    def forward(inputs) do
      case inputs.question do
        "What is 1+1?" -> {:ok, %{answer: "2"}}
        "What is 2+2?" -> {:ok, %{answer: "4"}}
        "What is the capital of France?" -> {:ok, %{answer: "Paris"}}
        "fail" -> {:error, :prediction_failed}
        _ -> {:ok, %{answer: "unknown"}}
      end
    end
  end

  def exact_match_metric(example, prediction) do
    case prediction do
      {:ok, pred} -> if pred.answer == example.answer, do: 1.0, else: 0.0
      {:error, _} -> 0.0
    end
  end

  setup do
    devset = [
      %DSPEx.Example{question: "What is 1+1?", answer: "2"},
      %DSPEx.Example{question: "What is 2+2?", answer: "4"},
      %DSPEx.Example{question: "What is the capital of France?", answer: "Paris"},
      %DSPEx.Example{question: "What is 3+3?", answer: "6"}  # Will be wrong
    ]

    %{devset: devset}
  end

  describe "evaluation initialization" do
    test "creates evaluator with required parameters", %{devset: devset} do
      evaluator = DSPEx.Evaluate.new(
        devset: devset,
        metric: &exact_match_metric/2,
        max_threads: 4
      )

      assert evaluator.devset == devset
      assert is_function(evaluator.metric, 2)
      assert evaluator.max_threads == 4
    end

    test "uses default parameters" do
      evaluator = DSPEx.Evaluate.new(devset: [], metric: fn _, _ -> 1.0 end)

      assert evaluator.max_threads == System.schedulers_online()
      assert evaluator.display_progress == true
    end
  end

  describe "evaluation execution" do
    test "evaluates program on devset", %{devset: devset} do
      evaluator = DSPEx.Evaluate.new(
        devset: devset,
        metric: &exact_match_metric/2,
        max_threads: 2
      )

      results = DSPEx.Evaluate.run(evaluator, MockProgram)

      assert length(results.individual_scores) == 4
      assert results.average_score == 0.75  # 3 correct out of 4
      assert results.total_examples == 4

      # Check individual results
      scores = results.individual_scores
      assert Enum.at(scores, 0) == 1.0  # 1+1=2 correct
      assert Enum.at(scores, 1) == 1.0  # 2+2=4 correct
      assert Enum.at(scores, 2) == 1.0  # Paris correct
      assert Enum.at(scores, 3) == 0.0  # 3+3≠unknown incorrect
    end

    test "handles program failures gracefully", %{devset: devset} do
      failing_devset = devset ++ [%DSPEx.Example{question: "fail", answer: "anything"}]

      evaluator = DSPEx.Evaluate.new(
        devset: failing_devset,
        metric: &exact_match_metric/2
      )

      results = DSPEx.Evaluate.run(evaluator, MockProgram)

      assert length(results.individual_scores) == 5
      assert results.total_examples == 5
      assert List.last(results.individual_scores) == 0.0  # Failed prediction
    end

    test "runs evaluation concurrently", %{devset: devset} do
      # Create a larger dataset to test concurrency
      large_devset = for i <- 1..20 do
        %DSPEx.Example{question: "What is #{i}+#{i}?", answer: "#{i*2}"}
      end

      evaluator = DSPEx.Evaluate.new(
        devset: large_devset,
        metric: fn _example, _prediction ->
          # Add small delay to make concurrency observable
          Process.sleep(10)
          1.0
        end,
        max_threads: 4
      )

      start_time = System.monotonic_time(:millisecond)
      results = DSPEx.Evaluate.run(evaluator, MockProgram)
      end_time = System.monotonic_time(:millisecond)

      duration = end_time - start_time

      # With 4 threads and 20 examples, should be much faster than sequential
      # Sequential would take ~200ms (20 * 10ms), concurrent should be ~50-60ms
      assert duration < 150  # Allow some margin for overhead
      assert results.total_examples == 20
    end

    test "displays progress when enabled" do
      # This would test progress bar functionality
      # Implementation depends on chosen progress bar library
    end
  end

  describe "metric functions" do
    test "supports different metric types" do
      examples = [
        %DSPEx.Example{question: "Test", answer: "correct"},
        %DSPEx.Example{question: "Test2", answer: "wrong"}
      ]

      # Binary metric (0 or 1)
      binary_metric = fn example, {:ok, prediction} ->
        if prediction.answer == example.answer, do: 1, else: 0
      end

      # Continuous metric (0.0 to 1.0)
      similarity_metric = fn example, {:ok, prediction} ->
        String.jaro_distance(example.answer, prediction.answer)
      end

      evaluator_binary = DSPEx.Evaluate.new(devset: examples, metric: binary_metric)
      evaluator_similarity = DSPEx.Evaluate.new(devset: examples, metric: similarity_metric)

      # Both should work
      assert is_struct(evaluator_binary)
      assert is_struct(evaluator_similarity)
    end

    test "handles metric exceptions" do
      failing_metric = fn _example, _prediction ->
        raise "Metric failed"
      end

      evaluator = DSPEx.Evaluate.new(
        devset: [%DSPEx.Example{question: "test", answer: "test"}],
        metric: failing_metric
      )

      results = DSPEx.Evaluate.run(evaluator, MockProgram)

      # Should handle metric failures gracefully
      assert results.total_examples == 1
      assert List.first(results.individual_scores) == 0.0  # Default for failed metric
    end
  end

  describe "result aggregation" do
    test "calculates statistics correctly", %{devset: devset} do
      scores = [1.0, 0.8, 0.6, 0.0]

      evaluator = DSPEx.Evaluate.new(
        devset: devset,
        metric: fn _example, _prediction ->
          Enum.at(scores, length(Process.get(:call_count, [])))
        end
      )

      results = DSPEx.Evaluate.run(evaluator, MockProgram)

      assert results.average_score == 0.6  # (1.0+0.8+0.6+0.0)/4
      assert results.total_examples == 4
      assert length(results.individual_scores) == 4
    end

    test "constructs result table" do
      devset = [
        %DSPEx.Example{question: "Q1", answer: "A1"},
        %DSPEx.Example{question: "Q2", answer: "A2"}
      ]

      evaluator = DSPEx.Evaluate.new(devset: devset, metric: &exact_match_metric/2)
      results = DSPEx.Evaluate.run(evaluator, MockProgram)

      table = DSPEx.Evaluate.construct_result_table(results, devset)

      assert length(table.rows) == 2
      assert table.headers == ["Question", "Expected", "Predicted", "Score"]
    end
  end
end
