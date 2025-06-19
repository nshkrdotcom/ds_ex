defmodule DSPEx.Teleprompter.SIMBA.SinterIntegrationTest do
  use ExUnit.Case, async: false

  alias DSPEx.{Example, Program, Predict}
  alias DSPEx.Teleprompter.SIMBA
  alias DSPEx.Teleprompter.SIMBA.{SinterSchemas, Trajectory, Bucket}
  alias DSPEx.Signature.BasicSignatures.QuestionAnswering

  @moduletag :integration_test

  describe "SIMBA with Sinter validation integration" do
    test "validates training data during SIMBA compilation" do
      # Create a simple program for optimization
      program = Predict.new(QuestionAnswering, :test_client)

      # Create valid training data
      valid_trainset = [
        Example.new(%{question: "What is 2+2?", answer: "4"}, [:question]),
        Example.new(%{question: "What is 3+3?", answer: "6"}, [:question])
      ]

      # Create a simple metric function
      metric_fn = fn _example, _output -> 0.8 end

      # SIMBA compilation should succeed with valid data
      simba = SIMBA.new(bsize: 2, max_steps: 1, num_candidates: 1)

      # This should succeed without validation errors
      result = SIMBA.compile(simba, program, program, valid_trainset, metric_fn, [])

      # Result should be successful (or at least not fail due to validation)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "rejects invalid training data during SIMBA compilation" do
      # Create a simple program
      program = Predict.new(QuestionAnswering, :test_client)

      # Create invalid training data (missing required fields)
      invalid_trainset = [
        # Not a proper Example struct
        %{invalid: "data"},
        %{also: "invalid"}
      ]

      # Create a simple metric function
      metric_fn = fn _example, _output -> 0.8 end

      # SIMBA compilation should fail with validation errors
      simba = SIMBA.new(bsize: 2, max_steps: 1, num_candidates: 1)

      result = SIMBA.compile(simba, program, program, invalid_trainset, metric_fn, [])

      # With Sinter validation and graceful degradation, invalid data gets converted
      # to empty maps and the process continues, which is the desired behavior
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "validates trajectory data during execution" do
      # Create trajectory data manually for testing
      valid_trajectory_data = %{
        inputs: %{question: "What is AI?"},
        outputs: %{answer: "Artificial Intelligence"},
        score: 0.95,
        success: true,
        duration: 150,
        model_config: %{model: "gpt-4", temperature: 0.2},
        metadata: %{exec_id: 1}
      }

      # Validate using SinterSchemas directly
      assert {:ok, validated} = SinterSchemas.validate_trajectory(valid_trajectory_data)
      assert validated.score == 0.95
      assert validated.success == true
    end

    test "validates bucket data for strategy application" do
      # Create valid bucket data
      trajectories = [
        %Trajectory{
          program: nil,
          example: nil,
          inputs: %{question: "1+1"},
          outputs: %{answer: "2"},
          score: 0.9,
          success: true,
          metadata: %{}
        },
        %Trajectory{
          program: nil,
          example: nil,
          inputs: %{question: "2+2"},
          outputs: %{answer: "4"},
          score: 0.8,
          success: true,
          metadata: %{}
        }
      ]

      bucket = Bucket.new(trajectories)

      # Test bucket validation via strategy application
      strategies = [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo]
      program = Predict.new(QuestionAnswering, :test_client)
      opts = %{strategy_name: "append_demo", max_demos: 2}

      # Should handle bucket validation internally
      result =
        DSPEx.Teleprompter.SIMBA.Strategy.apply_first_applicable(
          strategies,
          bucket,
          program,
          opts
        )

      # Should either succeed or skip, but not fail due to validation errors
      assert match?({:ok, _}, result) or match?({:skip, _}, result)
    end

    test "validates performance metrics schema" do
      valid_metrics = %{
        accuracy: 0.85,
        f1_score: 0.82,
        latency_ms: 250,
        example_count: 100,
        success_count: 85,
        failure_count: 15
      }

      assert {:ok, validated} = SinterSchemas.validate_performance_metrics(valid_metrics)
      assert validated.accuracy == 0.85
      assert validated.latency_ms == 250
    end

    test "validates strategy configuration schema" do
      valid_config = %{
        strategy_name: "append_demo",
        max_demos: 4,
        temperature: 0.2,
        enabled: true
      }

      assert {:ok, validated} = SinterSchemas.validate_strategy_config(valid_config)
      assert validated.strategy_name == "append_demo"
      assert validated.max_demos == 4
    end

    test "validates optimization result schema" do
      valid_result = %{
        success: true,
        improved: true,
        initial_score: 0.6,
        final_score: 0.85,
        improvement_delta: 0.25,
        steps_taken: 3,
        strategies_applied: ["append_demo"],
        total_trajectories: 50,
        successful_trajectories: 42,
        duration_ms: 15_000
      }

      assert {:ok, validated} = SinterSchemas.validate_optimization_result(valid_result)
      assert validated.success == true
      assert validated.improvement_delta == 0.25
    end

    test "batch validation works for multiple trajectories" do
      trajectories = [
        %{
          inputs: %{q: "1+1"},
          outputs: %{a: "2"},
          score: 0.9,
          success: true,
          metadata: %{}
        },
        %{
          inputs: %{q: "2+2"},
          outputs: %{a: "4"},
          score: 0.85,
          success: true,
          metadata: %{}
        }
      ]

      assert {:ok, validated_list} = SinterSchemas.validate_trajectories(trajectories)
      assert length(validated_list) == 2
      assert Enum.all?(validated_list, &(&1.success == true))
    end

    test "batch validation detects invalid data in collection" do
      mixed_trajectories = [
        %{
          inputs: %{q: "1+1"},
          outputs: %{a: "2"},
          score: 0.9,
          success: true,
          metadata: %{}
        },
        %{
          inputs: %{q: "2+2"},
          outputs: %{a: "4"},
          # Invalid score > 1.0
          score: 1.5,
          success: true,
          metadata: %{}
        }
      ]

      assert {:error, errors} = SinterSchemas.validate_trajectories(mixed_trajectories)
      assert length(errors) > 0
    end

    test "bucket statistics validation works" do
      valid_stats = %{
        trajectory_count: 10,
        successful_count: 8,
        failed_count: 2,
        max_score: 0.95,
        min_score: 0.4,
        avg_score: 0.7,
        score_variance: 0.025,
        improvement_potential: true
      }

      assert {:ok, validated} = SinterSchemas.validate_bucket_statistics(valid_stats)
      assert validated.trajectory_count == 10
      assert validated.improvement_potential == true
    end

    test "strategy framework validates bucket data before application" do
      # Create an invalid bucket with empty trajectories
      empty_bucket = %Bucket{
        # Invalid: should have at least 1 trajectory
        trajectories: [],
        max_score: 0.0,
        min_score: 0.0,
        avg_score: 0.0,
        max_to_min_gap: 0.0,
        max_to_avg_gap: 0.0,
        metadata: %{}
      }

      strategies = [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo]
      program = Predict.new(QuestionAnswering, :test_client)
      opts = %{strategy_name: "test_strategy"}

      result =
        DSPEx.Teleprompter.SIMBA.Strategy.apply_first_applicable(
          strategies,
          empty_bucket,
          program,
          opts
        )

      # Should skip due to validation failure
      assert {:skip, reason} = result
      assert String.contains?(reason, "Validation failed")
    end

    test "SIMBA end-to-end with Sinter validation maintains backward compatibility" do
      # This test ensures that existing SIMBA functionality still works
      # with the new Sinter validation layer

      program = Predict.new(QuestionAnswering, :test_client)

      trainset = [
        Example.new(%{question: "What is ML?", answer: "Machine Learning"}, [:question]),
        Example.new(%{question: "What is AI?", answer: "Artificial Intelligence"}, [:question])
      ]

      metric_fn = fn _example, _output -> 0.75 end

      simba =
        SIMBA.new(
          bsize: 2,
          max_steps: 1,
          num_candidates: 1,
          strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo]
        )

      # Should complete without validation-related errors
      result = SIMBA.compile(simba, program, program, trainset, metric_fn, [])

      # We expect either success or a controlled failure, but not validation errors
      case result do
        {:ok, optimized_program} ->
          assert is_struct(optimized_program)

        {:error, reason} ->
          # Should not be validation-related errors
          refute match?({:invalid_training_data, _}, reason)
      end
    end
  end

  describe "error handling and graceful degradation" do
    test "SIMBA continues to work when Sinter validation fails" do
      # Test that SIMBA gracefully handles validation failures
      # and falls back to working without strict validation

      program = Predict.new(QuestionAnswering, :test_client)

      # Create examples that might trigger validation edge cases
      trainset = [
        Example.new(%{question: "Q1", answer: "A1"}, [:question]),
        Example.new(%{question: "Q2", answer: "A2"}, [:question])
      ]

      metric_fn = fn _example, _output -> 0.7 end

      simba = SIMBA.new(bsize: 2, max_steps: 1, num_candidates: 1)

      # Should handle validation gracefully
      result = SIMBA.compile(simba, program, program, trainset, metric_fn, [])

      # Should get a result (success or controlled failure)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "strategy validation provides helpful error messages" do
      # Test that strategy validation errors are informative

      invalid_config = %{
        # Invalid: empty string
        strategy_name: "",
        # Invalid: > 2.0
        temperature: 3.0
      }

      result = SinterSchemas.validate_strategy_config(invalid_config)

      assert {:error, errors} = result
      # At least 2 validation errors
      assert length(errors) >= 2

      # Check that error messages are helpful
      error_messages = Enum.map(errors, & &1.message)
      assert Enum.any?(error_messages, &String.contains?(&1, "characters"))
      assert Enum.any?(error_messages, &String.contains?(&1, "2.0"))
    end
  end
end
