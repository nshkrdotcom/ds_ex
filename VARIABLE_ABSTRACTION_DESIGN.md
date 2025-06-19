# DSPEx Variable Abstraction System Design

## Executive Summary

This document presents a comprehensive design for implementing a Variable abstraction system in DSPEx, inspired by DSPy creator Omar Khattab's vision for decoupled parameter optimization. The system enables any optimizer to tune any discrete parameter automatically, including module selection (JSON vs MD tool calling, Predict vs CoT vs PoT) and configuration optimization.

## Design Objectives

### Primary Goals
1. **Unified Parameter Interface**: Single abstraction for all tunable parameters
2. **Optimizer Agnostic**: Any optimizer can tune any parameter type
3. **Automatic Module Selection**: AI-driven choice between adapters, strategies, and modules
4. **Configuration Optimization**: Automated parameter tuning with evaluation-driven selection
5. **Type Safety**: Compile-time and runtime validation of parameter configurations

### Target Use Cases
```elixir
# Automatic adapter selection with evaluation
program = DSPEx.Predict.new(signature)
  |> DSPEx.Variable.define(:adapter, choices: [:json_tool, :markdown_tool])
  |> DSPEx.Variable.define(:reasoning, choices: [:predict, :cot, :pot])
  |> DSPEx.Variable.define(:temperature, range: {0.1, 1.5})

# Optimizer automatically finds best combination
{:ok, optimized} = DSPEx.Teleprompter.SIMBA.compile(program, training_data, metric_fn)
```

## Architecture Design

### Core Variable System

#### 1. Variable Definition Types

```elixir
defmodule DSPEx.Variable do
  @type variable_type :: :float | :integer | :choice | :module | :struct | :boolean

  defstruct [
    :name,                    # Variable identifier
    :type,                    # Variable type
    :default,                 # Default value
    :constraints,             # Type-specific constraints
    :description,             # Human-readable description
    :dependencies,            # Variable dependencies
    :metadata                 # Additional metadata
  ]

  @doc "Define a continuous parameter variable"
  def float(name, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :float,
      default: Keyword.get(opts, :default, 0.5),
      constraints: %{
        range: Keyword.get(opts, :range, {0.0, 1.0}),
        precision: Keyword.get(opts, :precision, 0.01)
      },
      description: Keyword.get(opts, :description)
    }
  end

  @doc "Define a discrete choice variable"
  def choice(name, choices, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :choice,
      default: Keyword.get(opts, :default, List.first(choices)),
      constraints: %{
        choices: choices,
        allow_custom: Keyword.get(opts, :allow_custom, false)
      },
      description: Keyword.get(opts, :description)
    }
  end

  @doc "Define a module selection variable"
  def module(name, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :module,
      default: Keyword.get(opts, :default),
      constraints: %{
        modules: Keyword.get(opts, :modules, []),
        behavior: Keyword.get(opts, :behavior),
        capabilities: Keyword.get(opts, :capabilities, [])
      },
      description: Keyword.get(opts, :description)
    }
  end
end
```

#### 2. Variable Space Definition

```elixir
defmodule DSPEx.Variable.Space do
  @moduledoc """
  Defines a search space for optimization containing multiple variables
  with their relationships and constraints.
  """

  defstruct [
    :variables,               # Map of variable_name => Variable
    :dependencies,            # Variable dependency graph
    :constraints,             # Cross-variable constraints
    :metadata                 # Space-level metadata
  ]

  def new(variables \\ []) do
    %__MODULE__{
      variables: Map.new(variables, fn var -> {var.name, var} end),
      dependencies: %{},
      constraints: [],
      metadata: %{}
    }
  end

  def add_variable(space, variable) do
    %{space | variables: Map.put(space.variables, variable.name, variable)}
  end

  def add_dependency(space, from_var, to_var, condition) do
    dependencies = Map.update(space.dependencies, from_var, [to_var], &[to_var | &1])
    %{space | dependencies: dependencies}
  end
end
```

### Integration with DSPEx Components

#### 1. Program-Level Variable Integration

```elixir
defmodule DSPEx.Program.Variabilized do
  @moduledoc """
  Extension to DSPEx.Program that adds Variable support
  """

  defmacro __using__(_opts) do
    quote do
      import DSPEx.Variable
      
      @variables %{}
      @before_compile DSPEx.Program.Variabilized
      
      def variable(name, type, opts \\ []) do
        var = DSPEx.Variable.new(name, type, opts)
        Module.put_attribute(__MODULE__, :variables, 
          Map.put(@variables, name, var))
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __variables__, do: @variables
      
      def variable_space do
        DSPEx.Variable.Space.new(Map.values(@variables))
      end
    end
  end
end
```

#### 2. Enhanced Predict Module

```elixir
defmodule DSPEx.Predict.Variable do
  @moduledoc """
  Variable-aware version of DSPEx.Predict that supports
  automatic parameter optimization
  """

  use DSPEx.Program.Variabilized

  # Define standard LLM parameters as variables
  variable :temperature, :float, range: {0.0, 2.0}, default: 0.7
  variable :max_tokens, :integer, range: {1, 4000}, default: 1000
  variable :model, :choice, choices: ["gpt-4", "gpt-3.5-turbo", "gemini-pro"]
  variable :provider, :choice, choices: [:openai, :anthropic, :google]
  
  # Define reasoning strategy as variable
  variable :reasoning_strategy, :module,
    modules: [DSPEx.Reasoning.Predict, DSPEx.Reasoning.CoT, DSPEx.Reasoning.PoT],
    behavior: DSPEx.Reasoning.Strategy
  
  # Define adapter selection as variable
  variable :adapter, :module,
    modules: [DSPEx.Adapter.JSON, DSPEx.Adapter.Markdown],
    behavior: DSPEx.Adapter

  def forward(signature, inputs, variable_config \\ %{}) do
    # Resolve variables to concrete values
    resolved_config = resolve_variables(variable_config)
    
    # Use resolved configuration for prediction
    reasoning_strategy = resolved_config.reasoning_strategy
    adapter = resolved_config.adapter
    
    reasoning_strategy.forward(signature, inputs, resolved_config)
    |> adapter.format_response()
  end

  defp resolve_variables(config) do
    variable_space().variables
    |> Enum.reduce(%{}, fn {name, variable}, acc ->
      value = Map.get(config, name, variable.default)
      Map.put(acc, name, resolve_variable_value(variable, value))
    end)
  end
end
```

### Optimizer Integration

#### 1. Variable-Aware SIMBA

```elixir
defmodule DSPEx.Teleprompter.SIMBA.Variable do
  @moduledoc """
  Enhanced SIMBA that can optimize over Variable spaces
  """

  def compile(program, training_data, metric_fn, opts \\ []) do
    variable_space = program.variable_space()
    
    if Enum.empty?(variable_space.variables) do
      # Fallback to standard SIMBA
      DSPEx.Teleprompter.SIMBA.compile(program, training_data, metric_fn, opts)
    else
      # Variable-aware optimization
      optimize_with_variables(program, training_data, metric_fn, variable_space, opts)
    end
  end

  defp optimize_with_variables(program, training_data, metric_fn, variable_space, opts) do
    # Create search space for variables
    search_space = create_search_space(variable_space)
    
    # Sample variable configurations
    configurations = sample_configurations(search_space, opts)
    
    # Evaluate each configuration
    evaluated_configs = evaluate_configurations(
      program, training_data, metric_fn, configurations
    )
    
    # Select best configuration and update program
    best_config = select_best_configuration(evaluated_configs)
    updated_program = apply_variable_configuration(program, best_config)
    
    {:ok, updated_program}
  end

  defp sample_configurations(search_space, opts) do
    num_samples = Keyword.get(opts, :num_variable_samples, 10)
    
    1..num_samples
    |> Enum.map(fn _ -> 
      sample_single_configuration(search_space)
    end)
  end

  defp sample_single_configuration(search_space) do
    search_space.variables
    |> Enum.reduce(%{}, fn {name, variable}, config ->
      value = sample_variable_value(variable)
      Map.put(config, name, value)
    end)
  end

  defp sample_variable_value(%{type: :float, constraints: %{range: {min, max}}}) do
    min + :rand.uniform() * (max - min)
  end

  defp sample_variable_value(%{type: :choice, constraints: %{choices: choices}}) do
    Enum.random(choices)
  end

  defp sample_variable_value(%{type: :module, constraints: %{modules: modules}}) do
    Enum.random(modules)
  end
end
```

#### 2. Variable-Aware BEACON

```elixir
defmodule DSPEx.Teleprompter.BEACON.Variable do
  @moduledoc """
  Bayesian optimization over Variable spaces
  """

  def compile(program, training_data, metric_fn, opts \\ []) do
    variable_space = program.variable_space()
    
    # Create Bayesian optimization search space
    bo_space = create_bayesian_space(variable_space)
    
    # Run Bayesian optimization
    optimizer = initialize_bayesian_optimizer(bo_space, opts)
    
    best_config = run_bayesian_optimization(
      optimizer, program, training_data, metric_fn, opts
    )
    
    # Apply best configuration to program
    optimized_program = apply_variable_configuration(program, best_config)
    
    {:ok, optimized_program}
  end

  defp create_bayesian_space(variable_space) do
    variable_space.variables
    |> Enum.map(fn {name, variable} ->
      case variable.type do
        :float -> 
          {name, :continuous, variable.constraints.range}
        :integer -> 
          {name, :discrete_numeric, variable.constraints.range}
        :choice -> 
          {name, :categorical, variable.constraints.choices}
        :module ->
          {name, :categorical, variable.constraints.modules}
      end
    end)
  end
end
```

### Automatic Evaluation Framework

#### 1. Configuration Evaluator

```elixir
defmodule DSPEx.Variable.Evaluator do
  @moduledoc """
  Evaluates different variable configurations using multiple metrics
  """

  def evaluate_configuration(program, training_data, metric_fn, config) do
    # Apply configuration to program
    configured_program = apply_configuration(program, config)
    
    # Run evaluation
    results = run_evaluation(configured_program, training_data, metric_fn)
    
    # Collect additional metrics
    %{
      accuracy: results.accuracy,
      latency: results.latency,
      cost: calculate_cost(results),
      configuration: config,
      metadata: results.metadata
    }
  end

  defp calculate_cost(results) do
    base_cost = results.token_usage * get_token_cost(results.provider, results.model)
    
    # Add latency cost if applicable
    latency_penalty = if results.latency > 5000, do: 0.1, else: 0.0
    
    base_cost + latency_penalty
  end

  def multi_objective_evaluation(program, training_data, configs, objectives \\ [:accuracy, :cost, :latency]) do
    configs
    |> Enum.map(fn config ->
      evaluation = evaluate_configuration(program, training_data, &identity/2, config)
      
      objective_scores = objectives
      |> Enum.map(fn objective -> 
        {objective, Map.get(evaluation, objective, 0.0)}
      end)
      |> Map.new()
      
      %{config: config, scores: objective_scores, pareto_rank: nil}
    end)
    |> calculate_pareto_ranking()
  end
end
```

### Advanced Variable Features

#### 1. Conditional Variables

```elixir
defmodule DSPEx.Variable.Conditional do
  def define_conditional_variable(name, condition_var, condition_value, then_var, else_var) do
    %DSPEx.Variable{
      name: name,
      type: :conditional,
      constraints: %{
        condition: {condition_var, condition_value},
        then_variable: then_var,
        else_variable: else_var
      }
    }
  end

  # Example: temperature only matters for certain models
  def temperature_conditional do
    define_conditional_variable(
      :effective_temperature,
      :model, "gpt-4",
      DSPEx.Variable.float(:temperature, range: {0.0, 2.0}),
      DSPEx.Variable.float(:temperature, range: {0.7, 0.7})  # Fixed for other models
    )
  end
end
```

#### 2. Variable Composition

```elixir
defmodule DSPEx.Variable.Composite do
  def define_provider_bundle(provider_name, config_map) do
    %DSPEx.Variable{
      name: :"#{provider_name}_bundle",
      type: :composite,
      constraints: %{
        variables: config_map,
        activation_condition: {:provider, provider_name}
      }
    }
  end

  # Example: Provider-specific configuration bundles
  def openai_bundle do
    define_provider_bundle(:openai, %{
      model: DSPEx.Variable.choice(:model, ["gpt-4", "gpt-3.5-turbo"]),
      temperature: DSPEx.Variable.float(:temperature, range: {0.0, 2.0}),
      max_tokens: DSPEx.Variable.integer(:max_tokens, range: {100, 4000})
    })
  end
end
```

## Implementation Roadmap

### Phase 1: Core Variable System (Week 1-2)
- [ ] Implement `DSPEx.Variable` module with type system
- [ ] Create `DSPEx.Variable.Space` for search space definition
- [ ] Add variable validation and constraint checking
- [ ] Implement basic variable resolution

### Phase 2: Program Integration (Week 3-4)
- [ ] Create `DSPEx.Program.Variabilized` mixin
- [ ] Extend `DSPEx.Predict` with variable support
- [ ] Add variable-aware configuration resolution
- [ ] Implement configuration application logic

### Phase 3: Optimizer Integration (Week 5-6)
- [ ] Enhance SIMBA with variable optimization
- [ ] Add Bayesian optimization for variables in BEACON
- [ ] Implement configuration sampling strategies
- [ ] Create evaluation and selection logic

### Phase 4: Advanced Features (Week 7-8)
- [ ] Implement conditional variables
- [ ] Add composite variable support
- [ ] Create multi-objective optimization
- [ ] Add variable dependency management

### Phase 5: Validation and Documentation (Week 9-10)
- [ ] Comprehensive testing of all variable types
- [ ] Performance benchmarking
- [ ] Integration testing with existing DSPEx features
- [ ] Complete documentation and examples

## Success Metrics

### Technical Metrics
- **Coverage**: All major DSPEx parameters can be defined as variables
- **Performance**: Variable optimization adds <20% overhead to base optimization
- **Compatibility**: Existing DSPEx programs work unchanged
- **Flexibility**: New variable types can be added without core changes

### User Experience Metrics
- **Ease of Use**: Converting hardcoded parameters to variables requires <5 lines of code
- **Discovery**: System automatically identifies promising parameter configurations
- **Transparency**: Users can understand why certain configurations were selected

### Optimization Quality Metrics
- **Effectiveness**: Variable optimization finds better configurations than manual tuning
- **Efficiency**: Converges to good configurations faster than grid search
- **Robustness**: Works consistently across different problem domains

This Variable abstraction system would position DSPEx as the most advanced parameter optimization framework in the DSPy ecosystem, enabling automatic discovery of optimal configurations across all aspects of LLM program design.