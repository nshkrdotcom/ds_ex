defmodule DSPEx.Teleprompter.SIMBA.Strategy.AppendRuleTest do
  use ExUnit.Case
  alias DSPEx.Teleprompter.SIMBA.Strategy.AppendRule
  alias DSPEx.Teleprompter.SIMBA.{Trajectory, Bucket}

  describe "AppendRule strategy" do
    test "implements strategy behavior interface" do
      assert function_exported?(AppendRule, :applicable?, 2)
      assert function_exported?(AppendRule, :apply, 3)
      assert function_exported?(AppendRule, :strategy_name, 0)
    end

    test "strategy_name returns correct identifier" do
      assert AppendRule.strategy_name() == :append_rule
    end

    test "applicable? returns true when trajectory variance exists" do
      # Create trajectories with different success patterns
      successful_trajectory = %Trajectory{
        program: create_test_program(),
        example: create_test_example(),
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"},
        score: 1.0,
        success: true,
        error: nil
      }
      
      failed_trajectory = %Trajectory{
        program: create_test_program(),
        example: create_test_example(),
        inputs: %{question: "What is 3+3?"},
        outputs: %{answer: "wrong answer"},
        score: 0.0,
        success: false,
        error: nil
      }

      bucket = Bucket.new([successful_trajectory, failed_trajectory])

      context = %{buckets: [bucket], current_program: create_test_program()}
      
      assert AppendRule.applicable?(bucket, context)
    end

    test "applicable? returns false when insufficient trajectory data" do
      # Empty bucket should not be applicable
      empty_bucket = Bucket.new([])

      context = %{buckets: [], current_program: create_test_program()}
      
      refute AppendRule.applicable?(empty_bucket, context)
    end

    test "applicable? returns false when all trajectories have same success pattern" do
      # All successful trajectories - no variance for rule generation
      trajectory1 = %Trajectory{
        program: create_test_program(),
        example: create_test_example(),
        inputs: %{question: "What is 4+4?"},
        outputs: %{answer: "8"},
        score: 1.0,
        success: true,
        error: nil
      }
      
      trajectory2 = %Trajectory{
        program: create_test_program(),
        example: create_test_example(),
        inputs: %{question: "What is 5+5?"},
        outputs: %{answer: "10"},
        score: 1.0,
        success: true,
        error: nil
      }

      bucket = Bucket.new([trajectory1, trajectory2])

      context = %{buckets: [bucket], current_program: create_test_program()}
      
      refute AppendRule.applicable?(bucket, context)
    end

    test "apply generates instruction improvements from trajectory analysis" do
      # Create contrasting trajectories for rule generation
      successful_trajectory = %Trajectory{
        program: create_test_program(),
        example: %{inputs: %{question: "What is 2+2?"}, outputs: %{answer: "4"}},
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"},
        score: 1.0,
        success: true,
        error: nil
      }
      
      failed_trajectory = %Trajectory{
        program: create_test_program(),
        example: %{inputs: %{question: "What is 3+3?"}, outputs: %{answer: "6"}},
        inputs: %{question: "What is 3+3?"},
        outputs: %{answer: "seven"},
        score: 0.0,
        success: false,
        error: nil
      }

      bucket = Bucket.new([successful_trajectory, failed_trajectory])

      source_program = create_test_program()
      opts = %{
        buckets: [bucket], 
        client: create_test_client()
      }

      {:ok, enhanced_program} = AppendRule.apply(bucket, source_program, opts)
      
      # Verify the program has been enhanced with new instruction
      assert enhanced_program.instruction != source_program.instruction
      assert String.length(enhanced_program.instruction) > String.length(source_program.instruction)
      
      # Verify instruction contains improvement guidance
      keywords = ["precise", "double-check", "calculations", "arithmetic"]
      assert Enum.any?(keywords, fn keyword -> String.contains?(enhanced_program.instruction, keyword) end)
    end

    test "apply handles LLM response parsing errors gracefully" do
      bucket = create_test_bucket_with_variance()
      source_program = create_test_program()
      
      # Mock opts with client that returns malformed response
      opts = %{
        buckets: [bucket],
        client: create_failing_test_client()
      }

      result = AppendRule.apply(bucket, source_program, opts)
      
      # Should return skip tuple when LLM response is malformed
      assert {:skip, reason} = result
      assert String.contains?(reason, ["parse", "format", "response"])
    end

    test "apply integrates with OfferFeedback signature correctly" do
      bucket = create_test_bucket_with_variance()
      source_program = create_test_program()
      opts = %{
        buckets: [bucket],
        client: create_test_client()
      }

      {:ok, enhanced_program} = AppendRule.apply(bucket, source_program, opts)
      
      # Verify the enhanced program maintains signature compatibility
      assert enhanced_program.signature == source_program.signature
      assert enhanced_program.client == source_program.client
      
      # Verify only instruction was modified
      assert enhanced_program.demos == source_program.demos
    end

    test "apply preserves program structure and metadata" do
      original_program = create_test_program()
      bucket = create_test_bucket_with_variance()
      
      opts = %{
        buckets: [bucket],
        client: create_test_client()
      }

      {:ok, enhanced_program} = AppendRule.apply(bucket, original_program, opts)
      
      # Verify all non-instruction fields are preserved
      assert enhanced_program.signature == original_program.signature
      assert enhanced_program.client == original_program.client
      assert enhanced_program.demos == original_program.demos
      
      # Only instruction should be different
      assert enhanced_program.instruction != original_program.instruction
    end
  end

  # Test helper functions
  defp create_test_program do
    %DSPEx.Predict{
      signature: TestSignatures.QuestionAnswering,
      client: :gpt3_5,
      instruction: "Answer the question accurately.",
      demos: []
    }
  end

  defp create_test_example do
    %{
      inputs: %{question: "What is the capital of France?"},
      outputs: %{answer: "Paris"}
    }
  end

  defp create_test_bucket_with_variance do
    successful = %Trajectory{
      program: create_test_program(),
      example: create_test_example(),
      inputs: %{question: "What is the capital of France?"},
      outputs: %{answer: "Paris"},
      score: 1.0,
      success: true,
      error: nil
    }
    
    failed = %Trajectory{
      program: create_test_program(),
      example: %{inputs: %{question: "What is 5+5?"}, outputs: %{answer: "10"}},
      inputs: %{question: "What is 5+5?"},
      outputs: %{answer: "eleven"},
      score: 0.0,
      success: false,
      error: nil
    }

    Bucket.new([successful, failed])
  end

  defp create_test_client do
    # Mock client that returns properly formatted instruction improvement
    fn _signature, _inputs, _options ->
      {:ok, %{
        module_advice: %{
          "main" => "Be more precise with numerical calculations. Always double-check arithmetic."
        }
      }}
    end
  end

  defp create_failing_test_client do
    # Mock client that returns malformed response
    fn _signature, _inputs, _options ->
      {:ok, "malformed response without proper structure"}
    end
  end
end

defmodule TestSignatures.QuestionAnswering do
  use DSPEx.Signature, "question -> answer"
end