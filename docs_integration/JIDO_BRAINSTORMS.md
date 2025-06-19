# JIDO Integration Brainstorms for DSPEx
*Exploring Multiple Strategic Integration Approaches*

## Executive Summary

After analyzing the comprehensive DSPEx integration documentation (11 integration docs, variable system designs, and JIDO framework materials), this document explores **five distinct strategic approaches** for integrating JIDO components into DSPEx. Each approach offers different trade-offs between innovation, risk, implementation complexity, and long-term strategic positioning.

## Context: Current DSPEx Integration Landscape

### ✅ Strong Foundation (65% Complete)
- **Core SIMBA Algorithm**: Functional teleprompter optimization
- **11 Integration Documents**: 1,400+ pages of blueprints
- **Variable System Design**: Revolutionary universal parameter optimization
- **Testing Infrastructure**: Mox-based with comprehensive MockHelpers
- **Signature System**: Enhanced parsing with type safety

### 🔄 Active Development Areas
- **7 Missing Integration Documents**: RETRIEVE, TELEPROMPT, STREAMING, etc.
- **Variable System Implementation**: Two competing approaches (Cursor vs Claude Code)
- **Behavior Definitions**: Missing Client, Adapter, Evaluator behaviors
- **Ash Framework Integration**: Hybrid approach under consideration

### 🎯 Strategic Innovation Opportunities
- **Universal Variable Optimization**: Auto-discovery of optimal configurations
- **BAML-Inspired Static Analysis**: Compile-time safety and IDE integration
- **Event-Driven Architecture**: Real-time optimization workflows

## Five Strategic Integration Approaches

---

## Approach 1: "Selective Foundation Enhancement" 
*Conservative Integration with High-Value Components*

### Philosophy
**"Take the best patterns, preserve DSPEx identity"**

Adopt JIDO's excellent execution patterns while maintaining DSPEx's specialized LLM optimization capabilities. This approach focuses on enhancing DSPEx's foundation without fundamental architectural changes.

### Integration Strategy

#### Phase 1: Foundation Patterns (Weeks 1-2)
```elixir
# Enhanced DSPEx.Program with JIDO patterns
defmodule DSPEx.Program.Enhanced do
  @moduledoc """
  DSPEx Program with JIDO-inspired execution robustness
  """
  
  # Adopt JIDO's parameter validation patterns
  use NimbleOptions, [
    signature: [type: :atom, required: true],
    client: [type: :atom, default: :openai],
    temperature: [type: :float, default: 0.7],
    max_tokens: [type: :pos_integer, default: 1000]
  ]
  
  # Adopt JIDO's structured error handling
  @type execution_result :: 
    {:ok, outputs()} | 
    {:error, :validation_error, term()} |
    {:error, :execution_error, term()} |
    {:error, :timeout_error, term()}
  
  def forward(program, inputs, opts \\ []) do
    with {:ok, validated_opts} <- validate_options(opts),
         {:ok, validated_inputs} <- validate_inputs(inputs, program.signature),
         {:ok, result} <- execute_with_telemetry(program, validated_inputs, validated_opts) do
      {:ok, result}
    end
  end
  
  # JIDO-inspired execution with timeout and retry
  defp execute_with_telemetry(program, inputs, opts) do
    :telemetry.span([:dspex, :program, :execution], %{program: program}, fn ->
      case execute_with_timeout(program, inputs, opts) do
        {:ok, result} -> {result, %{status: :success}}
        {:error, reason} = error -> {error, %{status: :error, reason: reason}}
      end
    end)
  end
end
```

#### Phase 2: Enhanced Validation & Error Handling (Weeks 3-4)
```elixir
# Adopt JIDO's validation patterns for signatures
defmodule DSPEx.Signature.Enhanced do
  use DSPEx.Signature, "question -> answer"
  
  # JIDO-inspired schema validation
  def input_schema do
    [
      question: [type: :string, required: true, doc: "User question"]
    ]
  end
  
  def output_schema do
    [
      answer: [type: :string, required: true, doc: "Generated answer"]
    ]
  end
  
  # JIDO-style validation
  def validate_inputs(inputs) do
    NimbleOptions.validate(inputs, input_schema())
  end
end
```

#### Phase 3: Tool Integration Enhancement (Weeks 5-6)
```elixir
# Enhanced tool calling with JIDO patterns
defmodule DSPEx.Tools.Enhanced do
  @doc """
  Convert DSPEx programs to AI tool format using JIDO patterns
  """
  def to_tool_format(program) do
    %{
      type: "function",
      function: %{
        name: program.name || to_string(program.signature),
        description: program.signature.instructions(),
        parameters: build_json_schema(program.signature)
      }
    }
  end
  
  # JIDO-inspired parameter building
  defp build_json_schema(signature) do
    %{
      type: "object",
      properties: build_properties(signature.input_fields()),
      required: signature.required_fields()
    }
  end
end
```

### Benefits
- **Low Risk**: Minimal architectural disruption
- **High Value**: Immediate improvements in robustness and validation
- **Fast Implementation**: 6-week timeline
- **Preserve Identity**: DSPEx remains focused on LLM optimization

### Integration Timeline
- **Week 1-2**: Parameter validation and error handling
- **Week 3-4**: Enhanced signature validation
- **Week 5-6**: Tool integration improvements
- **Fits in Phase 1** of master integration plan (Foundation Consolidation)

---

## Approach 2: "Event-Driven Optimization Architecture"
*JIDO.Signal as DSPEx Nervous System*

### Philosophy
**"Transform DSPEx into a reactive, observable optimization system"**

Integrate JIDO.Signal as the core communication layer, enabling real-time optimization monitoring, decoupled workflows, and event-driven teleprompter execution.

### Integration Strategy

#### Phase 1: Signal Infrastructure (Weeks 1-3)
```elixir
# DSPEx Signal Bus Integration
defmodule DSPEx.Signal.Bus do
  @moduledoc """
  Event-driven communication for DSPEx optimization workflows
  """
  
  use Jido.Signal.Bus,
    name: :dspex_bus,
    adapters: [
      {Jido.Signal.Adapters.Logger, level: :info},
      {Jido.Signal.Adapters.Telemetry, prefix: [:dspex]},
      {DSPEx.Signal.Adapters.LiveView, topic: "optimization"}
    ]
  
  # DSPEx-specific signal types
  def optimization_started(correlation_id, program, dataset) do
    emit(%Jido.Signal{
      type: "dspex.optimization.started",
      data: %{
        correlation_id: correlation_id,
        program: serialize_program(program),
        dataset_size: length(dataset),
        timestamp: DateTime.utc_now()
      }
    })
  end
  
  def trial_completed(correlation_id, trial_number, score, config) do
    emit(%Jido.Signal{
      type: "dspex.optimization.trial.completed",
      data: %{
        correlation_id: correlation_id,
        trial_number: trial_number,
        score: score,
        configuration: config,
        timestamp: DateTime.utc_now()
      }
    })
  end
end
```

#### Phase 2: Event-Driven Teleprompters (Weeks 4-8)
```elixir
# SIMBA with Signal Integration
defmodule DSPEx.Teleprompter.SIMBA.EventDriven do
  use GenServer
  
  def compile(student, teacher, trainset, metric_fn, opts \\ []) do
    correlation_id = generate_correlation_id()
    
    # Start async optimization
    {:ok, pid} = GenServer.start_link(__MODULE__, {
      student, teacher, trainset, metric_fn, correlation_id, opts
    })
    
    # Emit start signal
    DSPEx.Signal.Bus.optimization_started(correlation_id, student, trainset)
    
    {:ok, %{correlation_id: correlation_id, pid: pid}}
  end
  
  def handle_info({:run_trial, trial_config}, state) do
    # Run trial
    score = evaluate_configuration(trial_config, state)
    
    # Emit progress signal
    DSPEx.Signal.Bus.trial_completed(
      state.correlation_id, 
      state.trial_number, 
      score, 
      trial_config
    )
    
    # Continue optimization
    {:noreply, update_optimization_state(state, score, trial_config)}
  end
end
```

#### Phase 3: Real-Time Monitoring (Weeks 9-10)
```elixir
# LiveView Dashboard for Real-Time Optimization
defmodule DSPExWeb.OptimizationLive do
  use DSPExWeb, :live_view
  
  def mount(_params, _session, socket) do
    # Subscribe to optimization signals
    DSPEx.Signal.Bus.subscribe("dspex.optimization.*")
    
    {:ok, assign(socket, :optimizations, %{})}
  end
  
  def handle_info({:signal, %Jido.Signal{type: "dspex.optimization.trial.completed"} = signal}, socket) do
    # Update real-time optimization progress
    optimizations = update_optimization_progress(socket.assigns.optimizations, signal)
    {:noreply, assign(socket, :optimizations, optimizations)}
  end
end
```

### Benefits
- **Real-Time Observability**: Live optimization monitoring
- **Decoupled Architecture**: Services can be scaled independently
- **Event Sourcing**: Complete audit trail of optimization decisions
- **Extensible**: Easy to add new monitoring and analysis tools

### Integration Timeline
- **Week 1-3**: Signal bus infrastructure
- **Week 4-8**: Event-driven teleprompters
- **Week 9-10**: Real-time monitoring dashboard
- **Fits in Phase 2** of master integration plan (Variable System Integration)

---

## Approach 3: "JIDO as DSPEx Runtime Foundation"
*Complete Architectural Transformation*

### Philosophy
**"JIDO becomes the execution engine, DSPEx becomes the optimization compiler"**

This is the most ambitious approach: DSPEx programs become configurations for JIDO agents, with teleprompters optimizing agent configurations rather than simple prompt templates.

### Integration Strategy

#### Phase 1: Program-to-Agent Transformation (Weeks 1-4)
```elixir
# DSPEx Program as JIDO Agent Configuration
defmodule DSPEx.Agent.Configuration do
  @moduledoc """
  DSPEx Programs become JIDO Agent configurations
  """
  
  defstruct [
    :agent_module,        # Base JIDO Agent
    :skills,              # Available JIDO Skills
    :initial_state,       # Agent's initial state
    :optimization_params  # Parameters for teleprompter optimization
  ]
  
  def from_program(%DSPEx.Predict{} = program) do
    %__MODULE__{
      agent_module: DSPEx.Agents.LLMAgent,
      skills: [DSPEx.Skills.TextGeneration],
      initial_state: %{
        signature: program.signature,
        client: program.client,
        demos: program.demos || []
      },
      optimization_params: %{
        tunable: [:temperature, :max_tokens, :model],
        constraints: %{
          temperature: {0.1, 1.5},
          max_tokens: {100, 4000}
        }
      }
    }
  end
end

# DSPEx Agent using JIDO framework
defmodule DSPEx.Agents.LLMAgent do
  use Jido.Agent,
    name: "dspex_llm_agent",
    description: "LLM-powered agent optimized by DSPEx"
  
  def initial_state(config) do
    Map.merge(%{
      signature: nil,
      client: :openai,
      demos: [],
      conversation_history: []
    }, config.initial_state)
  end
  
  def handle_signal(%Jido.Signal{type: "llm.predict"} = signal, state) do
    # Use DSPEx prediction logic within JIDO agent
    case DSPEx.Predict.forward(build_program(state), signal.data.inputs) do
      {:ok, outputs} ->
        response_signal = %Jido.Signal{
          type: "llm.prediction.completed",
          data: outputs,
          correlation_id: signal.correlation_id
        }
        {:ok, [response_signal], state}
      
      {:error, reason} ->
        {:error, reason, state}
    end
  end
end
```

#### Phase 2: Agent-Aware Teleprompters (Weeks 5-10)
```elixir
# SIMBA optimizing JIDO Agent configurations
defmodule DSPEx.Teleprompter.SIMBA.AgentOptimizer do
  @doc """
  Optimize JIDO Agent configurations instead of simple programs
  """
  def compile(agent_config, trainset, metric_fn, opts \\ []) do
    # Generate candidate agent configurations
    candidate_configs = generate_agent_configurations(agent_config, opts)
    
    # Evaluate each configuration by starting temporary agents
    evaluated_configs = 
      candidate_configs
      |> Task.async_stream(fn config ->
        evaluate_agent_configuration(config, trainset, metric_fn)
      end, max_concurrency: 4)
      |> Enum.map(fn {:ok, result} -> result end)
    
    # Select best configuration
    best_config = select_best_configuration(evaluated_configs)
    
    {:ok, best_config}
  end
  
  defp evaluate_agent_configuration(config, trainset, metric_fn) do
    # Start temporary JIDO agent
    {:ok, agent_pid} = Jido.Agent.Server.start_link([
      agent: config.agent_module,
      skills: config.skills,
      initial_state: config.initial_state
    ])
    
    try do
      # Run evaluation against trainset
      scores = 
        trainset
        |> Enum.map(fn example ->
          signal = %Jido.Signal{
            type: "llm.predict",
            data: %{inputs: example.inputs}
          }
          
          case Jido.Agent.Server.call(agent_pid, signal) do
            {:ok, outputs} -> metric_fn.(example.outputs, outputs)
            {:error, _} -> 0.0
          end
        end)
      
      average_score = Enum.sum(scores) / length(scores)
      {config, average_score}
      
    after
      Jido.Agent.Server.stop(agent_pid)
    end
  end
end
```

#### Phase 3: Production Agent Management (Weeks 11-14)
```elixir
# Production JIDO Agent management optimized by DSPEx
defmodule DSPEx.AgentManager do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    children = [
      # Registry for tracking optimized agents
      {Registry, keys: :unique, name: DSPEx.AgentRegistry},
      
      # Dynamic supervisor for agent instances
      {DynamicSupervisor, name: DSPEx.AgentSupervisor, strategy: :one_for_one}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  def deploy_optimized_agent(agent_config, opts \\ []) do
    agent_id = Keyword.get(opts, :id, generate_agent_id())
    
    child_spec = {
      Jido.Agent.Server,
      [
        id: agent_id,
        agent: agent_config.agent_module,
        skills: agent_config.skills,
        initial_state: agent_config.initial_state
      ]
    }
    
    case DynamicSupervisor.start_child(DSPEx.AgentSupervisor, child_spec) do
      {:ok, pid} ->
        Registry.register(DSPEx.AgentRegistry, agent_id, %{
          pid: pid,
          config: agent_config,
          deployed_at: DateTime.utc_now()
        })
        {:ok, agent_id, pid}
      
      error -> error
    end
  end
end
```

### Benefits
- **Stateful Programs**: Agents can maintain conversation history and context
- **Robust Execution**: Full JIDO supervision and fault tolerance
- **Advanced Orchestration**: Complex multi-agent workflows
- **Production Ready**: Battle-tested JIDO runtime

### Challenges
- **High Complexity**: Major architectural transformation
- **Learning Curve**: Team needs JIDO expertise
- **Migration Risk**: Significant changes to existing code

### Integration Timeline
- **Week 1-4**: Program-to-agent transformation
- **Week 5-10**: Agent-aware teleprompters
- **Week 11-14**: Production agent management
- **Spans Phases 2-3** of master integration plan

---

## Approach 4: "Variable System + JIDO Actions Integration"
*Enhanced Variable Optimization with JIDO Execution*

### Philosophy
**"Combine DSPEx variable innovation with JIDO execution robustness"**

Integrate JIDO.Action as the execution foundation for the revolutionary variable system, enabling sophisticated parameter optimization with robust execution patterns.

### Integration Strategy

#### Phase 1: Variable-Aware JIDO Actions (Weeks 1-3)
```elixir
# Enhanced DSPEx Actions with Variable Support
defmodule DSPEx.Actions.VariablePredict do
  use Jido.Action,
    name: "variable_predict",
    description: "LLM prediction with variable optimization support",
    schema: [
      signature: [type: :atom, required: true],
      inputs: [type: :map, required: true],
      variable_config: [type: :map, default: %{}]
    ]
  
  # Variable definitions integrated with action
  @variables [
    DSPEx.Variable.choice(:adapter, [:json_tool, :markdown_tool]),
    DSPEx.Variable.choice(:reasoning, [:predict, :cot, :pot]),
    DSPEx.Variable.float(:temperature, range: {0.1, 1.5}),
    DSPEx.Variable.choice(:model, ["gpt-4", "gpt-3.5-turbo", "claude-3"])
  ]
  
  @impl Jido.Action
  def run(%{signature: sig, inputs: inputs, variable_config: var_config}, context) do
    # Resolve variables to concrete configuration
    resolved_config = DSPEx.Variable.resolve(@variables, var_config)
    
    # Execute with resolved configuration using JIDO's robust execution
    case execute_prediction(sig, inputs, resolved_config, context) do
      {:ok, outputs} -> 
        # Track variable performance for learning
        DSPEx.Variable.Analytics.record_performance(var_config, outputs, context)
        {:ok, outputs}
      
      {:error, reason} -> 
        DSPEx.Variable.Analytics.record_failure(var_config, reason, context)
        {:error, reason}
    end
  end
  
  def variable_space, do: DSPEx.Variable.Space.new(@variables)
end
```

#### Phase 2: Variable-Driven Teleprompters (Weeks 4-8)
```elixir
# SIMBA with Variable and JIDO Integration
defmodule DSPEx.Teleprompter.SIMBA.VariableOptimizer do
  @doc """
  Optimize both demonstrations and variable configurations
  """
  def compile(action_module, trainset, metric_fn, opts \\ []) do
    variable_space = action_module.variable_space()
    
    # Multi-objective optimization: demos + variables
    optimization_result = 
      DSPEx.Variable.Optimizer.optimize(
        objective_fn: fn variable_config ->
          # Create action configuration with variables
          action_config = %{
            signature: opts[:signature],
            inputs: %{},  # Will be filled per example
            variable_config: variable_config
          }
          
          # Evaluate configuration across trainset
          evaluate_action_configuration(action_module, action_config, trainset, metric_fn)
        end,
        variable_space: variable_space,
        optimization_strategy: :bayesian,
        max_iterations: opts[:max_iterations] || 50
      )
    
    case optimization_result do
      {:ok, best_config} ->
        # Create optimized action with best variable configuration
        optimized_action = create_optimized_action(action_module, best_config)
        {:ok, optimized_action}
      
      error -> error
    end
  end
  
  defp evaluate_action_configuration(action_module, base_config, trainset, metric_fn) do
    scores = 
      trainset
      |> Task.async_stream(fn example ->
        action_config = %{base_config | inputs: example.inputs}
        
        case Jido.Exec.run(action_module, action_config, %{}) do
          {:ok, outputs} -> metric_fn.(example.outputs, outputs)
          {:error, _} -> 0.0
        end
      end, max_concurrency: 4)
      |> Enum.map(fn {:ok, score} -> score end)
    
    Enum.sum(scores) / length(scores)
  end
end
```

#### Phase 3: Continuous Variable Learning (Weeks 9-12)
```elixir
# Continuous learning system for variable optimization
defmodule DSPEx.Variable.ContinuousLearner do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def record_execution(action_module, variable_config, inputs, outputs, performance_metrics) do
    GenServer.cast(__MODULE__, {
      :record_execution, 
      action_module, 
      variable_config, 
      inputs, 
      outputs, 
      performance_metrics
    })
  end
  
  def handle_cast({:record_execution, action_module, var_config, inputs, outputs, metrics}, state) do
    # Store execution data
    execution_record = %{
      action_module: action_module,
      variable_config: var_config,
      inputs: inputs,
      outputs: outputs,
      performance: metrics,
      timestamp: DateTime.utc_now()
    }
    
    # Update variable performance models
    updated_models = DSPEx.Variable.Learning.update_performance_models(
      state.performance_models,
      execution_record
    )
    
    # Trigger re-optimization if performance degrades
    if should_reoptimize?(updated_models, state.thresholds) do
      Task.start(fn ->
        DSPEx.Variable.Optimizer.background_reoptimization(action_module, updated_models)
      end)
    end
    
    {:noreply, %{state | performance_models: updated_models}}
  end
end
```

### Benefits
- **Revolutionary Variable System**: Auto-optimization of all parameters
- **Robust Execution**: JIDO's battle-tested execution patterns
- **Continuous Learning**: Performance-driven variable adaptation
- **Multi-Objective Optimization**: Optimize demos + variables simultaneously

### Integration Timeline
- **Week 1-3**: Variable-aware JIDO actions
- **Week 4-8**: Variable-driven teleprompters
- **Week 9-12**: Continuous learning system
- **Fits in Phase 2** of master integration plan (Variable System Integration)

---

## Approach 5: "Ash + JIDO Unified Framework"
*Enterprise-Grade Declarative DSPEx*

### Philosophy
**"Combine Ash's declarative power with JIDO's execution robustness for enterprise DSPEx"**

This approach combines the Ash Framework integration (from ASH_FRAMEWORK_INTEGRATION_ANALYSIS.md) with JIDO components to create a fully declarative, enterprise-grade DSPEx framework.

### Integration Strategy

#### Phase 1: Ash Resources for JIDO Actions (Weeks 1-4)
```elixir
# DSPEx Programs as Ash Resources backed by JIDO Actions
defmodule DSPEx.Resources.Program do
  use Ash.Resource,
    domain: DSPEx.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :signature_module, :atom, allow_nil?: false
    attribute :action_module, :atom, allow_nil?: false
    attribute :configuration, :map, default: %{}
    attribute :variable_config, :map, default: %{}
    attribute :optimization_metadata, :map, default: %{}
  end

  relationships do
    has_many :optimization_runs, DSPEx.Resources.OptimizationRun
    has_many :executions, DSPEx.Resources.Execution
  end

  actions do
    defaults [:create, :read, :update, :destroy]
    
    action :execute, :map do
      argument :inputs, :map, allow_nil?: false
      argument :execution_options, :map, default: %{}
      
      run DSPEx.Actions.ExecuteProgram
    end
    
    action :optimize, DSPEx.Resources.Program do
      argument :training_data, {:array, :map}, allow_nil?: false
      argument :metric_function, :string, allow_nil?: false
      argument :optimization_strategy, :atom, default: :simba
      
      run DSPEx.Actions.OptimizeProgram
    end
  end

  calculations do
    calculate :current_performance, :float do
      DSPEx.Calculations.CurrentPerformance
    end
    
    calculate :execution_count, :integer do
      count(:executions)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end
end
```

#### Phase 2: Declarative Optimization Workflows (Weeks 5-8)
```elixir
# Ash Action for Program Execution using JIDO
defmodule DSPEx.Actions.ExecuteProgram do
  use Ash.Resource.Actions.Implementation

  def run(input, opts, context) do
    program = input.resource
    
    # Convert Ash resource to JIDO action configuration
    action_config = %{
      signature: program.signature_module,
      inputs: input.arguments.inputs,
      variable_config: program.variable_config
    }
    
    # Execute using JIDO with robust error handling
    case Jido.Exec.run(
      program.action_module, 
      action_config, 
      Map.merge(context, input.arguments.execution_options)
    ) do
      {:ok, outputs} ->
        # Record execution in Ash
        DSPEx.Resources.Execution.create!(%{
          program_id: program.id,
          inputs: input.arguments.inputs,
          outputs: outputs,
          status: :success,
          executed_at: DateTime.utc_now()
        })
        
        {:ok, outputs}
      
      {:error, reason} = error ->
        # Record failed execution
        DSPEx.Resources.Execution.create!(%{
          program_id: program.id,
          inputs: input.arguments.inputs,
          outputs: %{},
          status: :failed,
          error_reason: reason,
          executed_at: DateTime.utc_now()
        })
        
        error
    end
  end
end

# Declarative Program Definition
defmodule MyApp.Programs do
  use DSPEx.Framework
  
  program :question_answering do
    signature MySignatures.QuestionAnswering
    action DSPEx.Actions.VariablePredict
    
    variables do
      choice :adapter, [:json_tool, :markdown_tool]
      float :temperature, range: {0.1, 1.5}
      choice :model, ["gpt-4", "claude-3"]
    end
    
    optimize_with :simba,
      training_data: @qa_training_data,
      metric: &DSPEx.Metrics.exact_match/2
  end
end
```

#### Phase 3: Enterprise Features (Weeks 9-12)
```elixir
# Real-time optimization monitoring with Ash + JIDO Signals
defmodule DSPEx.Resources.OptimizationRun do
  use Ash.Resource,
    domain: DSPEx.Domain

  attributes do
    uuid_primary_key :id
    attribute :status, :atom, constraints: [one_of: [:running, :completed, :failed]]
    attribute :progress, :float, default: 0.0
    attribute :best_score, :float
    attribute :current_iteration, :integer, default: 0
    attribute :max_iterations, :integer
  end

  relationships do
    belongs_to :program, DSPEx.Resources.Program
    has_many :optimization_trials, DSPEx.Resources.OptimizationTrial
  end

  actions do
    action :start_optimization, DSPEx.Resources.OptimizationRun do
      argument :program_id, :uuid, allow_nil?: false
      argument :optimization_params, :map, default: %{}
      
      run DSPEx.Actions.StartOptimization
    end
  end

  preparations do
    prepare DSPEx.Preparations.SubscribeToOptimizationSignals
  end

  changes do
    change after_action(&emit_optimization_events/3), on: [:update]
  end

  defp emit_optimization_events(changeset, record, _context) do
    # Emit JIDO signals for real-time updates
    Jido.Signal.emit(%Jido.Signal{
      type: "dspex.optimization.progress",
      data: %{
        run_id: record.id,
        progress: record.progress,
        best_score: record.best_score,
        status: record.status
      }
    })
    
    {:ok, record}
  end
end

# Enterprise API with automatic GraphQL generation
defmodule DSPExWeb.Schema do
  use Absinthe.Schema
  use AshGraphql, domains: [DSPEx.Domain]

  query do
    # Automatically generated queries for all Ash resources
    # - programs
    # - optimization_runs  
    # - executions
    # - optimization_trials
  end

  mutation do
    # Automatically generated mutations
    # - create_program
    # - execute_program
    # - optimize_program
    # - start_optimization
  end

  subscription do
    field :optimization_progress, :optimization_run do
      arg :run_id, non_null(:id)
      
      config fn args, _info ->
        {:ok, topic: "optimization:#{args.run_id}"}
      end
      
      trigger [:update_optimization_run], topic: fn record ->
        "optimization:#{record.id}"
      end
    end
  end
end
```

### Benefits
- **Declarative Programming**: Define programs and optimizations declaratively
- **Enterprise Features**: Automatic APIs, real-time subscriptions, audit trails
- **Robust Execution**: JIDO's battle-tested execution with Ash's data modeling
- **Rich Querying**: Complex optimization analysis with Ash queries
- **Real-time Updates**: Live optimization monitoring via GraphQL subscriptions

### Integration Timeline
- **Week 1-4**: Ash resources for JIDO actions
- **Week 5-8**: Declarative optimization workflows
- **Week 9-12**: Enterprise features and APIs
- **Spans Phases 2-3** of master integration plan

---

## Strategic Recommendation Matrix

| Approach | Innovation Level | Risk Level | Implementation Time | Strategic Value | Best Fit |
|----------|-----------------|------------|-------------------|-----------------|----------|
| **Selective Foundation** | Medium | Low | 6 weeks | High | Teams wanting immediate improvements |
| **Event-Driven Architecture** | High | Medium | 10 weeks | Very High | Teams needing observability |
| **JIDO Runtime Foundation** | Very High | High | 14 weeks | Very High | Teams building agent systems |
| **Variable System + JIDO** | Very High | Medium | 12 weeks | Extremely High | Teams focused on optimization |
| **Ash + JIDO Unified** | Extremely High | High | 12 weeks | Extremely High | Enterprise teams |

## Recommended Phased Implementation

### Phase 1: Foundation (Weeks 1-6)
**Start with Approach 1: Selective Foundation Enhancement**
- Low risk, high value
- Immediate improvements to robustness
- Team learns JIDO patterns gradually
- Preserves DSPEx identity

### Phase 2: Architecture Evolution (Weeks 7-16)
**Choose based on strategic priorities:**

**For Optimization-Focused Teams:**
- **Approach 4: Variable System + JIDO Actions**
- Revolutionary parameter optimization
- Continuous learning capabilities

**For Enterprise Teams:**
- **Approach 5: Ash + JIDO Unified Framework**
- Declarative programming model
- Enterprise-grade features

**For Agent-Focused Teams:**
- **Approach 3: JIDO Runtime Foundation**
- Stateful, supervised programs
- Advanced orchestration capabilities

### Phase 3: Advanced Features (Weeks 17-24)
**Add Event-Driven Architecture (Approach 2) to any chosen path:**
- Real-time optimization monitoring
- Decoupled, scalable architecture

## Integration Points with Master Plan

### Fits in Phase 1 (Foundation Consolidation)
- **Approach 1**: Selective Foundation Enhancement
- Enhances missing behavior definitions
- Improves validation and error handling

### Fits in Phase 2 (Variable System Integration)
- **Approach 4**: Variable System + JIDO Actions
- **Approach 2**: Event-Driven Architecture
- Enhances variable system with robust execution
- Adds real-time optimization monitoring

### Spans Phases 2-3 (Advanced Integration)
- **Approach 3**: JIDO Runtime Foundation
- **Approach 5**: Ash + JIDO Unified Framework
- Major architectural transformations
- Enterprise-grade features

## Conclusion

The JIDO integration represents a strategic opportunity to transform DSPEx from a DSPy port into a uniquely powerful, BEAM-native AI optimization framework. Each approach offers different trade-offs, but all leverage JIDO's battle-tested patterns to enhance DSPEx's capabilities.

**Recommended Path**: Start with **Selective Foundation Enhancement** for immediate value, then evolve toward **Variable System + JIDO Actions** for revolutionary optimization capabilities, with **Event-Driven Architecture** as the ultimate observability layer.

This phased approach manages risk while maximizing innovation, positioning DSPEx as the most advanced prompt engineering framework available. 