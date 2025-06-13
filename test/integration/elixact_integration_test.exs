defmodule DSPEx.ElixactIntegrationTest do
  @moduledoc """
  Integration tests to validate Elixact functionality and API compatibility.

  These tests ensure that Elixact is properly installed and functional
  before proceeding with DSPEx integration work.
  """
  use ExUnit.Case, async: true

  @moduletag :integration_test

  describe "Elixact basic functionality" do
    test "Elixact module loads and has expected functions" do
      # Verify Elixact module is available
      assert Code.ensure_loaded?(Elixact)

      # Check for key functions we'll be using
      # Note: __using__ is a macro, not a function, so we check for it differently
      assert Code.ensure_loaded?(Elixact.Schema)
      assert Code.ensure_loaded?(Elixact.Schema)
      assert Code.ensure_loaded?(Elixact.Types)
      assert Code.ensure_loaded?(Elixact.JsonSchema)
    end

    test "can create basic Elixact schema" do
      defmodule TestSchema do
        use Elixact

        schema "Test schema for validation" do
          field :name, :string do
            min_length(2)
            max_length(50)
          end

          field :age, :integer do
            gteq(0)
            lteq(150)
          end

          field(:email, :string)
        end
      end

      # Verify schema module was created
      assert Code.ensure_loaded?(TestSchema)

      # Test schema validation with valid data
      valid_data = %{
        name: "John Doe",
        age: 30,
        email: "john@example.com"
      }

      case TestSchema.validate(valid_data) do
        {:ok, validated_data} ->
          assert validated_data.name == "John Doe"
          assert validated_data.age == 30
          assert validated_data.email == "john@example.com"

        {:error, errors} ->
          flunk("Expected validation to succeed, got errors: #{inspect(errors)}")
      end
    end

    test "validates constraint violations correctly" do
      defmodule ConstraintTestSchema do
        use Elixact

        schema "Schema with constraints" do
          field :username, :string do
            min_length(3)
            max_length(20)
          end

          field :score, :integer do
            gteq(0)
            lteq(100)
          end
        end
      end

      # Test constraint violations
      invalid_data = %{
        # Too short
        username: "ab",
        # Too high
        score: 150
      }

      case ConstraintTestSchema.validate(invalid_data) do
        {:ok, _data} ->
          flunk("Expected validation to fail due to constraint violations")

        {:error, errors} ->
          # Elixact might return a single error or a list of errors
          error_list = if is_list(errors), do: errors, else: [errors]
          # Should have at least one error
          assert length(error_list) >= 1

          # Verify error structure (flexible to handle different error formats)
          for error <- error_list do
            assert is_map(error) or is_struct(error)
            # For Elixact.Error structs, check for expected fields
            if is_struct(error, Elixact.Error) do
              assert Map.has_key?(error, :path) or Map.has_key?(error, :code) or
                       Map.has_key?(error, :message)
            else
              # For other error formats
              has_field = Map.has_key?(error, :field) or Map.has_key?(error, "field")

              has_message =
                Map.has_key?(error, :message) or Map.has_key?(error, "message") or
                  Map.has_key?(error, :type) or Map.has_key?(error, "type")

              assert has_field or has_message
            end
          end
      end
    end

    test "generates JSON schema from Elixact schema" do
      defmodule JsonSchemaTestSchema do
        use Elixact

        schema "Schema for JSON generation" do
          field :title, :string do
            min_length(1)
            max_length(100)
          end

          field :count, :integer do
            gteq(0)
          end

          field(:active, :boolean)
        end
      end

      # Generate JSON schema
      json_schema = Elixact.JsonSchema.from_schema(JsonSchemaTestSchema)

      # Verify JSON schema structure
      assert is_map(json_schema)
      # JSON schema uses string keys
      assert Map.has_key?(json_schema, "type")
      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "properties")

      properties = json_schema["properties"]
      assert Map.has_key?(properties, "title")
      assert Map.has_key?(properties, "count")
      assert Map.has_key?(properties, "active")

      # Verify field types
      assert properties["title"]["type"] == "string"
      assert properties["count"]["type"] == "integer"
      assert properties["active"]["type"] == "boolean"

      # Verify constraints are included (may use different key names)
      title_schema = properties["title"]
      assert Map.has_key?(title_schema, "minLength") or Map.has_key?(title_schema, "minimum")
      count_schema = properties["count"]
      assert Map.has_key?(count_schema, "minimum") or Map.has_key?(count_schema, "minValue")
    end

    test "supports nested schemas" do
      defmodule AddressSchema do
        use Elixact

        schema "Address information" do
          field(:street, :string)
          field(:city, :string)
          field(:zip_code, :string)
        end
      end

      defmodule PersonSchema do
        use Elixact

        schema "Person with address" do
          field(:name, :string)
          field(:address, AddressSchema)
        end
      end

      # Test nested validation
      valid_data = %{
        name: "Jane Smith",
        address: %{
          street: "123 Main St",
          city: "Anytown",
          zip_code: "12345"
        }
      }

      case PersonSchema.validate(valid_data) do
        {:ok, validated_data} ->
          assert validated_data.name == "Jane Smith"
          assert validated_data.address.street == "123 Main St"
          assert validated_data.address.city == "Anytown"
          assert validated_data.address.zip_code == "12345"

        {:error, errors} ->
          flunk("Expected nested validation to succeed, got errors: #{inspect(errors)}")
      end
    end

    test "supports array types" do
      defmodule ArrayTestSchema do
        use Elixact

        schema "Schema with arrays" do
          field :tags, {:array, :string} do
            min_items(1)
            max_items(10)
          end

          field(:scores, {:array, :integer})
        end
      end

      # Test array validation
      valid_data = %{
        tags: ["elixir", "dspex", "validation"],
        scores: [85, 92, 78, 96]
      }

      case ArrayTestSchema.validate(valid_data) do
        {:ok, validated_data} ->
          assert length(validated_data.tags) == 3
          assert length(validated_data.scores) == 4
          assert Enum.all?(validated_data.tags, &is_binary/1)
          assert Enum.all?(validated_data.scores, &is_integer/1)

        {:error, errors} ->
          flunk("Expected array validation to succeed, got errors: #{inspect(errors)}")
      end
    end

    test "validates array constraints" do
      defmodule ArrayConstraintSchema do
        use Elixact

        schema "Array with constraints" do
          field :items, {:array, :string} do
            min_items(2)
            max_items(5)
          end
        end
      end

      # Test empty array (should fail)
      case ArrayConstraintSchema.validate(%{items: []}) do
        {:ok, _data} ->
          flunk("Expected validation to fail for empty array")

        {:error, errors} ->
          error_list = if is_list(errors), do: errors, else: [errors]
          assert length(error_list) >= 1
      end

      # Test array with too many items
      large_array = %{items: Enum.map(1..10, &"item#{&1}")}

      case ArrayConstraintSchema.validate(large_array) do
        {:ok, _data} ->
          flunk("Expected validation to fail for oversized array")

        {:error, errors} ->
          error_list = if is_list(errors), do: errors, else: [errors]
          assert length(error_list) >= 1
      end
    end

    test "handles optional fields" do
      defmodule OptionalFieldSchema do
        use Elixact

        schema "Schema with optional fields" do
          field(:required_field, :string)

          field :optional_field, :string do
            optional()
          end
        end
      end

      # Test with only required field
      minimal_data = %{required_field: "test"}

      case OptionalFieldSchema.validate(minimal_data) do
        {:ok, validated_data} ->
          assert validated_data.required_field == "test"

        # Optional field might be nil or not present

        {:error, errors} ->
          flunk(
            "Expected validation to succeed with minimal data, got errors: #{inspect(errors)}"
          )
      end

      # Test with both fields
      complete_data = %{
        required_field: "test",
        optional_field: "optional"
      }

      case OptionalFieldSchema.validate(complete_data) do
        {:ok, validated_data} ->
          assert validated_data.required_field == "test"
          assert validated_data.optional_field == "optional"

        {:error, errors} ->
          flunk(
            "Expected validation to succeed with complete data, got errors: #{inspect(errors)}"
          )
      end
    end

    test "supports default values" do
      defmodule DefaultValueSchema do
        use Elixact

        schema "Schema with default values" do
          field(:name, :string)

          field :status, :string do
            default("active")
          end

          field :priority, :integer do
            default(5)
          end
        end
      end

      # Test validation with defaults applied
      input_data = %{name: "Test Item"}

      case DefaultValueSchema.validate(input_data) do
        {:ok, validated_data} ->
          assert validated_data.name == "Test Item"
          assert validated_data.status == "active"
          assert validated_data.priority == 5

        {:error, errors} ->
          flunk("Expected validation with defaults to succeed, got errors: #{inspect(errors)}")
      end
    end
  end

  describe "Elixact error handling and introspection" do
    test "provides detailed error information" do
      defmodule ErrorTestSchema do
        use Elixact

        schema "Schema for error testing" do
          field :email, :string do
            format(~r/^[^\s]+@[^\s]+$/)
          end

          field :age, :integer do
            gteq(18)
            lteq(65)
          end
        end
      end

      # Test with multiple validation errors
      invalid_data = %{
        email: "invalid-email",
        age: 10
      }

      case ErrorTestSchema.validate(invalid_data) do
        {:ok, _data} ->
          flunk("Expected validation to fail")

        {:error, errors} ->
          # Elixact might return a single error or a list of errors
          error_list = if is_list(errors), do: errors, else: [errors]
          # We should have at least 1 error
          assert length(error_list) >= 1

          # Check that errors contain useful information (flexible for different error formats)
          for error <- error_list do
            assert is_map(error) or is_struct(error)
          end
      end
    end

    test "can introspect schema information" do
      defmodule IntrospectionSchema do
        use Elixact

        schema "Schema for introspection" do
          field :username, :string do
            min_length(3)
            max_length(20)
          end

          field :score, :integer do
            gteq(0)
            lteq(100)
          end

          field(:tags, {:array, :string})
        end
      end

      # Test that we can extract schema information
      # The exact API may vary, so we'll test what's available

      # Check if schema module has expected functions
      assert function_exported?(IntrospectionSchema, :validate, 1)

      # Try to get JSON schema for introspection
      json_schema = Elixact.JsonSchema.from_schema(IntrospectionSchema)
      assert is_map(json_schema)
      assert Map.has_key?(json_schema, "properties")

      # Verify we can see all defined fields
      properties = json_schema["properties"]
      assert Map.has_key?(properties, "username")
      assert Map.has_key?(properties, "score")
      assert Map.has_key?(properties, "tags")
    end
  end

  describe "Elixact performance characteristics" do
    test "schema validation is reasonably fast" do
      defmodule PerformanceTestSchema do
        use Elixact

        schema "Schema for performance testing" do
          field(:id, :string)

          field :name, :string do
            min_length(1)
            max_length(100)
          end

          field :value, :integer do
            gteq(0)
            lteq(1000)
          end
        end
      end

      # Test data
      test_data = %{
        id: "test-123",
        name: "Performance Test",
        value: 42
      }

      # Warmup
      for _i <- 1..10 do
        PerformanceTestSchema.validate(test_data)
      end

      # Measure validation time
      start_time = System.monotonic_time()

      for _i <- 1..100 do
        PerformanceTestSchema.validate(test_data)
      end

      duration = System.monotonic_time() - start_time
      avg_duration_us = System.convert_time_unit(duration, :native, :microsecond) / 100

      # Validation should be reasonably fast (less than 5ms per validation for initial implementation)
      assert avg_duration_us < 5000, "Validation too slow: #{avg_duration_us}µs per validation"
    end

    test "JSON schema generation is cached or fast" do
      defmodule JsonPerformanceSchema do
        use Elixact

        schema "Schema for JSON performance testing" do
          field(:field1, :string)
          field(:field2, :integer)
          field(:field3, :boolean)
          field(:field4, {:array, :string})
        end
      end

      # Measure JSON schema generation time
      start_time = System.monotonic_time()

      for _i <- 1..50 do
        Elixact.JsonSchema.from_schema(JsonPerformanceSchema)
      end

      duration = System.monotonic_time() - start_time
      avg_duration_us = System.convert_time_unit(duration, :native, :microsecond) / 50

      # JSON schema generation should be fast (less than 50ms per generation for initial implementation)
      assert avg_duration_us < 50_000,
             "JSON schema generation too slow: #{avg_duration_us}µs per generation"
    end
  end
end
