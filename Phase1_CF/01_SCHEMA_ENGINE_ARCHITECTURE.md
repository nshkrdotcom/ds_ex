# Phase 1: Schema Engine Architecture
*Sinter-Powered Schema System for ElixirML/DSPEx*

## Executive Summary

The Schema Engine provides the foundational data validation and transformation layer for ElixirML/DSPEx. Built on Sinter's capabilities, it ensures type safety, enables automatic data transformation, and integrates seamlessly with the Variable System and Resource Framework.

## Core Architecture

### System Components

```
ElixirML.Schema Architecture
├── Core Schema System
│   ├── Schema Definition DSL
│   ├── Validation Engine  
│   ├── Transformation Pipeline
│   └── Type System
├── Integration Layer
│   ├── Variable System Binding
│   ├── Resource Framework Integration
│   ├── Program Schema Validation
│   └── Adapter Schema Support
├── Performance Layer
│   ├── Compile-Time Optimization
│   ├── Runtime Caching
│   └── Batch Validation
└── Developer Tools
    ├── Schema Visualization
    ├── Testing Framework
    └── Migration Utilities
```

## Schema Definition System

### Basic Schema DSL

```elixir
defmodule ElixirML.Schema do
  @moduledoc """
  Core schema definition system for ElixirML/DSPEx.
  Provides compile-time and runtime validation with transformation.
  """

  defmacro defschema(name, do: block) do
    quote do
      defmodule unquote(name) do
        use ElixirML.Schema.Definition
        import ElixirML.Schema.DSL
        
        unquote(block)
        
        @before_compile ElixirML.Schema.Compiler
      end
    end
  end

  defmacro field(name, type, opts \\ []) do
    quote do
      Module.put_attribute(__MODULE__, :fields, 
        {unquote(name), unquote(type), unquote(opts)})
    end
  end

  defmacro validation(name, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :validations,
        {unquote(name), unquote(block)})
    end
  end

  defmacro transform(name, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :transforms,
        {unquote(name), unquote(block)})
    end
  end
end
```

### ML-Specific Types

```elixir
defmodule ElixirML.Schema.Types do
  @moduledoc """
  Machine Learning specific type system for schemas.
  """

  @type ml_type :: 
    :embedding |
    :tensor |
    :token_list |
    :probability |
    :confidence_score |
    :model_response |
    :variable_config

  def validate_type(value, :embedding) do
    case value do
      list when is_list(list) and length(list) > 0 ->
        if Enum.all?(list, &is_number/1) do
          {:ok, value}
        else
          {:error, "Embedding must be list of numbers"}
        end
      _ -> {:error, "Invalid embedding format"}
    end
  end

  def validate_type(value, :probability) do
    case value do
      num when is_number(num) and num >= 0.0 and num <= 1.0 ->
        {:ok, value}
      _ -> {:error, "Probability must be between 0.0 and 1.0"}
    end
  end

  def validate_type(value, :variable_config) do
    case value do
      map when is_map(map) ->
        # Validate variable configuration structure
        required_keys = [:name, :type, :value]
        if Enum.all?(required_keys, &Map.has_key?(map, &1)) do
          {:ok, value}
        else
          {:error, "Variable config missing required keys"}
        end
      _ -> {:error, "Variable config must be a map"}
    end
  end
end
```

## Schema Examples for DSPEx

### Program Input/Output Schemas

```elixir
defmodule ElixirML.Schemas.Program do
  use ElixirML.Schema

  defschema ProgramInput do
    field :text, :string, required: true
    field :context, :string, default: ""
    field :variables, :variable_config
    field :metadata, :map, default: %{}
    
    validation :text_not_empty do
      String.trim(field(:text)) |> String.length() > 0
    end
    
    transform :normalize_input do
      update_field(:text, &String.trim/1)
    end
  end

  defschema ProgramOutput do
    field :result, :string, required: true
    field :confidence, :confidence_score, required: true
    field :reasoning, :string
    field :tokens_used, :integer, constraints: [min: 0]
    field :latency_ms, :integer, constraints: [min: 0]
    field :metadata, :map, default: %{}
    
    validation :result_quality do
      String.length(field(:result)) > 0 and field(:confidence) >= 0.5
    end
  end
end
```

### Variable System Schemas

```elixir
defmodule ElixirML.Schemas.Variable do
  use ElixirML.Schema

  defschema VariableDefinition do
    field :name, :atom, required: true
    field :type, :atom, required: true, 
          constraints: [in: [:float, :integer, :choice, :module]]
    field :default, :union, types: [:string, :integer, :float, :atom]
    field :constraints, :map, default: %{}
    field :description, :string
    field :metadata, :map, default: %{}
    
    validation :type_constraints_match do
      case {field(:type), field(:constraints)} do
        {:float, %{range: {min, max}}} when is_number(min) and is_number(max) -> 
          min < max
        {:choice, %{choices: choices}} when is_list(choices) -> 
          length(choices) > 0
        _ -> true
      end
    end
  end

  defschema VariableSpace do
    field :variables, {:array, VariableDefinition}, required: true
    field :dependencies, :map, default: %{}
    field :constraints, {:array, :map}, default: []
    field :metadata, :map, default: %{}
    
    validation :unique_variable_names do
      names = field(:variables) |> Enum.map(& &1.name)
      length(names) == length(Enum.uniq(names))
    end
  end
end
```

## Integration Points

### Variable System Integration

```elixir
defmodule ElixirML.Schema.VariableIntegration do
  @moduledoc """
  Integration between Schema Engine and Variable System.
  """

  def generate_schema_from_variables(variables) do
    fields = Enum.map(variables, fn variable ->
      {variable.name, variable_type_to_schema_type(variable), 
       variable_opts_to_schema_opts(variable)}
    end)

    %ElixirML.Schema.Runtime{
      fields: fields,
      validations: generate_variable_validations(variables),
      transforms: generate_variable_transforms(variables)
    }
  end

  defp variable_type_to_schema_type(%{type: :float}), do: :float
  defp variable_type_to_schema_type(%{type: :integer}), do: :integer
  defp variable_type_to_schema_type(%{type: :choice, constraints: %{choices: choices}}), 
    do: {:enum, choices}
  defp variable_type_to_schema_type(%{type: :module}), do: :atom
end
```

### Resource Framework Integration

```elixir
defmodule ElixirML.Schema.ResourceIntegration do
  @moduledoc """
  Integration with Ash Resource Framework.
  """

  defmacro __using__(opts) do
    quote do
      use Ash.Resource, unquote(opts)
      import ElixirML.Schema.ResourceIntegration
      
      defmacro schema_attribute(name, schema_module, opts \\ []) do
        quote do
          attribute unquote(name), :map, unquote(opts)
          
          validate unquote(:"validate_#{name}_schema") do
            ElixirML.Schema.ResourceIntegration.validate_attribute_schema(
              unquote(name), 
              unquote(schema_module)
            )
          end
        end
      end
    end
  end

  def validate_attribute_schema(attribute_name, schema_module) do
    fn changeset ->
      case Ash.Changeset.get_attribute(changeset, attribute_name) do
        nil -> changeset
        value ->
          case schema_module.validate(value) do
            {:ok, validated_value} ->
              Ash.Changeset.change_attribute(changeset, attribute_name, validated_value)
            {:error, errors} ->
              Ash.Changeset.add_error(changeset, 
                field: attribute_name, 
                message: format_schema_errors(errors))
          end
      end
    end
  end
end
```

## Performance Optimization

### Compile-Time Optimization

```elixir
defmodule ElixirML.Schema.Compiler do
  @moduledoc """
  Compile-time optimization for schema validation.
  """

  defmacro __before_compile__(env) do
    fields = Module.get_attribute(env.module, :fields, [])
    validations = Module.get_attribute(env.module, :validations, [])
    transforms = Module.get_attribute(env.module, :transforms, [])

    validation_ast = generate_validation_function(fields, validations)
    transform_ast = generate_transform_function(transforms)
    metadata_ast = generate_metadata_function(fields, validations, transforms)

    quote do
      unquote(validation_ast)
      unquote(transform_ast)
      unquote(metadata_ast)
      
      def validate(data, opts \\ []) do
        __validate__(data, opts)
      end
      
      def transform(data, opts \\ []) do
        __transform__(data, opts)
      end
      
      def metadata() do
        __metadata__()
      end
    end
  end

  defp generate_validation_function(fields, validations) do
    field_validations = Enum.map(fields, &generate_field_validation_ast/1)
    custom_validations = Enum.map(validations, &generate_custom_validation_ast/1)

    quote do
      def __validate__(data, opts) do
        with unquote_splicing(field_validations),
             unquote_splicing(custom_validations) do
          {:ok, data}
        else
          {:error, _} = error -> error
        end
      end
    end
  end
end
```

### Runtime Caching

```elixir
defmodule ElixirML.Schema.Cache do
  @moduledoc """
  High-performance caching for schema validation results.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    table_name = Keyword.get(opts, :table_name, :schema_cache)
    max_size = Keyword.get(opts, :max_size, 10_000)
    
    :ets.new(table_name, [:named_table, :public, :set])
    
    {:ok, %{
      table: table_name,
      max_size: max_size,
      current_size: 0
    }}
  end

  def get_cached_validation(schema_module, data_hash) do
    case :ets.lookup(:schema_cache, {schema_module, data_hash}) do
      [{_, result, _timestamp}] -> {:hit, result}
      [] -> :miss
    end
  end

  def cache_validation_result(schema_module, data_hash, result) do
    GenServer.cast(__MODULE__, {:cache, schema_module, data_hash, result})
  end
end
```

## Development Tools

### Schema Visualization

```elixir
defmodule ElixirML.Schema.Visualizer do
  @moduledoc """
  Tools for visualizing schema structure and relationships.
  """

  def generate_schema_diagram(schema_module, opts \\ []) do
    metadata = schema_module.metadata()
    
    nodes = generate_field_nodes(metadata.fields)
    edges = generate_validation_edges(metadata.validations)
    
    graphviz_content = """
    digraph schema {
      rankdir=TB;
      node [shape=box, style=rounded];
      
      #{nodes}
      #{edges}
    }
    """
    
    output_file = Keyword.get(opts, :output, "schema_diagram.dot")
    File.write!(output_file, graphviz_content)
  end

  defp generate_field_nodes(fields) do
    fields
    |> Enum.map(fn {name, type, opts} ->
      label = "#{name}\\n#{format_type(type)}"
      color = if Keyword.get(opts, :required, false), do: "red", else: "blue"
      "  #{name} [label=\"#{label}\", color=#{color}];"
    end)
    |> Enum.join("\n")
  end

  defp format_type(type) when is_atom(type), do: to_string(type)
  defp format_type({:array, inner_type}), do: "array(#{format_type(inner_type)})"
  defp format_type(type), do: inspect(type)
end
```

## Implementation Strategy

### Phase 1 Development Plan

#### Week 1: Core Foundation
- [ ] Basic schema definition DSL
- [ ] Core validation engine
- [ ] ML-specific type system
- [ ] Runtime schema creation

#### Week 2: Integration Layer
- [ ] Variable System integration
- [ ] Resource Framework integration
- [ ] Program schema binding
- [ ] Adapter schema validation

#### Week 3: Performance & Optimization
- [ ] Compile-time optimization
- [ ] Runtime caching system
- [ ] Batch validation
- [ ] Performance profiling

#### Week 4: Tools & Testing
- [ ] Schema visualization
- [ ] Testing framework
- [ ] Migration utilities
- [ ] Documentation generation

### Success Criteria

#### Functional Requirements
- [ ] 100% schema validation accuracy
- [ ] Support for complex nested structures
- [ ] Seamless Variable System integration
- [ ] Resource Framework compatibility

#### Performance Requirements
- [ ] <1ms validation time for typical schemas
- [ ] <100MB memory usage for 10,000 cached schemas
- [ ] 95%+ cache hit rate in production
- [ ] Zero-copy transformation where possible

#### Integration Requirements
- [ ] Full Variable System compatibility
- [ ] Resource Framework integration
- [ ] Backward compatibility maintenance
- [ ] Extensible type system

This Schema Engine architecture provides the foundational data validation and transformation capabilities required for ElixirML/DSPEx, enabling type-safe, high-performance ML workflows with comprehensive validation and optimization support. 