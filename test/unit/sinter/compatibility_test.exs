defmodule DSPEx.Sinter.CompatibilityTest do
  use ExUnit.Case, async: true

  alias DSPEx.Sinter, as: DSPExSinter
  alias DSPEx.Signature.Sinter, as: SignatureSinter

  @moduletag :phase_1
  @moduletag :sinter_test
  @moduletag :compatibility_test

  describe "Elixact function compatibility" do
    test "signature_to_schema provides equivalent functionality" do
      defmodule TestSignatureForCompatibility do
        use DSPEx.Signature, "name:string[min_length=2] -> greeting:string[max_length=50]"
      end

      # Test that we can generate a schema
      schema = SignatureSinter.signature_to_schema(TestSignatureForCompatibility)
      assert is_map(schema)

      # Test that validation works like Elixact
      {:ok, validated} =
        Elixir.Sinter.Validator.validate(schema, %{name: "Alice", greeting: "Hello!"})

      assert validated.name == "Alice"
      assert validated.greeting == "Hello!"

      # Test constraint violations
      # min_length violation
      {:error, _errors} =
        Elixir.Sinter.Validator.validate(schema, %{name: "X", greeting: "Hello!"})

      # max_length violation
      {:error, _errors} =
        Elixir.Sinter.Validator.validate(schema, %{
          name: "Alice",
          greeting: String.duplicate("a", 100)
        })
    end

    test "validate_with_sinter equivalent to validate_with_elixact" do
      defmodule TestValidationCompatibility do
        use DSPEx.Signature, "input:string[min_length=1] -> output:string"
      end

      # Test input validation
      {:ok, validated} =
        SignatureSinter.validate_with_sinter(
          TestValidationCompatibility,
          %{input: "test"},
          field_type: :inputs
        )

      assert validated.input == "test"

      # Test output validation
      {:ok, validated} =
        SignatureSinter.validate_with_sinter(
          TestValidationCompatibility,
          %{output: "result"},
          field_type: :outputs
        )

      assert validated.output == "result"

      # Test validation failures
      {:error, _errors} =
        SignatureSinter.validate_with_sinter(
          TestValidationCompatibility,
          %{input: ""},
          field_type: :inputs
        )
    end

    test "generate_json_schema equivalent to to_json_schema" do
      defmodule TestJsonCompatibility do
        use DSPEx.Signature, "question:string -> answer:string"
      end

      json_schema = SignatureSinter.generate_json_schema(TestJsonCompatibility)

      # Verify basic JSON Schema structure (same as Elixact)
      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "properties")

      # Test field filtering (same behavior as Elixact)
      input_schema =
        SignatureSinter.generate_json_schema(TestJsonCompatibility, field_type: :inputs)

      output_schema =
        SignatureSinter.generate_json_schema(TestJsonCompatibility, field_type: :outputs)

      assert input_schema["type"] == "object"
      assert output_schema["type"] == "object"
    end

    test "create_dynamic_schema equivalent functionality" do
      signature_definition = %{
        input_fields: [:name, :age],
        output_fields: [:greeting],
        field_types: %{name: :string, age: :integer, greeting: :string},
        constraints: %{
          name: %{min_length: 1},
          age: %{gteq: 0, lteq: 120}
        }
      }

      schema = DSPExSinter.create_dynamic_schema(signature_definition, "TestDynamicSchema")
      assert is_map(schema)

      # Test validation with the dynamic schema
      {:ok, validated} =
        Elixir.Sinter.Validator.validate(schema, %{
          name: "Alice",
          age: 30,
          greeting: "Hello Alice!"
        })

      assert validated.name == "Alice"
      assert validated.age == 30
      assert validated.greeting == "Hello Alice!"

      # Test constraint violations
      {:error, _errors} =
        Elixir.Sinter.Validator.validate(schema, %{
          # min_length violation
          name: "",
          age: 30,
          greeting: "Hello!"
        })

      {:error, _errors} =
        Elixir.Sinter.Validator.validate(schema, %{
          name: "Alice",
          # lteq violation
          age: 150,
          greeting: "Hello!"
        })
    end

    test "constraint mapping compatibility" do
      # Test all constraint types that were supported in Elixact
      dspex_constraints = %{
        min_length: 5,
        max_length: 50,
        min_items: 1,
        max_items: 10,
        gteq: 0,
        lteq: 100,
        gt: -1,
        lt: 101,
        format: ~r/^[A-Za-z]+$/,
        choices: ["option1", "option2", "option3"],
        required: true,
        default: "default_value"
      }

      sinter_constraints = DSPExSinter.map_constraints_to_sinter(dspex_constraints)

      # Verify all constraints are mapped
      assert Keyword.get(sinter_constraints, :min_length) == 5
      assert Keyword.get(sinter_constraints, :max_length) == 50
      assert Keyword.get(sinter_constraints, :min_items) == 1
      assert Keyword.get(sinter_constraints, :max_items) == 10
      assert Keyword.get(sinter_constraints, :gteq) == 0
      assert Keyword.get(sinter_constraints, :lteq) == 100
      assert Keyword.get(sinter_constraints, :gt) == -1
      assert Keyword.get(sinter_constraints, :lt) == 101
      assert Keyword.get(sinter_constraints, :format) == ~r/^[A-Za-z]+$/
      assert Keyword.get(sinter_constraints, :choices) == ["option1", "option2", "option3"]
      assert Keyword.get(sinter_constraints, :required) == true
      assert Keyword.get(sinter_constraints, :default) == "default_value"
    end

    test "error format compatibility" do
      # Test that Sinter errors are converted to DSPEx-compatible format
      sinter_errors = [
        %{path: [:name], message: "is required", code: :required},
        %{path: [:age], message: "must be greater than or equal to 0", code: :gteq}
      ]

      dspex_errors = DSPExSinter.convert_errors_to_dspex(sinter_errors)

      assert length(dspex_errors) == 2
      [name_error, age_error] = dspex_errors

      assert name_error.path == [:name]
      assert name_error.message == "is required"
      assert name_error.type == :sinter_validation_error

      assert age_error.path == [:age]
      assert age_error.message == "must be greater than or equal to 0"
      assert age_error.type == :sinter_validation_error
    end

    test "schema extraction compatibility" do
      # Create a simple Sinter schema
      schema =
        Elixir.Sinter.Schema.define(
          [
            {:name, :string, [required: true, min_length: 1, max_length: 50]},
            {:age, :integer, [required: true, gteq: 0, lteq: 120]},
            {:email, :string, [required: false, format: ~r/.+@.+/]}
          ],
          title: "Test Schema"
        )

      # Extract schema info (equivalent to Elixact's introspection)
      schema_info = DSPExSinter.extract_schema_info(schema)

      assert Map.has_key?(schema_info, :fields)
      assert Map.has_key?(schema_info, :constraints)
      assert Map.has_key?(schema_info, :descriptions)
      assert Map.has_key?(schema_info, :required)

      # Verify field types are extracted correctly
      assert schema_info.fields[:name] == :string
      assert schema_info.fields[:age] == :integer
      assert schema_info.fields[:email] == :string

      # Verify constraints are extracted
      assert schema_info.constraints[:name][:min_length] == 1
      assert schema_info.constraints[:name][:max_length] == 50
      assert schema_info.constraints[:age][:gteq] == 0
      assert schema_info.constraints[:age][:lteq] == 120
    end
  end

  describe "performance parity with Elixact" do
    test "schema creation performance is competitive" do
      defmodule TestPerformanceSchema do
        use DSPEx.Signature,
            "field1:string, field2:integer, field3:float, field4:boolean -> result1:string, result2:array(string)"
      end

      # Measure Sinter schema creation
      start_time = System.monotonic_time()

      for _i <- 1..100 do
        SignatureSinter.signature_to_schema(TestPerformanceSchema)
      end

      sinter_duration = System.monotonic_time() - start_time
      sinter_ms = System.convert_time_unit(sinter_duration, :native, :millisecond)

      # Should be very fast (much faster than Elixact due to no module compilation)
      # Should be under 200ms for 100 operations
      assert sinter_ms < 200
    end

    test "validation performance is competitive" do
      defmodule TestValidationPerformance do
        use DSPEx.Signature, "name:string, age:integer -> greeting:string"
      end

      schema = SignatureSinter.signature_to_schema(TestValidationPerformance)
      test_data = %{name: "Alice", age: 30, greeting: "Hello Alice!"}

      # Measure validation performance
      start_time = System.monotonic_time()

      for _i <- 1..1000 do
        Elixir.Sinter.Validator.validate(schema, test_data)
      end

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should be fast (faster than Elixact due to no module dispatch)
      # Should be under 1 second for 1000 validations
      assert duration_ms < 1000
    end

    test "JSON schema generation performance is competitive" do
      defmodule TestJsonPerformance do
        use DSPEx.Signature,
            "input1:string[min_length=1], input2:integer[gteq=0] -> output1:string, output2:float"
      end

      # Measure JSON schema generation performance
      start_time = System.monotonic_time()

      for _i <- 1..100 do
        SignatureSinter.generate_json_schema(TestJsonPerformance)
      end

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should be fast (with provider optimizations built-in)
      # Should be under 500ms for 100 generations
      assert duration_ms < 500
    end
  end

  describe "edge case compatibility" do
    test "handles empty signatures like Elixact" do
      defmodule TestEmptySignature do
        use DSPEx.Signature, "input -> output"
      end

      # Should not crash, should generate empty schema
      schema = SignatureSinter.signature_to_schema(TestEmptySignature)
      assert is_map(schema)

      # Should validate minimal data
      {:ok, validated} =
        Elixir.Sinter.Validator.validate(schema, %{input: "test", output: "result"})

      assert validated.input == "test"
      assert validated.output == "result"
    end

    test "handles complex nested types like Elixact" do
      defmodule TestNestedTypes do
        use DSPEx.Signature, "data:map -> results:array(map)"
      end

      schema = SignatureSinter.signature_to_schema(TestNestedTypes)

      # Test with complex nested data
      test_data = %{
        data: %{key1: "value1", key2: %{nested: "value"}},
        results: [%{result1: "value1"}, %{result2: "value2"}]
      }

      {:ok, validated} = Elixir.Sinter.Validator.validate(schema, test_data)
      assert validated.data == test_data.data
      assert validated.results == test_data.results
    end

    test "handles invalid module references gracefully" do
      # Should raise appropriate error like Elixact
      assert_raise ArgumentError, fn ->
        SignatureSinter.signature_to_schema(NonExistentModule)
      end
    end

    test "handles malformed data gracefully" do
      defmodule TestMalformedData do
        use DSPEx.Signature, "name:string -> greeting:string"
      end

      schema = SignatureSinter.signature_to_schema(TestMalformedData)

      # Test various malformed inputs
      {:error, _} = Elixir.Sinter.Validator.validate(schema, "not a map")
      {:error, _} = Elixir.Sinter.Validator.validate(schema, nil)
      {:error, _} = Elixir.Sinter.Validator.validate(schema, [])
      {:error, _} = Elixir.Sinter.Validator.validate(schema, %{name: nil, greeting: "hello"})
    end
  end

  describe "feature completeness vs Elixact" do
    test "supports all Elixact constraint types" do
      # Verify all constraint types from Elixact are supported
      all_constraints = %{
        # String constraints
        min_length: 1,
        max_length: 100,
        format: ~r/[a-z]+/,
        choices: ["a", "b", "c"],

        # Numeric constraints
        gteq: 0,
        lteq: 100,
        gt: -1,
        lt: 101,

        # Array constraints
        min_items: 1,
        max_items: 10,

        # General constraints
        required: true,
        optional: false,
        default: "default_value"
      }

      sinter_constraints = DSPExSinter.map_constraints_to_sinter(all_constraints)

      # All constraints should be mapped (no skipped constraints)
      assert length(sinter_constraints) == map_size(all_constraints)
    end

    test "supports all Elixact field types" do
      defmodule TestAllTypes do
        use DSPEx.Signature,
            "str:string, int:integer, float:float, bool:boolean, arr:array(string), obj:map -> result:any"
      end

      schema = SignatureSinter.signature_to_schema(TestAllTypes)

      # Test all types work
      test_data = %{
        str: "hello",
        int: 42,
        float: 3.14,
        bool: true,
        arr: ["a", "b", "c"],
        obj: %{key: "value"},
        result: "anything"
      }

      {:ok, validated} = Elixir.Sinter.Validator.validate(schema, test_data)
      assert validated == test_data
    end

    test "supports signature metadata like Elixact" do
      defmodule TestMetadata do
        @moduledoc "Test signature with metadata"
        use DSPEx.Signature, "input:string -> output:string"
      end

      _schema = SignatureSinter.signature_to_schema(TestMetadata)
      json_schema = SignatureSinter.generate_json_schema(TestMetadata)

      # Should include title and description
      assert json_schema["title"] == "TestMetadata"
      assert is_binary(json_schema["description"])
    end

    test "provides same API surface as Elixact module" do
      # Verify all public functions exist and work

      # Core signature conversion
      defmodule TestApiSurface do
        use DSPEx.Signature, "test:string -> result:string"
      end

      # schema_to_signature equivalent
      schema_def = %{
        fields: %{
          test: %{type: :string, required: true},
          result: %{type: :string, required: false}
        }
      }

      signature_module = DSPExSinter.schema_to_signature(schema_def)
      assert is_atom(signature_module)

      # generate_json_schema equivalent
      json_schema = DSPExSinter.generate_json_schema(TestApiSurface)
      assert json_schema["type"] == "object"

      # map_constraints_to_sinter equivalent
      constraints = DSPExSinter.map_constraints_to_sinter(%{min_length: 5})
      assert Keyword.get(constraints, :min_length) == 5

      # convert_errors_to_dspex equivalent
      errors = DSPExSinter.convert_errors_to_dspex([%{field: :test, message: "error"}])
      assert is_list(errors)

      # create_dynamic_schema equivalent
      dynamic_schema =
        DSPExSinter.create_dynamic_schema(
          %{
            input_fields: [:input],
            output_fields: [:output],
            field_types: %{input: :string, output: :string},
            constraints: %{}
          },
          "DynamicTest"
        )

      assert is_map(dynamic_schema)

      # extract_schema_info equivalent
      schema_info = DSPExSinter.extract_schema_info(dynamic_schema)
      assert is_map(schema_info)
    end
  end
end
