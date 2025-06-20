# DSPy Variable Abstraction for Elixir Port

## Overview

The Variable abstraction in the Elixir port of DSPy provides a unified way to declare tunable parameters that can be optimized by any optimizer, regardless of whether they represent prompts, weights, or other discrete choices. This design takes advantage of Elixir's powerful metaprogramming capabilities and actor model to create a clean, composable system.

## Core Design Principles

1. **Separation of Concerns**: Variables are declared independently from optimizers
2. **Type Safety**: Leverage Elixir's type system and behaviours
3. **Composability**: Variables can be composed and transformed
4. **Observability**: All variable changes are trackable through the actor system
5. **Immutability**: Variable updates create new versions, maintaining history

## API Specification

### Variable Behaviour

```elixir
defmodule DSPy.Variable do
  @moduledoc """
  Behaviour for all DSPy variables that can be optimized.
  """
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    type: variable_type(),
    value: any(),
    constraints: list(constraint()),
    metadata: map(),
    version: non_neg_integer(),
    history: list(version_entry())
  }
  
  @type variable_type :: :string | :weight | :discrete | :continuous | :structured
  @type constraint :: {constraint_type(), any()}
  @type constraint_type :: :range | :options | :pattern | :length | :custom
  @type version_entry :: {non_neg_integer(), any(), DateTime.t(), map()}
  
  @callback validate(value :: any(), constraints :: list(constraint())) :: 
    {:ok, any()} | {:error, String.t()}
  
  @callback transform(value :: any(), transformation :: map()) :: 
    {:ok, any()} | {:error, String.t()}
  
  @callback serialize(value :: any()) :: binary()
  @callback deserialize(binary()) :: {:ok, any()} | {:error, String.t()}
end
```

### Variable Types

```elixir
defmodule DSPy.Variable.String do
  @moduledoc """
  String variable for prompts, instructions, and text parameters.
  """
  use DSPy.Variable
  
  defstruct [:id, :name, :value, :constraints, :metadata, :version, :history,
             template: nil, 
             format: :plain,
             max_length: nil,
             min_length: nil]
  
  @impl true
  def validate(value, constraints) do
    with :ok <- validate_length(value, constraints),
         :ok <- validate_pattern(value, constraints),
         :ok <- validate_template(value, constraints) do
      {:ok, value}
    end
  end
end

defmodule DSPy.Variable.Weight do
  @moduledoc """
  Numeric weight variable for model parameters.
  """
  use DSPy.Variable
  
  defstruct [:id, :name, :value, :constraints, :metadata, :version, :history,
             shape: nil,
             dtype: :f32,
             initialization: :random_normal,
             regularization: nil]
  
  @impl true
  def validate(value, constraints) do
    with :ok <- validate_shape(value, constraints),
         :ok <- validate_range(value, constraints) do
      {:ok, value}
    end
  end
end

defmodule DSPy.Variable.Discrete do
  @moduledoc """
  Discrete choice variable for selecting from options.
  """
  use DSPy.Variable
  
  defstruct [:id, :name, :value, :constraints, :metadata, :version, :history,
             options: [],
             probabilities: nil,
             allow_multiple: false]
  
  @impl true
  def validate(value, constraints) do
    options = Keyword.get(constraints, :options, [])
    if value in options do
      {:ok, value}
    else
      {:error, "Value must be one of: #{inspect(options)}"}
    end
  end
end
```

### Variable Declaration DSL

```elixir
defmodule DSPy.Module do
  @moduledoc """
  Enhanced module macro with variable declarations.
  """
  
  defmacro __using__(_opts) do
    quote do
      import DSPy.Module
      import DSPy.Variable.DSL
      
      Module.register_attribute(__MODULE__, :variables, accumulate: true)
      Module.register_attribute(__MODULE__, :predictors, accumulate: true)
      
      @before_compile DSPy.Module
    end
  end
  
  defmacro variable(name, type, opts \\ []) do
    quote do
      @variables {unquote(name), unquote(type), unquote(opts)}
    end
  end
end

# Example usage
defmodule ChainOfThought do
  use DSPy.Module
  
  # Declare variables
  variable :reasoning_prompt, :string,
    default: "Let's think step by step",
    constraints: [
      length: [min: 10, max: 100],
      pattern: ~r/think|reason|analyze/i
    ]
  
  variable :temperature, :continuous,
    default: 0.7,
    constraints: [
      range: {0.0, 2.0}
    ]
  
  variable :reasoning_style, :discrete,
    default: :analytical,
    options: [:analytical, :creative, :systematic, :intuitive]
  
  variable :attention_weights, :weight,
    shape: {768, 768},
    initialization: :xavier_uniform
  
  def forward(state, inputs) do
    # Variables are automatically accessible
    prompt = get_variable(state, :reasoning_prompt)
    temp = get_variable(state, :temperature)
    style = get_variable(state, :reasoning_style)
    
    # Use variables in computation
    # ...
  end
end
```

### Variable Registry

```elixir
defmodule DSPy.Variable.Registry do
  @moduledoc """
  GenServer that manages all variables in the system.
  """
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def register_variable(module, name, type, opts) do
    GenServer.call(__MODULE__, {:register, module, name, type, opts})
  end
  
  def get_variable(module, name) do
    GenServer.call(__MODULE__, {:get, module, name})
  end
  
  def update_variable(module, name, value, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update, module, name, value, metadata})
  end
  
  def get_variables_for_module(module) do
    GenServer.call(__MODULE__, {:get_all, module})
  end
  
  def get_variables_by_type(type) do
    GenServer.call(__MODULE__, {:get_by_type, type})
  end
  
  # Implementation handles versioning, history, and notifications
end
```

### Optimizer Integration

```elixir
defmodule DSPy.Optimizer.Behaviour do
  @moduledoc """
  Enhanced optimizer behaviour with variable support.
  """
  
  @callback compile(program :: module(), opts :: keyword()) :: 
    {:ok, optimized_program :: module()} | {:error, term()}
  
  @callback optimize_variables(variables :: list(DSPy.Variable.t()), opts :: keyword()) ::
    {:ok, updates :: list({variable_id :: String.t(), new_value :: any()})} | 
    {:error, term()}
    
  @callback supports_variable_type?(type :: atom()) :: boolean()
end

defmodule DSPy.Optimizer.VariableOptimizer do
  @moduledoc """
  Mixin for optimizers to handle variable optimization.
  """
  
  defmacro __using__(_opts) do
    quote do
      def optimize_program(program, trainset, opts \\ []) do
        # Get all variables from the program
        variables = DSPy.Variable.Registry.get_variables_for_module(program)
        
        # Group by type for efficient optimization
        grouped = Enum.group_by(variables, & &1.type)
        
        # Optimize each group
        updates = Enum.flat_map(grouped, fn {type, vars} ->
          if supports_variable_type?(type) do
            {:ok, type_updates} = optimize_variable_group(type, vars, trainset, opts)
            type_updates
          else
            []
          end
        end)
        
        # Apply updates atomically
        apply_variable_updates(program, updates)
      end
      
      defp optimize_variable_group(type, variables, trainset, opts) do
        strategy = get_optimization_strategy(type)
        strategy.optimize(variables, trainset, opts)
      end
    end
  end
end
```

### Example Optimizers

```elixir
defmodule DSPy.Optimizer.BayesianOptimizer do
  @moduledoc """
  Bayesian optimization for continuous and discrete variables.
  """
  use DSPy.Optimizer.VariableOptimizer
  @behaviour DSPy.Optimizer.Behaviour
  
  def supports_variable_type?(type) when type in [:continuous, :discrete], do: true
  def supports_variable_type?(_), do: false
  
  def optimize_variables(variables, opts) do
    # Bayesian optimization logic
    acquisition_fn = opts[:acquisition_fn] || :expected_improvement
    
    surrogate_model = build_surrogate_model(variables)
    
    candidates = generate_candidates(variables, surrogate_model, acquisition_fn)
    
    # Evaluate candidates
    results = Enum.map(candidates, fn candidate ->
      score = evaluate_candidate(candidate, opts[:metric])
      {candidate, score}
    end)
    
    # Select best
    best = Enum.max_by(results, fn {_, score} -> score end)
    {:ok, best}
  end
end

defmodule DSPy.Optimizer.PromptOptimizer do
  @moduledoc """
  Specialized optimizer for string/prompt variables.
  """
  use DSPy.Optimizer.VariableOptimizer
  @behaviour DSPy.Optimizer.Behaviour
  
  def supports_variable_type?(:string), do: true
  def supports_variable_type?(_), do: false
  
  def optimize_variables(variables, opts) do
    # Use LLM to generate prompt variants
    variants = Enum.flat_map(variables, fn var ->
      generate_prompt_variants(var, opts[:num_variants] || 10)
    end)
    
    # Evaluate variants
    scored = Enum.map(variants, fn {var_id, variant} ->
      score = evaluate_prompt(variant, opts[:trainset], opts[:metric])
      {var_id, variant, score}
    end)
    
    # Select best per variable
    updates = scored
    |> Enum.group_by(fn {var_id, _, _} -> var_id end)
    |> Enum.map(fn {var_id, group} ->
      {_, best_variant, _} = Enum.max_by(group, fn {_, _, score} -> score end)
      {var_id, best_variant}
    end)
    
    {:ok, updates}
  end
  
  defp generate_prompt_variants(variable, num_variants) do
    # Use an LLM to generate variations
    prompt = """
    Generate #{num_variants} variations of this prompt:
    "#{variable.value}"
    
    Constraints: #{inspect(variable.constraints)}
    Each variation should maintain the same intent but use different phrasing.
    """
    
    # Call LLM and parse results
    # ...
  end
end
```

### Variable Composition

```elixir
defmodule DSPy.Variable.Composite do
  @moduledoc """
  Compose multiple variables into complex structures.
  """
  
  defstruct [:variables, :composition_fn, :constraints]
  
  def compose(variables, composition_fn, opts \\ []) do
    %__MODULE__{
      variables: variables,
      composition_fn: composition_fn,
      constraints: opts[:constraints] || []
    }
  end
  
  def evaluate(composite, variable_values) do
    composite.composition_fn.(variable_values)
  end
end

# Example: Composing a complex prompt from multiple variables
defmodule AdvancedChainOfThought do
  use DSPy.Module
  
  variable :task_description, :string
  variable :reasoning_style, :discrete, options: [:analytical, :creative]
  variable :output_format, :string
  
  composite_variable :full_prompt, [:task_description, :reasoning_style, :output_format],
    fn values ->
      """
      Task: #{values.task_description}
      
      Approach this #{values.reasoning_style}ly.
      
      #{values.output_format}
      """
    end
end
```

### Variable Constraints and Validation

```elixir
defmodule DSPy.Variable.Constraints do
  @moduledoc """
  Constraint system for variables.
  """
  
  def validate_constraint(value, {:range, {min, max}}) do
    if value >= min and value <= max do
      :ok
    else
      {:error, "Value #{value} outside range [#{min}, #{max}]"}
    end
  end
  
  def validate_constraint(value, {:options, allowed}) do
    if value in allowed do
      :ok
    else
      {:error, "Value must be one of: #{inspect(allowed)}"}
    end
  end
  
  def validate_constraint(value, {:pattern, regex}) do
    if Regex.match?(regex, to_string(value)) do
      :ok
    else
      {:error, "Value does not match pattern: #{inspect(regex)}"}
    end
  end
  
  def validate_constraint(value, {:custom, validator_fn}) do
    validator_fn.(value)
  end
  
  def validate_all(value, constraints) do
    Enum.reduce_while(constraints, :ok, fn constraint, _ ->
      case validate_constraint(value, constraint) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
```

### Variable History and Versioning

```elixir
defmodule DSPy.Variable.History do
  @moduledoc """
  Track variable changes over time.
  """
  
  defstruct [:variable_id, :entries, :max_entries]
  
  def new(variable_id, max_entries \\ 100) do
    %__MODULE__{
      variable_id: variable_id,
      entries: [],
      max_entries: max_entries
    }
  end
  
  def add_entry(history, value, metadata) do
    entry = {
      System.unique_integer([:positive]),
      value,
      DateTime.utc_now(),
      metadata
    }
    
    entries = [entry | history.entries] |> Enum.take(history.max_entries)
    %{history | entries: entries}
  end
  
  def get_trajectory(history, metric_fn) do
    history.entries
    |> Enum.reverse()
    |> Enum.map(fn {version, value, time, meta} ->
      score = meta[:score] || metric_fn.(value)
      %{version: version, value: value, time: time, score: score}
    end)
  end
end
```

### Integration with Existing DSPy Components

```elixir
defmodule DSPy.Predict do
  @moduledoc """
  Enhanced Predict with variable support.
  """
  
  defmacro predict(signature, opts \\ []) do
    quote do
      # Check if any variables are referenced in the signature
      variables = extract_variables_from_signature(unquote(signature))
      
      # Create a predictor that uses current variable values
      fn state ->
        # Resolve variable values
        resolved_signature = resolve_signature_variables(
          unquote(signature), 
          state.variables
        )
        
        # Standard prediction logic with resolved values
        DSPy.Predict.Base.predict(resolved_signature, unquote(opts))
      end
    end
  end
end
```

### Variable-Aware Teleprompters

```elixir
defmodule DSPy.Teleprompter.VariableAware do
  @moduledoc """
  Base teleprompter that can optimize variables.
  """
  
  def compile(student, trainset, opts \\ []) do
    # Extract all variables
    variables = DSPy.Variable.Registry.get_variables_for_module(student)
    
    # Separate optimizable variables
    {prompt_vars, other_vars} = Enum.split_with(variables, & &1.type == :string)
    
    # Optimize prompts
    optimized_prompts = optimize_prompts(prompt_vars, trainset, opts)
    
    # Optimize other variables
    optimized_others = optimize_other_variables(other_vars, trainset, opts)
    
    # Create new program with optimized variables
    create_optimized_program(student, optimized_prompts ++ optimized_others)
  end
end
```

## Benefits of This Design

1. **Clean Separation**: Variables are first-class citizens, not buried in optimizer logic
2. **Type Safety**: Elixir's type system ensures variables are used correctly
3. **Extensibility**: New variable types can be added without changing optimizers
4. **Observability**: All changes are tracked through the actor system
5. **Composability**: Variables can be composed into complex structures
6. **Optimizer Agnostic**: Any optimizer can work with any variable type it supports

This design leverages Elixir's strengths while providing a clean, extensible foundation for the variable abstraction that DSPy needs.
