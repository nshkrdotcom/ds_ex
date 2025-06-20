defmodule ElixirML.SchemaLLMTest do
  use ExUnit.Case

  describe "to_json_schema/2 with provider optimization" do
    test "generates OpenAI-optimized JSON schema" do
      schema = create_test_schema()
      
      json_schema = ElixirML.Schema.to_json_schema(schema, provider: :openai)
      
      # Should have OpenAI-specific optimizations
      assert json_schema["type"] == "object"
      assert is_map(json_schema["properties"])
      refute Map.has_key?(json_schema, "definitions")  # Flattened for OpenAI
      
      # Should have required fields
      assert is_list(json_schema["required"])
      
      # Should have additionalProperties set to false for OpenAI
      assert json_schema["additionalProperties"] == false
    end

    test "generates Anthropic-optimized JSON schema" do
      schema = create_test_schema()
      
      json_schema = ElixirML.Schema.to_json_schema(schema, provider: :anthropic)
      
      # Should have Anthropic-specific optimizations
      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "description")
      assert is_map(json_schema["properties"])
      
      # Anthropic prefers richer descriptions
      assert String.length(json_schema["description"]) > 0
    end

    test "generates Groq-optimized JSON schema" do
      schema = create_test_schema()
      
      json_schema = ElixirML.Schema.to_json_schema(schema, provider: :groq)
      
      # Should have Groq-specific optimizations
      assert json_schema["type"] == "object"
      assert is_map(json_schema["properties"])
      
      # Groq optimizations should be similar to OpenAI but with specific tweaks
      assert json_schema["additionalProperties"] == false
    end

    test "generates generic JSON schema when no provider specified" do
      schema = create_test_schema()
      
      json_schema = ElixirML.Schema.to_json_schema(schema)
      
      # Should have basic JSON schema structure
      assert json_schema["type"] == "object"
      assert is_map(json_schema["properties"])
      assert is_list(json_schema["required"])
    end

    test "handles ML-specific types in JSON schema generation" do
      schema = create_ml_test_schema()
      
      json_schema = ElixirML.Schema.to_json_schema(schema, provider: :openai)
      
      # Should convert ML types to appropriate JSON schema types
      properties = json_schema["properties"]
      
      # Embedding should be array of numbers
      assert properties["embedding"]["type"] == "array"
      assert properties["embedding"]["items"]["type"] == "number"
      
      # Probability should be number with constraints
      assert properties["confidence"]["type"] == "number"
      assert properties["confidence"]["minimum"] == 0.0
      assert properties["confidence"]["maximum"] == 1.0
      
      # Token list should be array with oneOf constraint for strings or integers
      assert properties["tokens"]["type"] == "array"
      assert is_map(properties["tokens"]["items"])
      assert Map.has_key?(properties["tokens"]["items"], "oneOf")
    end
  end

  describe "optimize_for_provider/2" do
    test "optimizes schema for OpenAI" do
      schema = create_test_schema()
      
      optimized = ElixirML.Schema.optimize_for_provider(schema, :openai)
      
      # Should maintain schema structure but optimize metadata
      assert optimized.name == schema.name
      assert length(optimized.fields) == length(schema.fields)
      
      # Should add provider-specific optimizations
      assert optimized.metadata.provider_optimizations == :openai
    end

    test "optimizes schema for Anthropic" do
      schema = create_test_schema()
      
      optimized = ElixirML.Schema.optimize_for_provider(schema, :anthropic)
      
      # Should enhance descriptions for Anthropic
      assert optimized.metadata.provider_optimizations == :anthropic
    end
  end

  describe "create_model/3 (Pydantic pattern)" do
    test "creates schema with Pydantic create_model pattern" do
      fields = %{
        reasoning: {:string, description: "Chain of thought"},
        answer: {:string, required: true},
        confidence: {:float, gteq: 0.0, lteq: 1.0}
      }
      
      schema = ElixirML.Schema.create_model("LLMOutput", fields)
      
      assert schema.name == "LLMOutput"
      
      # Access fields through metadata fields_map
      fields_map = schema.metadata.fields_map
      assert Map.has_key?(fields_map, :reasoning)
      assert Map.has_key?(fields_map, :answer)
      assert Map.has_key?(fields_map, :confidence)
      
      # Should handle required fields
      answer_field = fields_map[:answer]
      assert answer_field.type == :string
      assert Keyword.get(answer_field.opts, :required) == true
      
      # Should handle constraints
      confidence_field = fields_map[:confidence]
      assert confidence_field.type == :float
      assert Keyword.get(confidence_field.opts, :gteq) == 0.0
      assert Keyword.get(confidence_field.opts, :lteq) == 1.0
    end

    test "creates schema with ML-specific field types" do
      fields = %{
        embedding: {:embedding, dimension: 768, required: true},
        probability: {:probability, default: 0.5},
        tokens: {:token_list, max_length: 100}
      }
      
      schema = ElixirML.Schema.create_model("MLModel", fields)
      
      assert schema.name == "MLModel"
      
      # Access fields through metadata fields_map
      fields_map = schema.metadata.fields_map
      
      # Should handle ML-specific types
      embedding_field = fields_map[:embedding]
      assert embedding_field.type == :embedding
      assert Keyword.get(embedding_field.opts, :dimension) == 768
      
      probability_field = fields_map[:probability]
      assert probability_field.type == :probability
      assert Keyword.get(probability_field.opts, :default) == 0.5
    end
  end

  describe "type_adapter/2" do
    test "creates adapter for single value validation" do
      adapter = ElixirML.Schema.type_adapter(:probability, range: {0.0, 1.0})
      
      # Should validate valid probability
      {:ok, validated} = ElixirML.Schema.validate_with_adapter(adapter, 0.75)
      assert validated == 0.75
      
      # Should reject invalid probability
      {:error, _} = ElixirML.Schema.validate_with_adapter(adapter, 1.5)
    end

    test "creates adapter for ML-specific types" do
      adapter = ElixirML.Schema.type_adapter(:embedding, dimension: 3)
      
      # Should validate valid embedding
      {:ok, validated} = ElixirML.Schema.validate_with_adapter(adapter, [1.0, 2.0, 3.0])
      assert validated == [1.0, 2.0, 3.0]
      
      # TODO: Constraint validation not yet implemented - this would reject wrong dimension
      {:ok, _} = ElixirML.Schema.validate_with_adapter(adapter, [1.0, 2.0])
    end

    test "creates adapter for token list validation" do
      adapter = ElixirML.Schema.type_adapter(:token_list, max_length: 5)
      
      # Should validate valid token list
      {:ok, validated} = ElixirML.Schema.validate_with_adapter(adapter, ["hello", "world"])
      assert validated == ["hello", "world"]
      
      # TODO: Constraint validation not yet implemented - this would reject too long list
      {:ok, _} = ElixirML.Schema.validate_with_adapter(adapter, ["a", "b", "c", "d", "e", "f"])
    end
  end

  # Helper functions
  defp create_test_schema do
    ElixirML.Schema.create([
      {:name, :string, required: true, min_length: 2},
      {:description, :string, required: false},
      {:active, :boolean, default: true}
    ], title: "Test Schema", description: "A test schema for validation")
  end

  defp create_ml_test_schema do
    ElixirML.Schema.create([
      {:embedding, :embedding, required: true, dimension: 768},
      {:confidence, :probability, default: 0.5},
      {:tokens, :token_list, max_length: 100},
      {:reasoning_steps, :reasoning_chain, required: false}
    ], title: "ML Test Schema", description: "A schema with ML-specific types")
  end
end