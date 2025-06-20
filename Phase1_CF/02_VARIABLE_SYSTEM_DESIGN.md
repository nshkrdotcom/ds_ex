# Phase 1: Variable System Design
*Revolutionary Universal Parameter Optimization for ElixirML/DSPEx*

## Executive Summary

The Variable System represents the revolutionary core of ElixirML/DSPEx, enabling any optimizer to tune any parameter automatically. This system abstracts all configurable parameters into a unified interface, supporting automatic module selection (JSON vs Markdown adapters, Predict vs CoT vs PoT), configuration optimization, and multi-objective parameter discovery.

## Design Philosophy

### Core Innovation

The Variable System is inspired by DSPy creator Omar Khattab's vision for decoupled parameter optimization. Instead of hardcoding configurations, every parameter becomes a Variable that can be automatically optimized:

```elixir
# Traditional approach - hardcoded configuration
program = DSPEx.Predict.new(signature, client: :openai, temperature: 0.7)

# Variable System approach - automatic optimization
program = DSPEx.Predict.new(signature)
  |> DSPEx.Variable.define(:client, choices: [:openai, :anthropic, :groq])
  |> DSPEx.Variable.define(:temperature, range: {0.1, 1.5})
  |> DSPEx.Variable.define(:adapter, choices: [:json_tool, :markdown_tool])
  |> DSPEx.Variable.define(:reasoning, choices: [:predict, :cot, :pot])

# Optimizer automatically finds best combination
{:ok, optimized} = DSPEx.Teleprompter.SIMBA.compile(program, training_data, metric_fn)
```

### Strategic Advantages

1. **Universal Optimization**: Any parameter can be optimized by any optimizer
2. **Automatic Module Selection**: AI-driven choice between adapters and strategies  
3. **Multi-Objective Intelligence**: Optimize for accuracy, cost, and latency simultaneously
4. **Configuration Discovery**: Automatically discover optimal parameter combinations
5. **Type Safety**: Compile-time and runtime validation of parameter configurations

## Architecture Overview

```
Variable System Architecture
├── Core Variable Abstraction
│   ├── Variable Definition
│   ├── Variable Space Management
│   ├── Configuration Resolution
│   └── Constraint Validation
├── Parameter Types
│   ├── Continuous Variables (temperature, learning_rate)
│   ├── Discrete Variables (model, provider, adapter)
│   ├── Module Variables (reasoning strategy, adapter type)
│   └── Composite Variables (nested configurations)
├── Optimization Integration
│   ├── Optimizer Interface
│   ├── Multi-Objective Evaluation
│   ├── Pareto Frontier Analysis
│   └── Configuration Ranking
├── ML-Specific Features
│   ├── Provider-Model Compatibility
│   ├── Cost-Performance Trade-offs
│   ├── Latency Optimization
│   └── Quality Metrics Integration
└── Developer Experience
    ├── DSL for Variable Definition
    ├── Configuration Visualization
    ├── Performance Analytics
    └── Debugging Tools
```

## Core Variable Abstraction

### 1. Variable Definition

```elixir
defmodule ElixirML.Variable do
  @moduledoc """
  Universal variable abstraction for parameter optimization.
  Enables any optimizer to tune any parameter type.
  """

  @type variable_type :: :float | :integer | :choice | :module | :composite

  defstruct [
    :name,                    # Variable identifier (atom)
    :type,                    # Variable type
    :default,                 # Default value
    :constraints,             # Type-specific constraints
    :description,             # Human-readable description
    :dependencies,            # Variable dependencies
    :metadata,                # Additional metadata
    :optimization_hints       # Hints for optimizers
  ]

  @doc "Create a continuous floating-point variable"
  def float(name, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :float,
      default: Keyword.get(opts, :default, 0.5),
      constraints: %{
        range: Keyword.get(opts, :range, {0.0, 1.0}),
        precision: Keyword.get(opts, :precision, 0.01),
        distribution: Keyword.get(opts, :distribution, :uniform)
      },
      description: Keyword.get(opts, :description),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end

  @doc "Create an integer variable with range constraints"
  def integer(name, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :integer,
      default: Keyword.get(opts, :default, 1),
      constraints: %{
        range: Keyword.get(opts, :range, {1, 100}),
        step: Keyword.get(opts, :step, 1)
      },
      description: Keyword.get(opts, :description),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end

  @doc "Create a discrete choice variable"
  def choice(name, choices, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :choice,
      default: Keyword.get(opts, :default, List.first(choices)),
      constraints: %{
        choices: choices,
        allow_custom: Keyword.get(opts, :allow_custom, false),
        weights: Keyword.get(opts, :weights, nil)
      },
      description: Keyword.get(opts, :description),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end

  @doc "Create a module selection variable"
  def module(name, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :module,
      default: Keyword.get(opts, :default),
      constraints: %{
        modules: Keyword.get(opts, :modules, []),
        behavior: Keyword.get(opts, :behavior),
        capabilities: Keyword.get(opts, :capabilities, []),
        compatibility_matrix: Keyword.get(opts, :compatibility, %{})
      },
      description: Keyword.get(opts, :description),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end

  @doc "Create a composite variable with nested structure"
  def composite(name, variables, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :composite,
      default: Keyword.get(opts, :default, %{}),
      constraints: %{
        variables: variables,
        validation_fn: Keyword.get(opts, :validation)
      },
      description: Keyword.get(opts, :description),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end
end
```

### 2. Variable Space Management

```elixir
defmodule ElixirML.Variable.Space do
  @moduledoc """
  Manages collections of variables with their relationships and constraints.
  Provides the search space for optimization algorithms.
  """

  defstruct [
    :id,                      # Unique identifier
    :name,                    # Human-readable name
    :variables,               # Map of variable_name => Variable
    :dependencies,            # Variable dependency graph
    :constraints,             # Cross-variable constraints
    :metadata,                # Space-level metadata
    :optimization_config      # Optimization-specific configuration
  ]

  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      name: Keyword.get(opts, :name, "VariableSpace"),
      variables: %{},
      dependencies: %{},
      constraints: [],
      metadata: Keyword.get(opts, :metadata, %{}),
      optimization_config: Keyword.get(opts, :optimization_config, %{})
    }
  end

  def add_variable(space, %ElixirML.Variable{} = variable) do
    %{space | variables: Map.put(space.variables, variable.name, variable)}
  end

  def add_dependency(space, from_var, to_var, condition) do
    dependencies = Map.update(space.dependencies, from_var, [to_var], &[to_var | &1])
    %{space | dependencies: dependencies}
  end

  def add_constraint(space, constraint_fn, description \\ nil) do
    constraint = %{
      function: constraint_fn,
      description: description,
      id: generate_constraint_id()
    }
    %{space | constraints: [constraint | space.constraints]}
  end

  def get_variable(space, name) do
    Map.get(space.variables, name)
  end

  def list_variables(space) do
    Map.values(space.variables)
  end

  def variable_count(space) do
    map_size(space.variables)
  end

  def discrete_space_size(space) do
    space.variables
    |> Map.values()
    |> Enum.map(&discrete_variable_size/1)
    |> Enum.reduce(1, &*/2)
  end

  defp discrete_variable_size(%{type: :choice, constraints: %{choices: choices}}) do
    length(choices)
  end

  defp discrete_variable_size(%{type: :module, constraints: %{modules: modules}}) do
    length(modules)
  end

  defp discrete_variable_size(_), do: 1  # Continuous variables don't contribute to discrete size

  def validate_configuration(space, configuration) do
    with {:ok, _} <- validate_all_variables_present(space, configuration),
         {:ok, _} <- validate_variable_values(space, configuration),
         {:ok, _} <- validate_dependencies(space, configuration),
         {:ok, _} <- validate_constraints(space, configuration) do
      {:ok, configuration}
    else
      {:error, _} = error -> error
    end
  end

  defp validate_all_variables_present(space, configuration) do
    required_variables = 
      space.variables
      |> Enum.filter(fn {_name, var} -> 
        var.metadata[:required] || var.default == nil 
      end)
      |> Enum.map(fn {name, _var} -> name end)

    missing_variables = required_variables -- Map.keys(configuration)

    case missing_variables do
      [] -> {:ok, configuration}
      missing -> {:error, "Missing required variables: #{inspect(missing)}"}
    end
  end

  defp validate_variable_values(space, configuration) do
    errors = 
      configuration
      |> Enum.flat_map(fn {var_name, value} ->
        case Map.get(space.variables, var_name) do
          nil -> [%{variable: var_name, error: "Unknown variable"}]
          variable -> 
            case validate_variable_value(variable, value) do
              {:ok, _} -> []
              {:error, error} -> [%{variable: var_name, error: error}]
            end
        end
      end)

    case errors do
      [] -> {:ok, configuration}
      _ -> {:error, "Variable validation errors: #{inspect(errors)}"}
    end
  end

  defp validate_variable_value(%{type: :float, constraints: %{range: {min, max}}}, value) 
       when is_number(value) do
    if value >= min and value <= max do
      {:ok, value}
    else
      {:error, "Value #{value} outside range #{min}..#{max}"}
    end
  end

  defp validate_variable_value(%{type: :choice, constraints: %{choices: choices}}, value) do
    if value in choices do
      {:ok, value}
    else
      {:error, "Value #{inspect(value)} not in choices #{inspect(choices)}"}
    end
  end

  defp validate_variable_value(%{type: :module, constraints: %{modules: modules}}, value) do
    if value in modules do
      {:ok, value}
    else
      {:error, "Module #{inspect(value)} not in allowed modules #{inspect(modules)}"}
    end
  end

  defp validate_variable_value(_variable, value), do: {:ok, value}

  defp validate_dependencies(space, configuration) do
    # Check dependency graph for violations
    errors = 
      space.dependencies
      |> Enum.flat_map(fn {from_var, to_vars} ->
        from_value = Map.get(configuration, from_var)
        
        Enum.flat_map(to_vars, fn to_var ->
          to_value = Map.get(configuration, to_var)
          
          case check_dependency_condition(from_var, from_value, to_var, to_value) do
            true -> []
            false -> [%{from: from_var, to: to_var, error: "Dependency condition violated"}]
          end
        end)
      end)

    case errors do
      [] -> {:ok, configuration}
      _ -> {:error, "Dependency validation errors: #{inspect(errors)}"}
    end
  end

  defp validate_constraints(space, configuration) do
    errors = 
      space.constraints
      |> Enum.flat_map(fn constraint ->
        case constraint.function.(configuration) do
          true -> []
          false -> [%{constraint: constraint.id, error: constraint.description || "Constraint violated"}]
          {:error, error} -> [%{constraint: constraint.id, error: error}]
        end
      end)

    case errors do
      [] -> {:ok, configuration}
      _ -> {:error, "Constraint validation errors: #{inspect(errors)}"}
    end
  end

  defp check_dependency_condition(_from_var, _from_value, _to_var, _to_value) do
    # Simplified dependency checking - in real implementation would be configurable
    true
  end

  defp generate_id(), do: "vs_#{System.unique_integer([:positive])}"
  defp generate_constraint_id(), do: "constraint_#{System.unique_integer([:positive])}"
end
```

## ML-Specific Variable Types

### 1. Provider-Model Variables

```elixir
defmodule ElixirML.Variable.MLTypes do
  @moduledoc """
  ML-specific variable types with built-in compatibility and optimization logic.
  """

  alias ElixirML.Variable

  @doc "Create a provider variable with model compatibility"
  def provider(name, opts \\ []) do
    providers = Keyword.get(opts, :providers, [:openai, :anthropic, :groq, :google])
    
    Variable.choice(name, providers, 
      description: "LLM Provider selection",
      hints: [
        optimization_priority: :cost_performance,
        compatibility_aware: true
      ],
      metadata: %{
        cost_weights: %{
          openai: 1.0,
          anthropic: 1.2,
          groq: 0.3,
          google: 0.8
        },
        performance_weights: %{
          openai: 0.9,
          anthropic: 0.95,
          groq: 0.7,
          google: 0.85
        }
      }
    )
  end

  @doc "Create a model variable with provider compatibility"
  def model(name, opts \\ []) do
    models = Keyword.get(opts, :models, [
      "gpt-4", "gpt-3.5-turbo", "claude-3", "claude-2", 
      "gemini-pro", "llama-2-70b"
    ])
    
    Variable.choice(name, models,
      description: "Model selection",
      hints: [
        depends_on: [:provider],
        compatibility_matrix: true
      ],
      metadata: %{
        compatibility: %{
          openai: ["gpt-4", "gpt-3.5-turbo"],
          anthropic: ["claude-3", "claude-2"],
          google: ["gemini-pro"],
          groq: ["llama-2-70b"]
        },
        capabilities: %{
          "gpt-4" => [:reasoning, :code, :json_mode],
          "claude-3" => [:reasoning, :long_context],
          "gemini-pro" => [:multimodal, :reasoning]
        }
      }
    )
  end

  @doc "Create an adapter variable with capability awareness"
  def adapter(name, opts \\ []) do
    adapters = Keyword.get(opts, :adapters, [
      ElixirML.Adapter.JSON,
      ElixirML.Adapter.Markdown,
      ElixirML.Adapter.Chat
    ])
    
    Variable.module(name,
      modules: adapters,
      behavior: ElixirML.Adapter,
      description: "Response format adapter",
      hints: [
        performance_impact: :medium,
        model_compatibility: true
      ],
      metadata: %{
        capabilities: %{
          ElixirML.Adapter.JSON => [:structured_output, :tool_calling],
          ElixirML.Adapter.Markdown => [:readable_output, :formatting],
          ElixirML.Adapter.Chat => [:conversational, :streaming]
        },
        model_support: %{
          "gpt-4" => [ElixirML.Adapter.JSON, ElixirML.Adapter.Chat],
          "claude-3" => [ElixirML.Adapter.Markdown, ElixirML.Adapter.Chat],
          "gemini-pro" => [ElixirML.Adapter.JSON, ElixirML.Adapter.Markdown]
        }
      }
    )
  end

  @doc "Create a reasoning strategy variable"
  def reasoning_strategy(name, opts \\ []) do
    strategies = Keyword.get(opts, :strategies, [
      ElixirML.Reasoning.Predict,
      ElixirML.Reasoning.ChainOfThought,
      ElixirML.Reasoning.ProgramOfThought,
      ElixirML.Reasoning.ReAct
    ])
    
    Variable.module(name,
      modules: strategies,
      behavior: ElixirML.Reasoning.Strategy,
      description: "Reasoning strategy selection",
      hints: [
        performance_impact: :high,
        accuracy_impact: :high,
        cost_impact: :high
      ],
      metadata: %{
        complexity: %{
          ElixirML.Reasoning.Predict => 1,
          ElixirML.Reasoning.ChainOfThought => 3,
          ElixirML.Reasoning.ProgramOfThought => 5,
          ElixirML.Reasoning.ReAct => 4
        },
        use_cases: %{
          ElixirML.Reasoning.Predict => [:simple_qa, :classification],
          ElixirML.Reasoning.ChainOfThought => [:complex_reasoning, :math],
          ElixirML.Reasoning.ProgramOfThought => [:code_generation, :computation],
          ElixirML.Reasoning.ReAct => [:research, :multi_step]
        }
      }
    )
  end

  @doc "Create temperature variable with model-specific ranges"
  def temperature(name, opts \\ []) do
    Variable.float(name,
      range: Keyword.get(opts, :range, {0.0, 2.0}),
      default: 0.7,
      precision: 0.1,
      description: "Model temperature for response randomness",
      hints: [
        optimization_priority: :accuracy,
        model_dependent: true
      ],
      metadata: %{
        model_ranges: %{
          "gpt-4" => {0.0, 2.0},
          "claude-3" => {0.0, 1.0},
          "gemini-pro" => {0.0, 1.0}
        },
        recommended_ranges: %{
          reasoning: {0.1, 0.3},
          creative: {0.7, 1.2},
          factual: {0.0, 0.3}
        }
      }
    )
  end
end
```

### 2. Multi-Objective Configuration

```elixir
defmodule ElixirML.Variable.MultiObjective do
  @moduledoc """
  Multi-objective optimization support for variable configurations.
  Enables optimization across accuracy, cost, and latency simultaneously.
  """

  defstruct [
    :objectives,              # List of optimization objectives
    :weights,                 # Objective weights
    :constraints,             # Hard constraints
    :pareto_config           # Pareto frontier configuration
  ]

  def new(opts \\ []) do
    %__MODULE__{
      objectives: Keyword.get(opts, :objectives, [:accuracy, :cost, :latency]),
      weights: Keyword.get(opts, :weights, %{accuracy: 0.5, cost: 0.3, latency: 0.2}),
      constraints: Keyword.get(opts, :constraints, []),
      pareto_config: Keyword.get(opts, :pareto_config, %{})
    }
  end

  def evaluate_configuration(multi_objective, variable_space, configuration, evaluation_results) do
    objective_scores = 
      multi_objective.objectives
      |> Enum.map(fn objective ->
        {objective, calculate_objective_score(objective, variable_space, configuration, evaluation_results)}
      end)
      |> Map.new()

    weighted_score = calculate_weighted_score(objective_scores, multi_objective.weights)
    
    %{
      objective_scores: objective_scores,
      weighted_score: weighted_score,
      pareto_rank: calculate_pareto_rank(objective_scores, multi_objective.pareto_config),
      configuration: configuration,
      metadata: %{
        evaluated_at: DateTime.utc_now(),
        variable_space_id: variable_space.id
      }
    }
  end

  defp calculate_objective_score(:accuracy, _variable_space, _configuration, evaluation_results) do
    Map.get(evaluation_results, :accuracy, 0.0)
  end

  defp calculate_objective_score(:cost, variable_space, configuration, evaluation_results) do
    # Calculate cost based on variable configuration
    base_cost = Map.get(evaluation_results, :cost, 0.0)
    
    # Factor in provider costs
    provider_cost_multiplier = case Map.get(configuration, :provider) do
      :openai -> 1.0
      :anthropic -> 1.2
      :groq -> 0.3
      :google -> 0.8
      _ -> 1.0
    end

    # Factor in model costs
    model_cost_multiplier = case Map.get(configuration, :model) do
      "gpt-4" -> 3.0
      "gpt-3.5-turbo" -> 1.0
      "claude-3" -> 2.5
      "gemini-pro" -> 1.5
      _ -> 1.0
    end

    # Factor in reasoning complexity
    reasoning_cost_multiplier = case Map.get(configuration, :reasoning_strategy) do
      ElixirML.Reasoning.Predict -> 1.0
      ElixirML.Reasoning.ChainOfThought -> 2.5
      ElixirML.Reasoning.ProgramOfThought -> 4.0
      ElixirML.Reasoning.ReAct -> 3.5
      _ -> 1.0
    end

    total_cost = base_cost * provider_cost_multiplier * model_cost_multiplier * reasoning_cost_multiplier
    
    # Normalize to 0-1 scale (lower is better, so invert)
    1.0 - min(total_cost / 100.0, 1.0)
  end

  defp calculate_objective_score(:latency, _variable_space, configuration, evaluation_results) do
    base_latency = Map.get(evaluation_results, :latency_ms, 1000.0)
    
    # Factor in provider latency
    provider_latency_multiplier = case Map.get(configuration, :provider) do
      :groq -> 0.3      # Very fast
      :openai -> 1.0    # Baseline
      :google -> 1.2    # Slightly slower
      :anthropic -> 1.5 # Slower
      _ -> 1.0
    end

    # Factor in reasoning complexity latency
    reasoning_latency_multiplier = case Map.get(configuration, :reasoning_strategy) do
      ElixirML.Reasoning.Predict -> 1.0
      ElixirML.Reasoning.ChainOfThought -> 3.0
      ElixirML.Reasoning.ProgramOfThought -> 5.0
      ElixirML.Reasoning.ReAct -> 4.0
      _ -> 1.0
    end

    total_latency = base_latency * provider_latency_multiplier * reasoning_latency_multiplier
    
    # Normalize to 0-1 scale (lower is better, so invert)
    1.0 - min(total_latency / 10000.0, 1.0)
  end

  defp calculate_weighted_score(objective_scores, weights) do
    objective_scores
    |> Enum.map(fn {objective, score} ->
      weight = Map.get(weights, objective, 0.0)
      score * weight
    end)
    |> Enum.sum()
  end

  defp calculate_pareto_rank(objective_scores, _pareto_config) do
    # Simplified Pareto ranking - in real implementation would compare against frontier
    objective_scores
    |> Map.values()
    |> Enum.sum()
    |> Float.round(3)
  end

  def update_pareto_frontier(multi_objective, new_evaluation) do
    # Implementation for maintaining Pareto frontier
    # This would track the set of non-dominated solutions
    multi_objective
  end
end
```

## Integration with DSPEx Components

### 1. Program Variable Integration

```elixir
defmodule ElixirML.Variable.ProgramIntegration do
  @moduledoc """
  Integration layer for adding variable support to DSPEx programs.
  """

  defmacro __using__(_opts) do
    quote do
      import ElixirML.Variable.ProgramIntegration
      
      @variable_space ElixirML.Variable.Space.new()
      @before_compile ElixirML.Variable.ProgramIntegration
    end
  end

  defmacro __before_compile__(env) do
    variable_space = Module.get_attribute(env.module, :variable_space)
    
    quote do
      def __variable_space__, do: unquote(Macro.escape(variable_space))
      
      def variable_space, do: __variable_space__()
      
      def with_variable_configuration(configuration) do
        case ElixirML.Variable.Space.validate_configuration(__variable_space__(), configuration) do
          {:ok, validated_config} ->
            {:ok, apply_variable_configuration(__MODULE__, validated_config)}
          {:error, _} = error ->
            error
        end
      end
    end
  end

  defmacro variable(name, type, opts \\ []) do
    quote do
      variable_def = ElixirML.Variable.unquote(type)(unquote(name), unquote(opts))
      @variable_space ElixirML.Variable.Space.add_variable(@variable_space, variable_def)
    end
  end

  defmacro variable_constraint(constraint_fn, description \\ nil) do
    quote do
      @variable_space ElixirML.Variable.Space.add_constraint(@variable_space, unquote(constraint_fn), unquote(description))
    end
  end

  def apply_variable_configuration(program_module, configuration) do
    # Apply variable configuration to program
    # This would modify the program struct based on variable values
    program_module
  end
end
```

### 2. Optimizer Integration

```elixir
defmodule ElixirML.Variable.OptimizerIntegration do
  @moduledoc """
  Integration interface for optimizers to work with variable systems.
  """

  @callback sample_configuration(variable_space :: ElixirML.Variable.Space.t(), opts :: keyword()) :: 
    {:ok, map()} | {:error, term()}

  @callback evaluate_configuration(variable_space :: ElixirML.Variable.Space.t(), 
                                   configuration :: map(), 
                                   evaluation_results :: map()) :: 
    {:ok, map()} | {:error, term()}

  @callback update_optimization_state(optimizer_state :: term(), 
                                      evaluation :: map()) :: 
    {:ok, term()} | {:error, term()}

  def random_configuration(variable_space, _opts \\ []) do
    configuration = 
      variable_space.variables
      |> Enum.map(fn {name, variable} ->
        {name, sample_variable_value(variable)}
      end)
      |> Map.new()

    case ElixirML.Variable.Space.validate_configuration(variable_space, configuration) do
      {:ok, validated} -> {:ok, validated}
      {:error, _} -> random_configuration(variable_space)  # Retry on validation failure
    end
  end

  defp sample_variable_value(%{type: :float, constraints: %{range: {min, max}}}) do
    min + :rand.uniform() * (max - min)
  end

  defp sample_variable_value(%{type: :integer, constraints: %{range: {min, max}}}) do
    min + :rand.uniform(max - min + 1) - 1
  end

  defp sample_variable_value(%{type: :choice, constraints: %{choices: choices}}) do
    Enum.random(choices)
  end

  defp sample_variable_value(%{type: :module, constraints: %{modules: modules}}) do
    Enum.random(modules)
  end

  defp sample_variable_value(%{default: default}) when default != nil do
    default
  end

  defp sample_variable_value(_variable) do
    nil
  end

  def grid_search_configurations(variable_space, opts \\ []) do
    max_combinations = Keyword.get(opts, :max_combinations, 1000)
    
    if ElixirML.Variable.Space.discrete_space_size(variable_space) <= max_combinations do
      generate_all_combinations(variable_space)
    else
      # Use sampling for large spaces
      sample_count = min(max_combinations, 100)
      1..sample_count
      |> Enum.map(fn _ -> random_configuration(variable_space) end)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, config} -> config end)
    end
  end

  defp generate_all_combinations(variable_space) do
    variable_space.variables
    |> Map.values()
    |> Enum.filter(&discrete_variable?/1)
    |> Enum.map(&generate_variable_values/1)
    |> cartesian_product()
    |> Enum.map(&configuration_from_values(variable_space, &1))
  end

  defp discrete_variable?(%{type: type}) when type in [:choice, :module], do: true
  defp discrete_variable?(_), do: false

  defp generate_variable_values(%{type: :choice, constraints: %{choices: choices}, name: name}) do
    Enum.map(choices, &{name, &1})
  end

  defp generate_variable_values(%{type: :module, constraints: %{modules: modules}, name: name}) do
    Enum.map(modules, &{name, &1})
  end

  defp cartesian_product([]), do: [[]]
  defp cartesian_product([head | tail]) do
    for h <- head, t <- cartesian_product(tail), do: [h | t]
  end

  defp configuration_from_values(variable_space, values) do
    base_config = 
      values
      |> List.flatten()
      |> Map.new()

    # Add continuous variables with default values
    full_config = 
      variable_space.variables
      |> Enum.reduce(base_config, fn {name, variable}, acc ->
        if Map.has_key?(acc, name) do
          acc
        else
          Map.put(acc, name, variable.default)
        end
      end)

    full_config
  end
end
```

## Implementation Strategy

### Week 1: Core Variable System
- [ ] Variable definition and types
- [ ] Variable Space management
- [ ] Basic validation and constraints
- [ ] Configuration resolution

### Week 2: ML-Specific Features  
- [ ] Provider-model compatibility
- [ ] Multi-objective optimization
- [ ] Cost-performance analysis
- [ ] Reasoning strategy variables

### Week 3: Integration Layer
- [ ] Program integration macros
- [ ] Optimizer integration interface
- [ ] Schema Engine integration
- [ ] Resource Framework integration

### Week 4: Advanced Features
- [ ] Configuration visualization
- [ ] Performance analytics
- [ ] Debugging tools
- [ ] Documentation and examples

## Success Metrics

### Functional Requirements
- [ ] Support for all major variable types (float, integer, choice, module)
- [ ] Multi-objective optimization capability
- [ ] Provider-model compatibility validation
- [ ] Seamless integration with existing DSPEx programs

### Performance Requirements
- [ ] <10ms configuration validation time
- [ ] Support for 100+ variables in a single space
- [ ] Efficient sampling for large configuration spaces
- [ ] Memory-efficient storage of optimization history

### Integration Requirements
- [ ] Full Schema Engine compatibility
- [ ] Resource Framework integration
- [ ] Optimizer interface compliance
- [ ] Backward compatibility with existing programs

This Variable System design enables revolutionary parameter optimization capabilities for ElixirML/DSPEx, allowing any optimizer to automatically tune any parameter while maintaining type safety and performance.
