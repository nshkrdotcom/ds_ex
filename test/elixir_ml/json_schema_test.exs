defmodule ElixirML.JsonSchemaTest do
  use ExUnit.Case
  alias ElixirML.JsonSchema
  alias ElixirML.Runtime

  describe "generate/2" do
    test "generates basic JSON schema from runtime schema" do
      schema =
        Runtime.create_schema([
          {:name, :string, required: true, description: "User name"},
          {:age, :integer, required: false, default: 0}
        ])

      json_schema = JsonSchema.generate(schema)

      assert json_schema["type"] == "object"
      assert json_schema["required"] == ["name"]
      assert json_schema["additionalProperties"] == false

      properties = json_schema["properties"]
      assert properties["name"]["type"] == "string"
      assert properties["name"]["description"] == "User name"
      assert properties["age"]["type"] == "integer"
    end

    test "generates OpenAI-optimized JSON schema" do
      schema =
        Runtime.create_schema([
          {:question, :string, required: true},
          {:confidence, :probability, required: true}
        ])

      json_schema = JsonSchema.generate(schema, provider: :openai)

      assert json_schema["additionalProperties"] == false
      assert json_schema["x-openai-optimized"] == true
      assert is_list(json_schema["required"])
      refute Map.has_key?(json_schema, "definitions")

      # OpenAI should have strict required array (sorted alphabetically)
      assert json_schema["required"] == ["confidence", "question"]
    end

    test "generates Anthropic-optimized JSON schema" do
      schema =
        Runtime.create_schema([
          {:input_text, :string, required: true},
          {:reasoning, :reasoning_chain, required: false}
        ])

      json_schema = JsonSchema.generate(schema, provider: :anthropic)

      assert json_schema["additionalProperties"] == false
      assert json_schema["x-anthropic-optimized"] == true
      assert Map.has_key?(json_schema, "properties")

      # Anthropic should have enhanced descriptions
      properties = json_schema["properties"]

      assert String.contains?(properties["input_text"]["description"], "input_text") ||
               properties["input_text"]["description"] != ""
    end

    test "generates Groq-optimized JSON schema" do
      schema =
        Runtime.create_schema([
          {:prompt, :string, required: true},
          {:temperature, :float, required: false, range: {0.0, 2.0}}
        ])

      json_schema = JsonSchema.generate(schema, provider: :groq)

      assert json_schema["additionalProperties"] == false
      assert json_schema["x-groq-optimized"] == true
      assert is_list(json_schema["required"])
    end

    test "handles ML-specific types correctly" do
      schema =
        Runtime.create_schema([
          {:embedding, :embedding, required: true, dimensions: 1536},
          {:confidence, :probability, required: true},
          {:score, :confidence_score, required: false},
          {:tokens, :token_list, required: false},
          {:reasoning, :reasoning_chain, required: false}
        ])

      json_schema = JsonSchema.generate(schema)

      properties = json_schema["properties"]

      # Embedding should be array with number items
      embedding_prop = properties["embedding"]
      assert embedding_prop["type"] == "array"
      assert embedding_prop["items"]["type"] == "number"
      assert embedding_prop["minItems"] == 1536
      assert embedding_prop["maxItems"] == 1536

      # Probability should be number with 0-1 range
      confidence_prop = properties["confidence"]
      assert confidence_prop["type"] == "number"
      assert confidence_prop["minimum"] == 0.0
      assert confidence_prop["maximum"] == 1.0

      # Confidence score should be non-negative number
      score_prop = properties["score"]
      assert score_prop["type"] == "number"
      assert score_prop["minimum"] == 0.0
      refute Map.has_key?(score_prop, "maximum")

      # Token list should be array of strings or integers
      tokens_prop = properties["tokens"]
      assert tokens_prop["type"] == "array"
      assert tokens_prop["items"]["type"] == ["string", "integer"]

      # Reasoning chain should be array of objects
      reasoning_prop = properties["reasoning"]
      assert reasoning_prop["type"] == "array"
      assert reasoning_prop["items"]["type"] == "object"
      step_props = reasoning_prop["items"]["properties"]
      assert step_props["step"]["type"] == "string"
      assert step_props["reasoning"]["type"] == "string"
    end

    test "supports schema compilation from module" do
      defmodule TestSchema do
        use ElixirML.Schema

        defschema Example do
          field(:input, :string, required: true)
          field(:output, :string, required: true)
          field(:confidence, :probability, default: 0.5)
        end
      end

      json_schema = JsonSchema.generate(TestSchema.Example)

      assert json_schema["type"] == "object"
      assert json_schema["required"] == ["input", "output"]

      properties = json_schema["properties"]
      assert properties["input"]["type"] == "string"
      assert properties["output"]["type"] == "string"
      assert properties["confidence"]["type"] == "number"
    end
  end

  describe "optimize_for_provider/2" do
    test "applies OpenAI-specific optimizations" do
      base_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "format" => "date"},
          "email" => %{"type" => "string", "format" => "email"}
        },
        "required" => ["name"]
      }

      optimized = JsonSchema.optimize_for_provider(base_schema, :openai)

      assert optimized["additionalProperties"] == false
      assert optimized["x-openai-optimized"] == true

      # OpenAI doesn't support some formats, should be removed
      properties = optimized["properties"]
      refute Map.has_key?(properties["name"], "format")
      refute Map.has_key?(properties["email"], "format")
    end

    test "applies Anthropic-specific optimizations" do
      base_schema = %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "format" => "uri"},
          "data" => %{"type" => "object"}
        }
      }

      optimized = JsonSchema.optimize_for_provider(base_schema, :anthropic)

      assert optimized["additionalProperties"] == false
      assert optimized["x-anthropic-optimized"] == true

      # Anthropic should ensure object properties are defined
      assert Map.has_key?(optimized, "properties")

      # Should remove unsupported formats
      properties = optimized["properties"]
      refute Map.has_key?(properties["query"], "format")
    end

    test "handles generic provider gracefully" do
      base_schema = %{
        "type" => "object",
        "properties" => %{"field" => %{"type" => "string"}}
      }

      optimized = JsonSchema.optimize_for_provider(base_schema, :unknown_provider)

      # Should return original schema unchanged for unknown providers
      assert optimized == base_schema
    end
  end

  describe "flatten_schema/1" do
    test "flattens nested schema definitions" do
      nested_schema = %{
        "type" => "object",
        "properties" => %{
          "user" => %{"$ref" => "#/definitions/User"}
        },
        "definitions" => %{
          "User" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"}
            }
          }
        }
      }

      flattened = JsonSchema.flatten_schema(nested_schema)

      # Should inline the reference
      user_prop = flattened["properties"]["user"]
      assert user_prop["type"] == "object"
      assert user_prop["properties"]["name"]["type"] == "string"

      # Should remove definitions section
      refute Map.has_key?(flattened, "definitions")
    end

    test "handles schemas without definitions" do
      simple_schema = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}}
      }

      flattened = JsonSchema.flatten_schema(simple_schema)

      # Should return unchanged
      assert flattened == simple_schema
    end
  end

  describe "enhance_descriptions/1" do
    test "enhances empty or missing descriptions" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "field1" => %{"type" => "string"},
          "field2" => %{"type" => "string", "description" => ""},
          "field3" => %{"type" => "string", "description" => "Existing description"}
        }
      }

      enhanced = JsonSchema.enhance_descriptions(schema)

      properties = enhanced["properties"]
      assert String.contains?(properties["field1"]["description"], "field1")
      assert String.contains?(properties["field2"]["description"], "field2")
      assert properties["field3"]["description"] == "Existing description"
    end

    test "handles schemas without properties" do
      schema = %{"type" => "string"}

      enhanced = JsonSchema.enhance_descriptions(schema)

      assert enhanced == schema
    end
  end

  describe "remove_unsupported_formats/2" do
    test "removes specified unsupported formats" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "date_field" => %{"type" => "string", "format" => "date"},
          "email_field" => %{"type" => "string", "format" => "email"},
          "regular_field" => %{"type" => "string", "format" => "custom"}
        }
      }

      cleaned = JsonSchema.remove_unsupported_formats(schema, [:date, :email])

      properties = cleaned["properties"]
      refute Map.has_key?(properties["date_field"], "format")
      refute Map.has_key?(properties["email_field"], "format")
      assert properties["regular_field"]["format"] == "custom"
    end

    test "handles schemas without properties or formats" do
      schema = %{"type" => "string"}

      cleaned = JsonSchema.remove_unsupported_formats(schema, [:date])

      assert cleaned == schema
    end
  end

  describe "validate_json_schema/1" do
    test "validates correct JSON schema structure" do
      valid_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"}
        },
        "required" => ["name"],
        "additionalProperties" => false
      }

      assert {:ok, ^valid_schema} = JsonSchema.validate_json_schema(valid_schema)
    end

    test "detects invalid JSON schema structure" do
      invalid_schema = %{
        "type" => "invalid_type",
        "properties" => "not_an_object"
      }

      assert {:error, _reason} = JsonSchema.validate_json_schema(invalid_schema)
    end

    test "handles missing required fields" do
      incomplete_schema = %{
        "properties" => %{"name" => %{"type" => "string"}}
      }

      assert {:error, reason} = JsonSchema.validate_json_schema(incomplete_schema)
      assert String.contains?(reason, "type")
    end
  end

  describe "to_openapi_schema/2" do
    test "converts to OpenAPI 3.0 schema format" do
      runtime_schema =
        Runtime.create_schema([
          {:user_id, :string, required: true, description: "Unique user identifier"},
          {:score, :probability, required: false}
        ])

      openapi_schema = JsonSchema.to_openapi_schema(runtime_schema, version: "3.0")

      # Should have OpenAPI-specific structure
      assert openapi_schema["type"] == "object"
      assert is_map(openapi_schema["properties"])
      assert openapi_schema["required"] == ["user_id"]

      # Should include example if possible
      assert Map.has_key?(openapi_schema, "example") or
               Map.has_key?(openapi_schema["properties"]["user_id"], "example")
    end
  end

  describe "add_examples/2" do
    test "adds examples to schema properties" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"},
          "score" => %{"type" => "number", "minimum" => 0.0, "maximum" => 1.0}
        }
      }

      with_examples =
        JsonSchema.add_examples(schema, %{
          "name" => "Alice",
          "age" => 30,
          "score" => 0.95
        })

      properties = with_examples["properties"]
      assert properties["name"]["example"] == "Alice"
      assert properties["age"]["example"] == 30
      assert properties["score"]["example"] == 0.95
    end

    test "handles missing properties gracefully" do
      schema = %{"type" => "string"}

      with_examples = JsonSchema.add_examples(schema, %{"field" => "value"})

      # Should not crash and return original schema
      assert with_examples == schema
    end
  end

  describe "merge_schemas/2" do
    test "merges multiple JSON schemas" do
      schema1 = %{
        "type" => "object",
        "properties" => %{
          "field1" => %{"type" => "string"}
        },
        "required" => ["field1"]
      }

      schema2 = %{
        "type" => "object",
        "properties" => %{
          "field2" => %{"type" => "integer"}
        },
        "required" => ["field2"]
      }

      {:ok, merged} = JsonSchema.merge_schemas([schema1, schema2])

      assert merged["type"] == "object"
      assert Map.has_key?(merged["properties"], "field1")
      assert Map.has_key?(merged["properties"], "field2")
      assert "field1" in merged["required"]
      assert "field2" in merged["required"]
    end

    test "handles conflicting field types" do
      schema1 = %{
        "type" => "object",
        "properties" => %{
          "field" => %{"type" => "string"}
        }
      }

      schema2 = %{
        "type" => "object",
        "properties" => %{
          "field" => %{"type" => "integer"}
        }
      }

      assert {:error, reason} = JsonSchema.merge_schemas([schema1, schema2])
      assert String.contains?(reason, "conflict")
    end
  end
end
