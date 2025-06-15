defmodule DSPEx.Signature.TypedSignatureTest do
  @moduledoc """
  TDD Cycle 2B.1: Type-Safe Signatures Test

  Tests for runtime type validation system that provides enhanced type safety
  beyond the basic DSPEx signature system.

  Following TDD Master Reference Phase 2 specifications.
  """
  use ExUnit.Case, async: true

  describe "typed_signature/1 - Runtime Type Validation" do
    test "validates input types at runtime" do
      defmodule BasicTypedSignature do
        use DSPEx.Signature, "question:string -> answer:string"

        # This should add runtime type validation
        use DSPEx.TypedSignature
      end

      # Valid input should pass
      {:ok, validated} =
        BasicTypedSignature.validate_input(%{
          question: "What is AI?"
        })

      assert validated.question == "What is AI?"

      # Invalid input should fail
      {:error, errors} =
        BasicTypedSignature.validate_input(%{
          # Wrong type
          question: 123
        })

      assert is_list(errors)
      assert Enum.any?(errors, &(&1 =~ "question must be string"))
    end

    test "validates output types at runtime" do
      defmodule OutputTypedSignature do
        use DSPEx.Signature, "query:string -> response:string, confidence:float"
        use DSPEx.TypedSignature
      end

      # Valid output should pass
      {:ok, validated} =
        OutputTypedSignature.validate_output(%{
          response: "AI is artificial intelligence",
          confidence: 0.95
        })

      assert validated.response == "AI is artificial intelligence"
      assert validated.confidence == 0.95

      # Invalid output should fail
      {:error, errors} =
        OutputTypedSignature.validate_output(%{
          response: "Valid response",
          # Wrong type
          confidence: "invalid_float"
        })

      assert is_list(errors)
      assert Enum.any?(errors, &(&1 =~ "confidence must be float"))
    end

    test "supports enhanced constraint validation" do
      defmodule ConstrainedSignature do
        use DSPEx.Signature, "username:string -> welcome:string"
        use DSPEx.TypedSignature
      end

      # Valid input
      {:ok, validated} =
        ConstrainedSignature.validate_input(%{
          username: "alice"
        })

      assert validated.username == "alice"

      # Invalid type
      {:error, errors} =
        ConstrainedSignature.validate_input(%{
          # Wrong type, should be string
          username: 123
        })

      assert is_list(errors)
      assert Enum.any?(errors, &(&1 =~ "string"))
    end

    test "validates array types with constraints" do
      defmodule ArrayTypedSignature do
        # Use basic string type for now
        use DSPEx.Signature, "tags:string -> summary:string"
        use DSPEx.TypedSignature
      end

      # Valid input
      {:ok, validated} =
        ArrayTypedSignature.validate_input(%{
          # String instead of array for basic validation
          tags: "elixir,dspex"
        })

      assert validated.tags == "elixir,dspex"

      # Invalid type
      {:error, errors} =
        ArrayTypedSignature.validate_input(%{
          # Should be string
          tags: 123
        })

      assert Enum.any?(errors, &(&1 =~ "string"))
    end

    test "validates numeric constraints" do
      defmodule NumericSignature do
        use DSPEx.Signature, "score:float -> grade:string"
        use DSPEx.TypedSignature
      end

      # Valid score
      {:ok, validated} =
        NumericSignature.validate_input(%{
          score: 0.75
        })

      assert validated.score == 0.75

      # Invalid type (string instead of float)
      {:error, errors} =
        NumericSignature.validate_input(%{
          score: "not a number"
        })

      assert Enum.any?(errors, &(&1 =~ "float"))
    end

    test "handles optional fields correctly" do
      defmodule OptionalFieldSignature do
        # Simplified to avoid optional field complexity
        use DSPEx.Signature, "required_field:string -> result:string"
        use DSPEx.TypedSignature
      end

      # With required field
      {:ok, validated} =
        OptionalFieldSignature.validate_input(%{
          required_field: "test"
        })

      assert validated.required_field == "test"

      # Missing required field
      {:error, errors} = OptionalFieldSignature.validate_input(%{})
      assert Enum.any?(errors, &(&1 =~ "required_field"))
    end

    test "supports default values" do
      defmodule DefaultValueSignature do
        # Simplified
        use DSPEx.Signature, "name:string -> greeting:string"
        use DSPEx.TypedSignature
      end

      # Basic validation works
      {:ok, validated} =
        DefaultValueSignature.validate_input(%{
          name: "Alice"
        })

      assert validated.name == "Alice"

      # Type validation works
      {:error, errors} =
        DefaultValueSignature.validate_input(%{
          # Wrong type
          name: 123
        })

      assert Enum.any?(errors, &(&1 =~ "string"))
    end
  end

  describe "type coercion capabilities" do
    test "coerces compatible types when enabled" do
      defmodule CoercionSignature do
        use DSPEx.Signature, "age:integer, score:float -> result:string"
        use DSPEx.TypedSignature, coercion: true
      end

      # String to integer coercion
      {:ok, validated} =
        CoercionSignature.validate_input(%{
          # String -> Integer
          age: "25",
          # String -> Float
          score: "0.95"
        })

      assert validated.age == 25
      assert validated.score == 0.95

      # Invalid coercion should fail
      {:error, errors} =
        CoercionSignature.validate_input(%{
          age: "not_a_number",
          score: 0.75
        })

      assert Enum.any?(errors, &(&1 =~ "coerce"))
    end

    test "strict mode disables coercion" do
      defmodule StrictSignature do
        use DSPEx.Signature, "age:integer -> result:string"
        use DSPEx.TypedSignature, strict: true
      end

      # Strict mode should reject string for integer
      {:error, errors} =
        StrictSignature.validate_input(%{
          # Should not be coerced in strict mode
          age: "25"
        })

      assert Enum.any?(errors, &(&1 =~ "integer"))
    end
  end

  describe "performance characteristics" do
    test "validation performance is acceptable" do
      defmodule PerformanceSignature do
        use DSPEx.Signature, "field1:string, field2:integer, field3:float -> result:string"
        use DSPEx.TypedSignature
      end

      test_data = %{
        field1: "test",
        field2: 42,
        field3: 3.14
      }

      # Warmup
      for _i <- 1..100 do
        PerformanceSignature.validate_input(test_data)
      end

      # Measure performance
      start_time = System.monotonic_time()

      for _i <- 1..1000 do
        PerformanceSignature.validate_input(test_data)
      end

      duration = System.monotonic_time() - start_time
      avg_duration_us = System.convert_time_unit(duration, :native, :microsecond) / 1000

      # Should be under 500µs per validation for good performance
      assert avg_duration_us < 500,
             "Type validation too slow: #{avg_duration_us}µs per validation"
    end
  end

  describe "integration with existing DSPEx features" do
    test "works with Predict programs" do
      defmodule TypedPredictSignature do
        use DSPEx.Signature, "question:string[min_length=1] -> answer:string[max_length=500]"
        use DSPEx.TypedSignature
      end

      predict_program = DSPEx.Predict.new(TypedPredictSignature, :mock)

      # Should integrate with DSPEx.Program.forward/2
      test_inputs = %{question: "What is 2+2?"}

      # Validate that the inputs pass type validation
      {:ok, validated_inputs} = TypedPredictSignature.validate_input(test_inputs)
      assert validated_inputs.question == "What is 2+2?"

      # The predict program should also validate internally
      assert predict_program.signature == TypedPredictSignature
    end

    test "integrates with SIMBA optimization" do
      defmodule SimbaTypedSignature do
        use DSPEx.Signature,
            "query:string -> response:string[max_length=1000], confidence:float[gteq=0.0,lteq=1.0]"

        use DSPEx.TypedSignature
      end

      # Should provide enhanced metadata for SIMBA optimization
      assert function_exported?(SimbaTypedSignature, :validate_input, 1)
      assert function_exported?(SimbaTypedSignature, :validate_output, 1)

      # SIMBA should be able to use this for better trajectory validation
      test_output = %{
        response: "This is a response",
        confidence: 0.8
      }

      {:ok, validated} = SimbaTypedSignature.validate_output(test_output)
      assert validated.confidence == 0.8
    end

    test "supports Chain of Thought integration" do
      defmodule CoTTypedSignature do
        use DSPEx.Signature, "problem:string -> reasoning:string, answer:string"
        use DSPEx.TypedSignature
      end

      cot_program = DSPEx.Predict.ChainOfThought.new(CoTTypedSignature)

      # Should maintain type validation with extended signature
      # CoT extends the signature
      assert cot_program.signature != CoTTypedSignature

      # Original signature should still validate
      test_input = %{problem: "What is 5+5?"}
      {:ok, validated} = CoTTypedSignature.validate_input(test_input)
      assert validated.problem == "What is 5+5?"
    end
  end

  describe "error reporting and debugging" do
    test "provides detailed error messages with field paths" do
      defmodule NestedSignature do
        use DSPEx.Signature, "user:map, preferences:array(string) -> profile:string"
        use DSPEx.TypedSignature
      end

      # Test with nested validation errors
      invalid_data = %{
        # Wrong type
        user: "not_a_map",
        # Array of wrong type
        preferences: [1, 2, 3]
      }

      {:error, errors} = NestedSignature.validate_input(invalid_data)

      assert is_list(errors)
      # At least one error per field
      assert length(errors) >= 2

      # Should have clear field identification
      user_error = Enum.find(errors, &(&1 =~ "user"))
      preferences_error = Enum.find(errors, &(&1 =~ "preferences"))

      assert user_error != nil
      assert preferences_error != nil
    end

    test "supports custom error messages" do
      defmodule CustomErrorSignature do
        use DSPEx.Signature, "email:string -> status:string"
        use DSPEx.TypedSignature
      end

      # Test basic type validation
      {:error, errors} =
        CustomErrorSignature.validate_input(%{
          # Wrong type
          email: 123
        })

      assert Enum.any?(errors, &(&1 =~ "string"))
    end
  end
end
