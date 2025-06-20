# SINTER_BUILDOUT.md
*Strategic Enhancement of Sinter for DSPEx Variable System*

## Executive Summary

This document outlines the strategic enhancement of **Sinter** to serve as the schema validation foundation for DSPEx's revolutionary **Variable System**. The Variable System enables automatic optimization across adapters, modules, and parameters - solving the exact challenge posed by the DSPy community.

**Core Mission**: Transform Sinter into the type-safe foundation that enables any optimizer to tune any parameter type (discrete choices, continuous values, module selection) automatically.

**Philosophy**: Enhance what works, add only what's essential, build the foundation for the Variable revolution.

## The Variable System Challenge

### **The DSPy Community Problem:**
> "Do we have optimizers that permute through adapters and modules? (e.g., JSON vs Markdown tool calling, Predict vs CoT vs PoT)... all evaluated and selected automatically."

### **DSPEx Solution:**
```elixir
# Instead of hard-coding choices:
program = DSPEx.Predict.new(signature, adapter: JSONAdapter, strategy: CoT)

# Declare variables for optimization:
program = DSPEx.Predict.new(signature)
  |> Variable.define(:adapter, choices: [JSONAdapter, MarkdownAdapter, ChatAdapter])
  |> Variable.define(:strategy, choices: [Predict, CoT, PoT, ReAct])
  |> Variable.define(:temperature, range: {0.1, 1.5})

# ANY optimizer can find the best combination:
{:ok, optimized} = SIMBA.optimize(program, training_data, eval_fn)
{:ok, optimized} = BEACON.optimize(program, training_data, eval_fn)
{:ok, optimized} = GridSearch.optimize(program, training_data, eval_fn)
```

## Current Sinter Analysis

### ✅ **Sinter's Strengths (Keep These)**
```elixir
# Clean, focused API
schema = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:age, :integer, [gt: 0]}
])

{:ok, validated} = Sinter.validate(schema, %{name: "Alice", age: 30})
```

### ❌ **Missing for Variable System (Add These)**
1. **Variable-Aware Types**: `:variable_choice`, `:variable_range`, `:variable_module`
2. **ML-Specific Types**: `:embedding`, `:probability`, `:model_response`
3. **Variable Extraction**: Identify optimization parameters from schemas
4. **Runtime Schema Resolution**: Apply variable configurations to schemas
5. **Enhanced Validation**: Support for dynamic type resolution

## Enhancement Strategy

### Phase 1: Variable-Aware Type System (Week 1-2)

#### 1.1 Core Variable Types
```elixir
# sinter/lib/sinter/types.ex - Add variable-aware types

def validate(:variable_choice, value, path) when is_atom(value) or is_binary(value) do
  # Variable choices are validated at resolution time, not definition time
  {:ok, value}
end

def validate(:variable_range, value, path) when is_number(value) do
  # Variable ranges are validated at resolution time
  {:ok, value}
end

def validate(:variable_module, value, path) when is_atom(value) do
  # Variable modules are validated at resolution time
  if Code.ensure_loaded?(value) do
    {:ok, value}
  else
    error = Error.new(path, :module_not_found, "Module #{value} not found")
    {:error, [error]}
  end
end

# ML-specific types for Variable System
def validate(:embedding, value, path) when is_list(value) do
  if Enum.all?(value, &is_number/1) and length(value) > 0 do
    {:ok, value}
  else
    error = Error.new(path, :type, "Embedding must be non-empty list of numbers")
    {:error, [error]}
  end
end

def validate(:probability, value, path) when is_number(value) do
  if value >= 0.0 and value <= 1.0 do
    {:ok, value}
  else
    error = Error.new(path, :constraint, "Probability must be between 0.0 and 1.0")
    {:error, [error]}
  end
end

def validate(:model_response, value, path) when is_map(value) do
  case value do
    %{text: text} when is_binary(text) -> {:ok, value}
    %{"text" => text} when is_binary(text) -> {:ok, value}
    _ ->
      error = Error.new(path, :constraint, "Model response must have 'text' field")
      {:error, [error]}
  end
end

def validate(:confidence_score, value, path) when is_number(value) do
  if value >= 0.0 do
    {:ok, value}
  else
    error = Error.new(path, :constraint, "Confidence score must be non-negative")
    {:error, [error]}
  end
end
```

#### 1.2 Variable-Specific Constraints
```elixir
# sinter/lib/sinter/constraints.ex - Add variable constraints

def validate_constraint({:choices, choices}, value, _path) do
  if value in choices do
    :ok
  else
    {:error, "Value #{inspect(value)} not in choices #{inspect(choices)}"}
  end
end

def validate_constraint({:range, {min_val, max_val}}, value, _path) when is_number(value) do
  if value >= min_val and value <= max_val do
    :ok
  else
    {:error, "Value #{value} not in range #{min_val}..#{max_val}"}
  end
end

def validate_constraint({:behavior, behavior}, value, _path) when is_atom(value) do
  if implements_behavior?(value, behavior) do
    :ok
  else
    {:error, "Module #{value} does not implement behavior #{behavior}"}
  end
end

def validate_constraint({:embedding_dim, expected_dim}, value, _path) when is_list(value) do
  if length(value) == expected_dim do
    :ok
  else
    {:error, "Embedding dimension must be #{expected_dim}, got #{length(value)}"}
  end
end

defp implements_behavior?(module, behavior) do
  case Code.ensure_loaded(module) do
    {:module, _} ->
      behaviors = module.module_info(:attributes)
      |> Keyword.get(:behaviour, [])
      behavior in behaviors
    _ -> false
  end
end
```

### Phase 2: Variable-Aware Schema System (Week 2-3)

#### 2.1 Enhanced Schema Structure
```elixir
# sinter/lib/sinter/schema.ex - Add variable support

defstruct [
  :fields,
  :variables,     # ← New: extracted variable definitions
  :metadata
]

def define(fields, opts \\ []) do
  {variable_fields, regular_fields} = extract_variables(fields)
  
  %Schema{
    fields: regular_fields ++ variable_fields,
    variables: variable_fields,
    metadata: Keyword.get(opts, :metadata, %{})
  }
end

# Extract variable fields from schema definition
defp extract_variables(fields) do
  Enum.split_with(fields, fn {_name, _type, opts} ->
    Keyword.get(opts, :variable, false)
  end)
end

# New: Variable-aware validation
def validate_with_variables(schema, data, variable_config \\ %{}) do
  # Resolve variables to concrete values
  resolved_schema = resolve_variables(schema, variable_config)
  
  # Standard validation with resolved schema
  validate(resolved_schema, data)
end

# Apply variable configuration to schema
defp resolve_variables(schema, variable_config) do
  resolved_fields = 
    Enum.map(schema.fields, fn {name, type, opts} ->
      if Keyword.get(opts, :variable) do
        # Apply variable configuration
        case Map.get(variable_config, name) do
          nil -> 
            # Use default value if no variable config provided
            {name, type, opts}
          resolved_value ->
            # Replace with resolved value and update constraints
            resolved_type = resolve_variable_type(type, resolved_value, opts)
            resolved_opts = resolve_variable_constraints(opts, resolved_value)
            {name, resolved_type, resolved_opts}
        end
      else
        {name, type, opts}
      end
    end)
  
  %{schema | fields: resolved_fields}
end

# Resolve variable type based on configuration
defp resolve_variable_type(:variable_choice, resolved_value, opts) do
  choices = Keyword.get(opts, :choices, [])
  cond do
    is_atom(resolved_value) and resolved_value in choices -> :atom
    is_binary(resolved_value) and resolved_value in choices -> :string
    is_integer(resolved_value) and resolved_value in choices -> :integer
    true -> :any
  end
end

defp resolve_variable_type(:variable_range, _resolved_value, opts) do
  {min_val, max_val} = Keyword.get(opts, :range, {0, 1})
  cond do
    is_float(min_val) or is_float(max_val) -> :float
    true -> :integer
  end
end

defp resolve_variable_type(:variable_module, _resolved_value, _opts) do
  :atom
end

defp resolve_variable_type(type, _resolved_value, _opts), do: type

# Update constraints based on resolved value
defp resolve_variable_constraints(opts, resolved_value) do
  opts
  |> Keyword.put(:resolved_value, resolved_value)
  |> Keyword.delete(:variable)
end
```

#### 2.2 Variable Definition Helpers
```elixir
# sinter/lib/sinter/variables.ex - New module for variable helpers

defmodule Sinter.Variables do
  @moduledoc """
  Variable definition helpers for optimization-aware schemas.
  
  Provides utilities for defining, extracting, and working with
  optimization variables in Sinter schemas.
  """

  @doc """
  Define a discrete choice variable.
  
  ## Examples
      
      iex> Variables.choice(:adapter, [JSONAdapter, MarkdownAdapter])
      {:adapter, :variable_choice, [variable: true, choices: [JSONAdapter, MarkdownAdapter]]}
  """
  def choice(name, choices, opts \\ []) do
    variable_opts = [
      variable: true,
      choices: choices,
      default: Keyword.get(opts, :default, List.first(choices)),
      description: Keyword.get(opts, :description, "")
    ] ++ opts
    
    {name, :variable_choice, variable_opts}
  end

  @doc """
  Define a continuous range variable.
  
  ## Examples
      
      iex> Variables.range(:temperature, {0.0, 2.0})
      {:temperature, :variable_range, [variable: true, range: {0.0, 2.0}]}
  """
  def range(name, {min_val, max_val}, opts \\ []) do
    variable_opts = [
      variable: true,
      range: {min_val, max_val},
      default: Keyword.get(opts, :default, (min_val + max_val) / 2),
      description: Keyword.get(opts, :description, "")
    ] ++ opts
    
    {name, :variable_range, variable_opts}
  end

  @doc """
  Define a module selection variable.
  
  ## Examples
      
      iex> Variables.module(:strategy, [Predict, CoT, PoT])
      {:strategy, :variable_module, [variable: true, choices: [Predict, CoT, PoT]]}
  """
  def module(name, modules, opts \\ []) do
    variable_opts = [
      variable: true,
      choices: modules,
      behavior: Keyword.get(opts, :behavior),
      default: Keyword.get(opts, :default, List.first(modules)),
      description: Keyword.get(opts, :description, "")
    ] ++ opts
    
    {name, :variable_module, variable_opts}
  end

  @doc """
  Extract variable space from a schema for optimization.
  """
  def extract_variable_space(schema) do
    schema.variables
    |> Enum.map(fn {name, type, opts} ->
      %{
        name: name,
        type: variable_type_to_optimizer_type(type),
        constraints: extract_variable_constraints(opts),
        default: Keyword.get(opts, :default),
        description: Keyword.get(opts, :description, "")
      }
    end)
  end

  # Convert Sinter variable types to optimizer-friendly types
  defp variable_type_to_optimizer_type(:variable_choice), do: :discrete
  defp variable_type_to_optimizer_type(:variable_range), do: :continuous
  defp variable_type_to_optimizer_type(:variable_module), do: :discrete

  defp extract_variable_constraints(opts) do
    opts
    |> Keyword.take([:choices, :range, :behavior, :gt, :lt, :gteq, :lteq])
    |> Enum.into(%{})
  end

  @doc """
  Validate a variable configuration against schema variables.
  """
  def validate_variable_config(schema, variable_config) do
    schema.variables
    |> Enum.reduce_while({:ok, %{}}, fn {name, type, opts}, {:ok, acc} ->
      case Map.get(variable_config, name) do
        nil ->
          # Use default if available
          case Keyword.get(opts, :default) do
            nil -> {:halt, {:error, "Missing required variable: #{name}"}}
            default -> {:cont, {:ok, Map.put(acc, name, default)}}
          end
        value ->
          case validate_variable_value(type, value, opts) do
            :ok -> {:cont, {:ok, Map.put(acc, name, value)}}
            {:error, reason} -> {:halt, {:error, "Invalid value for #{name}: #{reason}"}}
          end
      end
    end)
  end

  defp validate_variable_value(:variable_choice, value, opts) do
    choices = Keyword.get(opts, :choices, [])
    if value in choices do
      :ok
    else
      {:error, "#{inspect(value)} not in choices #{inspect(choices)}"}
    end
  end

  defp validate_variable_value(:variable_range, value, opts) when is_number(value) do
    {min_val, max_val} = Keyword.get(opts, :range, {0, 1})
    if value >= min_val and value <= max_val do
      :ok
    else
      {:error, "#{value} not in range #{min_val}..#{max_val}"}
    end
  end

  defp validate_variable_value(:variable_module, value, opts) when is_atom(value) do
    choices = Keyword.get(opts, :choices, [])
    behavior = Keyword.get(opts, :behavior)
    
    cond do
      not (value in choices) ->
        {:error, "#{value} not in module choices #{inspect(choices)}"}
      behavior && not implements_behavior?(value, behavior) ->
        {:error, "#{value} does not implement behavior #{behavior}"}
      true ->
        :ok
    end
  end

  defp validate_variable_value(_, value, _), do: {:error, "Invalid variable value: #{inspect(value)}"}

  defp implements_behavior?(module, behavior) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        behaviors = module.module_info(:attributes)
        |> Keyword.get(:behaviour, [])
        behavior in behaviors
      _ -> false
    end
  end
end
```

### Phase 3: ElixirML Integration Bridge (Week 3-4)

#### 3.1 ElixirML.Variable Integration
```elixir
# sinter/lib/sinter/elixir_ml.ex - Bridge to ElixirML Variable system

defmodule Sinter.ElixirML do
  @moduledoc """
  Integration bridge between Sinter and ElixirML Variable system.
  
  Converts ElixirML.Variable definitions to Sinter schemas and vice versa.
  """

  @doc """
  Convert ElixirML.Variable to Sinter variable field.
  """
  def from_elixir_ml_variable(%ElixirML.Variable{} = var) do
    sinter_type = elixir_ml_type_to_sinter(var.type)
    
    opts = [
      variable: true,
      default: var.default,
      description: var.description || ""
    ]
    
    # Add type-specific constraints
    opts = add_type_constraints(opts, var)
    
    {var.name, sinter_type, opts}
  end

  @doc """
  Convert Sinter variable field to ElixirML.Variable.
  """
  def to_elixir_ml_variable({name, type, opts}) do
    if Keyword.get(opts, :variable, false) do
      %ElixirML.Variable{
        name: name,
        type: sinter_type_to_elixir_ml(type),
        default: Keyword.get(opts, :default),
        constraints: extract_elixir_ml_constraints(opts),
        description: Keyword.get(opts, :description, "")
      }
    else
      {:error, "Not a variable field"}
    end
  end

  @doc """
  Create Sinter schema from ElixirML Variable space.
  """
  def schema_from_variable_space(variable_space) do
    fields = 
      variable_space.variables
      |> Map.values()
      |> Enum.map(&from_elixir_ml_variable/1)
    
    Sinter.Schema.define(fields)
  end

  @doc """
  Extract variable space from Sinter schema for ElixirML.
  """
  def variable_space_from_schema(schema) do
    variables = 
      schema.variables
      |> Enum.map(&to_elixir_ml_variable/1)
      |> Enum.filter(fn
        {:error, _} -> false
        _ -> true
      end)
      |> Map.new(fn var -> {var.name, var} end)
    
    %ElixirML.Variable.Space{
      variables: variables,
      dependencies: %{},
      constraints: [],
      metadata: schema.metadata
    }
  end

  # Type conversion helpers
  defp elixir_ml_type_to_sinter(:choice), do: :variable_choice
  defp elixir_ml_type_to_sinter(:float), do: :variable_range
  defp elixir_ml_type_to_sinter(:integer), do: :variable_range
  defp elixir_ml_type_to_sinter(:module), do: :variable_module
  defp elixir_ml_type_to_sinter(type), do: type

  defp sinter_type_to_elixir_ml(:variable_choice), do: :choice
  defp sinter_type_to_elixir_ml(:variable_range), do: :float
  defp sinter_type_to_elixir_ml(:variable_module), do: :module
  defp sinter_type_to_elixir_ml(type), do: type

  defp add_type_constraints(opts, %{type: :choice, constraints: %{choices: choices}}) do
    Keyword.put(opts, :choices, choices)
  end

  defp add_type_constraints(opts, %{type: :float, constraints: %{range: range}}) do
    Keyword.put(opts, :range, range)
  end

  defp add_type_constraints(opts, %{type: :integer, constraints: %{range: range}}) do
    Keyword.put(opts, :range, range)
  end

  defp add_type_constraints(opts, %{type: :module, constraints: %{modules: modules, behavior: behavior}}) do
    opts
    |> Keyword.put(:choices, modules)
    |> Keyword.put(:behavior, behavior)
  end

  defp add_type_constraints(opts, _), do: opts

  defp extract_elixir_ml_constraints(opts) do
    constraints = %{}
    
    constraints = if choices = Keyword.get(opts, :choices) do
      Map.put(constraints, :choices, choices)
    else
      constraints
    end
    
    constraints = if range = Keyword.get(opts, :range) do
      Map.put(constraints, :range, range)
    else
      constraints
    end
    
    constraints = if behavior = Keyword.get(opts, :behavior) do
      Map.put(constraints, :behavior, behavior)
    else
      constraints
    end
    
    constraints
  end
end
```

### Phase 4: Enhanced Error Messages & Developer Experience (Week 4)

#### 4.1 Variable-Aware Error Messages
```elixir
# sinter/lib/sinter/error.ex - Enhanced error messages for variables

defmodule Sinter.Error do
  defstruct [:path, :code, :message, :context]

  def new(path, code, message, context \\ %{}) do
    enhanced_message = enhance_variable_message(code, message, context)
    
    %__MODULE__{
      path: path,
      code: code,
      message: enhanced_message,
      context: context
    }
  end

  defp enhance_variable_message(:constraint, message, %{constraint: :choices, choices: choices}) do
    """
    #{message}
    
    Available choices:
    #{format_choices(choices)}
    
    This is a variable parameter that can be optimized automatically.
    """
  end

  defp enhance_variable_message(:constraint, message, %{constraint: :range, range: {min_val, max_val}}) do
    """
    #{message}
    
    Valid range: #{min_val} to #{max_val}
    
    This is a continuous variable that optimizers can tune automatically.
    """
  end

  defp enhance_variable_message(:module_not_found, message, %{module: module}) do
    """
    #{message}
    
    Make sure the module is:
    1. Correctly spelled: #{module}
    2. Available in the current environment
    3. Implements the required behavior (if specified)
    
    This is a module variable for automatic strategy selection.
    """
  end

  defp enhance_variable_message(:type, message, %{expected_type: :embedding}) do
    """
    #{message}
    
    Embeddings should be:
    - Non-empty list of numbers: [0.1, 0.2, 0.3, ...]
    - Consistent dimensionality across your dataset
    - Normalized if using cosine similarity
    
    Example: [0.1, 0.2, 0.3, 0.4, 0.5]
    """
  end

  defp enhance_variable_message(:constraint, message, %{constraint: :probability}) do
    """
    #{message}
    
    Probabilities must be between 0.0 and 1.0:
    - 0.0 = impossible
    - 0.5 = equally likely  
    - 1.0 = certain
    
    Common sources: model confidence scores, sampling probabilities
    """
  end

  defp enhance_variable_message(_code, message, _context), do: message

  defp format_choices(choices) when is_list(choices) do
    choices
    |> Enum.map(fn choice -> "  - #{inspect(choice)}" end)
    |> Enum.join("\n")
  end
end
```

#### 4.2 Developer-Friendly Variable Definition Macros
```elixir
# sinter/lib/sinter/dsl.ex - Optional DSL for easier variable definition

defmodule Sinter.DSL do
  @moduledoc """
  Optional DSL for defining variable-aware schemas with cleaner syntax.
  """

  defmacro defschema(name, do: block) do
    quote do
      defmodule unquote(name) do
        import Sinter.Variables
        import Sinter.DSL.Helpers
        
        # Collect field definitions
        @fields []
        
        unquote(block)
        
        # Create the schema
        @schema Sinter.Schema.define(@fields)
        
        def schema, do: @schema
        def variables, do: @schema.variables
        def validate(data), do: Sinter.validate(@schema, data)
        def validate_with_variables(data, config), do: Sinter.validate_with_variables(@schema, data, config)
      end
    end
  end

  defmodule Helpers do
    defmacro field(name, type, opts \\ []) do
      quote do
        @fields [{unquote(name), unquote(type), unquote(opts)} | @fields]
      end
    end

    defmacro variable_choice(name, choices, opts \\ []) do
      quote do
        @fields [Sinter.Variables.choice(unquote(name), unquote(choices), unquote(opts)) | @fields]
      end
    end

    defmacro variable_range(name, range, opts \\ []) do
      quote do
        @fields [Sinter.Variables.range(unquote(name), unquote(range), unquote(opts)) | @fields]
      end
    end

    defmacro variable_module(name, modules, opts \\ []) do
      quote do
        @fields [Sinter.Variables.module(unquote(name), unquote(modules), unquote(opts)) | @fields]
      end
    end
  end
end
```

## Usage Examples

### Basic Variable Schema Definition
```elixir
# Using the core API
schema = Sinter.Schema.define([
  # Regular fields
  {:input, :string, [required: true]},
  {:output, :string, [required: true]},
  
  # Variable fields for optimization
  Sinter.Variables.choice(:adapter, [JSONAdapter, MarkdownAdapter, ChatAdapter]),
  Sinter.Variables.range(:temperature, {0.0, 2.0}, default: 0.7),
  Sinter.Variables.module(:strategy, [Predict, CoT, PoT], behavior: DSPEx.Strategy)
])

# Extract variables for optimizer
variable_space = Sinter.Variables.extract_variable_space(schema)
# => [
#   %{name: :adapter, type: :discrete, constraints: %{choices: [...]}, ...},
#   %{name: :temperature, type: :continuous, constraints: %{range: {0.0, 2.0}}, ...},
#   %{name: :strategy, type: :discrete, constraints: %{choices: [...], behavior: DSPEx.Strategy}, ...}
# ]

# Validate with variable configuration
variable_config = %{
  adapter: JSONAdapter,
  temperature: 0.8,
  strategy: CoT
}

data = %{
  input: "What is the capital of France?",
  output: "The capital of France is Paris."
}

{:ok, validated} = Sinter.validate_with_variables(schema, data, variable_config)
```

### Using the Optional DSL
```elixir
# Using the cleaner DSL syntax
defmodule MyProgramSchema do
  use Sinter.DSL

  defschema do
    # Regular fields
    field :input, :string, required: true
    field :output, :string, required: true
    
    # Variable fields
    variable_choice :adapter, [JSONAdapter, MarkdownAdapter, ChatAdapter]
    variable_range :temperature, {0.0, 2.0}, default: 0.7
    variable_module :strategy, [Predict, CoT, PoT], behavior: DSPEx.Strategy
  end
end

# Usage
{:ok, validated} = MyProgramSchema.validate_with_variables(data, variable_config)
variables = MyProgramSchema.variables()
```

### Integration with Existing ElixirML
```elixir
# Convert existing ElixirML.Variable to Sinter
elixir_ml_var = %ElixirML.Variable{
  name: :temperature,
  type: :float,
  constraints: %{range: {0.0, 2.0}},
  default: 0.7
}

sinter_field = Sinter.ElixirML.from_elixir_ml_variable(elixir_ml_var)
# => {:temperature, :variable_range, [variable: true, range: {0.0, 2.0}, default: 0.7]}

# Create schema from ElixirML Variable.Space
variable_space = %ElixirML.Variable.Space{variables: %{temp: elixir_ml_var}}
schema = Sinter.ElixirML.schema_from_variable_space(variable_space)
```

## Migration Strategy

### Step 1: Add Enhanced Sinter to Dependencies
```elixir
# mix.exs
def deps do
  [
    {:sinter, path: "../sinter"},  # Enhanced version
    # ... other deps
  ]
end
```

### Step 2: Gradual ElixirML.Schema Replacement
```elixir
# Before (ElixirML custom)
schema = ElixirML.Schema.define([
  {:temperature, :probability, required: false, default: 0.7},
  {:response, :model_response, required: true}
])

# After (Enhanced Sinter)
schema = Sinter.Schema.define([
  {:temperature, :probability, [default: 0.7]},
  {:response, :model_response, [required: true]}
])
```

### Step 3: Variable System Integration
```elixir
# Add variable support to existing schemas
schema = Sinter.Schema.define([
  {:input, :string, [required: true]},
  {:output, :string, [required: true]},
  
  # Convert fixed parameters to variables
  Sinter.Variables.choice(:adapter, [JSONAdapter, MarkdownAdapter]),
  Sinter.Variables.range(:temperature, {0.0, 2.0})
])
```

## Testing Strategy

### Unit Tests for Variable System
```elixir
# test/sinter/variables_test.exs
defmodule Sinter.VariablesTest do
  use ExUnit.Case
  
  describe "variable definition" do
    test "defines choice variable correctly" do
      field = Sinter.Variables.choice(:adapter, [JSON, Markdown])
      assert {:adapter, :variable_choice, opts} = field
      assert Keyword.get(opts, :variable) == true
      assert Keyword.get(opts, :choices) == [JSON, Markdown]
    end
    
    test "defines range variable correctly" do
      field = Sinter.Variables.range(:temp, {0.0, 1.0})
      assert {:temp, :variable_range, opts} = field
      assert Keyword.get(opts, :range) == {0.0, 1.0}
    end
  end
  
  describe "variable validation" do
    test "validates choice variables" do
      schema = Sinter.Schema.define([
        Sinter.Variables.choice(:adapter, [JSON, Markdown])
      ])
      
      config = %{adapter: JSON}
      data = %{}
      
      assert {:ok, _} = Sinter.validate_with_variables(schema, data, config)
    end
    
    test "rejects invalid choice values" do
      schema = Sinter.Schema.define([
        Sinter.Variables.choice(:adapter, [JSON, Markdown])
      ])
      
      config = %{adapter: InvalidAdapter}
      data = %{}
      
      assert {:error, _} = Sinter.validate_with_variables(schema, data, config)
    end
  end
end
```

### Integration Tests with ElixirML
```elixir
# test/sinter/elixir_ml_integration_test.exs
defmodule Sinter.ElixirMLIntegrationTest do
  use ExUnit.Case
  
  test "converts ElixirML.Variable to Sinter field" do
    var = %ElixirML.Variable{
      name: :temperature,
      type: :float,
      constraints: %{range: {0.0, 2.0}},
      default: 0.7
    }
    
    field = Sinter.ElixirML.from_elixir_ml_variable(var)
    assert {:temperature, :variable_range, opts} = field
    assert Keyword.get(opts, :range) == {0.0, 2.0}
    assert Keyword.get(opts, :default) == 0.7
  end
  
  test "creates schema from variable space" do
    var = %ElixirML.Variable{name: :temp, type: :float, constraints: %{range: {0.0, 1.0}}}
    space = %ElixirML.Variable.Space{variables: %{temp: var}}
    
    schema = Sinter.ElixirML.schema_from_variable_space(space)
    assert length(schema.variables) == 1
  end
end
```

## Implementation Timeline

### Week 1: Core Variable Types
- [ ] Add variable-aware types to `sinter/lib/sinter/types.ex`
- [ ] Add ML-specific types (embedding, probability, etc.)
- [ ] Add variable-specific constraints
- [ ] Unit tests for all new types

### Week 2: Variable-Aware Schema System
- [ ] Enhance `Sinter.Schema` with variable support
- [ ] Implement `validate_with_variables/3`
- [ ] Create `Sinter.Variables` helper module
- [ ] Integration tests for variable system

### Week 3: ElixirML Integration Bridge
- [ ] Create `Sinter.ElixirML` integration module
- [ ] Bidirectional conversion between ElixirML.Variable and Sinter
- [ ] Schema creation from ElixirML Variable.Space
- [ ] Test ElixirML integration thoroughly

### Week 4: Developer Experience & Polish
- [ ] Enhanced error messages for variables
- [ ] Optional DSL for cleaner syntax
- [ ] Migration documentation
- [ ] Performance testing and optimization

## Success Criteria

1. **✅ Enhanced Sinter supports all Variable System requirements**
2. **✅ Seamless ElixirML.Variable integration**
3. **✅ Variable-aware validation working correctly**
4. **✅ Clear migration path from ElixirML.Schema**
5. **✅ Performance equivalent to current implementation**
6. **✅ Comprehensive test coverage**
7. **✅ Developer-friendly error messages**
8. **✅ Documentation and examples complete**

## Benefits

### ✅ **Focused Enhancement**
- Builds on proven Sinter foundation
- Adds only essential Variable System features
- No architectural complexity or scope creep

### ✅ **Revolutionary Capability**
- Enables automatic optimization across all parameter types
- Solves the exact DSPy community challenge
- Universal optimizer compatibility

### ✅ **Seamless Migration**
- Clear upgrade path from ElixirML.Schema
- Backward compatibility during transition
- Gradual adoption possible

### ✅ **Production Ready**
- Type-safe variable definitions
- Comprehensive validation
- Excellent error messages
- Battle-tested foundation

This enhancement strategy transforms Sinter into the type-safe foundation for DSPEx's revolutionary Variable System while maintaining its core simplicity and reliability. The Variable System will differentiate DSPEx from DSPy and position it as the most advanced optimization framework in the LLM space.