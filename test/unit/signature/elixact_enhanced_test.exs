defmodule DSPEx.Signature.ElixactEnhancedTest do
  use ExUnit.Case, async: true

  alias DSPEx.Signature.Elixact

  describe "enhanced signature to schema conversion" do
    test "converts enhanced signature with constraints to Elixact schema" do
      defmodule TestEnhancedForElixact do
        use DSPEx.Signature,
            "name:string[min_length=2,max_length=50] -> greeting:string[max_length=100]"
      end

      {:ok, schema_module} = Elixact.signature_to_schema(TestEnhancedForElixact)

      # Test that schema was generated
      assert is_atom(schema_module)
      assert function_exported?(schema_module, :validate, 1)

      # Test validation with valid data
      valid_data = %{name: "Alice", greeting: "Hello Alice!"}
      {:ok, validated} = schema_module.validate(valid_data)
      assert validated.name == "Alice"

      # Test constraint violations
      {:error, error} = schema_module.validate(%{name: "A", greeting: "Hello"})
      # Should fail min_length constraint
      assert is_struct(error)
      assert error.code == :min_length
    end

    test "handles array types with constraints" do
      defmodule TestArrayForElixact do
        use DSPEx.Signature, "tags:array(string)[min_items=1,max_items=3] -> summary:string"
      end

      {:ok, schema_module} = Elixact.signature_to_schema(TestArrayForElixact)

      # Test valid array
      {:ok, _} = schema_module.validate(%{tags: ["tag1", "tag2"], summary: "Summary"})

      # Test constraint violations
      # min_items violation
      {:error, _} = schema_module.validate(%{tags: [], summary: "Summary"})
      # max_items violation
      {:error, _} = schema_module.validate(%{tags: ["1", "2", "3", "4"], summary: "Summary"})
    end

    test "handles numeric constraints" do
      defmodule TestNumericForElixact do
        use DSPEx.Signature, "score:integer[gteq=0,lteq=100] -> grade:string"
      end

      {:ok, schema_module} = Elixact.signature_to_schema(TestNumericForElixact)

      # Test valid score
      {:ok, _} = schema_module.validate(%{score: 85, grade: "B"})

      # Test constraint violations
      # gteq violation
      {:error, _} = schema_module.validate(%{score: -1, grade: "F"})
      # lteq violation
      {:error, _} = schema_module.validate(%{score: 101, grade: "A+"})
    end

    test "handles choice constraints" do
      defmodule TestChoicesForElixact do
        use DSPEx.Signature, "grade:string[min_length=1,max_length=2] -> points:integer"
      end

      {:ok, schema_module} = Elixact.signature_to_schema(TestChoicesForElixact)

      # Test valid length
      {:ok, _} = schema_module.validate(%{grade: "A", points: 4})

      # Test invalid length
      {:error, _} = schema_module.validate(%{grade: "", points: 0})
    end

    test "handles regex format constraints" do
      defmodule TestFormatForElixact do
        use DSPEx.Signature, "email:string[min_length=5] -> status:string"
      end

      {:ok, schema_module} = Elixact.signature_to_schema(TestFormatForElixact)

      # Test valid email length
      {:ok, _} = schema_module.validate(%{email: "test@example.com", status: "valid"})

      # Test invalid email length
      {:error, _} = schema_module.validate(%{email: "x", status: "invalid"})
    end
  end

  describe "constraint mapping accuracy" do
    test "maps string constraints correctly" do
      defmodule TestStringConstraints do
        use DSPEx.Signature, "text:string[min_length=5,max_length=20] -> result:string"
      end

      # Extract the enhanced field definitions and verify constraint mapping
      enhanced_fields = TestStringConstraints.__enhanced_fields__()
      [text_field, _] = enhanced_fields

      assert text_field.constraints.min_length == 5
      assert text_field.constraints.max_length == 20
    end

    test "maps numeric constraints correctly" do
      defmodule TestNumericConstraints do
        use DSPEx.Signature, "value:float[gteq=0.0,lteq=1.0,gt=-1.0,lt=2.0] -> result:string"
      end

      enhanced_fields = TestNumericConstraints.__enhanced_fields__()
      [value_field, _] = enhanced_fields

      assert value_field.constraints.gteq == 0.0
      assert value_field.constraints.lteq == 1.0
      assert value_field.constraints.gt == -1.0
      assert value_field.constraints.lt == 2.0
    end

    test "maps array constraints correctly" do
      defmodule TestArrayConstraints do
        use DSPEx.Signature, "items:array(integer)[min_items=2,max_items=5] -> count:integer"
      end

      enhanced_fields = TestArrayConstraints.__enhanced_fields__()
      [items_field, _] = enhanced_fields

      assert items_field.constraints.min_items == 2
      assert items_field.constraints.max_items == 5
    end
  end

  describe "type conversion to Elixact" do
    test "converts basic types correctly" do
      defmodule TestBasicTypes do
        use DSPEx.Signature, "text:string, num:integer, flag:boolean, score:float -> result:any"
      end

      {:ok, schema_module} = Elixact.signature_to_schema(TestBasicTypes)

      # Test type validation
      {:ok, _} =
        schema_module.validate(%{
          text: "hello",
          num: 42,
          flag: true,
          score: 3.14,
          result: "anything"
        })

      # Test type mismatches
      {:error, _} =
        schema_module.validate(%{
          # should be string
          text: 123,
          num: 42,
          flag: true,
          score: 3.14,
          result: "anything"
        })
    end

    test "converts array types correctly" do
      defmodule TestArrayTypes do
        use DSPEx.Signature, "strings:array(string), numbers:array(integer) -> result"
      end

      {:ok, schema_module} = Elixact.signature_to_schema(TestArrayTypes)

      # Test valid arrays
      {:ok, _} =
        schema_module.validate(%{
          strings: ["a", "b", "c"],
          numbers: [1, 2, 3],
          result: "ok"
        })

      # Test invalid array element types
      {:error, _} =
        schema_module.validate(%{
          # should be strings
          strings: [1, 2, 3],
          numbers: [1, 2, 3],
          result: "ok"
        })
    end
  end

  describe "validation with enhanced signatures" do
    test "validates input fields with enhanced constraints" do
      defmodule TestInputValidation do
        use DSPEx.Signature, "username:string[min_length=3,max_length=20] -> welcome:string"
      end

      # Test field-type validation
      {:ok, validated} =
        Elixact.validate_with_elixact(
          TestInputValidation,
          %{username: "alice"},
          field_type: :inputs
        )

      assert validated.username == "alice"

      # Test constraint violations
      {:error, errors} =
        Elixact.validate_with_elixact(
          TestInputValidation,
          # too short
          %{username: "al"},
          field_type: :inputs
        )

      assert length(errors) > 0
    end

    test "validates output fields with enhanced constraints" do
      defmodule TestOutputValidation do
        use DSPEx.Signature,
            "query:string -> response:string[max_length=100], confidence:float[gteq=0.0,lteq=1.0]"
      end

      # Test valid outputs
      {:ok, _} =
        Elixact.validate_with_elixact(
          TestOutputValidation,
          %{response: "Short response", confidence: 0.85},
          field_type: :outputs
        )

      # Test constraint violations
      {:error, _} =
        Elixact.validate_with_elixact(
          TestOutputValidation,
          # confidence too high
          %{response: "Valid response", confidence: 1.5},
          field_type: :outputs
        )
    end
  end

  describe "JSON schema generation from enhanced signatures" do
    test "generates JSON schema with constraints" do
      defmodule TestJSONSchema do
        use DSPEx.Signature, "name:string[min_length=2], age:integer[gteq=0] -> profile:string"
      end

      {:ok, json_schema} = Elixact.to_json_schema(TestJSONSchema)

      assert json_schema["type"] == "object"
      assert is_map(json_schema["properties"])

      # Check that constraints are preserved in JSON schema
      name_props = json_schema["properties"]["name"]
      assert name_props["minLength"] == 2

      age_props = json_schema["properties"]["age"]
      assert age_props["minimum"] == 0
    end

    test "generates JSON schema for array types" do
      defmodule TestArrayJSONSchema do
        use DSPEx.Signature, "tags:array(string)[min_items=1,max_items=5] -> summary:string"
      end

      {:ok, json_schema} = Elixact.to_json_schema(TestArrayJSONSchema)

      tags_props = json_schema["properties"]["tags"]
      assert tags_props["type"] == "array"
      assert tags_props["minItems"] == 1
      assert tags_props["maxItems"] == 5
      assert tags_props["items"]["type"] == "string"
    end
  end

  describe "backward compatibility with basic signatures" do
    test "works with basic signatures" do
      defmodule TestBasicCompatibility do
        use DSPEx.Signature, "question -> answer"
      end

      # Should still work without enhanced features
      {:ok, schema_module} = Elixact.signature_to_schema(TestBasicCompatibility)
      {:ok, _} = schema_module.validate(%{question: "test", answer: "response"})
    end

    test "handles mixed enhanced and basic usage" do
      defmodule TestMixedUsage do
        use DSPEx.Signature, "enhanced:string[min_length=1], basic -> result"
      end

      {:ok, schema_module} = Elixact.signature_to_schema(TestMixedUsage)
      {:ok, _} = schema_module.validate(%{enhanced: "test", basic: "anything", result: "ok"})
    end
  end

  describe "error handling and edge cases" do
    test "handles invalid signature modules gracefully" do
      defmodule NotASignature do
        def some_function, do: :ok
      end

      {:error, reason} = Elixact.signature_to_schema(NotASignature)
      assert reason != nil
    end

    test "handles empty constraint maps" do
      defmodule TestEmptyConstraints do
        use DSPEx.Signature, "field:string -> result:string"
      end

      {:ok, schema_module} = Elixact.signature_to_schema(TestEmptyConstraints)
      {:ok, _} = schema_module.validate(%{field: "test", result: "ok"})
    end
  end
end
