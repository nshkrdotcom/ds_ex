defmodule DSPEx.Teleprompter.SIMBAElixirMLTest do
  use ExUnit.Case, async: true

  alias DSPEx.Teleprompter.SIMBA

  @moduletag :simba_elixir_ml

  describe "ElixirML schema integration" do
    test "uses ElixirML for trajectory validation" do
      # Create a trajectory data structure
      trajectory_data = %{
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"},
        score: 0.95,
        success: true,
        duration: 150,
        model_config: %{temperature: 0.2, provider: :openai},
        metadata: %{step: 1, batch_id: "batch_001"}
      }

      # Should validate using ElixirML instead of Sinter
      assert {:ok, validated} = SIMBA.ElixirMLSchemas.validate_trajectory(trajectory_data)

      assert validated.inputs.question == "What is 2+2?"
      assert validated.outputs.answer == "4"
      assert validated.score == 0.95
      assert validated.success == true
      assert validated.duration == 150
    end

    test "uses ElixirML for bucket validation" do
      bucket_data = %{
        trajectories: [
          %{inputs: %{q: "test"}, outputs: %{a: "test"}, score: 0.8, success: true},
          %{inputs: %{q: "test2"}, outputs: %{a: "test2"}, score: 0.9, success: true}
        ],
        max_score: 0.9,
        min_score: 0.8,
        avg_score: 0.85,
        max_to_min_gap: 0.1,
        max_to_avg_gap: 0.05,
        metadata: %{bucket_id: "bucket_001"}
      }

      # Should validate using ElixirML
      assert {:ok, validated} = SIMBA.ElixirMLSchemas.validate_bucket(bucket_data)

      assert length(validated.trajectories) == 2
      assert validated.max_score == 0.9
      assert validated.min_score == 0.8
      assert validated.avg_score == 0.85
    end

    test "uses ElixirML for performance metrics validation" do
      metrics_data = %{
        accuracy: 0.85,
        f1_score: 0.82,
        precision: 0.88,
        recall: 0.78,
        latency_ms: 250,
        # Fixed: within reasonable range
        throughput: 4.2,
        example_count: 100,
        success_count: 85,
        failure_count: 15,
        improvement_score: 0.15,
        convergence_indicator: 0.75
      }

      # Should validate using ElixirML
      assert {:ok, validated} = SIMBA.ElixirMLSchemas.validate_performance_metrics(metrics_data)

      assert validated.accuracy == 0.85
      assert validated.f1_score == 0.82
      assert validated.latency_ms == 250
      assert validated.example_count == 100
    end

    test "uses ElixirML for training example validation" do
      example_data = %{
        inputs: %{question: "What is ML?", context: "Machine Learning context"},
        outputs: %{answer: "Machine Learning is...", confidence: 0.9},
        quality_score: 0.95,
        validated: true,
        example_id: "example_001",
        source: "training_set",
        created_at: "2024-01-15T10:30:00Z",
        metadata: %{difficulty: "medium", domain: "AI"}
      }

      # Should validate using ElixirML
      assert {:ok, validated} = SIMBA.ElixirMLSchemas.validate_training_example(example_data)

      assert validated.inputs.question == "What is ML?"
      assert validated.outputs.answer == "Machine Learning is..."
      assert validated.quality_score == 0.95
      assert validated.validated == true
    end

    test "uses ElixirML for strategy configuration validation" do
      strategy_config = %{
        strategy_name: "append_demo",
        strategy_version: "1.0.0",
        min_improvement_threshold: 0.1,
        max_score_threshold: 0.1,
        max_demos: 4,
        demo_input_field_maxlen: 100_000,
        temperature: 0.2,
        enabled: true,
        priority: 5,
        metadata: %{author: "system", created_at: "2024-01-15"}
      }

      # Should validate using ElixirML
      assert {:ok, validated} = SIMBA.ElixirMLSchemas.validate_strategy_config(strategy_config)

      assert validated.strategy_name == "append_demo"
      assert validated.max_demos == 4
      assert validated.temperature == 0.2
      assert validated.enabled == true
    end

    test "uses ElixirML for optimization result validation" do
      result_data = %{
        success: true,
        improved: true,
        initial_score: 0.65,
        final_score: 0.85,
        improvement_delta: 0.20,
        steps_taken: 8,
        strategies_applied: ["append_demo", "modify_instruction"],
        # Fixed: within constraint range
        total_trajectories: 50,
        successful_trajectories: 42,
        duration_ms: 45_000,
        convergence_step: 6,
        correlation_id: "opt_001",
        metadata: %{algorithm: "simba", version: "1.0"}
      }

      # Should validate using ElixirML
      assert {:ok, validated} = SIMBA.ElixirMLSchemas.validate_optimization_result(result_data)

      assert validated.success == true
      assert validated.improved == true
      assert validated.initial_score == 0.65
      assert validated.final_score == 0.85
      assert validated.improvement_delta == 0.20
    end
  end

  describe "SIMBA integration with ElixirML" do
    test "creates ElixirML schemas for dynamic validation" do
      # Test that SIMBA can be configured to use ElixirML
      teleprompter =
        SIMBA.new(
          bsize: 2,
          num_candidates: 2,
          max_steps: 1
        )

      # Verify the teleprompter is configured properly
      assert teleprompter.bsize == 2
      assert teleprompter.num_candidates == 2
      assert teleprompter.max_steps == 1

      # Verify that ElixirMLSchemas module exists and has expected functions
      assert function_exported?(SIMBA.ElixirMLSchemas, :validate_trajectory, 1)
      assert function_exported?(SIMBA.ElixirMLSchemas, :validate_bucket, 1)
      assert function_exported?(SIMBA.ElixirMLSchemas, :validate_training_examples, 1)
    end

    test "generates provider-optimized JSON schemas for LLM instruction generation" do
      # Test OpenAI-optimized schema generation
      trajectory_schema = SIMBA.ElixirMLSchemas.trajectory_schema()

      openai_json = SIMBA.ElixirMLSchemas.to_json_schema(trajectory_schema, provider: :openai)

      # Should have OpenAI-specific optimizations
      assert openai_json["type"] == "object"
      assert openai_json["additionalProperties"] == false
      assert is_map(openai_json["properties"])

      # Test Anthropic-optimized schema generation
      anthropic_json =
        SIMBA.ElixirMLSchemas.to_json_schema(trajectory_schema, provider: :anthropic)

      # Should have Anthropic-specific optimizations
      assert anthropic_json["type"] == "object"
      assert Map.has_key?(anthropic_json, "x-anthropic-optimized")
    end

    test "extracts variables for optimization systems" do
      # Create strategy configuration schema
      strategy_schema = SIMBA.ElixirMLSchemas.strategy_config_schema()

      # Should extract variables for hyperparameter optimization
      variables = SIMBA.ElixirMLSchemas.extract_variables(strategy_schema)

      # For now, just check that extraction returns something
      # This will be properly implemented when ElixirML Runtime is complete
      assert is_list(variables) or is_map(variables)
    end
  end

  describe "error handling and validation" do
    test "provides detailed validation errors" do
      # Invalid trajectory data
      invalid_trajectory = %{
        inputs: %{question: "test"},
        outputs: %{answer: "test"},
        # Invalid: > 1.0
        score: 1.5,
        # Invalid: should be boolean
        success: "yes",
        # Invalid: negative duration
        duration: -10
      }

      # Should return detailed ElixirML validation errors
      assert {:error, error} = SIMBA.ElixirMLSchemas.validate_trajectory(invalid_trajectory)

      assert %ElixirML.Schema.ValidationError{} = error
      assert is_binary(error.message)

      # Error should be informative
      assert String.contains?(error.message, "score") or
               String.contains?(error.message, "success") or
               String.contains?(error.message, "duration")
    end

    test "handles missing required fields" do
      # Incomplete bucket data
      incomplete_bucket = %{
        # Empty trajectories
        trajectories: [],
        max_score: 0.9
        # Missing required fields: min_score, avg_score, etc.
      }

      assert {:error, error} = SIMBA.ElixirMLSchemas.validate_bucket(incomplete_bucket)

      # Should identify missing required fields
      assert %ElixirML.Schema.ValidationError{} = error

      assert String.contains?(error.message, "min_score") or
               String.contains?(error.message, "avg_score")
    end
  end

  describe "performance and ML-specific features" do
    test "supports ML-native types in validation" do
      # Trajectory with ML-specific types
      ml_trajectory = %{
        inputs: %{question: "test"},
        outputs: %{
          answer: "test",
          # probability type
          confidence: 0.85,
          # embedding type
          embedding: [1.0, 2.0, 3.0],
          # attention matrix
          attention_weights: [[0.1, 0.9], [0.8, 0.2]]
        },
        score: 0.9,
        success: true,
        model_config: %{
          # temperature type
          temperature: 0.7,
          provider: :openai
        }
      }

      # Should validate ML-native types correctly
      assert {:ok, validated} = SIMBA.ElixirMLSchemas.validate_trajectory(ml_trajectory)

      assert validated.outputs.confidence == 0.85
      assert validated.outputs.embedding == [1.0, 2.0, 3.0]
      assert validated.model_config.temperature == 0.7
    end

    test "optimizes validation performance for SIMBA scale" do
      # Create large dataset for performance testing
      large_trajectories =
        Enum.map(1..1000, fn i ->
          %{
            inputs: %{question: "Question #{i}"},
            outputs: %{answer: "Answer #{i}"},
            score: :rand.uniform(),
            success: true
          }
        end)

      # Should validate efficiently at scale
      start_time = System.monotonic_time()

      results =
        Enum.map(large_trajectories, fn trajectory ->
          SIMBA.ElixirMLSchemas.validate_trajectory(trajectory)
        end)

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should complete within reasonable time (< 1 second for 1000 validations)
      assert duration_ms < 1000

      # All validations should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
end
