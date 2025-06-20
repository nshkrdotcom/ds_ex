defmodule ElixirML.RuntimeTest do
  use ExUnit.Case, async: true

  alias ElixirML.Runtime

  describe "create_schema/2" do
    test "creates runtime schema from field definitions" do
      fields = [
        {:name, :string, required: true, min_length: 2},
        {:confidence, :probability, default: 0.5}
      ]

      schema = Runtime.create_schema(fields, title: "Test Schema")

      assert schema.title == "Test Schema"
      assert Map.has_key?(schema.fields, :name)
      assert Map.has_key?(schema.fields, :confidence)
    end

    test "supports ML-specific types" do
      fields = [
        {:embedding, :embedding, required: true},
        {:temperature, :float, range: {0.0, 2.0}}
      ]

      schema = Runtime.create_schema(fields)

      {:ok, validated} =
        Runtime.validate(schema, %{
          embedding: [1.0, 2.0, 3.0],
          temperature: 0.7
        })

      assert validated.embedding == [1.0, 2.0, 3.0]
      assert validated.temperature == 0.7
    end

    test "handles field constraints and defaults" do
      fields = [
        {:title, :string, required: true, min_length: 5},
        {:score, :probability, default: 0.8},
        {:tokens, :token_list, required: false}
      ]

      schema = Runtime.create_schema(fields)

      # Test with valid data
      {:ok, validated} =
        Runtime.validate(schema, %{
          title: "Valid Title",
          score: 0.9
        })

      assert validated.title == "Valid Title"
      assert validated.score == 0.9
      assert validated[:tokens] == nil

      # Test with defaults applied
      {:ok, validated} =
        Runtime.validate(schema, %{
          title: "Valid Title"
        })

      assert validated.score == 0.8
    end

    test "validates ML types correctly" do
      fields = [
        {:embedding, :embedding, required: true},
        {:confidence, :confidence_score, required: true}
      ]

      schema = Runtime.create_schema(fields)

      # Valid data
      {:ok, _} =
        Runtime.validate(schema, %{
          embedding: [1.0, 2.0, 3.0],
          confidence: 0.95
        })

      # Invalid embedding
      {:error, error} =
        Runtime.validate(schema, %{
          embedding: "not a list",
          confidence: 0.95
        })

      assert error.message =~ "embedding"

      # Invalid confidence score
      {:error, error} =
        Runtime.validate(schema, %{
          embedding: [1.0, 2.0, 3.0],
          confidence: -0.5
        })

      assert error.message =~ "confidence"
    end
  end

  describe "create_model/3 (Pydantic pattern)" do
    test "creates schema with Pydantic create_model pattern" do
      fields = %{
        reasoning: {:string, description: "Chain of thought"},
        answer: {:string, required: true},
        confidence: {:float, gteq: 0.0, lteq: 1.0}
      }

      schema = Runtime.create_model("LLMOutput", fields)

      assert schema.name == "LLMOutput"
      assert Map.has_key?(schema.fields, :reasoning)
      assert Map.has_key?(schema.fields, :answer)
      assert Map.has_key?(schema.fields, :confidence)
    end

    test "handles Pydantic-style field constraints" do
      fields = %{
        temperature: {:float, ge: 0.0, le: 2.0, default: 0.7},
        max_tokens: {:integer, gt: 0, le: 4096},
        provider: {:choice, choices: [:openai, :anthropic], default: :openai}
      }

      schema = Runtime.create_model("ModelConfig", fields)

      {:ok, validated} =
        Runtime.validate(schema, %{
          temperature: 1.2,
          max_tokens: 1000
        })

      assert validated.temperature == 1.2
      assert validated.max_tokens == 1000
      # default applied
      assert validated.provider == :openai
    end
  end

  describe "infer_schema/2" do
    test "infers schema from example data" do
      examples = [
        %{name: "Alice", age: 30, score: 0.95},
        %{name: "Bob", age: 25, score: 0.88}
      ]

      schema = Runtime.infer_schema(examples, title: "Person")

      assert schema.title == "Person"
      assert Map.has_key?(schema.fields, :name)
      assert Map.has_key?(schema.fields, :age)
      assert Map.has_key?(schema.fields, :score)

      # Should infer types correctly
      name_field = schema.fields[:name]
      age_field = schema.fields[:age]
      score_field = schema.fields[:score]

      assert name_field.type == :string
      assert age_field.type == :integer
      # Inferred as probability since 0.0 <= value <= 1.0
      assert score_field.type == :probability
    end

    test "handles nested structures" do
      examples = [
        %{
          user: %{name: "Alice", email: "alice@test.com"},
          embedding: [1.0, 2.0, 3.0],
          metadata: %{source: "test"}
        }
      ]

      schema = Runtime.infer_schema(examples)

      user_field = schema.fields[:user]
      embedding_field = schema.fields[:embedding]

      assert user_field.type == :map
      assert embedding_field.type == :embedding
    end
  end

  describe "merge_schemas/2" do
    test "merges multiple schemas" do
      schema1 =
        Runtime.create_schema(
          [
            {:input_text, :string, required: true}
          ],
          title: "Input"
        )

      schema2 =
        Runtime.create_schema(
          [
            {:output_text, :string, required: true},
            {:confidence, :probability, default: 0.8}
          ],
          title: "Output"
        )

      merged = Runtime.merge_schemas([schema1, schema2], title: "Complete")

      assert merged.title == "Complete"
      assert Map.has_key?(merged.fields, :input_text)
      assert Map.has_key?(merged.fields, :output_text)
      assert Map.has_key?(merged.fields, :confidence)
    end

    test "handles field conflicts with last-wins strategy" do
      schema1 =
        Runtime.create_schema([
          {:score, :integer, default: 1}
        ])

      schema2 =
        Runtime.create_schema([
          {:score, :probability, default: 0.8}
        ])

      merged = Runtime.merge_schemas([schema1, schema2])

      score_field = merged.fields[:score]
      assert score_field.type == :probability
      assert score_field.default == 0.8
    end
  end

  describe "extract_variables/1" do
    test "extracts variable fields from schema" do
      fields = [
        {:name, :string, required: true},
        {:temperature, :float, range: {0.0, 2.0}, variable: true},
        {:provider, :choice, choices: [:openai, :anthropic], variable: true, default: :openai}
      ]

      schema = Runtime.create_schema(fields)
      variables = Runtime.extract_variables(schema)

      assert length(variables) == 2

      variable_names = Enum.map(variables, fn {name, _type, _opts} -> name end)
      assert :temperature in variable_names
      assert :provider in variable_names
      assert :name not in variable_names
    end
  end

  describe "optimize_for_provider/2" do
    test "optimizes schema for OpenAI" do
      fields = [
        {:question, :string, required: true},
        {:context, :embedding, dimensions: 1536},
        {:answer, :string, required: true}
      ]

      schema = Runtime.create_schema(fields)
      optimized = Runtime.optimize_for_provider(schema, :openai)

      # Should have OpenAI-specific optimizations
      assert optimized.provider_config.provider == :openai
      assert optimized.provider_config.flatten_nested == true
      assert optimized.provider_config.enhance_descriptions == true
    end

    test "optimizes schema for Anthropic" do
      fields = [
        {:reasoning, :reasoning_chain, required: false},
        {:answer, :string, required: true}
      ]

      schema = Runtime.create_schema(fields)
      optimized = Runtime.optimize_for_provider(schema, :anthropic)

      assert optimized.provider_config.provider == :anthropic
      assert optimized.provider_config.preserve_structure == true
    end
  end

  describe "to_json_schema/2" do
    test "generates provider-optimized JSON schema" do
      fields = [
        {:question, :string, required: true, description: "User question"},
        {:confidence, :probability, default: 0.8},
        {:embedding, :embedding, dimensions: 1536}
      ]

      schema = Runtime.create_schema(fields, title: "QA Schema")

      # OpenAI format
      openai_json = Runtime.to_json_schema(schema, provider: :openai)

      assert openai_json["type"] == "object"
      assert openai_json["title"] == "QA Schema"
      assert is_map(openai_json["properties"])
      assert openai_json["required"] == ["question"]

      # Should be flattened for OpenAI
      refute Map.has_key?(openai_json, "definitions")

      # Anthropic format
      anthropic_json = Runtime.to_json_schema(schema, provider: :anthropic)

      assert anthropic_json["type"] == "object"
      assert is_map(anthropic_json["properties"])
    end
  end

  describe "type_adapter/2" do
    test "creates single-field adapter for validation" do
      adapter = Runtime.type_adapter(:embedding, dimensions: 1536)

      {:ok, validated} = Runtime.validate_with_adapter(adapter, [1.0, 2.0, 3.0])
      assert validated == [1.0, 2.0, 3.0]

      {:error, _} = Runtime.validate_with_adapter(adapter, "not an embedding")
    end

    test "handles Pydantic-style single type validation" do
      adapter = Runtime.type_adapter(:probability)

      {:ok, 0.5} = Runtime.validate_with_adapter(adapter, 0.5)
      {:error, _} = Runtime.validate_with_adapter(adapter, 1.5)
    end
  end

  describe "validation_errors" do
    test "provides detailed error information" do
      fields = [
        {:name, :string, required: true, min_length: 5},
        {:score, :probability, required: true}
      ]

      schema = Runtime.create_schema(fields)

      {:error, error} =
        Runtime.validate(schema, %{
          # Too short
          name: "Hi",
          # Invalid probability
          score: 1.5
        })

      assert %ElixirML.Schema.ValidationError{} = error
      assert error.schema == ElixirML.Runtime
      assert is_map(error.data)
      assert error.message =~ "name" or error.message =~ "score"
    end
  end
end
