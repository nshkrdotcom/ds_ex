# Phase 1: Schema Engine Integration
*Seamless Integration with ElixirML/DSPEx Core Systems*

## Executive Summary

The Schema Engine serves as the foundational integration layer for ElixirML/DSPEx, providing seamless interoperability between the Variable System, Resource Framework, and Process Orchestrator. This document outlines the integration patterns, APIs, and architectural decisions that enable the Schema Engine to act as the universal validation and transformation backbone.

## Integration Architecture

### System Integration Overview

```
Schema Engine Integration Architecture
├── Variable System Integration
│   ├── Variable Schema Validation
│   ├── Configuration Schema Generation
│   ├── Optimization Constraint Validation
│   └── Variable Space Schema Management
├── Resource Framework Integration
│   ├── Ash Resource Schema Binding
│   ├── Automatic Validation Integration
│   ├── Schema-Driven API Generation
│   └── Resource Lifecycle Schema Hooks
├── Process Orchestrator Integration
│   ├── Process State Schema Validation
│   ├── Message Schema Enforcement
│   ├── Pipeline Schema Coordination
│   └── Distributed Schema Synchronization
└── External System Integration
    ├── Sinter Core Integration
    ├── Database Schema Mapping
    ├── API Schema Generation
    └── Third-Party Adapter Schemas
```

## Variable System Integration

### 1. Variable Schema Validation

The Schema Engine provides comprehensive validation for all Variable System components:

```elixir
defmodule ElixirML.Schema.Variable.Integration do
  @moduledoc """
  Integration layer between Schema Engine and Variable System.
  Provides schema validation for all variable-related operations.
  """

  # Schema for Variable definitions
  defschema VariableDefinition do
    field :name, :atom, required: true
    field :type, :atom, required: true, 
          constraints: [in: [:float, :integer, :choice, :module, :composite]]
    field :default, :union, types: [:string, :integer, :float, :atom, :map]
    field :constraints, :map, default: %{}
    field :description, :string
    field :metadata, :map, default: %{}
    field :optimization_hints, {:array, :atom}, default: []
    
    validation :constraints_match_type do
      case {field(:type), field(:constraints)} do
        {:float, %{range: {min, max}}} -> 
          is_number(min) and is_number(max) and min < max
        {:integer, %{range: {min, max}}} -> 
          is_integer(min) and is_integer(max) and min < max
        {:choice, %{choices: choices}} -> 
          is_list(choices) and length(choices) > 0
        {:module, %{modules: modules}} -> 
          is_list(modules) and Enum.all?(modules, &is_atom/1)
        _ -> true
      end
    end
    
    transform :normalize_constraints do
      case field(:type) do
        :float -> 
          update_field(:constraints, &Map.put_new(&1, :precision, 0.01))
        :integer ->
          update_field(:constraints, &Map.put_new(&1, :step, 1))
        _ -> 
          identity()
      end
    end
  end

  # Schema for Variable Space
  defschema VariableSpace do
    field :id, :uuid, required: true
    field :name, :string, required: true
    field :variables, {:array, VariableDefinition}, required: true
    field :dependencies, :map, default: %{}
    field :constraints, {:array, :map}, default: []
    field :metadata, :map, default: %{}
    field :optimization_config, :map, default: %{}
    
    validation :no_circular_dependencies do
      deps = field(:dependencies)
      ElixirML.Variable.Space.Utils.validate_acyclic(deps)
    end
    
    validation :all_dependency_targets_exist do
      var_names = field(:variables) |> Enum.map(& &1.name) |> MapSet.new()
      dep_targets = field(:dependencies) |> Map.values() |> List.flatten() |> MapSet.new()
      MapSet.subset?(dep_targets, var_names)
    end
  end

  # Schema for Variable Configuration
  defschema VariableConfiguration do
    field :variable_space_id, :uuid, required: true
    field :configuration, :map, required: true
    field :metadata, :map, default: %{}
    field :created_at, :utc_datetime, required: true
    field :created_by, :string
    
    validation :configuration_matches_space do
      # Validate that configuration keys match variable space variables
      space = ElixirML.Variable.Space.get!(field(:variable_space_id))
      var_names = Enum.map(space.variables, & &1.name) |> MapSet.new()
      config_keys = Map.keys(field(:configuration)) |> MapSet.new()
      MapSet.subset?(config_keys, var_names)
    end
    
    transform :validate_individual_values do
      space = ElixirML.Variable.Space.get!(field(:variable_space_id))
      config = field(:configuration)
      
      validated_config = for {name, value} <- config, into: %{} do
        variable = Enum.find(space.variables, &(&1.name == name))
        {:ok, validated_value} = ElixirML.Variable.validate_value(variable, value)
        {name, validated_value}
      end
      
      update_field(:configuration, fn _ -> validated_config end)
    end
  end

  @doc "Validate a variable definition against its schema"
  def validate_variable(variable) do
    VariableDefinition.validate(variable)
  end

  @doc "Validate a variable space against its schema"
  def validate_variable_space(space) do
    VariableSpace.validate(space)
  end

  @doc "Validate a variable configuration against its schema and space"
  def validate_configuration(config) do
    VariableConfiguration.validate(config)
  end
end
```

### 2. Schema-Driven Variable Generation

The Schema Engine can automatically generate Variable definitions from schemas:

```elixir
defmodule ElixirML.Schema.Variable.Generator do
  @moduledoc """
  Generates Variable definitions from existing schemas.
  Enables automatic variable extraction from program schemas.
  """

  @doc "Extract variables from a schema definition"
  def extract_variables(schema_module) do
    schema_module.__schema__(:fields)
    |> Enum.filter(&has_variable_metadata?/1)
    |> Enum.map(&field_to_variable/1)
  end

  @doc "Generate variable space from multiple schemas"
  def generate_variable_space(schemas, opts \\ []) do
    variables = schemas
    |> Enum.flat_map(&extract_variables/1)
    |> Enum.uniq_by(& &1.name)

    %ElixirML.Variable.Space{
      id: Keyword.get(opts, :id, UUID.uuid4()),
      name: Keyword.get(opts, :name, "Generated Variable Space"),
      variables: variables,
      dependencies: infer_dependencies(variables),
      metadata: %{
        generated_from: Enum.map(schemas, &to_string/1),
        generated_at: DateTime.utc_now()
      }
    }
  end

  defp field_to_variable({name, type, opts}) do
    %ElixirML.Variable{
      name: name,
      type: map_schema_type_to_variable_type(type),
      default: Keyword.get(opts, :default),
      constraints: extract_constraints(opts),
      description: Keyword.get(opts, :description),
      metadata: %{
        source: :schema_generated,
        original_type: type
      }
    }
  end

  defp map_schema_type_to_variable_type(:integer), do: :integer
  defp map_schema_type_to_variable_type(:float), do: :float
  defp map_schema_type_to_variable_type(:string), do: :choice
  defp map_schema_type_to_variable_type(:atom), do: :choice
  defp map_schema_type_to_variable_type(_), do: :composite
end
```

## Resource Framework Integration

### 1. Ash Resource Schema Binding

The Schema Engine provides seamless integration with Ash Resources:

```elixir
defmodule ElixirML.Schema.Resource.Integration do
  @moduledoc """
  Integration layer between Schema Engine and Ash Resource Framework.
  Provides automatic schema validation for all resource operations.
  """

  defmacro __using__(opts) do
    quote do
      use Ash.Resource, unquote(opts)
      
      # Import schema integration macros
      import ElixirML.Schema.Resource.Integration
      
      # Register schema hooks
      @before_compile ElixirML.Schema.Resource.Compiler
    end
  end

  @doc "Define a schema-validated attribute"
  defmacro schema_attribute(name, schema_module, opts \\ []) do
    quote do
      attribute unquote(name), :map, unquote(opts)
      
      # Add schema validation
      validate unquote(:"validate_#{name}") do
        case unquote(schema_module).validate(attribute(unquote(name))) do
          {:ok, _} -> :ok
          {:error, errors} -> {:error, field: unquote(name), errors: errors}
        end
      end
      
      # Add schema transformation
      change unquote(:"transform_#{name}") do
        case unquote(schema_module).transform(attribute(unquote(name))) do
          {:ok, transformed} -> 
            change_attribute(unquote(name), transformed)
          {:error, _} = error -> 
            error
        end
      end
    end
  end

  @doc "Define a variable-enabled attribute"
  defmacro variable_attribute(name, variable_def, opts \\ []) do
    quote do
      schema_attribute unquote(name), ElixirML.Schema.Variable.Configuration, unquote(opts)
      
      # Register as variable
      Module.put_attribute(__MODULE__, :variables, {unquote(name), unquote(variable_def)})
    end
  end
end

# Example usage in a resource
defmodule ElixirML.Resources.Program do
  use ElixirML.Schema.Resource.Integration,
    domain: ElixirML.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    
    # Schema-validated attributes
    schema_attribute :signature_config, ElixirML.Schemas.Program.SignatureConfig
    schema_attribute :program_config, ElixirML.Schemas.Program.ProgramConfig
    schema_attribute :performance_metrics, ElixirML.Schemas.Program.PerformanceMetrics
    
    # Variable-enabled attributes
    variable_attribute :temperature, ElixirML.Variable.float(:temperature, range: {0.0, 2.0})
    variable_attribute :model_config, ElixirML.Variable.composite(:model_config, [
      ElixirML.Variable.choice(:provider, [:openai, :anthropic, :groq]),
      ElixirML.Variable.choice(:model, [:gpt4, :claude3, :llama2])
    ])
  end

  actions do
    defaults [:create, :read, :update, :destroy]
    
    create :create_with_validation do
      accept [:name, :signature_config, :program_config]
      
      # Automatic schema validation
      change ElixirML.Schema.Resource.Changes.ValidateAll
    end
  end
end
```

### 2. Automatic API Schema Generation

The Schema Engine automatically generates API schemas for resources:

```elixir
defmodule ElixirML.Schema.Resource.APIGenerator do
  @moduledoc """
  Generates API schemas (GraphQL, REST, etc.) from resource definitions.
  """

  @doc "Generate GraphQL schema from resource"
  def generate_graphql_schema(resource_module) do
    fields = resource_module.__ash_schema__(:attributes)
    |> Enum.map(&attribute_to_graphql_field/1)
    
    """
    type #{resource_name(resource_module)} {
      #{Enum.join(fields, "\n  ")}
    }
    
    input #{resource_name(resource_module)}Input {
      #{Enum.join(input_fields(fields), "\n  ")}
    }
    """
  end

  @doc "Generate OpenAPI schema from resource"
  def generate_openapi_schema(resource_module) do
    properties = resource_module.__ash_schema__(:attributes)
    |> Enum.map(&attribute_to_openapi_property/1)
    |> Map.new()
    
    %{
      type: "object",
      properties: properties,
      required: required_fields(resource_module)
    }
  end

  defp attribute_to_graphql_field({name, type, opts}) do
    graphql_type = map_to_graphql_type(type)
    nullable = if Keyword.get(opts, :allow_nil?, true), do: "", else: "!"
    "#{name}: #{graphql_type}#{nullable}"
  end

  defp map_to_graphql_type(:string), do: "String"
  defp map_to_graphql_type(:integer), do: "Int"
  defp map_to_graphql_type(:float), do: "Float"
  defp map_to_graphql_type(:boolean), do: "Boolean"
  defp map_to_graphql_type(:map), do: "JSON"
  defp map_to_graphql_type(:uuid), do: "ID"
  defp map_to_graphql_type(_), do: "JSON"
end
```

## Process Orchestrator Integration

### 1. Process State Schema Validation

The Schema Engine validates all process state transitions:

```elixir
defmodule ElixirML.Schema.Process.Integration do
  @moduledoc """
  Integration layer between Schema Engine and Process Orchestrator.
  Provides schema validation for process states and messages.
  """

  # Schema for process state
  defschema ProcessState do
    field :process_id, :uuid, required: true
    field :process_type, :atom, required: true,
          constraints: [in: [:program, :pipeline, :optimization, :evaluation]]
    field :status, :atom, required: true,
          constraints: [in: [:starting, :running, :paused, :completed, :failed]]
    field :state_data, :map, default: %{}
    field :metadata, :map, default: %{}
    field :last_updated, :utc_datetime, required: true
    field :version, :integer, required: true, constraints: [min: 1]
    
    validation :state_data_matches_type do
      case {field(:process_type), field(:state_data)} do
        {:program, state} -> validate_program_state(state)
        {:pipeline, state} -> validate_pipeline_state(state)
        {:optimization, state} -> validate_optimization_state(state)
        {:evaluation, state} -> validate_evaluation_state(state)
      end
    end
  end

  # Schema for process messages
  defschema ProcessMessage do
    field :from_process, :uuid, required: true
    field :to_process, :uuid, required: true
    field :message_type, :atom, required: true
    field :payload, :map, required: true
    field :correlation_id, :uuid
    field :timestamp, :utc_datetime, required: true
    field :priority, :integer, default: 5, constraints: [min: 1, max: 10]
    
    validation :payload_matches_message_type do
      case {field(:message_type), field(:payload)} do
        {:execute, payload} -> validate_execute_payload(payload)
        {:result, payload} -> validate_result_payload(payload)
        {:error, payload} -> validate_error_payload(payload)
        {:status_update, payload} -> validate_status_payload(payload)
        _ -> true
      end
    end
  end

  # Schema for pipeline configuration
  defschema PipelineConfiguration do
    field :pipeline_id, :uuid, required: true
    field :stages, {:array, :map}, required: true
    field :connections, {:array, :map}, default: []
    field :execution_strategy, :atom, default: :sequential,
          constraints: [in: [:sequential, :parallel, :streaming, :distributed]]
    field :error_handling, :atom, default: :stop,
          constraints: [in: [:stop, :continue, :retry, :fallback]]
    field :timeout_ms, :integer, default: 30_000, constraints: [min: 1000]
    field :retry_config, :map, default: %{max_retries: 3, backoff: :exponential}
    
    validation :stages_are_valid do
      stages = field(:stages)
      Enum.all?(stages, &validate_stage/1)
    end
    
    validation :connections_reference_valid_stages do
      stages = field(:stages) |> Enum.map(& &1["id"]) |> MapSet.new()
      connections = field(:connections)
      
      Enum.all?(connections, fn conn ->
        MapSet.member?(stages, conn["from"]) and 
        MapSet.member?(stages, conn["to"])
      end)
    end
  end

  @doc "Validate process state transition"
  def validate_state_transition(from_state, to_state) do
    with {:ok, _} <- ProcessState.validate(from_state),
         {:ok, _} <- ProcessState.validate(to_state),
         :ok <- validate_transition_rules(from_state.status, to_state.status) do
      {:ok, to_state}
    else
      error -> error
    end
  end

  @doc "Validate process message"
  def validate_message(message) do
    ProcessMessage.validate(message)
  end

  @doc "Validate pipeline configuration"
  def validate_pipeline_config(config) do
    PipelineConfiguration.validate(config)
  end

  defp validate_transition_rules(from_status, to_status) do
    valid_transitions = %{
      :starting => [:running, :failed],
      :running => [:paused, :completed, :failed],
      :paused => [:running, :completed, :failed],
      :completed => [],
      :failed => [:starting]
    }
    
    allowed = Map.get(valid_transitions, from_status, [])
    if to_status in allowed do
      :ok
    else
      {:error, "Invalid state transition from #{from_status} to #{to_status}"}
    end
  end
end
```

### 2. Distributed Schema Synchronization

The Schema Engine ensures schema consistency across distributed processes:

```elixir
defmodule ElixirML.Schema.Process.Distributed do
  @moduledoc """
  Handles schema synchronization across distributed processes.
  """

  use GenServer

  defstruct [
    :node_schemas,
    :schema_versions,
    :sync_interval,
    :conflict_resolution
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Synchronize schema across all nodes"
  def sync_schemas() do
    GenServer.call(__MODULE__, :sync_schemas)
  end

  @doc "Register a schema update"
  def register_schema_update(schema_module, version) do
    GenServer.cast(__MODULE__, {:schema_update, schema_module, version, node()})
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      node_schemas: %{},
      schema_versions: %{},
      sync_interval: Keyword.get(opts, :sync_interval, 30_000),
      conflict_resolution: Keyword.get(opts, :conflict_resolution, :latest_wins)
    }
    
    # Start periodic sync
    :timer.send_interval(state.sync_interval, :sync_tick)
    
    {:ok, state}
  end

  @impl true
  def handle_call(:sync_schemas, _from, state) do
    case perform_sync(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:schema_update, schema_module, version, node}, state) do
    new_state = %{state |
      node_schemas: Map.put(state.node_schemas, {node, schema_module}, version),
      schema_versions: Map.update(state.schema_versions, schema_module, 
        %{node => version}, &Map.put(&1, node, version))
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:sync_tick, state) do
    case perform_sync(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  defp perform_sync(state) do
    # Get all connected nodes
    nodes = [node() | Node.list()]
    
    # Collect schema versions from all nodes
    schema_versions = for node <- nodes, node != node() do
      case :rpc.call(node, __MODULE__, :get_local_schemas, []) do
        {:badrpc, _} -> {node, %{}}
        schemas -> {node, schemas}
      end
    end
    
    # Resolve conflicts and update schemas
    resolved_schemas = resolve_schema_conflicts(schema_versions, state.conflict_resolution)
    
    # Apply updates
    for {schema_module, target_version} <- resolved_schemas do
      apply_schema_update(schema_module, target_version)
    end
    
    {:ok, state}
  end

  def get_local_schemas() do
    # Return local schema versions
    ElixirML.Schema.Registry.get_all_versions()
  end

  defp resolve_schema_conflicts(node_schemas, :latest_wins) do
    # Simple conflict resolution: use the latest version
    node_schemas
    |> Enum.flat_map(fn {_node, schemas} -> schemas end)
    |> Enum.group_by(fn {schema, _version} -> schema end)
    |> Enum.map(fn {schema, versions} ->
      latest_version = versions |> Enum.map(&elem(&1, 1)) |> Enum.max()
      {schema, latest_version}
    end)
  end

  defp apply_schema_update(schema_module, version) do
    # Apply schema update if needed
    current_version = ElixirML.Schema.Registry.get_version(schema_module)
    
    if version > current_version do
      ElixirML.Schema.Registry.update_schema(schema_module, version)
    end
  end
end
```

## External System Integration

### 1. Sinter Core Integration

Deep integration with Sinter for advanced schema capabilities:

```elixir
defmodule ElixirML.Schema.Sinter.Integration do
  @moduledoc """
  Deep integration with Sinter for advanced schema capabilities.
  """

  @doc "Create a Sinter schema from ElixirML schema definition"
  def to_sinter_schema(schema_module) do
    fields = schema_module.__schema__(:fields)
    validations = schema_module.__schema__(:validations)
    transforms = schema_module.__schema__(:transforms)
    
    Sinter.Schema.new()
    |> add_fields(fields)
    |> add_validations(validations)
    |> add_transforms(transforms)
  end

  @doc "Create ElixirML schema from Sinter schema"
  def from_sinter_schema(sinter_schema, module_name) do
    quote do
      defmodule unquote(module_name) do
        use ElixirML.Schema
        
        unquote(generate_fields(sinter_schema))
        unquote(generate_validations(sinter_schema))
        unquote(generate_transforms(sinter_schema))
      end
    end
  end

  @doc "Validate data using Sinter backend"
  def validate_with_sinter(data, schema_module) do
    sinter_schema = to_sinter_schema(schema_module)
    Sinter.validate(data, sinter_schema)
  end

  @doc "Transform data using Sinter backend"
  def transform_with_sinter(data, schema_module) do
    sinter_schema = to_sinter_schema(schema_module)
    Sinter.transform(data, sinter_schema)
  end

  defp add_fields(sinter_schema, fields) do
    Enum.reduce(fields, sinter_schema, fn {name, type, opts}, schema ->
      Sinter.Schema.add_field(schema, name, type, opts)
    end)
  end

  defp add_validations(sinter_schema, validations) do
    Enum.reduce(validations, sinter_schema, fn {name, validation_fn}, schema ->
      Sinter.Schema.add_validation(schema, name, validation_fn)
    end)
  end

  defp add_transforms(sinter_schema, transforms) do
    Enum.reduce(transforms, sinter_schema, fn {name, transform_fn}, schema ->
      Sinter.Schema.add_transform(schema, name, transform_fn)
    end)
  end
end
```

### 2. Database Schema Mapping

Automatic database schema generation and synchronization:

```elixir
defmodule ElixirML.Schema.Database.Integration do
  @moduledoc """
  Automatic database schema generation and synchronization.
  """

  @doc "Generate Ecto migration from ElixirML schema"
  def generate_migration(schema_module, table_name) do
    fields = schema_module.__schema__(:fields)
    
    migration_content = """
    defmodule #{migration_module_name(schema_module)} do
      use Ecto.Migration
      
      def change do
        create table(:#{table_name}) do
          #{generate_field_definitions(fields)}
          
          timestamps()
        end
        
        #{generate_indexes(fields)}
      end
    end
    """
    
    migration_content
  end

  @doc "Sync ElixirML schema with database table"
  def sync_with_database(schema_module, table_name, repo) do
    # Get current table structure
    current_columns = get_table_columns(table_name, repo)
    
    # Get expected structure from schema
    expected_columns = schema_to_columns(schema_module)
    
    # Generate ALTER statements
    alter_statements = diff_columns(current_columns, expected_columns)
    
    # Execute alterations
    Enum.each(alter_statements, &execute_alter_statement(&1, repo))
  end

  defp generate_field_definitions(fields) do
    fields
    |> Enum.map(&field_to_column_definition/1)
    |> Enum.join("\n      ")
  end

  defp field_to_column_definition({name, type, opts}) do
    column_type = map_to_ecto_type(type)
    null_constraint = if Keyword.get(opts, :required, false), do: ", null: false", else: ""
    default_value = case Keyword.get(opts, :default) do
      nil -> ""
      value -> ", default: #{inspect(value)}"
    end
    
    "add :#{name}, :#{column_type}#{null_constraint}#{default_value}"
  end

  defp map_to_ecto_type(:string), do: :string
  defp map_to_ecto_type(:integer), do: :integer
  defp map_to_ecto_type(:float), do: :float
  defp map_to_ecto_type(:boolean), do: :boolean
  defp map_to_ecto_type(:map), do: :map
  defp map_to_ecto_type(:uuid), do: :uuid
  defp map_to_ecto_type(:utc_datetime), do: :utc_datetime
  defp map_to_ecto_type(_), do: :text
end
```

## Integration Testing Framework

### 1. Cross-System Integration Tests

```elixir
defmodule ElixirML.Schema.Integration.Test do
  @moduledoc """
  Comprehensive integration testing framework for Schema Engine integrations.
  """

  use ExUnit.Case
  
  describe "Variable System Integration" do
    test "schema validates variable definitions" do
      variable_def = %{
        name: :temperature,
        type: :float,
        default: 0.7,
        constraints: %{range: {0.0, 2.0}}
      }
      
      assert {:ok, _} = ElixirML.Schema.Variable.Integration.validate_variable(variable_def)
    end
    
    test "schema generates variables from program schemas" do
      variables = ElixirML.Schema.Variable.Generator.extract_variables(TestProgramSchema)
      
      assert length(variables) > 0
      assert Enum.any?(variables, &(&1.name == :temperature))
    end
  end
  
  describe "Resource Framework Integration" do
    test "schema-validated attributes work in resources" do
      {:ok, program} = TestProgram.create(%{
        name: "Test Program",
        signature_config: %{input: "string", output: "string"},
        program_config: %{temperature: 0.7}
      })
      
      assert program.name == "Test Program"
      assert program.signature_config.input == "string"
    end
    
    test "automatic API schema generation works" do
      schema = ElixirML.Schema.Resource.APIGenerator.generate_graphql_schema(TestProgram)
      
      assert schema =~ "type TestProgram"
      assert schema =~ "name: String!"
    end
  end
  
  describe "Process Orchestrator Integration" do
    test "process state validation works" do
      state = %{
        process_id: UUID.uuid4(),
        process_type: :program,
        status: :running,
        state_data: %{},
        last_updated: DateTime.utc_now(),
        version: 1
      }
      
      assert {:ok, _} = ElixirML.Schema.Process.Integration.ProcessState.validate(state)
    end
    
    test "process message validation works" do
      message = %{
        from_process: UUID.uuid4(),
        to_process: UUID.uuid4(),
        message_type: :execute,
        payload: %{input: "test"},
        timestamp: DateTime.utc_now()
      }
      
      assert {:ok, _} = ElixirML.Schema.Process.Integration.ProcessMessage.validate(message)
    end
  end
end
```

## Performance Optimization

### 1. Schema Compilation Optimization

```elixir
defmodule ElixirML.Schema.Integration.Performance do
  @moduledoc """
  Performance optimizations for schema integrations.
  """

  @doc "Precompile all integration schemas"
  def precompile_schemas() do
    schemas = [
      ElixirML.Schema.Variable.Integration.VariableDefinition,
      ElixirML.Schema.Variable.Integration.VariableSpace,
      ElixirML.Schema.Variable.Integration.VariableConfiguration,
      ElixirML.Schema.Process.Integration.ProcessState,
      ElixirML.Schema.Process.Integration.ProcessMessage,
      ElixirML.Schema.Process.Integration.PipelineConfiguration
    ]
    
    Enum.each(schemas, &precompile_schema/1)
  end

  @doc "Cache schema validation functions"
  def cache_validation_functions() do
    # Create ETS table for cached validation functions
    :ets.new(:schema_validation_cache, [:named_table, :public, :set])
    
    # Pre-cache common validations
    common_schemas = get_common_schemas()
    Enum.each(common_schemas, &cache_schema_validation/1)
  end

  defp precompile_schema(schema_module) do
    # Force compilation of validation and transformation functions
    schema_module.__schema__(:validate_compiled)
    schema_module.__schema__(:transform_compiled)
  end

  defp cache_schema_validation(schema_module) do
    validation_fn = &schema_module.validate/1
    :ets.insert(:schema_validation_cache, {schema_module, validation_fn})
  end

  defp get_common_schemas() do
    [
      ElixirML.Schema.Variable.Integration.VariableDefinition,
      ElixirML.Schema.Process.Integration.ProcessState,
      ElixirML.Schema.Process.Integration.ProcessMessage
    ]
  end
end
```

## Monitoring and Observability

### 1. Integration Metrics

```elixir
defmodule ElixirML.Schema.Integration.Telemetry do
  @moduledoc """
  Telemetry and monitoring for schema integrations.
  """

  @doc "Emit schema validation metrics"
  def emit_validation_metrics(schema_module, validation_time, result) do
    :telemetry.execute(
      [:elixir_ml, :schema, :validation],
      %{duration: validation_time},
      %{
        schema: schema_module,
        result: result,
        node: node()
      }
    )
  end

  @doc "Emit integration performance metrics"
  def emit_integration_metrics(integration_type, operation, duration) do
    :telemetry.execute(
      [:elixir_ml, :schema, :integration],
      %{duration: duration},
      %{
        integration_type: integration_type,
        operation: operation,
        node: node()
      }
    )
  end

  @doc "Setup telemetry handlers for schema integration monitoring"
  def setup_telemetry_handlers() do
    handlers = [
      {
        [:elixir_ml, :schema, :validation],
        &handle_validation_event/4,
        []
      },
      {
        [:elixir_ml, :schema, :integration],
        &handle_integration_event/4,
        []
      }
    ]
    
    Enum.each(handlers, fn {event, handler, config} ->
      :telemetry.attach("elixir_ml_schema_#{:erlang.phash2(event)}", event, handler, config)
    end)
  end

  defp handle_validation_event(_event, measurements, metadata, _config) do
    # Log validation performance
    Logger.debug("Schema validation completed", 
      schema: metadata.schema,
      duration: measurements.duration,
      result: metadata.result
    )
    
    # Update metrics
    :prometheus_histogram.observe(
      :schema_validation_duration_seconds,
      [schema: metadata.schema],
      measurements.duration / 1000
    )
  end

  defp handle_integration_event(_event, measurements, metadata, _config) do
    # Log integration performance
    Logger.debug("Schema integration operation completed",
      integration_type: metadata.integration_type,
      operation: metadata.operation,
      duration: measurements.duration
    )
    
    # Update metrics
    :prometheus_histogram.observe(
      :schema_integration_duration_seconds,
      [type: metadata.integration_type, operation: metadata.operation],
      measurements.duration / 1000
    )
  end
end
```

## Summary

The Schema Engine Integration provides seamless interoperability between all ElixirML/DSPEx core systems through:

1. **Variable System Integration**: Comprehensive validation and generation of variable definitions
2. **Resource Framework Integration**: Automatic schema validation for Ash resources and API generation
3. **Process Orchestrator Integration**: Process state and message validation with distributed synchronization
4. **External System Integration**: Deep Sinter integration and database schema mapping
5. **Performance Optimization**: Schema compilation and validation caching
6. **Monitoring**: Comprehensive telemetry and observability

This integration layer ensures that the Schema Engine acts as the universal validation and transformation backbone, enabling type safety and consistency across the entire ElixirML/DSPEx system while maintaining high performance and developer productivity.
