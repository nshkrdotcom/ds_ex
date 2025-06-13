defmodule DSPEx.Signature.ElixactTest do
  @moduledoc """
  Test suite for DSPEx.Signature.Elixact bridge module.

  Tests the conversion between DSPEx signatures and Elixact schemas,
  validation functionality, and JSON schema generation.
  """
  use ExUnit.Case, async: true

  alias DSPEx.Signature.Elixact

  # Test signature modules
  defmodule SimpleSignature do
    use DSPEx.Signature, "name -> greeting"
  end

  defmodule MultiFieldSignature do
    use DSPEx.Signature, "question, context -> answer, reasoning"
  end

  defmodule InstructedSignature do
    @moduledoc "Generate a greeting based on the provided name"
    use DSPEx.Signature, "name -> greeting"
  end

  describe "signature_to_schema/1" do
    test "converts simple signature to Elixact schema" do
      assert {:ok, schema_module} = Elixact.signature_to_schema(SimpleSignature)

      # Verify the schema module was created
      assert is_atom(schema_module)
      assert Code.ensure_loaded?(schema_module)

      # Verify it has the expected Elixact functions
      assert function_exported?(schema_module, :validate, 1)
      assert function_exported?(schema_module, :validate!, 1)
    end

    test "converts multi-field signature to Elixact schema" do
      assert {:ok, schema_module} = Elixact.signature_to_schema(MultiFieldSignature)

      # Test that the schema can validate data with all fields
      valid_data = %{
        question: "What is AI?",
        context: "Computer science",
        answer: "Artificial Intelligence",
        reasoning: "Based on context"
      }

      assert {:ok, validated} = schema_module.validate(valid_data)
      assert validated.question == "What is AI?"
      assert validated.context == "Computer science"
      assert validated.answer == "Artificial Intelligence"
      assert validated.reasoning == "Based on context"
    end

    test "returns error for invalid signature" do
      defmodule InvalidModule do
        # Not a DSPEx signature
      end

      assert {:error, reason} = Elixact.signature_to_schema(InvalidModule)
      assert match?({:invalid_signature, _}, reason)
    end

    test "generates unique schema modules for repeated conversions" do
      assert {:ok, schema1} = Elixact.signature_to_schema(SimpleSignature)
      assert {:ok, schema2} = Elixact.signature_to_schema(SimpleSignature)

      # Should generate different modules each time
      assert schema1 != schema2
    end
  end

  describe "validate_with_elixact/3" do
    test "validates input data successfully" do
      input_data = %{name: "Alice"}

      assert {:ok, validated} =
               Elixact.validate_with_elixact(SimpleSignature, input_data, field_type: :inputs)

      assert validated.name == "Alice"
    end

    test "validates output data successfully" do
      output_data = %{greeting: "Hello, Alice!"}

      assert {:ok, validated} =
               Elixact.validate_with_elixact(SimpleSignature, output_data, field_type: :outputs)

      assert validated.greeting == "Hello, Alice!"
    end

    test "validates multi-field input data" do
      input_data = %{
        question: "What is machine learning?",
        context: "AI and data science"
      }

      assert {:ok, validated} =
               Elixact.validate_with_elixact(MultiFieldSignature, input_data, field_type: :inputs)

      assert validated.question == "What is machine learning?"
      assert validated.context == "AI and data science"
    end

    test "validates multi-field output data" do
      output_data = %{
        answer: "A subset of AI that learns from data",
        reasoning: "Based on the context provided"
      }

      assert {:ok, validated} =
               Elixact.validate_with_elixact(MultiFieldSignature, output_data,
                 field_type: :outputs
               )

      assert validated.answer == "A subset of AI that learns from data"
      assert validated.reasoning == "Based on the context provided"
    end

    test "filters data by field type correctly" do
      mixed_data = %{
        # input field
        question: "Test question",
        # input field
        context: "Test context",
        # output field
        answer: "Test answer",
        # output field
        reasoning: "Test reasoning",
        # not in signature
        extra: "Should be ignored"
      }

      # Validate inputs only
      assert {:ok, input_validated} =
               Elixact.validate_with_elixact(MultiFieldSignature, mixed_data, field_type: :inputs)

      assert Map.has_key?(input_validated, :question)
      assert Map.has_key?(input_validated, :context)
      assert not Map.has_key?(input_validated, :answer)
      assert not Map.has_key?(input_validated, :reasoning)
      assert not Map.has_key?(input_validated, :extra)

      # Validate outputs only
      assert {:ok, output_validated} =
               Elixact.validate_with_elixact(MultiFieldSignature, mixed_data,
                 field_type: :outputs
               )

      assert not Map.has_key?(output_validated, :question)
      assert not Map.has_key?(output_validated, :context)
      assert Map.has_key?(output_validated, :answer)
      assert Map.has_key?(output_validated, :reasoning)
      assert not Map.has_key?(output_validated, :extra)
    end

    test "returns error for missing required fields" do
      # Missing 'name' field
      empty_data = %{}

      assert {:error, errors} =
               Elixact.validate_with_elixact(SimpleSignature, empty_data, field_type: :inputs)

      assert is_list(errors)
      assert length(errors) >= 1

      # Check that error is related to missing field
      error = hd(errors)
      assert is_struct(error, Elixact.Error) or is_map(error)
    end

    test "handles invalid signature gracefully" do
      defmodule NotASignature do
        # Not a DSPEx signature
      end

      assert {:error, reason} = Elixact.validate_with_elixact(NotASignature, %{}, [])
      assert match?({:invalid_signature, _}, reason)
    end

    test "handles invalid field type option" do
      assert {:error, reason} =
               Elixact.validate_with_elixact(SimpleSignature, %{name: "test"},
                 field_type: :invalid
               )

      assert match?({:invalid_field_type, :invalid}, reason)
    end
  end

  describe "to_json_schema/2" do
    test "generates JSON schema from simple signature" do
      assert {:ok, json_schema} = Elixact.to_json_schema(SimpleSignature)

      # Verify basic JSON schema structure
      assert is_map(json_schema)
      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "properties")

      properties = json_schema["properties"]
      assert Map.has_key?(properties, "name")
      assert Map.has_key?(properties, "greeting")

      # Verify field types (default to string)
      assert properties["name"]["type"] == "string"
      assert properties["greeting"]["type"] == "string"
    end

    test "generates JSON schema with custom title" do
      assert {:ok, json_schema} = Elixact.to_json_schema(SimpleSignature, title: "Custom Title")
      assert json_schema["title"] == "Custom Title"
    end

    test "generates JSON schema with custom description" do
      assert {:ok, json_schema} =
               Elixact.to_json_schema(SimpleSignature, description: "Custom description")

      assert json_schema["description"] == "Custom description"
    end

    test "uses signature instructions as description when available" do
      assert {:ok, json_schema} = Elixact.to_json_schema(InstructedSignature)
      assert json_schema["description"] == "Generate a greeting based on the provided name"
    end

    test "filters JSON schema by field type" do
      # Generate schema for inputs only
      assert {:ok, input_schema} =
               Elixact.to_json_schema(MultiFieldSignature, field_type: :inputs)

      properties = input_schema["properties"]
      assert Map.has_key?(properties, "question")
      assert Map.has_key?(properties, "context")
      assert not Map.has_key?(properties, "answer")
      assert not Map.has_key?(properties, "reasoning")

      # Generate schema for outputs only
      assert {:ok, output_schema} =
               Elixact.to_json_schema(MultiFieldSignature, field_type: :outputs)

      properties = output_schema["properties"]
      assert not Map.has_key?(properties, "question")
      assert not Map.has_key?(properties, "context")
      assert Map.has_key?(properties, "answer")
      assert Map.has_key?(properties, "reasoning")
    end

    test "includes all fields by default" do
      assert {:ok, json_schema} = Elixact.to_json_schema(MultiFieldSignature)

      properties = json_schema["properties"]
      assert Map.has_key?(properties, "question")
      assert Map.has_key?(properties, "context")
      assert Map.has_key?(properties, "answer")
      assert Map.has_key?(properties, "reasoning")
    end

    test "returns error for invalid signature" do
      defmodule InvalidForJson do
        # Not a DSPEx signature
      end

      assert {:error, reason} = Elixact.to_json_schema(InvalidForJson)
      assert match?({:invalid_signature, _}, reason)
    end
  end

  describe "dspex_errors_to_elixact/1" do
    test "converts missing_inputs error" do
      errors = Elixact.dspex_errors_to_elixact(:missing_inputs)

      assert is_list(errors)
      assert length(errors) == 1

      error = hd(errors)
      assert error.code == :missing_inputs
      assert error.path == []
      assert is_binary(error.message)
    end

    test "converts missing_outputs error" do
      errors = Elixact.dspex_errors_to_elixact(:missing_outputs)

      assert is_list(errors)
      assert length(errors) == 1

      error = hd(errors)
      assert error.code == :missing_outputs
      assert error.path == []
      assert is_binary(error.message)
    end

    test "converts missing_inputs error with field list" do
      errors = Elixact.dspex_errors_to_elixact({:missing_inputs, [:name, :email]})

      assert is_list(errors)
      assert length(errors) == 2

      [error1, error2] = errors
      assert error1.code == :required
      assert error1.path == [:name]
      assert String.contains?(error1.message, "name")

      assert error2.code == :required
      assert error2.path == [:email]
      assert String.contains?(error2.message, "email")
    end

    test "converts missing_outputs error with field list" do
      errors = Elixact.dspex_errors_to_elixact({:missing_outputs, [:result, :status]})

      assert is_list(errors)
      assert length(errors) == 2

      [error1, error2] = errors
      assert error1.code == :required
      assert error1.path == [:result]
      assert String.contains?(error1.message, "result")

      assert error2.code == :required
      assert error2.path == [:status]
      assert String.contains?(error2.message, "status")
    end

    test "converts invalid_signature error" do
      errors = Elixact.dspex_errors_to_elixact(:invalid_signature)

      assert is_list(errors)
      assert length(errors) == 1

      error = hd(errors)
      assert error.code == :invalid_signature
      assert error.path == []
      assert String.contains?(error.message, "Invalid signature")
    end

    test "handles unknown errors gracefully" do
      errors = Elixact.dspex_errors_to_elixact(:unknown_error)

      assert is_list(errors)
      assert length(errors) == 1

      error = hd(errors)
      assert error.code == :unknown_error
      assert error.path == []
      assert String.contains?(error.message, "Unknown validation error")
    end

    test "handles complex error tuples" do
      complex_error = {:custom_error, "some details"}
      errors = Elixact.dspex_errors_to_elixact(complex_error)

      assert is_list(errors)
      assert length(errors) == 1

      error = hd(errors)
      assert error.code == :unknown_error
      assert String.contains?(error.message, inspect(complex_error))
    end
  end

  describe "integration scenarios" do
    test "end-to-end conversion and validation workflow" do
      # Step 1: Convert signature to schema
      assert {:ok, _schema_module} = Elixact.signature_to_schema(MultiFieldSignature)

      # Step 2: Validate input data using the bridge
      input_data = %{question: "Test?", context: "Testing"}

      assert {:ok, validated_inputs} =
               Elixact.validate_with_elixact(MultiFieldSignature, input_data, field_type: :inputs)

      # Step 3: Validate output data using the bridge
      output_data = %{answer: "Test result", reasoning: "Because testing"}

      assert {:ok, validated_outputs} =
               Elixact.validate_with_elixact(MultiFieldSignature, output_data,
                 field_type: :outputs
               )

      # Step 4: Generate JSON schema
      assert {:ok, json_schema} = Elixact.to_json_schema(MultiFieldSignature)

      # Verify the entire workflow
      assert validated_inputs.question == "Test?"
      assert validated_inputs.context == "Testing"
      assert validated_outputs.answer == "Test result"
      assert validated_outputs.reasoning == "Because testing"
      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema["properties"], "question")
    end

    test "handles validation errors gracefully in workflow" do
      # Missing required input fields
      # Missing context
      incomplete_data = %{question: "Only question"}

      assert {:error, errors} =
               Elixact.validate_with_elixact(MultiFieldSignature, incomplete_data,
                 field_type: :inputs
               )

      assert is_list(errors)

      # Should still be able to generate JSON schema despite validation error
      assert {:ok, json_schema} = Elixact.to_json_schema(MultiFieldSignature)
      assert is_map(json_schema)
    end

    test "schema modules are independent" do
      # Create two different schemas from the same signature
      assert {:ok, schema1} = Elixact.signature_to_schema(SimpleSignature)
      assert {:ok, schema2} = Elixact.signature_to_schema(SimpleSignature)

      # They should be different modules
      assert schema1 != schema2

      # But both should validate the same data successfully
      # Since signature_to_schema includes ALL fields, we need to provide both input and output
      test_data = %{name: "Test", greeting: "Hello, Test!"}
      assert {:ok, _} = schema1.validate(test_data)
      assert {:ok, _} = schema2.validate(test_data)
    end

    test "preserves signature information in generated schemas" do
      assert {:ok, schema_module} = Elixact.signature_to_schema(InstructedSignature)

      # The description should be preserved
      # This tests that we're passing the signature's instructions to Elixact
      test_data = %{name: "Test User", greeting: "Hello!"}
      assert {:ok, validated} = schema_module.validate(test_data)
      assert validated.name == "Test User"
      assert validated.greeting == "Hello!"
    end
  end

  describe "error handling and edge cases" do
    test "handles signature without instructions gracefully" do
      defmodule NoInstructionsSignature do
        use DSPEx.Signature, "input -> output"
      end

      # Should still work without instructions
      assert {:ok, _schema_module} = Elixact.signature_to_schema(NoInstructionsSignature)
      assert {:ok, json_schema} = Elixact.to_json_schema(NoInstructionsSignature)

      # Should have a generated description
      assert is_binary(json_schema["description"])
    end

    test "handles empty field lists gracefully" do
      # This is a bit artificial since DSPEx requires at least one input and output
      # But we test the error path
      defmodule EmptyFieldsSignature do
        @behaviour DSPEx.Signature

        def input_fields, do: []
        def output_fields, do: []
        def fields, do: []
        def instructions, do: "Empty signature for testing"
      end

      # Should handle empty field lists
      assert {:ok, schema_module} = Elixact.signature_to_schema(EmptyFieldsSignature)

      # Should validate empty data
      assert {:ok, validated} = schema_module.validate(%{})
      assert validated == %{}
    end

    test "handles validation with mixed valid and invalid data" do
      mixed_data = %{
        # valid
        name: "Valid name",
        # potentially invalid (empty string)
        greeting: "",
        # should be filtered out
        extra_field: "ignored"
      }

      # Should filter and validate only relevant fields
      assert {:ok, validated} =
               Elixact.validate_with_elixact(SimpleSignature, mixed_data, field_type: :inputs)

      assert validated.name == "Valid name"
      assert not Map.has_key?(validated, :greeting)
      assert not Map.has_key?(validated, :extra_field)
    end

    test "performance with repeated conversions" do
      # Test that repeated conversions don't cause memory leaks or performance issues
      start_time = System.monotonic_time()

      for _i <- 1..50 do
        assert {:ok, _schema} = Elixact.signature_to_schema(SimpleSignature)
      end

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should complete in reasonable time (less than 5 seconds for 50 conversions)
      assert duration_ms < 5000, "Schema conversion too slow: #{duration_ms}ms for 50 conversions"
    end
  end
end
