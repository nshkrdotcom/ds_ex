# DSPEx Implementation Guide: Foundation 2.0 Development Strategy

## Executive Summary

This implementation guide provides a detailed roadmap for transforming DSPEx from its current state into a distributed AI programming framework powered by Foundation 2.0. The strategy balances immediate deliverables with the long-term vision of 1000+ node AI clusters.

## Current State Analysis & Action Plan

### Phase 1A: Foundation Consolidation (Weeks 1-2)
**Objective**: Complete the actual Phase 1 with proper Foundation integration

#### Critical Tasks with Detailed Implementation Steps

##### 1. GenServer-Based Client Architecture

**Current Issue**: The existing client in `lib/dspex/client.ex` is a basic HTTP wrapper.

**Solution**: Replace with Foundation 2.0-enhanced GenServer architecture.

```elixir
# File: lib/dspex/client/manager.ex
defmodule DSPEx.Client.Manager do
  @moduledoc """
  Central client manager using Foundation 2.0 infrastructure.
  Manages multiple provider clients with shared protection mechanisms.
  """
  
  use GenServer
  alias Foundation.{Infrastructure, Config, ServiceRegistry}
  
  # State management
  defstruct [
    :clients,        # %{provider_name => client_pid}
    :infrastructure, # Foundation infrastructure references
    :config,         # Merged configuration
    :stats           # Runtime statistics
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Wait for Foundation to be available
    :ok = Foundation.ready?() || wait_for_foundation()
    
    # Load DSPEx configuration
    {:ok, config} = Config.get([:dspex])
    
    # Initialize Foundation infrastructure
    {:ok, infrastructure} = setup_foundation_infrastructure(config)
    
    # Start provider clients
    {:ok, clients} = start_provider_clients(config.providers, infrastructure)
    
    # Register with Foundation service registry
    :ok = ServiceRegistry.register(
      :production,
      :dspex_client_manager,
      self(),
      %{
        capabilities: [:llm_inference, :distributed_optimization],
        providers: Map.keys(clients)
      }
    )
    
    state = %__MODULE__{
      clients: clients,
      infrastructure: infrastructure,
      config: config,
      stats: %{started_at: DateTime.utc_now(), requests: 0}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:request, provider, messages, opts}, _from, state) do
    case Map.get(state.clients, provider) do
      nil ->
        {:reply, {:error, :provider_not_configured}, state}
      
      client_pid ->
        # Forward to specific provider client
        result = GenServer.call(client_pid, {:request, messages, opts})
        
        # Update stats
        updated_state = update_in(state, [:stats, :requests], &(&1 + 1))
        
        {:reply, result, updated_state}
    end
  end
  
  # Private implementation details...
  defp setup_foundation_infrastructure(config) do
    # Configure Foundation services for DSPEx
    protection_configs = build_protection_configs(config.providers)
    
    Enum.each(protection_configs, fn {provider, protection_config} ->
      Infrastructure.configure_protection(:"dspex_#{provider}", protection_config)
    end)
    
    {:ok, %{protection_keys: Map.keys(protection_configs)}}
  end
  
  defp start_provider_clients(providers_config, infrastructure) do
    clients = Enum.reduce(providers_config, %{}, fn {provider, config}, acc ->
      {:ok, client_pid} = DSPEx.Client.Provider.start_link([
        provider: provider,
        config: config,
        infrastructure: infrastructure
      ])
      
      Map.put(acc, provider, client_pid)
    end)
    
    {:ok, clients}
  end
  
  defp wait_for_foundation() do
    case Foundation.available?() do
      true -> :ok
      false ->
        Process.sleep(100)
        wait_for_foundation()
    end
  end
end
```

**Implementation Steps**:

1. **Update existing client.ex** (Day 1):
   ```bash
   # Backup current implementation
   cp lib/dspex/client.ex lib/dspex/client.ex.backup
   
   # Create new structure
   mkdir -p lib/dspex/client
   ```

2. **Create provider-specific client** (Day 2):
   ```elixir
   # File: lib/dspex/client/provider.ex
   defmodule DSPEx.Client.Provider do
     use GenServer
     alias Foundation.Infrastructure
     
     def start_link(opts) do
       provider = Keyword.fetch!(opts, :provider)
       GenServer.start_link(__MODULE__, opts, name: :"dspex_client_#{provider}")
     end
     
     @impl true
     def init(opts) do
       provider = Keyword.fetch!(opts, :provider)
       config = Keyword.fetch!(opts, :config)
       infrastructure = Keyword.fetch!(opts, :infrastructure)
       
       # Set up provider-specific pool
       pool_name = :"dspex_#{provider}_pool"
       
       :ok = Infrastructure.ConnectionManager.start_pool(pool_name, %{
         worker_module: DSPEx.Client.HttpWorker,
         worker_args: [
           provider: provider,
           api_key: resolve_api_key(config.api_key),
           base_url: config.base_url,
           timeout: config.timeout || 30_000
         ],
         size: config.pool_size || 10,
         max_overflow: config.max_overflow || 5
       })
       
       state = %{
         provider: provider,
         pool_name: pool_name,
         protection_key: :"dspex_#{provider}",
         config: config,
         stats: %{requests: 0, errors: 0}
       }
       
       {:ok, state}
     end
     
     @impl true
     def handle_call({:request, messages, opts}, _from, state) do
       correlation_id = Keyword.get(opts, :correlation_id) || 
         Foundation.Utils.generate_correlation_id()
       
       Foundation.Context.with_correlation_id(correlation_id, fn ->
         request_fn = fn ->
           Infrastructure.ConnectionManager.execute_with_worker(
             state.pool_name,
             fn worker ->
               DSPEx.Client.HttpWorker.post(worker, %{
                 messages: messages,
                 model: opts[:model] || state.config.default_model,
                 temperature: opts[:temperature] || 0.7,
                 max_tokens: opts[:max_tokens] || 150
               })
             end
           )
         end
         
         result = Infrastructure.execute_protected(
           state.protection_key,
           [
             connection_pool: state.pool_name,
             rate_limiter: {:api_calls, opts[:user_id] || :global}
           ],
           request_fn
         )
         
         # Update stats
         updated_state = case result do
           {:ok, _} -> update_in(state, [:stats, :requests], &(&1 + 1))
           {:error, _} -> 
             state
             |> update_in([:stats, :requests], &(&1 + 1))
             |> update_in([:stats, :errors], &(&1 + 1))
         end
         
         {:reply, result, updated_state}
       end)
     end
     
     defp resolve_api_key({:system, env_var}), do: System.get_env(env_var)
     defp resolve_api_key(api_key) when is_binary(api_key), do: api_key
   end
   ```

3. **Update application.ex** (Day 3):
   ```elixir
   # File: lib/dspex/application.ex
   def start(_type, _args) do
     children = [
       # Foundation services start automatically
       
       # DSPEx-specific services
       {DSPEx.Services.ConfigManager, []},
       {DSPEx.Services.TelemetrySetup, []},
       
       # Enhanced client manager
       {DSPEx.Client.Manager, []},
       
       # HTTP client pool
       {Finch, name: DSPEx.Finch}
     ]
     
     opts = [strategy: :one_for_one, name: Dspex.Supervisor]
     Supervisor.start_link(children, opts)
   end
   ```

##### 2. DSPEx.Program Behavior Implementation

**Current Issue**: Missing `DSPEx.Program` behavior referenced throughout codebase.

**Solution**: Define comprehensive behavior and update existing modules.

```elixir
# File: lib/dspex/program.ex
defmodule DSPEx.Program do
  @moduledoc """
  Behavior for all DSPEx programs with Foundation 2.0 integration.
  """
  
  alias Foundation.{Context, Telemetry}
  
  @type program :: struct()
  @type inputs :: map()
  @type outputs :: map()
  @type options :: keyword()
  
  @callback forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}
  @callback forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}
  
  @optional_callbacks forward: 3
  
  @doc """
  Execute a program with Foundation 2.0 observability.
  """
  @spec forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}
  def forward(program, inputs) do
    forward(program, inputs, [])
  end
  
  @spec forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}
  def forward(program, inputs, opts) do
    correlation_id = Keyword.get(opts, :correlation_id) || 
      Foundation.Utils.generate_correlation_id()
    
    Context.with_correlation_id(correlation_id, fn ->
      Telemetry.emit_span([:dspex, :program, :forward], %{
        program: program_name(program),
        correlation_id: correlation_id
      }, fn ->
        program.__struct__.forward(program, inputs, opts)
      end)
    end)
  end
  
  @doc """
  Macro for implementing program behavior with automatic telemetry.
  """
  defmacro __using__(opts) do
    quote do
      @behaviour DSPEx.Program
      
      @impl DSPEx.Program
      def forward(program, inputs, opts \\ []) do
        # Default implementation calls forward/2 if not overridden
        if function_exported?(__MODULE__, :forward, 2) do
          forward(program, inputs)
        else
          {:error, :not_implemented}
        end
      end
      
      defoverridable forward: 3
    end
  end
  
  defp program_name(program) when is_struct(program) do
    program.__struct__
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end
  defp program_name(_), do: :unknown
end
```

**Implementation Steps**:

1. **Create program.ex** (Day 1):
   - Define behavior and macros
   - Add telemetry integration
   - Create utility functions

2. **Update DSPEx.Predict** (Day 2):
   ```elixir
   # File: lib/dspex/predict.ex (updated)
   defmodule DSPEx.Predict do
     use DSPEx.Program
     
     defstruct [:signature, :client, :adapter, demos: []]
     
     @impl DSPEx.Program
     def forward(program, inputs, opts \\ []) do
       with {:ok, messages} <- DSPEx.Adapter.format_messages(
              program.signature, 
              program.demos, 
              inputs
            ),
            {:ok, response} <- DSPEx.Client.request(
              program.client, 
              messages, 
              opts
            ),
            {:ok, outputs} <- DSPEx.Adapter.parse_response(
              program.signature, 
              response
            ) do
         {:ok, outputs}
       end
     end
   end
   ```

3. **Update other program modules** (Day 3):
   - Add `use DSPEx.Program` to all program modules
   - Ensure consistent `forward/3` implementations

##### 3. Enhanced Configuration Management

**Current Issue**: ConfigManager has Foundation integration but limited capabilities.

**Solution**: Enhance with distributed configuration and hot updates.

```elixir
# File: lib/dspex/services/config_manager.ex (enhanced)
defmodule DSPEx.Services.ConfigManager do
  use GenServer
  require Logger
  
  alias Foundation.{Config, Events, DistributedState}
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    :ok = wait_for_foundation()
    
    # Set up distributed configuration state
    {:ok, distributed_config} = DistributedState.create(
      :dspex_config,
      get_default_config()
    )
    
    # Register for configuration change events
    :ok = Events.subscribe([:dspex, :config, :changed])
    
    # Enhanced circuit breaker setup
    setup_enhanced_circuit_breakers()
    
    state = %{
      distributed_config: distributed_config,
      local_cache: %{},
      last_update: DateTime.utc_now()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get, path}, _from, state) do
    # Try local cache first, then distributed state
    case get_from_cache(state.local_cache, path) do
      {:ok, value} -> 
        {:reply, {:ok, value}, state}
      :not_found ->
        case DistributedState.get(state.distributed_config, path) do
          {:ok, value} ->
            # Update local cache
            updated_cache = put_in_cache(state.local_cache, path, value)
            {:reply, {:ok, value}, %{state | local_cache: updated_cache}}
          error ->
            {:reply, error, state}
        end
    end
  end
  
  @impl true
  def handle_call({:update, path, value}, _from, state) do
    case DistributedState.update(state.distributed_config, path, value) do
      :ok ->
        # Update local cache and broadcast change
        updated_cache = put_in_cache(state.local_cache, path, value)
        
        Events.emit([:dspex, :config, :changed], %{
          path: path,
          value: value,
          timestamp: DateTime.utc_now()
        })
        
        {:reply, :ok, %{state | local_cache: updated_cache}}
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_info({:foundation_event, [:dspex, :config, :changed], metadata}, state) do
    # Handle configuration changes from other nodes
    Logger.info("Configuration changed: #{inspect(metadata)}")
    
    # Invalidate local cache for changed path
    updated_cache = remove_from_cache(state.local_cache, metadata.path)
    
    {:noreply, %{state | local_cache: updated_cache, last_update: DateTime.utc_now()}}
  end
  
  defp setup_enhanced_circuit_breakers() do
    providers = [:openai, :anthropic, :gemini, :cohere]
    
    Enum.each(providers, fn provider ->
      circuit_config = %{
        failure_threshold: 5,
        recovery_time: 30_000,
        failure_analyzer: &analyze_provider_failures/1,
        recovery_strategy: :exponential_backoff
      }
      
      Foundation.Infrastructure.initialize_circuit_breaker(
        :"dspex_#{provider}",
        circuit_config
      )
    end)
  end
  
  defp analyze_provider_failures(failures) do
    # Enhanced failure analysis
    recent_failures = Enum.filter(failures, fn failure ->
      DateTime.diff(DateTime.utc_now(), failure.timestamp, :second) < 300
    end)
    
    error_types = Enum.frequencies_by(recent_failures, & &1.error_type)
    
    cond do
      Map.get(error_types, :rate_limit, 0) > 3 -> :rate_limited
      Map.get(error_types, :timeout, 0) > 5 -> :network_issues
      Map.get(error_types, :api_error, 0) > 2 -> :service_degraded
      true -> :transient_failure
    end
  end
  
  # Cache management helpers
  defp get_from_cache(cache, path) do
    case get_in(cache, path) do
      nil -> :not_found
      value -> {:ok, value}
    end
  end
  
  defp put_in_cache(cache, path, value) do
    put_in(cache, path, value)
  end
  
  defp remove_from_cache(cache, path) do
    pop_in(cache, path) |> elem(1)
  end
end
```

### Phase 1B: Evaluation Engine (Weeks 3-4)

#### 1. Core Evaluation Implementation

```elixir
# File: lib/dspex/evaluate.ex (complete implementation)
defmodule DSPEx.Evaluate do
  @moduledoc """
  Concurrent evaluation engine with Foundation 2.0 distribution.
  """
  
  alias Foundation.{Cluster, WorkDistribution, Context, Telemetry}
  
  @type evaluation_result :: %{
    score: float(),
    stats: %{
      total_examples: non_neg_integer(),
      successful: non_neg_integer(),
      failed: non_neg_integer(),
      duration_ms: non_neg_integer(),
      success_rate: float(),
      throughput: float(),
      errors: [term()]
    }
  }
  
  @doc """
  Run evaluation with automatic distribution if cluster available.
  """
  @spec run(DSPEx.Program.t(), [DSPEx.Example.t()], function(), keyword()) ::
    {:ok, evaluation_result()} | {:error, term()}
  def run(program, examples, metric_fn, opts \\ []) do
    if should_distribute?(opts) and cluster_available?() do
      run_distributed(program, examples, metric_fn, opts)
    else
      run_local(program, examples, metric_fn, opts)
    end
  end
  
  @doc """
  Run local evaluation with Foundation observability.
  """
  @spec run_local(DSPEx.Program.t(), [DSPEx.Example.t()], function(), keyword()) ::
    {:ok, evaluation_result()} | {:error, term()}
  def run_local(program, examples, metric_fn, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || 
      Foundation.Utils.generate_correlation_id()
    
    Context.with_correlation_id(correlation_id, fn ->
      Telemetry.emit_span([:dspex, :evaluate, :local], %{
        program: program_name(program),
        example_count: length(examples),
        correlation_id: correlation_id
      }, fn ->
        do_run_local(program, examples, metric_fn, opts)
      end)
    end)
  end
  
  @doc """
  Run distributed evaluation across Foundation cluster.
  """
  @spec run_distributed(DSPEx.Program.t(), [DSPEx.Example.t()], function(), keyword()) ::
    {:ok, evaluation_result()} | {:error, term()}
  def run_distributed(program, examples, metric_fn, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || 
      Foundation.Utils.generate_correlation_id()
    
    Context.with_correlation_id(correlation_id, fn ->
      Telemetry.emit_span([:dspex, :evaluate, :distributed], %{
        program: program_name(program),
        example_count: length(examples),
        correlation_id: correlation_id
      }, fn ->
        do_run_distributed(program, examples, metric_fn, opts)
      end)
    end)
  end
  
  # Implementation details
  defp do_run_local(program, examples, metric_fn, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 100)
    timeout = Keyword.get(opts, :timeout, :infinity)
    progress_callback = Keyword.get(opts, :progress_callback)
    
    start_time = System.monotonic_time()
    
    results = examples
    |> Stream.with_index()
    |> Task.async_stream(
      fn {example, index} ->
        result = Context.propagate(fn ->
          evaluate_single_example(program, example, metric_fn)
        end)
        
        # Report progress if callback provided
        if progress_callback && rem(index, 10) == 0 do
          progress_callback.(%{
            completed: index,
            total: length(examples),
            percentage: (index / length(examples)) * 100
          })
        end
        
        result
      end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.to_list()
    
    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    process_evaluation_results(results, duration)
  end
  
  defp do_run_distributed(program, examples, metric_fn, opts) do
    # Get capable nodes
    nodes = Cluster.active_nodes_with_capabilities([:dspex_evaluation])
    
    if Enum.empty?(nodes) do
      # Fallback to local
      do_run_local(program, examples, metric_fn, opts)
    else
      distribute_evaluation_work(program, examples, metric_fn, nodes, opts)
    end
  end
  
  defp distribute_evaluation_work(program, examples, metric_fn, nodes, opts) do
    chunk_size = calculate_optimal_chunk_size(examples, nodes)
    max_node_concurrency = Keyword.get(opts, :max_node_concurrency, 50)
    
    start_time = System.monotonic_time()
    
    results = examples
    |> Enum.chunk_every(chunk_size)
    |> Enum.with_index()
    |> Task.async_stream(fn {chunk, index} ->
      target_node = Enum.at(nodes, rem(index, length(nodes)))
      
      Context.propagate(fn ->
        WorkDistribution.execute_on_node(target_node, fn ->
          evaluate_chunk_on_node(program, chunk, metric_fn, max_node_concurrency)
        end)
      end)
    end, timeout: :infinity)
    |> Enum.reduce({[], %{}}, fn
      {:ok, {:ok, chunk_result}}, {results, stats} ->
        {[chunk_result | results], merge_chunk_stats(stats, chunk_result.stats)}
      
      {:ok, {:error, error}}, {results, stats} ->
        updated_stats = Map.update(stats, :chunk_failures, [error], &[error | &1])
        {results, updated_stats}
      
      {:exit, reason}, {results, stats} ->
        updated_stats = Map.update(stats, :node_failures, [reason], &[reason | &1])
        {results, updated_stats}
    end)
    
    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    aggregate_distributed_results(results, duration)
  end
  
  defp evaluate_chunk_on_node(program, chunk, metric_fn, max_concurrency) do
    results = chunk
    |> Task.async_stream(
      fn example ->
        evaluate_single_example(program, example, metric_fn)
      end,
      max_concurrency: max_concurrency,
      timeout: 30_000
    )
    |> Enum.to_list()
    
    {scores, errors} = Enum.reduce(results, {[], []}, fn
      {:ok, {:ok, score}}, {scores, errors} -> {[score | scores], errors}
      {:ok, {:error, error}}, {scores, errors} -> {scores, [error | errors]}
      {:exit, reason}, {scores, errors} -> {scores, [{:timeout, reason} | errors]}
    end)
    
    {:ok, %{
      scores: scores,
      stats: %{
        node: node(),
        chunk_size: length(chunk),
        successful: length(scores),
        failed: length(errors),
        errors: errors
      }
    }}
  end
  
  defp evaluate_single_example(program, example, metric_fn) do
    Telemetry.emit_span([:dspex, :evaluate, :example], %{}, fn ->
      with {:ok, prediction} <- DSPEx.Program.forward(program, example.inputs),
           score when is_number(score) <- metric_fn.(example, prediction) do
        {:ok, score}
      else
        {:error, reason} -> {:error, reason}
        other -> {:error, {:invalid_metric_result, other}}
      end
    end)
  end
  
  # Utility functions
  defp should_distribute?(opts) do
    Keyword.get(opts, :distributed, true)
  end
  
  defp cluster_available?() do
    Foundation.Cluster.active_nodes() |> length() > 1
  end
  
  defp calculate_optimal_chunk_size(examples, nodes) do
    total_examples = length(examples)
    total_nodes = length(nodes)
    
    # Aim for 2-3 chunks per node
    chunk_size = div(total_examples, total_nodes * 3)
    max(chunk_size, 1)
  end
  
  defp process_evaluation_results(results, duration) do
    {scores, errors} = Enum.reduce(results, {[], []}, fn
      {:ok, {:ok, score}}, {scores, errors} -> {[score | scores], errors}
      {:ok, {:error, error}}, {scores, errors} -> {scores, [error | errors]}
      {:exit, reason}, {scores, errors} -> {scores, [{:timeout, reason} | errors]}
    end)
    
    if Enum.empty?(scores) do
      {:error, :no_successful_evaluations}
    else
      total_examples = length(scores) + length(errors)
      average_score = Enum.sum(scores) / length(scores)
      success_rate = length(scores) / total_examples
      throughput = total_examples / (duration / 1000)  # examples per second
      
      {:ok, %{
        score: average_score,
        stats: %{
          total_examples: total_examples,
          successful: length(scores),
          failed: length(errors),
          duration_ms: duration,
          success_rate: success_rate,
          throughput: throughput,
          errors: errors
        }
      }}
    end
  end
  
  defp aggregate_distributed_results({chunk_results, global_stats}, duration) do
    all_scores = Enum.flat_map(chunk_results, & &1.scores)
    
    if Enum.empty?(all_scores) do
      {:error, :no_successful_evaluations}
    else
      total_stats = Enum.reduce(chunk_results, %{}, fn chunk_result, acc ->
        %{
          total_examples: (acc[:total_examples] || 0) + chunk_result.stats.chunk_size,
          successful: (acc[:successful] || 0) + chunk_result.stats.successful,
          failed: (acc[:failed] || 0) + chunk_result.stats.failed,
          nodes_used: MapSet.put(acc[:nodes_used] || MapSet.new(), chunk_result.stats.node)
        }
      end)
      
      average_score = Enum.sum(all_scores) / length(all_scores)
      success_rate = total_stats.successful / total_stats.total_examples
      throughput = total_stats.total_examples / (duration / 1000)
      
      {:ok, %{
        score: average_score,
        stats: %{
          total_examples: total_stats.total_examples,
          successful: total_stats.successful,
          failed: total_stats.failed,
          duration_ms: duration,
          success_rate: success_rate,
          throughput: throughput,
          nodes_used: MapSet.size(total_stats.nodes_used),
          distribution_overhead: calculate_distribution_overhead(duration, chunk_results),
          errors: []
        }
      }}
    end
  end
  
  defp merge_chunk_stats(global_stats, chunk_stats) do
    Map.merge(global_stats, chunk_stats, fn
      _key, v1, v2 when is_number(v1) and is_number(v2) -> v1 + v2
      _key, v1, v2 when is_list(v1) and is_list(v2) -> v1 ++ v2
      _key, _v1, v2 -> v2
    end)
  end
  
  defp calculate_distribution_overhead(total_duration, chunk_results) do
    # Calculate overhead of distribution vs estimated local time
    estimated_local_duration = Enum.max(Enum.map(chunk_results, fn result ->
      get_in(result.stats, [:duration_ms]) || 0
    end))
    
    overhead_percentage = ((total_duration - estimated_local_duration) / total_duration) * 100
    max(overhead_percentage, 0)
  end
  
  defp program_name(program) when is_struct(program) do
    program.__struct__
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end
  defp program_name(_), do: :unknown
end
```

## Testing Strategy for Phase 1

### 1. Unit Tests for Enhanced Client

```elixir
# File: test/dspex/client_test.exs
defmodule DSPEx.ClientTest do
  use ExUnit.Case, async: true
  
  import Mox
  
  setup :verify_on_exit!
  
  describe "Foundation integration" do
    test "client manager starts with Foundation infrastructure" do
      # Mock Foundation services
      expect(Foundation.Config, :get, fn [:dspex] ->
        {:ok, %{
          providers: %{
            openai: %{
              api_key: {:system, "OPENAI_API_KEY"},
              base_url: "https://api.openai.com/v1",
              default_model: "gpt-4"
            }
          }
        }}
      end)
      
      assert {:ok, _pid} = DSPEx.Client.Manager.start_link([])
    end
    
    test "provider client handles Foundation protection" do
      # Test circuit breaker integration
      # Test rate limiting
      # Test connection pooling
    end
  end
  
  describe "multi-provider support" do
    test "routes requests to correct provider" do
      # Test OpenAI routing
      # Test Anthropic routing
      # Test Gemini routing
    end
    
    test "handles provider-specific response formats" do
      # Test response transformation
    end
  end
end
```

### 2. Integration Tests for Evaluation

```elixir
# File: test/dspex/evaluate_test.exs
defmodule DSPEx.EvaluateTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.{Evaluate, Example}
  
  setup do
    # Set up test program and examples
    program = %DSPEx.Predict{
      signature: TestSignature,
      client: :test_client
    }
    
    examples = [
      %Example{inputs: %{question: "What is 2+2?"}, outputs: %{answer: "4"}},
      %Example{inputs: %{question: "What is 3+3?"}, outputs: %{answer: "6"}}
    ]
    
    metric_fn = fn example, prediction ->
      if example.outputs.answer == prediction.outputs.answer, do: 1.0, else: 0.0
    end
    
    %{program: program, examples: examples, metric_fn: metric_fn}
  end
  
  test "local evaluation with Foundation telemetry", %{program: program, examples: examples, metric_fn: metric_fn} do
    {:ok, result} = Evaluate.run_local(program, examples, metric_fn)
    
    assert result.score >= 0.0
    assert result.stats.total_examples == 2
    assert is_number(result.stats.duration_ms)
  end
  
  test "distributed evaluation when cluster available", %{program: program, examples: examples, metric_fn: metric_fn} do
    # Mock cluster availability
    # Test distributed coordination
    # Verify results aggregation
  end
end
```

## Success Metrics for Phase 1 Completion

### Technical Metrics
- [ ] All existing tests pass with new architecture
- [ ] Zero Dialyzer warnings maintained
- [ ] Foundation 2.0 services operational (Circuit Breaker, Rate Limiter, Connection Pool)
- [ ] Multi-provider support functional (OpenAI, Anthropic, Gemini)
- [ ] Evaluation engine supports both local and distributed execution

### Performance Metrics
- [ ] Client startup time < 500ms
- [ ] Request latency overhead < 50ms vs direct HTTP
- [ ] Evaluation throughput > 100 examples/second locally
- [ ] Memory usage stable under load

### Documentation Metrics
- [ ] Updated README reflecting actual capabilities
- [ ] API documentation for all public functions
- [ ] Architecture decision records for major changes
- [ ] Migration guide from Phase 0 to Phase 1

## Risk Mitigation

### Foundation Library Dependency
- **Risk**: Foundation 2.0 features not ready
- **Mitigation**: Fallback implementations for each Foundation service
- **Timeline**: Weekly check-ins with Foundation development

### Performance Regression
- **Risk**: Enhanced architecture slower than simple HTTP
- **Mitigation**: Comprehensive benchmarking at each step
- **Timeline**: Performance gates before merging

### Complexity Overengineering
- **Risk**: Over-architecting for future needs
- **Mitigation**: YAGNI principle, incremental complexity
- **Timeline**: Regular architecture reviews

## Next Steps After Phase 1

Once Phase 1 is successfully completed, the foundation will be solid for the revolutionary distributed AI capabilities that make DSPEx unique.

### Phase 2: Optimization Engine (Weeks 5-8)

#### 1. Distributed Teleprompter Implementation

```elixir
# File: lib/dspex/teleprompter/distributed_bootstrap.ex
defmodule DSPEx.Teleprompter.DistributedBootstrap do
  @moduledoc """
  Foundation 2.0-powered distributed optimization engine.
  
  This represents the breakthrough capability: distributed AI program optimization
  that leverages BEAM's process model and Foundation's clustering to achieve
  unprecedented scale and reliability.
  """
  
  use GenServer
  @behaviour DSPEx.Teleprompter
  
  alias Foundation.{DistributedState, Consensus, WorkDistribution, Context, Telemetry}
  
  defstruct [
    :student,
    :teacher,
    :trainset,
    :metric_fn,
    :optimization_state,
    :consensus_group,
    demos: [],
    target_demos: 16,
    optimization_id: nil,
    nodes_participating: []
  ]
  
  @doc """
  Compile student program using distributed optimization across Foundation cluster.
  
  This is where DSPEx shows its revolutionary advantage over Python DSPy:
  - Distribute training examples across 100+ nodes
  - Use consensus algorithms to select best demonstrations
  - Fault-tolerant optimization that survives node failures
  - Real-time optimization progress across cluster
  """
  @spec compile(DSPEx.Program.t(), DSPEx.Program.t(), [DSPEx.Example.t()], function(), keyword()) ::
    {:ok, DSPEx.Program.t()} | {:error, term()}
  def compile(student, teacher, trainset, metric_fn, opts \\ []) do
    optimization_id = Foundation.Utils.generate_correlation_id()
    
    Context.with_correlation_id(optimization_id, fn ->
      Telemetry.emit_span([:dspex, :teleprompter, :compile], %{
        student: program_name(student),
        teacher: program_name(teacher),
        trainset_size: length(trainset),
        optimization_id: optimization_id
      }, fn ->
        if should_distribute?(opts) and cluster_available?() do
          compile_distributed(student, teacher, trainset, metric_fn, opts, optimization_id)
        else
          compile_local(student, teacher, trainset, metric_fn, opts)
        end
      end)
    end)
  end
  
  # Revolutionary distributed compilation
  defp compile_distributed(student, teacher, trainset, metric_fn, opts, optimization_id) do
    # Create distributed optimization state shared across cluster
    {:ok, optimization_state} = DistributedState.create(
      {:dspex_optimization, optimization_id},
      %{
        student: serialize_program(student),
        teacher: serialize_program(teacher),
        trainset: trainset,
        metric_fn_id: register_metric_function(metric_fn),
        target_demos: Keyword.get(opts, :target_demos, 16),
        quality_threshold: Keyword.get(opts, :quality_threshold, 0.7),
        nodes_participating: Foundation.Cluster.active_nodes(),
        start_time: DateTime.utc_now(),
        progress: %{completed: 0, total: length(trainset)}
      }
    )
    
    # Create consensus group for demo selection
    {:ok, consensus_group} = Consensus.create_group(
      {:dspex_demo_consensus, optimization_id},
      threshold: Keyword.get(opts, :consensus_threshold, 0.6),
      timeout: Keyword.get(opts, :consensus_timeout, 30_000)
    )
    
    # Execute distributed bootstrap process
    case execute_distributed_bootstrap(optimization_state, consensus_group, opts) do
      {:ok, optimized_demos} ->
        # Apply consensus-selected demos to student
        optimized_student = apply_demos_to_program(student, optimized_demos)
        
        # Validate optimization results
        case validate_optimization_results(student, optimized_student, trainset, metric_fn) do
          {:ok, improvement} ->
            Logger.info("Distributed optimization improved performance by #{improvement}%")
            {:ok, optimized_student}
          {:error, reason} ->
            Logger.warning("Optimization validation failed: #{inspect(reason)}")
            {:ok, student}  # Return original if optimization didn't help
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp execute_distributed_bootstrap(optimization_state, consensus_group, opts) do
    # Get nodes capable of running teacher models
    capable_nodes = Foundation.Cluster.active_nodes_with_capabilities([:dspex_teacher, :gpu_available])
    
    if Enum.empty?(capable_nodes) do
      {:error, :no_capable_nodes}
    else
      # Distribute bootstrap work with intelligent load balancing
      bootstrap_results = WorkDistribution.distribute_workload(
        optimization_state.trainset,
        capable_nodes,
        fn examples_chunk, target_node ->
          execute_bootstrap_on_node(
            target_node,
            examples_chunk,
            optimization_state,
            opts
          )
        end,
        strategy: :capability_aware,
        max_chunks_per_node: 5,
        timeout: Keyword.get(opts, :node_timeout, 300_000)  # 5 minutes per node
      )
      
      # Aggregate results and use consensus for final selection
      aggregate_and_consensus_select(bootstrap_results, consensus_group, optimization_state)
    end
  end
  
  defp execute_bootstrap_on_node(target_node, examples_chunk, optimization_state, opts) do
    WorkDistribution.execute_on_node(target_node, fn ->
      Context.propagate(fn ->
        # Deserialize programs on target node
        teacher = deserialize_program(optimization_state.teacher)
        metric_fn = get_metric_function(optimization_state.metric_fn_id)
        
        # Bootstrap examples with enhanced error handling
        bootstrapped_demos = examples_chunk
        |> Task.async_stream(
          fn example ->
            bootstrap_single_example_with_retry(
              teacher,
              example,
              metric_fn,
              optimization_state.quality_threshold,
              retries: 3,
              backoff: :exponential
            )
          end,
          max_concurrency: get_node_concurrency(target_node),
          timeout: 30_000
        )
        |> Stream.filter(fn
          {:ok, {:ok, _demo}} -> true
          _ -> false
        end)
        |> Stream.map(fn {:ok, {:ok, demo}} -> demo end)
        |> Enum.to_list()
        
        # Report progress back to distributed state
        DistributedState.update(optimization_state, [:progress, :completed], fn completed ->
          completed + length(examples_chunk)
        end)
        
        {:ok, %{
          node: target_node,
          demos: bootstrapped_demos,
          chunk_size: length(examples_chunk),
          successful: length(bootstrapped_demos),
          node_stats: get_node_performance_stats(target_node)
        }}
      end)
    end)
  end
  
  defp bootstrap_single_example_with_retry(teacher, example, metric_fn, threshold, opts) do
    retries = Keyword.get(opts, :retries, 3)
    backoff = Keyword.get(opts, :backoff, :linear)
    
    Enum.reduce_while(0..retries, {:error, :max_retries}, fn attempt, _acc ->
      case bootstrap_single_example(teacher, example, metric_fn, threshold) do
        {:ok, demo} = success ->
          {:halt, success}
        
        {:error, reason} when attempt < retries ->
          # Apply backoff strategy
          backoff_time = calculate_backoff(backoff, attempt)
          Process.sleep(backoff_time)
          
          Telemetry.emit([:dspex, :bootstrap, :retry], %{
            attempt: attempt,
            reason: reason,
            backoff_ms: backoff_time
          })
          
          {:cont, {:error, reason}}
        
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
  
  defp aggregate_and_consensus_select(bootstrap_results, consensus_group, optimization_state) do
    # Collect all successful bootstrap results
    all_demos = bootstrap_results
    |> Enum.flat_map(fn
      {:ok, %{demos: demos}} -> demos
      _ -> []
    end)
    
    if Enum.empty?(all_demos) do
      {:error, :no_successful_bootstraps}
    else
      # Score and rank all demos
      scored_demos = all_demos
      |> Enum.map(fn demo ->
        score = calculate_demo_quality_score(demo)
        {demo, score}
      end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      
      # Use Foundation's consensus algorithm to select best demos
      consensus_proposals = scored_demos
      |> Enum.take(optimization_state.target_demos * 3)  # Consider top 3x candidates
      |> Enum.chunk_every(5)  # Create manageable proposal chunks
      
      selected_demos = consensus_proposals
      |> Enum.reduce([], fn chunk, acc ->
        proposal = {:select_demos, Enum.map(chunk, &elem(&1, 0))}
        
        case Consensus.propose_and_decide(consensus_group, proposal) do
          {:ok, :accepted} ->
            acc ++ Enum.map(chunk, &elem(&1, 0))
          {:ok, :rejected} ->
            acc
          {:error, :timeout} ->
            # Fallback to local decision for this chunk
            acc ++ Enum.take(Enum.map(chunk, &elem(&1, 0)), 2)
        end
      end)
      |> Enum.take(optimization_state.target_demos)
      
      {:ok, selected_demos}
    end
  end
  
  # Advanced optimization validation
  defp validate_optimization_results(original_student, optimized_student, validation_set, metric_fn) do
    # Sample validation set for quick comparison
    sample_size = min(length(validation_set), 100)
    validation_sample = Enum.take_random(validation_set, sample_size)
    
    # Evaluate both versions
    {:ok, original_results} = DSPEx.Evaluate.run_local(
      original_student,
      validation_sample,
      metric_fn,
      max_concurrency: 20
    )
    
    {:ok, optimized_results} = DSPEx.Evaluate.run_local(
      optimized_student,
      validation_sample,
      metric_fn,
      max_concurrency: 20
    )
    
    improvement = ((optimized_results.score - original_results.score) / original_results.score) * 100
    
    if improvement > 5.0 do  # At least 5% improvement required
      {:ok, improvement}
    else
      {:error, {:insufficient_improvement, improvement}}
    end
  end
  
  # Utility functions
  defp should_distribute?(opts) do
    Keyword.get(opts, :distributed, true)
  end
  
  defp cluster_available?() do
    Foundation.Cluster.active_nodes() |> length() > 1
  end
  
  defp get_node_concurrency(node) do
    # Query node capabilities for optimal concurrency
    case Foundation.Cluster.get_node_capabilities(node) do
      %{cpu_cores: cores, memory_gb: memory} ->
        # Conservative concurrency based on resources
        min(cores * 2, div(memory, 2))
      _ ->
        10  # Safe default
    end
  end
  
  defp calculate_demo_quality_score(demo) do
    base_score = demo.metadata.bootstrap_score
    
    # Add bonus factors
    diversity_bonus = calculate_diversity_bonus(demo)
    complexity_bonus = calculate_complexity_bonus(demo)
    
    base_score + diversity_bonus + complexity_bonus
  end
  
  defp calculate_backoff(:linear, attempt), do: attempt * 1000
  defp calculate_backoff(:exponential, attempt), do: :math.pow(2, attempt) * 1000 |> round()
  
  defp program_name(program) when is_struct(program) do
    program.__struct__ |> Module.split() |> List.last() |> String.to_atom()
  end
  defp program_name(_), do: :unknown
  
  # Serialization helpers for distributed state
  defp serialize_program(program) do
    :erlang.term_to_binary(program)
  end
  
  defp deserialize_program(binary) do
    :erlang.binary_to_term(binary)
  end
  
  defp register_metric_function(metric_fn) do
    # Store function in distributed registry for cross-node access
    function_id = Foundation.Utils.generate_correlation_id()
    Foundation.DistributedRegistry.register({:metric_function, function_id}, metric_fn)
    function_id
  end
  
  defp get_metric_function(function_id) do
    Foundation.DistributedRegistry.lookup({:metric_function, function_id})
  end
end
```

#### 2. Advanced Program Composition

```elixir
# File: lib/dspex/programs/chain_of_thought.ex
defmodule DSPEx.Programs.ChainOfThought do
  @moduledoc """
  Enhanced ChainOfThought with Foundation 2.0 distributed reasoning.
  """
  
  use DSPEx.Program
  
  defstruct [:signature, :predictor, :reasoning_steps, :distributed]
  
  def new(signature, client, opts \\ []) do
    # Create extended signature with reasoning field
    extended_signature = DSPEx.Signature.extend(signature, %{
      reasoning: %{
        type: :string,
        description: "Step-by-step reasoning process",
        position: :before_outputs
      }
    })
    
    # Create internal predictor
    predictor = %DSPEx.Predict{
      signature: extended_signature,
      client: client,
      adapter: Keyword.get(opts, :adapter, DSPEx.Adapter.Chat)
    }
    
    %__MODULE__{
      signature: signature,
      predictor: predictor,
      reasoning_steps: Keyword.get(opts, :reasoning_steps, 3),
      distributed: Keyword.get(opts, :distributed, false)
    }
  end
  
  @impl DSPEx.Program
  def forward(program, inputs, opts \\ []) do
    if program.distributed and cluster_has_capacity?() do
      forward_distributed(program, inputs, opts)
    else
      forward_local(program, inputs, opts)
    end
  end
  
  defp forward_distributed(program, inputs, opts) do
    # Distribute reasoning steps across cluster nodes
    reasoning_tasks = 1..program.reasoning_steps
    |> Task.async_stream(fn step ->
      Foundation.WorkDistribution.execute_on_optimal_node(fn ->
        generate_reasoning_step(program, inputs, step, opts)
      end)
    end, timeout: :infinity)
    |> Enum.map(fn {:ok, step_result} -> step_result end)
    
    # Aggregate reasoning steps
    consolidated_reasoning = reasoning_tasks
    |> Enum.map(& &1.reasoning)
    |> Enum.join("\n\n")
    
    # Final prediction with consolidated reasoning
    enhanced_inputs = Map.put(inputs, :reasoning, consolidated_reasoning)
    DSPEx.Program.forward(program.predictor, enhanced_inputs, opts)
  end
  
  defp forward_local(program, inputs, opts) do
    DSPEx.Program.forward(program.predictor, inputs, opts)
  end
  
  defp generate_reasoning_step(program, inputs, step, opts) do
    step_prompt = "Step #{step}: Analyze this aspect of the problem..."
    step_inputs = Map.put(inputs, :step_instruction, step_prompt)
    
    case DSPEx.Program.forward(program.predictor, step_inputs, opts) do
      {:ok, result} -> %{step: step, reasoning: result.reasoning}
      {:error, _} -> %{step: step, reasoning: "Step failed"}
    end
  end
  
  defp cluster_has_capacity?() do
    Foundation.Cluster.cluster_load() < 0.8
  end
end
```

### Phase 3: Foundation 2.0 Revolutionary Features (Weeks 9-12)

#### 1. Massive Scale Architecture

```elixir
# File: lib/dspex/cluster/massive_scale.ex
defmodule DSPEx.Cluster.MassiveScale do
  @moduledoc """
  1000+ node distributed AI inference using Foundation 2.0 Partisan networking.
  
  This module represents DSPEx's revolutionary breakthrough: achieving AI workload
  distribution that's impossible with traditional clustering approaches.
  """
  
  alias Foundation.{Topology, Stream, ProcessEcosystem, Partisan}
  
  @doc """
  Execute massive-scale inference across 1000+ node cluster.
  """
  def massive_inference(program, inputs_stream, opts \\ []) do
    # Foundation 2.0 dynamic topology optimization
    optimal_topology = determine_optimal_topology(program, opts)
    :ok = Topology.switch_to(optimal_topology)
    
    # Multi-channel Partisan communication setup
    channels = setup_partisan_channels(opts)
    
    # Distributed stream processing with backpressure
    inputs_stream
    |> Stream.distribute_across_cluster(
      partition_strategy: :capability_aware,
      channels: channels,
      load_balancing: :adaptive
    )
    |> Stream.process_with_backpressure(
      processor: &process_inference_ecosystem/1,
      max_demand: Keyword.get(opts, :max_demand, 1000),
      buffer_size: Keyword.get(opts, :buffer_size, 10_000)
    )
    |> Stream.aggregate_results(
      aggregation_strategy: :consensus_based,
      quality_threshold: 0.95
    )
  end
  
  defp determine_optimal_topology(program, opts) do
    cluster_size = Foundation.Cluster.active_nodes() |> length()
    workload_type = classify_workload(program)
    
    case {cluster_size, workload_type} do
      {size, :compute_intensive} when size > 500 ->
        :hyparview  # Gossip-based for massive scale
      
      {size, :io_intensive} when size > 100 ->
        :client_server  # Hierarchical for coordination
      
      {size, _} when size > 50 ->
        :mesh  # Full connectivity for smaller clusters
      
      _ ->
        :standard_distributed_erlang
    end
  end
  
  defp setup_partisan_channels(opts) do
    base_channels = [:inference, :coordination, :telemetry]
    
    additional_channels = case Keyword.get(opts, :advanced_features, []) do
      features when :streaming in features -> [:streaming | base_channels]
      features when :real_time in features -> [:real_time | base_channels]
      _ -> base_channels
    end
    
    Enum.each(additional_channels, fn channel ->
      Partisan.setup_channel(channel, %{
        compression: true,
        encryption: Keyword.get(opts, :encryption, false),
        priority: channel_priority(channel)
      })
    end)
    
    additional_channels
  end
  
  defp process_inference_ecosystem(inputs_batch) do
    # Create process ecosystem for each batch
    ProcessEcosystem.spawn_ecosystem(
      :massive_inference_batch,
      [
        # Coordinator manages the batch
        {:coordinator, DSPEx.BatchCoordinator, [inputs: inputs_batch]},
        
        # Load balancer distributes within batch
        {:load_balancer, DSPEx.LoadBalancer, [strategy: :least_connections]},
        
        # Result aggregator collects outputs
        {:aggregator, DSPEx.ResultAggregator, [consensus_required: true]},
        
        # Health monitor tracks ecosystem health
        {:health_monitor, DSPEx.HealthMonitor, [failure_threshold: 0.1]}
      ]
    )
  end
  
  defp classify_workload(program) do
    case program do
      %{signature: signature} ->
        input_complexity = analyze_input_complexity(signature)
        output_complexity = analyze_output_complexity(signature)
        
        cond do
          input_complexity > 0.8 or output_complexity > 0.8 -> :compute_intensive
          has_external_dependencies?(program) -> :io_intensive
          true -> :balanced
        end
      
      _ -> :balanced
    end
  end
  
  defp channel_priority(:inference), do: :high
  defp channel_priority(:real_time), do: :critical
  defp channel_priority(:coordination), do: :normal
  defp channel_priority(_), do: :low
end
```

#### 2. Self-Managing Infrastructure

```elixir
# File: lib/dspex/infrastructure/self_managing.ex
defmodule DSPEx.Infrastructure.SelfManaging do
  @moduledoc """
  Self-managing AI infrastructure using Foundation 2.0 intelligence.
  
  Features:
  - Predictive scaling based on workload patterns
  - Automatic failure recovery and rerouting
  - Dynamic resource allocation
  - Cost optimization across cloud providers
  """
  
  use GenServer
  alias Foundation.{Analytics, Prediction, SelfHealing}
  
  defstruct [
    :cluster_state,
    :workload_patterns,
    :scaling_policies,
    :cost_targets,
    :performance_thresholds
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    # Initialize predictive analytics
    {:ok, analytics_engine} = Analytics.start_engine(:dspex_workload_analytics)
    
    # Set up self-healing policies
    :ok = SelfHealing.configure_policies([
      {:node_failure, &handle_node_failure/1},
      {:performance_degradation, &handle_performance_issues/1},
      {:cost_overrun, &optimize_costs/1}
    ])
    
    # Start workload pattern learning
    :ok = Prediction.start_learning(:workload_patterns, %{
      features: [:time_of_day, :request_volume, :complexity_score],
      target: :resource_demand,
      algorithm: :lstm
    })
    
    state = %__MODULE__{
      cluster_state: Foundation.Cluster.get_state(),
      workload_patterns: %{},
      scaling_policies: build_scaling_policies(opts),
      cost_targets: Keyword.get(opts, :cost_targets, %{}),
      performance_thresholds: Keyword.get(opts, :performance_thresholds, %{})
    }
    
    # Schedule periodic optimization
    :timer.send_interval(60_000, self(), :optimize_infrastructure)
    
    {:ok, state}
  end
  
  @impl true
  def handle_info(:optimize_infrastructure, state) do
    # Collect current metrics
    current_metrics = collect_infrastructure_metrics()
    
    # Predict future workload
    {:ok, workload_prediction} = Prediction.predict(:workload_patterns, %{
      current_time: DateTime.utc_now(),
      recent_metrics: current_metrics
    })
    
    # Make optimization decisions
    optimization_actions = decide_optimization_actions(
      current_metrics,
      workload_prediction,
      state
    )
    
    # Execute optimizations
    Enum.each(optimization_actions, &execute_optimization_action/1)
    
    {:noreply, state}
  end
  
  defp decide_optimization_actions(current_metrics, prediction, state) do
    actions = []
    
    # Scaling decisions
    scaling_actions = if prediction.demand_increase > 0.3 do
      [{:scale_up, calculate_scale_up_amount(prediction)}]
    else if prediction.demand_decrease > 0.3 do
      [{:scale_down, calculate_scale_down_amount(prediction)}]
    else
      []
    end
    
    # Cost optimization
    cost_actions = if current_metrics.cost_rate > state.cost_targets.max_hourly do
      [{:optimize_costs, :aggressive}]
    else
      []
    end
    
    # Performance optimization
    performance_actions = if current_metrics.p99_latency > state.performance_thresholds.max_latency do
      [{:optimize_performance, :latency_focused}]
    else
      []
    end
    
    actions ++ scaling_actions ++ cost_actions ++ performance_actions
  end
  
  defp execute_optimization_action({:scale_up, amount}) do
    Foundation.Cluster.scale_up(amount, strategy: :predictive)
  end
  
  defp execute_optimization_action({:scale_down, amount}) do
    Foundation.Cluster.scale_down(amount, strategy: :graceful)
  end
  
  defp execute_optimization_action({:optimize_costs, level}) do
    case level do
      :aggressive ->
        # Move workloads to cheaper nodes
        Foundation.WorkDistribution.rebalance(strategy: :cost_optimized)
        
        # Terminate underutilized nodes
        Foundation.Cluster.terminate_idle_nodes(utilization_threshold: 0.3)
      
      :moderate ->
        # Optimize without disrupting workloads
        Foundation.Cluster.optimize_node_types()
    end
  end
  
  defp execute_optimization_action({:optimize_performance, focus}) do
    case focus do
      :latency_focused ->
        # Move latency-sensitive workloads to optimal nodes
        Foundation.WorkDistribution.rebalance(strategy: :latency_optimized)
        
        # Enable performance boosting features
        Foundation.Cluster.enable_performance_mode([:cpu_boost, :memory_optimization])
      
      :throughput_focused ->
        Foundation.WorkDistribution.rebalance(strategy: :throughput_optimized)
    end
  end
  
  # Self-healing handlers
  defp handle_node_failure(failed_node) do
    # Immediate recovery
    affected_workloads = Foundation.Cluster.get_workloads_on_node(failed_node)
    
    # Redistribute workloads
    Enum.each(affected_workloads, fn workload ->
      Foundation.WorkDistribution.migrate_workload(
        workload,
        target_selection: :optimal_available
      )
    end)
    
    # Learn from failure
    Analytics.record_event(:node_failure, %{
      node: failed_node,
      workloads_affected: length(affected_workloads),
      recovery_time: measure_recovery_time(),
      root_cause: analyze_failure_cause(failed_node)
    })
  end
  
  defp handle_performance_issues(issue_details) do
    case issue_details.type do
      :high_latency ->
        # Identify bottleneck nodes
        bottlenecks = Foundation.Analytics.identify_bottlenecks()
        
        # Apply targeted optimizations
        Enum.each(bottlenecks, fn node ->
          Foundation.Cluster.optimize_node(node, focus: :latency)
        end)
      
      :low_throughput ->
        # Scale horizontally
        Foundation.Cluster.scale_up(
          calculate_throughput_scaling_need(),
          strategy: :throughput_optimized
        )
    end
  end
end
```

## Final Success Criteria

### Revolutionary Capabilities Achieved
- [ ] **1000+ node clusters** running stable DSPEx workloads
- [ ] **Distributed optimization** completing 10x faster than local
- [ ] **Self-healing infrastructure** with <1 minute recovery time
- [ ] **Zero-ops scaling** with predictive workload management

### Technical Excellence
- [ ] **Linear scalability** up to 1000 nodes demonstrated
- [ ] **Sub-second failover** for critical inference workloads
- [ ] **Cost optimization** reducing cloud spend by 40%
- [ ] **Performance gains** of 50x over Python DSPy at scale

### Community Impact
- [ ] **Industry recognition** as the distributed AI framework
- [ ] **Production deployments** by 10+ companies
- [ ] **Open source adoption** with 1000+ GitHub stars
- [ ] **BEAM ecosystem leadership** in AI/ML applications

This implementation guide provides the complete roadmap for transforming DSPEx into the world's first distributed-native AI programming framework, leveraging Foundation 2.0's revolutionary capabilities to achieve unprecedented scale and reliability.