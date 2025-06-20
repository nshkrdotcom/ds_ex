# Phase 1: Resource Framework Design
*Ash-Inspired Resource Management for ElixirML/DSPEx*

## Executive Summary

The Resource Framework provides the enterprise-grade foundation for ElixirML/DSPEx, treating programs, optimizations, and configurations as first-class Ash resources. This system enables declarative resource modeling, automatic API generation, real-time subscriptions, and policy-based access control while maintaining seamless integration with the Schema Engine and Variable System.

## Design Philosophy

### Core Principles

1. **Resources as First-Class Citizens**: Programs, variables, optimizations are all resources
2. **Declarative Configuration**: Define behavior through resource attributes and relationships
3. **Automatic API Generation**: GraphQL, REST, and LiveView APIs generated automatically
4. **Enterprise Features**: Built-in authentication, authorization, and audit trails
5. **Real-Time Intelligence**: Live subscriptions to optimization progress and results

### Strategic Advantages

- **Enterprise Ready**: Production-grade features out of the box
- **Developer Productivity**: Automatic API generation and admin interfaces
- **Scalability**: Built on Ash's proven architecture patterns
- **Flexibility**: Extensible resource definitions with custom actions
- **Integration**: Native support for Schema validation and Variable optimization

## Architecture Overview

```
Resource Framework Architecture
├── Core Resource System
│   ├── Program Resources
│   ├── Variable Space Resources
│   ├── Optimization Resources
│   └── Configuration Resources
├── Enterprise Features
│   ├── Authentication & Authorization
│   ├── Policy Engine
│   ├── Audit Logging
│   └── Multi-Tenancy Support
├── API Generation
│   ├── GraphQL API
│   ├── REST API
│   ├── LiveView Admin
│   └── Real-Time Subscriptions
├── Integration Layer
│   ├── Schema Engine Integration
│   ├── Variable System Integration
│   ├── Process Orchestrator Integration
│   └── External System Connectors
└── Developer Experience
    ├── Resource Definition DSL
    ├── Admin Dashboard
    ├── Query Builder
    └── Performance Analytics
```

## Core Resource Definitions

### 1. Program Resource

```elixir
defmodule ElixirML.Resources.Program do
  use Ash.Resource,
    domain: ElixirML.Domain,
    data_layer: AshPostgres.DataLayer

  use ElixirML.Schema.ResourceIntegration

  postgres do
    table "programs"
    repo ElixirML.Repo

    references do
      reference :variable_space, on_delete: :nilify
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints max_length: 255
    end

    attribute :description, :string do
      constraints max_length: 1000
    end

    attribute :type, :atom do
      allow_nil? false
      constraints one_of: [:predict, :chain_of_thought, :react, :custom]
    end

    schema_attribute :signature_config, ElixirML.Schemas.Program.SignatureConfig do
      allow_nil? false
    end

    schema_attribute :program_config, ElixirML.Schemas.Program.ProgramConfig do
      default %{}
    end

    attribute :status, :atom do
      default :draft
      constraints one_of: [:draft, :active, :optimizing, :archived]
    end

    schema_attribute :performance_metrics, ElixirML.Schemas.Program.PerformanceMetrics do
      default %{}
    end

    attribute :version, :integer do
      default 1
      constraints min: 1
    end

    timestamps()
  end

  relationships do
    belongs_to :variable_space, ElixirML.Resources.VariableSpace do
      allow_nil? true
    end

    belongs_to :parent_program, ElixirML.Resources.Program do
      allow_nil? true
    end

    has_many :child_programs, ElixirML.Resources.Program do
      destination_attribute :parent_program_id
    end

    has_many :optimization_runs, ElixirML.Resources.OptimizationRun do
      destination_attribute :program_id
    end

    has_many :executions, ElixirML.Resources.Execution do
      destination_attribute :program_id
    end

    has_many :evaluations, ElixirML.Resources.Evaluation do
      destination_attribute :program_id
    end

    many_to_many :tags, ElixirML.Resources.Tag do
      through ElixirML.Resources.ProgramTag
      source_attribute_on_join_resource :program_id
      destination_attribute_on_join_resource :tag_id
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :create_with_variable_space do
      accept [:name, :description, :type, :signature_config, :program_config]
      
      argument :variable_definitions, {:array, :map} do
        allow_nil? false
      end

      change fn changeset, _context ->
        variable_definitions = Ash.Changeset.get_argument(changeset, :variable_definitions)
        
        # Create variable space
        {:ok, variable_space} = ElixirML.Resources.VariableSpace.create(%{
          name: "#{Ash.Changeset.get_attribute(changeset, :name)} Variables",
          variable_definitions: variable_definitions
        })

        Ash.Changeset.change_attribute(changeset, :variable_space_id, variable_space.id)
      end
    end

    action :execute, ElixirML.Resources.Execution do
      argument :inputs, :map do
        allow_nil? false
      end

      argument :variable_configuration, :map do
        default %{}
      end

      argument :execution_options, :map do
        default %{}
      end

      run ElixirML.Actions.ExecuteProgram
    end

    action :optimize, ElixirML.Resources.OptimizationRun do
      argument :training_data, {:array, :map} do
        allow_nil? false
      end

      argument :optimization_strategy, :atom do
        default :simba
        constraints one_of: [:simba, :bayesian, :grid_search, :random]
      end

      argument :optimization_config, :map do
        default %{}
      end

      run ElixirML.Actions.OptimizeProgram
    end

    action :clone, ElixirML.Resources.Program do
      argument :new_name, :string do
        allow_nil? false
      end

      run fn input, context ->
        program = input.resource
        
        {:ok, cloned} = ElixirML.Resources.Program.create(%{
          name: input.arguments.new_name,
          description: "Clone of #{program.name}",
          type: program.type,
          signature_config: program.signature_config,
          program_config: program.program_config,
          variable_space_id: program.variable_space_id,
          parent_program_id: program.id
        })

        {:ok, cloned}
      end
    end

    update :update_performance_metrics do
      accept []
      
      argument :metrics, :map do
        allow_nil? false
      end

      change fn changeset, _context ->
        new_metrics = Ash.Changeset.get_argument(changeset, :metrics)
        current_metrics = Ash.Changeset.get_attribute(changeset, :performance_metrics) || %{}
        
        updated_metrics = Map.merge(current_metrics, new_metrics)
        Ash.Changeset.change_attribute(changeset, :performance_metrics, updated_metrics)
      end
    end

    destroy :archive do
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :archived)
      end

      soft? true
    end
  end

  calculations do
    calculate :current_performance_score, :float, ElixirML.Calculations.CurrentPerformanceScore

    calculate :optimization_count, :integer do
      ElixirML.Calculations.OptimizationCount
    end

    calculate :average_execution_time, :float do
      ElixirML.Calculations.AverageExecutionTime
    end

    calculate :cost_efficiency_ratio, :float do
      ElixirML.Calculations.CostEfficiencyRatio
    end

    calculate :variable_importance_scores, {:array, :map} do
      ElixirML.Calculations.VariableImportanceScores
    end
  end

  aggregates do
    count :execution_count, :executions
    avg :avg_performance, :evaluations, :score
    max :best_performance, :evaluations, :score
    sum :total_cost, :executions, :cost
  end

  validations do
    validate compare(:version, greater_than: 0), message: "Version must be positive"
    
    validate fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :type) do
        :custom ->
          # Custom programs require additional validation
          signature_config = Ash.Changeset.get_attribute(changeset, :signature_config)
          if Map.has_key?(signature_config, :custom_implementation) do
            :ok
          else
            {:error, field: :signature_config, message: "Custom programs require custom_implementation"}
          end
        _ -> :ok
      end
    end
  end

  policies do
    # Default policy - users can read their own programs
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:id, :user_id)
    end

    # Creation policy - authenticated users can create programs
    policy action_type(:create) do
      authorize_if actor_present()
    end

    # Update policy - only program owners can update
    policy action_type(:update) do
      authorize_if actor_attribute_equals(:id, :user_id)
    end

    # Admin policy - admins can do anything
    policy always() do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  pub_sub do
    module ElixirML.PubSub
    prefix "program"

    publish_all :create, ["created"]
    publish :update, ["updated", :id]
    publish :destroy, ["deleted", :id]
    
    # Custom publications for ML-specific events
    publish :execute, ["executed", :id]
    publish :optimize, ["optimization_started", :id]
  end
end
```

### 2. Variable Space Resource

```elixir
defmodule ElixirML.Resources.VariableSpace do
  use Ash.Resource,
    domain: ElixirML.Domain,
    data_layer: AshPostgres.DataLayer

  use ElixirML.Schema.ResourceIntegration

  postgres do
    table "variable_spaces"
    repo ElixirML.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints max_length: 255
    end

    attribute :description, :string do
      constraints max_length: 1000
    end

    schema_attribute :variable_definitions, ElixirML.Schemas.Variable.VariableDefinitions do
      allow_nil? false
    end

    schema_attribute :constraints, ElixirML.Schemas.Variable.Constraints do
      default %{dependencies: [], validations: []}
    end

    schema_attribute :optimization_hints, ElixirML.Schemas.Variable.OptimizationHints do
      default %{}
    end

    attribute :discrete_space_size, :integer do
      default 1
      constraints min: 1
    end

    attribute :continuous_dimensions, :integer do
      default 0
      constraints min: 0
    end

    timestamps()
  end

  relationships do
    has_many :programs, ElixirML.Resources.Program do
      destination_attribute :variable_space_id
    end

    has_many :optimization_runs, ElixirML.Resources.OptimizationRun do
      destination_attribute :variable_space_id
    end

    has_many :configurations, ElixirML.Resources.VariableConfiguration do
      destination_attribute :variable_space_id
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :create_from_definitions do
      accept [:name, :description]
      
      argument :variable_definitions, {:array, :map} do
        allow_nil? false
      end

      change fn changeset, _context ->
        definitions = Ash.Changeset.get_argument(changeset, :variable_definitions)
        
        # Validate and process variable definitions
        processed_definitions = process_variable_definitions(definitions)
        
        # Calculate space metrics
        discrete_size = calculate_discrete_space_size(processed_definitions)
        continuous_dims = calculate_continuous_dimensions(processed_definitions)

        changeset
        |> Ash.Changeset.change_attribute(:variable_definitions, processed_definitions)
        |> Ash.Changeset.change_attribute(:discrete_space_size, discrete_size)
        |> Ash.Changeset.change_attribute(:continuous_dimensions, continuous_dims)
      end
    end

    action :generate_configuration, ElixirML.Resources.VariableConfiguration do
      argument :strategy, :atom do
        default :random
        constraints one_of: [:random, :grid_point, :latin_hypercube, :sobol]
      end

      argument :seed, :integer do
        allow_nil? true
      end

      run ElixirML.Actions.GenerateVariableConfiguration
    end

    action :validate_configuration, :boolean do
      argument :configuration, :map do
        allow_nil? false
      end

      run fn input, _context ->
        variable_space = input.resource
        configuration = input.arguments.configuration
        
        case ElixirML.Variable.Space.validate_configuration(
          convert_to_variable_space(variable_space), 
          configuration
        ) do
          {:ok, _} -> {:ok, true}
          {:error, _} -> {:ok, false}
        end
      end
    end

    action :analyze_variable_importance, {:array, :map} do
      argument :optimization_runs, {:array, :uuid} do
        allow_nil? false
      end

      run ElixirML.Actions.AnalyzeVariableImportance
    end

    update :add_variable do
      accept []
      
      argument :variable_definition, :map do
        allow_nil? false
      end

      change fn changeset, _context ->
        new_var = Ash.Changeset.get_argument(changeset, :variable_definition)
        current_definitions = Ash.Changeset.get_attribute(changeset, :variable_definitions)
        
        updated_definitions = [new_var | current_definitions]
        
        # Recalculate space metrics
        discrete_size = calculate_discrete_space_size(updated_definitions)
        continuous_dims = calculate_continuous_dimensions(updated_definitions)

        changeset
        |> Ash.Changeset.change_attribute(:variable_definitions, updated_definitions)
        |> Ash.Changeset.change_attribute(:discrete_space_size, discrete_size)
        |> Ash.Changeset.change_attribute(:continuous_dimensions, continuous_dims)
      end
    end
  end

  calculations do
    calculate :variable_count, :integer do
      ElixirML.Calculations.VariableCount
    end

    calculate :complexity_score, :float do
      ElixirML.Calculations.ComplexityScore
    end

    calculate :optimization_difficulty, :atom do
      ElixirML.Calculations.OptimizationDifficulty
    end
  end

  aggregates do
    count :program_count, :programs
    count :optimization_count, :optimization_runs
    count :configuration_count, :configurations
  end

  validations do
    validate fn changeset, _context ->
      definitions = Ash.Changeset.get_attribute(changeset, :variable_definitions)
      
      # Validate unique variable names
      names = Enum.map(definitions, & &1["name"])
      if length(names) == length(Enum.uniq(names)) do
        :ok
      else
        {:error, field: :variable_definitions, message: "Variable names must be unique"}
      end
    end
  end

  defp process_variable_definitions(definitions) do
    # Process and validate variable definitions
    definitions
    |> Enum.map(&normalize_variable_definition/1)
    |> Enum.map(&validate_variable_definition/1)
  end

  defp normalize_variable_definition(definition) do
    # Normalize variable definition format
    definition
    |> Map.put_new("metadata", %{})
    |> Map.put_new("constraints", %{})
  end

  defp validate_variable_definition(definition) do
    # Validate individual variable definition
    required_fields = ["name", "type"]
    
    case Enum.all?(required_fields, &Map.has_key?(definition, &1)) do
      true -> definition
      false -> raise "Variable definition missing required fields: #{inspect(required_fields)}"
    end
  end

  defp calculate_discrete_space_size(definitions) do
    definitions
    |> Enum.map(&discrete_variable_size/1)
    |> Enum.reduce(1, &*/2)
  end

  defp calculate_continuous_dimensions(definitions) do
    definitions
    |> Enum.count(fn def -> def["type"] in ["float", "integer"] end)
  end

  defp discrete_variable_size(%{"type" => "choice", "constraints" => %{"choices" => choices}}) do
    length(choices)
  end

  defp discrete_variable_size(%{"type" => "module", "constraints" => %{"modules" => modules}}) do
    length(modules)
  end

  defp discrete_variable_size(_), do: 1

  defp convert_to_variable_space(resource) do
    # Convert Ash resource to ElixirML.Variable.Space
    %ElixirML.Variable.Space{
      id: resource.id,
      name: resource.name,
      variables: convert_variable_definitions(resource.variable_definitions),
      constraints: resource.constraints["validations"] || [],
      dependencies: resource.constraints["dependencies"] || %{},
      metadata: %{
        discrete_space_size: resource.discrete_space_size,
        continuous_dimensions: resource.continuous_dimensions
      }
    }
  end

  defp convert_variable_definitions(definitions) do
    definitions
    |> Enum.map(&convert_variable_definition/1)
    |> Map.new(fn var -> {var.name, var} end)
  end

  defp convert_variable_definition(definition) do
    %ElixirML.Variable{
      name: String.to_atom(definition["name"]),
      type: String.to_atom(definition["type"]),
      default: definition["default"],
      constraints: definition["constraints"],
      description: definition["description"],
      metadata: definition["metadata"]
    }
  end
end
```

### 3. Optimization Run Resource

```elixir
defmodule ElixirML.Resources.OptimizationRun do
  use Ash.Resource,
    domain: ElixirML.Domain,
    data_layer: AshPostgres.DataLayer

  use ElixirML.Schema.ResourceIntegration

  postgres do
    table "optimization_runs"
    repo ElixirML.Repo

    references do
      reference :program, on_delete: :delete
      reference :variable_space, on_delete: :delete
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints max_length: 255
    end

    attribute :strategy, :atom do
      allow_nil? false
      constraints one_of: [:simba, :bayesian, :grid_search, :random, :evolutionary]
    end

    attribute :status, :atom do
      default :pending
      constraints one_of: [:pending, :running, :completed, :failed, :cancelled]
    end

    schema_attribute :configuration, ElixirML.Schemas.Optimization.Configuration do
      allow_nil? false
    end

    schema_attribute :training_data, ElixirML.Schemas.Optimization.TrainingData do
      allow_nil? false
    end

    schema_attribute :results, ElixirML.Schemas.Optimization.Results do
      default %{}
    end

    schema_attribute :pareto_frontier, ElixirML.Schemas.Optimization.ParetoFrontier do
      default %{points: [], objectives: []}
    end

    attribute :iterations_completed, :integer do
      default 0
      constraints min: 0
    end

    attribute :max_iterations, :integer do
      default 100
      constraints min: 1
    end

    attribute :best_score, :float do
      constraints min: 0.0, max: 1.0
    end

    attribute :convergence_score, :float do
      constraints min: 0.0, max: 1.0
    end

    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime

    timestamps()
  end

  relationships do
    belongs_to :program, ElixirML.Resources.Program do
      allow_nil? false
    end

    belongs_to :variable_space, ElixirML.Resources.VariableSpace do
      allow_nil? false
    end

    has_many :evaluations, ElixirML.Resources.Evaluation do
      destination_attribute :optimization_run_id
    end

    has_many :configurations_tested, ElixirML.Resources.VariableConfiguration do
      destination_attribute :optimization_run_id
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :start_optimization do
      accept [:name, :strategy, :configuration, :training_data, :max_iterations]
      
      argument :program_id, :uuid do
        allow_nil? false
      end

      change fn changeset, _context ->
        program_id = Ash.Changeset.get_argument(changeset, :program_id)
        
        # Load program and variable space
        program = ElixirML.Resources.Program.get!(program_id, load: [:variable_space])
        
        changeset
        |> Ash.Changeset.change_attribute(:program_id, program.id)
        |> Ash.Changeset.change_attribute(:variable_space_id, program.variable_space.id)
        |> Ash.Changeset.change_attribute(:status, :pending)
      end

      after_action fn changeset, optimization_run, _context ->
        # Start the optimization process asynchronously
        Task.Supervisor.start_child(ElixirML.TaskSupervisor, fn ->
          ElixirML.Optimization.Runner.execute(optimization_run)
        end)

        {:ok, optimization_run}
      end
    end

    update :update_progress do
      accept [:iterations_completed, :best_score, :convergence_score]
      
      argument :new_evaluation, :map do
        allow_nil? true
      end

      argument :pareto_point, :map do
        allow_nil? true
      end

      change fn changeset, _context ->
        # Update pareto frontier if new point provided
        if pareto_point = Ash.Changeset.get_argument(changeset, :pareto_point) do
          current_frontier = Ash.Changeset.get_attribute(changeset, :pareto_frontier)
          updated_frontier = add_to_pareto_frontier(current_frontier, pareto_point)
          
          Ash.Changeset.change_attribute(changeset, :pareto_frontier, updated_frontier)
        else
          changeset
        end
      end
    end

    update :complete do
      accept []
      
      argument :final_results, :map do
        allow_nil? false
      end

      change fn changeset, _context ->
        final_results = Ash.Changeset.get_argument(changeset, :final_results)
        
        changeset
        |> Ash.Changeset.change_attribute(:status, :completed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:results, final_results)
      end
    end

    update :fail do
      accept []
      
      argument :error_message, :string do
        allow_nil? false
      end

      change fn changeset, _context ->
        error_message = Ash.Changeset.get_argument(changeset, :error_message)
        
        current_results = Ash.Changeset.get_attribute(changeset, :results) || %{}
        error_results = Map.put(current_results, :error, error_message)

        changeset
        |> Ash.Changeset.change_attribute(:status, :failed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:results, error_results)
      end
    end

    action :cancel do
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :cancelled)
      end
    end

    action :get_best_configuration, :map do
      run fn input, _context ->
        optimization_run = input.resource
        
        case optimization_run.results do
          %{"best_configuration" => config} -> {:ok, config}
          _ -> {:error, "No best configuration available"}
        end
      end
    end
  end

  calculations do
    calculate :duration_seconds, :integer do
      ElixirML.Calculations.OptimizationDuration
    end

    calculate :progress_percentage, :float do
      ElixirML.Calculations.OptimizationProgress
    end

    calculate :convergence_status, :atom do
      ElixirML.Calculations.ConvergenceStatus
    end

    calculate :estimated_completion, :utc_datetime do
      ElixirML.Calculations.EstimatedCompletion
    end
  end

  aggregates do
    count :evaluation_count, :evaluations
    avg :average_score, :evaluations, :score
    max :best_evaluation_score, :evaluations, :score
  end

  validations do
    validate compare(:iterations_completed, less_than_or_equal_to: :max_iterations),
      message: "Completed iterations cannot exceed maximum"
    
    validate fn changeset, _context ->
      started_at = Ash.Changeset.get_attribute(changeset, :started_at)
      completed_at = Ash.Changeset.get_attribute(changeset, :completed_at)
      
      case {started_at, completed_at} do
        {nil, nil} -> :ok
        {start, nil} when not is_nil(start) -> :ok
        {start, finish} when not is_nil(start) and not is_nil(finish) ->
          if DateTime.compare(start, finish) in [:lt, :eq] do
            :ok
          else
            {:error, field: :completed_at, message: "Completion time must be after start time"}
          end
        _ -> {:error, field: :started_at, message: "Start time required if completion time is set"}
      end
    end
  end

  pub_sub do
    module ElixirML.PubSub
    prefix "optimization"

    publish_all :create, ["started"]
    publish :update, ["progress", :id]
    publish :complete, ["completed", :id]
    publish :fail, ["failed", :id]
  end

  defp add_to_pareto_frontier(current_frontier, new_point) do
    current_points = current_frontier["points"] || []
    
    # Simple Pareto frontier update (in real implementation would be more sophisticated)
    updated_points = [new_point | current_points]
    |> Enum.uniq_by(fn point -> point["configuration"] end)
    |> Enum.take(100)  # Limit frontier size
    
    %{current_frontier | "points" => updated_points}
  end
end
```

## Enterprise Features

### 1. Authentication & Authorization

```elixir
defmodule ElixirML.Resources.User do
  use Ash.Resource,
    domain: ElixirML.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "users"
    repo ElixirML.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :string do
      allow_nil? false
      constraints format: ~r/^[^\s]+@[^\s]+\.[^\s]+$/
    end

    attribute :name, :string do
      allow_nil? false
      constraints max_length: 255
    end

    attribute :role, :atom do
      default :user
      constraints one_of: [:user, :admin, :viewer]
    end

    attribute :organization, :string do
      constraints max_length: 255
    end

    attribute :preferences, :map do
      default %{}
    end

    attribute :api_key_hash, :string do
      sensitive? true
    end

    attribute :last_login_at, :utc_datetime
    attribute :active, :boolean, default: true

    timestamps()
  end

  relationships do
    has_many :programs, ElixirML.Resources.Program do
      destination_attribute :user_id
    end

    has_many :optimization_runs, ElixirML.Resources.OptimizationRun do
      destination_attribute :user_id
    end
  end

  actions do
    defaults [:create, :read, :update]

    create :register do
      accept [:email, :name, :organization]
      
      change fn changeset, _context ->
        # Generate API key
        api_key = generate_api_key()
        api_key_hash = hash_api_key(api_key)
        
        changeset
        |> Ash.Changeset.change_attribute(:api_key_hash, api_key_hash)
        |> Ash.Changeset.after_action(fn _changeset, user ->
          # Return user with API key (only time it's visible)
          {:ok, Map.put(user, :api_key, api_key)}
        end)
      end
    end

    action :authenticate do
      argument :email, :string, allow_nil?: false
      argument :api_key, :string, allow_nil?: false
      
      run fn input, _context ->
        user = ElixirML.Resources.User.get_by_email!(input.arguments.email)
        
        if verify_api_key(input.arguments.api_key, user.api_key_hash) do
          # Update last login
          ElixirML.Resources.User.update!(user, %{last_login_at: DateTime.utc_now()})
          {:ok, user}
        else
          {:error, "Invalid credentials"}
        end
      end
    end

    update :regenerate_api_key do
      change fn changeset, _context ->
        api_key = generate_api_key()
        api_key_hash = hash_api_key(api_key)
        
        changeset
        |> Ash.Changeset.change_attribute(:api_key_hash, api_key_hash)
        |> Ash.Changeset.after_action(fn _changeset, user ->
          {:ok, Map.put(user, :api_key, api_key)}
        end)
      end
    end
  end

  validations do
    validate unique(:email), message: "Email already exists"
  end

  defp generate_api_key do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

  defp hash_api_key(api_key) do
    :crypto.hash(:sha256, api_key) |> Base.encode64()
  end

  defp verify_api_key(api_key, hash) do
    hash_api_key(api_key) == hash
  end
end
```

### 2. Policy Engine

```elixir
defmodule ElixirML.Policies.ProgramPolicy do
  use Ash.Policy.SimpleCheck

  def describe(_), do: "Program access policy"

  def match?(actor, resource, _context) do
    cond do
      # Admins can access everything
      actor.role == :admin -> true
      
      # Users can access their own programs
      resource.user_id == actor.id -> true
      
      # Users can read public programs in their organization
      resource.visibility == :public and resource.organization == actor.organization -> true
      
      # Viewers can only read
      actor.role == :viewer -> false
      
      # Default deny
      true -> false
    end
  end
end

defmodule ElixirML.Policies.OptimizationPolicy do
  use Ash.Policy.SimpleCheck

  def describe(_), do: "Optimization access policy"

  def match?(actor, resource, _context) do
    # Load the associated program
    program = ElixirML.Resources.Program.get!(resource.program_id)
    
    # Apply program policy
    ElixirML.Policies.ProgramPolicy.match?(actor, program, _context)
  end
end
```

### 3. Audit Logging

```elixir
defmodule ElixirML.Resources.AuditLog do
  use Ash.Resource,
    domain: ElixirML.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "audit_logs"
    repo ElixirML.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :action, :string do
      allow_nil? false
    end

    attribute :resource_type, :string do
      allow_nil? false
    end

    attribute :resource_id, :uuid

    attribute :actor_id, :uuid
    attribute :actor_type, :string, default: "User"

    attribute :changes, :map do
      default %{}
    end

    attribute :metadata, :map do
      default %{}
    end

    attribute :ip_address, :string
    attribute :user_agent, :string

    timestamps(updated_at: false)
  end

  actions do
    defaults [:create, :read]

    create :log_action do
      accept [:action, :resource_type, :resource_id, :actor_id, :changes, :metadata, :ip_address, :user_agent]
    end
  end

  # No updates or deletes - audit logs are immutable
end

# Audit logging hook
defmodule ElixirML.AuditHook do
  use Ash.Notifier

  def notify(%Ash.Notifier.Notification{} = notification) do
    # Log all resource changes
    ElixirML.Resources.AuditLog.create!(%{
      action: to_string(notification.action.name),
      resource_type: notification.resource |> Module.split() |> List.last(),
      resource_id: notification.data.id,
      actor_id: notification.actor && notification.actor.id,
      changes: extract_changes(notification),
      metadata: %{
        domain: notification.domain,
        timestamp: DateTime.utc_now()
      }
    })
  end

  defp extract_changes(notification) do
    case notification.changeset do
      nil -> %{}
      changeset -> Ash.Changeset.get_changes(changeset)
    end
  end
end
```

## API Generation

### 1. GraphQL API

```elixir
defmodule ElixirMLWeb.Schema do
  use Absinthe.Schema
  use AshGraphql, domains: [ElixirML.Domain]

  query do
    # Automatically generated queries for all resources
  end

  mutation do
    # Automatically generated mutations
  end

  subscription do
    field :optimization_progress, :optimization_run do
      arg :id, non_null(:id)
      
      config fn args, %{context: %{current_user: user}} ->
        # Verify user has access to this optimization
        optimization = ElixirML.Resources.OptimizationRun.get!(args.id)
        
        if can_access_optimization?(user, optimization) do
          {:ok, topic: "optimization:progress:#{args.id}"}
        else
          {:error, "Access denied"}
        end
      end

      trigger :update_optimization_progress, topic: fn optimization ->
        "optimization:progress:#{optimization.id}"
      end
    end

    field :program_execution, :execution do
      arg :program_id, non_null(:id)
      
      config fn args, %{context: %{current_user: user}} ->
        program = ElixirML.Resources.Program.get!(args.program_id)
        
        if can_access_program?(user, program) do
          {:ok, topic: "program:execution:#{args.program_id}"}
        else
          {:error, "Access denied"}
        end
      end

      trigger :program_executed, topic: fn execution ->
        "program:execution:#{execution.program_id}"
      end
    end

    field :pareto_frontier_update, :pareto_point do
      arg :optimization_id, non_null(:id)
      
      config fn args, %{context: %{current_user: user}} ->
        optimization = ElixirML.Resources.OptimizationRun.get!(args.optimization_id)
        
        if can_access_optimization?(user, optimization) do
          {:ok, topic: "pareto:#{args.optimization_id}"}
        else
          {:error, "Access denied"}
        end
      end

      trigger :pareto_frontier_updated, topic: fn %{optimization_id: id} ->
        "pareto:#{id}"
      end
    end
  end

  defp can_access_optimization?(user, optimization) do
    program = ElixirML.Resources.Program.get!(optimization.program_id)
    can_access_program?(user, program)
  end

  defp can_access_program?(user, program) do
    user.role == :admin or program.user_id == user.id
  end
end
```

### 2. LiveView Admin Dashboard

```elixir
defmodule ElixirMLWeb.AdminLive do
  use ElixirMLWeb, :live_view
  use AshAdmin.LiveView

  admin_table ElixirML.Resources.Program do
    column :name
    column :type
    column :status
    column :current_performance_score
    column :optimization_count
    column :inserted_at
    
    action :optimize, "Optimize Program"
    action :clone, "Clone Program"
    action :archive, "Archive"
  end

  admin_table ElixirML.Resources.OptimizationRun do
    column :name
    column :strategy
    column :status
    column :progress_percentage
    column :best_score
    column :started_at
    
    action :cancel, "Cancel Optimization"
  end

  admin_table ElixirML.Resources.VariableSpace do
    column :name
    column :variable_count
    column :discrete_space_size
    column :continuous_dimensions
    column :program_count
    
    action :analyze_importance, "Analyze Variable Importance"
  end

  def mount(_params, _session, socket) do
    # Subscribe to real-time updates
    ElixirML.PubSub.subscribe("optimization:*")
    ElixirML.PubSub.subscribe("program:*")
    
    {:ok, socket}
  end

  def handle_info({:optimization_progress, optimization}, socket) do
    # Update optimization progress in real-time
    send_update(OptimizationProgressComponent, 
      id: "optimization-#{optimization.id}",
      optimization: optimization
    )
    
    {:noreply, socket}
  end

  def handle_info({:program_executed, execution}, socket) do
    # Update program execution status
    send_update(ProgramStatusComponent,
      id: "program-#{execution.program_id}",
      execution: execution
    )
    
    {:noreply, socket}
  end
end
```

## Implementation Strategy

### Week 1: Core Resource Foundation
- [ ] Program, VariableSpace, and OptimizationRun resources
- [ ] Basic CRUD actions and relationships
- [ ] Schema Engine integration
- [ ] Database migrations

### Week 2: Enterprise Features
- [ ] Authentication and authorization
- [ ] Policy engine implementation
- [ ] Audit logging system
- [ ] Multi-tenancy support

### Week 3: API Generation & Real-Time
- [ ] GraphQL API with subscriptions
- [ ] REST API endpoints
- [ ] LiveView admin dashboard
- [ ] Real-time progress updates

### Week 4: Advanced Features & Integration
- [ ] Variable System integration
- [ ] Process Orchestrator integration
- [ ] Performance analytics
- [ ] Documentation and examples

## Success Metrics

### Functional Requirements
- [ ] Complete CRUD operations for all resources
- [ ] Real-time subscriptions for optimization progress
- [ ] Policy-based access control
- [ ] Automatic API generation

### Performance Requirements
- [ ] <100ms response time for resource queries
- [ ] Support for 10,000+ concurrent subscriptions
- [ ] Efficient pagination for large datasets
- [ ] Optimized database queries

### Enterprise Requirements
- [ ] Role-based access control
- [ ] Complete audit trail
- [ ] Multi-tenant isolation
- [ ] API rate limiting and monitoring

This Resource Framework design provides enterprise-grade resource management for ElixirML/DSPEx, enabling declarative resource modeling with automatic API generation, real-time capabilities, and comprehensive enterprise features.
