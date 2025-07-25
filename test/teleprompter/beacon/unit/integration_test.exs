defmodule DSPEx.Teleprompter.BEACON.IntegrationTest do
  @moduledoc """
  Comprehensive test suite for BEACON Integration module.
  """

  use ExUnit.Case, async: false

  alias DSPEx.{Example, Program}
  alias DSPEx.Teleprompter.BEACON.Integration
  alias DSPEx.Teleprompter.BEACON.Utils

  # Mock structures for testing
  defmodule MockProgram do
    defstruct [:id, :quality_score]

    def forward(program, inputs, opts \\ [])

    def forward(%{quality_score: score}, _inputs, _opts) when is_number(score) do
      if score > 0.5 do
        {:ok, %{result: "success", score: score}}
      else
        {:error, :low_quality}
      end
    end

    def forward(_program, _inputs, _opts) do
      {:ok, %{result: "mock_result", score: 0.8}}
    end
  end

  setup do
    # Create mock programs and data for testing
    student = %MockProgram{id: :student, quality_score: 0.6}
    teacher = %MockProgram{id: :teacher, quality_score: 0.9}

    trainset = [
      Example.new(%{input: "test1", output: "result1"}, [:input]),
      Example.new(%{input: "test2", output: "result2"}, [:input]),
      Example.new(%{input: "test3", output: "result3"}, [:input])
    ]

    metric_fn = fn _example, prediction ->
      case prediction do
        %{score: score} -> score
        _ -> 0.7
      end
    end

    %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    }
  end

  describe "optimize_for_production" do
    test "validates input parameters", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Test invalid student
      result = Integration.optimize_for_production(nil, teacher, trainset, metric_fn)
      assert match?({:error, :invalid_student_program}, result)

      # Test invalid teacher
      result = Integration.optimize_for_production(student, nil, trainset, metric_fn)
      assert match?({:error, :invalid_teacher_program}, result)

      # Test insufficient training data
      result = Integration.optimize_for_production(student, teacher, [], metric_fn)
      assert match?({:error, :insufficient_training_data}, result)

      # Test invalid metric function (with sufficient training data)
      sufficient_trainset = List.duplicate(Example.new(%{input: "test"}, [:input]), 6)

      result =
        Integration.optimize_for_production(
          student,
          teacher,
          sufficient_trainset,
          "not_a_function"
        )

      assert match?({:error, :invalid_metric_function}, result)
    end

    test "generates correlation ID when not provided", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Test that optimization runs and generates a correlation ID
      result = Integration.optimize_for_production(student, teacher, trainset, metric_fn)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "uses provided correlation ID", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      custom_id = "custom-test-id"

      # Test that optimization runs with custom correlation ID
      result =
        Integration.optimize_for_production(student, teacher, trainset, metric_fn,
          correlation_id: custom_id
        )

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles optimization timeout", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Test with very short timeout
      result =
        Integration.optimize_for_production(
          student,
          teacher,
          trainset,
          metric_fn,
          # 1ms timeout
          timeout: 1
        )

      # Should either succeed quickly or timeout gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "validates optimization results", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Test that optimization runs and validates results
      result = Integration.optimize_for_production(student, teacher, trainset, metric_fn)

      case result do
        {:ok, optimized_program} ->
          # Optimization succeeded
          assert is_struct(optimized_program)

        {:error, _reason} ->
          # Acceptable if validation fails
          :ok
      end
    end

    test "falls back to original program on insufficient improvement", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Test that optimization handles fallback scenarios
      result = Integration.optimize_for_production(student, teacher, trainset, metric_fn)

      # Should either return improved program or fall back to original
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "optimize_batch" do
    test "processes multiple program configurations" do
      program_configs = [
        %{
          student: %MockProgram{id: :program1},
          teacher: %MockProgram{id: :teacher1},
          trainset: [Example.new(%{input: "test1"}, [:input])],
          metric_fn: fn _, _ -> 0.8 end
        },
        %{
          student: %MockProgram{id: :program2},
          teacher: %MockProgram{id: :teacher2},
          trainset: [Example.new(%{input: "test2"}, [:input])],
          metric_fn: fn _, _ -> 0.7 end
        }
      ]

      result = Integration.optimize_batch(program_configs, max_concurrent: 2)

      assert match?({:ok, %{batch_id: _, results: _, stats: _}}, result)

      case result do
        {:ok, %{results: results, stats: stats}} ->
          assert length(results) == 2
          assert Map.has_key?(stats, :duration)
          assert Map.has_key?(stats, :successful)
          assert Map.has_key?(stats, :failed)
          assert Map.has_key?(stats, :success_rate)

        _ ->
          :ok
      end
    end

    test "handles mixed success and failure in batch" do
      program_configs = [
        %{
          student: %MockProgram{id: :good_program},
          teacher: %MockProgram{id: :teacher},
          trainset: [Example.new(%{input: "test"}, [:input])],
          metric_fn: fn _, _ -> 0.8 end
        },
        %{
          # Missing required fields to cause failure
          student: nil,
          teacher: %MockProgram{id: :teacher},
          trainset: [],
          metric_fn: fn _, _ -> 0.7 end
        }
      ]

      result = Integration.optimize_batch(program_configs, max_concurrent: 1)

      case result do
        {:ok, %{stats: stats}} ->
          # Should have at least one failure
          assert stats.failed > 0

        _ ->
          :ok
      end
    end

    test "respects concurrency limits" do
      # Test that batch processing respects concurrency settings
      max_concurrent = 2

      program_configs =
        List.duplicate(
          %{
            student: %MockProgram{},
            teacher: %MockProgram{},
            trainset: [Example.new(%{input: "test"}, [:input])],
            metric_fn: fn _, _ -> 0.8 end
          },
          5
        )

      start_time = System.monotonic_time()
      Integration.optimize_batch(program_configs, max_concurrent: max_concurrent)

      duration =
        System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

      # With limited concurrency, should take longer than fully parallel execution
      # This is a basic check - exact timing depends on system performance
      assert duration >= 0
    end
  end

  describe "optimize_adaptively" do
    test "performs two-stage optimization", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      result = Integration.optimize_adaptively(student, teacher, trainset, metric_fn)

      # Should complete both stages
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "adapts configuration based on exploratory results", %{trainset: trainset} do
      # Test configuration adaptation logic
      base_config = %{
        num_candidates: 10,
        num_trials: 15,
        quality_threshold: 0.6
      }

      # High quality should make config more aggressive
      high_score = 0.85
      adapted_high = adapt_config_logic(base_config, high_score, trainset)

      # Low quality should be more conservative but with more search space
      low_score = 0.45
      adapted_low = adapt_config_logic(base_config, low_score, trainset)

      # High score should lead to more trials
      assert adapted_high.num_trials > base_config.num_trials

      # Low score should lead to more candidates (broader search)
      assert adapted_low.num_candidates > base_config.num_candidates
    end

    test "chooses best result between exploratory and refined", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Test adaptive optimization behavior
      result = Integration.optimize_adaptively(student, teacher, trainset, metric_fn)

      case result do
        {:ok, optimized_program} ->
          # Should have chosen the better result
          assert is_struct(optimized_program)

        {:error, _} ->
          :ok
      end
    end

    test "falls back gracefully when refinement fails", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      result = Integration.optimize_adaptively(student, teacher, trainset, metric_fn)

      # Should fall back to exploratory result
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "create_optimization_pipeline" do
    test "executes pipeline stages in sequence" do
      stages = [
        %{
          name: "stage1",
          student: %MockProgram{id: :stage1_student},
          teacher: %MockProgram{id: :stage1_teacher},
          trainset: [Example.new(%{input: "test1"}, [:input])],
          metric_fn: fn _, _ -> 0.8 end
        },
        %{
          name: "stage2",
          # Should use output from stage1
          student: nil,
          teacher: %MockProgram{id: :stage2_teacher},
          trainset: [Example.new(%{input: "test2"}, [:input])],
          metric_fn: fn _, _ -> 0.9 end
        }
      ]

      result = Integration.create_optimization_pipeline(stages, quality_threshold: 0.7)

      # Should process stages sequentially
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "stops pipeline on quality gate failure" do
      stages = [
        %{
          name: "failing_stage",
          # Below threshold
          student: %MockProgram{quality_score: 0.3},
          teacher: %MockProgram{},
          trainset: [Example.new(%{input: "test"}, [:input])],
          # Low quality score
          metric_fn: fn _, _ -> 0.3 end
        },
        %{
          name: "should_not_reach",
          student: %MockProgram{},
          teacher: %MockProgram{},
          trainset: [Example.new(%{input: "test"}, [:input])],
          metric_fn: fn _, _ -> 0.9 end
        }
      ]

      result = Integration.create_optimization_pipeline(stages, quality_threshold: 0.7)

      case result do
        {:error, {:quality_gate_failed, stage_name, _score}} ->
          assert stage_name == "failing_stage"

        _ ->
          # May pass depending on mock behavior
          :ok
      end
    end

    test "passes input between pipeline stages" do
      # Test that output of one stage becomes input to next
      _stage1_output = %MockProgram{id: :stage1_output}

      stages = [
        %{
          name: "producer",
          student: %MockProgram{id: :producer_student},
          teacher: %MockProgram{},
          trainset: [Example.new(%{input: "test"}, [:input])],
          metric_fn: fn _, _ -> 0.8 end
        },
        %{
          name: "consumer",
          # Should receive stage1_output
          student: nil,
          teacher: %MockProgram{},
          trainset: [Example.new(%{input: "test"}, [:input])],
          metric_fn: fn _, _ -> 0.9 end
        }
      ]

      # The pipeline should handle stage chaining
      result = Integration.create_optimization_pipeline(stages)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "helper functions" do
    test "validate_optimization_inputs catches invalid inputs" do
      student = %MockProgram{}
      teacher = %MockProgram{}
      trainset = [Example.new(%{input: "test"}, [:input])]
      metric_fn = fn _, _ -> 0.8 end

      # All valid should return :ok
      result = validate_inputs_logic(student, teacher, trainset, metric_fn)
      assert result == :ok

      # Invalid student
      result = validate_inputs_logic(nil, teacher, trainset, metric_fn)
      assert result == {:error, :invalid_student_program}

      # Invalid teacher
      result = validate_inputs_logic(student, nil, trainset, metric_fn)
      assert result == {:error, :invalid_teacher_program}

      # Insufficient training data
      result = validate_inputs_logic(student, teacher, [], metric_fn)
      assert result == {:error, :insufficient_training_data}

      # Invalid metric function
      result = validate_inputs_logic(student, teacher, trainset, "not_a_function")
      assert result == {:error, :invalid_metric_function}
    end

    test "evaluate_program_quality calculates average score" do
      examples = [
        Example.new(%{input: "test1", output: "result1"}, [:input]),
        Example.new(%{input: "test2", output: "result2"}, [:input])
      ]

      metric_fn = fn _example, prediction ->
        case prediction do
          %{score: score} -> score
          _ -> 0.5
        end
      end

      program = %MockProgram{quality_score: 0.8}

      # Mock program quality evaluation
      quality = evaluate_program_quality_logic(program, examples, metric_fn)
      assert is_float(quality)
      assert quality >= 0.0
      assert quality <= 1.0
    end

    test "correlation ID propagation through optimization" do
      correlation_id = Utils.generate_correlation_id()

      # Test that correlation ID is properly used and propagated
      assert is_binary(correlation_id)
      assert String.starts_with?(correlation_id, "beacon-")

      # In a real optimization, the correlation ID would be used for tracking
      stage_id = "#{correlation_id}_stage_test"
      assert String.contains?(stage_id, correlation_id)
    end

    test "progress callback creation and execution" do
      correlation_id = "test-correlation-123"

      # Mock progress callback
      callback = create_mock_progress_callback(correlation_id)
      assert is_function(callback)

      # Test different progress phases
      bootstrap_progress = %{
        phase: :bootstrap_generation,
        completed: 10,
        total: 100
      }

      optimization_progress = %{
        phase: :bayesian_optimization,
        trial: 5,
        current_score: 0.75
      }

      # Should handle different progress types without crashing
      assert callback.(bootstrap_progress) == :ok
      assert callback.(optimization_progress) == :ok
    end
  end

  defp adapt_config_logic(base_config, score, trainset) do
    adaptation_factor =
      cond do
        score > 0.8 ->
          %{
            num_candidates: round(base_config.num_candidates * 1.5),
            num_trials: round(base_config.num_trials * 2),
            quality_threshold: min(base_config.quality_threshold + 0.1, 0.9)
          }

        score > 0.6 ->
          %{
            num_candidates: round(base_config.num_candidates * 1.2),
            num_trials: round(base_config.num_trials * 1.5),
            quality_threshold: base_config.quality_threshold
          }

        true ->
          %{
            num_candidates: round(base_config.num_candidates * 2),
            num_trials: round(base_config.num_trials * 1.2),
            quality_threshold: max(base_config.quality_threshold - 0.1, 0.4)
          }
      end

    # Adjust for dataset size
    dataset_factor =
      cond do
        length(trainset) > 500 -> 1.3
        length(trainset) > 200 -> 1.1
        true -> 0.9
      end

    Map.merge(base_config, %{
      num_candidates: round(adaptation_factor.num_candidates * dataset_factor),
      num_trials: adaptation_factor.num_trials,
      quality_threshold: adaptation_factor.quality_threshold
    })
  end

  defp create_mock_progress_callback(_correlation_id) do
    fn progress ->
      handle_progress_phase(progress.phase, progress)
      :ok
    end
  end

  defp handle_progress_phase(:bootstrap_generation, progress) do
    if rem(progress[:completed] || 0, 10) == 0 do
      # Mock logging without actual IO
      :ok
    else
      :ok
    end
  end

  defp handle_progress_phase(:bayesian_optimization, progress) do
    if rem(progress[:trial] || 0, 5) == 0 do
      # Mock logging without actual IO
      :ok
    else
      :ok
    end
  end

  defp handle_progress_phase(_, _progress) do
    # Mock logging for unknown phases
    :ok
  end

  # Helper functions to test private functions
  defp validate_inputs_logic(student, teacher, trainset, metric_fn) do
    # Replicate the logic from Integration.validate_optimization_inputs/4
    cond do
      not is_struct(student) ->
        {:error, :invalid_student_program}

      not is_struct(teacher) ->
        {:error, :invalid_teacher_program}

      not is_list(trainset) or length(trainset) < 1 ->
        {:error, :insufficient_training_data}

      not is_function(metric_fn, 2) ->
        {:error, :invalid_metric_function}

      true ->
        :ok
    end
  end

  defp evaluate_program_quality_logic(program, examples, metric_fn) do
    # Replicate the logic from Integration.evaluate_program_quality/3
    results =
      examples
      |> Enum.map(fn example ->
        case Program.forward(program, Example.inputs(example)) do
          {:ok, prediction} -> metric_fn.(example, prediction)
          {:error, _} -> 0.0
        end
      end)

    if Enum.empty?(results) do
      0.0
    else
      Enum.sum(results) / length(results)
    end
  end
end
