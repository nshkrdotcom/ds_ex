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
end
```

### 2. Variable Space Definition

```elixir
# lib/dspex/variables/variable_space.ex
defmodule DSPEx.Variables.VariableSpace do
  @moduledoc """
  Defines the complete optimization space for a DSPEx program.
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
end
```

## Usage Examples

### Basic Optimization

```elixir
# Define the optimization space
variable_space = VariableSpace.dspex_standard_space()

# Create optimizer
optimizer = UniversalOptimizer.new(variable_space, 
  budget: 50,
  strategy: :bayesian_optimization
)

# Define your program
program = %DSPEx.Predict{
  signature: MySignature,
  client: DSPEx.Client
}

# Run optimization
{:ok, optimized_program} = UniversalOptimizer.optimize(
  optimizer, 
  program, 
  trainset, 
  &my_evaluation_function/2
)
```

### Multi-Objective Optimization

```elixir
# Create multi-objective evaluator
evaluator = MultiObjectiveEvaluator.dspex_standard_evaluator()

# Define custom objectives
custom_evaluator = MultiObjectiveEvaluator.new([
  %{name: :accuracy, function: &evaluate_accuracy/2, weight: 0.5, direction: :maximize},
  %{name: :cost, function: &evaluate_cost/2, weight: 0.3, direction: :minimize},
  %{name: :latency, function: &evaluate_latency/2, weight: 0.2, direction: :minimize}
])

# Run optimization
optimizer = UniversalOptimizer.new(variable_space,
  strategy: :multi_objective,
  evaluation_metric: custom_evaluator
)
```

### Custom Variable Spaces

```elixir
# Define custom variables for specific use cases
custom_space = VariableSpace.new()
  |> VariableSpace.add_variable(Variable.discrete(:reasoning_style, [
    :analytical, :creative, :logical, :intuitive
  ]))
  |> VariableSpace.add_variable(Variable.continuous(:creativity_factor, {0.0, 1.0}))
  |> VariableSpace.add_variable(Variable.hybrid(:model_size, 
    [:small, :medium, :large], 
    [{0.1, 0.5}, {0.3, 0.8}, {0.7, 1.0}]
  ))
```

## Advanced Features

### 1. Automatic Strategy Selection

The system automatically selects the best optimization strategy based on:
- Number of discrete vs continuous variables
- Search space size
- Available budget
- Multiple objectives presence

### 2. Pareto Optimization

For multi-objective problems, the system maintains a Pareto frontier of non-dominated solutions, allowing users to choose the best trade-off between competing objectives.

### 3. Nx-Powered Numerical Optimization

Uses Nx for high-performance numerical operations in:
- Gradient-based optimization
- Statistical analysis of results
- Similarity calculations
- Performance trend analysis

### 4. Concurrent Evaluation

Leverages Elixir's concurrency for:
- Parallel configuration evaluation
- Distributed optimization across nodes
- Real-time performance monitoring

## Integration with Existing DSPEx

### Teleprompter Integration

```elixir
# Use with existing teleprompters
teleprompter = DSPEx.Teleprompter.AdaptiveOptimizer.new(
  variable_space: VariableSpace.dspex_standard_space(),
  base_teleprompter: DSPEx.Teleprompter.BootstrapFewShot,
  optimization_budget: 100
)

{:ok, optimized_program} = DSPEx.Teleprompter.compile(
  teleprompter, student, teacher, trainset, metric_fn
)
```

### Evaluation System Integration

The system integrates with DSPEx's evaluation framework to provide comprehensive performance analysis across different configurations.

## Benefits

### 1. **Automated Discovery**
- Automatically finds optimal adapter/module combinations
- Reduces manual experimentation time
- Discovers non-obvious optimization opportunities

### 2. **Cost Optimization**
- Balances performance with cost considerations
- Finds cheaper alternatives that meet quality thresholds
- Provides cost-performance Pareto frontiers

### 3. **Systematic Evaluation**
- Comprehensive testing across parameter space
- Statistical significance testing
- Reproducible optimization results

### 4. **Extensibility**
- Easy to add new variables and constraints
- Pluggable optimization strategies
- Custom evaluation metrics

## Implementation Roadmap

### Phase 1: Core Framework (Week 1-2)
- [ ] Implement Variable and VariableSpace systems
- [ ] Create UniversalOptimizer with basic strategies
- [ ] Build AdaptiveConfig system
- [ ] Add Nx integration for numerical optimization

### Phase 2: Advanced Optimization (Week 3-4)
- [ ] Implement MultiObjectiveEvaluator
- [ ] Add Bayesian optimization strategy
- [ ] Create genetic algorithm implementation
- [ ] Build Pareto frontier analysis

### Phase 3: Integration & Testing (Week 5-6)
- [ ] Integrate with existing teleprompters
- [ ] Add comprehensive test suite
- [ ] Create performance benchmarks
- [ ] Build documentation and examples

### Phase 4: Advanced Features (Week 7-8)
- [ ] Add distributed optimization support
- [ ] Implement adaptive strategy selection
- [ ] Create optimization visualization tools
- [ ] Add real-time monitoring dashboard

This system positions DSPEx as the most advanced optimization framework in the LLM space, addressing the exact needs identified by the DSPy community while leveraging Elixir's unique strengths for concurrent, fault-tolerant optimization. 