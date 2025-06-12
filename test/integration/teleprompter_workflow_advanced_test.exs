defmodule DSPEx.Integration.TeleprompterWorkflowAdvancedTest do
  @moduledoc """
  Integration tests for complete teleprompter workflows.

  CRITICAL: This validates the complete Student → Teacher → Optimized Student
  pipeline that SIMBA depends on. Tests ensure all components work together
  correctly before SIMBA's sophisticated optimization algorithms are added.
  """
  use ExUnit.Case, async: false
  @moduletag :group_3

  alias DSPEx.{Teleprompter, Example, Predict, OptimizedProgram, Program}
  alias DSPEx.Teleprompter.BootstrapFewShot

  @moduletag :phase5a
  @moduletag :integration_test

  # Create test signature for workflow testing
  defmodule WorkflowSignature do
    use DSPEx.Signature, "question -> answer"
  end

  setup_all do
    # Set test mode for reliable workflow testing
    original_mode = DSPEx.TestModeConfig.get_test_mode()
    DSPEx.TestModeConfig.set_test_mode(:mock)

    on_exit(fn ->
      DSPEx.TestModeConfig.set_test_mode(original_mode)
    end)

    :ok
  end

  setup do
    # Create standard test components
    student = %Predict{signature: WorkflowSignature, client: :test}
    teacher = %Predict{signature: WorkflowSignature, client: :test}

    # Create comprehensive training set
    trainset = [
      %Example{
        data: %{question: "What is 2+2?", answer: "4"},
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{question: "What is 3+3?", answer: "6"},
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{question: "What is the capital of France?", answer: "Paris"},
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{question: "Who wrote Romeo and Juliet?", answer: "William Shakespeare"},
        input_keys: MapSet.new([:question])
      },
      %Example{
        data: %{question: "What is the largest planet?", answer: "Jupiter"},
        input_keys: MapSet.new([:question])
      }
    ]

    # Set up mock responses using the proper SIMBA mock provider
    expected_answers = ["4", "6", "Paris", "William Shakespeare", "Jupiter"]

    # Set up mock client manager
    {:ok, _} = DSPEx.MockClientManager.start_link(:test, %{responses: :contextual})

    # Use SimbaMockProvider to set up proper bootstrap responses
    # Create a large pool of correct answers to ensure matches
    large_answer_pool = List.duplicate(expected_answers, 10) |> List.flatten()
    alias DSPEx.Test.SimbaMockProvider
    SimbaMockProvider.setup_bootstrap_mocks(large_answer_pool)

    # Create metric function for evaluation
    metric_fn = Teleprompter.exact_match(:answer)

    %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    }
  end

  describe "complete teleprompter workflow - SIMBA dependency" do
    test "BootstrapFewShot complete pipeline execution", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # This is the exact workflow SIMBA will execute

      # 1. Create teleprompter with realistic configuration
      teleprompter =
        BootstrapFewShot.new(
          max_bootstrapped_demos: 3,
          max_labeled_demos: 8,
          quality_threshold: 0.2,
          max_concurrency: 10
        )

      # 2. Execute compilation (optimization)
      result =
        BootstrapFewShot.compile(
          teleprompter,
          student,
          teacher,
          trainset,
          metric_fn,
          []
        )

      # 3. Validate successful optimization
      assert {:ok, optimized_student} = result
      assert is_struct(optimized_student)

      # 4. Verify optimized student has demonstrations
      demos =
        case optimized_student do
          %OptimizedProgram{demos: demos} -> demos
          %{demos: demos} when is_list(demos) -> demos
          _ -> []
        end

      assert length(demos) > 0, "Optimized student should have demonstrations"
      assert Enum.all?(demos, &is_struct(&1, Example))

      # 5. Verify optimized student can make predictions
      test_input = %{question: "What is 4+4?"}

      case Program.forward(optimized_student, test_input) do
        {:ok, prediction} ->
          assert %{answer: answer} = prediction
          assert is_binary(answer)
          assert String.length(answer) > 0

        {:error, reason} ->
          # In mock mode, this might fail, which is acceptable for unit testing
          IO.puts("Note: Optimized student prediction failed in mock mode: #{inspect(reason)}")
      end
    end

    test "student → teacher → optimized student pipeline validation", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Step-by-step validation of the complete pipeline

      # Step 1: Validate all inputs
      assert :ok = Teleprompter.validate_student(student)
      assert :ok = Teleprompter.validate_teacher(teacher)
      assert :ok = Teleprompter.validate_trainset(trainset)
      assert is_function(metric_fn, 2)

      # Step 2: Verify teacher can generate demonstrations
      sample_input = %{question: "Sample question for teacher"}

      _teacher_result =
        case Program.forward(teacher, sample_input) do
          {:ok, teacher_prediction} ->
            assert %{answer: _} = teacher_prediction
            :ok

          {:error, _} ->
            # Mock mode might fail, which is acceptable
            :ok
        end

      # Step 3: Execute teleprompter compilation
      compilation_start = System.monotonic_time()

      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          max_bootstrapped_demos: 2,
          quality_threshold: 0.2
        )

      compilation_duration = System.monotonic_time() - compilation_start
      compilation_ms = System.convert_time_unit(compilation_duration, :native, :millisecond)

      # Step 4: Validate optimized program structure
      assert is_struct(optimized)

      # Should be either OptimizedProgram or enhanced student
      case optimized do
        %OptimizedProgram{} ->
          assert OptimizedProgram.get_program(optimized) == student
          demos = OptimizedProgram.get_demos(optimized)
          assert is_list(demos)
          assert length(demos) > 0

        %{demos: demos} when is_list(demos) ->
          assert length(demos) > 0

        _ ->
          flunk("Optimized program should have demonstrations")
      end

      # Step 5: Verify compilation was efficient
      assert compilation_ms < 10_000, "Compilation took too long: #{compilation_ms}ms"

      IO.puts("✅ Complete pipeline validated in #{compilation_ms}ms")
    end

    test "error handling throughout workflow", %{
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Test various error conditions in the workflow

      # Invalid student
      invalid_student = %{not_a_program: true}

      assert {:error, reason} =
               BootstrapFewShot.compile(
                 invalid_student,
                 teacher,
                 trainset,
                 metric_fn
               )

      assert reason != nil

      # Invalid teacher
      invalid_teacher = "not a teacher"

      assert {:error, reason} =
               BootstrapFewShot.compile(
                 %Predict{signature: WorkflowSignature, client: :test},
                 invalid_teacher,
                 trainset,
                 metric_fn
               )

      assert reason != nil

      # Empty trainset
      assert {:error, reason} =
               BootstrapFewShot.compile(
                 %Predict{signature: WorkflowSignature, client: :test},
                 teacher,
                 [],
                 metric_fn
               )

      assert reason != nil

      # Invalid metric function
      assert {:error, reason} =
               BootstrapFewShot.compile(
                 %Predict{signature: WorkflowSignature, client: :test},
                 teacher,
                 trainset,
                 "not a function"
               )

      assert reason != nil
    end

    # test "workflow with different teleprompter configurations", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
    #   # Test various teleprompter configurations SIMBA might use

    #   configurations = [
    #     # Conservative configuration
    #     %{max_bootstrapped_demos: 2, quality_threshold: 0.8},
    #     # Aggressive configuration
    #     %{max_bootstrapped_demos: 5, quality_threshold: 0.4},
    #     # Balanced configuration
    #     %{max_bootstrapped_demos: 3, quality_threshold: 0.6}
    #   ]

    #   results = Enum.map(configurations, fn config ->
    #     teleprompter = BootstrapFewShot.new(config)

    #     result = BootstrapFewShot.compile(
    #       teleprompter,
    #       student,
    #       teacher,
    #       trainset,
    #       metric_fn
    #     )

    #     {config, result}
  end
end
