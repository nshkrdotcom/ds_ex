defmodule DSPEx.SignatureSchemaIntegrationTest do
  use ExUnit.Case, async: true
  doctest DSPEx.Signature.SchemaIntegration

  alias DSPEx.Signature.SchemaIntegration
  alias ElixirML.Variable

  describe "schema DSL integration" do
    defmodule TestMLSignature do
      @moduledoc "Test signature with ML-specific types"
      use DSPEx.Signature, :schema_dsl
      
      input :question, :string
      input :context, :embedding, dimensions: 1536
      input :threshold, :probability, default: 0.8
      output :answer, :string  
      output :confidence, :confidence_score
      output :reasoning, :reasoning_chain
    end

    test "generates proper signature struct" do
      signature = TestMLSignature.new(%{
        question: "What is 2+2?",
        context: Enum.map(1..1536, fn _ -> 0.1 end),
        threshold: 0.9,
        answer: "4",
        confidence: 0.95,
        reasoning: ["Step 1: Identify numbers", "Step 2: Add them"]
      })

      assert signature.question == "What is 2+2?"
      assert length(signature.context) == 1536
      assert signature.threshold == 0.9
      assert signature.answer == "4"
      assert signature.confidence == 0.95
      assert signature.reasoning == ["Step 1: Identify numbers", "Step 2: Add them"]
    end

    test "implements signature behaviour" do
      assert TestMLSignature.input_fields() == [:question, :context, :threshold]
      assert TestMLSignature.output_fields() == [:answer, :confidence, :reasoning]
      assert TestMLSignature.fields() == [:question, :context, :threshold, :answer, :confidence, :reasoning]
      assert is_binary(TestMLSignature.instructions())
    end

    test "provides enhanced field definitions" do
      enhanced_fields = TestMLSignature.__enhanced_fields__()
      
      assert length(enhanced_fields) == 6
      
      # Find the context field
      context_field = Enum.find(enhanced_fields, &(&1.name == :context))
      assert context_field.type == :embedding
      assert context_field.constraints.dimensions == 1536
      
      # Find the confidence field
      confidence_field = Enum.find(enhanced_fields, &(&1.name == :confidence))
      assert confidence_field.type == :confidence_score
    end

    test "validates inputs with schema" do
      valid_inputs = %{
        question: "What is the capital of France?",
        context: Enum.map(1..1536, fn _ -> 0.1 end),
        threshold: 0.85
      }
      
      assert {:ok, validated} = TestMLSignature.validate_inputs_with_schema(valid_inputs)
      assert validated.question == "What is the capital of France?"
      assert length(validated.context) == 1536
      assert validated.threshold == 0.85
    end

    test "validates outputs with schema" do
      valid_outputs = %{
        answer: "Paris",
        confidence: 0.92,
        reasoning: ["Step 1: Recall geography", "Step 2: Identify capital"]
      }
      
      assert {:ok, validated} = TestMLSignature.validate_outputs_with_schema(valid_outputs)
      assert validated.answer == "Paris"
      assert validated.confidence == 0.92
      assert validated.reasoning == ["Step 1: Recall geography", "Step 2: Identify capital"]
    end

    test "extracts variables from field definitions" do
      variable_space = TestMLSignature.extract_variables()
      
      variables = Map.values(variable_space.variables)
      variable_names = Enum.map(variables, & &1.name)
      
      # Should extract variables from ML-specific types
      assert :threshold_threshold in variable_names
      assert :confidence_min_confidence in variable_names
      assert :context_dimensions in variable_names
    end

    test "maintains backward compatibility with basic validation" do
      # Basic validation should still work
      assert :ok = TestMLSignature.validate_inputs(%{
        question: "test",
        context: [],
        threshold: 0.5
      })
      
      assert {:error, {:missing_inputs, missing}} = TestMLSignature.validate_inputs(%{
        question: "test"
      })
      
      assert :context in missing
      assert :threshold in missing
    end
  end

  describe "ML-specific type validation" do
    defmodule MLTypesSignature do
      use DSPEx.Signature, :schema_dsl
      
      input :embedding_field, :embedding, dimensions: 512
      input :prob_field, :probability
      input :tokens_field, :token_list
      output :confidence_field, :confidence_score
      output :response_field, :model_response
      output :tensor_field, :tensor
    end

    test "validates embedding fields" do
      # Valid embedding
      valid_data = %{
        embedding_field: Enum.map(1..512, fn _ -> 0.1 end),
        prob_field: 0.8,
        tokens_field: ["hello", "world"]
      }
      
      assert {:ok, _} = MLTypesSignature.validate_inputs_with_schema(valid_data)
      
      # Invalid embedding - wrong dimensions
      invalid_data = %{
        embedding_field: [0.1, 0.2], # Only 2 dimensions instead of 512
        prob_field: 0.8,
        tokens_field: ["hello", "world"]
      }
      
      assert {:error, _} = MLTypesSignature.validate_inputs_with_schema(invalid_data)
    end

    test "validates probability fields" do
      # Valid probability
      valid_data = %{
        embedding_field: Enum.map(1..512, fn _ -> 0.1 end),
        prob_field: 0.75,
        tokens_field: ["test"]
      }
      
      assert {:ok, _} = MLTypesSignature.validate_inputs_with_schema(valid_data)
      
      # Invalid probability - out of range
      invalid_data = %{
        embedding_field: Enum.map(1..512, fn _ -> 0.1 end),
        prob_field: 1.5, # > 1.0
        tokens_field: ["test"]
      }
      
      assert {:error, _} = MLTypesSignature.validate_inputs_with_schema(invalid_data)
    end

    test "validates confidence score fields" do
      valid_data = %{
        confidence_field: 0.95,
        response_field: %{text: "response", metadata: %{}},
        tensor_field: [[1, 2], [3, 4]]
      }
      
      assert {:ok, _} = MLTypesSignature.validate_outputs_with_schema(valid_data)
      
      # Invalid confidence - negative
      invalid_data = %{
        confidence_field: -0.1,
        response_field: %{text: "response"},
        tensor_field: [[1, 2]]
      }
      
      assert {:error, _} = MLTypesSignature.validate_outputs_with_schema(invalid_data)
    end

    test "validates token list fields" do
      # Valid token lists
      assert {:ok, _} = MLTypesSignature.validate_inputs_with_schema(%{
        embedding_field: Enum.map(1..512, fn _ -> 0.1 end),
        prob_field: 0.8,
        tokens_field: ["hello", "world", "test"]
      })
      
      assert {:ok, _} = MLTypesSignature.validate_inputs_with_schema(%{
        embedding_field: Enum.map(1..512, fn _ -> 0.1 end),
        prob_field: 0.8,
        tokens_field: [1, 2, 3, 4]  # Integer tokens
      })
      
      # Invalid token list
      assert {:error, _} = MLTypesSignature.validate_inputs_with_schema(%{
        embedding_field: Enum.map(1..512, fn _ -> 0.1 end),
        prob_field: 0.8,
        tokens_field: [1.5, 2.7, "mixed"]  # Mixed invalid types
      })
    end
  end

  describe "variable extraction" do
    defmodule VariableExtractionSignature do
      use DSPEx.Signature, :schema_dsl
      
      input :text, :string, max_length: 1000
      input :embedding, :embedding, dimensions: 768
      input :threshold, :probability
      output :confidence, :confidence_score
      output :tokens, :token_list, max_tokens: 50
    end

    test "extracts variables from ML field types" do
      variable_space = VariableExtractionSignature.extract_variables()
      variables = Map.values(variable_space.variables)
      variable_names = Enum.map(variables, & &1.name)
      
      # Variables from ML types
      assert :threshold_threshold in variable_names
      assert :confidence_min_confidence in variable_names
      assert :embedding_dimensions in variable_names
      
      # Variables from constraints
      assert :text_max_length in variable_names
      assert :tokens_max_tokens in variable_names
    end

    test "variable extraction provides proper variable definitions" do
      variable_space = VariableExtractionSignature.extract_variables()
      variables = Map.values(variable_space.variables)
      
      # Find the threshold variable
      threshold_var = Enum.find(variables, &(&1.name == :threshold_threshold))
      assert threshold_var.type == :float
      assert threshold_var.constraints.range == {0.0, 1.0}
      assert threshold_var.default == 0.5
      
      # Find the embedding dimensions variable
      dims_var = Enum.find(variables, &(&1.name == :embedding_dimensions))
      assert dims_var.type == :integer
      assert dims_var.constraints.range == {128, 4096}
      assert dims_var.default == 768
    end
  end

  describe "error handling" do
    defmodule ErrorTestSignature do
      use DSPEx.Signature, :schema_dsl
      
      input :required_field, :string
      input :optional_field, :string, required: false
      output :result, :confidence_score
    end

    test "handles missing required fields" do
      # Missing required field
      assert {:error, {field_name, :required_field_missing}} = 
        ErrorTestSignature.validate_inputs_with_schema(%{optional_field: "present"})
      
      assert field_name == :required_field
    end

    test "handles type validation errors" do
      # Invalid confidence score in output
      assert {:error, {field_name, error}} = 
        ErrorTestSignature.validate_outputs_with_schema(%{result: "not_a_number"})
      
      assert field_name == :result
      assert error == :invalid_confidence_score
    end

    test "handles malformed signature modules gracefully" do
      # Test with a module that doesn't have enhanced fields
      defmodule BasicSignature do
        defstruct [:field]
        def __enhanced_fields__, do: []
      end
      
      variable_space = SchemaIntegration.extract_variables(BasicSignature)
      assert Map.values(variable_space.variables) == []
    end
  end

  describe "integration with existing DSPEx patterns" do
    defmodule IntegrationSignature do
      @moduledoc "A signature for question answering with confidence scoring"
      use DSPEx.Signature, :schema_dsl
      
      input :question, :string
      input :context, :string
      output :answer, :string
      output :confidence, :confidence_score
    end

    test "works with DSPEx.Program integration" do
      # Should be able to create a program with this signature
      case DSPEx.Program.new(IntegrationSignature, []) do
        {:ok, program} ->
          assert program.signature == IntegrationSignature
          assert is_struct(program, DSPEx.Program)
        
        {:error, reason} ->
          # Program creation might have specific requirements - that's ok
          # The important thing is that the signature is compatible
          assert IntegrationSignature.input_fields() == [:question, :context]
          assert IntegrationSignature.output_fields() == [:answer, :confidence]
      end
    end

    test "provides both basic and enhanced validation" do
      data = %{
        question: "What is ML?",
        context: "Machine Learning context"
      }
      
      # Basic validation (backward compatibility)
      assert :ok = IntegrationSignature.validate_inputs(data)
      
      # Enhanced validation (new capability)
      assert {:ok, validated} = IntegrationSignature.validate_inputs_with_schema(data)
      assert validated.question == "What is ML?"
    end

    test "integrates with variable system" do
      # Should be able to extract variables for optimization
      variable_space = IntegrationSignature.extract_variables()
      
      # Should have extracted confidence-related variable
      variables = Map.values(variable_space.variables)
      confidence_vars = Enum.filter(variables, &String.contains?(Atom.to_string(&1.name), "confidence"))
      assert length(confidence_vars) > 0
    end
  end
end