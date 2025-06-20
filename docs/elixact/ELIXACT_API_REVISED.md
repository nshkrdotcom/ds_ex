# Elixact API Specification - Variable System Support

**Complete API for Elixact supporting DSPEx Variable System, Multi-Objective Optimization, and Adaptive Configuration**

## Table of Contents

- [Core Variable System API](#core-variable-system-api)
- [Schema Definition API](#schema-definition-api)
- [Variable Space Management API](#variable-space-management-api)
- [Multi-Objective Evaluation API](#multi-objective-evaluation-api)
- [Adaptive Configuration API](#adaptive-configuration-api)
- [Runtime Schema Generation API](#runtime-schema-generation-api)
- [Constraint System API](#constraint-system-api)
- [Integration APIs](#integration-apis)

## Core Variable System API

### Variable Definition

```elixir
defmodule Elixact.Variable do
  @moduledoc """
  Core variable abstraction for optimization and configuration.
  Supports discrete choices, continuous ranges, and hybrid variables.
  """
  
  @type variable_type :: :discrete | :continuous | :hybrid | :conditional | :composite
  @type discrete_choice :: atom() | String.t() | module() | any()
  @type continuous_range :: {number(), number()}
  @type hybrid_config :: {discrete_choice(), number()}
  
  defstruct [
    :id,                      # Unique identifier
    :type,                    # Variable type
    :choices,                 # For discrete variables
    :range,                   # For continuous variables
    :default,                 # Default value
    :constraints,             # Validation constraints
    :dependencies,            # Variable dependencies
    :metadata,                # Additional metadata
    :description,             # Human description
    :cost_weight,             # Cost optimization weight
    :performance_weight,      # Performance optimization weight
    :validation_schema,       # Elixact schema for validation
    :transform_fn,            # Value transformation function
    :condition_fn            # Conditional activation function
  ]
  
  @type t :: %__MODULE__{
    id: atom(),
    type: variable_type(),
    choices: [discrete_choice()] | nil,
    range: continuous_range() | nil,
    default: any(),
    constraints: [constraint()],
    dependencies: [dependency()],
    metadata: map(),
    description: String.t(),
    cost_weight: float(),
    performance_weight: float(),
    validation_schema: Elixact.Schema.t() | nil,
    transform_fn: (any() -> any()) | nil,
    condition_fn: (map() -> boolean()) | nil
  }
  
  @type constraint :: 
    {:range, number(), number()} |
    {:enum, [any()]} |
    {:function, (any() -> boolean())} |
    {:schema, Elixact.Schema.t()} |
    {:dependent, atom(), any()}
  
  @type dependency :: 
    {:requires, atom()} |
    {:conflicts, atom()} |
    {:conditional, atom(), any()} |
    {:derived, atom(), (any() -> any())}
  
  # Variable Creation Functions
  
  @doc """
  Create a discrete variable for adapter/module selection.
  
  ## Examples
      
      iex> Variable.discrete(:adapter, [
      ...>   DSPEx.Adapters.JSONAdapter,
      ...>   DSPEx.Adapters.ChatAdapter,
      ...>   DSPEx.Adapters.MarkdownAdapter
      ...> ], 
      ...> description: "Response format adapter",
      ...> validation_schema: adapter_schema()
      ...> )
      %Variable{id: :adapter, type: :discrete, choices: [...]}
  """
  @spec discrete(atom(), [discrete_choice()], keyword()) :: t()
  def discrete(id, choices, opts \\ [])
  
  @doc """
  Create a continuous variable for numerical parameters.
  
  ## Examples
      
      iex> Variable.continuous(:temperature, {0.0, 2.0}, 
      ...>   default: 0.7,
      ...>   constraints: [{:range, 0.1, 1.5}],
      ...>   validation_schema: temperature_schema()
      ...> )
      %Variable{id: :temperature, type: :continuous, range: {0.0, 2.0}}
  """
  @spec continuous(atom(), continuous_range(), keyword()) :: t()
  def continuous(id, range, opts \\ [])
  
  @doc """
  Create a hybrid variable combining discrete and continuous aspects.
  
  ## Examples
      
      iex> Variable.hybrid(:model_config, 
      ...>   [:gpt4, :claude, :gemini], 
      ...>   [{0.1, 2.0}, {0.1, 2.0}, {0.1, 2.0}],
      ...>   description: "Model with temperature range"
      ...> )
      %Variable{id: :model_config, type: :hybrid}
  """
  @spec hybrid(atom(), [discrete_choice()], [continuous_range()], keyword()) :: t()
  def hybrid(id, choices, ranges, opts \\ [])
  
  @doc """
  Create a conditional variable that activates based on other variables.
  
  ## Examples
      
      iex> Variable.conditional(:reasoning_temperature,
      ...>   condition: {:reasoning_module, :chain_of_thought},
      ...>   then_variable: Variable.continuous(:temperature, {0.3, 1.2}),
      ...>   else_variable: Variable.continuous(:temperature, {0.1, 0.8})
      ...> )
      %Variable{id: :reasoning_temperature, type: :conditional}
  """
  @spec conditional(atom(), keyword()) :: t()
  def conditional(id, opts)
  
  @doc """
  Create a composite variable that bundles related variables.
  
  ## Examples
      
      iex> Variable.composite(:provider_bundle,
      ...>   variables: %{
      ...>     provider: Variable.discrete(:provider, [:openai, :anthropic]),
      ...>     model: Variable.discrete(:model, ["gpt-4", "claude-3"]),
      ...>     temperature: Variable.continuous(:temperature, {0.1, 1.0})
      ...>   },
      ...>   activation_condition: {:use_provider_bundle, true}
      ...> )
      %Variable{id: :provider_bundle, type: :composite}
  """
  @spec composite(atom(), keyword()) :: t()
  def composite(id, opts)
  
  # Variable Operations
  
  @doc """
  Validate a value against the variable's constraints and schema.
  """
  @spec validate(t(), any()) :: {:ok, any()} | {:error, [Elixact.ValidationError.t()]}
  def validate(variable, value)
  
  @doc """
  Transform a value using the variable's transformation function.
  """
  @spec transform(t(), any()) :: any()
  def transform(variable, value)
  
  @doc """
  Check if a variable should be active given a configuration context.
  """
  @spec active?(t(), map()) :: boolean()
  def active?(variable, context)
  
  @doc """
  Sample a random value from the variable's domain.
  """
  @spec sample(t(), keyword()) :: any()
  def sample(variable, opts \\ [])
  
  @doc """
  Get the variable's validation schema.
  """
  @spec schema(t()) :: Elixact.Schema.t()
  def schema(variable)
end
```

This API provides the complete foundation for the Variable System architecture.

### Variable Space Management

```elixir
defmodule Elixact.VariableSpace do
  @moduledoc """
  Manages collections of variables for optimization and configuration.
  Provides utilities for sampling, constraint checking, and space exploration.
  """
  
  alias Elixact.Variable
  
  defstruct [
    :variables,               # Map of variable_id => Variable
    :dependencies,            # Dependency graph
    :constraints,             # Cross-variable constraints
    :metadata,                # Space metadata
    :validation_schema,       # Overall validation schema
    :optimization_hints,      # Hints for optimizers
    :sampling_strategy,       # Default sampling strategy
    :constraint_solver       # Constraint solver configuration
  ]
  
  @type t :: %__MODULE__{
    variables: %{atom() => Variable.t()},
    dependencies: dependency_graph(),
    constraints: [space_constraint()],
    metadata: map(),
    validation_schema: Elixact.Schema.t() | nil,
    optimization_hints: optimization_hints(),
    sampling_strategy: sampling_strategy(),
    constraint_solver: constraint_solver_config()
  }
  
  @type dependency_graph :: %{atom() => [atom()]}
  @type space_constraint :: (map() -> {:ok, map()} | {:error, term()})
  @type optimization_hints :: %{
    search_strategy: atom(),
    budget_allocation: map(),
    parallel_evaluations: pos_integer(),
    early_stopping: map()
  }
  @type sampling_strategy :: :uniform | :weighted | :latin_hypercube | :sobol | :adaptive
  @type constraint_solver_config :: %{
    solver: atom(),
    timeout: pos_integer(),
    max_iterations: pos_integer()
  }
  
  # Space Creation and Management
  
  @doc """
  Create a new variable space.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ [])
  
  @doc """
  Add a variable to the space.
  """
  @spec add_variable(t(), Variable.t()) :: t()
  def add_variable(space, variable)
  
  @doc """
  Remove a variable from the space.
  """
  @spec remove_variable(t(), atom()) :: t()
  def remove_variable(space, variable_id)
  
  @doc """
  Add a dependency between variables.
  """
  @spec add_dependency(t(), atom(), atom(), dependency_type()) :: t()
  def add_dependency(space, from_var, to_var, dependency_type)
  
  @doc """
  Add a cross-variable constraint.
  """
  @spec add_constraint(t(), space_constraint()) :: t()
  def add_constraint(space, constraint_fn)
  
  # Predefined Spaces
  
  @doc """
  Create a standard DSPEx optimization space.
  """
  @spec dspex_standard_space() :: t()
  def dspex_standard_space()
  
  @doc """
  Create a space for adapter selection optimization.
  """
  @spec adapter_optimization_space() :: t()
  def adapter_optimization_space()
  
  @doc """
  Create a space for module selection optimization.
  """
  @spec module_optimization_space() :: t()
  def module_optimization_space()
  
  @doc """
  Create a space for multi-objective optimization.
  """
  @spec multi_objective_space(keyword()) :: t()
  def multi_objective_space(objectives)
  
  # Sampling and Exploration
  
  @doc """
  Sample a configuration from the variable space.
  """
  @spec sample(t(), keyword()) :: {:ok, map()} | {:error, term()}
  def sample(space, opts \\ [])
  
  @doc """
  Generate multiple configurations using different sampling strategies.
  """
  @spec sample_multiple(t(), pos_integer(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def sample_multiple(space, count, opts \\ [])
  
  @doc """
  Generate a Latin Hypercube sample for efficient space exploration.
  """
  @spec latin_hypercube_sample(t(), pos_integer(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def latin_hypercube_sample(space, count, opts \\ [])
  
  @doc """
  Generate a Sobol sequence sample for quasi-random exploration.
  """
  @spec sobol_sample(t(), pos_integer(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def sobol_sample(space, count, opts \\ [])
  
  # Validation and Constraints
  
  @doc """
  Validate a configuration against the variable space.
  """
  @spec validate_configuration(t(), map()) :: {:ok, map()} | {:error, [Elixact.ValidationError.t()]}
  def validate_configuration(space, configuration)
  
  @doc """
  Resolve variable dependencies in a configuration.
  """
  @spec resolve_dependencies(t(), map()) :: {:ok, map()} | {:error, term()}
  def resolve_dependencies(space, configuration)
  
  @doc """
  Check if a configuration satisfies all constraints.
  """
  @spec satisfies_constraints?(t(), map()) :: boolean()
  def satisfies_constraints?(space, configuration)
  
  # Analysis and Optimization
  
  @doc """
  Analyze the variable space for optimization characteristics.
  """
  @spec analyze(t()) :: space_analysis()
  def analyze(space)
  
  @doc """
  Get optimization hints for the variable space.
  """
  @spec optimization_hints(t()) :: optimization_hints()
  def optimization_hints(space)
  
  @doc """
  Estimate the size of the search space.
  """
  @spec search_space_size(t()) :: pos_integer() | :infinite
  def search_space_size(space)
  
  @type space_analysis :: %{
    variable_count: pos_integer(),
    discrete_count: pos_integer(),
    continuous_count: pos_integer(),
    hybrid_count: pos_integer(),
    dependency_complexity: atom(),
    constraint_complexity: atom(),
    recommended_strategy: atom(),
    estimated_budget: pos_integer()
  }
end
```

## Schema Definition API

### Variable-Aware Schema System

```elixir
defmodule Elixact.Schema.Variable do
  @moduledoc """
  Schema system that supports variable definitions and runtime schema generation.
  Enables schemas that adapt based on variable configurations.
  """
  
  @doc """
  Define a schema that can adapt based on variable values.
  
  ## Examples
      
      schema :adaptive_response do
        field :content, :string, required: true
        
        # Conditional field based on variable
        conditional_field :reasoning, :string,
          condition: {:reasoning_module, :chain_of_thought},
          required: true,
          min_length: 20
          
        # Variable-dependent validation
        variable_field :confidence, :float,
          variable: :confidence_required,
          when_true: [required: true, gteq: 0.0, lteq: 1.0],
          when_false: [optional: true]
          
        # Dynamic field based on adapter choice
        adapter_field :format_specific,
          json_adapter: [:structured_data, :object, required: true],
          markdown_adapter: [:formatted_text, :string, required: true],
          chat_adapter: [:messages, {:array, :string}, required: true]
      end
  """
  
  @doc """
  Create a variable-aware schema.
  """
  defmacro variable_schema(name, opts \\ [], do: block)
  
  @doc """
  Define a field that's conditional on variable values.
  """
  defmacro conditional_field(name, type, opts)
  
  @doc """
  Define a field that changes based on a variable.
  """
  defmacro variable_field(name, type, opts)
  
  @doc """
  Define a field that adapts to adapter selection.
  """
  defmacro adapter_field(name, adapter_configs)
  
  @doc """
  Define a field that changes based on module selection.
  """
  defmacro module_field(name, module_configs)
  
  @doc """
  Generate a concrete schema from a variable schema and configuration.
  """
  @spec generate_concrete_schema(atom(), map()) :: Elixact.Schema.t()
  def generate_concrete_schema(variable_schema_name, variable_config)
  
  @doc """
  Validate data against a variable schema with configuration.
  """
  @spec validate_with_variables(atom(), any(), map()) :: 
    {:ok, any()} | {:error, [Elixact.ValidationError.t()]}
  def validate_with_variables(variable_schema_name, data, variable_config)
end
```

### Runtime Schema Generation

```elixir
defmodule Elixact.Schema.Runtime do
  @moduledoc """
  Runtime schema generation and modification based on variable configurations.
  Supports dynamic schema creation for optimization and adaptation.
  """
  
  @doc """
  Generate a schema at runtime based on variable configuration.
  
  ## Examples
      
      config = %{
        adapter: DSPEx.Adapters.JSONAdapter,
        reasoning_module: DSPEx.ChainOfThought,
        include_confidence: true
      }
      
      schema = Runtime.generate_schema(:response_schema, config)
  """
  @spec generate_schema(atom(), map()) :: Elixact.Schema.t()
  def generate_schema(schema_template, variable_config)
  
  @doc """
  Modify an existing schema based on variable changes.
  """
  @spec modify_schema(Elixact.Schema.t(), map(), map()) :: Elixact.Schema.t()
  def modify_schema(base_schema, old_config, new_config)
  
  @doc """
  Create a schema that validates variable configurations themselves.
  """
  @spec variable_config_schema(Elixact.VariableSpace.t()) :: Elixact.Schema.t()
  def variable_config_schema(variable_space)
  
  @doc """
  Generate provider-specific schemas based on variable configuration.
  """
  @spec provider_schema(atom(), map()) :: Elixact.Schema.t()
  def provider_schema(provider, config)
  
  @doc """
  Generate adapter-specific schemas.
  """
  @spec adapter_schema(module(), map()) :: Elixact.Schema.t()
  def adapter_schema(adapter_module, config)
  
  @doc """
  Generate module-specific schemas for different reasoning strategies.
  """
  @spec module_schema(module(), map()) :: Elixact.Schema.t()
  def module_schema(module_type, config)
  
  @doc """
  Cache generated schemas for performance.
  """
  @spec cache_schema(atom(), map(), Elixact.Schema.t()) :: :ok
  def cache_schema(template, config, schema)
  
  @doc """
  Retrieve cached schema if available.
  """
  @spec get_cached_schema(atom(), map()) :: {:ok, Elixact.Schema.t()} | :miss
  def get_cached_schema(template, config)
end
```

## Multi-Objective Evaluation API

### Evaluation Framework

```elixir
defmodule Elixact.Evaluation.MultiObjective do
  @moduledoc """
  Multi-objective evaluation system for variable configurations.
  Supports Pareto optimization and complex objective functions.
  """
  
  defstruct [
    :objectives,              # List of objectives
    :weights,                 # Objective weights
    :constraints,             # Evaluation constraints
    :pareto_frontier,         # Current Pareto frontier
    :evaluation_history,      # History of evaluations
    :evaluation_cache,        # Cache for expensive evaluations
    :parallel_config         # Parallel evaluation configuration
  ]
  
  @type t :: %__MODULE__{
    objectives: [objective()],
    weights: %{atom() => float()},
    constraints: [constraint()],
    pareto_frontier: [evaluation_result()],
    evaluation_history: [evaluation_result()],
    evaluation_cache: :ets.tid(),
    parallel_config: parallel_config()
  }
  
  @type objective :: %{
    name: atom(),
    function: evaluation_function(),
    weight: float(),
    direction: :maximize | :minimize,
    validation_schema: Elixact.Schema.t() | nil,
    constraints: [constraint()]
  }
  
  @type evaluation_function :: (map(), evaluation_context() -> evaluation_result())
  @type evaluation_context :: %{
    program: any(),
    training_data: [any()],
    variable_config: map(),
    metadata: map()
  }
  
  @type evaluation_result :: %{
    configuration: map(),
    objective_scores: %{atom() => float()},
    weighted_score: float(),
    pareto_rank: pos_integer() | nil,
    dominance_count: pos_integer(),
    crowding_distance: float(),
    evaluation_time: pos_integer(),
    metadata: map(),
    validation_errors: [Elixact.ValidationError.t()]
  }
  
  @type parallel_config :: %{
    max_concurrency: pos_integer(),
    timeout: pos_integer(),
    chunk_size: pos_integer()
  }
  
  # Evaluator Creation
  
  @doc """
  Create a new multi-objective evaluator.
  """
  @spec new([objective()], keyword()) :: t()
  def new(objectives, opts \\ [])
  
  @doc """
  Create a standard DSPEx multi-objective evaluator.
  """
  @spec dspex_standard_evaluator() :: t()
  def dspex_standard_evaluator()
  
  @doc """
  Create a custom evaluator with specific objectives.
  """
  @spec custom_evaluator(keyword()) :: t()
  def custom_evaluator(objective_specs)
  
  # Evaluation Operations
  
  @doc """
  Evaluate a single configuration across all objectives.
  """
  @spec evaluate(t(), map(), evaluation_context()) :: {evaluation_result(), t()}
  def evaluate(evaluator, configuration, context)
  
  @doc """
  Evaluate multiple configurations in parallel.
  """
  @spec evaluate_multiple(t(), [map()], evaluation_context()) :: {[evaluation_result()], t()}
  def evaluate_multiple(evaluator, configurations, context)
  
  @doc """
  Evaluate configurations with caching and validation.
  """
  @spec evaluate_with_cache(t(), [map()], evaluation_context()) :: {[evaluation_result()], t()}
  def evaluate_with_cache(evaluator, configurations, context)
  
  # Pareto Analysis
  
  @doc """
  Update the Pareto frontier with new evaluation results.
  """
  @spec update_pareto_frontier(t(), [evaluation_result()]) :: t()
  def update_pareto_frontier(evaluator, results)
  
  @doc """
  Get the current Pareto frontier.
  """
  @spec pareto_frontier(t()) :: [evaluation_result()]
  def pareto_frontier(evaluator)
  
  @doc """
  Calculate Pareto dominance between two results.
  """
  @spec dominates?(evaluation_result(), evaluation_result(), [objective()]) :: boolean()
  def dominates?(result_a, result_b, objectives)
  
  @doc """
  Calculate crowding distance for diversity preservation.
  """
  @spec crowding_distance([evaluation_result()], [objective()]) :: [evaluation_result()]
  def crowding_distance(results, objectives)
  
  # Objective Functions
  
  @doc """
  Standard accuracy evaluation objective.
  """
  @spec accuracy_objective(keyword()) :: objective()
  def accuracy_objective(opts \\ [])
  
  @doc """
  Standard cost evaluation objective.
  """
  @spec cost_objective(keyword()) :: objective()
  def cost_objective(opts \\ [])
  
  @doc """
  Standard latency evaluation objective.
  """
  @spec latency_objective(keyword()) :: objective()
  def latency_objective(opts \\ [])
  
  @doc """
  Standard reliability evaluation objective.
  """
  @spec reliability_objective(keyword()) :: objective()
  def reliability_objective(opts \\ [])
  
  @doc """
  Custom objective with validation schema.
  """
  @spec custom_objective(atom(), evaluation_function(), keyword()) :: objective()
  def custom_objective(name, function, opts \\ [])
end
```

### Selection and Decision Making

```elixir
defmodule Elixact.Selection.Strategy do
  @moduledoc """
  Selection strategies for choosing optimal configurations from evaluation results.
  Supports various decision-making approaches and user preferences.
  """
  
  @type selection_strategy :: 
    :pareto_optimal | :weighted_sum | :lexicographic | :goal_programming |
    :topsis | :electre | :promethee | :custom
  
  @type user_preferences :: %{
    objective_weights: %{atom() => float()},
    constraints: [constraint()],
    preferences: [preference()],
    risk_tolerance: float()
  }
  
  @type preference :: 
    {:prefer, atom(), :over, atom()} |
    {:minimum, atom(), float()} |
    {:maximum, atom(), float()} |
    {:target, atom(), float()}
  
  @doc """
  Select the best configuration using the specified strategy.
  """
  @spec select_best(selection_strategy(), [evaluation_result()], user_preferences()) :: 
    evaluation_result()
  def select_best(strategy, results, preferences \\ %{})
  
  @doc """
  Select multiple good configurations for ensemble approaches.
  """
  @spec select_multiple(selection_strategy(), [evaluation_result()], pos_integer(), user_preferences()) :: 
    [evaluation_result()]
  def select_multiple(strategy, results, count, preferences \\ %{})
  
  @doc """
  Rank configurations based on selection strategy.
  """
  @spec rank_configurations([evaluation_result()], selection_strategy(), user_preferences()) :: 
    [evaluation_result()]
  def rank_configurations(results, strategy, preferences \\ %{})
  
  # Specific Selection Strategies
  
  @doc """
  Pareto-optimal selection strategy.
  """
  @spec pareto_optimal_selection([evaluation_result()], keyword()) :: evaluation_result()
  def pareto_optimal_selection(results, opts \\ [])
  
  @doc """
  Weighted sum selection strategy.
  """
  @spec weighted_sum_selection([evaluation_result()], %{atom() => float()}) :: evaluation_result()
  def weighted_sum_selection(results, weights)
  
  @doc """
  TOPSIS (Technique for Order Preference by Similarity to Ideal Solution) selection.
  """
  @spec topsis_selection([evaluation_result()], user_preferences()) :: evaluation_result()
  def topsis_selection(results, preferences)
  
  @doc """
  Custom selection using user-provided function.
  """
  @spec custom_selection([evaluation_result()], (evaluation_result() -> float())) :: evaluation_result()
  def custom_selection(results, scoring_function)
end
```

## Adaptive Configuration API

### Configuration Management

```elixir
defmodule Elixact.Config.Adaptive do
  @moduledoc """
  Adaptive configuration system that applies optimized variable configurations
  to programs and validates the results.
  """
  
  @doc """
  Apply a variable configuration to a program with validation.
  
  ## Examples
      
      config = %{
        adapter: DSPEx.Adapters.JSONAdapter,
        reasoning_module: DSPEx.ChainOfThought,
        temperature: 0.7,
        provider: :openai
      }
      
      {:ok, configured_program} = Adaptive.apply_configuration(
        base_program, 
        config, 
        variable_space,
        validation: true
      )
  """
  @spec apply_configuration(any(), map(), Elixact.VariableSpace.t(), keyword()) :: 
    {:ok, any()} | {:error, [Elixact.ValidationError.t()]}
  def apply_configuration(program, configuration, variable_space, opts \\ [])
  
  @doc """
  Apply configuration with rollback capability.
  """
  @spec apply_with_rollback(any(), map(), Elixact.VariableSpace.t(), keyword()) :: 
    {:ok, any(), rollback_info()} | {:error, [Elixact.ValidationError.t()]}
  def apply_with_rollback(program, configuration, variable_space, opts \\ [])
  
  @doc """
  Rollback a configuration change.
  """
  @spec rollback(any(), rollback_info()) :: {:ok, any()} | {:error, term()}
  def rollback(program, rollback_info)
  
  @doc """
  Validate a configuration before applying it.
  """
  @spec validate_configuration(map(), Elixact.VariableSpace.t()) :: 
    {:ok, map()} | {:error, [Elixact.ValidationError.t()]}
  def validate_configuration(configuration, variable_space)
  
  @doc """
  Generate a configuration diff showing changes.
  """
  @spec configuration_diff(map(), map()) :: configuration_diff()
  def configuration_diff(old_config, new_config)
  
  @type rollback_info :: %{
    original_config: map(),
    applied_changes: [change()],
    timestamp: DateTime.t()
  }
  
  @type change :: %{
    field: atom(),
    old_value: any(),
    new_value: any(),
    change_type: :add | :update | :remove
  }
  
  @type configuration_diff :: %{
    added: [atom()],
    updated: [atom()],
    removed: [atom()],
    changes: [change()]
  }
end
```

### Configuration Templates

```elixir
defmodule Elixact.Config.Templates do
  @moduledoc """
  Pre-defined configuration templates for common optimization scenarios.
  """
  
  @doc """
  High-performance configuration template.
  """
  @spec high_performance_template() :: map()
  def high_performance_template()
  
  @doc """
  Cost-optimized configuration template.
  """
  @spec cost_optimized_template() :: map()
  def cost_optimized_template()
  
  @doc """
  Balanced configuration template.
  """
  @spec balanced_template() :: map()
  def balanced_template()
  
  @doc """
  Development/testing configuration template.
  """
  @spec development_template() :: map()
  def development_template()
  
  @doc """
  Production configuration template.
  """
  @spec production_template() :: map()
  def production_template()
  
  @doc """
  Create a custom template from a configuration.
  """
  @spec create_template(String.t(), map(), keyword()) :: :ok | {:error, term()}
  def create_template(name, configuration, opts \\ [])
  
  @doc """
  Load a saved template.
  """
  @spec load_template(String.t()) :: {:ok, map()} | {:error, term()}
  def load_template(name)
  
  @doc """
  List available templates.
  """
  @spec list_templates() :: [String.t()]
  def list_templates()
end
```

## Constraint System API

### Advanced Constraint Handling

```elixir
defmodule Elixact.Constraints.Advanced do
  @moduledoc """
  Advanced constraint system supporting complex relationships between variables,
  conditional constraints, and constraint solving.
  """
  
  @type constraint_type :: 
    :equality | :inequality | :conditional | :mutual_exclusion | 
    :dependency | :cardinality | :temporal | :resource | :custom
  
  @type constraint :: %{
    id: atom(),
    type: constraint_type(),
    variables: [atom()],
    condition: constraint_condition(),
    validation_schema: Elixact.Schema.t() | nil,
    priority: pos_integer(),
    metadata: map()
  }
  
  @type constraint_condition :: 
    {:eq, atom(), any()} |
    {:neq, atom(), any()} |
    {:lt, atom(), number()} |
    {:lte, atom(), number()} |
    {:gt, atom(), number()} |
    {:gte, atom(), number()} |
    {:in, atom(), [any()]} |
    {:not_in, atom(), [any()]} |
    {:and, [constraint_condition()]} |
    {:or, [constraint_condition()]} |
    {:not, constraint_condition()} |
    {:custom, (map() -> boolean())}
  
  @doc """
  Define an equality constraint between variables.
  """
  @spec equality_constraint(atom(), atom(), any()) :: constraint()
  def equality_constraint(id, var1, var2_or_value)
  
  @doc """
  Define an inequality constraint.
  """
  @spec inequality_constraint(atom(), atom(), :lt | :lte | :gt | :gte, number()) :: constraint()
  def inequality_constraint(id, variable, operator, value)
  
  @doc """
  Define a conditional constraint that applies only when a condition is met.
  """
  @spec conditional_constraint(atom(), constraint_condition(), constraint()) :: constraint()
  def conditional_constraint(id, condition, then_constraint)
  
  @doc """
  Define a mutual exclusion constraint (only one variable can be active).
  """
  @spec mutual_exclusion_constraint(atom(), [atom()]) :: constraint()
  def mutual_exclusion_constraint(id, variables)
  
  @doc """
  Define a dependency constraint (variable A requires variable B).
  """
  @spec dependency_constraint(atom(), atom(), atom()) :: constraint()
  def dependency_constraint(id, dependent_var, required_var)
  
  @doc """
  Define a cardinality constraint (exactly N variables must be active).
  """
  @spec cardinality_constraint(atom(), [atom()], pos_integer()) :: constraint()
  def cardinality_constraint(id, variables, count)
  
  @doc """
  Define a resource constraint (total resource usage cannot exceed limit).
  """
  @spec resource_constraint(atom(), %{atom() => number()}, number()) :: constraint()
  def resource_constraint(id, resource_usage, limit)
  
  @doc """
  Define a custom constraint with validation schema.
  """
  @spec custom_constraint(atom(), (map() -> boolean()), keyword()) :: constraint()
  def custom_constraint(id, validation_fn, opts \\ [])
  
  @doc """
  Validate a configuration against a set of constraints.
  """
  @spec validate_constraints([constraint()], map()) :: 
    {:ok, map()} | {:error, [constraint_violation()]}
  def validate_constraints(constraints, configuration)
  
  @doc """
  Solve constraints to find valid configurations.
  """
  @spec solve_constraints([constraint()], Elixact.VariableSpace.t(), keyword()) :: 
    {:ok, [map()]} | {:error, term()}
  def solve_constraints(constraints, variable_space, opts \\ [])
  
  @type constraint_violation :: %{
    constraint_id: atom(),
    constraint_type: constraint_type(),
    variables: [atom()],
    violation_type: atom(),
    message: String.t(),
    suggested_fix: String.t() | nil
  }
end
```

## Integration APIs

### DSPEx Integration

```elixir
defmodule Elixact.Integration.DSPEx do
  @moduledoc """
  Integration layer between Elixact and DSPEx for variable-aware optimization.
  """
  
  @doc """
  Create a variable-aware DSPEx signature.
  """
  defmacro variable_signature(name, opts \\ [], do: block)
  
  @doc """
  Enhance a DSPEx program with variable support.
  """
  @spec enhance_program(any(), Elixact.VariableSpace.t()) :: any()
  def enhance_program(program, variable_space)
  
  @doc """
  Create a variable-aware teleprompter.
  """
  @spec variable_teleprompter(module(), Elixact.VariableSpace.t(), keyword()) :: any()
  def variable_teleprompter(base_teleprompter, variable_space, opts \\ [])
  
  @doc """
  Optimize a DSPEx program using the variable system.
  """
  @spec optimize_program(any(), [any()], function(), keyword()) :: 
    {:ok, any(), optimization_result()} | {:error, term()}
  def optimize_program(program, training_data, metric_fn, opts \\ [])
  
  @type optimization_result :: %{
    best_configuration: map(),
    all_evaluations: [evaluation_result()],
    pareto_frontier: [evaluation_result()],
    optimization_history: [optimization_step()],
    performance_metrics: map()
  }
  
  @type optimization_step :: %{
    step: pos_integer(),
    configuration: map(),
    score: float(),
    improvement: float(),
    timestamp: DateTime.t()
  }
end
```

### Teleprompter Integration

```elixir
defmodule Elixact.Integration.Teleprompter do
  @moduledoc """
  Integration with DSPEx teleprompters for variable-aware optimization.
  """
  
  @doc """
  Enhance SIMBA with variable optimization.
  """
  @spec enhance_simba(keyword()) :: module()
  def enhance_simba(opts \\ [])
  
  @doc """
  Enhance BEACON with variable optimization.
  """
  @spec enhance_beacon(keyword()) :: module()
  def enhance_beacon(opts \\ [])
  
  @doc """
  Enhance BootstrapFewShot with variable optimization.
  """
  @spec enhance_bootstrap_fewshot(keyword()) :: module()
  def enhance_bootstrap_fewshot(opts \\ [])
  
  @doc """
  Create a universal teleprompter that works with any variable space.
  """
  @spec universal_teleprompter(Elixact.VariableSpace.t(), keyword()) :: module()
  def universal_teleprompter(variable_space, opts \\ [])
end
```

## Usage Examples

### Complete Variable System Setup

```elixir
# Define variable space
variable_space = Elixact.VariableSpace.new()
  |> Elixact.VariableSpace.add_variable(
    Elixact.Variable.discrete(:adapter, [
      DSPEx.Adapters.JSONAdapter,
      DSPEx.Adapters.ChatAdapter,
      DSPEx.Adapters.MarkdownAdapter
    ], 
    description: "Response format adapter",
    validation_schema: adapter_schema()
    )
  )
  |> Elixact.VariableSpace.add_variable(
    Elixact.Variable.discrete(:reasoning_module, [
      DSPEx.Predict,
      DSPEx.ChainOfThought,
      DSPEx.ProgramOfThought
    ],
    description: "Reasoning strategy",
    validation_schema: module_schema()
    )
  )
  |> Elixact.VariableSpace.add_variable(
    Elixact.Variable.continuous(:temperature, {0.0, 2.0},
      default: 0.7,
      validation_schema: temperature_schema()
    )
  )

# Create multi-objective evaluator
evaluator = Elixact.Evaluation.MultiObjective.dspex_standard_evaluator()

# Define program with variable schema
defmodule MyProgram do
  use Elixact.Integration.DSPEx
  
  variable_signature "Question Answering with Variables" do
    input :question, :string, required: true, min_length: 5
    output :answer, :string, required: true, min_length: 10
    
    # Variable-dependent fields
    conditional_field :reasoning, :string,
      condition: {:reasoning_module, DSPEx.ChainOfThought},
      required: true
      
    variable_field :confidence, :float,
      variable: :include_confidence,
      when_true: [required: true, gteq: 0.0, lteq: 1.0],
      when_false: [optional: true]
  end
end

# Run optimization
{:ok, optimized_program, results} = Elixact.Integration.DSPEx.optimize_program(
  MyProgram.new(),
  training_data,
  &accuracy_metric/2,
  variable_space: variable_space,
  evaluator: evaluator,
  budget: 50,
  strategy: :multi_objective
)

# Apply best configuration
{:ok, final_program} = Elixact.Config.Adaptive.apply_configuration(
  base_program,
  results.best_configuration,
  variable_space,
  validation: true
)
```

## Summary

This comprehensive Elixact API provides complete support for the Variable System architecture, enabling:

- **Variable Abstraction**: Discrete, continuous, hybrid, conditional, and composite variables
- **Variable Space Management**: Collections of variables with dependencies and constraints
- **Multi-Objective Evaluation**: Pareto optimization with complex objective functions
- **Adaptive Configuration**: Dynamic configuration application with validation
- **Runtime Schema Generation**: Schemas that adapt based on variable configurations
- **Advanced Constraints**: Complex relationships and constraint solving
- **DSPEx Integration**: Seamless integration with DSPEx programs and teleprompters

The API supports Omar Khattab's vision of decoupled parameter optimization where any optimizer can tune any discrete parameter automatically, with full validation and multi-objective optimization capabilities.
