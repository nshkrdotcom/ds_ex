defmodule DSPEx.TeleprompterAdvancedTest do
  @moduledoc """
  Advanced unit tests for DSPEx.Teleprompter behavior.

  CRITICAL: This test validates the teleprompter behavior that BEACON depends on.
  Without this behavior properly defined, BEACON will fail to compile.
  """
  use ExUnit.Case, async: true
  @moduletag :group_3

  alias DSPEx.{Teleprompter, Example, Predict}

  # Create a test signature for validation
  defmodule TestSignature do
    use DSPEx.Signature, "question -> answer"
  end

  # Create a mock teleprompter for behavior testing
  defmodule MockTeleprompter do
    @behaviour DSPEx.Teleprompter

    @impl DSPEx.Teleprompter
    def compile(student, _teacher, _trainset, _metric_fn, opts \\ []) do
      # Simple mock implementation
      case Keyword.get(opts, :should_fail, false) do
        true -> {:error, :mock_failure}
        # Return student unchanged for testing
        false -> {:ok, student}
      end
    end
  end

  describe "behavior validation" do
    test "implements_behavior?/1 correctly identifies teleprompters" do
      # Test with valid teleprompter
      assert Teleprompter.implements_behavior?(MockTeleprompter)
      assert Teleprompter.implements_behavior?(DSPEx.Teleprompter.BootstrapFewShot)

      # Test with non-teleprompter modules
      refute Teleprompter.implements_behavior?(DSPEx.Predict)
      refute Teleprompter.implements_behavior?(DSPEx.Example)
      refute Teleprompter.implements_behavior?(NonExistentModule)
    end

    test "behavior info includes required callbacks" do
      callbacks = DSPEx.Teleprompter.behaviour_info(:callbacks)

      # Must include compile/5 callback for BEACON compatibility
      assert {:compile, 5} in callbacks
    end

    test "mock teleprompter implements behavior correctly" do
      student = %Predict{signature: TestSignature, client: :test}
      teacher = %Predict{signature: TestSignature, client: :test}
      trainset = [create_test_example()]
      metric_fn = fn _example, _prediction -> 1.0 end

      # Test successful compilation
      assert {:ok, result} = MockTeleprompter.compile(student, teacher, trainset, metric_fn)
      assert result == student

      # Test failure case
      assert {:error, :mock_failure} =
               MockTeleprompter.compile(
                 student,
                 teacher,
                 trainset,
                 metric_fn,
                 should_fail: true
               )
    end
  end

  describe "validation functions" do
    test "validate_student/1 accepts valid programs" do
      valid_student = %Predict{signature: TestSignature, client: :test}
      assert :ok = Teleprompter.validate_student(valid_student)
    end

    test "validate_student/1 rejects invalid students" do
      # Test with non-struct
      assert {:error, :invalid_student_program} = Teleprompter.validate_student("not a program")

      # Test with struct that doesn't implement Program behavior
      invalid_student = %{not_a_program: true}
      assert {:error, :invalid_student_program} = Teleprompter.validate_student(invalid_student)
    end

    test "validate_teacher/1 accepts valid programs" do
      valid_teacher = %Predict{signature: TestSignature, client: :test}
      assert :ok = Teleprompter.validate_teacher(valid_teacher)
    end

    test "validate_teacher/1 rejects invalid teachers" do
      # Test with non-struct
      assert {:error, :invalid_teacher_program} = Teleprompter.validate_teacher(nil)

      # Test with invalid struct
      assert {:error, :invalid_teacher_program} = Teleprompter.validate_teacher(%{invalid: true})
    end

    test "validate_trainset/1 accepts valid example lists" do
      valid_trainset = [
        create_test_example("What is 2+2?", "4"),
        create_test_example("What is 3+3?", "6")
      ]

      assert :ok = Teleprompter.validate_trainset(valid_trainset)
    end

    test "validate_trainset/1 rejects invalid trainsets" do
      # Empty trainset
      assert {:error, :trainset_cannot_be_empty} = Teleprompter.validate_trainset([])

      # Non-list trainset
      assert {:error, :trainset_must_be_list} = Teleprompter.validate_trainset("not a list")

      # List with invalid examples
      invalid_trainset = [
        create_test_example("Valid", "Example"),
        %{not_an_example: true}
      ]

      assert {:error, :trainset_must_contain_examples} =
               Teleprompter.validate_trainset(invalid_trainset)
    end
  end

  describe "helper functions" do
    test "exact_match/1 creates correct metric function" do
      metric_fn = Teleprompter.exact_match(:answer)
      assert is_function(metric_fn, 2)

      # Test exact match
      example = create_test_example("Test", "Expected")
      prediction = %{answer: "Expected"}
      assert 1.0 = metric_fn.(example, prediction)

      # Test non-match
      prediction_wrong = %{answer: "Wrong"}
      assert +0.0 = metric_fn.(example, prediction_wrong)
    end

    test "contains_match/1 creates correct metric function" do
      metric_fn = Teleprompter.contains_match(:answer)
      assert is_function(metric_fn, 2)

      example = create_test_example("Test", "The answer is Paris")

      # Test contains match
      prediction_contains = %{answer: "Paris is the capital"}
      assert 1.0 = metric_fn.(example, prediction_contains)

      # Test exact match
      prediction_exact = %{answer: "The answer is Paris"}
      assert 1.0 = metric_fn.(example, prediction_exact)

      # Test no match
      prediction_wrong = %{answer: "London"}
      assert +0.0 = metric_fn.(example, prediction_wrong)
    end

    test "contains_match/1 handles case insensitivity" do
      metric_fn = Teleprompter.contains_match(:answer)
      example = create_test_example("Test", "PARIS")

      # Test case insensitive match
      prediction = %{answer: "paris is the city"}
      assert 1.0 = metric_fn.(example, prediction)
    end

    test "metric functions handle missing fields gracefully" do
      exact_metric = Teleprompter.exact_match(:answer)
      contains_metric = Teleprompter.contains_match(:answer)

      example = create_test_example("Test", "Answer")
      prediction_missing = %{other_field: "value"}

      # Should handle missing fields without crashing
      assert +0.0 = exact_metric.(example, prediction_missing)
      assert +0.0 = contains_metric.(example, prediction_missing)
    end

    test "metric functions handle non-string values" do
      metric_fn = Teleprompter.contains_match(:score)

      example = %Example{
        data: %{question: "Test", score: 42},
        input_keys: MapSet.new([:question])
      }

      # Numeric exact match
      prediction_exact = %{score: 42}
      assert 1.0 = metric_fn.(example, prediction_exact)

      # Numeric non-match
      prediction_wrong = %{score: 24}
      assert +0.0 = metric_fn.(example, prediction_wrong)
    end
  end

  describe "integration with BootstrapFewShot" do
    test "BootstrapFewShot implements teleprompter behavior" do
      assert Teleprompter.implements_behavior?(DSPEx.Teleprompter.BootstrapFewShot)
    end

    test "BootstrapFewShot has required functions" do
      # Verify the module loads and has expected functions
      assert Code.ensure_loaded?(DSPEx.Teleprompter.BootstrapFewShot)
      assert function_exported?(DSPEx.Teleprompter.BootstrapFewShot, :compile, 5)
      # struct version
      assert function_exported?(DSPEx.Teleprompter.BootstrapFewShot, :compile, 6)
      assert function_exported?(DSPEx.Teleprompter.BootstrapFewShot, :new, 1)
    end
  end

  describe "edge cases and error handling" do
    test "handles malformed examples in validation" do
      malformed_trainset = [
        # Empty example
        %Example{data: %{}, input_keys: MapSet.new()},
        create_test_example("Valid", "Example")
      ]

      # These are still valid Example structs, so validation should pass
      # The validation function only checks type, not content validity
      assert :ok = Teleprompter.validate_trainset(malformed_trainset)
    end

    test "metric functions handle edge cases" do
      metric_fn = Teleprompter.exact_match(:answer)

      # Test with empty example
      empty_example = %Example{data: %{}, input_keys: MapSet.new()}
      prediction = %{answer: "test"}

      # Should handle gracefully
      assert +0.0 = metric_fn.(empty_example, prediction)
    end

    test "validation handles modules that don't exist" do
      refute Teleprompter.implements_behavior?(NonExistentTeleprompter)
    end
  end

  # Helper function to create test examples
  defp create_test_example(question \\ "Test question", answer \\ "Test answer") do
    %Example{
      data: %{question: question, answer: answer},
      input_keys: MapSet.new([:question])
    }
  end
end
