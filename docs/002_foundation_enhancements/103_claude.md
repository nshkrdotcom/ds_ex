Looking at the comprehensive Foundation library documentation and the extensive enhancement proposals already made, I can see significant opportunities for additional foundational improvements that would benefit not just DSPEx but any complex, distributed Elixir application. Let me propose complementary enhancements that focus on core infrastructure capabilities.

## Foundation Enhancement Series IV: Advanced Infrastructure Primitives

### Enhancement 21: Dynamic Resource Discovery and Service Mesh

**Overview:** Build intelligent service discovery that can adapt to changing network topologies and automatically route requests to optimal service instances.

```elixir
defmodule Foundation.ServiceMesh do
  @moduledoc """
  Dynamic service discovery and routing with health-aware load balancing.
  """

  def register_service(service_name, instance_info, health_check_opts \\ []) do
    instance_id = Foundation.Utils.generate_id()
    
    instance_data = %{
      id: instance_id,
      service_name: service_name,
      node: Node.self(),
      pid: instance_info.pid,
      metadata: instance_info.metadata || %{},
      capabilities: instance_info.capabilities || [],
      registered_at: DateTime.utc_now(),
      last_health_check: nil,
      health_status: :unknown,
      load_score: 0.0,
      version: instance_info.version || "1.0.0"
    }
    
    # Start health monitoring
    {:ok, monitor_pid} = Foundation.ServiceMesh.HealthMonitor.start_link(
      instance_id, 
      health_check_opts
    )
    
    # Register in distributed registry
    Foundation.ServiceRegistry.register(
      :global, 
      {:service_instance, service_name, instance_id}, 
      instance_data
    )
    
    {:ok, instance_id}
  end

  def discover_service(service_name, requirements \\ %{}) do
    # Get all instances of the service
    instances = Foundation.ServiceRegistry.list_by_pattern(
      :global, 
      {:service_instance, service_name, :_}
    )
    
    # Filter by requirements and health
    viable_instances = 
      instances
      |> filter_by_health(:healthy)
      |> filter_by_capabilities(requirements[:capabilities] || [])
      |> filter_by_version(requirements[:min_version])
      |> sort_by_load_and_locality()
    
    case viable_instances do
      [] -> {:error, :no_viable_instances}
      [best | alternatives] -> {:ok, best, alternatives}
    end
  end

  def route_request(service_name, request, opts \\ []) do
    case discover_service(service_name, opts[:requirements] || %{}) do
      {:ok, instance, _alternatives} ->
        execute_with_circuit_protection(instance, request, opts)
      
      {:error, reason} ->
        {:error, Foundation.Error.new(:service_unavailable, 
          "No viable instances for service #{service_name}",
          context: %{service: service_name, reason: reason}
        )}
    end
  end

  defp execute_with_circuit_protection(instance, request, opts) do
    Foundation.Infrastructure.execute_protected(
      {:service_instance, instance.id},
      [
        circuit_breaker: instance.service_name,
        timeout: opts[:timeout] || 30_000
      ],
      fn -> GenServer.call(instance.pid, request) end
    )
  end
end

defmodule Foundation.ServiceMesh.HealthMonitor do
  use GenServer
  
  def start_link(instance_id, opts) do
    GenServer.start_link(__MODULE__, {instance_id, opts})
  end
  
  def init({instance_id, opts}) do
    check_interval = opts[:check_interval] || 30_000
    health_check_fun = opts[:health_check] || fn -> :ok end
    
    # Schedule first health check
    Process.send_after(self(), :health_check, 1000)
    
    state = %{
      instance_id: instance_id,
      check_interval: check_interval,
      health_check_fun: health_check_fun,
      consecutive_failures: 0,
      last_check_time: nil
    }
    
    {:ok, state}
  end
  
  def handle_info(:health_check, state) do
    health_result = perform_health_check(state)
    update_instance_health(state.instance_id, health_result)
    
    # Schedule next check
    Process.send_after(self(), :health_check, state.check_interval)
    
    new_failures = case health_result do
      :healthy -> 0
      _ -> state.consecutive_failures + 1
    end
    
    {:noreply, %{state | 
      consecutive_failures: new_failures,
      last_check_time: DateTime.utc_now()
    }}
  end
  
  defp perform_health_check(state) do
    try do
      case state.health_check_fun.() do
        :ok -> :healthy
        {:ok, _} -> :healthy
        :error -> :unhealthy
        {:error, _} -> :unhealthy
        _ -> :unknown
      end
    rescue
      _ -> :unhealthy
    catch
      :exit, _ -> :unhealthy
    end
  end
end
```

### Enhancement 22: Advanced Data Pipeline Framework

**Overview:** Sophisticated data processing pipelines with transformation stages, error recovery, and backpressure management.

```elixir
defmodule Foundation.Pipeline do
  @moduledoc """
  Advanced data processing pipelines with stages, transformations, and flow control.
  """

  defstruct [
    :name,
    :stages,
    :config,
    :supervisor_pid,
    :metrics
  ]

  def create_pipeline(name, stage_definitions, opts \\ []) do
    config = %{
      name: name,
      max_concurrency: opts[:max_concurrency] || System.schedulers_online(),
      buffer_size: opts[:buffer_size] || 1000,
      error_strategy: opts[:error_strategy] || :retry,
      metrics_enabled: opts[:metrics_enabled] || true
    }
    
    # Validate and compile stages
    {:ok, compiled_stages} = compile_stages(stage_definitions)
    
    # Start pipeline supervisor
    {:ok, supervisor_pid} = Foundation.Pipeline.Supervisor.start_link(
      name: name,
      stages: compiled_stages,
      config: config
    )
    
    pipeline = %__MODULE__{
      name: name,
      stages: compiled_stages,
      config: config,
      supervisor_pid: supervisor_pid,
      metrics: Foundation.Pipeline.Metrics.new(name)
    }
    
    {:ok, pipeline}
  end

  def process_item(pipeline, data, opts \\ []) do
    correlation_id = opts[:correlation_id] || Foundation.Utils.generate_correlation_id()
    
    # Create processing context
    context = %{
      correlation_id: correlation_id,
      pipeline_name: pipeline.name,
      data: data,
      stage_results: %{},
      started_at: System.monotonic_time()
    }
    
    # Start processing through the pipeline
    Foundation.Pipeline.Executor.process(pipeline, context)
  end

  def process_stream(pipeline, data_stream, opts \\ []) do
    # Create a GenStage pipeline for streaming data
    data_stream
    |> Foundation.Pipeline.StreamProcessor.new(pipeline, opts)
    |> Stream.map(&Foundation.Pipeline.Executor.process(pipeline, &1))
  end

  defp compile_stages(stage_definitions) do
    compiled = 
      stage_definitions
      |> Enum.with_index()
      |> Enum.map(fn {{stage_name, stage_config}, index} ->
        %{
          name: stage_name,
          index: index,
          type: stage_config[:type] || :transform,
          function: stage_config[:function],
          config: stage_config[:config] || %{},
          retry_policy: stage_config[:retry_policy] || %{max_attempts: 3},
          timeout: stage_config[:timeout] || 30_000
        }
      end)
    
    {:ok, compiled}
  end
end

defmodule Foundation.Pipeline.Executor do
  def process(pipeline, context) do
    pipeline.stages
    |> Enum.reduce_while({:ok, context}, fn stage, {:ok, ctx} ->
      case execute_stage(stage, ctx, pipeline.config) do
        {:ok, updated_ctx} ->
          {:cont, {:ok, updated_ctx}}
        
        {:error, reason} ->
          handle_stage_error(stage, reason, ctx, pipeline.config)
      end
    end)
    |> case do
      {:ok, final_context} ->
        # Emit success metrics
        duration = System.monotonic_time() - final_context.started_at
        
        Foundation.Telemetry.emit_histogram(
          [:foundation, :pipeline, :processing_time],
          duration,
          %{pipeline: pipeline.name, success: true}
        )
        
        {:ok, final_context.data}
      
      {:error, reason} ->
        # Emit error metrics
        Foundation.Telemetry.emit_counter(
          [:foundation, :pipeline, :errors],
          %{pipeline: pipeline.name, stage: reason.stage}
        )
        
        {:error, reason}
    end
  end

  defp execute_stage(stage, context, pipeline_config) do
    stage_context = Foundation.ErrorContext.new(
      Foundation.Pipeline.Stage, 
      stage.name,
      correlation_id: context.correlation_id,
      metadata: %{
        pipeline: pipeline_config.name,
        stage_index: stage.index
      }
    )
    
    Foundation.ErrorContext.with_context(stage_context, fn ->
      case stage.type do
        :transform -> execute_transform_stage(stage, context)
        :validate -> execute_validation_stage(stage, context)
        :enrich -> execute_enrichment_stage(stage, context)
        :filter -> execute_filter_stage(stage, context)
        :branch -> execute_branch_stage(stage, context)
        :aggregate -> execute_aggregate_stage(stage, context)
      end
    end)
  end

  defp execute_transform_stage(stage, context) do
    try do
      transformed_data = stage.function.(context.data, stage.config)
      
      updated_context = %{context |
        data: transformed_data,
        stage_results: Map.put(context.stage_results, stage.name, :success)
      }
      
      {:ok, updated_context}
    rescue
      error ->
        {:error, %{stage: stage.name, reason: error, type: :transform_error}}
    end
  end

  defp execute_validation_stage(stage, context) do
    case stage.function.(context.data, stage.config) do
      true -> {:ok, context}
      false -> {:error, %{stage: stage.name, reason: :validation_failed}}
      {:error, reason} -> {:error, %{stage: stage.name, reason: reason}}
    end
  end

  defp handle_stage_error(stage, reason, context, pipeline_config) do
    case pipeline_config.error_strategy do
      :retry ->
        attempt_stage_retry(stage, reason, context, pipeline_config)
      
      :skip ->
        {:cont, {:ok, context}}
      
      :fail ->
        {:halt, {:error, reason}}
      
      :default_value ->
        default_data = stage.config[:default_value] || context.data
        updated_context = %{context | data: default_data}
        {:cont, {:ok, updated_context}}
    end
  end
end
```

### Enhancement 23: Intelligent Caching with Machine Learning

**Overview:** Self-optimizing cache that learns access patterns and predicts future needs.

```elixir
defmodule Foundation.IntelligentCache do
  @moduledoc """
  ML-powered caching system that learns and adapts to usage patterns.
  """

  use GenServer
  
  defstruct [
    :name,
    :l1_cache,
    :l2_cache,
    :l3_cache,
    :access_patterns,
    :prediction_model,
    :warming_scheduler,
    :analytics
  ]

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  def get_or_compute(cache_name, key, compute_fn, opts \\ []) do
    GenServer.call(via_tuple(cache_name), {:get_or_compute, key, compute_fn, opts})
  end

  def init(opts) do
    name = opts[:name]
    config = opts[:config] || %{}
    
    # Initialize multi-tier cache
    {:ok, l1_cache} = Foundation.Cache.L1.start_link(
      size: config[:l1_size] || 1000,
      policy: :lru
    )
    
    {:ok, l2_cache} = Foundation.Cache.L2.start_link(
      size: config[:l2_size] || 10_000,
      policy: :lfu,
      persistence: :disk
    )
    
    {:ok, l3_cache} = Foundation.Cache.L3.start_link(
      type: :distributed,
      size: config[:l3_size] || 100_000
    )
    
    # Initialize access pattern tracking
    access_patterns = Foundation.IntelligentCache.PatternTracker.new()
    
    # Start prediction model
    {:ok, prediction_model} = Foundation.IntelligentCache.MLModel.start_link(name)
    
    # Start cache warming scheduler
    {:ok, warming_scheduler} = Foundation.IntelligentCache.Warmer.start_link(name)
    
    state = %__MODULE__{
      name: name,
      l1_cache: l1_cache,
      l2_cache: l2_cache,
      l3_cache: l3_cache,
      access_patterns: access_patterns,
      prediction_model: prediction_model,
      warming_scheduler: warming_scheduler,
      analytics: Foundation.IntelligentCache.Analytics.new()
    }
    
    # Schedule periodic optimization
    :timer.send_interval(300_000, :optimize_cache)  # Every 5 minutes
    
    {:ok, state}
  end

  def handle_call({:get_or_compute, key, compute_fn, opts}, _from, state) do
    start_time = System.monotonic_time()
    access_context = create_access_context(key, opts)
    
    # Record access pattern
    updated_patterns = Foundation.IntelligentCache.PatternTracker.record_access(
      state.access_patterns, 
      access_context
    )
    
    # Try cache tiers in order
    result = case try_cache_tiers(key, state) do
      {:hit, value, tier} ->
        # Cache hit - promote to higher tier if beneficial
        maybe_promote_to_higher_tier(key, value, tier, state)
        
        # Record hit metrics
        record_cache_metrics(:hit, tier, start_time, access_context)
        
        {:ok, value}
      
      :miss ->
        # Cache miss - compute value
        case compute_value_with_protection(compute_fn, access_context) do
          {:ok, computed_value} ->
            # Determine optimal cache tier for this value
            optimal_tier = determine_optimal_cache_tier(
              key, 
              computed_value, 
              access_context, 
              state
            )
            
            # Store in cache
            store_in_cache_tier(key, computed_value, optimal_tier, state)
            
            # Record miss metrics
            record_cache_metrics(:miss, :none, start_time, access_context)
            
            {:ok, computed_value}
          
          {:error, reason} ->
            {:error, reason}
        end
    end
    
    # Update state with new patterns
    new_state = %{state | access_patterns: updated_patterns}
    
    {:reply, result, new_state}
  end

  def handle_info(:optimize_cache, state) do
    # Run ML-based cache optimization
    optimization_results = Foundation.IntelligentCache.Optimizer.optimize(state)
    
    # Apply optimizations
    updated_state = apply_cache_optimizations(state, optimization_results)
    
    # Update prediction model
    Foundation.IntelligentCache.MLModel.update_model(
      state.prediction_model,
      state.access_patterns
    )
    
    {:noreply, updated_state}
  end

  defp try_cache_tiers(key, state) do
    # Try L1 (memory) first
    case Foundation.Cache.L1.get(state.l1_cache, key) do
      {:ok, value} -> {:hit, value, :l1}
      :miss ->
        # Try L2 (local disk)
        case Foundation.Cache.L2.get(state.l2_cache, key) do
          {:ok, value} -> {:hit, value, :l2}
          :miss ->
            # Try L3 (distributed)
            case Foundation.Cache.L3.get(state.l3_cache, key) do
              {:ok, value} -> {:hit, value, :l3}
              :miss -> :miss
            end
        end
    end
  end

  defp determine_optimal_cache_tier(key, value, access_context, state) do
    # Use ML model to predict optimal tier
    features = %{
      key_hash: :erlang.phash2(key),
      value_size: :erlang.external_size(value),
      access_frequency: get_access_frequency(key, state.access_patterns),
      computation_cost: access_context.computation_time || 0,
      temporal_locality: calculate_temporal_locality(key, state.access_patterns),
      user_priority: access_context.priority || :normal
    }
    
    case Foundation.IntelligentCache.MLModel.predict_optimal_tier(
      state.prediction_model, 
      features
    ) do
      {:ok, tier} -> tier
      _ -> :l1  # Default fallback
    end
  end
end

defmodule Foundation.IntelligentCache.MLModel do
  @moduledoc """
  Machine learning model for cache optimization decisions.
  """
  
  use GenServer
  
  def start_link(cache_name) do
    GenServer.start_link(__MODULE__, cache_name)
  end
  
  def predict_optimal_tier(model_pid, features) do
    GenServer.call(model_pid, {:predict, features})
  end
  
  def update_model(model_pid, access_patterns) do
    GenServer.cast(model_pid, {:update, access_patterns})
  end
  
  def init(cache_name) do
    # Initialize simple decision tree model
    model = %{
      type: :decision_tree,
      rules: default_decision_rules(),
      learned_patterns: %{},
      cache_name: cache_name,
      training_data: []
    }
    
    {:ok, model}
  end
  
  def handle_call({:predict, features}, _from, model) do
    prediction = apply_decision_rules(features, model.rules)
    {:reply, {:ok, prediction}, model}
  end
  
  def handle_cast({:update, access_patterns}, model) do
    # Extract training data from access patterns
    new_training_data = extract_training_data(access_patterns)
    
    # Update model with new data
    updated_model = retrain_model(model, new_training_data)
    
    {:noreply, updated_model}
  end
  
  defp default_decision_rules do
    [
      # High frequency + small size -> L1
      %{
        condition: fn f -> f.access_frequency > 10 and f.value_size < 1024 end,
        result: :l1,
        confidence: 0.9
      },
      
      # Medium frequency + medium size -> L2  
      %{
        condition: fn f -> f.access_frequency > 2 and f.value_size < 10_240 end,
        result: :l2,
        confidence: 0.7
      },
      
      # Low frequency or large size -> L3
      %{
        condition: fn f -> f.access_frequency <= 2 or f.value_size >= 10_240 end,
        result: :l3,
        confidence: 0.6
      }
    ]
  end
  
  defp apply_decision_rules(features, rules) do
    rules
    |> Enum.find(fn rule -> rule.condition.(features) end)
    |> case do
      nil -> :l1  # Default
      rule -> rule.result
    end
  end
end
```

### Enhancement 24: Event Sourcing and CQRS Infrastructure

**Overview:** Production-ready event sourcing with projections, snapshots, and command/query separation.

```elixir
defmodule Foundation.EventSourcing do
  @moduledoc """
  Event sourcing infrastructure with CQRS support, projections, and snapshots.
  """

  def create_aggregate(aggregate_module, aggregate_id, opts \\ []) do
    # Start aggregate process
    {:ok, aggregate_pid} = Foundation.EventSourcing.Aggregate.start_link(
      module: aggregate_module,
      id: aggregate_id,
      opts: opts
    )
    
    # Register in aggregate registry
    Foundation.ServiceRegistry.register(
      :event_sourcing,
      {:aggregate, aggregate_module, aggregate_id},
      aggregate_pid
    )
    
    {:ok, aggregate_pid}
  end

  def execute_command(aggregate_module, aggregate_id, command) do
    case Foundation.ServiceRegistry.lookup(
      :event_sourcing, 
      {:aggregate, aggregate_module, aggregate_id}
    ) do
      {:ok, pid} ->
        GenServer.call(pid, {:execute_command, command})
      
      {:error, :not_found} ->
        # Auto-create aggregate if it doesn't exist
        {:ok, pid} = create_aggregate(aggregate_module, aggregate_id)
        GenServer.call(pid, {:execute_command, command})
    end
  end

  def create_projection(projection_module, event_types, opts \\ []) do
    projection_id = Foundation.Utils.generate_id()
    
    # Start projection process
    {:ok, projection_pid} = Foundation.EventSourcing.Projection.start_link(
      module: projection_module,
      id: projection_id,
      event_types: event_types,
      opts: opts
    )
    
    # Subscribe to relevant events
    Enum.each(event_types, fn event_type ->
      Foundation.Events.subscribe_to_pattern(
        {:event_type, event_type},
        projection_pid
      )
    end)
    
    {:ok, projection_id}
  end

  def query_projection(projection_module, query, opts \\ []) do
    case Foundation.ServiceRegistry.lookup(
      :event_sourcing,
      {:projection, projection_module}
    ) do
      {:ok, pid} ->
        GenServer.call(pid, {:query, query, opts})
      
      {:error, :not_found} ->
        {:error, Foundation.Error.new(:projection_not_found,
          "Projection #{projection_module} not found")}
    end
  end
end

defmodule Foundation.EventSourcing.Aggregate do
  use GenServer
  
  def start_link(opts) do
    module = Keyword.fetch!(opts, :module)
    id = Keyword.fetch!(opts, :id)
    
    GenServer.start_link(__MODULE__, {module, id, opts})
  end
  
  def init({module, id, opts}) do
    # Load aggregate state from event store
    {:ok, events} = Foundation.Events.query(%{
      aggregate_id: id,
      aggregate_type: module
    })
    
    # Replay events to build current state
    state = %{
      module: module,
      id: id,
      version: length(events),
      data: replay_events(module, events),
      uncommitted_events: [],
      snapshot_threshold: opts[:snapshot_threshold] || 100
    }
    
    {:ok, state}
  end
  
  def handle_call({:execute_command, command}, _from, state) do
    correlation_id = Foundation.Utils.generate_correlation_id()
    
    # Validate command
    case state.module.validate_command(command, state.data) do
      :ok ->
        # Execute command and get events
        case state.module.handle_command(command, state.data) do
          {:ok, events} when is_list(events) ->
            # Apply events to state
            new_data = apply_events(state.module, state.data, events)
            
            # Store events
            stored_events = store_events(events, state, correlation_id)
            
            # Update state
            new_state = %{state |
              version: state.version + length(events),
              data: new_data,
              uncommitted_events: []
            }
            
            # Check if snapshot needed
            maybe_create_snapshot(new_state)
            
            {:reply, {:ok, stored_events}, new_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  defp replay_events(module, events) do
    events
    |> Enum.sort_by(& &1.data.sequence_number)
    |> Enum.reduce(module.initial_state(), fn event, acc ->
      module.apply_event(event, acc)
    end)
  end
  
  defp apply_events(module, current_state, events) do
    Enum.reduce(events, current_state, fn event, acc ->
      module.apply_event(event, acc)
    end)
  end
  
  defp store_events(events, state, correlation_id) do
    events
    |> Enum.with_index(state.version + 1)
    |> Enum.map(fn {event, sequence_number} ->
      event_data = %{
        aggregate_id: state.id,
        aggregate_type: state.module,
        sequence_number: sequence_number,
        event_type: event.event_type,
        event_data: event.data,
        metadata: event.metadata || %{}
      }
      
      Foundation.Events.new_event(
        event.event_type,
        event_data,
        correlation_id: correlation_id
      )
      |> Foundation.Events.store()
    end)
  end
end

defmodule Foundation.EventSourcing.Projection do
  use GenServer
  
  def start_link(opts) do
    module = Keyword.fetch!(opts, :module)
    id = Keyword.fetch!(opts, :id)
    
    GenServer.start_link(__MODULE__, {module, id, opts})
  end
  
  def init({module, id, opts}) do
    # Initialize projection state
    state = %{
      module: module,
      id: id,
      data: module.initial_state(),
      last_processed_event: nil,
      processing_mode: opts[:mode] || :realtime
    }
    
    # If catching up, process historical events
    if state.processing_mode == :catchup do
      spawn_link(fn -> catch_up_with_events(self(), module, opts[:event_types]) end)
    end
    
    {:ok, state}
  end
  
  def handle_info({:foundation_event, event}, state) do
    # Process event through projection
    case state.module.handle_event(event, state.data) do
      {:ok, new_data} ->
        updated_state = %{state |
          data: new_data,
          last_processed_event: event.id
        }
        
        # Emit projection update event
        Foundation.Events.new_event(:projection_updated, %{
          projection_module: state.module,
          projection_id: state.id,
          event_id: event.id
        })
        |> Foundation.Events.store()
        
        {:noreply, updated_state}
      
      {:error, reason} ->
        Logger.error("Projection #{state.module} failed to process event",
          event_id: event.id,
          reason: reason)
        
        {:noreply, state}
    end
  end
  
  def handle_call({:query, query, opts}, _from, state) do
    result = state.module.handle_query(query, state.data, opts)
    {:reply, result, state}
  end
end
```

### Enhancement 25: Advanced Distributed State Management

**Overview:** Sophisticated distributed state synchronization with conflict resolution and eventual consistency.

```elixir
defmodule Foundation.DistributedState do
  @moduledoc """
  Advanced distributed state management with conflict resolution and consistency guarantees.
  """

  def create_distributed_object(name, initial_state, opts \\ []) do
    consistency_model = opts[:consistency] || :eventual
    conflict_resolution = opts[:conflict_resolution] || :last_writer_wins
    
    # Create CRDT-based state object
    {:ok, state_pid} = Foundation.DistributedState.Object.start_link(
      name: name,
      initial_state: initial_state,
      consistency_model: consistency_model,
      conflict_resolution: conflict_resolution
    )
    
    # Register in distributed registry
    Foundation.ServiceRegistry.register(
      :global,
      {:distributed_state, name},
      state_pid
    )
    
    # Set up replication to other nodes
    setup_replication(name, Node.list())
    
    {:ok, name}
  end

  def update_state(object_name, update_fn) when is_function(update_fn, 1) do
    case Foundation.ServiceRegistry.lookup(:global, {:distributed_state, object_name}) do
      {:ok, pid} ->
        GenServer.call(pid, {:update, update_fn})
      
      {:error, :not_found} ->
        {:error, Foundation.Error.new(:object_not_found,
          "Distributed state object #{object_name} not found")}
    end
  end

  def get_state(object_name) do
    case Foundation.ServiceRegistry.lookup(:global, {:distributed_state, object_name}) do
      {:ok, pid} ->
        GenServer.call(pid, :get_state)
      
      {:error, :not_found} ->
        {:error, Foundation.Error.new(:object_not_found,
          "Distributed state object #{object_name} not found")}
    end
  end

  def sync_with_nodes(object_name, nodes) do
    case Foundation.ServiceRegistry.lookup(:global, {:distributed_state, object_name}) do
      {:ok, pid} ->
        GenServer.cast(pid, {:sync_with_nodes, nodes})
      
      {:error, :not_found} ->
        {:error, :object_not_found}
    end
  end
end

## Foundation Enhancement Series IV: Advanced Infrastructure Primitives (Continued)

```elixir
defmodule Foundation.DistributedState.Object do
  use GenServer
  
  defstruct [
    :name,
    :state,
    :vector_clock,
    :consistency_model,
    :conflict_resolution,
    :pending_updates,
    :sync_partners
  ]
  
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts)
  end
  
  def init(opts) do
    name = opts[:name]
    initial_state = opts[:initial_state]
    
    state = %__MODULE__{
      name: name,
      state: initial_state,
      vector_clock: Foundation.DistributedState.VectorClock.new(Node.self()),
      consistency_model: opts[:consistency_model],
      conflict_resolution: opts[:conflict_resolution],
      pending_updates: [],
      sync_partners: []
    }
    
    # Start periodic sync with other nodes
    :timer.send_interval(5000, :sync_state)
    
    # Monitor node changes
    :net_kernel.monitor_nodes(true)
    
    {:ok, state}
  end
  
  def handle_call({:update, update_fn}, _from, state) do
    try do
      # Apply update function to current state
      new_local_state = update_fn.(state.state)
      
      # Create update operation with vector clock
      updated_clock = Foundation.DistributedState.VectorClock.increment(
        state.vector_clock, 
        Node.self()
      )
      
      update_operation = %{
        id: Foundation.Utils.generate_id(),
        timestamp: DateTime.utc_now(),
        node: Node.self(),
        vector_clock: updated_clock,
        operation: :update,
        update_fn: update_fn,
        previous_state_hash: :erlang.phash2(state.state)
      }
      
      # Apply update locally
      new_state = %{state |
        state: new_local_state,
        vector_clock: updated_clock,
        pending_updates: [update_operation | state.pending_updates]
      }
      
      # Replicate to other nodes asynchronously
      spawn(fn -> replicate_update(state.name, update_operation, state.sync_partners) end)
      
      {:reply, {:ok, new_local_state}, new_state}
    rescue
      error ->
        {:reply, {:error, error}, state}
    end
  end
  
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state.state}, state}
  end
  
  def handle_cast({:sync_with_nodes, nodes}, state) do
    new_sync_partners = Enum.uniq(nodes ++ state.sync_partners)
    {:noreply, %{state | sync_partners: new_sync_partners}}
  end
  
  def handle_cast({:remote_update, update_operation}, state) do
    # Handle update from remote node
    case should_apply_remote_update?(update_operation, state) do
      true ->
        new_state = apply_remote_update(update_operation, state)
        {:noreply, new_state}
      
      false ->
        # Conflict detected - resolve using configured strategy
        resolved_state = resolve_conflict(update_operation, state)
        {:noreply, resolved_state}
    end
  end
  
  def handle_info(:sync_state, state) do
    # Periodic synchronization with other nodes
    spawn(fn -> sync_with_all_partners(state.name, state.sync_partners) end)
    {:noreply, state}
  end
  
  def handle_info({:nodeup, node}, state) do
    # New node joined - add to sync partners
    new_partners = [node | state.sync_partners] |> Enum.uniq()
    {:noreply, %{state | sync_partners: new_partners}}
  end
  
  def handle_info({:nodedown, node}, state) do
    # Node left - remove from sync partners
    new_partners = List.delete(state.sync_partners, node)
    {:noreply, %{state | sync_partners: new_partners}}
  end
  
  defp should_apply_remote_update?(update_operation, state) do
    # Check if remote update can be applied based on vector clocks
    Foundation.DistributedState.VectorClock.can_apply?(
      update_operation.vector_clock,
      state.vector_clock
    )
  end
  
  defp apply_remote_update(update_operation, state) do
    try do
      # Apply the remote update function
      new_state_data = update_operation.update_fn.(state.state)
      
      # Merge vector clocks
      merged_clock = Foundation.DistributedState.VectorClock.merge(
        state.vector_clock,
        update_operation.vector_clock
      )
      
      %{state |
        state: new_state_data,
        vector_clock: merged_clock
      }
    rescue
      _error ->
        # If update fails, trigger conflict resolution
        resolve_conflict(update_operation, state)
    end
  end
  
  defp resolve_conflict(update_operation, state) do
    case state.conflict_resolution do
      :last_writer_wins ->
        # Compare timestamps
        if DateTime.compare(update_operation.timestamp, DateTime.utc_now()) == :gt do
          apply_remote_update(update_operation, state)
        else
          state
        end
      
      :manual ->
        # Queue for manual resolution
        Foundation.Events.new_event(:state_conflict_detected, %{
          object_name: state.name,
          local_state: state.state,
          remote_operation: update_operation
        })
        |> Foundation.Events.store()
        
        state
      
      :merge ->
        # Attempt automatic merge
        attempt_automatic_merge(update_operation, state)
    end
  end
  
  defp replicate_update(object_name, update_operation, sync_partners) do
    Enum.each(sync_partners, fn node ->
      case :rpc.call(node, GenServer, :cast, [
        {:via, Foundation.ServiceRegistry, {:global, {:distributed_state, object_name}}},
        {:remote_update, update_operation}
      ]) do
        :ok -> :ok
        {:badrpc, reason} ->
          Logger.warn("Failed to replicate to node #{node}: #{inspect(reason)}")
      end
    end)
  end
end

defmodule Foundation.DistributedState.VectorClock do
  @moduledoc """
  Vector clock implementation for distributed state ordering.
  """
  
  def new(node) do
    %{node => 1}
  end
  
  def increment(clock, node) do
    Map.update(clock, node, 1, &(&1 + 1))
  end
  
  def merge(clock1, clock2) do
    all_nodes = MapSet.union(MapSet.new(Map.keys(clock1)), MapSet.new(Map.keys(clock2)))
    
    Enum.reduce(all_nodes, %{}, fn node, acc ->
      val1 = Map.get(clock1, node, 0)
      val2 = Map.get(clock2, node, 0)
      Map.put(acc, node, max(val1, val2))
    end)
  end
  
  def can_apply?(remote_clock, local_clock) do
    # Check if remote clock is causally after local clock
    Map.keys(remote_clock)
    |> Enum.all?(fn node ->
      Map.get(remote_clock, node, 0) >= Map.get(local_clock, node, 0)
    end)
  end
  
  def compare(clock1, clock2) do
    cond do
      happens_before?(clock1, clock2) -> :before
      happens_before?(clock2, clock1) -> :after
      clock1 == clock2 -> :equal
      true -> :concurrent
    end
  end
  
  defp happens_before?(clock1, clock2) do
    all_nodes = MapSet.union(MapSet.new(Map.keys(clock1)), MapSet.new(Map.keys(clock2)))
    
    less_equal = Enum.all?(all_nodes, fn node ->
      Map.get(clock1, node, 0) <= Map.get(clock2, node, 0)
    end)
    
    strictly_less = Enum.any?(all_nodes, fn node ->
      Map.get(clock1, node, 0) < Map.get(clock2, node, 0)
    end)
    
    less_equal and strictly_less
  end
end
```

### Enhancement 26: Real-time Collaboration Framework

**Overview:** Infrastructure for building real-time collaborative applications with operational transformation and conflict-free replicated data types.

```elixir
defmodule Foundation.Collaboration do
  @moduledoc """
  Real-time collaboration infrastructure with operational transformation and CRDTs.
  """

  def create_collaboration_session(session_id, document_type, opts \\ []) do
    # Start collaboration session
    {:ok, session_pid} = Foundation.Collaboration.Session.start_link(
      id: session_id,
      document_type: document_type,
      opts: opts
    )
    
    # Register session
    Foundation.ServiceRegistry.register(
      :collaboration,
      {:session, session_id},
      session_pid
    )
    
    {:ok, session_id}
  end

  def join_session(session_id, participant_id, opts \\ []) do
    case Foundation.ServiceRegistry.lookup(:collaboration, {:session, session_id}) do
      {:ok, session_pid} ->
        GenServer.call(session_pid, {:join, participant_id, opts})
      
      {:error, :not_found} ->
        {:error, Foundation.Error.new(:session_not_found,
          "Collaboration session #{session_id} not found")}
    end
  end

  def submit_operation(session_id, participant_id, operation) do
    case Foundation.ServiceRegistry.lookup(:collaboration, {:session, session_id}) do
      {:ok, session_pid} ->
        GenServer.call(session_pid, {:submit_operation, participant_id, operation})
      
      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  def get_document_state(session_id) do
    case Foundation.ServiceRegistry.lookup(:collaboration, {:session, session_id}) do
      {:ok, session_pid} ->
        GenServer.call(session_pid, :get_document_state)
      
      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end
end

defmodule Foundation.Collaboration.Session do
  use GenServer
  
  defstruct [
    :id,
    :document_type,
    :document_state,
    :participants,
    :operation_log,
    :transformation_engine,
    :conflict_resolver
  ]
  
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts)
  end
  
  def init(opts) do
    session_id = opts[:id]
    document_type = opts[:document_type]
    
    # Initialize document state based on type
    initial_state = case document_type do
      :text -> Foundation.Collaboration.TextDocument.new()
      :json -> Foundation.Collaboration.JSONDocument.new()
      :custom -> opts[:initial_state] || %{}
    end
    
    state = %__MODULE__{
      id: session_id,
      document_type: document_type,
      document_state: initial_state,
      participants: %{},
      operation_log: [],
      transformation_engine: get_transformation_engine(document_type),
      conflict_resolver: get_conflict_resolver(document_type)
    }
    
    {:ok, state}
  end
  
  def handle_call({:join, participant_id, opts}, {from_pid, _tag}, state) do
    participant_info = %{
      id: participant_id,
      pid: from_pid,
      joined_at: DateTime.utc_now(),
      cursor_position: opts[:cursor_position],
      metadata: opts[:metadata] || %{}
    }
    
    # Add participant
    new_participants = Map.put(state.participants, participant_id, participant_info)
    
    # Monitor participant process
    Process.monitor(from_pid)
    
    # Broadcast join event to other participants
    broadcast_to_participants(
      new_participants,
      {:participant_joined, participant_info},
      [participant_id]
    )
    
    new_state = %{state | participants: new_participants}
    
    # Return current document state to new participant
    {:reply, {:ok, state.document_state}, new_state}
  end
  
  def handle_call({:submit_operation, participant_id, operation}, _from, state) do
    case Map.get(state.participants, participant_id) do
      nil ->
        {:reply, {:error, :participant_not_found}, state}
      
      _participant ->
        # Transform operation against concurrent operations
        transformed_operation = transform_operation(operation, state)
        
        # Apply operation to document
        case apply_operation(transformed_operation, state.document_state, state.document_type) do
          {:ok, new_document_state} ->
            # Add to operation log
            new_log = [transformed_operation | state.operation_log]
            
            # Broadcast operation to other participants
            broadcast_to_participants(
              state.participants,
              {:operation, transformed_operation},
              [participant_id]
            )
            
            new_state = %{state |
              document_state: new_document_state,
              operation_log: new_log
            }
            
            {:reply, {:ok, transformed_operation}, new_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  def handle_call(:get_document_state, _from, state) do
    {:reply, {:ok, state.document_state}, state}
  end
  
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove participant whose process died
    {departed_participant, new_participants} = 
      Enum.find_value(state.participants, fn {id, info} ->
        if info.pid == pid do
          {info, Map.delete(state.participants, id)}
        else
          nil
        end
      end) || {nil, state.participants}
    
    if departed_participant do
      # Broadcast departure to remaining participants
      broadcast_to_participants(
        new_participants,
        {:participant_left, departed_participant},
        []
      )
    end
    
    {:noreply, %{state | participants: new_participants}}
  end
  
  defp transform_operation(operation, state) do
    # Get concurrent operations from log
    concurrent_ops = get_concurrent_operations(operation, state.operation_log)
    
    # Apply operational transformation
    state.transformation_engine.transform(operation, concurrent_ops)
  end
  
  defp apply_operation(operation, document_state, document_type) do
    case document_type do
      :text ->
        Foundation.Collaboration.TextDocument.apply_operation(document_state, operation)
      
      :json ->
        Foundation.Collaboration.JSONDocument.apply_operation(document_state, operation)
      
      :custom ->
        # Use custom operation application
        operation.apply_fn.(document_state, operation)
    end
  end
  
  defp broadcast_to_participants(participants, message, exclude_ids) do
    participants
    |> Enum.reject(fn {id, _info} -> id in exclude_ids end)
    |> Enum.each(fn {_id, info} ->
      send(info.pid, {:collaboration_event, message})
    end)
  end
end

defmodule Foundation.Collaboration.TextDocument do
  @moduledoc """
  Text document implementation with operational transformation.
  """
  
  defstruct [:content, :version]
  
  def new(initial_content \\ "") do
    %__MODULE__{
      content: initial_content,
      version: 0
    }
  end
  
  def apply_operation(document, operation) do
    case operation.type do
      :insert ->
        apply_insert(document, operation)
      
      :delete ->
        apply_delete(document, operation)
      
      :retain ->
        {:ok, document}  # Retain operations don't change content
      
      _ ->
        {:error, :unknown_operation_type}
    end
  end
  
  defp apply_insert(document, operation) do
    position = operation.position
    text = operation.text
    
    {before, after} = String.split_at(document.content, position)
    new_content = before <> text <> after
    
    new_document = %{document |
      content: new_content,
      version: document.version + 1
    }
    
    {:ok, new_document}
  end
  
  defp apply_delete(document, operation) do
    position = operation.position
    length = operation.length
    
    {before, rest} = String.split_at(document.content, position)
    {_deleted, after} = String.split_at(rest, length)
    new_content = before <> after
    
    new_document = %{document |
      content: new_content,
      version: document.version + 1
    }
    
    {:ok, new_document}
  end
end

defmodule Foundation.Collaboration.OperationalTransform do
  @moduledoc """
  Operational transformation algorithms for conflict resolution.
  """
  
  def transform_text_operations(op1, op2) do
    # Implement operational transformation for text operations
    case {op1.type, op2.type} do
      {:insert, :insert} ->
        transform_insert_insert(op1, op2)
      
      {:insert, :delete} ->
        transform_insert_delete(op1, op2)
      
      {:delete, :insert} ->
        {op2_prime, op1_prime} = transform_insert_delete(op2, op1)
        {op1_prime, op2_prime}
      
      {:delete, :delete} ->
        transform_delete_delete(op1, op2)
    end
  end
  
  defp transform_insert_insert(op1, op2) do
    # Two concurrent insertions
    if op1.position <= op2.position do
      # op1 is before or at same position as op2
      op2_prime = %{op2 | position: op2.position + String.length(op1.text)}
      {op1, op2_prime}
    else
      # op2 is before op1
      op1_prime = %{op1 | position: op1.position + String.length(op2.text)}
      {op1_prime, op2}
    end
  end
  
  defp transform_insert_delete(insert_op, delete_op) do
    if insert_op.position <= delete_op.position do
      # Insert is before delete
      delete_op_prime = %{delete_op | position: delete_op.position + String.length(insert_op.text)}
      {insert_op, delete_op_prime}
    else
      # Insert is after delete start
      if insert_op.position >= delete_op.position + delete_op.length do
        # Insert is after delete end
        insert_op_prime = %{insert_op | position: insert_op.position - delete_op.length}
        {insert_op_prime, delete_op}
      else
        # Insert is within delete range
        insert_op_prime = %{insert_op | position: delete_op.position}
        delete_op_prime = %{delete_op | length: delete_op.length + String.length(insert_op.text)}
        {insert_op_prime, delete_op_prime}
      end
    end
  end
  
  defp transform_delete_delete(op1, op2) do
    # Two concurrent deletions - complex case
    cond do
      op1.position + op1.length <= op2.position ->
        # op1 is completely before op2
        op2_prime = %{op2 | position: op2.position - op1.length}
        {op1, op2_prime}
      
      op2.position + op2.length <= op1.position ->
        # op2 is completely before op1
        op1_prime = %{op1 | position: op1.position - op2.length}
        {op1_prime, op2}
      
      true ->
        # Deletions overlap - need to resolve carefully
        resolve_overlapping_deletes(op1, op2)
    end
  end
  
  defp resolve_overlapping_deletes(op1, op2) do
    # Simplified: merge overlapping deletes
    start_pos = min(op1.position, op2.position)
    end_pos = max(op1.position + op1.length, op2.position + op2.length)
    
    # Create a single delete operation that covers both ranges
    merged_delete = %{
      type: :delete,
      position: start_pos,
      length: end_pos - start_pos
    }
    
    # Return empty operation for one, merged for other
    {merged_delete, %{type: :retain}}
  end
end
```

### Enhancement 27: Multi-Tenant Resource Isolation

**Overview:** Comprehensive multi-tenancy support with resource isolation, quota management, and tenant-specific configurations.

```elixir
defmodule Foundation.MultiTenant do
  @moduledoc """
  Multi-tenant infrastructure with resource isolation and quota management.
  """

  def create_tenant(tenant_id, config \\ %{}) do
    # Validate tenant configuration
    case validate_tenant_config(config) do
      :ok ->
        # Create tenant namespace
        tenant_namespace = {:tenant, tenant_id}
        
        # Start tenant supervisor
        {:ok, supervisor_pid} = Foundation.MultiTenant.TenantSupervisor.start_link(
          tenant_id: tenant_id,
          config: config
        )
        
        # Register tenant
        Foundation.ServiceRegistry.register(
          :multi_tenant,
          tenant_namespace,
          supervisor_pid
        )
        
        # Initialize tenant resources
        initialize_tenant_resources(tenant_id, config)
        
        {:ok, tenant_id}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_tenant_context(tenant_id) do
    case Foundation.ServiceRegistry.lookup(:multi_tenant, {:tenant, tenant_id}) do
      {:ok, supervisor_pid} ->
        {:ok, %{
          tenant_id: tenant_id,
          supervisor: supervisor_pid,
          namespace: {:tenant, tenant_id}
        }}
      
      {:error, :not_found} ->
        {:error, Foundation.Error.new(:tenant_not_found,
          "Tenant #{tenant_id} not found")}
    end
  end

  def execute_in_tenant_context(tenant_id, fun) do
    case get_tenant_context(tenant_id) do
      {:ok, context} ->
        # Set up tenant-specific configuration
        previous_config = Foundation.Config.get_all()
        
        try do
          # Apply tenant-specific configuration
          apply_tenant_config(tenant_id)
          
          # Execute function in tenant context
          fun.(context)
        after
          # Restore previous configuration
          Foundation.Config.replace_all(previous_config)
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  def check_resource_quota(tenant_id, resource_type, requested_amount) do
    case Foundation.MultiTenant.QuotaManager.check_quota(
      tenant_id, 
      resource_type, 
      requested_amount
    ) do
      :ok -> :ok
      {:error, :quota_exceeded} -> {:error, :quota_exceeded}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_tenant_config(config) do
    required_fields = [:name, :resource_quotas]
    
    missing_fields = required_fields -- Map.keys(config)
    
    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_fields, fields}}
    end
  end

  defp initialize_tenant_resources(tenant_id, config) do
    # Initialize tenant-specific quotas
    Foundation.MultiTenant.QuotaManager.initialize_quotas(tenant_id, config.resource_quotas)
    
    # Set up tenant-specific event streams
    Foundation.Events.create_tenant_stream(tenant_id)
    
    # Initialize tenant-specific telemetry
    Foundation.Telemetry.create_tenant_namespace(tenant_id)
    
    :ok
  end
end

defmodule Foundation.MultiTenant.TenantSupervisor do
  use Supervisor
  
  def start_link(opts) do
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(tenant_id))
  end
  
  def init(opts) do
    tenant_id = opts[:tenant_id]
    config = opts[:config]
    
    children = [
      # Tenant-specific services
      {Foundation.MultiTenant.ResourceManager, tenant_id: tenant_id, config: config},
      {Foundation.MultiTenant.QuotaManager, tenant_id: tenant_id, quotas: config.resource_quotas},
      {Foundation.MultiTenant.EventProcessor, tenant_id: tenant_id},
      
      # Dynamic supervisor for tenant processes
      {DynamicSupervisor, name: tenant_dynamic_supervisor_name(tenant_id), strategy: :one_for_one}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  defp via_tuple(tenant_id) do
    Foundation.ServiceRegistry.via_tuple(:multi_tenant, {:tenant_supervisor, tenant_id})
  end
  
  defp tenant_dynamic_supervisor_name(tenant_id) do
    {:via, Foundation.ServiceRegistry, {:multi_tenant, {:tenant_dynamic_supervisor, tenant_id}}}
  end
end

defmodule Foundation.MultiTenant.QuotaManager do
  use GenServer
  
  defstruct [
    :tenant_id,
    :quotas,
    :current_usage,
    :usage_history
  ]
  
  def start_link(opts) do
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    GenServer.start_link(__MODULE__, opts, 
      name: via_tuple(tenant_id))
  end
  
  def check_quota(tenant_id, resource_type, requested_amount) do
    GenServer.call(via_tuple(tenant_id), {:check_quota, resource_type, requested_amount})
  end
  
  def consume_quota(tenant_id, resource_type, amount) do
    GenServer.call(via_tuple(tenant_id), {:consume_quota, resource_type, amount})
  end
  
  def get_usage_stats(tenant_id) do
    GenServer.call(via_tuple(tenant_id), :get_usage_stats)
  end
  
  def init(opts) do
    tenant_id = opts[:tenant_id]
    quotas = opts[:quotas]
    
    # Initialize usage tracking
    current_usage = 
      quotas
      |> Map.keys()
      |> Enum.map(fn resource_type -> {resource_type, 0} end)
      |> Enum.into(%{})
    
    state = %__MODULE__{
      tenant_id: tenant_id,
      quotas: quotas,
      current_usage: current_usage,
      usage_history: []
    }
    
    # Schedule periodic usage cleanup
    :timer.send_interval(300_000, :cleanup_usage_history)  # Every 5 minutes
    
    {:ok, state}
  end
  
  def handle_call({:check_quota, resource_type, requested_amount}, _from, state) do
    current_usage = Map.get(state.current_usage, resource_type, 0)
    quota_limit = Map.get(state.quotas, resource_type, :unlimited)
    
    result = case quota_limit do
      :unlimited -> :ok
      limit when is_number(limit) ->
        if current_usage + requested_amount <= limit do
          :ok
        else
          {:error, :quota_exceeded}
        end
      _ -> {:error, :invalid_quota_config}
    end
    
    {:reply, result, state}
  end
  
  def handle_call({:consume_quota, resource_type, amount}, _from, state) do
    case handle_call({:check_quota, resource_type, amount}, nil, state) do
      {:reply, :ok, _} ->
        # Update usage
        new_usage = Map.update(state.current_usage, resource_type, amount, &(&1 + amount))
        
        # Record usage event
        usage_event = %{
          resource_type: resource_type,
          amount: amount,
          timestamp: DateTime.utc_now(),
          total_usage: Map.get(new_usage, resource_type)
        }
        
        new_history = [usage_event | Enum.take(state.usage_history, 999)]
        
        new_state = %{state |
          current_usage: new_usage,
          usage_history: new_history
        }
        
        # Emit telemetry
        Foundation.Telemetry.emit_gauge(
          [:foundation, :tenant, :resource_usage],
          Map.get(new_usage, resource_type),
          %{tenant_id: state.tenant_id, resource_type: resource_type}
        )
        
        {:reply, :ok, new_state}
      
      {:reply, error, state} ->
        {:reply, error, state}
    end
  end
  
  def handle_call(:get_usage_stats, _from, state) do
    stats = %{
      tenant_id: state.tenant_id,
      current_usage: state.current_usage,
      quotas: state.quotas,
      utilization: calculate_utilization(state.current_usage, state.quotas),
      recent_activity: Enum.take(state.usage_history, 10)
    }
    
    {:reply, {:ok, stats}, state}
  end
  
  def handle_info(:cleanup_usage_history, state) do
    # Keep only recent history (last hour)
    cutoff_time = DateTime.add(DateTime.utc_now(), -3600, :second)
    
    new_history = 
      state.usage_history
      |> Enum.filter(fn event ->
        DateTime.compare(event.timestamp, cutoff_time) == :gt
      end)
    
    {:noreply, %{state | usage_history: new_history}}
  end
  
  defp calculate_utilization(current_usage, quotas) do
    Enum.map(current_usage, fn {resource_type, usage} ->
      quota = Map.get(quotas, resource_type, :unlimited)
      
      utilization = case quota do
        :unlimited -> 0.0
        limit when is_number(limit) and limit > 0 -> usage / limit
        _ -> 0.0
      end
      
      {resource_type, utilization}
    end)
    |> Enum.into(%{})
  end
  
  defp via_tuple(tenant_id) do
    Foundation.ServiceRegistry.via_tuple(:multi_tenant, {:quota_manager, tenant_id})
  end
end
```
 