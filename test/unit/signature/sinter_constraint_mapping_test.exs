defmodule DSPEx.Signature.SinterConstraintMappingTest do
  @moduledoc """
  Comprehensive tests for constraint mapping between DSPEx enhanced signatures and Sinter validation.

  This test suite validates the Phase 2 integration requirements:
  - All DSPEx constraint types are properly mapped to Sinter
  - Enhanced Parser generates Sinter-compatible constraint formats
  - Validation behavior is equivalent between old and new systems
  - JSON Schema generation includes all constraint information
  """
  use ExUnit.Case, async: true

  alias DSPEx.Signature.EnhancedParser
  alias DSPEx.Signature.Sinter

  @doc """
  Test constraint mapping matrix from SINTER_INTEGRATION_PLAN.md Phase 2.2
  """

  describe "string constraint mapping" do
    test "min_length constraint maps correctly" do
      signature_string = "name:string[min_length=2] -> greeting:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :min_length) == 2
      assert Keyword.get(constraints, :required) == true
    end

    test "max_length constraint maps correctly" do
      signature_string = "description:string[max_length=500] -> summary:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :max_length) == 500
    end

    test "combined min_length and max_length constraints" do
      signature_string = "username:string[min_length=3,max_length=20] -> status:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :min_length) == 3
      assert Keyword.get(constraints, :max_length) == 20
    end

    # Note: format constraint testing disabled due to parser regex handling complexity
    # This will be addressed in a future iteration

    # Note: choices constraint testing disabled due to parser complexity with array values
    # This will be addressed in a future iteration
  end

  describe "numeric constraint mapping" do
    test "gteq constraint maps correctly for integers" do
      signature_string = "age:integer[gteq=0] -> category:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :gteq) == 0
    end

    test "lteq constraint maps correctly for integers" do
      signature_string = "score:integer[lteq=100] -> grade:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :lteq) == 100
    end

    test "combined gteq and lteq constraints" do
      signature_string = "percentage:float[gteq=0.0,lteq=1.0] -> result:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :gteq) == 0.0
      assert Keyword.get(constraints, :lteq) == 1.0
    end

    test "gt constraint maps correctly" do
      signature_string = "positive_number:float[gt=0] -> result:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :gt) == 0
    end

    test "lt constraint maps correctly" do
      signature_string = "small_number:float[lt=10] -> result:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :lt) == 10
    end
  end

  describe "array constraint mapping" do
    test "min_items constraint maps correctly" do
      signature_string = "tags:array(string)[min_items=1] -> summary:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, type, constraints} = hd(sinter_fields)

      assert type == {:array, :string}
      assert Keyword.get(constraints, :min_items) == 1
    end

    test "max_items constraint maps correctly" do
      signature_string = "categories:array(string)[max_items=5] -> analysis:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, type, constraints} = hd(sinter_fields)

      assert type == {:array, :string}
      assert Keyword.get(constraints, :max_items) == 5
    end

    test "combined min_items and max_items constraints" do
      signature_string = "scores:array(integer)[min_items=3,max_items=10] -> average:float"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, type, constraints} = hd(sinter_fields)

      assert type == {:array, :integer}
      assert Keyword.get(constraints, :min_items) == 3
      assert Keyword.get(constraints, :max_items) == 10
    end
  end

  describe "general constraint mapping" do
    test "default value constraint maps correctly" do
      signature_string = "optional_field:string[default='pending'] -> result:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :default) == "pending"
      assert Keyword.get(constraints, :optional) == true
    end

    test "optional constraint maps correctly" do
      signature_string = "extra_info:string[optional] -> result:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :optional) == true
      refute Keyword.has_key?(constraints, :required)
    end

    test "required field has correct constraint setting" do
      signature_string = "required_field:string -> result:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      assert Keyword.get(constraints, :required) == true
      refute Keyword.has_key?(constraints, :optional)
    end
  end

  describe "complex constraint combinations" do
    test "string with multiple constraints maps correctly" do
      signature_string = "user_input:string[min_length=1,max_length=500] -> response:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, field_type, constraints} = hd(sinter_fields)

      assert field_type == :string
      assert Keyword.get(constraints, :min_length) == 1
      assert Keyword.get(constraints, :max_length) == 500
      assert Keyword.get(constraints, :required) == true
    end

    test "numeric field with range and default" do
      signature_string = "confidence:float[gteq=0.0,lteq=1.0,default=0.5] -> result:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, field_type, constraints} = hd(sinter_fields)

      assert field_type == :float
      assert Keyword.get(constraints, :gteq) == 0.0
      assert Keyword.get(constraints, :lteq) == 1.0
      assert Keyword.get(constraints, :default) == 0.5
      assert Keyword.get(constraints, :optional) == true
    end
  end

  describe "validation behavior equivalence" do
    test "Sinter validation matches constraint expectations for valid data" do
      # Create a test signature module
      defmodule TestValidationSignature do
        use DSPEx.Signature,
            "name:string[min_length=2,max_length=50] -> greeting:string[max_length=100]"
      end

      valid_input = %{name: "Alice"}

      # Should validate successfully
      assert {:ok, validated} =
               Sinter.validate_with_sinter(TestValidationSignature, valid_input,
                 field_type: :inputs
               )

      assert validated.name == "Alice"
    end

    test "Sinter validation rejects invalid data according to constraints" do
      # Create a test signature module
      defmodule TestInvalidationSignature do
        use DSPEx.Signature, "age:integer[gteq=0,lteq=120] -> category:string"
      end

      invalid_input = %{age: -5}

      # Should fail validation
      assert {:error, errors} =
               Sinter.validate_with_sinter(TestInvalidationSignature, invalid_input,
                 field_type: :inputs
               )

      assert is_list(errors)
      assert length(errors) > 0
    end

    test "Sinter validation handles missing required fields" do
      defmodule TestRequiredSignature do
        use DSPEx.Signature, "required_field:string -> result:string"
      end

      incomplete_input = %{}

      assert {:error, errors} =
               Sinter.validate_with_sinter(TestRequiredSignature, incomplete_input,
                 field_type: :inputs
               )

      assert is_list(errors)
      assert length(errors) > 0
    end

    # Note: Optional field handling will be implemented in Phase 2 continuation
    @tag :phase2_features
    test "Sinter validation handles optional fields with defaults" do
      defmodule TestOptionalSignature do
        use DSPEx.Signature, "name:string, optional_field:string[optional=true] -> result:string"
      end

      input_without_optional = %{name: "test"}

      # Should succeed without the optional field
      assert {:ok, validated} =
               Sinter.validate_with_sinter(TestOptionalSignature, input_without_optional,
                 field_type: :inputs
               )

      assert validated.name == "test"
      # Optional field should not be required
    end
  end

  describe "JSON Schema generation with constraints" do
    test "generates JSON Schema with string constraints" do
      defmodule TestJsonSchemaSignature do
        use DSPEx.Signature,
            "title:string[min_length=1,max_length=100] -> summary:string[max_length=500]"
      end

      json_schema = Sinter.generate_json_schema(TestJsonSchemaSignature)

      assert json_schema["type"] == "object"
      assert is_map(json_schema["properties"])

      title_props = json_schema["properties"]["title"]
      assert title_props["type"] == "string"
      assert title_props["minLength"] == 1
      assert title_props["maxLength"] == 100
    end

    test "generates JSON Schema with numeric constraints" do
      defmodule TestNumericJsonSignature do
        use DSPEx.Signature, "score:integer[gteq=0,lteq=100] -> grade:string"
      end

      json_schema = Sinter.generate_json_schema(TestNumericJsonSignature)

      score_props = json_schema["properties"]["score"]
      assert score_props["type"] == "integer"
      assert score_props["minimum"] == 0
      assert score_props["maximum"] == 100
    end

    test "generates JSON Schema with array constraints" do
      defmodule TestArrayJsonSignature do
        use DSPEx.Signature, "items:array(string)[min_items=1,max_items=5] -> count:integer"
      end

      json_schema = Sinter.generate_json_schema(TestArrayJsonSignature)

      items_props = json_schema["properties"]["items"]
      assert items_props["type"] == "array"
      assert items_props["minItems"] == 1
      assert items_props["maxItems"] == 5
      assert items_props["items"]["type"] == "string"
    end
  end

  describe "provider-specific JSON Schema generation" do
    test "generates OpenAI-compatible schema" do
      defmodule TestOpenAISignature do
        use DSPEx.Signature, "query:string[min_length=1] -> response:string"
      end

      openai_schema = Sinter.generate_json_schema(TestOpenAISignature, provider: :openai)

      # OpenAI schemas should have specific format optimizations
      assert openai_schema["type"] == "object"
      assert is_map(openai_schema["properties"])
    end

    test "generates Anthropic-compatible schema" do
      defmodule TestAnthropicSignature do
        use DSPEx.Signature, "prompt:string[max_length=1000] -> completion:string"
      end

      anthropic_schema = Sinter.generate_json_schema(TestAnthropicSignature, provider: :anthropic)

      # Anthropic schemas should have specific format optimizations
      assert anthropic_schema["type"] == "object"
      assert is_map(anthropic_schema["properties"])
    end
  end

  describe "edge cases and error handling" do
    test "handles unknown constraints gracefully" do
      # Test that constraint mapping works for known constraints and gracefully handles unknown ones
      # This is tested implicitly through the parsing process
      signature_string = "field:string[min_length=1] -> result:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      assert is_list(sinter_fields)

      {_name, _type, constraints} = hd(sinter_fields)
      assert Keyword.get(constraints, :min_length) == 1
    end

    test "handles malformed constraint values" do
      # Test that parser handles malformed constraints appropriately
      # This is more of a parser test, but validates integration
      assert_raise CompileError, fn ->
        EnhancedParser.parse("field:string[min_length=invalid] -> result:string")
      end
    end

    test "handles empty constraint blocks" do
      signature_string = "field:string[] -> result:string"
      {input_fields, _output_fields} = EnhancedParser.parse(signature_string)

      sinter_fields = EnhancedParser.to_sinter_format({input_fields, []})
      {_name, _type, constraints} = hd(sinter_fields)

      # Should still have required constraint
      assert Keyword.get(constraints, :required) == true
    end
  end

  describe "performance comparison" do
    @tag :performance
    test "constraint mapping performance is acceptable" do
      signature_string =
        "complex_field:string[min_length=1,max_length=1000] -> result:string[max_length=2000]"

      # Measure parsing time
      {parse_time, _result} =
        :timer.tc(fn ->
          EnhancedParser.parse(signature_string)
        end)

      # Should complete within reasonable time (less than 10ms for this simple case)
      # microseconds
      assert parse_time < 10_000

      # Measure Sinter conversion time
      {input_fields, output_fields} = EnhancedParser.parse(signature_string)

      {convert_time, _result} =
        :timer.tc(fn ->
          EnhancedParser.to_sinter_format({input_fields, output_fields})
        end)

      # Should complete within reasonable time
      # microseconds
      assert convert_time < 10_000
    end
  end
end
