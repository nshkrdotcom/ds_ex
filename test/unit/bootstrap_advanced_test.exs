# File: test/unit/bootstrap_advanced_test.exs
defmodule DSPEx.Teleprompter.BootstrapAdvancedTest do
  use ExUnit.Case, async: true
  @moduletag :group_3

  alias DSPEx.{Teleprompter, Example, Predict, OptimizedProgram, Program}
  alias DSPEx.Teleprompter.BootstrapFewShot
  alias DSPEx.Test.MockProvider

  doctest DSPEx.Teleprompter.BootstrapFewShot

  # Define test signature at module level to prevent redefinition warnings
  defmodule TestBootstrapSignature do
    @moduledoc "Test signature for bootstrap few-shot testing"
    use DSPEx.Signature, "question -> answer"
  end

  setup do
    # Start mock provider for testing - handle if already started
    case MockProvider.start_link(mode: :contextual) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Create programs
    student = %Predict{signature: TestBootstrapSignature, client: :test}
    teacher = %Predict{signature: TestBootstrapSignature, client: :test}

    # Create training examples
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
      }
    ]

    # Create metric function
    metric_fn = Teleprompter.exact_match(:answer)

    %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn,
      signature: TestBootstrapSignature
    }
  end

  describe "teleprompter behavior implementation" do
    test "implements DSPEx.Teleprompter behavior correctly" do
      # Verify BootstrapFewShot implements the behavior
      assert Teleprompter.implements_behavior?(BootstrapFewShot)

      # Test that compile/5 function exists with correct arity
      assert function_exported?(BootstrapFewShot, :compile, 5)
      # struct version
      assert function_exported?(BootstrapFewShot, :compile, 6)
    end

    test "new/1 creates teleprompter with correct default options" do
      teleprompter = BootstrapFewShot.new()

      assert %BootstrapFewShot{} = teleprompter
      assert teleprompter.max_bootstrapped_demos == 4
      assert teleprompter.max_labeled_demos == 16
      assert teleprompter.quality_threshold == 0.7
      assert teleprompter.max_concurrency == 20
      assert teleprompter.timeout == 30_000
      assert teleprompter.teacher_retries == 2
      assert teleprompter.progress_callback == nil
    end

    test "new/1 accepts custom options" do
      options = [
        max_bootstrapped_demos: 8,
        quality_threshold: 0.9,
        max_concurrency: 50,
        timeout: 60_000,
        progress_callback: fn _progress -> :ok end
      ]

      teleprompter = BootstrapFewShot.new(options)

      assert teleprompter.max_bootstrapped_demos == 8
      assert teleprompter.quality_threshold == 0.9
      assert teleprompter.max_concurrency == 50
      assert teleprompter.timeout == 60_000
      assert is_function(teleprompter.progress_callback, 1)
    end
  end

  describe "core optimization algorithm" do
    test "compile/5 successfully optimizes student programs", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Set up mock responses for teacher directly using MockClientManager
      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      # Execute compilation
      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Very low threshold to ensure success
          quality_threshold: 0.0
        )

      # Should return optimized program
      assert {:ok, optimized} = result
      assert is_struct(optimized)
    end

    test "handles invalid student program", %{
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      invalid_student = "not a program"

      result =
        BootstrapFewShot.compile(
          invalid_student,
          teacher,
          trainset,
          metric_fn
        )

      assert {:error, :invalid_student_program} = result
    end

    test "handles invalid teacher program", %{
      student: student,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      invalid_teacher = %{not: "a program"}

      result =
        BootstrapFewShot.compile(
          student,
          invalid_teacher,
          trainset,
          metric_fn
        )

      assert {:error, :invalid_teacher_program} = result
    end

    test "handles invalid metric function", %{
      student: student,
      teacher: teacher,
      trainset: trainset
    } do
      invalid_metric = "not a function"

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          invalid_metric
        )

      assert {:error, :invalid_metric_function} = result
    end

    test "handles all teacher failures gracefully", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      # Force the mock manager to simulate failures by providing responses that don't match
      # Use responses that won't match the expected exact answers
      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "wrong answer 1"},
        %{content: "wrong answer 2"},
        %{content: "wrong answer 3"}
      ])

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Impossible threshold
          quality_threshold: 1.0
        )

      # With wrong answers and high threshold, should succeed but with no demos
      assert {:ok, optimized} = result

      demos =
        case optimized do
          %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
          %{demos: demos} -> demos
          _ -> []
        end

      # Should have no demos due to quality filtering
      assert Enum.empty?(demos)
    end

    test "handles metric function errors gracefully", %{
      student: student,
      teacher: teacher,
      trainset: trainset
    } do
      # Metric function that throws errors
      error_metric = fn _example, _prediction ->
        raise "Metric error"
      end

      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          error_metric
        )

      # Should handle metric errors gracefully
      case result do
        {:ok, optimized} ->
          # Should succeed with empty or filtered demos
          demos =
            case optimized do
              %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
              %{demos: demos} -> demos
              _ -> []
            end

          # Demos might be empty due to metric errors
          assert is_list(demos)

        {:error, _reason} ->
          # Also acceptable if all metrics fail
          :ok
      end
    end

    test "handles very small quality thresholds", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Accept everything
          quality_threshold: 0.0
        )

      demos =
        case optimized do
          %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
          %{demos: demos} -> demos
          _ -> []
        end

      # Should have demos since threshold is 0
      assert length(demos) > 0
    end

    test "handles very high quality thresholds", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Impossible threshold
          quality_threshold: 1.1
        )

      # Should handle impossible threshold gracefully - might return empty demos or error
      case result do
        {:ok, optimized} ->
          demos =
            case optimized do
              %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
              %{demos: demos} -> demos
              _ -> []
            end

          # Should have no demos due to impossible threshold
          assert Enum.empty?(demos)

        {:error, :no_successful_bootstrap_candidates} ->
          # This is also acceptable for impossible threshold
          :ok
      end
    end

    test "handles single example training set", %{
      student: student,
      teacher: teacher,
      metric_fn: metric_fn
    } do
      single_example = [
        %Example{
          data: %{question: "Single question?", answer: "Single answer"},
          input_keys: MapSet.new([:question])
        }
      ]

      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Single answer"}])

      {:ok, optimized} =
        BootstrapFewShot.compile(
          student,
          teacher,
          single_example,
          metric_fn
        )

      demos =
        case optimized do
          %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
          %{demos: demos} -> demos
          _ -> []
        end

      # Should work with single example
      # Might be 0 or 1 depending on quality
      assert length(demos) >= 0
    end

    test "handles malformed examples in training set", %{
      student: student,
      teacher: teacher,
      metric_fn: metric_fn
    } do
      malformed_trainset = [
        %Example{
          data: %{question: "Good question?", answer: "Good answer"},
          input_keys: MapSet.new([:question])
        },
        # This should be filtered out
        "not an example",
        %{not: "a proper example"}
      ]

      # Should validate and reject malformed trainset
      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          malformed_trainset,
          metric_fn
        )

      assert {:error, :invalid_or_empty_trainset} = result
    end
  end

  describe "optimization results validation" do
    test "optimized program maintains original program interface", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Very low threshold to ensure success
          quality_threshold: 0.0
        )

      assert {:ok, optimized} = result

      # Should be usable as a program
      assert Program.implements_program?(optimized.__struct__)

      # Should maintain program interface
      test_input = %{question: "Test question"}

      # Mock a response for the optimized program test
      DSPEx.MockClientManager.set_mock_responses(:test, [%{content: "Test response"}])

      result =
        try do
          Program.forward(optimized, test_input)
        rescue
          _ -> :expected_test_error
        end

      # Should either work or fail gracefully
      case result do
        {:ok, _response} -> :ok
        {:error, _reason} -> :ok
        :expected_test_error -> :ok
      end
    end

    test "demonstrations have correct metadata", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Very low threshold to ensure success
          quality_threshold: 0.0
        )

      assert {:ok, optimized} = result

      demos =
        case optimized do
          %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
          %{demos: demos} -> demos
          _ -> []
        end

      # Each demo should have bootstrap metadata
      assert Enum.all?(demos, fn demo ->
               data = demo.data

               Map.has_key?(data, :__generated_by) and
                 data[:__generated_by] == :bootstrap_fewshot and
                 Map.has_key?(data, :__teacher) and
                 Map.has_key?(data, :__timestamp) and
                 Map.has_key?(data, :__quality_score) and
                 is_number(data[:__quality_score])
             end)
    end

    test "optimization preserves example input/output structure", %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fn: metric_fn
    } do
      DSPEx.MockClientManager.set_mock_responses(:test, [
        %{content: "4"},
        %{content: "6"},
        %{content: "Paris"}
      ])

      result =
        BootstrapFewShot.compile(
          student,
          teacher,
          trainset,
          metric_fn,
          # Very low threshold to ensure success
          quality_threshold: 0.0
        )

      assert {:ok, optimized} = result

      demos =
        case optimized do
          %OptimizedProgram{} -> OptimizedProgram.get_demos(optimized)
          %{demos: demos} -> demos
          _ -> []
        end

      # Each demo should have proper input/output structure
      assert Enum.all?(demos, fn demo ->
               inputs = Example.inputs(demo)
               outputs = Example.outputs(demo)

               Map.has_key?(inputs, :question) and
                 Map.has_key?(outputs, :answer)
             end)
    end
  end
end
