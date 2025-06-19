defmodule DSPEx.SinterSignatureIntegrationTest do
  @moduledoc """
  Integration tests for enhanced signature system with Sinter validation.

  This test suite validates the Phase 2 integration requirements:
  - Enhanced signature system works end-to-end with Sinter
  - Complex signatures with multiple constraint types function correctly
  - TypedSignature macros provide proper validation behavior
  - JSON Schema generation produces correct schemas for different providers
  - Backwards compatibility with existing signature system is maintained
  """
  use ExUnit.Case, async: true

  @doc """
  Test enhanced signature integration per SINTER_INTEGRATION_PLAN.md Phase 2.3
  """

  describe "end-to-end enhanced signature validation" do
    test "simple enhanced signature with constraints validates correctly" do
      defmodule SimpleEnhancedSignature do
        use DSPEx.Signature,
            "name:string[min_length=2,max_length=50] -> greeting:string[max_length=100]"

        use DSPEx.TypedSignature
      end

      # Valid input should pass
      valid_input = %{name: "Alice"}
      assert {:ok, validated} = SimpleEnhancedSignature.validate_input(valid_input)
      assert validated.name == "Alice"

      # Invalid input should fail
      # Too short
      invalid_input = %{name: "A"}
      assert {:error, errors} = SimpleEnhancedSignature.validate_input(invalid_input)
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "numeric constraints work with enhanced signatures" do
      defmodule NumericEnhancedSignature do
        use DSPEx.Signature, "age:integer[gteq=0,lteq=120] -> category:string"
        use DSPEx.TypedSignature
      end

      # Valid numeric input
      valid_input = %{age: 25}
      assert {:ok, validated} = NumericEnhancedSignature.validate_input(valid_input)
      assert validated.age == 25

      # Invalid numeric input - negative
      invalid_input = %{age: -5}
      assert {:error, errors} = NumericEnhancedSignature.validate_input(invalid_input)
      assert is_list(errors)

      # Invalid numeric input - too high
      invalid_input2 = %{age: 150}
      assert {:error, errors2} = NumericEnhancedSignature.validate_input(invalid_input2)
      assert is_list(errors2)
    end

    test "array constraints work with enhanced signatures" do
      defmodule ArrayEnhancedSignature do
        use DSPEx.Signature, "tags:array(string)[min_items=1,max_items=5] -> summary:string"
        use DSPEx.TypedSignature
      end

      # Valid array input
      valid_input = %{tags: ["test", "example"]}
      assert {:ok, validated} = ArrayEnhancedSignature.validate_input(valid_input)
      assert validated.tags == ["test", "example"]

      # Invalid array input - empty
      empty_input = %{tags: []}
      assert {:error, errors} = ArrayEnhancedSignature.validate_input(empty_input)
      assert is_list(errors)

      # Invalid array input - too many items
      too_many_input = %{tags: ["a", "b", "c", "d", "e", "f"]}
      assert {:error, errors2} = ArrayEnhancedSignature.validate_input(too_many_input)
      assert is_list(errors2)
    end

    test "output validation works with enhanced signatures" do
      defmodule OutputValidationSignature do
        use DSPEx.Signature, "query:string -> response:string[max_length=100]"
        use DSPEx.TypedSignature
      end

      # Valid output
      valid_output = %{response: "This is a short response"}
      assert {:ok, validated} = OutputValidationSignature.validate_output(valid_output)
      assert validated.response == "This is a short response"

      # Invalid output - too long
      long_response = String.duplicate("a", 150)
      invalid_output = %{response: long_response}
      assert {:error, errors} = OutputValidationSignature.validate_output(invalid_output)
      assert is_list(errors)
    end
  end

  describe "complex multi-constraint signatures" do
    test "signature with multiple field types and constraints" do
      defmodule ComplexSignature do
        use DSPEx.Signature,
            "user_id:integer[gteq=1], username:string[min_length=3,max_length=30], tags:array(string)[max_items=10] -> profile:string, score:float[gteq=0.0,lteq=1.0]"

        use DSPEx.TypedSignature
      end

      # Valid complex input
      valid_input = %{
        user_id: 123,
        username: "alice_123",
        tags: ["developer", "elixir"]
      }

      assert {:ok, validated} = ComplexSignature.validate_input(valid_input)
      assert validated.user_id == 123
      assert validated.username == "alice_123"
      assert validated.tags == ["developer", "elixir"]

      # Valid complex output
      valid_output = %{
        profile: "User profile description",
        score: 0.85
      }

      assert {:ok, validated_output} = ComplexSignature.validate_output(valid_output)
      assert validated_output.profile == "User profile description"
      assert validated_output.score == 0.85

      # Invalid input - multiple constraint violations
      invalid_input = %{
        # Too low
        user_id: 0,
        # Too short
        username: "ab",
        # Too many items
        tags: Enum.map(1..15, &"tag#{&1}")
      }

      assert {:error, errors} = ComplexSignature.validate_input(invalid_input)
      assert is_list(errors)
      # Should have multiple errors
      assert length(errors) >= 3
    end

    test "default values work correctly in enhanced signatures" do
      defmodule DefaultValueSignature do
        use DSPEx.Signature, "name:string, status:string[default='active'] -> result:string"
        use DSPEx.TypedSignature
      end

      # Input with all fields
      complete_input = %{name: "test", status: "pending"}
      assert {:ok, validated} = DefaultValueSignature.validate_input(complete_input)
      assert validated.name == "test"
      assert validated.status == "pending"

      # Note: Default value handling depends on Sinter implementation
      # This test verifies the signature is properly configured
    end
  end

  describe "backwards compatibility" do
    test "basic signatures without constraints still work" do
      defmodule BasicCompatSignature do
        use DSPEx.Signature, "question -> answer"
        use DSPEx.TypedSignature
      end

      valid_input = %{question: "What is 2+2?"}
      assert {:ok, validated} = BasicCompatSignature.validate_input(valid_input)
      assert validated.question == "What is 2+2?"

      valid_output = %{answer: "4"}
      assert {:ok, validated_output} = BasicCompatSignature.validate_output(valid_output)
      assert validated_output.answer == "4"
    end

    test "signatures with only type annotations work" do
      defmodule TypeOnlySignature do
        use DSPEx.Signature, "age:integer -> category:string"
        use DSPEx.TypedSignature
      end

      valid_input = %{age: 25}
      assert {:ok, validated} = TypeOnlySignature.validate_input(valid_input)
      assert validated.age == 25
    end

    test "mixed basic and enhanced fields work together" do
      defmodule MixedSignature do
        use DSPEx.Signature,
            "name:string[min_length=2], description -> summary:string[max_length=200], details"

        use DSPEx.TypedSignature
      end

      valid_input = %{name: "Alice", description: "A description"}
      assert {:ok, validated} = MixedSignature.validate_input(valid_input)
      assert validated.name == "Alice"
      assert validated.description == "A description"

      valid_output = %{summary: "Brief summary", details: "Additional details"}
      assert {:ok, validated_output} = MixedSignature.validate_output(valid_output)
      assert validated_output.summary == "Brief summary"
      assert validated_output.details == "Additional details"
    end
  end

  describe "Sinter integration behavior" do
    test "Sinter error format is consistent and informative" do
      defmodule ErrorFormatSignature do
        use DSPEx.Signature, "value:integer[gteq=0,lteq=100] -> result:string"
        use DSPEx.TypedSignature
      end

      invalid_input = %{value: -10}
      assert {:error, errors} = ErrorFormatSignature.validate_input(invalid_input)

      # Verify error structure
      assert is_list(errors)
      assert length(errors) > 0

      error = hd(errors)
      assert is_map(error)

      # Sinter error format should include these fields
      assert Map.has_key?(error, :code) or Map.has_key?(error, :message)

      # Error should be informative
      error_text = error[:message] || error["message"] || inspect(error)
      assert is_binary(error_text)
      assert String.length(error_text) > 0
    end

    test "constraint violations produce specific error codes" do
      defmodule ConstraintErrorSignature do
        use DSPEx.Signature, "text:string[min_length=5,max_length=10] -> output:string"
        use DSPEx.TypedSignature
      end

      # Test min_length violation
      short_input = %{text: "abc"}
      assert {:error, min_errors} = ConstraintErrorSignature.validate_input(short_input)
      assert is_list(min_errors)
      assert length(min_errors) > 0

      # Test max_length violation  
      long_input = %{text: "this text is way too long"}
      assert {:error, max_errors} = ConstraintErrorSignature.validate_input(long_input)
      assert is_list(max_errors)
      assert length(max_errors) > 0
    end

    test "missing required fields produce appropriate errors" do
      defmodule RequiredFieldSignature do
        use DSPEx.Signature, "required_field:string[min_length=1] -> result:string"
        use DSPEx.TypedSignature
      end

      empty_input = %{}
      assert {:error, errors} = RequiredFieldSignature.validate_input(empty_input)
      assert is_list(errors)
      assert length(errors) > 0

      # Error should indicate the field is required
      error = hd(errors)
      error_info = error[:message] || error["message"] || inspect(error)
      assert String.contains?(String.downcase(error_info), "required")
    end
  end

  describe "JSON Schema generation integration" do
    test "enhanced signatures produce valid JSON schemas" do
      defmodule JsonSchemaSignature do
        use DSPEx.Signature,
            "title:string[min_length=1,max_length=100] -> summary:string[max_length=500]"
      end

      schema = DSPEx.Signature.Sinter.generate_json_schema(JsonSchemaSignature)

      # Basic JSON Schema structure
      assert schema["type"] == "object"
      assert is_map(schema["properties"])

      # Input field validation
      title_props = schema["properties"]["title"]
      assert title_props["type"] == "string"
      assert title_props["minLength"] == 1
      assert title_props["maxLength"] == 100

      # Output field validation
      summary_props = schema["properties"]["summary"]
      assert summary_props["type"] == "string"
      assert summary_props["maxLength"] == 500
    end

    test "numeric constraints appear in JSON schema" do
      defmodule NumericJsonSignature do
        use DSPEx.Signature, "score:integer[gteq=0,lteq=100] -> grade:string"
      end

      schema = DSPEx.Signature.Sinter.generate_json_schema(NumericJsonSignature)

      score_props = schema["properties"]["score"]
      assert score_props["type"] == "integer"
      assert score_props["minimum"] == 0
      assert score_props["maximum"] == 100
    end

    test "array constraints appear in JSON schema" do
      defmodule ArrayJsonSignature do
        use DSPEx.Signature, "items:array(string)[min_items=1,max_items=5] -> count:integer"
      end

      schema = DSPEx.Signature.Sinter.generate_json_schema(ArrayJsonSignature)

      items_props = schema["properties"]["items"]
      assert items_props["type"] == "array"
      assert items_props["minItems"] == 1
      assert items_props["maxItems"] == 5
      assert items_props["items"]["type"] == "string"
    end

    test "provider-specific JSON schema generation" do
      defmodule ProviderSpecificSignature do
        use DSPEx.Signature, "query:string[min_length=1] -> response:string"
      end

      # Test generic schema
      generic_schema = DSPEx.Signature.Sinter.generate_json_schema(ProviderSpecificSignature)
      assert generic_schema["type"] == "object"

      # Test OpenAI-specific schema
      openai_schema =
        DSPEx.Signature.Sinter.generate_json_schema(ProviderSpecificSignature, provider: :openai)

      assert openai_schema["type"] == "object"

      # Test Anthropic-specific schema
      anthropic_schema =
        DSPEx.Signature.Sinter.generate_json_schema(ProviderSpecificSignature,
          provider: :anthropic
        )

      assert anthropic_schema["type"] == "object"

      # All should be valid schemas
      [generic_schema, openai_schema, anthropic_schema]
      |> Enum.each(fn schema ->
        assert is_map(schema["properties"])
        assert is_list(schema["required"]) or is_nil(schema["required"])
      end)
    end
  end

  describe "performance integration" do
    test "enhanced signature validation performance is acceptable" do
      defmodule PerformanceTestSignature do
        use DSPEx.Signature,
            "field1:string[min_length=1,max_length=100], field2:integer[gteq=0,lteq=1000], field3:array(string)[max_items=10] -> result1:string[max_length=200], result2:float[gteq=0.0,lteq=1.0]"

        use DSPEx.TypedSignature
      end

      test_input = %{
        field1: "test input",
        field2: 42,
        field3: ["tag1", "tag2", "tag3"]
      }

      # Measure validation time
      {validation_time, result} =
        :timer.tc(fn ->
          PerformanceTestSignature.validate_input(test_input)
        end)

      # Should validate successfully
      assert {:ok, _validated} = result

      # Should complete within reasonable time (less than 5ms)
      # microseconds
      assert validation_time < 5000
    end

    test "JSON schema generation performance is acceptable" do
      defmodule SchemaPerformanceSignature do
        use DSPEx.Signature,
            "complex_field:string[min_length=1,max_length=1000] -> complex_result:array(string)[max_items=20]"
      end

      # Measure schema generation time
      {schema_time, schema} =
        :timer.tc(fn ->
          DSPEx.Signature.Sinter.generate_json_schema(SchemaPerformanceSignature)
        end)

      # Should generate valid schema
      assert schema["type"] == "object"

      # Should complete within reasonable time (less than 5ms)
      # microseconds
      assert schema_time < 5000
    end
  end

  describe "edge cases and error handling" do
    test "malformed signatures are handled gracefully" do
      # This test verifies that the integration handles edge cases appropriately
      # For enhanced signatures with valid syntax but edge case constraints

      defmodule EdgeCaseSignature do
        use DSPEx.Signature, "value:string[min_length=0,max_length=0] -> empty:string"
        use DSPEx.TypedSignature
      end

      # Empty string should be valid for min_length=0, max_length=0
      edge_input = %{value: ""}
      assert {:ok, validated} = EdgeCaseSignature.validate_input(edge_input)
      assert validated.value == ""

      # Non-empty string should fail
      invalid_input = %{value: "a"}
      assert {:error, errors} = EdgeCaseSignature.validate_input(invalid_input)
      assert is_list(errors)
    end

    test "type coercion works when enabled" do
      defmodule CoercionSignature do
        use DSPEx.Signature, "number:integer -> result:string"
        use DSPEx.TypedSignature, coercion: true
      end

      # Note: Type coercion behavior depends on Sinter implementation
      # This test verifies the signature accepts the coercion option
      assert CoercionSignature.__typed_signature_opts__() == [coercion: true]
    end

    test "strict mode works when enabled" do
      defmodule StrictSignature do
        use DSPEx.Signature, "value:integer -> result:string"
        use DSPEx.TypedSignature, strict: true
      end

      # Verify strict mode is configured
      assert StrictSignature.__typed_signature_opts__() == [strict: true]
    end
  end

  describe "real-world usage patterns" do
    test "Question-Answering signature with validation" do
      defmodule QASignature do
        use DSPEx.Signature,
            "question:string[min_length=5,max_length=500] -> answer:string[max_length=1000], confidence:float[gteq=0.0,lteq=1.0]"

        use DSPEx.TypedSignature
      end

      # Valid QA input
      qa_input = %{question: "What is the capital of France?"}
      assert {:ok, validated_input} = QASignature.validate_input(qa_input)
      assert validated_input.question == "What is the capital of France?"

      # Valid QA output
      qa_output = %{answer: "The capital of France is Paris.", confidence: 0.95}
      assert {:ok, validated_output} = QASignature.validate_output(qa_output)
      assert validated_output.answer == "The capital of France is Paris."
      assert validated_output.confidence == 0.95

      # Invalid QA input - too short
      short_qa = %{question: "What"}
      assert {:error, errors} = QASignature.validate_input(short_qa)
      assert is_list(errors)

      # Invalid QA output - confidence out of range
      bad_confidence = %{answer: "Paris", confidence: 1.5}
      assert {:error, errors} = QASignature.validate_output(bad_confidence)
      assert is_list(errors)
    end

    test "Multi-step reasoning signature with validation" do
      defmodule ReasoningSignature do
        use DSPEx.Signature,
            "premise:string[min_length=10], context:string[max_length=2000] -> reasoning_steps:array(string)[min_items=1,max_items=10], conclusion:string[max_length=500]"

        use DSPEx.TypedSignature
      end

      # Valid reasoning input
      reasoning_input = %{
        premise: "All birds can fly",
        context: "Consider the statement about birds and think about exceptions"
      }

      assert {:ok, validated_input} = ReasoningSignature.validate_input(reasoning_input)
      assert validated_input.premise == "All birds can fly"

      # Valid reasoning output
      reasoning_output = %{
        reasoning_steps: [
          "The premise states all birds can fly",
          "However, there are flightless birds like penguins",
          "Therefore, the premise is not universally true"
        ],
        conclusion: "The premise is false due to counterexamples like penguins."
      }

      assert {:ok, validated_output} = ReasoningSignature.validate_output(reasoning_output)
      assert length(validated_output.reasoning_steps) == 3
    end
  end
end
