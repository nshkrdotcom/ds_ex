# Phase 1: Schema Engine Testing Framework
*Comprehensive Testing Strategy for ElixirML/DSPEx Schema Engine*

## Executive Summary

The Schema Engine Testing Framework provides comprehensive validation of the schema system through unit tests, integration tests, performance benchmarks, and property-based testing. This framework ensures reliability, performance, and correctness of the schema validation and transformation systems.

## Testing Architecture

### Testing Framework Overview

```
Schema Engine Testing Architecture
├── Unit Testing
│   ├── Schema Definition Tests
│   ├── Validation Function Tests
│   ├── Transformation Logic Tests
│   └── Type System Tests
├── Integration Testing
│   ├── Variable System Integration
│   ├── Resource Framework Integration
│   ├── Process Orchestrator Integration
│   └── External System Integration
├── Performance Testing
│   ├── Validation Performance Benchmarks
│   ├── Transformation Performance Tests
│   ├── Memory Usage Analysis
│   └── Concurrent Access Tests
├── Property-Based Testing
│   ├── Schema Invariant Testing
│   ├── Validation Property Tests
│   ├── Transformation Property Tests
│   └── Roundtrip Property Tests
└── End-to-End Testing
    ├── Complete Workflow Tests
    ├── Error Handling Tests
    ├── Edge Case Coverage
    └── Real-World Scenario Tests
```

## Unit Testing Framework

### 1. Schema Definition Tests

```elixir
defmodule ElixirML.Schema.Test.DefinitionTest do
  use ExUnit.Case, async: true
  
  alias ElixirML.Schema.TestHelpers
  
  describe "schema definition" do
    test "creates valid schema with basic fields" do
      defmodule TestSchema do
        use ElixirML.Schema
        
        field :name, :string, required: true
        field :age, :integer, constraints: [min: 0, max: 150]
        field :email, :string, format: :email
      end
      
      assert TestSchema.__schema__(:fields) == [
        {:name, :string, [required: true]},
        {:age, :integer, [constraints: [min: 0, max: 150]]},
        {:email, :string, [format: :email]}
      ]
    end
    
    test "validates field constraints at compile time" do
      assert_raise CompileError, ~r/invalid constraint/, fn ->
        defmodule InvalidSchema do
          use ElixirML.Schema
          
          field :age, :integer, constraints: [min: 100, max: 50]
        end
      end
    end
    
    test "supports ML-specific types" do
      defmodule MLSchema do
        use ElixirML.Schema
        
        field :embedding, :embedding, dimensions: 768
        field :confidence, :probability
        field :tokens, :token_list
      end
      
      fields = MLSchema.__schema__(:fields)
      assert {:embedding, :embedding, [dimensions: 768]} in fields
      assert {:confidence, :probability, []} in fields
      assert {:tokens, :token_list, []} in fields
    end
  end
  
  describe "validation definitions" do
    test "creates custom validation functions" do
      defmodule ValidationSchema do
        use ElixirML.Schema
        
        field :password, :string
        field :password_confirmation, :string
        
        validation :passwords_match do
          field(:password) == field(:password_confirmation)
        end
      end
      
      validations = ValidationSchema.__schema__(:validations)
      assert {:passwords_match, _} = List.first(validations)
    end
    
    test "validates complex business rules" do
      defmodule BusinessRuleSchema do
        use ElixirML.Schema
        
        field :start_date, :date
        field :end_date, :date
        field :status, :atom, constraints: [in: [:active, :inactive, :pending]]
        
        validation :date_range_valid do
          Date.compare(field(:start_date), field(:end_date)) in [:lt, :eq]
        end
        
        validation :status_date_consistency do
          case field(:status) do
            :active -> Date.compare(field(:start_date), Date.utc_today()) != :gt
            :pending -> Date.compare(field(:start_date), Date.utc_today()) == :gt
            :inactive -> true
          end
        end
      end
      
      valid_data = %{
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-12-31],
        status: :active
      }
      
      assert {:ok, _} = BusinessRuleSchema.validate(valid_data)
      
      invalid_data = %{
        start_date: ~D[2024-12-31],
        end_date: ~D[2024-01-01],
        status: :active
      }
      
      assert {:error, _} = BusinessRuleSchema.validate(invalid_data)
    end
  end
  
  describe "transformation definitions" do
    test "creates data transformation functions" do
      defmodule TransformSchema do
        use ElixirML.Schema
        
        field :name, :string
        field :email, :string
        
        transform :normalize_data do
          data = get_data()
          %{data |
            name: String.trim(data.name) |> String.downcase(),
            email: String.trim(data.email) |> String.downcase()
          }
        end
      end
      
      input = %{name: "  JOHN DOE  ", email: "  JOHN@EXAMPLE.COM  "}
      expected = %{name: "john doe", email: "john@example.com"}
      
      assert {:ok, ^expected} = TransformSchema.transform(input)
    end
    
    test "chains multiple transformations" do
      defmodule ChainedTransformSchema do
        use ElixirML.Schema
        
        field :text, :string
        field :word_count, :integer
        
        transform :normalize_text do
          update_field(:text, &String.trim/1)
        end
        
        transform :calculate_word_count do
          text = field(:text)
          word_count = text |> String.split() |> length()
          set_field(:word_count, word_count)
        end
      end
      
      input = %{text: "  hello world  "}
      expected = %{text: "hello world", word_count: 2}
      
      assert {:ok, ^expected} = ChainedTransformSchema.transform(input)
    end
  end
end
```

### 2. Type System Tests

```elixir
defmodule ElixirML.Schema.Test.TypeSystemTest do
  use ExUnit.Case, async: true
  
  alias ElixirML.Schema.Types
  
  describe "basic types" do
    test "validates string type" do
      assert {:ok, "hello"} = Types.validate_type("hello", :string)
      assert {:error, _} = Types.validate_type(123, :string)
    end
    
    test "validates integer type with constraints" do
      constraints = [min: 0, max: 100]
      
      assert {:ok, 50} = Types.validate_type(50, :integer, constraints)
      assert {:error, _} = Types.validate_type(-1, :integer, constraints)
      assert {:error, _} = Types.validate_type(101, :integer, constraints)
    end
    
    test "validates float type with precision" do
      constraints = [precision: 0.01]
      
      assert {:ok, 1.23} = Types.validate_type(1.23, :float, constraints)
      assert {:ok, 1.23} = Types.validate_type(1.234, :float, constraints)  # Rounded
    end
  end
  
  describe "ML-specific types" do
    test "validates embedding type" do
      valid_embedding = [0.1, 0.2, 0.3, 0.4]
      invalid_embedding = ["a", "b", "c"]
      
      assert {:ok, ^valid_embedding} = Types.validate_type(valid_embedding, :embedding)
      assert {:error, _} = Types.validate_type(invalid_embedding, :embedding)
    end
    
    test "validates probability type" do
      assert {:ok, 0.5} = Types.validate_type(0.5, :probability)
      assert {:ok, 0.0} = Types.validate_type(0.0, :probability)
      assert {:ok, 1.0} = Types.validate_type(1.0, :probability)
      
      assert {:error, _} = Types.validate_type(-0.1, :probability)
      assert {:error, _} = Types.validate_type(1.1, :probability)
    end
    
    test "validates confidence_score type" do
      assert {:ok, 0.95} = Types.validate_type(0.95, :confidence_score)
      assert {:error, _} = Types.validate_type("high", :confidence_score)
    end
    
    test "validates token_list type" do
      valid_tokens = ["hello", "world", "!"]
      invalid_tokens = [123, 456]
      
      assert {:ok, ^valid_tokens} = Types.validate_type(valid_tokens, :token_list)
      assert {:error, _} = Types.validate_type(invalid_tokens, :token_list)
    end
  end
  
  describe "composite types" do
    test "validates union types" do
      union_type = {:union, [:string, :integer]}
      
      assert {:ok, "hello"} = Types.validate_type("hello", union_type)
      assert {:ok, 123} = Types.validate_type(123, union_type)
      assert {:error, _} = Types.validate_type(12.34, union_type)
    end
    
    test "validates array types" do
      array_type = {:array, :string}
      
      assert {:ok, ["a", "b", "c"]} = Types.validate_type(["a", "b", "c"], array_type)
      assert {:error, _} = Types.validate_type([1, 2, 3], array_type)
    end
    
    test "validates map types with schema" do
      map_schema = %{
        name: :string,
        age: :integer
      }
      
      valid_map = %{name: "John", age: 30}
      invalid_map = %{name: "John", age: "thirty"}
      
      assert {:ok, ^valid_map} = Types.validate_type(valid_map, {:map, map_schema})
      assert {:error, _} = Types.validate_type(invalid_map, {:map, map_schema})
    end
  end
end
```

## Integration Testing

### 1. Variable System Integration Tests

```elixir
defmodule ElixirML.Schema.Test.VariableIntegrationTest do
  use ExUnit.Case, async: false
  
  alias ElixirML.Schema.Variable.Integration
  alias ElixirML.Variable
  
  setup do
    # Setup test variable space
    variables = [
      Variable.float(:temperature, range: {0.0, 2.0}, default: 0.7),
      Variable.choice(:model, [:gpt4, :claude3, :llama2], default: :gpt4),
      Variable.integer(:max_tokens, range: {1, 4000}, default: 1000)
    ]
    
    {:ok, variable_space} = Variable.Space.create(%{
      name: "Test Variable Space",
      variables: variables
    })
    
    {:ok, variable_space: variable_space}
  end
  
  test "validates variable definitions through schema", %{variable_space: space} do
    for variable <- space.variables do
      assert {:ok, _} = Integration.validate_variable(variable)
    end
  end
  
  test "validates variable space schema", %{variable_space: space} do
    assert {:ok, _} = Integration.validate_variable_space(space)
  end
  
  test "validates variable configuration against space", %{variable_space: space} do
    valid_config = %{
      variable_space_id: space.id,
      configuration: %{
        temperature: 0.8,
        model: :claude3,
        max_tokens: 2000
      },
      created_at: DateTime.utc_now()
    }
    
    assert {:ok, _} = Integration.validate_configuration(valid_config)
    
    invalid_config = %{
      variable_space_id: space.id,
      configuration: %{
        temperature: 3.0,  # Out of range
        model: :invalid_model,  # Not in choices
        max_tokens: 2000
      },
      created_at: DateTime.utc_now()
    }
    
    assert {:error, _} = Integration.validate_configuration(invalid_config)
  end
  
  test "generates variables from schema definitions" do
    defmodule TestProgramSchema do
      use ElixirML.Schema
      
      field :temperature, :float, variable: true, range: {0.0, 1.0}
      field :model, :atom, variable: true, choices: [:gpt4, :claude3]
      field :prompt, :string
    end
    
    variables = Integration.Generator.extract_variables(TestProgramSchema)
    
    assert length(variables) == 2
    assert Enum.any?(variables, &(&1.name == :temperature))
    assert Enum.any?(variables, &(&1.name == :model))
  end
end
```

### 2. Resource Framework Integration Tests

```elixir
defmodule ElixirML.Schema.Test.ResourceIntegrationTest do
  use ExUnit.Case, async: false
  
  alias ElixirML.Schema.Resource.Integration
  
  defmodule TestResource do
    use Integration,
      domain: ElixirML.TestDomain,
      data_layer: Ash.DataLayer.Ets
    
    ets do
      private? true
    end
    
    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false
      
      schema_attribute :config, TestConfigSchema
      variable_attribute :temperature, ElixirML.Variable.float(:temperature, range: {0.0, 2.0})
    end
    
    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end
  
  defmodule TestConfigSchema do
    use ElixirML.Schema
    
    field :model, :atom, constraints: [in: [:gpt4, :claude3]]
    field :max_tokens, :integer, constraints: [min: 1, max: 4000]
    
    validation :model_token_compatibility do
      case field(:model) do
        :gpt4 -> field(:max_tokens) <= 4000
        :claude3 -> field(:max_tokens) <= 3000
      end
    end
  end
  
  test "creates resource with schema validation" do
    valid_attrs = %{
      name: "Test Resource",
      config: %{model: :gpt4, max_tokens: 2000},
      temperature: 0.8
    }
    
    assert {:ok, resource} = TestResource.create(valid_attrs)
    assert resource.name == "Test Resource"
    assert resource.config.model == :gpt4
  end
  
  test "rejects invalid schema data" do
    invalid_attrs = %{
      name: "Test Resource",
      config: %{model: :gpt4, max_tokens: 5000},  # Exceeds limit
      temperature: 0.8
    }
    
    assert {:error, _} = TestResource.create(invalid_attrs)
  end
  
  test "generates GraphQL schema from resource" do
    schema = Integration.APIGenerator.generate_graphql_schema(TestResource)
    
    assert schema =~ "type TestResource"
    assert schema =~ "name: String!"
    assert schema =~ "config: JSON"
    assert schema =~ "temperature: Float"
  end
  
  test "generates OpenAPI schema from resource" do
    schema = Integration.APIGenerator.generate_openapi_schema(TestResource)
    
    assert schema.type == "object"
    assert Map.has_key?(schema.properties, "name")
    assert Map.has_key?(schema.properties, "config")
    assert "name" in schema.required
  end
end
```

## Performance Testing

### 1. Validation Performance Benchmarks

```elixir
defmodule ElixirML.Schema.Test.PerformanceBenchmark do
  use ExUnit.Case, async: false
  
  @moduletag :benchmark
  
  setup_all do
    # Create test schemas of varying complexity
    schemas = %{
      simple: create_simple_schema(),
      medium: create_medium_schema(),
      complex: create_complex_schema()
    }
    
    # Generate test data
    test_data = %{
      simple: generate_test_data(:simple, 1000),
      medium: generate_test_data(:medium, 1000),
      complex: generate_test_data(:complex, 1000)
    }
    
    {:ok, schemas: schemas, test_data: test_data}
  end
  
  test "validation performance benchmark", %{schemas: schemas, test_data: test_data} do
    results = for {complexity, schema} <- schemas do
      data = test_data[complexity]
      
      {time, _} = :timer.tc(fn ->
        Enum.each(data, &schema.validate/1)
      end)
      
      {complexity, time / 1000}  # Convert to milliseconds
    end
    
    IO.puts("\nValidation Performance Results:")
    for {complexity, time} <- results do
      throughput = 1000 / time * 1000  # validations per second
      IO.puts("#{complexity}: #{Float.round(time, 2)}ms total, #{Float.round(throughput, 0)} validations/sec")
    end
    
    # Performance assertions
    simple_time = results[:simple]
    complex_time = results[:complex]
    
    # Complex schema should not be more than 10x slower than simple
    assert complex_time / simple_time < 10
  end
  
  test "transformation performance benchmark", %{schemas: schemas, test_data: test_data} do
    results = for {complexity, schema} <- schemas do
      data = test_data[complexity]
      
      {time, _} = :timer.tc(fn ->
        Enum.each(data, &schema.transform/1)
      end)
      
      {complexity, time / 1000}
    end
    
    IO.puts("\nTransformation Performance Results:")
    for {complexity, time} <- results do
      throughput = 1000 / time * 1000
      IO.puts("#{complexity}: #{Float.round(time, 2)}ms total, #{Float.round(throughput, 0)} transforms/sec")
    end
  end
  
  test "concurrent validation performance" do
    schema = create_medium_schema()
    data = generate_test_data(:medium, 100)
    
    # Test with different concurrency levels
    concurrency_levels = [1, 2, 4, 8, 16]
    
    results = for concurrency <- concurrency_levels do
      {time, _} = :timer.tc(fn ->
        data
        |> Enum.chunk_every(div(length(data), concurrency))
        |> Enum.map(fn chunk ->
          Task.async(fn ->
            Enum.each(chunk, &schema.validate/1)
          end)
        end)
        |> Task.await_many()
      end)
      
      {concurrency, time / 1000}
    end
    
    IO.puts("\nConcurrent Validation Results:")
    for {concurrency, time} <- results do
      IO.puts("#{concurrency} processes: #{Float.round(time, 2)}ms")
    end
  end
  
  test "memory usage analysis" do
    schema = create_complex_schema()
    data = generate_test_data(:complex, 1000)
    
    # Measure memory before
    :erlang.garbage_collect()
    {_, mem_before} = :erlang.process_info(self(), :memory)
    
    # Perform validations
    results = Enum.map(data, &schema.validate/1)
    
    # Measure memory after
    :erlang.garbage_collect()
    {_, mem_after} = :erlang.process_info(self(), :memory)
    
    memory_used = mem_after - mem_before
    memory_per_validation = memory_used / length(data)
    
    IO.puts("\nMemory Usage Analysis:")
    IO.puts("Total memory used: #{memory_used} bytes")
    IO.puts("Memory per validation: #{Float.round(memory_per_validation, 2)} bytes")
    
    # Memory should be reasonable (less than 1KB per validation)
    assert memory_per_validation < 1024
  end
  
  defp create_simple_schema() do
    defmodule SimpleSchema do
      use ElixirML.Schema
      
      field :name, :string, required: true
      field :age, :integer, constraints: [min: 0, max: 150]
    end
    
    SimpleSchema
  end
  
  defp create_medium_schema() do
    defmodule MediumSchema do
      use ElixirML.Schema
      
      field :name, :string, required: true
      field :email, :string, format: :email
      field :age, :integer, constraints: [min: 0, max: 150]
      field :preferences, :map
      field :tags, {:array, :string}
      
      validation :email_age_consistency do
        if String.contains?(field(:email), "student") do
          field(:age) < 25
        else
          true
        end
      end
      
      transform :normalize_name do
        update_field(:name, &String.trim/1)
      end
    end
    
    MediumSchema
  end
  
  defp create_complex_schema() do
    defmodule ComplexSchema do
      use ElixirML.Schema
      
      field :user_id, :uuid, required: true
      field :profile, :map, required: true
      field :settings, :map
      field :embeddings, {:array, :embedding}
      field :confidence_scores, {:array, :probability}
      field :metadata, :map
      field :created_at, :utc_datetime
      field :updated_at, :utc_datetime
      
      validation :profile_completeness do
        profile = field(:profile)
        required_fields = [:name, :email, :bio]
        Enum.all?(required_fields, &Map.has_key?(profile, &1))
      end
      
      validation :embeddings_consistency do
        embeddings = field(:embeddings)
        if length(embeddings) > 0 do
          first_dim = length(List.first(embeddings))
          Enum.all?(embeddings, &(length(&1) == first_dim))
        else
          true
        end
      end
      
      transform :normalize_profile do
        profile = field(:profile)
        normalized = %{profile |
          name: String.trim(profile[:name] || ""),
          email: String.downcase(String.trim(profile[:email] || ""))
        }
        set_field(:profile, normalized)
      end
      
      transform :update_timestamps do
        now = DateTime.utc_now()
        set_field(:updated_at, now)
        if field(:created_at) == nil do
          set_field(:created_at, now)
        end
      end
    end
    
    ComplexSchema
  end
  
  defp generate_test_data(:simple, count) do
    for _ <- 1..count do
      %{
        name: "User #{:rand.uniform(1000)}",
        age: :rand.uniform(100)
      }
    end
  end
  
  defp generate_test_data(:medium, count) do
    for _ <- 1..count do
      %{
        name: "User #{:rand.uniform(1000)}",
        email: "user#{:rand.uniform(1000)}@example.com",
        age: :rand.uniform(100),
        preferences: %{theme: "dark", language: "en"},
        tags: ["tag1", "tag2", "tag3"]
      }
    end
  end
  
  defp generate_test_data(:complex, count) do
    for _ <- 1..count do
      %{
        user_id: UUID.uuid4(),
        profile: %{
          name: "User #{:rand.uniform(1000)}",
          email: "user#{:rand.uniform(1000)}@example.com",
          bio: "A test user bio"
        },
        settings: %{notifications: true, privacy: "public"},
        embeddings: [
          Enum.map(1..768, fn _ -> :rand.uniform() end),
          Enum.map(1..768, fn _ -> :rand.uniform() end)
        ],
        confidence_scores: [0.8, 0.9, 0.7],
        metadata: %{source: "test", version: 1},
        created_at: DateTime.utc_now()
      }
    end
  end
end
```

## Property-Based Testing

### 1. Schema Invariant Testing

```elixir
defmodule ElixirML.Schema.Test.PropertyTest do
  use ExUnit.Case, async: true
  use PropCheck
  
  alias ElixirML.Schema.Types
  
  property "valid data always passes validation" do
    forall {schema, data} <- {schema_generator(), valid_data_generator()} do
      case schema.validate(data) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    end
  end
  
  property "validation is deterministic" do
    forall {schema, data} <- {schema_generator(), any_data_generator()} do
      result1 = schema.validate(data)
      result2 = schema.validate(data)
      result1 == result2
    end
  end
  
  property "transformation preserves validation" do
    forall {schema, data} <- {schema_generator(), valid_data_generator()} do
      case schema.transform(data) do
        {:ok, transformed} ->
          case schema.validate(transformed) do
            {:ok, _} -> true
            {:error, _} -> false
          end
        {:error, _} -> true  # If transformation fails, that's acceptable
      end
    end
  end
  
  property "roundtrip transformation is stable" do
    forall {schema, data} <- {schema_generator(), valid_data_generator()} do
      case schema.transform(data) do
        {:ok, transformed1} ->
          case schema.transform(transformed1) do
            {:ok, transformed2} ->
              transformed1 == transformed2
            {:error, _} -> false
          end
        {:error, _} -> true
      end
    end
  end
  
  property "ML type validation properties" do
    forall type_data <- ml_type_generator() do
      case type_data do
        {:embedding, embedding} ->
          case Types.validate_type(embedding, :embedding) do
            {:ok, _} -> is_list(embedding) and Enum.all?(embedding, &is_number/1)
            {:error, _} -> not (is_list(embedding) and Enum.all?(embedding, &is_number/1))
          end
        
        {:probability, prob} ->
          case Types.validate_type(prob, :probability) do
            {:ok, _} -> is_number(prob) and prob >= 0.0 and prob <= 1.0
            {:error, _} -> not (is_number(prob) and prob >= 0.0 and prob <= 1.0)
          end
        
        {:token_list, tokens} ->
          case Types.validate_type(tokens, :token_list) do
            {:ok, _} -> is_list(tokens) and Enum.all?(tokens, &is_binary/1)
            {:error, _} -> not (is_list(tokens) and Enum.all?(tokens, &is_binary/1))
          end
      end
    end
  end
  
  # Generators
  
  defp schema_generator() do
    # Generate simple test schemas
    oneof([
      simple_string_schema(),
      integer_range_schema(),
      map_schema()
    ])
  end
  
  defp simple_string_schema() do
    defmodule PropTestStringSchema do
      use ElixirML.Schema
      field :value, :string, required: true
    end
    
    PropTestStringSchema
  end
  
  defp integer_range_schema() do
    defmodule PropTestIntegerSchema do
      use ElixirML.Schema
      field :value, :integer, constraints: [min: 0, max: 100]
    end
    
    PropTestIntegerSchema
  end
  
  defp map_schema() do
    defmodule PropTestMapSchema do
      use ElixirML.Schema
      field :name, :string, required: true
      field :count, :integer, constraints: [min: 0]
    end
    
    PropTestMapSchema
  end
  
  defp valid_data_generator() do
    oneof([
      %{value: binary()},
      %{value: range(0, 100)},
      %{name: binary(), count: range(0, 1000)}
    ])
  end
  
  defp any_data_generator() do
    oneof([
      map(atom(), any()),
      list(any()),
      binary(),
      integer(),
      float(),
      atom(),
      boolean()
    ])
  end
  
  defp ml_type_generator() do
    oneof([
      {:embedding, list(float())},
      {:probability, float()},
      {:token_list, list(binary())}
    ])
  end
end
```

## Test Utilities and Helpers

### 1. Schema Test Helpers

```elixir
defmodule ElixirML.Schema.TestHelpers do
  @moduledoc """
  Utility functions for schema testing.
  """
  
  @doc "Create a test schema with given fields"
  def create_test_schema(fields, opts \\ []) do
    module_name = Keyword.get(opts, :module_name, :"TestSchema#{:rand.uniform(10000)}")
    
    quote do
      defmodule unquote(module_name) do
        use ElixirML.Schema
        
        unquote_splicing(for {name, type, field_opts} <- fields do
          quote do
            field unquote(name), unquote(type), unquote(field_opts)
          end
        end)
      end
    end
    |> Code.eval_quoted()
    |> elem(0)
  end
  
  @doc "Generate valid test data for a schema"
  def generate_valid_data(schema_module) do
    fields = schema_module.__schema__(:fields)
    
    for {name, type, opts} <- fields, into: %{} do
      {name, generate_valid_value(type, opts)}
    end
  end
  
  @doc "Generate invalid test data for a schema"
  def generate_invalid_data(schema_module) do
    fields = schema_module.__schema__(:fields)
    
    for {name, type, opts} <- fields, into: %{} do
      {name, generate_invalid_value(type, opts)}
    end
  end
  
  @doc "Assert that validation succeeds"
  def assert_valid(schema_module, data) do
    case schema_module.validate(data) do
      {:ok, _} -> :ok
      {:error, errors} -> 
        raise "Expected validation to succeed, but got errors: #{inspect(errors)}"
    end
  end
  
  @doc "Assert that validation fails"
  def assert_invalid(schema_module, data) do
    case schema_module.validate(data) do
      {:ok, _} -> 
        raise "Expected validation to fail, but it succeeded"
      {:error, _} -> :ok
    end
  end
  
  @doc "Assert that transformation succeeds"
  def assert_transforms(schema_module, input, expected_output) do
    case schema_module.transform(input) do
      {:ok, ^expected_output} -> :ok
      {:ok, actual} ->
        raise "Expected transformation to produce #{inspect(expected_output)}, but got #{inspect(actual)}"
      {:error, error} ->
        raise "Expected transformation to succeed, but got error: #{inspect(error)}"
    end
  end
  
  defp generate_valid_value(:string, opts) do
    if Keyword.get(opts, :required, false) do
      "test_string"
    else
      if :rand.uniform(2) == 1, do: "test_string", else: nil
    end
  end
  
  defp generate_valid_value(:integer, opts) do
    min = get_in(opts, [:constraints, :min]) || 0
    max = get_in(opts, [:constraints, :max]) || 100
    :rand.uniform(max - min) + min
  end
  
  defp generate_valid_value(:float, opts) do
    min = get_in(opts, [:constraints, :min]) || 0.0
    max = get_in(opts, [:constraints, :max]) || 1.0
    :rand.uniform() * (max - min) + min
  end
  
  defp generate_valid_value(:boolean, _opts) do
    :rand.uniform(2) == 1
  end
  
  defp generate_valid_value(:atom, opts) do
    choices = get_in(opts, [:constraints, :in])
    if choices do
      Enum.random(choices)
    else
      :test_atom
    end
  end
  
  defp generate_valid_value(:embedding, _opts) do
    Enum.map(1..768, fn _ -> :rand.uniform() end)
  end
  
  defp generate_valid_value(:probability, _opts) do
    :rand.uniform()
  end
  
  defp generate_valid_value(:token_list, _opts) do
    ["token1", "token2", "token3"]
  end
  
  defp generate_valid_value(_, _opts) do
    "default_value"
  end
  
  defp generate_invalid_value(:string, _opts) do
    123  # Wrong type
  end
  
  defp generate_invalid_value(:integer, opts) do
    min = get_in(opts, [:constraints, :min])
    if min do
      min - 1  # Below minimum
    else
      "not_an_integer"  # Wrong type
    end
  end
  
  defp generate_invalid_value(:float, opts) do
    max = get_in(opts, [:constraints, :max])
    if max do
      max + 1.0  # Above maximum
    else
      "not_a_float"  # Wrong type
    end
  end
  
  defp generate_invalid_value(:embedding, _opts) do
    ["not", "numbers"]  # Wrong element types
  end
  
  defp generate_invalid_value(:probability, _opts) do
    1.5  # Out of range
  end
  
  defp generate_invalid_value(_, _opts) do
    %{invalid: :data}
  end
end
```

## Test Configuration and Setup

### 1. Test Configuration

```elixir
# test/test_helper.exs
ExUnit.start([
  exclude: [:benchmark],
  formatters: [ExUnit.CLIFormatter, ExUnit.JsonFormatter]
])

# Configure test database
Application.put_env(:elixir_ml, ElixirML.TestRepo,
  database: ":memory:",
  pool: Ecto.Adapters.SQLite3.ConnectionPool
)

# Start test supervision tree
{:ok, _} = ElixirML.TestApplication.start(:normal, [])

# Setup test schemas
ElixirML.Schema.Integration.Performance.precompile_schemas()
ElixirML.Schema.Integration.Performance.cache_validation_functions()
```

### 2. Test Data Fixtures

```elixir
defmodule ElixirML.Schema.Test.Fixtures do
  @moduledoc """
  Test data fixtures for schema testing.
  """
  
  def program_schema_fixture() do
    %{
      name: "Test Program",
      signature_config: %{
        input: "string",
        output: "string"
      },
      program_config: %{
        temperature: 0.7,
        max_tokens: 1000
      }
    }
  end
  
  def variable_space_fixture() do
    %{
      name: "Test Variable Space",
      variables: [
        %{
          name: :temperature,
          type: :float,
          default: 0.7,
          constraints: %{range: {0.0, 2.0}}
        },
        %{
          name: :model,
          type: :choice,
          default: :gpt4,
          constraints: %{choices: [:gpt4, :claude3, :llama2]}
        }
      ]
    }
  end
  
  def ml_data_fixture() do
    %{
      embedding: Enum.map(1..768, fn _ -> :rand.uniform() end),
      confidence: 0.95,
      tokens: ["hello", "world", "!"],
      metadata: %{
        model: "gpt-4",
        timestamp: DateTime.utc_now()
      }
    }
  end
end
```

## Summary

The Schema Engine Testing Framework provides comprehensive validation through:

1. **Unit Testing**: Complete coverage of schema definitions, validations, and transformations
2. **Integration Testing**: Cross-system integration validation with Variable System and Resource Framework
3. **Performance Testing**: Benchmarks for validation speed, memory usage, and concurrent access
4. **Property-Based Testing**: Invariant validation and roundtrip testing
5. **Test Utilities**: Helper functions and fixtures for consistent testing

This testing framework ensures the Schema Engine maintains reliability, performance, and correctness across all use cases and integration scenarios.
