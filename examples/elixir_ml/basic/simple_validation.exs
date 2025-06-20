#!/usr/bin/env elixir

# Example: Simple Schema Validation
#
# This example demonstrates:
# - Basic schema creation
# - Data validation
# - Error handling
# - Performance measurement
#
# Usage: elixir examples/elixir_ml/basic/simple_validation.exs

# This example should be run from the ds_ex project root:
# cd /path/to/ds_ex && elixir examples/elixir_ml/basic/simple_validation.exs

# Add the lib directory to the code path
Code.prepend_path("lib")

# Load the necessary modules in dependency order
Code.require_file("lib/elixir_ml/schema/validation_error.ex")
Code.require_file("lib/elixir_ml/schema/types.ex")
Code.require_file("lib/elixir_ml/schema/definition.ex")
Code.require_file("lib/elixir_ml/schema/behaviour.ex")
Code.require_file("lib/elixir_ml/schema/dsl.ex")
Code.require_file("lib/elixir_ml/schema/compiler.ex")
Code.require_file("lib/elixir_ml/schema/runtime.ex")
Code.require_file("lib/elixir_ml/schema.ex")
Code.require_file("lib/elixir_ml/variable.ex")
Code.require_file("lib/elixir_ml/variable/space.ex")
Code.require_file("lib/elixir_ml/variable/ml_types.ex")
Code.require_file("lib/elixir_ml/runtime.ex")
Code.require_file("lib/elixir_ml/performance.ex")

defmodule SimpleValidationExample do
  @moduledoc """
  Comprehensive example of basic ElixirML schema validation.

  This example covers the fundamental concepts of ElixirML:
  - Creating schemas with various data types
  - Validating data against schemas
  - Handling validation errors
  - Basic performance measurement
  """

  def run do
    IO.puts("\n🚀 ElixirML Simple Validation Example")
    IO.puts("=====================================")

    # Step 1: Create a basic schema
    basic_schema_example()

    # Step 2: ML-specific schema
    ml_schema_example()

    # Step 3: Error handling
    error_handling_example()

    # Step 4: Performance measurement
    performance_example()

    IO.puts("\n✅ Simple validation examples completed!")
  end

  defp basic_schema_example do
    IO.puts("\n📝 Step 1: Basic Schema Creation")
    IO.puts("--------------------------------")

    # Create a simple user profile schema
    schema = ElixirML.Runtime.create_schema([
      {:name, :string, [min_length: 1, max_length: 100]},
      {:age, :integer, [gteq: 0, lteq: 150]},
      {:email, :string, [min_length: 5]},
      {:active, :boolean, []}
    ])

    IO.puts("Schema created with 4 fields: name, age, email, active")

    # Valid data
    valid_data = %{
      name: "Alice Johnson",
      age: 30,
      email: "alice@example.com",
      active: true
    }

    case ElixirML.Runtime.validate(schema, valid_data) do
      {:ok, validated} ->
        IO.puts("✅ Valid data passed validation:")
        IO.inspect(validated, pretty: true)

      {:error, errors} ->
        IO.puts("❌ Unexpected validation error:")
        IO.inspect(errors)
    end
  end

  defp ml_schema_example do
    IO.puts("\n🧠 Step 2: ML-Specific Schema")
    IO.puts("-----------------------------")

    # Create an LLM parameter schema
    ml_schema = ElixirML.Runtime.create_schema([
      {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
      {:max_tokens, :integer, [gteq: 1, lteq: 4096]},
      {:top_p, :float, [gteq: 0.0, lteq: 1.0]},
      {:model, :string, [choices: ["gpt-4", "gpt-3.5-turbo", "claude-3"]]},
      {:stream, :boolean, []}
    ])

    IO.puts("ML schema created for LLM parameters")

    # Valid ML configuration
    ml_config = %{
      temperature: 0.7,
      max_tokens: 1000,
      top_p: 0.9,
      model: "gpt-4",
      stream: false
    }

    case ElixirML.Runtime.validate(ml_schema, ml_config) do
      {:ok, validated} ->
        IO.puts("✅ ML configuration validated:")
        IO.inspect(validated, pretty: true)

      {:error, errors} ->
        IO.puts("❌ ML validation error:")
        IO.inspect(errors)
    end

    # Export JSON schema for API documentation
    json_schema = ElixirML.Runtime.to_json_schema(ml_schema)
    IO.puts("\n📄 JSON Schema exported:")
    IO.inspect(json_schema, pretty: true, limit: :infinity)
  end

  defp error_handling_example do
    IO.puts("\n⚠️  Step 3: Error Handling")
    IO.puts("-------------------------")

    # Create a strict schema
    strict_schema = ElixirML.Runtime.create_schema([
      {:probability, :float, [gteq: 0.0, lteq: 1.0]},
      {:count, :integer, [gteq: 1, lteq: 100]},
      {:category, :string, [choices: ["A", "B", "C"]]}
    ])

    # Invalid data examples
    invalid_examples = [
      {%{probability: 1.5, count: 50, category: "A"}, "probability out of range"},
      {%{probability: 0.8, count: 0, category: "A"}, "count below minimum"},
      {%{probability: 0.8, count: 50, category: "D"}, "invalid category choice"},
      {%{probability: "invalid", count: 50, category: "A"}, "wrong data type"},
      {%{count: 50, category: "A"}, "missing required field"}
    ]

    Enum.each(invalid_examples, fn {data, description} ->
      case ElixirML.Runtime.validate(strict_schema, data) do
        {:ok, _} ->
          IO.puts("⚠️  Expected error for: #{description}")

        {:error, error} ->
          IO.puts("✅ Caught expected error (#{description}):")
          IO.puts("   #{format_validation_error(error)}")
      end
    end)
  end

  defp performance_example do
    IO.puts("\n⚡ Step 4: Performance Measurement")
    IO.puts("----------------------------------")

    # Create a performance test schema
    perf_schema = ElixirML.Runtime.create_schema([
      {:temperature, :float, [gteq: 0.0, lteq: 2.0]},
      {:max_tokens, :integer, [gteq: 1, lteq: 4096]},
      {:quality_score, :float, [gteq: 0.0, lteq: 10.0]}
    ])

    # Generate test data
    test_data = Enum.map(1..1000, fn _i ->
      %{
        temperature: :rand.uniform() * 2.0,
        max_tokens: :rand.uniform(4096),
        quality_score: :rand.uniform() * 10.0
      }
    end)

    IO.puts("Generated 1,000 test records")

    # Measure validation performance
    {time_microseconds, results} = :timer.tc(fn ->
      Enum.map(test_data, fn data ->
        ElixirML.Runtime.validate(perf_schema, data)
      end)
    end)

    successful_validations = Enum.count(results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)

    validations_per_second = (1_000_000 * length(test_data)) / time_microseconds
    avg_time_per_validation = time_microseconds / length(test_data)

    IO.puts("📊 Performance Results:")
    IO.puts("   Total validations: #{length(test_data)}")
    IO.puts("   Successful: #{successful_validations}")
    IO.puts("   Total time: #{Float.round(time_microseconds / 1000, 2)} ms")
    IO.puts("   Average per validation: #{Float.round(avg_time_per_validation, 2)} μs")
    IO.puts("   Validations per second: #{Float.round(validations_per_second, 0)}")

    # Performance assessment
    cond do
      validations_per_second > 50_000 ->
        IO.puts("🚀 Excellent performance!")

      validations_per_second > 10_000 ->
        IO.puts("✅ Good performance")

      validations_per_second > 1_000 ->
        IO.puts("⚠️  Acceptable performance")

      true ->
        IO.puts("❌ Performance needs improvement")
    end
  end

  defp format_validation_error(error) do
    case error do
      %ElixirML.Schema.ValidationError{} = err ->
        "#{err.field}: #{err.message}"

      errors when is_list(errors) ->
        errors
        |> Enum.map(&format_validation_error/1)
        |> Enum.join(", ")

      other ->
        inspect(other)
    end
  end
end

# Run the example
SimpleValidationExample.run()
