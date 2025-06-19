defmodule DSPEx.Teleprompter.SIMBA.SinterSchemasTest do
  use ExUnit.Case, async: true

  alias DSPEx.Teleprompter.SIMBA.SinterSchemas

  describe "trajectory_schema/0" do
    test "validates valid trajectory data" do
      valid_trajectory = %{
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"},
        score: 0.95,
        success: true,
        duration: 150,
        model_config: %{model: "gpt-4", temperature: 0.2},
        metadata: %{strategy: "append_demo"}
      }

      assert {:ok, validated} = SinterSchemas.validate_trajectory(valid_trajectory)
      assert validated.score == 0.95
      assert validated.success == true
    end

    test "rejects trajectory with invalid score" do
      invalid_trajectory = %{
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"},
        # Invalid: > 1.0
        score: 1.5,
        success: true
      }

      assert {:error, errors} = SinterSchemas.validate_trajectory(invalid_trajectory)
      assert Enum.any?(errors, fn error -> error.path == [:score] end)
    end

    test "rejects trajectory missing required fields" do
      incomplete_trajectory = %{
        inputs: %{question: "What is 2+2?"}
        # Missing outputs, score, success
      }

      assert {:error, errors} = SinterSchemas.validate_trajectory(incomplete_trajectory)
      # At least outputs, score, success missing
      assert length(errors) >= 3
    end

    test "handles optional fields with defaults" do
      minimal_trajectory = %{
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"},
        score: 0.95,
        success: true
      }

      assert {:ok, validated} = SinterSchemas.validate_trajectory(minimal_trajectory)
      assert validated.metadata == %{}
    end
  end

  describe "bucket_schema/0" do
    test "validates valid bucket data" do
      valid_bucket = %{
        trajectories: [
          %{score: 0.9, success: true},
          %{score: 0.7, success: true}
        ],
        max_score: 0.9,
        min_score: 0.7,
        avg_score: 0.8,
        max_to_min_gap: 0.2,
        max_to_avg_gap: 0.1,
        metadata: %{bucket_id: 1}
      }

      assert {:ok, validated} = SinterSchemas.validate_bucket(valid_bucket)
      assert validated.max_score == 0.9
      assert length(validated.trajectories) == 2
    end

    test "requires at least one trajectory" do
      invalid_bucket = %{
        # Invalid: empty array
        trajectories: [],
        max_score: 0.0,
        min_score: 0.0,
        avg_score: 0.0,
        max_to_min_gap: 0.0,
        max_to_avg_gap: 0.0
      }

      assert {:error, errors} = SinterSchemas.validate_bucket(invalid_bucket)
      assert Enum.any?(errors, fn error -> error.path == [:trajectories] end)
    end

    test "validates score constraints" do
      invalid_bucket = %{
        trajectories: [%{score: 0.5}],
        # Invalid: negative score
        max_score: -0.1,
        min_score: 0.0,
        avg_score: 0.0,
        max_to_min_gap: 0.0,
        max_to_avg_gap: 0.0
      }

      assert {:error, errors} = SinterSchemas.validate_bucket(invalid_bucket)
      assert Enum.any?(errors, fn error -> error.path == [:max_score] end)
    end
  end

  describe "performance_metrics_schema/0" do
    test "validates complete performance metrics" do
      valid_metrics = %{
        accuracy: 0.85,
        f1_score: 0.82,
        precision: 0.87,
        recall: 0.78,
        latency_ms: 250,
        throughput: 15.5,
        example_count: 100,
        success_count: 85,
        failure_count: 15,
        improvement_score: 0.25,
        convergence_indicator: 0.9
      }

      assert {:ok, validated} = SinterSchemas.validate_performance_metrics(valid_metrics)
      assert validated.accuracy == 0.85
      assert validated.latency_ms == 250
    end

    test "validates minimal required metrics" do
      minimal_metrics = %{
        accuracy: 0.85,
        f1_score: 0.82,
        latency_ms: 250,
        example_count: 100,
        success_count: 85,
        failure_count: 15
      }

      assert {:ok, validated} = SinterSchemas.validate_performance_metrics(minimal_metrics)
      assert validated.accuracy == 0.85
    end

    test "rejects invalid latency" do
      invalid_metrics = %{
        accuracy: 0.85,
        f1_score: 0.82,
        # Invalid: must be > 0
        latency_ms: 0,
        example_count: 100,
        success_count: 85,
        failure_count: 15
      }

      assert {:error, errors} = SinterSchemas.validate_performance_metrics(invalid_metrics)
      assert Enum.any?(errors, fn error -> error.path == [:latency_ms] end)
    end
  end

  describe "training_example_schema/0" do
    test "validates training example with all fields" do
      valid_example = %{
        inputs: %{question: "What is the capital of France?"},
        outputs: %{answer: "Paris"},
        quality_score: 0.95,
        validated: true,
        example_id: "ex_001",
        source: "human_curated",
        created_at: "2024-01-15T10:30:00Z",
        metadata: %{difficulty: "easy"}
      }

      assert {:ok, validated} = SinterSchemas.validate_training_example(valid_example)
      assert validated.quality_score == 0.95
      assert validated.validated == true
    end

    test "validates minimal training example" do
      minimal_example = %{
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"}
      }

      assert {:ok, validated} = SinterSchemas.validate_training_example(minimal_example)
      # Default value
      assert validated.validated == false
      # Default value
      assert validated.metadata == %{}
    end

    test "validates quality score bounds" do
      invalid_example = %{
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"},
        # Invalid: > 1.0
        quality_score: 1.5
      }

      assert {:error, errors} = SinterSchemas.validate_training_example(invalid_example)
      assert Enum.any?(errors, fn error -> error.path == [:quality_score] end)
    end
  end

  describe "strategy_config_schema/0" do
    test "validates complete strategy configuration" do
      valid_config = %{
        strategy_name: "append_demo",
        strategy_version: "1.0.0",
        min_improvement_threshold: 0.1,
        max_score_threshold: 0.1,
        max_demos: 4,
        demo_input_field_maxlen: 100_000,
        temperature: 0.2,
        enabled: true,
        priority: 5,
        metadata: %{author: "simba_system"}
      }

      assert {:ok, validated} = SinterSchemas.validate_strategy_config(valid_config)
      assert validated.strategy_name == "append_demo"
      assert validated.max_demos == 4
    end

    test "validates minimal strategy configuration" do
      minimal_config = %{
        strategy_name: "append_rule"
      }

      assert {:ok, validated} = SinterSchemas.validate_strategy_config(minimal_config)
      # Default value
      assert validated.max_demos == 4
      # Default value
      assert validated.enabled == true
      # Default value
      assert validated.priority == 5
    end

    test "rejects empty strategy name" do
      invalid_config = %{
        # Invalid: empty string
        strategy_name: ""
      }

      assert {:error, errors} = SinterSchemas.validate_strategy_config(invalid_config)
      assert Enum.any?(errors, fn error -> error.path == [:strategy_name] end)
    end

    test "validates temperature bounds" do
      invalid_config = %{
        strategy_name: "test_strategy",
        # Invalid: > 2.0
        temperature: 3.0
      }

      assert {:error, errors} = SinterSchemas.validate_strategy_config(invalid_config)
      assert Enum.any?(errors, fn error -> error.path == [:temperature] end)
    end
  end

  describe "optimization_result_schema/0" do
    test "validates complete optimization result" do
      valid_result = %{
        success: true,
        improved: true,
        initial_score: 0.6,
        final_score: 0.85,
        improvement_delta: 0.25,
        steps_taken: 5,
        strategies_applied: ["append_demo", "append_rule"],
        total_trajectories: 150,
        successful_trajectories: 128,
        duration_ms: 45000,
        convergence_step: 3,
        correlation_id: "opt_12345",
        metadata: %{model: "gpt-4"}
      }

      assert {:ok, validated} = SinterSchemas.validate_optimization_result(valid_result)
      assert validated.success == true
      assert validated.improvement_delta == 0.25
    end

    test "validates improvement delta bounds" do
      invalid_result = %{
        success: true,
        improved: false,
        initial_score: 0.8,
        final_score: 0.6,
        # Invalid: < -1.0
        improvement_delta: -1.5,
        steps_taken: 3,
        strategies_applied: ["append_demo"],
        total_trajectories: 50,
        successful_trajectories: 30,
        duration_ms: 15000
      }

      assert {:error, errors} = SinterSchemas.validate_optimization_result(invalid_result)
      assert Enum.any?(errors, fn error -> error.path == [:improvement_delta] end)
    end
  end

  describe "bucket_statistics_schema/0" do
    test "validates complete bucket statistics" do
      valid_stats = %{
        trajectory_count: 25,
        successful_count: 20,
        failed_count: 5,
        max_score: 0.95,
        min_score: 0.4,
        avg_score: 0.7,
        median_score: 0.72,
        score_variance: 0.025,
        score_std_dev: 0.158,
        improvement_potential: true,
        strategy_applicable: true,
        metadata: %{bucket_id: "bucket_001"}
      }

      assert {:ok, validated} = SinterSchemas.validate_bucket_statistics(valid_stats)
      assert validated.trajectory_count == 25
      assert validated.improvement_potential == true
    end

    test "validates count consistency" do
      # Note: This test validates the schema accepts the data,
      # but doesn't validate business logic like successful_count + failed_count == trajectory_count
      valid_stats = %{
        trajectory_count: 10,
        successful_count: 7,
        failed_count: 3,
        max_score: 0.9,
        min_score: 0.5,
        avg_score: 0.75,
        score_variance: 0.02,
        improvement_potential: true
      }

      assert {:ok, _validated} = SinterSchemas.validate_bucket_statistics(valid_stats)
    end
  end

  describe "batch validation helpers" do
    test "validate_trajectories/1 validates multiple trajectories" do
      trajectories = [
        %{
          inputs: %{q: "1+1"},
          outputs: %{a: "2"},
          score: 0.9,
          success: true
        },
        %{
          inputs: %{q: "2+2"},
          outputs: %{a: "4"},
          score: 0.85,
          success: true
        }
      ]

      assert {:ok, validated_list} = SinterSchemas.validate_trajectories(trajectories)
      assert length(validated_list) == 2
      assert Enum.all?(validated_list, &(&1.success == true))
    end

    test "validate_training_examples/1 validates multiple examples" do
      examples = [
        %{inputs: %{q: "What is AI?"}, outputs: %{a: "Artificial Intelligence"}},
        %{inputs: %{q: "Define ML"}, outputs: %{a: "Machine Learning"}}
      ]

      assert {:ok, validated_list} = SinterSchemas.validate_training_examples(examples)
      assert length(validated_list) == 2
      # Default value
      assert Enum.all?(validated_list, &(&1.validated == false))
    end

    test "batch validation handles mixed valid/invalid data" do
      mixed_trajectories = [
        %{
          inputs: %{q: "1+1"},
          outputs: %{a: "2"},
          score: 0.9,
          success: true
        },
        %{
          inputs: %{q: "2+2"},
          outputs: %{a: "4"},
          # Invalid score
          score: 1.5,
          success: true
        }
      ]

      assert {:error, errors} = SinterSchemas.validate_trajectories(mixed_trajectories)
      assert length(errors) > 0
    end
  end
end
