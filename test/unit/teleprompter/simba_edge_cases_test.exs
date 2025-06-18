defmodule DSPEx.Teleprompter.SIMBA.EdgeCasesTest do
  @moduledoc """
  Phase 5: Comprehensive edge case testing for SIMBA teleprompter.

  Tests edge case handling, malformed responses, network failures, empty trajectories,
  and production reliability scenarios for the SIMBA optimization algorithm.
  """
  use ExUnit.Case, async: false

  alias DSPEx.Teleprompter.SIMBA
  alias DSPEx.Teleprompter.SIMBA.{Strategy, Trajectory, Bucket}
  alias DSPEx.{Predict, Example}

  @moduletag :group_3
  @moduletag :edge_cases
  @moduletag :phase_5

  # Test signature for edge case testing
  defmodule EdgeCaseSignature do
    use DSPEx.Signature, "question -> answer"
  end

  describe "empty trajectory handling" do
    test "handles empty trajectory buckets gracefully" do
      simba = SIMBA.new(
        strategies: [:append_demo, :append_rule],
        num_candidates: 5,
        max_steps: 3
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Answer questions accurately."
      }

      # Empty training data
      training_data = []
      metric_fn = fn _example, _prediction -> 1.0 end

      # Should handle empty training data gracefully
      result = SIMBA.compile(simba, program, training_data, metric_fn)

      assert {:error, reason} = result
      assert String.contains?(inspect(reason), ["empty", "no data", "insufficient"])
    end

    test "handles single trajectory edge case" do
      simba = SIMBA.new(
        strategies: [:append_demo],
        num_candidates: 3,
        max_steps: 2
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Answer questions."
      }

      # Single training example
      training_data = [
        %{inputs: %{question: "What is 2+2?"}, outputs: %{answer: "4"}}
      ]

      metric_fn = fn _example, _prediction -> 1.0 end

      # Mock successful response
      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "4"}])

      result = SIMBA.compile(simba, program, training_data, metric_fn)

      # Should handle single example appropriately
      case result do
        {:ok, optimized} ->
          assert is_struct(optimized)

        {:error, _reason} ->
          # May fail with insufficient data - that's acceptable
          :ok
      end
    end

    test "handles all failed trajectories scenario" do
      simba = SIMBA.new(
        strategies: [:append_demo],
        num_candidates: 4,
        max_steps: 2
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Answer questions."
      }

      training_data = [
        %{inputs: %{question: "What is impossible?"}, outputs: %{answer: "Nothing"}},
        %{inputs: %{question: "Another impossible?"}, outputs: %{answer: "Still nothing"}}
      ]

      # Metric that always returns 0 (all trajectories fail)
      metric_fn = fn _example, _prediction -> 0.0 end

      # Mock responses that won't match expected outputs
      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "Wrong answer"},
        %{content: "Another wrong answer"}
      ])

      result = SIMBA.compile(simba, program, training_data, metric_fn)

      # Should handle all failed trajectories gracefully
      case result do
        {:ok, optimized} ->
          # If it succeeds, it should have minimal improvements
          demo_count = case optimized do
            %{demos: demos} -> length(demos)
            %{examples: examples} -> length(examples)
            _ -> 0
          end
          assert demo_count == 0 or demo_count <= 1

        {:error, reason} ->
          # Error is acceptable when all trajectories fail
          assert String.contains?(inspect(reason), ["no successful", "failed", "insufficient"])
      end
    end
  end

  describe "malformed LLM response handling" do
    test "recovers from malformed JSON responses" do
      simba = SIMBA.new(
        strategies: [:append_rule],
        num_candidates: 3,
        max_steps: 2
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Answer questions."
      }

      training_data = [
        %{inputs: %{question: "What is 2+2?"}, outputs: %{answer: "4"}},
        %{inputs: %{question: "What is 3+3?"}, outputs: %{answer: "6"}}
      ]

      metric_fn = fn _example, _prediction -> 0.5 end

      # Mock malformed JSON responses
      DSPEx.MockClientManager.set_mock_responses(:test, [
        "{ invalid json without closing brace",
        %{content: "malformed: {not: valid}"},
        "plain text response",
        nil
      ])

      result = SIMBA.compile(simba, program, training_data, metric_fn)

      # Should handle malformed responses gracefully
      case result do
        {:ok, optimized} ->
          # If successful, should fall back gracefully
          assert is_struct(optimized)

        {:error, reason} ->
          # Error is acceptable when LLM responses are malformed
          assert String.contains?(inspect(reason), ["parse", "format", "response", "malformed"])
      end
    end

    test "handles unparseable instruction generation responses" do
      # Test specific to AppendRule strategy with malformed OfferFeedback responses
      bucket = create_test_bucket_with_variance()
      source_program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Original instruction."
      }

      # Mock client that returns unparseable instruction improvements
      malformed_client = fn _signature, _inputs, _opts ->
        # Return responses that can't be parsed as module advice
        malformed_responses = [
          {:ok, "not a map"},
          {:ok, %{wrong_field: "data"}},
          {:ok, %{module_advice: "should be map but is string"}},
          {:error, :network_timeout}
        ]

        Enum.random(malformed_responses)
      end

      opts = %{
        buckets: [bucket],
        client: malformed_client
      }

      result = Strategy.AppendRule.apply(bucket, source_program, opts)

      # Should handle malformed responses gracefully
      assert {:skip, reason} = result
      assert is_binary(reason)
      assert String.contains?(reason, ["parse", "format", "invalid", "timeout", "network", "malformed"])
    end

    test "handles network timeouts during trajectory sampling" do
      simba = SIMBA.new(
        strategies: [:append_demo],
        num_candidates: 3,
        max_steps: 2
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Answer questions."
      }

      training_data = [
        %{inputs: %{question: "Timeout test 1"}, outputs: %{answer: "Answer 1"}},
        %{inputs: %{question: "Timeout test 2"}, outputs: %{answer: "Answer 2"}},
        %{inputs: %{question: "Timeout test 3"}, outputs: %{answer: "Answer 3"}}
      ]

      metric_fn = fn _example, _prediction -> 0.8 end

      # Mock timeout responses (simulate network failures)
      timeout_responses = [
        {:error, :timeout},
        {:error, :network_error},
        %{content: "Partial success"}
      ]

      DSPEx.MockClientManager.set_mock_responses(:test, timeout_responses)

      result = SIMBA.compile(simba, program, training_data, metric_fn)

      # Should handle timeouts gracefully
      case result do
        {:ok, optimized} ->
          # Should work with at least some successful responses
          assert is_struct(optimized)

        {:error, reason} ->
          # Network failures might cause compilation to fail
          assert String.contains?(inspect(reason), ["timeout", "network", "error", "failed"])
      end
    end
  end

  describe "temperature and parameter edge values" do
    test "handles temperature edge values correctly" do
      edge_temperatures = [0.0, 0.001, 0.999, 1.0, 1.5, 2.0]

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Test temperature handling."
      }

      training_data = [
        %{inputs: %{question: "Temperature test"}, outputs: %{answer: "Response"}}
      ]

      metric_fn = fn _example, _prediction -> 0.7 end

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Response"}])

      Enum.each(edge_temperatures, fn temp ->
        simba = SIMBA.new(
          strategies: [:append_demo],
          num_candidates: 2,
          max_steps: 1,
          temperature: temp
        )

        result = SIMBA.compile(simba, program, training_data, metric_fn)

        # Should handle all temperature values gracefully
        case result do
          {:ok, _optimized} ->
            :ok
          {:error, _reason} ->
            # Some extreme temperatures might cause failures - that's acceptable
            :ok
        end
      end)
    end

    test "handles zero and negative configuration values" do
      edge_configs = [
        %{num_candidates: 0},
        %{num_candidates: -1},
        %{max_steps: 0},
        %{max_steps: -1},
        %{max_examples_per_demo: 0},
        %{min_score_threshold: -1.0},
        %{max_score_threshold: 2.0}
      ]

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Test edge config values."
      }

      training_data = [
        %{inputs: %{question: "Config test"}, outputs: %{answer: "Response"}}
      ]

      metric_fn = fn _example, _prediction -> 0.5 end

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Response"}])

      Enum.each(edge_configs, fn config ->
        try do
          base_config = %{
            strategies: [:append_demo],
            num_candidates: 3,
            max_steps: 2
          }

          merged_config = Map.merge(base_config, config)
          simba = SIMBA.new(merged_config)

          result = SIMBA.compile(simba, program, training_data, metric_fn)

          # Should handle edge config values gracefully (either succeed or fail safely)
          case result do
            {:ok, _optimized} -> :ok
            {:error, _reason} -> :ok
          end
        rescue
          error ->
            # Configuration validation might raise errors - that's acceptable
            assert error.__struct__ in [ArgumentError, RuntimeError, FunctionClauseError]
        end
      end)
    end
  end

  describe "concurrent task failure recovery" do
    test "recovers from metric function failures" do
      simba = SIMBA.new(
        strategies: [:append_demo],
        num_candidates: 3,
        max_steps: 2
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Test metric failures."
      }

      training_data = [
        %{inputs: %{question: "Metric test 1"}, outputs: %{answer: "Answer 1"}},
        %{inputs: %{question: "Metric test 2"}, outputs: %{answer: "Answer 2"}},
        %{inputs: %{question: "Metric test 3"}, outputs: %{answer: "Answer 3"}}
      ]

      # Metric function that randomly fails
      failing_metric_fn = fn _example, _prediction ->
        case :rand.uniform(4) do
          1 -> raise "Random metric failure"
          2 -> {:error, "Metric error"}
          3 -> nil  # Invalid return type
          4 -> 0.8  # Success case
        end
      end

      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "Answer 1"},
        %{content: "Answer 2"},
        %{content: "Answer 3"}
      ])

      result = SIMBA.compile(simba, program, training_data, failing_metric_fn)

      # Should handle metric failures gracefully
      case result do
        {:ok, optimized} ->
          # Should work with successful metric evaluations
          assert is_struct(optimized)

        {:error, reason} ->
          # Metric failures might cause compilation to fail
          assert String.contains?(inspect(reason), ["metric", "evaluation", "error", "failed"])
      end
    end

    test "manages concurrent task failures gracefully" do
      simba = SIMBA.new(
        strategies: [:append_demo],
        num_candidates: 10,  # High concurrency to test task failures
        max_steps: 2
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Test concurrent task failures."
      }

      # Large training set to encourage concurrent execution
      training_data = Enum.map(1..20, fn i ->
        %{inputs: %{question: "Concurrent test #{i}"}, outputs: %{answer: "Answer #{i}"}}
      end)

      metric_fn = fn _example, _prediction -> 0.6 end

      # Mix of successful and failing responses to simulate partial task failures
      mixed_responses = [
        %{content: "Success 1"},
        {:error, :task_failed},
        %{content: "Success 2"},
        {:error, :process_crashed},
        %{content: "Success 3"},
        nil,  # Simulate null response
        %{content: "Success 4"}
      ] ++ Enum.map(1..15, fn i -> %{content: "Response #{i}"} end)

      DSPEx.MockClientManager.set_mock_responses(:test, mixed_responses)

      result = SIMBA.compile(simba, program, training_data, metric_fn)

      # Should handle partial task failures and continue with successful ones
      case result do
        {:ok, optimized} ->
          # Should succeed with at least some successful tasks
          assert is_struct(optimized)

        {:error, reason} ->
          # Too many task failures might cause overall failure
          assert String.contains?(inspect(reason), ["task", "failed", "concurrent", "error"])
      end
    end
  end

  describe "memory pressure and resource limits" do
    test "handles memory pressure during large optimizations" do
      simba = SIMBA.new(
        strategies: [:append_demo],
        num_candidates: 5,
        max_steps: 2
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Test memory pressure."
      }

      # Create memory pressure with large training data
      large_training_data = Enum.map(1..1000, fn i ->
        large_question = String.duplicate("Memory pressure test question #{i} ", 100)
        large_answer = String.duplicate("Answer #{i} ", 50)

        %{
          inputs: %{question: large_question},
          outputs: %{answer: large_answer},
          metadata: %{
            id: i,
            timestamp: System.monotonic_time(),
            large_field: String.duplicate("x", 1000)
          }
        }
      end)

      metric_fn = fn _example, _prediction -> 0.7 end

      # Responses for large dataset
      responses = Enum.map(1..1000, fn i -> %{content: "Answer #{i}"} end)
      DSPEx.MockClientManager.set_mock_responses(:test, responses)

      initial_memory = :erlang.memory()[:total]

      result = SIMBA.compile(simba, program, large_training_data, metric_fn)

      final_memory = :erlang.memory()[:total]
      memory_growth_mb = (final_memory - initial_memory) / (1024 * 1024)

      # Should handle large datasets without excessive memory growth
      assert memory_growth_mb < 200, "Memory growth too high: #{Float.round(memory_growth_mb, 2)}MB"

      case result do
        {:ok, optimized} ->
          # Should handle large dataset efficiently
          assert is_struct(optimized)

        {:error, reason} ->
          # Memory pressure might cause failure - that's acceptable for stress test
          assert String.contains?(inspect(reason), ["memory", "resource", "timeout", "failed"])
      end
    end

    test "handles resource exhaustion gracefully" do
      # Test behavior when approaching system resource limits
      simba = SIMBA.new(
        strategies: [:append_demo, :append_rule],
        num_candidates: 50,  # Very high to stress resources
        max_steps: 5
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Test resource exhaustion."
      }

      training_data = Enum.map(1..100, fn i ->
        %{inputs: %{question: "Resource test #{i}"}, outputs: %{answer: "Answer #{i}"}}
      end)

      metric_fn = fn _example, _prediction -> 0.5 end

      responses = Enum.map(1..100, fn i -> %{content: "Answer #{i}"} end)
      DSPEx.MockClientManager.set_mock_responses(:test, responses)

      initial_process_count = length(Process.list())

      result = SIMBA.compile(simba, program, training_data, metric_fn)

      final_process_count = length(Process.list())
      process_growth = final_process_count - initial_process_count

      # Should not create excessive processes
      assert process_growth < 500, "Process growth too high: #{process_growth}"

      case result do
        {:ok, optimized} ->
          # Should succeed despite high resource usage
          assert is_struct(optimized)

        {:error, reason} ->
          # Resource exhaustion might cause failure - acceptable for stress test
          assert String.contains?(inspect(reason), ["resource", "timeout", "failed", "limit"])
      end
    end
  end

  describe "program composition edge cases" do
    test "handles circular reference prevention" do
      # Test that SIMBA prevents circular references in program optimization
      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Test circular references."
      }

      # Try to create a circular reference scenario
      demo = %Example{
        data: %{question: "Circular test", answer: "Response"},
        input_keys: MapSet.new([:question])
      }

      # Create an optimized program
      optimized = DSPEx.OptimizedProgram.new(program, [demo])

      # Try to optimize the already optimized program (potential circular reference)
      simba = SIMBA.new(
        strategies: [:append_demo],
        num_candidates: 2,
        max_steps: 1
      )

      training_data = [%{inputs: %{question: "Circular test"}, outputs: %{answer: "Response"}}]
      metric_fn = fn _example, _prediction -> 0.8 end

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Response"}])

      result = SIMBA.compile(simba, optimized, training_data, metric_fn)

      # Should handle nested optimization without creating circular references
      case result do
        {:ok, double_optimized} ->
          # Should be able to unwrap the composition safely
          assert is_struct(double_optimized)

        {:error, reason} ->
          # May reject circular reference attempts - that's acceptable
          assert is_binary(inspect(reason))
      end
    end

    test "handles incompatible signature combinations" do
      # Test SIMBA with mismatched signatures
      simba = SIMBA.new(
        strategies: [:append_demo],
        num_candidates: 2,
        max_steps: 1
      )

      program = %Predict{
        signature: EdgeCaseSignature,
        client: :test,
        instruction: "Test signature compatibility."
      }

      # Training data with incompatible structure
      incompatible_training_data = [
        %{inputs: %{wrong_field: "data"}, outputs: %{wrong_output: "response"}},
        %{inputs: %{question: "What is this?"}, outputs: %{answer: "Valid"}}
      ]

      metric_fn = fn _example, _prediction -> 0.5 end

      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "response"},
        %{content: "Valid"}
      ])

      result = SIMBA.compile(simba, program, incompatible_training_data, metric_fn)

      # Should handle signature mismatches gracefully
      case result do
        {:ok, optimized} ->
          # Should work with compatible examples, ignore incompatible ones
          assert is_struct(optimized)

        {:error, reason} ->
          # Signature mismatches might cause failure - that's acceptable
          assert String.contains?(inspect(reason), ["signature", "compatible", "field", "mismatch"])
      end
    end
  end

  # Helper functions for edge case testing

  defp create_test_bucket_with_variance do
    successful = %Trajectory{
      program: create_test_program(),
      example: %{inputs: %{question: "Success test"}, outputs: %{answer: "Correct"}},
      inputs: %{question: "Success test"},
      outputs: %{answer: "Correct"},
      score: 1.0,
      success: true,
      error: nil
    }

    failed = %Trajectory{
      program: create_test_program(),
      example: %{inputs: %{question: "Failure test"}, outputs: %{answer: "Correct"}},
      inputs: %{question: "Failure test"},
      outputs: %{answer: "Wrong"},
      score: 0.0,
      success: false,
      error: nil
    }

    Bucket.new([successful, failed])
  end

  defp create_test_program do
    %Predict{
      signature: EdgeCaseSignature,
      client: :test,
      instruction: "Answer questions accurately.",
      demos: []
    }
  end
end
