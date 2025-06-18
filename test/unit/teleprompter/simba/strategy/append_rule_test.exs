defmodule DSPEx.Teleprompter.SIMBA.Strategy.AppendRuleTest do
  use ExUnit.Case
  alias DSPEx.Teleprompter.SIMBA.Strategy.AppendRule
  alias DSPEx.Teleprompter.SIMBA.{Trajectory, Bucket}

  @moduletag :group_2
  @moduletag :append_rule
  @moduletag :phase_5

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

  describe "AppendRule edge cases and error handling" do
    test "handles extremely large trajectory datasets efficiently" do
      # Test with large number of trajectories
      large_trajectory_set = Enum.map(1..1000, fn i ->
        success = rem(i, 3) == 0  # Create variance pattern
        
        %Trajectory{
          program: create_test_program(),
          example: %{inputs: %{question: "Question #{i}"}, outputs: %{answer: "Answer #{i}"}},
          inputs: %{question: "Question #{i}"},
          outputs: %{answer: if(success, do: "Answer #{i}", else: "Wrong #{i}")},
          score: if(success, do: 1.0, else: 0.0),
          success: success,
          error: nil
        }
      end)

      bucket = Bucket.new(large_trajectory_set)
      source_program = create_test_program()
      
      opts = %{
        buckets: [bucket],
        client: create_test_client()
      }

      start_time = System.monotonic_time()
      result = AppendRule.apply(bucket, source_program, opts)
      end_time = System.monotonic_time()
      
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Should handle large datasets efficiently (< 5 seconds)
      assert duration_ms < 5000, "Large trajectory processing too slow: #{duration_ms}ms"

      case result do
        {:ok, enhanced_program} ->
          assert enhanced_program.instruction != source_program.instruction
        {:skip, _reason} ->
          # Skip is acceptable for large datasets with complex patterns
          :ok
      end
    end

    test "handles memory pressure during trajectory analysis" do
      # Create memory-intensive trajectories
      memory_intensive_trajectories = Enum.map(1..50, fn i ->
        large_data = String.duplicate("Large trajectory data #{i} ", 1000)
        
        %Trajectory{
          program: create_test_program(),
          example: %{
            inputs: %{question: "Memory test #{i}"},
            outputs: %{answer: "Answer #{i}"},
            metadata: %{large_field: large_data}
          },
          inputs: %{question: "Memory test #{i}"},
          outputs: %{answer: if(rem(i, 2) == 0, do: "Answer #{i}", else: "Wrong")},
          score: if(rem(i, 2) == 0, do: 1.0, else: 0.0),
          success: rem(i, 2) == 0,
          error: nil
        }
      end)

      bucket = Bucket.new(memory_intensive_trajectories)
      source_program = create_test_program()
      
      initial_memory = :erlang.memory()[:total]
      
      opts = %{
        buckets: [bucket],
        client: create_test_client()
      }

      result = AppendRule.apply(bucket, source_program, opts)
      
      :erlang.garbage_collect()
      final_memory = :erlang.memory()[:total]
      memory_growth_mb = (final_memory - initial_memory) / (1024 * 1024)

      # Should not consume excessive memory
      assert memory_growth_mb < 20, "Memory growth too high: #{Float.round(memory_growth_mb, 2)}MB"

      # Should still produce valid result
      case result do
        {:ok, _enhanced} -> :ok
        {:skip, _reason} -> :ok
      end
    end

    test "handles concurrent trajectory analysis safely" do
      # Test thread safety when multiple AppendRule applications run concurrently
      bucket = create_test_bucket_with_variance()
      source_program = create_test_program()
      
      concurrent_tasks = Enum.map(1..10, fn task_id ->
        Task.async(fn ->
          opts = %{
            buckets: [bucket],
            client: create_test_client(),
            correlation_id: "task_#{task_id}"
          }

          AppendRule.apply(bucket, source_program, opts)
        end)
      end)

      results = Task.await_many(concurrent_tasks, 10_000)

      # All should complete without errors
      assert length(results) == 10

      # All should be either success or consistent skip
      result_types = Enum.group_by(results, fn
        {:ok, _} -> :success
        {:skip, _} -> :skip
        {:error, _} -> :error
      end)

      # Should not have any errors from concurrency issues
      assert Map.get(result_types, :error, []) == [], "Should not have concurrency errors"

      # Should have mostly consistent results
      success_count = length(Map.get(result_types, :success, []))
      skip_count = length(Map.get(result_types, :skip, []))

      assert success_count + skip_count == 10, "All results should be success or skip"
    end

    test "gracefully degrades with malformed trajectory data" do
      # Test with various malformed trajectory structures
      malformed_trajectories = [
        # Missing required fields
        %{program: create_test_program(), score: 1.0},
        
        # Invalid score types
        %Trajectory{
          program: create_test_program(),
          example: create_test_example(),
          inputs: %{question: "Test"},
          outputs: %{answer: "Test"},
          score: "invalid_score",
          success: true,
          error: nil
        },
        
        # Nil values
        %Trajectory{
          program: nil,
          example: create_test_example(),
          inputs: nil,
          outputs: %{answer: "Test"},
          score: 1.0,
          success: true,
          error: nil
        },
        
        # Valid trajectory for comparison
        %Trajectory{
          program: create_test_program(),
          example: create_test_example(),
          inputs: %{question: "Valid"},
          outputs: %{answer: "Valid"},
          score: 0.0,
          success: false,
          error: nil
        }
      ]

      bucket = Bucket.new(malformed_trajectories)
      source_program = create_test_program()
      
      opts = %{
        buckets: [bucket],
        client: create_test_client()
      }

      # Should handle malformed data gracefully without crashing
      result = AppendRule.apply(bucket, source_program, opts)

      case result do
        {:ok, enhanced_program} ->
          # Should work with valid trajectories
          assert enhanced_program.instruction != source_program.instruction
        {:skip, reason} ->
          # Should skip with appropriate reason for malformed data
          assert String.contains?(reason, ["insufficient", "invalid", "malformed"])
        {:error, reason} ->
          # Error is acceptable for severely malformed data
          assert is_binary(inspect(reason))
      end
    end

    test "handles timeout scenarios during LLM instruction generation" do
      bucket = create_test_bucket_with_variance()
      source_program = create_test_program()
      
      # Mock client that simulates timeout
      timeout_client = fn _signature, _inputs, _opts ->
        Process.sleep(100)  # Simulate slow response
        {:error, :timeout}
      end
      
      opts = %{
        buckets: [bucket],
        client: timeout_client,
        timeout: 50  # Very short timeout to force timeout scenario
      }

      result = AppendRule.apply(bucket, source_program, opts)

      # Should handle timeout gracefully
      assert {:skip, reason} = result
      assert String.contains?(reason, ["timeout", "failed", "error"])
    end

    test "validates OfferFeedback signature response format strictly" do
      bucket = create_test_bucket_with_variance()
      source_program = create_test_program()
      
      # Test various invalid response formats
      invalid_response_clients = [
        # Wrong field name
        fn _sig, _inputs, _opts -> {:ok, %{wrong_field: %{"main" => "advice"}}} end,
        
        # Invalid nested structure
        fn _sig, _inputs, _opts -> {:ok, %{module_advice: "should be map not string"}} end,
        
        # Empty advice
        fn _sig, _inputs, _opts -> {:ok, %{module_advice: %{}}} end,
        
        # Non-string advice values
        fn _sig, _inputs, _opts -> {:ok, %{module_advice: %{"main" => 123}}} end
      ]

      Enum.each(invalid_response_clients, fn invalid_client ->
        opts = %{
          buckets: [bucket],
          client: invalid_client
        }

        result = AppendRule.apply(bucket, source_program, opts)

        # Should reject invalid formats
        assert {:skip, reason} = result
        assert String.contains?(reason, ["parse", "format", "invalid", "response"])
      end)
    end

    test "handles edge cases in trajectory variance detection" do
      # Test various edge cases for trajectory variance
      test_cases = [
        # All identical scores
        {[1.0, 1.0, 1.0, 1.0], false},
        
        # All zeros
        {[0.0, 0.0, 0.0, 0.0], false},
        
        # Minimal variance
        {[0.99, 1.0, 0.99, 1.0], true},
        
        # Single outlier
        {[1.0, 1.0, 0.0, 1.0], true},
        
        # Mixed variance
        {[0.2, 0.8, 0.3, 0.9], true},
        
        # Single trajectory
        {[0.5], false},
        
        # Two trajectories with difference
        {[0.0, 1.0], true}
      ]

      Enum.each(test_cases, fn {scores, expected_variance} ->
        trajectories = Enum.with_index(scores, fn score, i ->
          %Trajectory{
            program: create_test_program(),
            example: %{inputs: %{question: "Test #{i}"}, outputs: %{answer: "Answer #{i}"}},
            inputs: %{question: "Test #{i}"},
            outputs: %{answer: "Answer #{i}"},
            score: score,
            success: score > 0.5,
            error: nil
          }
        end)

        bucket = Bucket.new(trajectories)
        context = %{buckets: [bucket], current_program: create_test_program()}

        result = AppendRule.applicable?(bucket, context)

        if expected_variance do
          assert result, "Should detect variance in scores: #{inspect(scores)}"
        else
          refute result, "Should not detect variance in scores: #{inspect(scores)}"
        end
      end)
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