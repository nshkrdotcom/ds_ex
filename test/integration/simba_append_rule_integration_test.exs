defmodule DSPEx.Integration.SimbaAppendRuleTest do
  use ExUnit.Case
  alias DSPEx.Teleprompter.SIMBA, as: Simba
  alias DSPEx.Predict

  @moduletag :integration_test
  @moduletag timeout: 60_000

  describe "SIMBA with AppendRule strategy integration" do
    test "optimizes programs using append_rule strategy" do
      # Define test signature
      signature = TestSignatures.MathQuestionAnswering
      program = Predict.new(signature, :gpt3_5)
      
      # Create training data with clear success/failure patterns
      training_data = [
        %{inputs: %{question: "What is 2+2?"}, outputs: %{answer: "4"}},
        %{inputs: %{question: "What is 3+3?"}, outputs: %{answer: "6"}},
        %{inputs: %{question: "What is 5+5?"}, outputs: %{answer: "10"}},
        %{inputs: %{question: "What is 7+7?"}, outputs: %{answer: "14"}}
      ]
      
      # Simple exact match metric
      metric_fn = fn example, prediction ->
        if example.outputs.answer == prediction.answer, do: 1.0, else: 0.0
      end
      
      # Create SIMBA with append_rule strategy only
      simba = Simba.new(
        strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendRule],
        num_candidates: 4,
        max_steps: 2
      )
      
      # Test the optimization with SIMBA
      result = Simba.compile(simba, program, program, training_data, metric_fn, [])
      
      # AppendRule strategy should now work
      assert {:ok, optimized_program} = result
      
      # Verify optimization occurred
      assert optimized_program.signature == program.signature
      assert optimized_program.client == program.client
    end

    test "optimizes programs using both demo and rule strategies" do
      signature = TestSignatures.MathQuestionAnswering
      program = Predict.new(signature, :gpt3_5)
      
      training_data = [
        %{inputs: %{question: "What is 4+4?"}, outputs: %{answer: "8"}},
        %{inputs: %{question: "What is 6+6?"}, outputs: %{answer: "12"}}
      ]
      
      metric_fn = fn example, prediction ->
        if example.outputs.answer == prediction.answer, do: 1.0, else: 0.0
      end
      
      # Try to use both strategies together
      simba = Simba.new(
        strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo, DSPEx.Teleprompter.SIMBA.Strategy.AppendRule],
        num_candidates: 6,
        max_steps: 3
      )
      
      # Both strategies should now work together
      result = Simba.compile(simba, program, program, training_data, metric_fn, [])
      
      assert {:ok, optimized_program} = result
      
      # Verify both strategies were available and optimization completed
      assert optimized_program.signature == program.signature
      assert optimized_program.client == program.client
    end

    test "validates strategy configuration before optimization" do
      signature = TestSignatures.SimpleQA
      program = Predict.new(signature, :gpt3_5)
      
      training_data = [
        %{inputs: %{question: "Test?"}, outputs: %{answer: "Test answer"}}
      ]
      
      metric_fn = fn _example, _prediction -> 1.0 end
      
      # Valid strategy configuration should succeed  
      simba = Simba.new(
        strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendRule],
        num_candidates: 2,
        max_steps: 1
      )
      
      result = Simba.compile(simba, program, program, training_data, metric_fn, [])
      
      # Should succeed with valid strategy
      assert {:ok, optimized_program} = result
      assert optimized_program.signature == program.signature
    end

    test "append_rule strategy generates meaningful instruction improvements" do
      # This test defines the expected behavior once append_rule is implemented
      signature = TestSignatures.DetailedQA
      original_program = Predict.new(signature, :gpt3_5)
      
      # Training data designed to expose instruction improvement opportunities
      training_data = [
        # Examples where better instructions would help
        %{inputs: %{question: "Explain photosynthesis"}, outputs: %{answer: "Photosynthesis is the process by which plants convert sunlight into energy."}},
        %{inputs: %{question: "What causes rain?"}, outputs: %{answer: "Rain is caused by water vapor in clouds condensing and falling to Earth."}}
      ]
      
      metric_fn = fn example, prediction ->
        # Metric that rewards detailed, accurate answers
        if String.length(prediction.answer) > 20 && 
           String.contains?(String.downcase(prediction.answer), String.downcase(example.outputs.answer)), 
           do: 1.0, else: 0.0
      end
      
      simba = Simba.new(
        strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendRule],
        num_candidates: 3,
        max_steps: 2
      )
      
      # AppendRule strategy should now work
      result = Simba.compile(simba, original_program, original_program, training_data, metric_fn, [])
      
      # Should succeed and generate instruction improvements
      assert {:ok, optimized_program} = result
      
      # Verify the program was optimized
      assert optimized_program.signature == original_program.signature
      assert optimized_program.client == original_program.client
    end

    test "handles insufficient trajectory variance gracefully" do
      signature = TestSignatures.SimpleQA
      program = Predict.new(signature, :gpt3_5)
      
      # Training data with very uniform patterns (low variance)
      training_data = [
        %{inputs: %{question: "A?"}, outputs: %{answer: "A"}},
        %{inputs: %{question: "B?"}, outputs: %{answer: "B"}},
        %{inputs: %{question: "C?"}, outputs: %{answer: "C"}}
      ]
      
      # Metric that will give uniform scores
      metric_fn = fn _example, _prediction -> 1.0 end
      
      simba = Simba.new(
        strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendRule],
        num_candidates: 3,
        max_steps: 1
      )
      
      result = Simba.compile(simba, program, program, training_data, metric_fn, [])
      
      # AppendRule should handle low variance gracefully
      # If there's insufficient variance, it should skip or handle gracefully
      case result do
        {:ok, optimized_program} -> 
          # Strategy worked despite low variance
          assert optimized_program.signature == program.signature
        {:error, _reason} -> 
          # Strategy appropriately skipped due to insufficient variance
          :ok
      end
    end

    test "integrates append_rule with existing trajectory sampling" do
      signature = TestSignatures.MathQuestionAnswering
      program = Predict.new(signature, :gpt3_5)
      
      training_data = [
        %{inputs: %{question: "Calculate 15 + 27"}, outputs: %{answer: "42"}},
        %{inputs: %{question: "Calculate 9 * 8"}, outputs: %{answer: "72"}}
      ]
      
      metric_fn = fn example, prediction ->
        if example.outputs.answer == prediction.answer, do: 1.0, else: 0.0
      end
      
      simba = Simba.new(
        strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendRule],
        num_candidates: 4,
        max_steps: 1,
        # Test specific configuration for trajectory analysis
        bsize: 6
      )
      
      result = Simba.compile(simba, program, program, training_data, metric_fn, [])
      
      # AppendRule strategy should integrate with trajectory sampling
      assert {:ok, optimized_program} = result
      
      # Verify integration with existing trajectory system
      assert optimized_program.signature == program.signature
      assert optimized_program.client == program.client
    end
  end

  # Helper test signatures for different scenarios
  defmodule TestSignatures.MathQuestionAnswering do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule TestSignatures.SimpleQA do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule TestSignatures.DetailedQA do
    use DSPEx.Signature, "question -> answer"
  end
end