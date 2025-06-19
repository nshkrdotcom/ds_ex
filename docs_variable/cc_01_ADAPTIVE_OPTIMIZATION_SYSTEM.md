# DSPEx Adaptive Optimization System - Technical Design

## Executive Summary

This document presents DSPEx's solution to the DSPy community challenge: **automated optimization across adapters, modules, and parameters**. Our system introduces a `DSPEx.Variable` abstraction that enables any optimizer to tune discrete parameters (adapters, modules) alongside continuous parameters (strings, weights), with automatic evaluation and selection.

**Key Innovation**: A unified optimization framework that treats adapter selection, module choice, and parameter tuning as a single multi-dimensional optimization problem using Elixir's concurrent capabilities and Nx for numerical optimization.

## Problem Analysis

### Current DSPy/DSPEx Limitations

1. **Manual Adapter Selection**: Developers must manually choose between JSON, Markdown, Chat adapters
2. **Module Selection Guesswork**: No automatic way to determine if Predict vs CoT vs PoT is better
3. **Cost-Performance Trade-offs**: No systematic evaluation of cheaper vs more expensive approaches
4. **Fragmented Optimization**: Different optimizers can't tune across all parameter types
5. **No Cross-Cutting Evaluation**: Adapters and modules optimized in isolation

### The DSPy Community Need

From Omar Khattab's response, the community needs:
- **Variable Abstraction**: Decoupled parameter declaration from specific optimizers
- **Universal Optimization**: Any optimizer should tune any parameter type
- **Multi-Type Parameters**: Discrete (adapters/modules) + continuous (strings/weights)
- **Automatic Evaluation**: System-driven selection based on performance metrics

## DSPEx Solution Architecture

### 1. Variable Abstraction System

```elixir
# lib/dspex/variables/variable.ex
defmodule DSPEx.Variables.Variable do
  @moduledoc """
  Universal variable abstraction for DSPEx optimization.
  
  Enables declaration of parameters that can be optimized by any optimizer,
  supporting discrete choices (adapters, modules) and continuous parameters.
  """
  
  @type variable_type :: :discrete | :continuous | :hybrid
  @type discrete_choice :: atom() | String.t() | module()
  @type continuous_range :: {number(), number()}
  @type constraint :: (any() -> boolean()) | {:range, number(), number()} | {:enum, [any()]}
  
  defstruct [
    :id,
    :type,
    :choices,
    :range,
    :default,
    :constraints,
    :description,
    :cost_weight,
    :performance_weight,
    :metadata
  ]
  
  @type t :: %__MODULE__{
    id: atom(),
    type: variable_type(),
    choices: [discrete_choice()] | nil,
    range: continuous_range() | nil,
    default: any(),
    constraints: [constraint()],
    description: String.t(),
    cost_weight: float(),
    performance_weight: float(),
    metadata: map()
  }
  
  @doc """
  Create a discrete variable for adapter/module selection.
  
  ## Examples
      
      iex> Variable.discrete(:adapter, [
      ...>   DSPEx.Adapters.JSONAdapter,
      ...>   DSPEx.Adapters.ChatAdapter,
      ...>   DSPEx.Adapters.MarkdownAdapter
      ...> ], description: "Response format adapter")
      %Variable{id: :adapter, type: :discrete, choices: [...]}
  """
  def discrete(id, choices, opts \\ []) do
    %__MODULE__{
      id: id,
      type: :discrete,
      choices: choices,
      default: List.first(choices),
      constraints: Keyword.get(opts, :constraints, []),
      description: Keyword.get(opts, :description, ""),
      cost_weight: Keyword.get(opts, :cost_weight, 1.0),
      performance_weight: Keyword.get(opts, :performance_weight, 1.0),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
  
  @doc """
  Create a continuous variable for numerical parameters.
  """
  def continuous(id, {min_val, max_val}, opts \\ []) do
    %__MODULE__{
      id: id,
      type: :continuous,
      range: {min_val, max_val},
      default: Keyword.get(opts, :default, (min_val + max_val) / 2),
      constraints: Keyword.get(opts, :constraints, []),
      description: Keyword.get(opts, :description, ""),
      cost_weight: Keyword.get(opts, :cost_weight, 1.0),
      performance_weight: Keyword.get(opts, :performance_weight, 1.0),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
  
  @doc """
  Create a hybrid variable that combines discrete and continuous aspects.
  """
  def hybrid(id, choices, ranges, opts \\ []) do
    %__MODULE__{
      id: id,
      type: :hybrid,
      choices: choices,
      range: ranges,
      default: {List.first(choices), elem(List.first(ranges), 0)},
      constraints: Keyword.get(opts, :constraints, []),
      description: Keyword.get(opts, :description, ""),
      cost_weight: Keyword.get(opts, :cost_weight, 1.0),
      performance_weight: Keyword.get(opts, :performance_weight, 1.0),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
  
  @doc """
  Validate if a value satisfies the variable's constraints.
  """
  def validate(variable, value) do
    case variable.type do
      :discrete -> validate_discrete(variable, value)
      :continuous -> validate_continuous(variable, value)
      :hybrid -> validate_hybrid(variable, value)
    end
  end
  
  defp validate_discrete(%{choices: choices}, value) do
    if value in choices do
      {:ok, value}
    else
      {:error, {:invalid_choice, value, choices}}
    end
  end
  
  defp validate_continuous(%{range: {min_val, max_val}}, value) when is_number(value) do
    if value >= min_val and value <= max_val do
      {:ok, value}
    else
      {:error, {:out_of_range, value, {min_val, max_val}}}
    end
  end
  
  defp validate_continuous(_, value) do
    {:error, {:not_numeric, value}}
  end
  
  defp validate_hybrid(variable, {discrete_val, continuous_val}) do
    with {:ok, _} <- validate_discrete(%{variable | type: :discrete}, discrete_val),
         {:ok, _} <- validate_continuous(%{variable | type: :continuous}, continuous_val) do
      {:ok, {discrete_val, continuous_val}}
    end
  end
  
  defp validate_hybrid(_, value) do
    {:error, {:invalid_hybrid_format, value}}
  end
end
```

### 2. Variable Space Definition

```elixir
# lib/dspex/variables/variable_space.ex
defmodule DSPEx.Variables.VariableSpace do
  @moduledoc """
  Defines the complete optimization space for a DSPEx program.
  
  Manages collections of variables and provides utilities for
  sampling, constraint checking, and space exploration.
  """
  
  alias DSPEx.Variables.Variable
  
  defstruct [:variables, :constraints, :metadata]
  
  @type t :: %__MODULE__{
    variables: %{atom() => Variable.t()},
    constraints: [constraint_function()],
    metadata: map()
  }
  
  @type constraint_function :: (map() -> {:ok, map()} | {:error, term()})
  
  def new(variables \\ %{}, opts \\ []) do
    %__MODULE__{
      variables: variables,
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
  
  @doc """
  Add a variable to the space.
  """
  def add_variable(space, variable) do
    %{space | variables: Map.put(space.variables, variable.id, variable)}
  end
  
  @doc """
  Define common DSPEx optimization variables.
  """
  def dspex_standard_space() do
    new()
    |> add_variable(Variable.discrete(:adapter, [
      DSPEx.Adapters.JSONAdapter,
      DSPEx.Adapters.ChatAdapter,
      DSPEx.Adapters.MarkdownAdapter,
      DSPEx.Adapters.MultiModalAdapter
    ], description: "Response format adapter", cost_weight: 0.2))
    
    |> add_variable(Variable.discrete(:module_type, [
      DSPEx.Predict,
      DSPEx.ChainOfThought,
      DSPEx.ProgramOfThought,
      DSPEx.ReAct,
      DSPEx.MultiHop
    ], description: "Core reasoning module", performance_weight: 2.0))
    
    |> add_variable(Variable.continuous(:temperature, {0.0, 2.0}, 
      default: 0.7, description: "Model temperature"))
    
    |> add_variable(Variable.continuous(:top_p, {0.1, 1.0}, 
      default: 0.9, description: "Nucleus sampling parameter"))
    
    |> add_variable(Variable.discrete(:provider, [
      :openai, :anthropic, :gemini, :groq, :ollama
    ], description: "LLM provider", cost_weight: 1.5))
    
    |> add_variable(Variable.hybrid(:model_config, 
      [:gpt4, :claude, :gemini], 
      [{0.1, 2.0}, {0.1, 2.0}, {0.1, 2.0}],
      description: "Model with temperature range"))
  end
  
  @doc """
  Sample a random configuration from the variable space.
  """
  def sample(space, opts \\ []) do
    sampler = Keyword.get(opts, :sampler, :uniform)
    
    case sampler do
      :uniform -> uniform_sample(space)
      :weighted -> weighted_sample(space)
      :latin_hypercube -> latin_hypercube_sample(space, opts)
      :sobol -> sobol_sample(space, opts)
    end
  end
  
  defp uniform_sample(space) do
    space.variables
    |> Enum.map(fn {id, variable} ->
      value = case variable.type do
        :discrete -> Enum.random(variable.choices)
        :continuous -> sample_continuous(variable.range)
        :hybrid -> {Enum.random(variable.choices), sample_continuous(List.first(variable.range))}
      end
      {id, value}
    end)
    |> Enum.into(%{})
  end
  
  defp sample_continuous({min_val, max_val}) do
    min_val + :rand.uniform() * (max_val - min_val)
  end
  
  defp weighted_sample(space) do
    # Sample based on cost and performance weights
    # Higher performance weight = more likely to be sampled
    # Higher cost weight = less likely to be sampled
    space.variables
    |> Enum.map(fn {id, variable} ->
      value = weighted_sample_variable(variable)
      {id, value}
    end)
    |> Enum.into(%{})
  end
  
  defp weighted_sample_variable(variable) do
    case variable.type do
      :discrete ->
        # For discrete variables, we could implement preference-based sampling
        # For now, use uniform sampling
        Enum.random(variable.choices)
      
      :continuous ->
        # For continuous variables, bias towards middle values for exploration
        {min_val, max_val} = variable.range
        mid = (min_val + max_val) / 2
        std = (max_val - min_val) / 6  # 99.7% within range
        
        # Clamp to range
        value = :rand.normal(mid, std)
        max(min_val, min(max_val, value))
      
      :hybrid ->
        discrete_choice = Enum.random(variable.choices)
        continuous_val = sample_continuous(List.first(variable.range))
        {discrete_choice, continuous_val}
    end
  end
  
  @doc """
  Validate a configuration against the variable space.
  """
  def validate_configuration(space, config) do
    # Validate individual variables
    variable_validations = 
      Enum.map(space.variables, fn {id, variable} ->
        value = Map.get(config, id)
        case Variable.validate(variable, value) do
          {:ok, validated_value} -> {:ok, {id, validated_value}}
          {:error, reason} -> {:error, {id, reason}}
        end
      end)
    
    # Check if all variables are valid
    case Enum.find(variable_validations, &match?({:error, _}, &1)) do
      nil ->
        # All variables valid, check space-level constraints
        validated_config = 
          variable_validations
          |> Enum.map(fn {:ok, {id, value}} -> {id, value} end)
          |> Enum.into(%{})
        
        validate_space_constraints(space, validated_config)
      
      {:error, {id, reason}} ->
        {:error, {:variable_validation_failed, id, reason}}
    end
  end
  
  defp validate_space_constraints(space, config) do
    case Enum.find(space.constraints, fn constraint_fn ->
      case constraint_fn.(config) do
        {:ok, _} -> false
        {:error, _} -> true
      end
    end) do
      nil -> {:ok, config}
      failing_constraint -> 
        case failing_constraint.(config) do
          {:error, reason} -> {:error, {:constraint_failed, reason}}
        end
    end
  end
end
```

### 3. Universal Optimizer Interface

```elixir
# lib/dspex/optimization/universal_optimizer.ex
defmodule DSPEx.Optimization.UniversalOptimizer do
  @moduledoc """
  Universal optimizer that can tune any combination of discrete and continuous variables.
  
  Implements multiple optimization strategies and automatically selects the best
  approach based on the variable space characteristics.
  """
  
  alias DSPEx.Variables.{Variable, VariableSpace}
  alias DSPEx.Optimization.Strategies
  
  @behaviour DSPEx.Teleprompter
  
  defstruct [
    :variable_space,
    :strategy,
    :evaluation_metric,
    :budget,
    :parallel_evaluations,
    :early_stopping,
    :optimization_history,
    :best_configuration,
    :convergence_criteria
  ]
  
  @type t :: %__MODULE__{
    variable_space: VariableSpace.t(),
    strategy: optimization_strategy(),
    evaluation_metric: evaluation_function(),
    budget: pos_integer(),
    parallel_evaluations: pos_integer(),
    early_stopping: early_stopping_config(),
    optimization_history: [optimization_result()],
    best_configuration: map() | nil,
    convergence_criteria: convergence_config()
  }
  
  @type optimization_strategy :: 
    :random_search | :grid_search | :bayesian_optimization | 
    :genetic_algorithm | :simulated_annealing | :particle_swarm |
    :multi_objective | :hybrid_strategy
  
  @type evaluation_function :: (map(), any() -> evaluation_result())
  @type evaluation_result :: %{score: float(), cost: float(), metadata: map()}
  @type optimization_result :: %{configuration: map(), evaluation: evaluation_result()}
  
  def new(variable_space, opts \\ []) do
    %__MODULE__{
      variable_space: variable_space,
      strategy: select_optimal_strategy(variable_space, opts),
      evaluation_metric: Keyword.get(opts, :evaluation_metric),
      budget: Keyword.get(opts, :budget, 100),
      parallel_evaluations: Keyword.get(opts, :parallel_evaluations, System.schedulers_online()),
      early_stopping: Keyword.get(opts, :early_stopping, %{patience: 10, threshold: 0.01}),
      optimization_history: [],
      best_configuration: nil,
      convergence_criteria: Keyword.get(opts, :convergence_criteria, %{
        max_iterations: 1000,
        target_score: 0.95,
        improvement_threshold: 0.001
      })
    }
  end
  
  @doc """
  Run optimization to find the best configuration.
  """
  def optimize(optimizer, program, trainset, evaluation_fn) do
    case optimizer.strategy do
      :random_search -> 
        Strategies.RandomSearch.optimize(optimizer, program, trainset, evaluation_fn)
      
      :bayesian_optimization -> 
        Strategies.BayesianOptimization.optimize(optimizer, program, trainset, evaluation_fn)
      
      :genetic_algorithm -> 
        Strategies.GeneticAlgorithm.optimize(optimizer, program, trainset, evaluation_fn)
      
      :multi_objective -> 
        Strategies.MultiObjective.optimize(optimizer, program, trainset, evaluation_fn)
      
      :hybrid_strategy -> 
        Strategies.HybridStrategy.optimize(optimizer, program, trainset, evaluation_fn)
    end
  end
  
  @doc """
  Automatically select the best optimization strategy based on variable space.
  """
  def select_optimal_strategy(variable_space, opts) do
    num_variables = map_size(variable_space.variables)
    discrete_count = count_discrete_variables(variable_space)
    continuous_count = num_variables - discrete_count
    budget = Keyword.get(opts, :budget, 100)
    
    cond do
      # Small discrete space - use grid search
      discrete_count > 0 and continuous_count == 0 and 
      estimate_grid_size(variable_space) <= budget ->
        :grid_search
      
      # Large discrete space or mixed - use genetic algorithm
      discrete_count > continuous_count ->
        :genetic_algorithm
      
      # Mostly continuous with small budget - use random search
      continuous_count > discrete_count and budget < 50 ->
        :random_search
      
      # Mostly continuous with larger budget - use Bayesian optimization
      continuous_count > discrete_count and budget >= 50 ->
        :bayesian_optimization
      
      # Mixed space with multiple objectives - use multi-objective
      has_cost_and_performance_objectives?(variable_space) ->
        :multi_objective
      
      # Default to hybrid strategy
      true ->
        :hybrid_strategy
    end
  end
  
  defp count_discrete_variables(variable_space) do
    variable_space.variables
    |> Map.values()
    |> Enum.count(fn var -> var.type in [:discrete, :hybrid] end)
  end
  
  defp estimate_grid_size(variable_space) do
    variable_space.variables
    |> Map.values()
    |> Enum.reduce(1, fn var, acc ->
      case var.type do
        :discrete -> acc * length(var.choices)
        :continuous -> acc * 10  # Assume 10 grid points for continuous
        :hybrid -> acc * length(var.choices) * 10
      end
    end)
  end
  
  defp has_cost_and_performance_objectives?(variable_space) do
    variables = Map.values(variable_space.variables)
    has_cost = Enum.any?(variables, fn var -> var.cost_weight > 0 end)
    has_performance = Enum.any?(variables, fn var -> var.performance_weight > 0 end)
    has_cost and has_performance
  end
end
```

### 4. Adaptive Configuration System

```elixir
# lib/dspex/optimization/adaptive_config.ex
defmodule DSPEx.Optimization.AdaptiveConfig do
  @moduledoc """
  Automatically applies optimized configurations to DSPEx programs.
  
  Handles the complex task of taking optimization results and properly
  configuring programs with the right adapters, modules, and parameters.
  """
  
  alias DSPEx.Variables.VariableSpace
  
  @doc """
  Apply an optimized configuration to a DSPEx program.
  """
  def apply_configuration(program, configuration, variable_space) do
    # Start with the base program
    configured_program = program
    
    # Apply each configuration parameter
    Enum.reduce(configuration, configured_program, fn {var_id, value}, acc_program ->
      variable = Map.get(variable_space.variables, var_id)
      apply_variable_configuration(acc_program, variable, value)
    end)
  end
  
  defp apply_variable_configuration(program, variable, value) do
    case variable.id do
      :adapter -> configure_adapter(program, value)
      :module_type -> configure_module_type(program, value)
      :provider -> configure_provider(program, value)
      :temperature -> configure_parameter(program, :temperature, value)
      :top_p -> configure_parameter(program, :top_p, value)
      :model_config -> configure_model_config(program, value)
      _ -> configure_custom_parameter(program, variable.id, value)
    end
  end
  
  defp configure_adapter(program, adapter_module) do
    %{program | adapter: adapter_module}
  end
  
  defp configure_module_type(program, module_type) do
    case module_type do
      DSPEx.Predict -> 
        %DSPEx.Predict{
          signature: program.signature,
          adapter: program.adapter,
          client: program.client
        }
      
      DSPEx.ChainOfThought -> 
        %DSPEx.ChainOfThought{
          signature: program.signature,
          adapter: program.adapter,
          client: program.client,
          reasoning_steps: 3
        }
      
      DSPEx.ProgramOfThought -> 
        %DSPEx.ProgramOfThought{
          signature: program.signature,
          adapter: program.adapter,
          client: program.client,
          code_executor: DSPEx.CodeExecutor.Python
        }
      
      DSPEx.ReAct -> 
        %DSPEx.ReAct{
          signature: program.signature,
          adapter: program.adapter,
          client: program.client,
          tools: program.tools || []
        }
      
      DSPEx.MultiHop -> 
        %DSPEx.MultiHop{
          signature: program.signature,
          adapter: program.adapter,
          client: program.client,
          max_hops: 3
        }
      
      _ -> program
    end
  end
  
  defp configure_provider(program, provider) do
    # Update client configuration with new provider
    client_config = Map.get(program, :client_config, %{})
    updated_config = Map.put(client_config, :provider, provider)
    
    %{program | client_config: updated_config}
  end
  
  defp configure_parameter(program, param_name, value) do
    client_config = Map.get(program, :client_config, %{})
    updated_config = Map.put(client_config, param_name, value)
    
    %{program | client_config: updated_config}
  end
  
  defp configure_model_config(program, {model, temperature}) do
    client_config = Map.get(program, :client_config, %{})
    updated_config = 
      client_config
      |> Map.put(:model, model)
      |> Map.put(:temperature, temperature)
    
    %{program | client_config: updated_config}
  end
  
  defp configure_custom_parameter(program, param_name, value) do
    # Handle custom parameters by storing in metadata
    metadata = Map.get(program, :metadata, %{})
    updated_metadata = Map.put(metadata, param_name, value)
    
    %{program | metadata: updated_metadata}
  end
end
```

### 5. Multi-Objective Evaluation Framework

```elixir
# lib/dspex/optimization/multi_objective_evaluator.ex
defmodule DSPEx.Optimization.MultiObjectiveEvaluator do
  @moduledoc """
  Evaluates configurations across multiple objectives: performance, cost, latency.
  
  Implements Pareto optimization to find configurations that balance
  quality, speed, and cost effectively.
  """
  
  import Nx.Defn
  
  defstruct [
    :objectives,
    :weights,
    :constraints,
    :pareto_frontier,
    :evaluation_history
  ]
  
  @type objective :: %{
    name: atom(),
    function: evaluation_function(),
    weight: float(),
    direction: :maximize | :minimize
  }
  
  @type evaluation_function :: (any(), any() -> float())
  
  def new(objectives, opts \\ []) do
    %__MODULE__{
      objectives: objectives,
      weights: normalize_weights(objectives),
      constraints: Keyword.get(opts, :constraints, []),
      pareto_frontier: [],
      evaluation_history: []
    }
  end
  
  @doc """
  Standard DSPEx multi-objective evaluator.
  """
  def dspex_standard_evaluator() do
    objectives = [
      %{
        name: :accuracy,
        function: &evaluate_accuracy/2,
        weight: 0.4,
        direction: :maximize
      },
      %{
        name: :cost,
        function: &evaluate_cost/2,
        weight: 0.3,
        direction: :minimize
      },
      %{
        name: :latency,
        function: &evaluate_latency/2,
        weight: 0.2,
        direction: :minimize
      },
      %{
        name: :reliability,
        function: &evaluate_reliability/2,
        weight: 0.1,
        direction: :maximize
      }
    ]
    
    new(objectives)
  end
  
  @doc """
  Evaluate a configuration across all objectives.
  """
  def evaluate(evaluator, configuration, program, trainset) do
    # Run evaluation for each objective
    objective_scores = 
      evaluator.objectives
      |> Task.async_stream(fn objective ->
        score = objective.function.(configuration, {program, trainset})
        {objective.name, score, objective.direction}
      end, max_concurrency: System.schedulers_online())
      |> Enum.map(fn {:ok, result} -> result end)
    
    # Calculate weighted score
    weighted_score = calculate_weighted_score(objective_scores, evaluator.weights)
    
    # Update Pareto frontier
    evaluation_result = %{
      configuration: configuration,
      objective_scores: objective_scores,
      weighted_score: weighted_score,
      timestamp: DateTime.utc_now()
    }
    
    updated_evaluator = update_pareto_frontier(evaluator, evaluation_result)
    
    {evaluation_result, updated_evaluator}
  end
  
  defp calculate_weighted_score(objective_scores, weights) do
    objective_scores
    |> Enum.reduce(0.0, fn {name, score, direction}, acc ->
      weight = Map.get(weights, name, 0.0)
      normalized_score = case direction do
        :maximize -> score
        :minimize -> 1.0 - score  # Invert for minimization objectives
      end
      acc + (weight * normalized_score)
    end)
  end
  
  defp update_pareto_frontier(evaluator, new_evaluation) do
    # Check if new evaluation is Pareto optimal
    new_scores = extract_objective_values(new_evaluation.objective_scores)
    
    # Remove dominated solutions
    updated_frontier = 
      evaluator.pareto_frontier
      |> Enum.reject(fn existing ->
        existing_scores = extract_objective_values(existing.objective_scores)
        dominates?(new_scores, existing_scores, evaluator.objectives)
      end)
    
    # Add new solution if it's not dominated
    final_frontier = 
      if Enum.any?(updated_frontier, fn existing ->
        existing_scores = extract_objective_values(existing.objective_scores)
        dominates?(existing_scores, new_scores, evaluator.objectives)
      end) do
        updated_frontier  # New solution is dominated
      else
        [new_evaluation | updated_frontier]  # New solution is Pareto optimal
      end
    
    %{evaluator | 
      pareto_frontier: final_frontier,
      evaluation_history: [new_evaluation | evaluator.evaluation_history]
    }
  end
  
  defp extract_objective_values(objective_scores) do
    objective_scores
    |> Enum.map(fn {name, score, _direction} -> {name, score} end)
    |> Enum.into(%{})
  end
  
  defp dominates?(scores_a, scores_b, objectives) do
    # A dominates B if A is better or equal in all objectives and strictly better in at least one
    comparisons = 
      Enum.map(objectives, fn objective ->
        score_a = Map.get(scores_a, objective.name)
        score_b = Map.get(scores_b, objective.name)
        
        case objective.direction do
          :maximize -> {score_a >= score_b, score_a > score_b}
          :minimize -> {score_a <= score_b, score_a < score_b}
        end
      end)
    
    all_better_or_equal = Enum.all?(comparisons, fn {better_or_equal, _} -> better_or_equal end)
    at_least_one_strictly_better = Enum.any?(comparisons, fn {_, strictly_better} -> strictly_better end)
    
    all_better_or_equal and at_least_one_strictly_better
  end
  
  # Objective evaluation functions
  
  defp evaluate_accuracy(_configuration, {program, trainset}) do
    # Run program on trainset and calculate accuracy
    results = 
      trainset
      |> Enum.map(fn example ->
        case DSPEx.Program.forward(program, example.inputs) do
          {:ok, outputs} -> 
            # Compare with expected outputs
            calculate_example_accuracy(outputs, example.outputs)
          {:error, _} -> 0.0
        end
      end)
    
    case results do
      [] -> 0.0
      _ -> Enum.sum(results) / length(results)
    end
  end
  
  defp evaluate_cost(configuration, {program, trainset}) do
    # Estimate cost based on provider, model, and token usage
    provider_cost = get_provider_cost(Map.get(configuration, :provider, :openai))
    model_cost = get_model_cost(Map.get(configuration, :model_config, :gpt4))
    
    # Estimate tokens per example
    avg_tokens = estimate_token_usage(program, trainset)
    
    total_cost = provider_cost * model_cost * avg_tokens * length(trainset)
    
    # Normalize to 0-1 scale (higher cost = higher score, will be inverted for minimization)
    normalize_cost(total_cost)
  end
  
  defp evaluate_latency(_configuration, {program, trainset}) do
    # Measure actual latency by running a sample
    sample_size = min(5, length(trainset))
    sample_examples = Enum.take_random(trainset, sample_size)
    
    latencies = 
      sample_examples
      |> Enum.map(fn example ->
        start_time = System.monotonic_time(:millisecond)
        DSPEx.Program.forward(program, example.inputs)
        end_time = System.monotonic_time(:millisecond)
        end_time - start_time
      end)
    
    avg_latency = Enum.sum(latencies) / length(latencies)
    
    # Normalize to 0-1 scale
    normalize_latency(avg_latency)
  end
  
  defp evaluate_reliability(_configuration, {program, trainset}) do
    # Measure consistency across multiple runs
    sample_example = List.first(trainset)
    
    if sample_example do
      results = 
        1..5
        |> Enum.map(fn _ ->
          case DSPEx.Program.forward(program, sample_example.inputs) do
            {:ok, outputs} -> outputs
            {:error, _} -> nil
          end
        end)
      
      # Calculate consistency score
      successful_runs = Enum.count(results, & &1 != nil)
      success_rate = successful_runs / 5
      
      # If we have multiple successful runs, check output consistency
      if successful_runs > 1 do
        successful_outputs = Enum.reject(results, & &1 == nil)
        consistency_score = calculate_output_consistency(successful_outputs)
        (success_rate + consistency_score) / 2
      else
        success_rate
      end
    else
      0.0
    end
  end
  
  # Helper functions
  
  defp normalize_weights(objectives) do
    total_weight = Enum.sum(Enum.map(objectives, & &1.weight))
    
    objectives
    |> Enum.map(fn obj -> {obj.name, obj.weight / total_weight} end)
    |> Enum.into(%{})
  end
  
  defp calculate_example_accuracy(outputs, expected_outputs) do
    # Simple exact match for now - can be made more sophisticated
    if outputs == expected_outputs do
      1.0
    else
      # Partial credit based on similarity
      calculate_similarity(outputs, expected_outputs)
    end
  end
  
  defp calculate_similarity(outputs, expected_outputs) when is_map(outputs) and is_map(expected_outputs) do
    # Calculate field-wise similarity
    all_keys = MapSet.union(MapSet.new(Map.keys(outputs)), MapSet.new(Map.keys(expected_outputs)))
    
    similarities = 
      Enum.map(all_keys, fn key ->
        output_val = Map.get(outputs, key)
        expected_val = Map.get(expected_outputs, key)
        calculate_value_similarity(output_val, expected_val)
      end)
    
    Enum.sum(similarities) / length(similarities)
  end
  
  defp calculate_similarity(outputs, expected_outputs) do
    # Fallback for non-map types
    if outputs == expected_outputs, do: 1.0, else: 0.0
  end
  
  defp calculate_value_similarity(val, val), do: 1.0
  defp calculate_value_similarity(val1, val2) when is_binary(val1) and is_binary(val2) do
    # Use Levenshtein distance for string similarity
    max_len = max(String.length(val1), String.length(val2))
    if max_len == 0 do
      1.0
    else
      distance = String.jaro_distance(val1, val2)
      distance
    end
  end
  defp calculate_value_similarity(val1, val2) when is_number(val1) and is_number(val2) do
    # Numerical similarity
    max_val = max(abs(val1), abs(val2))
    if max_val == 0 do
      1.0
    else
      1.0 - (abs(val1 - val2) / max_val)
    end
  end
  defp calculate_value_similarity(_, _), do: 0.0
  
  defp get_provider_cost(provider) do
    case provider do
      :openai -> 1.0
      :anthropic -> 0.8
      :gemini -> 0.6
      :groq -> 0.3
      :ollama -> 0.1
      _ -> 1.0
    end
  end
  
  defp get_model_cost(model_config) do
    case model_config do
      :gpt4 -> 1.0
      :claude -> 0.8
      :gemini -> 0.6
      _ -> 0.7
    end
  end
  
  defp estimate_token_usage(program, trainset) do
    # Rough estimation based on program type and input/output sizes
    sample_example = List.first(trainset)
    
    if sample_example do
      input_tokens = estimate_tokens(sample_example.inputs)
      output_tokens = estimate_tokens(sample_example.outputs)
      
      # Add overhead based on program type
      overhead = case program do
        %DSPEx.Predict{} -> 50
        %DSPEx.ChainOfThought{} -> 200
        %DSPEx.ProgramOfThought{} -> 500
        %DSPEx.ReAct{} -> 300
        _ -> 100
      end
      
      input_tokens + output_tokens + overhead
    else
      100  # Default estimate
    end
  end
  
  defp estimate_tokens(data) when is_binary(data) do
    # Rough approximation: 1 token per 4 characters
    div(String.length(data), 4)
  end
  
  defp estimate_tokens(data) when is_map(data) do
    data
    |> Map.values()
    |> Enum.map(&estimate_tokens/1)
    |> Enum.sum()
  end
  
  defp estimate_tokens(data) when is_list(data) do
    data
    |> Enum.map(&estimate_tokens/1)
    |> Enum.sum()
  end
  
  defp estimate_tokens(_), do: 10  # Default for other types
  
  defp normalize_cost(cost) do
    # Normalize cost to 0-1 scale (assuming max cost of $10 per evaluation)
    min(cost / 10.0, 1.0)
  end
  
  defp normalize_latency(latency_ms) do
    # Normalize latency to 0-1 scale (assuming max acceptable latency of 10 seconds)
    min(latency_ms / 10000.0, 1.0)
  end
  
  defp calculate_output_consistency(outputs) do
    # Calculate how consistent the outputs are
    if length(outputs) < 2 do
      1.0
    else
      # Compare each pair of outputs
      pairs = for i <- outputs, j <- outputs, i != j, do: {i, j}
      
      similarities = 
        pairs
        |> Enum.map(fn {out1, out2} -> calculate_similarity(out1, out2) end)
      
      Enum.sum(similarities) / length(similarities)
    end
  end
end
```

This is getting quite long. Let me continue with the optimization strategies and create a second document for the implementation details. 