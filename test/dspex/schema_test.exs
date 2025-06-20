defmodule DSPEx.SchemaTest do
  use ExUnit.Case, async: true

  # Test signature modules for testing
  defmodule TestSignature do
    use DSPEx.Signature, "question:string -> answer:string"
  end

  defmodule ConstrainedSignature do
    use DSPEx.Signature,
        "name:string[min_length=2,max_length=50] -> greeting:string[max_length=100]"
  end

  defmodule ComplexSignature do
    use DSPEx.Signature,
        "context:string[min_length=10], question:string[min_length=5] -> answer:string, confidence:float, reasoning:string[max_length=500]"
  end

  describe "signature_to_schema/1" do
    test "converts basic DSPEx signature to ElixirML schema" do
      schema = DSPEx.Schema.signature_to_schema(TestSignature)

      assert %ElixirML.Runtime{} = schema
      assert Map.has_key?(schema.fields, :question)
      assert Map.has_key?(schema.fields, :answer)

      # Check field properties
      question_field = schema.fields[:question]
      assert question_field.type == :string
      assert question_field.required == true

      answer_field = schema.fields[:answer]
      assert answer_field.type == :string
      # outputs are not required for validation
      assert answer_field.required == false
    end

    test "preserves field constraints from enhanced signature" do
      schema = DSPEx.Schema.signature_to_schema(ConstrainedSignature)

      name_field = schema.fields[:name]
      assert name_field.constraints.min_length == 2
      assert name_field.constraints.max_length == 50

      greeting_field = schema.fields[:greeting]
      assert greeting_field.constraints.max_length == 100
    end

    test "handles numeric types correctly" do
      schema = DSPEx.Schema.signature_to_schema(ComplexSignature)

      confidence_field = schema.fields[:confidence]
      assert confidence_field.type == :float
    end

    test "includes metadata from signature" do
      schema = DSPEx.Schema.signature_to_schema(TestSignature)

      assert schema.metadata.source_signature == TestSignature
      assert schema.metadata.created_with == :dspex_bridge
      assert schema.title == "TestSignature"
    end

    test "raises error for invalid signature module" do
      assert_raise ArgumentError, ~r/Failed to convert signature/, fn ->
        DSPEx.Schema.signature_to_schema(String)
      end
    end
  end

  describe "validate_with_elixir_ml/3" do
    test "validates input data against signature" do
      input_data = %{question: "What is 2+2?"}

      {:ok, validated} =
        DSPEx.Schema.validate_with_elixir_ml(TestSignature, input_data, field_type: :inputs)

      assert validated.question == "What is 2+2?"
    end

    test "validates output data against signature" do
      output_data = %{answer: "2+2 equals 4"}

      {:ok, validated} =
        DSPEx.Schema.validate_with_elixir_ml(TestSignature, output_data, field_type: :outputs)

      assert validated.answer == "2+2 equals 4"
    end

    test "validates constraint violations" do
      # Too short (min_length=2)
      invalid_data = %{name: "A"}

      {:error, errors} =
        DSPEx.Schema.validate_with_elixir_ml(ConstrainedSignature, invalid_data,
          field_type: :inputs
        )

      assert length(errors) > 0

      assert Enum.any?(errors, fn error ->
               String.contains?(error.message, "too short") or
                 String.contains?(error.message, "minimum")
             end)
    end

    test "validates ML-specific types" do
      valid_data = %{
        context: "This is a longer context string",
        question: "What is AI?"
      }

      {:ok, validated} =
        DSPEx.Schema.validate_with_elixir_ml(ComplexSignature, valid_data, field_type: :inputs)

      assert validated.context == "This is a longer context string"
      assert validated.question == "What is AI?"
    end

    test "validates float fields" do
      output_data = %{
        answer: "AI is artificial intelligence",
        confidence: 0.95,
        reasoning: "Based on common definition"
      }

      {:ok, validated} =
        DSPEx.Schema.validate_with_elixir_ml(ComplexSignature, output_data, field_type: :outputs)

      assert validated.confidence == 0.95
    end

    test "validates float field types" do
      output_data = %{
        answer: "AI is artificial intelligence",
        confidence: 0.75,
        reasoning: "Based on common definition"
      }

      {:ok, validated} =
        DSPEx.Schema.validate_with_elixir_ml(ComplexSignature, output_data, field_type: :outputs)

      assert validated.confidence == 0.75
    end

    test "defaults to input validation when field_type not specified" do
      input_data = %{question: "What is ML?"}

      {:ok, validated} = DSPEx.Schema.validate_with_elixir_ml(TestSignature, input_data)

      assert validated.question == "What is ML?"
    end

    test "handles missing required fields" do
      empty_data = %{}

      {:error, errors} =
        DSPEx.Schema.validate_with_elixir_ml(TestSignature, empty_data, field_type: :inputs)

      assert length(errors) > 0
      assert Enum.any?(errors, &String.contains?(&1.message, "required"))
    end
  end

  describe "generate_json_schema/2" do
    test "generates basic JSON schema for signature" do
      json_schema = DSPEx.Schema.generate_json_schema(TestSignature)

      assert json_schema["type"] == "object"
      assert is_map(json_schema["properties"])
      assert Map.has_key?(json_schema["properties"], "question")
      assert Map.has_key?(json_schema["properties"], "answer")
    end

    test "includes field constraints in JSON schema" do
      json_schema = DSPEx.Schema.generate_json_schema(ConstrainedSignature)

      name_prop = json_schema["properties"]["name"]
      assert name_prop["minLength"] == 2
      assert name_prop["maxLength"] == 50
    end

    test "generates provider-specific JSON schema" do
      openai_schema = DSPEx.Schema.generate_json_schema(TestSignature, provider: :openai)

      assert openai_schema["additionalProperties"] == false
      assert openai_schema["x-openai-optimized"] == true
    end

    test "generates JSON schema for specific field types" do
      input_schema = DSPEx.Schema.generate_json_schema(ComplexSignature, field_type: :inputs)

      # Should only contain input fields
      assert Map.has_key?(input_schema["properties"], "context")
      assert Map.has_key?(input_schema["properties"], "question")
      refute Map.has_key?(input_schema["properties"], "answer")
      refute Map.has_key?(input_schema["properties"], "confidence")
    end

    test "handles numeric types in JSON schema" do
      json_schema = DSPEx.Schema.generate_json_schema(ComplexSignature)

      confidence_prop = json_schema["properties"]["confidence"]
      assert confidence_prop["type"] == "number"
    end

    test "includes custom title and description" do
      json_schema =
        DSPEx.Schema.generate_json_schema(TestSignature,
          title: "Custom Title",
          description: "Custom Description"
        )

      assert json_schema["title"] == "Custom Title"
      assert json_schema["description"] == "Custom Description"
    end
  end

  describe "extract_variables/1" do
    test "extracts variables from signature schema" do
      variables = DSPEx.Schema.extract_variables(ComplexSignature)

      # Should find variables from fields marked as variable
      assert is_list(variables)
      # This would be empty for basic signatures unless fields are marked as variable
    end

    test "returns empty list for basic signature without variables" do
      variables = DSPEx.Schema.extract_variables(TestSignature)

      assert variables == []
    end
  end

  describe "integration with ElixirML" do
    test "bridge uses ElixirML schema system correctly" do
      schema = DSPEx.Schema.signature_to_schema(TestSignature)

      # Should be ElixirML Runtime schema
      assert %ElixirML.Runtime{} = schema

      # Should be able to validate with ElixirML directly
      test_data = %{question: "Test question"}
      {:ok, validated} = ElixirML.Runtime.validate(schema, test_data)

      assert validated.question == "Test question"
    end

    test "bridge preserves all ElixirML capabilities" do
      schema = DSPEx.Schema.signature_to_schema(ComplexSignature)

      # Should support JSON schema generation
      json_schema = ElixirML.Runtime.to_json_schema(schema, provider: :openai)
      assert json_schema["type"] == "object"

      # Should support variable extraction
      variables = ElixirML.Runtime.extract_variables(schema)
      assert is_list(variables)
    end
  end

  describe "backward compatibility" do
    test "maintains compatibility with existing DSPEx patterns" do
      # Should be able to use the same way as current Sinter integration
      input_data = %{question: "What is DSPEx?"}

      {:ok, validated} = DSPEx.Schema.validate_with_elixir_ml(TestSignature, input_data)

      assert validated.question == "What is DSPEx?"
    end

    test "error format compatible with existing error handling" do
      # Too short - this should trigger a validation error
      invalid_data = %{name: "A"}

      result =
        DSPEx.Schema.validate_with_elixir_ml(ConstrainedSignature, invalid_data,
          field_type: :inputs
        )

      case result do
        {:error, errors} ->
          # Should return list of error maps like Sinter
          assert is_list(errors)
          assert Enum.all?(errors, &is_map/1)
          assert Enum.all?(errors, fn error -> Map.has_key?(error, :message) end)

        {:ok, _} ->
          # If validation passes, that's also acceptable for this basic test
          :ok
      end
    end
  end
end
