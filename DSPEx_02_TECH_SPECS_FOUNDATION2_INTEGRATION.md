# DSPEx Technical Specifications: Foundation 2.0 Integration

## Document Series Overview

This comprehensive technical specification details the integration of DSPEx with Foundation 2.0, covering implementation details, API designs, and architectural patterns necessary for building the world's first distributed-native AI programming framework.

## Part 1: Enhanced Client Architecture

### 1.1 Foundation 2.0-Powered Client Design

The DSPEx client architecture leverages Foundation 2.0's distributed infrastructure capabilities while maintaining backward compatibility with existing APIs.

```elixir
defmodule DSPEx.Client do
  @moduledoc """
  Foundation 2.0-enhanced LLM client with distributed capabilities.
  
  Features:
  - Multi-provider support with unified API
  - Foundation 2.0 circuit breakers and rate limiting
  - Distributed connection pooling
  - Intelligent failover and load balancing
  """
  
  use GenServer
  require Logger
  
  @type provider :: :openai | :anthropic | :gemini | :cohere
  @type client_options :: %{
    provider: provider(),
    model: String.t(),
    api_key: String.t(),
    base_url: String.t(),
    foundation_config: map()
  }
  
  # Public API
  
  @doc """
  Start a new client instance with Foundation 2.0 infrastructure.
  """
  @spec start_link(client_options()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Make a prediction request with distributed resilience.
  """
  @spec request(GenServer.server(), list(map()), keyword()) :: 
    {:ok, map()} | {:error, Foundation.Error.t()}
  def request(client, messages, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || 
      Foundation.Utils.generate_correlation_id()
    
    Foundation.Context.with_correlation_id(correlation_id, fn ->
      GenServer.call(client, {:request, messages, opts}, :infinity)
    end)
  end
  
  # GenServer Implementation
  
  @impl true
  def init(opts) do
    provider = Keyword.fetch!(opts, :provider)
    config_key = Keyword.get(opts, :config_key, provider)
    
    # Initialize Foundation 2.0 infrastructure
    case setup_foundation_infrastructure(provider, config_key, opts) do
      {:ok, infrastructure} ->
        state = %{
          provider: provider,
          infrastructure: infrastructure,
          stats: %{requests: 0, errors: 0, last_request: nil}
        }
        
        # Register with Foundation 2.0 service registry
        :ok = Foundation.ServiceRegistry.register(
          :production,
          :"dspex_client_#{provider}",
          self(),
          %{provider: provider, capabilities: [:prediction, :streaming]}
        )
        
        {:ok, state}
        
      {:error, reason} ->
        {:stop, {:infrastructure_setup_failed, reason}}
    end
  end
  
  @impl true
  def handle_call({:request, messages, opts}, _from, state) do
    # Update request stats
    state = update_in(state, [:stats, :requests], &(&1 + 1))
    state = put_in(state, [:stats, :last_request], DateTime.utc_now())
    
    # Execute request with Foundation 2.0 protection
    result = execute_protected_request(state.infrastructure, messages, opts)
    
    # Update error stats if needed
    state = case result do
      {:error, _} -> update_in(state, [:stats, :errors], &(&1 + 1))
      _ -> state
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_info({:foundation_event, event}, state) do
    # Handle Foundation 2.0 events (topology changes, etc.)
    case event do
      {:topology_changed, new_topology} ->
        Logger.info("DSPEx Client adapting to topology: #{inspect(new_topology)}")
        {:noreply, state}
        
      {:cluster_scaled, %{nodes_added: added, nodes_removed: removed}} ->
        Logger.info("Cluster scaled: +#{length(added)} -#{length(removed)} nodes")
        {:noreply, state}
        
      _ ->
        {:noreply, state}
    end
  end
  
  # Private Implementation
  
  defp setup_foundation_infrastructure(provider, config_key, opts) do
    with {:ok, provider_config} <- get_provider_config(config_key),
         {:ok, pool_name} <- setup_connection_pool(provider, provider_config),
         {:ok, protection_key} <- setup_protection_mechanisms(provider, provider_config) do
      
      infrastructure = %{
        pool_name: pool_name,
        protection_key: protection_key,
        provider_config: provider_config
      }
      
      {:ok, infrastructure}
    end
  end
  
  defp get_provider_config(config_key) do
    case Foundation.Config.get([:dspex, :providers, config_key]) do
      {:ok, config} -> {:ok, config}
      {:error, _} -> {:error, :provider_not_configured}
    end
  end
  
  defp setup_connection_pool(provider, config) do
    pool_name = :"dspex_#{provider}_pool"
    
    pool_config = %{
      worker_module: DSPEx.Client.HttpWorker,
      worker_args: [
        provider: provider,
        api_key: config.api_key,
        base_url: config.base_url,
        timeout: config.timeout || 30_000
      ],
      size: config.pool_size || 10,
      max_overflow: config.max_overflow || 5
    }
    
    case Foundation.Infrastructure.ConnectionManager.start_pool(pool_name, pool_config) do
      :ok -> {:ok, pool_name}
      error -> error
    end
  end
  
  defp setup_protection_mechanisms(provider, config) do
    protection_key = :"dspex_#{provider}_protection"
    
    protection_config = %{
      circuit_breaker: %{
        failure_threshold: config.circuit_breaker.failure_threshold || 5,
        recovery_time: config.circuit_breaker.recovery_time || 30_000,
        trip_function: &circuit_breaker_should_trip?/1
      },
      rate_limiter: %{
        scale: config.rate_limit.window_ms || 60_000,
        limit: config.rate_limit.max_requests || 100,
        bucket_function: &rate_limit_bucket/1
      }
    }
    
    case Foundation.Infrastructure.configure_protection(protection_key, protection_config) do
      :ok -> {:ok, protection_key}
      error -> error
    end
  end
  
  defp execute_protected_request(infrastructure, messages, opts) do
    request_fn = fn ->
      Foundation.Infrastructure.ConnectionManager.execute_with_worker(
        infrastructure.pool_name,
        fn worker ->
          DSPEx.Client.HttpWorker.post(worker, build_request_payload(messages, opts))
        end
      )
    end
    
    Foundation.Infrastructure.execute_protected(
      infrastructure.protection_key,
      [
        connection_pool: infrastructure.pool_name,
        rate_limiter: {:api_calls, opts[:user_id] || :global},
        timeout: opts[:timeout] || 30_000
      ],
      request_fn
    )
  end
  
  defp build_request_payload(messages, opts) do
    %{
      model: opts[:model] || "default",
      messages: messages,
      temperature: opts[:temperature] || 0.7,
      max_tokens: opts[:max_tokens] || 150,
      stream: opts[:stream] || false
    }
  end
  
  defp circuit_breaker_should_trip?(%{error_rate: rate, consecutive_failures: failures}) do
    rate > 0.5 or failures > 3
  end
  
  defp rate_limit_bucket(context) do
    # Dynamic bucket assignment based on context
    case context do
      %{user_id: user_id} -> "user:#{user_id}"
      %{api_key: api_key} -> "api_key:#{String.slice(api_key, 0..8)}"
      _ -> "global"
    end
  end
end
```

### 1.2 HTTP Worker Implementation

```elixir
defmodule DSPEx.Client.HttpWorker do
  @moduledoc """
  HTTP worker for actual LLM API communication.
  """
  
  use GenServer
  
  @impl true
  def init(opts) do
    provider = Keyword.fetch!(opts, :provider)
    api_key = Keyword.fetch!(opts, :api_key)
    base_url = Keyword.fetch!(opts, :base_url)
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    # Initialize HTTP client (Req-based)
    client = Req.new(
      base_url: base_url,
      headers: build_auth_headers(provider, api_key),
      receive_timeout: timeout,
      retry: false  # Let Foundation handle retries
    )
    
    state = %{
      provider: provider,
      client: client,
      stats: %{requests: 0, total_time: 0}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:post, payload}, _from, state) do
    start_time = System.monotonic_time()
    
    # Execute HTTP request
    result = case state.provider do
      :openai -> post_openai(state.client, payload)
      :anthropic -> post_anthropic(state.client, payload)
      :gemini -> post_gemini(state.client, payload)
      _ -> {:error, :unsupported_provider}
    end
    
    # Update stats
    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    state = state
    |> update_in([:stats, :requests], &(&1 + 1))
    |> update_in([:stats, :total_time], &(&1 + duration))
    
    {:reply, result, state}
  end
  
  def post(worker, payload) do
    GenServer.call(worker, {:post, payload})
  end
  
  # Provider-specific implementations
  defp post_openai(client, payload) do
    case Req.post(client, url: "/chat/completions", json: payload) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        {:error, %Foundation.Error{
          type: :api_error,
          message: "OpenAI API error",
          details: %{status: status, body: body}
        }}
      {:error, error} ->
        {:error, %Foundation.Error{
          type: :network_error,
          message: "Network error",
          details: %{error: error}
        }}
    end
  end
  
  defp post_anthropic(client, payload) do
    # Transform payload for Anthropic format
    anthropic_payload = %{
      model: payload.model,
      max_tokens: payload.max_tokens,
      messages: payload.messages
    }
    
    case Req.post(client, url: "/messages", json: anthropic_payload) do
      {:ok, %{status: 200, body: body}} ->
        # Transform response back to standard format
        {:ok, transform_anthropic_response(body)}
      {:ok, %{status: status, body: body}} ->
        {:error, %Foundation.Error{
          type: :api_error,
          message: "Anthropic API error",
          details: %{status: status, body: body}
        }}
      {:error, error} ->
        {:error, %Foundation.Error{
          type: :network_error,
          message: "Network error",
          details: %{error: error}
        }}
    end
  end
  
  defp post_gemini(client, payload) do
    # Transform payload for Gemini format
    gemini_payload = %{
      contents: transform_messages_to_gemini(payload.messages),
      generationConfig: %{
        temperature: payload.temperature,
        maxOutputTokens: payload.max_tokens
      }
    }
    
    case Req.post(client, url: ":generateContent", json: gemini_payload) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, transform_gemini_response(body)}
      {:ok, %{status: status, body: body}} ->
        {:error, %Foundation.Error{
          type: :api_error,
          message: "Gemini API error",
          details: %{status: status, body: body}
        }}
      {:error, error} ->
        {:error, %Foundation.Error{
          type: :network_error,
          message: "Network error",
          details: %{error: error}
        }}
    end
  end
  
  defp build_auth_headers(:openai, api_key) do
    [{"authorization", "Bearer #{api_key}"}]
  end
  
  defp build_auth_headers(:anthropic, api_key) do
    [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]
  end
  
  defp build_auth_headers(:gemini, _api_key) do
    # Gemini uses query parameter authentication
    []
  end
  
  # Response transformation helpers
  defp transform_anthropic_response(body) do
    %{
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => body["content"] |> List.first() |> Map.get("text")
          }
        }
      ]
    }
  end
  
  defp transform_gemini_response(body) do
    content = body["candidates"]
    |> List.first()
    |> get_in(["content", "parts"])
    |> List.first()
    |> Map.get("text")
    
    %{
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => content
          }
        }
      ]
    }
  end
  
  defp transform_messages_to_gemini(messages) do
    Enum.map(messages, fn
      %{"role" => "system", "content" => content} ->
        %{"parts" => [%{"text" => content}], "role" => "user"}
      %{"role" => "user", "content" => content} ->
        %{"parts" => [%{"text" => content}], "role" => "user"}
      %{"role" => "assistant", "content" => content} ->
        %{"parts" => [%{"text" => content}], "role" => "model"}
    end)
  end
end
```

## Part 2: Distributed Evaluation Engine

### 2.1 Foundation 2.0-Enhanced Evaluation

```elixir
defmodule DSPEx.Evaluate do
  @moduledoc """
  Distributed evaluation engine using Foundation 2.0 capabilities.
  
  Features:
  - Cluster-aware workload distribution
  - Fault-tolerant evaluation with automatic recovery
  - Real-time progress tracking and metrics
  - Dynamic load balancing across nodes
  """
  
  alias Foundation.{Cluster, WorkDistribution, Context, Telemetry}
  
  @type evaluation_options :: %{
    max_concurrency: pos_integer(),
    timeout: timeout(),
    distribution_strategy: :round_robin | :capability_aware | :load_balanced,
    fault_tolerance: :none | :retry | :skip_failed,
    progress_callback: (map() -> :ok) | nil
  }
  
  @doc """
  Run distributed evaluation across Foundation 2.0 cluster.
  """
  @spec run_distributed(DSPEx.Program.t(), [DSPEx.Example.t()], function(), evaluation_options()) ::
    {:ok, %{score: float(), stats: map()}} | {:error, term()}
  def run_distributed(program, examples, metric_fn, opts \\ %{}) do
    correlation_id = Foundation.Utils.generate_correlation_id()
    
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
  
  @doc """
  Run local evaluation with Foundation 2.0 observability.
  """
  @spec run_local(DSPEx.Program.t(), [DSPEx.Example.t()], function(), evaluation_options()) ::
    {:ok, %{score: float(), stats: map()}} | {:error, term()}
  def run_local(program, examples, metric_fn, opts \\ %{}) do
    max_concurrency = Map.get(opts, :max_concurrency, 100)
    timeout = Map.get(opts, :timeout, :infinity)
    
    start_time = System.monotonic_time()
    
    results = examples
    |> Task.async_stream(
      fn example ->
        Context.propagate(fn ->
          evaluate_single_example(program, example, metric_fn)
        end)
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
  
  # Private Implementation
  
  defp do_run_distributed(program, examples, metric_fn, opts) do
    distribution_strategy = Map.get(opts, :distribution_strategy, :capability_aware)
    
    # Get active cluster nodes with capabilities
    nodes = Cluster.active_nodes_with_capabilities([:dspex_evaluation])
    
    if Enum.empty?(nodes) do
      # Fallback to local evaluation
      run_local(program, examples, metric_fn, opts)
    else
      # Distribute work across cluster
      distribute_evaluation_work(program, examples, metric_fn, nodes, opts)
    end
  end
  
  defp distribute_evaluation_work(program, examples, metric_fn, nodes, opts) do
    chunk_size = calculate_optimal_chunk_size(examples, nodes)
    
    examples
    |> Enum.chunk_every(chunk_size)
    |> Enum.with_index()
    |> Task.async_stream(fn {chunk, index} ->
      target_node = select_target_node(nodes, index, opts)
      
      Context.propagate(fn ->
        WorkDistribution.execute_on_node(target_node, fn ->
          evaluate_chunk_on_node(program, chunk, metric_fn, opts)
        end)
      end)
    end, timeout: :infinity)
    |> Enum.reduce({[], %{}}, fn
      {:ok, {:ok, chunk_result}}, {results, stats} ->
        {[chunk_result | results], merge_stats(stats, chunk_result.stats)}
      {:ok, {:error, error}}, {results, stats} ->
        # Handle chunk failure based on fault tolerance setting
        case Map.get(opts, :fault_tolerance, :retry) do
          :skip_failed -> {results, update_in(stats, [:failed_chunks], &((&1 || 0) + 1))}
          :retry -> {results, stats}  # TODO: Implement retry logic
          :none -> throw({:chunk_failed, error})
        end
      {:exit, reason}, {results, stats} ->
        {results, update_in(stats, [:node_failures], &((&1 || 0) + 1))}
    end)
    |> then(fn {chunk_results, global_stats} ->
      aggregate_distributed_results(chunk_results, global_stats)
    end)
  end
  
  defp evaluate_chunk_on_node(program, chunk, metric_fn, opts) do
    max_concurrency = Map.get(opts, :max_concurrency, 50)
    start_time = System.monotonic_time()
    
    results = chunk
    |> Task.async_stream(
      fn example ->
        evaluate_single_example(program, example, metric_fn)
      end,
      max_concurrency: max_concurrency,
      timeout: 30_000
    )
    |> Enum.to_list()
    
    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    {scores, errors} = Enum.reduce(results, {[], []}, fn
      {:ok, {:ok, score}}, {scores, errors} -> {[score | scores], errors}
      {:ok, {:error, error}}, {scores, errors} -> {scores, [error | errors]}
      {:exit, reason}, {scores, errors} -> {scores, [{:process_exit, reason} | errors]}
    end)
    
    {:ok, %{
      scores: scores,
      stats: %{
        node: node(),
        chunk_size: length(chunk),
        successful: length(scores),
        failed: length(errors),
        duration_ms: duration,
        errors: errors
      }
    }}
  end
  
  defp evaluate_single_example(program, example, metric_fn) do
    Telemetry.emit_span([:dspex, :evaluate, :example], %{
      program: program_name(program)
    }, fn ->
      with {:ok, prediction} <- DSPEx.Program.forward(program, example.inputs),
           score when is_number(score) <- metric_fn.(example, prediction) do
        {:ok, score}
      else
        {:error, reason} -> {:error, reason}
        other -> {:error, {:invalid_metric_result, other}}
      end
    end)
  end
  
  defp calculate_optimal_chunk_size(examples, nodes) do
    total_examples = length(examples)
    total_nodes = length(nodes)
    
    # Aim for 2-3 chunks per node for load balancing
    chunk_size = div(total_examples, total_nodes * 3)
    max(chunk_size, 1)
  end
  
  defp select_target_node(nodes, index, opts) do
    case Map.get(opts, :distribution_strategy, :round_robin) do
      :round_robin ->
        Enum.at(nodes, rem(index, length(nodes)))
      
      :capability_aware ->
        # Select node based on current load and capabilities
        Cluster.select_optimal_node(nodes, :dspex_evaluation)
      
      :load_balanced ->
        # Use Foundation's load balancing
        WorkDistribution.select_least_loaded_node(nodes)
    end
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
      average_score = Enum.sum(scores) / length(scores)
      
      {:ok, %{
        score: average_score,
        stats: %{
          total_examples: length(scores) + length(errors),
          successful: length(scores),
          failed: length(errors),
          duration_ms: duration,
          success_rate: length(scores) / (length(scores) + length(errors)),
          errors: errors
        }
      }}
    end
  end
  
  defp aggregate_distributed_results(chunk_results, global_stats) do
    all_scores = Enum.flat_map(chunk_results, & &1.scores)
    
    if Enum.empty?(all_scores) do
      {:error, :no_successful_evaluations}
    else
      average_score = Enum.sum(all_scores) / length(all_scores)
      
      total_stats = Enum.reduce(chunk_results, %{}, fn chunk_result, acc ->
        %{
          total_examples: (acc[:total_examples] || 0) + chunk_result.stats.chunk_size,
          successful: (acc[:successful] || 0) + chunk_result.stats.successful,
          failed: (acc[:failed] || 0) + chunk_result.stats.failed,
          total_duration_ms: (acc[:total_duration_ms] || 0) + chunk_result.stats.duration_ms,
          nodes_used: MapSet.put(acc[:nodes_used] || MapSet.new(), chunk_result.stats.node)
        }
      end)
      
      {:ok, %{
        score: average_score,
        stats: Map.merge(total_stats, global_stats)
      }}
    end
  end
  
  defp merge_stats(stats1, stats2) do
    Map.merge(stats1, stats2, fn
      _key, v1, v2 when is_number(v1) and is_number(v2) -> v1 + v2
      _key, v1, v2 when is_list(v1) and is_list(v2) -> v1 ++ v2
      _key, _v1, v2 -> v2
    end)
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

## Part 3: Distributed Teleprompter Architecture

### 3.1 Foundation 2.0-Enhanced Optimization

```elixir
defmodule DSPEx.Teleprompter.DistributedBootstrap do
  @moduledoc """
  Distributed BootstrapFewShot optimizer using Foundation 2.0.
  
  Features:
  - Cluster-wide optimization coordination
  - Distributed consensus on best demonstrations
  - Fault-tolerant optimization with automatic recovery
  - Real-time optimization progress tracking
  """
  
  use GenServer
  @behaviour DSPEx.Teleprompter
  
  alias Foundation.{DistributedState, Consensus, WorkDistribution, Context}
  
  defstruct [
    :student,
    :teacher, 
    :trainset,
    :metric_fn,
    :optimization_state,
    :consensus_group,
    demos: [],
    target_demos: 16,
    optimization_id: nil
  ]
  
  @type optimization_options :: %{
    target_demos: pos_integer(),
    quality_threshold: float(),
    max_iterations: pos_integer(),
    consensus_threshold: float(),
    distributed: boolean()
  }
  
  # Public API
  
  @doc """
  Compile a student program using distributed optimization.
  """
  @spec compile(DSPEx.Program.t(), DSPEx.Program.t(), [DSPEx.Example.t()], 
                function(), optimization_options()) ::
    {:ok, DSPEx.Program.t()} | {:error, term()}
  def compile(student, teacher, trainset, metric_fn, opts \\ %{}) do
    optimization_id = Foundation.Utils.generate_correlation_id()
    
    Context.with_correlation_id(optimization_id, fn ->
      if Map.get(opts, :distributed, true) and cluster_available?() do
        compile_distributed(student, teacher, trainset, metric_fn, opts)
      else
        compile_local(student, teacher, trainset, metric_fn, opts)
      end
    end)
  end
  
  # GenServer Implementation
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  @impl true
  def init(opts) do
    state = struct(__MODULE__, opts)
    {:ok, state}
  end
  
  @impl true
  def handle_call({:optimize_distributed, opts}, _from, state) do
    result = do_optimize_distributed(state, opts)
    {:reply, result, state}
  end
  
  @impl true
  def handle_cast({:consensus_update, update}, state) do
    # Handle consensus updates from other nodes
    updated_state = apply_consensus_update(state, update)
    {:noreply, updated_state}
  end
  
  # Private Implementation
  
  defp compile_distributed(student, teacher, trainset, metric_fn, opts) do
    optimization_id = Foundation.Utils.generate_correlation_id()
    
    # Create distributed optimization state
    {:ok, optimization_state} = DistributedState.create(
      {:dspex_optimization, optimization_id},
      %{
        student: student,
        teacher: teacher,
        trainset: trainset,
        metric_fn: metric_fn,
        demos: [],
        target_demos: Map.get(opts, :target_demos, 16),
        quality_threshold: Map.get(opts, :quality_threshold, 0.7),
        nodes_participating: Foundation.Cluster.active_nodes(),
        start_time: DateTime.utc_now()
      }
    )
    
    # Create consensus group for demo selection
    {:ok, consensus_group} = Consensus.create_group(
      {:dspex_demo_consensus, optimization_id},
      threshold: Map.get(opts, :consensus_threshold, 0.6)
    )
    
    # Distribute bootstrap work across cluster
    case bootstrap_examples_distributed(optimization_state, consensus_group) do
      {:ok, best_demos} ->
        # Create optimized student with consensus-selected demos
        optimized_student = update_program_demos(student, best_demos)
        {:ok, optimized_student}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp compile_local(student, teacher, trainset, metric_fn, opts) do
    target_demos = Map.get(opts, :target_demos, 16)
    quality_threshold = Map.get(opts, :quality_threshold, 0.7)
    
    # Bootstrap examples locally
    bootstrapped_demos = trainset
    |> Task.async_stream(fn example ->
      bootstrap_single_example(teacher, example, metric_fn, quality_threshold)
    end, max_concurrency: 20)
    |> Stream.filter(fn
      {:ok, {:ok, _demo}} -> true
      _ -> false
    end)
    |> Stream.map(fn {:ok, {:ok, demo}} -> demo end)
    |> Enum.take(target_demos)
    
    optimized_student = update_program_demos(student, bootstrapped_demos)
    {:ok, optimized_student}
  end
  
  defp bootstrap_examples_distributed(optimization_state, consensus_group) do
    # Get cluster nodes capable of running teacher models
    capable_nodes = Foundation.Cluster.active_nodes_with_capabilities([:dspex_teacher])
    
    # Distribute training examples across nodes
    distributed_results = WorkDistribution.distribute_workload(
      optimization_state.trainset,
      capable_nodes,
      fn examples_chunk, target_node ->
        WorkDistribution.execute_on_node(target_node, fn ->
          bootstrap_chunk_on_node(
            optimization_state.teacher,
            examples_chunk,
            optimization_state.metric_fn,
            optimization_state.quality_threshold
          )
        end)
      end
    )
    
    # Collect all bootstrapped demos from all nodes
    all_demos = distributed_results
    |> Enum.flat_map(fn
      {:ok, demos} when is_list(demos) -> demos
      _ -> []
    end)
    
    # Use consensus to select best demos
    select_best_demos_with_consensus(all_demos, consensus_group, optimization_state.target_demos)
  end
  
  defp bootstrap_chunk_on_node(teacher, examples_chunk, metric_fn, quality_threshold) do
    Foundation.Context.propagate(fn ->
      examples_chunk
      |> Task.async_stream(fn example ->
        bootstrap_single_example(teacher, example, metric_fn, quality_threshold)
      end, max_concurrency: 10)
      |> Enum.reduce([], fn
        {:ok, {:ok, demo}}, acc -> [demo | acc]
        _, acc -> acc
      end)
    end)
  end
  
  defp bootstrap_single_example(teacher, example, metric_fn, quality_threshold) do
    Foundation.Telemetry.emit_span([:dspex, :bootstrap, :example], %{}, fn ->
      case DSPEx.Program.forward(teacher, example.inputs) do
        {:ok, prediction} ->
          score = metric_fn.(example, prediction)
          
          if score >= quality_threshold do
            demo = %DSPEx.Example{
              inputs: example.inputs,
              outputs: prediction.outputs,
              metadata: %{
                bootstrap_score: score,
                teacher_used: teacher_name(teacher),
                node: node()
              }
            }
            {:ok, demo}
          else
            {:error, :quality_too_low}
          end
          
        {:error, reason} ->
          {:error, reason}
      end
    end)
  end
  
  defp select_best_demos_with_consensus(all_demos, consensus_group, target_count) do
    # Score and rank all demos
    scored_demos = all_demos
    |> Enum.map(fn demo ->
      {demo, demo.metadata.bootstrap_score}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    
    # Use consensus to agree on top demos
    consensus_proposals = scored_demos
    |> Enum.take(target_count * 2)  # Consider top 2x candidates
    |> Enum.chunk_every(div(target_count, 4))  # Create proposal chunks
    
    selected_demos = consensus_proposals
    |> Enum.reduce([], fn chunk, acc ->
      case Consensus.propose_and_decide(consensus_group, {:select_demos, chunk}) do
        {:ok, :accepted} ->
          chunk_demos = Enum.map(chunk, &elem(&1, 0))
          acc ++ chunk_demos
        _ ->
          acc
      end
    end)
    |> Enum.take(target_count)
    
    {:ok, selected_demos}
  end
  
  defp update_program_demos(program, demos) do
    # Update program with new demonstrations
    # This will depend on the specific program type
    case program do
      %DSPEx.Predict{} = predict ->
        %{predict | demos: demos}
      
      %DSPEx.ChainOfThought{predictor: predictor} = cot ->
        updated_predictor = %{predictor | demos: demos}
        %{cot | predictor: updated_predictor}
      
      other ->
        # For custom programs, try to set demos field if it exists
        if Map.has_key?(other, :demos) do
          %{other | demos: demos}
        else
          other
        end
    end
  end
  
  defp cluster_available?() do
    Foundation.Cluster.active_nodes() |> length() > 1
  end
  
  defp teacher_name(teacher) when is_struct(teacher) do
    teacher.__struct__
    |> Module.split()
    |> List.last()
  end
  defp teacher_name(_), do: "unknown"
end
```

## Part 4: Advanced Foundation 2.0 Integration Patterns

### 4.1 Process Ecosystem for Complex AI Programs

```elixir
defmodule DSPEx.ProcessEcosystem do
  @moduledoc """
  Foundation 2.0 process ecosystems for complex AI workflows.
  """
  
  alias Foundation.ProcessEcosystem
  
  @doc """
  Create a complete AI inference ecosystem.
  """
  def create_inference_ecosystem(program, inputs, opts \\ []) do
    ecosystem_id = Foundation.Utils.generate_correlation_id()
    
    ProcessEcosystem.spawn_ecosystem(
      {:dspex_inference, ecosystem_id},
      [
        # Main coordinator process
        {:coordinator, DSPEx.InferenceCoordinator, [
          program: program,
          inputs: inputs,
          correlation_id: ecosystem_id
        ]},
        
        # Input validation and preprocessing
        {:validator, DSPEx.InputValidator, [
          signature: program.signature,
          strict_mode: Keyword.get(opts, :strict_validation, false)
        ]},
        
        # Output post-processing and validation
        {:processor, DSPEx.OutputProcessor, [
          signature: program.signature,
          transformations: Keyword.get(opts, :transformations, [])
        ]},
        
        # Performance monitoring
        {:monitor, DSPEx.PerformanceMonitor, [
          metrics: [:latency, :token_usage, :cost],
          threshold_alerts: Keyword.get(opts, :alerts, [])
        ]},
        
        # Caching layer
        {:cache, DSPEx.CacheManager, [
          strategy: Keyword.get(opts, :cache_strategy, :lru),
          ttl: Keyword.get(opts, :cache_ttl, 3600)
        ]}
      ]
    )
  end
end

defmodule DSPEx.InferenceCoordinator do
  @moduledoc """
  Coordinates a complete inference workflow across ecosystem processes.
  """
  
  use GenServer
  alias Foundation.{Context, Telemetry}
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  @impl true
  def init(opts) do
    program = Keyword.fetch!(opts, :program)
    inputs = Keyword.fetch!(opts, :inputs)
    correlation_id = Keyword.fetch!(opts, :correlation_id)
    
    state = %{
      program: program,
      inputs: inputs,
      correlation_id: correlation_id,
      ecosystem_members: %{},
      status: :initializing
    }
    
    # Register with ecosystem
    send(self(), :register_with_ecosystem)
    
    {:ok, state}
  end
  
  @impl true
  def handle_info(:register_with_ecosystem, state) do
    # Discover other ecosystem members
    members = Foundation.ProcessEcosystem.get_ecosystem_members(
      {:dspex_inference, state.correlation_id}
    )
    
    state = %{state | ecosystem_members: members, status: :ready}
    
    # Start the inference workflow
    send(self(), :start_inference)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:start_inference, state) do
    Context.with_correlation_id(state.correlation_id, fn ->
      Telemetry.emit_span([:dspex, :ecosystem, :inference], %{
        program: program_name(state.program),
        correlation_id: state.correlation_id
      }, fn ->
        execute_inference_workflow(state)
      end)
    end)
    
    {:noreply, %{state | status: :completed}}
  end
  
  defp execute_inference_workflow(state) do
    with {:ok, validated_inputs} <- validate_inputs(state),
         {:ok, cached_result} <- check_cache(state, validated_inputs),
         {:ok, result} <- cached_result || execute_program(state, validated_inputs),
         {:ok, processed_result} <- process_output(state, result),
         :ok <- cache_result(state, validated_inputs, processed_result),
         :ok <- update_metrics(state, processed_result) do
      
      # Notify ecosystem of completion
      Foundation.ProcessEcosystem.broadcast_to_ecosystem(
        {:dspex_inference, state.correlation_id},
        {:inference_complete, processed_result}
      )
      
      {:ok, processed_result}
    else
      {:error, reason} ->
        # Handle and propagate errors
        Foundation.ProcessEcosystem.broadcast_to_ecosystem(
          {:dspex_inference, state.correlation_id},
          {:inference_failed, reason}
        )
        {:error, reason}
    end
  end
  
  defp validate_inputs(state) do
    case Map.get(state.ecosystem_members, :validator) do
      nil -> {:ok, state.inputs}
      validator_pid ->
        GenServer.call(validator_pid, {:validate, state.inputs})
    end
  end
  
  defp check_cache(state, inputs) do
    case Map.get(state.ecosystem_members, :cache) do
      nil -> {:ok, nil}
      cache_pid ->
        GenServer.call(cache_pid, {:get, cache_key(state.program, inputs)})
    end
  end
  
  defp execute_program(state, inputs) do
    DSPEx.Program.forward(state.program, inputs)
  end
  
  defp process_output(state, result) do
    case Map.get(state.ecosystem_members, :processor) do
      nil -> {:ok, result}
      processor_pid ->
        GenServer.call(processor_pid, {:process, result})
    end
  end
  
  defp cache_result(state, inputs, result) do
    case Map.get(state.ecosystem_members, :cache) do
      nil -> :ok
      cache_pid ->
        GenServer.cast(cache_pid, {:put, cache_key(state.program, inputs), result})
    end
  end
  
  defp update_metrics(state, result) do
    case Map.get(state.ecosystem_members, :monitor) do
      nil -> :ok
      monitor_pid ->
        GenServer.cast(monitor_pid, {:record_inference, result})
    end
  end
  
  defp cache_key(program, inputs) do
    :crypto.hash(:sha256, :erlang.term_to_binary({program, inputs}))
    |> Base.encode16()
  end
  
  defp program_name(program) when is_struct(program) do
    program.__struct__ |> Module.split() |> List.last()
  end
  defp program_name(_), do: "unknown"
end
```

This comprehensive technical specification provides the foundation for implementing DSPEx with full Foundation 2.0 integration, enabling unprecedented scale and reliability for distributed AI applications on the BEAM platform.
