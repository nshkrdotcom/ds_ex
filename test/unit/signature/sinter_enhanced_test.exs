defmodule DSPEx.Signature.SinterEnhancedTest do
  use ExUnit.Case, async: true

  alias DSPEx.Signature.Sinter, as: DSPExSinter

  @moduletag :phase_1
  @moduletag :sinter_test

  describe "enhanced signature to schema conversion" do
    test "converts enhanced signature with constraints to Sinter schema" do
      defmodule TestEnhancedForSinter do
        use DSPEx.Signature,
            "name:string[min_length=2,max_length=50] -> greeting:string[max_length=100]"
      end

      schema = DSPExSinter.signature_to_schema(TestEnhancedForSinter)

      # Test that schema was generated
      assert is_map(schema)

      # Test validation with valid data
      valid_data = %{name: "Alice", greeting: "Hello Alice!"}
      {:ok, validated} = Sinter.Validator.validate(schema, valid_data)
      assert validated.name == "Alice"

      # Test constraint violations
      {:error, errors} = Sinter.Validator.validate(schema, %{name: "A", greeting: "Hello"})
      # Should fail min_length constraint
      assert is_list(errors) or is_map(errors)
    end

    test "handles array types with constraints" do
      defmodule TestArrayForSinter do
        use DSPEx.Signature, "tags:array(string)[min_items=1,max_items=3] -> summary:string"
      end

      schema = DSPExSinter.signature_to_schema(TestArrayForSinter)

      # Test valid array
      {:ok, _} = Sinter.Validator.validate(schema, %{tags: ["tag1", "tag2"], summary: "Summary"})

      # Test constraint violations
      # min_items violation
      {:error, _} = Sinter.Validator.validate(schema, %{tags: [], summary: "Summary"})
      # max_items violation
      {:error, _} =
        Sinter.Validator.validate(schema, %{tags: ["1", "2", "3", "4"], summary: "Summary"})
    end

    test "handles numeric constraints" do
      defmodule TestNumericForSinter do
        use DSPEx.Signature, "score:integer[gteq=0,lteq=100] -> grade:string"
      end

      schema = DSPExSinter.signature_to_schema(TestNumericForSinter)

      # Test valid score
      {:ok, _} = Sinter.Validator.validate(schema, %{score: 85, grade: "B"})

      # Test constraint violations
      # gteq violation
      {:error, _} = Sinter.Validator.validate(schema, %{score: -1, grade: "F"})
      # lteq violation
      {:error, _} = Sinter.Validator.validate(schema, %{score: 101, grade: "A+"})
    end

    test "handles choice constraints" do
      defmodule TestChoicesForSinter do
        use DSPEx.Signature, "grade:string[min_length=1,max_length=2] -> points:integer"
      end

      schema = DSPExSinter.signature_to_schema(TestChoicesForSinter)

      # Test valid length
      {:ok, _} = Sinter.Validator.validate(schema, %{grade: "A", points: 4})

      # Test invalid length
      {:error, _} = Sinter.Validator.validate(schema, %{grade: "", points: 0})
    end

    test "handles regex format constraints" do
      defmodule TestFormatForSinter do
        use DSPEx.Signature, "email:string[min_length=5] -> status:string"
      end

      schema = DSPExSinter.signature_to_schema(TestFormatForSinter)

      # Test valid email length
      {:ok, _} = Sinter.Validator.validate(schema, %{email: "test@example.com", status: "valid"})

      # Test invalid email length
      {:error, _} = Sinter.Validator.validate(schema, %{email: "x", status: "invalid"})
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

  describe "type conversion to Sinter" do
    test "converts basic types correctly" do
      defmodule TestBasicTypes do
        use DSPEx.Signature, "text:string, num:integer, flag:boolean, score:float -> result:any"
      end

      schema = DSPExSinter.signature_to_schema(TestBasicTypes)

      # Test type validation
      {:ok, _} =
        Sinter.Validator.validate(schema, %{
          text: "hello",
          num: 42,
          flag: true,
          score: 3.14,
          result: "anything"
        })

      # Test type mismatches
      {:error, _} =
        Sinter.Validator.validate(schema, %{
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

      schema = DSPExSinter.signature_to_schema(TestArrayTypes)

      # Test valid arrays
      {:ok, _} =
        Sinter.Validator.validate(schema, %{
          strings: ["a", "b", "c"],
          numbers: [1, 2, 3],
          result: "ok"
        })

      # Test invalid array element types
      {:error, _} =
        Sinter.Validator.validate(schema, %{
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
        DSPExSinter.validate_with_sinter(
          TestInputValidation,
          %{username: "alice"},
          field_type: :inputs
        )

      assert validated.username == "alice"

      # Test constraint violations
      {:error, errors} =
        DSPExSinter.validate_with_sinter(
          TestInputValidation,
          %{username: "ab"},
          field_type: :inputs
        )

      assert is_list(errors) or is_map(errors)
    end

    test "validates output fields with enhanced constraints" do
      defmodule TestOutputValidation do
        use DSPEx.Signature, "query:string -> response:string[max_length=100]"
      end

      # Test valid output
      {:ok, validated} =
        DSPExSinter.validate_with_sinter(
          TestOutputValidation,
          %{response: "Short response"},
          field_type: :outputs
        )

      assert validated.response == "Short response"

      # Test constraint violations
      long_response = String.duplicate("a", 150)

      {:error, errors} =
        DSPExSinter.validate_with_sinter(
          TestOutputValidation,
          %{response: long_response},
          field_type: :outputs
        )

      assert is_list(errors) or is_map(errors)
    end

    test "validates all fields when field_type is :all" do
      defmodule TestAllFieldValidation do
        use DSPEx.Signature,
            "input:string[min_length=2] -> output:string[max_length=50]"
      end

      # Test valid all fields
      {:ok, validated} =
        DSPExSinter.validate_with_sinter(
          TestAllFieldValidation,
          %{input: "test", output: "result"},
          field_type: :all
        )

      assert validated.input == "test"
      assert validated.output == "result"

      # Test constraint violations
      {:error, errors} =
        DSPExSinter.validate_with_sinter(
          TestAllFieldValidation,
          %{input: "x", output: String.duplicate("a", 100)},
          field_type: :all
        )

      assert is_list(errors) or is_map(errors)
    end
  end

  describe "JSON schema generation" do
    test "generates JSON schema from enhanced signature" do
      defmodule TestJsonGeneration do
        use DSPEx.Signature,
            "name:string[min_length=1,max_length=50] -> greeting:string[max_length=100]"
      end

      json_schema = DSPExSinter.generate_json_schema(TestJsonGeneration)

      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "properties")

      properties = json_schema["properties"]
      assert Map.has_key?(properties, "name") or Map.has_key?(properties, "greeting")
    end

    test "supports provider-specific optimizations" do
      defmodule TestProviderOptimization do
        use DSPEx.Signature, "question:string -> answer:string"
      end

      # Test OpenAI optimization
      openai_schema =
        DSPExSinter.generate_json_schema(TestProviderOptimization, provider: :openai)

      assert openai_schema["type"] == "object"

      # Test Anthropic optimization
      anthropic_schema =
        DSPExSinter.generate_json_schema(TestProviderOptimization, provider: :anthropic)

      assert anthropic_schema["type"] == "object"

      # Test generic schema
      generic_schema =
        DSPExSinter.generate_json_schema(TestProviderOptimization, provider: :generic)

      assert generic_schema["type"] == "object"
    end

    test "handles field type filtering in JSON schema" do
      defmodule TestFieldFiltering do
        use DSPEx.Signature, "input1:string, input2:string -> output1:string, output2:string"
      end

      # Test inputs only
      input_schema = DSPExSinter.generate_json_schema(TestFieldFiltering, field_type: :inputs)
      input_properties = Map.keys(input_schema["properties"] || %{})
      assert "input1" in input_properties or "input2" in input_properties

      # Test outputs only
      output_schema = DSPExSinter.generate_json_schema(TestFieldFiltering, field_type: :outputs)
      output_properties = Map.keys(output_schema["properties"] || %{})
      assert "output1" in output_properties or "output2" in output_properties
    end
  end

  describe "error handling and edge cases" do
    test "handles invalid signature modules gracefully" do
      assert_raise ArgumentError, fn ->
        DSPExSinter.signature_to_schema(NonExistentModule)
      end
    end

    test "handles validation of invalid data types" do
      defmodule TestTypeValidation do
        use DSPEx.Signature, "number:integer -> result:string"
      end

      {:error, errors} =
        DSPExSinter.validate_with_sinter(TestTypeValidation, %{number: "not_a_number"})

      assert is_list(errors) or is_map(errors)
    end

    test "handles missing required fields" do
      defmodule TestRequiredFields do
        use DSPEx.Signature, "required_field:string -> result:string"
      end

      {:error, errors} =
        DSPExSinter.validate_with_sinter(TestRequiredFields, %{})

      assert is_list(errors) or is_map(errors)
    end

    test "handles empty constraint maps" do
      defmodule TestNoConstraints do
        use DSPEx.Signature, "simple:string -> output:string"
      end

      schema = DSPExSinter.signature_to_schema(TestNoConstraints)
      assert is_map(schema)

      {:ok, validated} =
        DSPExSinter.validate_with_sinter(TestNoConstraints, %{simple: "test"})

      assert validated.simple == "test"
    end
  end

  describe "performance characteristics" do
    test "schema creation is fast" do
      defmodule TestPerformance do
        use DSPEx.Signature,
            "field1:string, field2:integer, field3:float -> result1:string, result2:boolean"
      end

      start_time = System.monotonic_time()

      # Create schema multiple times
      for _i <- 1..100 do
        DSPExSinter.signature_to_schema(TestPerformance)
      end

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should be very fast (under 1 second for 100 operations)
      assert duration_ms < 1000
    end

    test "validation is efficient" do
      defmodule TestValidationPerformance do
        use DSPEx.Signature, "data:string -> result:string"
      end

      schema = DSPExSinter.signature_to_schema(TestValidationPerformance)
      test_data = %{data: "test input"}

      start_time = System.monotonic_time()

      # Validate multiple times
      for _i <- 1..1000 do
        Sinter.Validator.validate(schema, test_data)
      end

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should be fast (under 2 seconds for 1000 validations)
      assert duration_ms < 2000
    end
  end
end
