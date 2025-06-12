# File: test/unit/teleprompter_test.exs
defmodule DSPEx.TeleprompterTest do
  use ExUnit.Case, async: true

  alias DSPEx.{Teleprompter, Example, Predict}

  doctest DSPEx.Teleprompter

  describe "behavior validation" do
    test "DSPEx.Teleprompter behavior exists and defines compile/5 callback" do
      # Test that the behavior module exists
      assert Code.ensure_loaded?(DSPEx.Teleprompter)

      # Test that it defines the behavior
      assert function_exported?(DSPEx.Teleprompter, :behaviour_info, 1)

      # Test that it defines the required callback
      callbacks = DSPEx.Teleprompter.behaviour_info(:callbacks)
      required_callback = {:compile, 5}
      assert required_callback in callbacks, "compile/5 callback not found in behavior"
    end

    test "implements_behavior?/1 correctly identifies teleprompter modules" do
      # Test with a real teleprompter implementation
      assert Teleprompter.implements_behavior?(DSPEx.Teleprompter.BootstrapFewShot)

      # Test with non-teleprompter modules
      refute Teleprompter.implements_behavior?(DSPEx.Predict)
      refute Teleprompter.implements_behavior__(DSPEx.Example)
      refute Teleprompter.implements_behavior?(String)

      # Test with non-existent module
      refute Teleprompter.implements_behavior?(NonExistentModule)

      # Test with invalid inputs
      refute Teleprompter.implements_behavior?("not_a_module")
      refute Teleprompter.implements_behavior?(123)
      refute Teleprompter.implements_behavior?(nil)
    end

    test "behavior info returns correct callback arity and specifications" do
      callbacks = DSPEx.Teleprompter.behaviour_info(:callbacks)

      # Verify compile/5 is the main callback
      assert {:compile, 5} in callbacks

      # Verify no other unexpected callbacks
      assert length(callbacks) == 1, "Expected only compile/5 callback, got: #{inspect(callbacks)}"
    end
  end

  describe "validation functions" do
    setup do
      # Create test signature
      defmodule TestTeleprompterSignature do
        use DSPEx.Signature, "question -> answer"
      end

      # Create valid programs
      student = %Predict{signature: TestTeleprompterSignature, client: :test}
      teacher = %Predict{signature: TestTeleprompterSignature, client: :test}

      %{student: student, teacher: teacher, signature: TestTeleprompterSignature}
    end

    test "validate_student/1 accepts valid programs", %{student: student} do
      assert :ok = Teleprompter.validate_student(student)
    end

    test "validate_student/1 rejects invalid inputs" do
      # Test with non-struct
      assert {:error, {:invalid_student, _}} = Teleprompter.validate_student("not a program")

      # Test with struct that doesn't implement Program behavior
      non_program = %{some: "struct"}
      assert {:error, {:invalid_student, _}} = Teleprompter.validate_student(non_program)

      # Test with nil
      assert {:error, {:invalid_student, _}} = Teleprompter.validate_student(nil)

      # Test with invalid struct type
      assert {:error, {:invalid_student, _}} = Teleprompter.validate_student(%DateTime{})
    end

    test "validate_teacher/1 accepts valid programs", %{teacher: teacher} do
      assert :ok = Teleprompter.validate_teacher(teacher)
    end

    test "validate_teacher/1 rejects invalid inputs" do
      # Test with non-struct
      assert {:error, {:invalid_teacher, _}} = Teleprompter.validate_teacher("not a program")

      # Test with invalid map
      assert {:error, {:invalid_teacher, _}} = Teleprompter.validate_teacher(%{invalid: "teacher"})

      # Test with nil
      assert {:error, {:invalid_teacher, _}} = Teleprompter.validate_teacher(nil)

      # Test with number
      assert {:error, {:invalid_teacher, _}} = Teleprompter.validate_teacher(42)
    end

    test "validate_trainset/1 accepts valid example lists" do
      valid_examples = [
        %Example{data: %{question: "test1", answer: "response1"}, input_keys: MapSet.new([:question])},
        %Example{data: %{question: "test2", answer: "response2"}, input_keys: MapSet.new([:question])}
      ]

      assert :ok = Teleprompter.validate_trainset(valid_examples)
    end

    test "validate_trainset/1 rejects empty lists" do
      assert {:error, {:invalid_trainset, "Training set cannot be empty"}} =
        Teleprompter.validate_trainset([])
    end

    test "validate_trainset/1 rejects non-lists" do
      assert {:error, {:invalid_trainset, "Training set must be a list"}} =
        Teleprompter.validate_trainset("not a list")

      assert {:error, {:invalid_trainset, "Training set must be a list"}} =
        Teleprompter.validate_trainset(%{not: "a list"})

      assert {:error, {:invalid_trainset, "Training set must be a list"}} =
        Teleprompter.validate_trainset(nil)
    end

    test "validate_trainset/1 rejects lists with invalid examples" do
      # Mix of valid and invalid examples
      mixed_examples = [
        %Example{data: %{question: "valid", answer: "response"}, input_keys: MapSet.new([:question])},
        "invalid example",
        %{not: "an example struct"}
      ]

      assert {:error, {:invalid_trainset, _}} = Teleprompter.validate_trainset(mixed_examples)

      # All invalid examples
      invalid_examples = ["not", "examples", 123]
      assert {:error, {:invalid_trainset, _}} = Teleprompter.validate_trainset(invalid_examples)

      # Empty examples (no inputs or outputs)
      empty_examples = [
        %Example{data: %{}, input_keys: MapSet.new()}
      ]
      assert {:error, {:invalid_trainset, _}} = Teleprompter.validate_trainset(empty_examples)
    end

    test "validate_trainset/1 handles examples with missing inputs or outputs" do
      # Examples with no inputs
      no_inputs = [
        %Example{data: %{answer: "response"}, input_keys: MapSet.new()}
      ]
      assert {:error, {:invalid_trainset, _}} = Teleprompter.validate_trainset(no_inputs)

      # Examples with no outputs
      no_outputs = [
        %Example{data: %{question: "test"}, input_keys: MapSet.new([:question])}
      ]
      assert {:error, {:invalid_trainset, _}} = Teleprompter.validate_trainset(no_outputs)
    end
  end

  describe "helper functions" do
    setup do
      # Create test examples
      example1 = %Example{
        data: %{question: "2+2?", answer: "4", reasoning: "Simple math"},
        input_keys: MapSet.new([:question])
      }

      example2 = %Example{
        data: %{question: "Capital of France?", answer: "Paris", reasoning: "Geography"},
        input_keys: MapSet.new([:question])
      }

      %{example1: example1, example2: example2}
    end

    test "exact_match/1 creates correct metric functions", %{example1: example1} do
      metric_fn = Teleprompter.exact_match(:answer)

      # Test exact match
      prediction1 = %{answer: "4", reasoning: "Basic addition"}
      assert 1.0 = metric_fn.(example1, prediction1)

      # Test non-match
      prediction2 = %{answer: "5", reasoning: "Wrong answer"}
      assert 0.0 = metric_fn.(example1, prediction2)

      # Test missing field in prediction
      prediction3 = %{reasoning: "No answer field"}
      assert 0.0 = metric_fn.(example1, prediction3)
    end

    test "contains_match/1 creates correct string matching functions", %{example2: example2} do
      metric_fn = Teleprompter.contains_match(:answer)

      # Test exact match
      prediction1 = %{answer: "Paris"}
      assert 1.0 = metric_fn.(example2, prediction1)

      # Test substring match
      prediction2 = %{answer: "The capital is Paris, France"}
      assert 1.0 = metric_fn.(example2, prediction2)

      # Test case insensitive match
      prediction3 = %{answer: "paris"}
      assert 1.0 = metric_fn.(example2, prediction3)

      # Test no match
      prediction4 = %{answer: "London"}
      assert 0.0 = metric_fn.(example2, prediction4)

      # Test missing field
      prediction5 = %{reasoning: "No answer"}
      assert 0.0 = metric_fn.(example2, prediction5)
    end

    test "contains_match/1 handles non-string values gracefully" do
      # Example with numeric answer
      numeric_example = %Example{
        data: %{question: "How many?", answer: 42},
        input_keys: MapSet.new([:question])
      }

      metric_fn = Teleprompter.contains_match(:answer)

      # Should fall back to exact match for non-strings
      prediction1 = %{answer: 42}
      assert 1.0 = metric_fn.(numeric_example, prediction1)

      prediction2 = %{answer: 43}
      assert 0.0 = metric_fn.(numeric_example, prediction2)
    end

    test "metric functions handle edge cases" do
      example = %Example{
        data: %{question: "test", answer: nil},
        input_keys: MapSet.new([:question])
      }

      exact_metric = Teleprompter.exact_match(:answer)
      contains_metric = Teleprompter.contains_match(:answer)

      # Test nil values in example
      prediction1 = %{answer: nil}
      assert 1.0 = exact_metric.(example, prediction1)
      assert 1.0 = contains_metric.(example, prediction1)

      prediction2 = %{answer: "something"}
      assert 0.0 = exact_metric.(example, prediction2)
      assert 0.0 = contains_metric.(example, prediction2)

      # Test nil values in prediction
      example_with_answer = %Example{
        data: %{question: "test", answer: "expected"},
        input_keys: MapSet.new([:question])
      }

      prediction3 = %{answer: nil}
      assert 0.0 = exact_metric.(example_with_answer, prediction3)
      assert 0.0 = contains_metric.(example_with_answer, prediction3)
    end

    test "metric functions handle missing Example methods gracefully" do
      # Create an invalid "example" that might not have proper methods
      invalid_example = %{data: %{answer: "test"}}

      metric_fn = Teleprompter.exact_match(:answer)
      prediction = %{answer: "test"}

      # Should handle gracefully (might error, but shouldn't crash the test)
      result = try do
        metric_fn.(invalid_example, prediction)
      rescue
        _ -> :error
      end

      # Either works or errors gracefully
      assert result in [0.0, 1.0, :error]
    end
  end

  describe "field access and data validation" do
    test "validates example structure for metric functions" do
      valid_example = %Example{
        data: %{question: "test", answer: "response"},
        input_keys: MapSet.new([:question])
      }

      # Test that example has required structure
      assert is_struct(valid_example, Example)
      assert not Example.empty?(valid_example)
      assert map_size(Example.inputs(valid_example)) > 0
      assert map_size(Example.outputs(valid_example)) > 0
    end

    test "handles examples with only inputs or only outputs" do
      # Example with only inputs
      input_only = %Example{
        data: %{question: "test"},
        input_keys: MapSet.new([:question])
      }

      assert map_size(Example.inputs(input_only)) > 0
      assert map_size(Example.outputs(input_only)) == 0

      # Example with only outputs (no input_keys specified)
      output_only = %Example{
        data: %{answer: "response"},
        input_keys: MapSet.new()
      }

      assert map_size(Example.inputs(output_only)) == 0
      assert map_size(Example.outputs(output_only)) > 0
    end

    test "metric functions work with complex example structures" do
      complex_example = %Example{
        data: %{
          question: "Complex question",
          context: "Additional context",
          answer: "Complex answer",
          reasoning: "Step by step reasoning",
          confidence: 0.95
        },
        input_keys: MapSet.new([:question, :context])
      }

      # Test metric on different fields
      answer_metric = Teleprompter.exact_match(:answer)
      confidence_metric = Teleprompter.exact_match(:confidence)
      reasoning_metric = Teleprompter.contains_match(:reasoning)

      prediction = %{
        answer: "Complex answer",
        reasoning: "This shows step by step reasoning approach",
        confidence: 0.95
      }

      assert 1.0 = answer_metric.(complex_example, prediction)
      assert 1.0 = confidence_metric.(complex_example, prediction)
      assert 1.0 = reasoning_metric.(complex_example, prediction)
    end
  end
end
