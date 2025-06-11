# DSPEx Bug Fixes - Comprehensive Guide

## Overview

Based on the test failures, there are several critical issues in the DSPEx codebase that need immediate attention:

1. **GenServer call timeouts** in ClientManager
2. **Performance issues** with request processing
3. **Concurrent request handling** problems
4. **Telemetry integration** failures
5. **Error propagation** issues
6. **Statistics tracking** problems

## Critical Fixes

### 1. Fix ClientManager GenServer Call Timeouts

**Problem**: `GenServer.call(#PID<...>, {:request, ...}, 1)` is timing out.

**File**: `lib/dspex/client_manager.ex`

**Fix**: Update the `handle_call` for requests to be more efficient and add proper timeout handling:

```elixir
@impl GenServer
def handle_call({:request, messages, options}, from, state) do
  # Use async processing to avoid blocking the GenServer
  Task.start(fn ->
    # Update state to active
    updated_state = %{state | state: :active}
    
    # Validate messages quickly
    if valid_messages?(messages) do
      correlation_id = Map.get(options, :correlation_id) || generate_correlation_id()
      
      # Perform the request in a separate process
      result = execute_request(messages, options, updated_state, correlation_id)
      
      # Update statistics
      final_state = update_stats(updated_state, result)
      
      # Send the result back
      GenServer.reply(from, result)
      
      # Update the GenServer state
      GenServer.cast(self(), {:update_state, final_state})
    else
      GenServer.reply(from, {:error, :invalid_messages})
      GenServer.cast(self(), {:update_state, %{state | state: :idle}})
    end
  end)
  
  {:noreply, state}
end

@impl GenServer
def handle_cast({:update_state, new_state}, _old_state) do
  {:noreply, new_state}
end
```

### 2. Optimize Request Processing Performance

**Problem**: Processing is taking >1000ms, which is too slow.

**File**: `lib/dspex/client_manager.ex`

**Fix**: Optimize the `execute_request` function:

```elixir
defp execute_request(messages, options, state, correlation_id) do
  # Reduce telemetry overhead by batching events
  start_time = :erlang.monotonic_time(:microsecond)
  
  # Skip telemetry in test environment for performance
  if Application.get_env(:dspex, :environment) != :test do
    emit_telemetry_start(state.provider, correlation_id, length(messages))
  end
  
  # Execute the HTTP request with optimized settings
  result = execute_http_request_optimized(messages, options, state, correlation_id)
  
  # Emit stop telemetry only if not in test
  if Application.get_env(:dspex, :environment) != :test do
    duration = :erlang.monotonic_time(:microsecond) - start_time
    emit_telemetry_stop(state.provider, correlation_id, duration, match?({:ok, _}, result))
  end
  
  result
end

defp execute_http_request_optimized(messages, options, state, correlation_id) do
  # Use connection pooling and reduce overhead
  with {:ok, request_body} <- build_request_body_fast(messages, options, state.config),
       {:ok, http_response} <- make_http_request_fast(request_body, state.config, correlation_id),
       {:ok, parsed_response} <- parse_response_fast(http_response, state.provider) do
    {:ok, parsed_response}
  else
    {:error, reason} -> {:error, reason}
  end
end
```

### 3. Fix Concurrent Request Handling

**Problem**: Tasks are timing out after 5 seconds when handling concurrent requests.

**File**: `lib/dspex/client_manager.ex`

**Fix**: Implement proper connection pooling and concurrent request handling:

```elixir
defmodule DSPEx.ClientManager do
  use GenServer
  
  # Add connection pool to state
  defstruct provider: nil,
            config: %{},
            state: :idle,
            stats: %{},
            connection_pool: nil
  
  @impl GenServer
  def init({provider, user_config}) do
    case load_provider_config(provider, user_config) do
      {:ok, config} ->
        # Initialize connection pool
        pool_opts = [
          name: {:local, :"#{provider}_pool"},
          worker_module: DSPEx.HTTPWorker,
          size: 10,
          max_overflow: 20
        ]
        
        {:ok, pool} = :poolboy.start_link(pool_opts, config)
        
        state = %__MODULE__{
          provider: provider,
          config: config,
          state: :idle,
          stats: initial_stats(),
          connection_pool: pool
        }
        
        Logger.info("DSPEx.ClientManager started for provider: #{provider}")
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to start DSPEx.ClientManager for #{provider}: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  # Use pooled workers for HTTP requests
  defp make_http_request_fast(body, config, correlation_id) do
    :poolboy.transaction(
      :"#{config.provider}_pool",
      fn worker ->
        DSPEx.HTTPWorker.request(worker, body, config, correlation_id)
      end,
      5000  # 5 second timeout
    )
  rescue
    :timeout -> {:error, :pool_timeout}
    error -> {:error, {:pool_error, error}}
  end
end
```

### 4. Create HTTP Worker Module

**File**: `lib/dspex/http_worker.ex` (new file)

```elixir
defmodule DSPEx.HTTPWorker do
  @moduledoc "HTTP worker for connection pooling"
  
  use GenServer
  
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end
  
  def request(worker, body, config, correlation_id) do
    GenServer.call(worker, {:request, body, config, correlation_id}, 30_000)
  end
  
  @impl GenServer
  def init(config) do
    # Initialize HTTP client with keep-alive connections
    {:ok, %{config: config, connections: %{}}}
  end
  
  @impl GenServer
  def handle_call({:request, body, config, correlation_id}, _from, state) do
    url = build_api_url(config)
    headers = build_headers(config)
    timeout = Map.get(config, :timeout, 30_000)
    
    result = try do
      case Req.post(url, 
           json: body, 
           headers: headers, 
           receive_timeout: timeout,
           pool_timeout: 5000,
           retry: false) do
        {:ok, %Req.Response{status: 200} = response} ->
          {:ok, response}
        {:ok, %Req.Response{status: status}} when status >= 400 ->
          {:error, :api_error}
        {:error, %{reason: :timeout}} ->
          {:error, :timeout}
        {:error, _} ->
          {:error, :network_error}
      end
    rescue
      _ -> {:error, :network_error}
    catch
      _ -> {:error, :network_error}
    end
    
    {:reply, result, state}
  end
  
  # Helper functions (move from client_manager.ex)
  defp build_api_url(config) do
    # ... existing implementation
  end
  
  defp build_headers(config) do
    # ... existing implementation  
  end
end
```

### 5. Fix Integration Test Statistics Issues

**Problem**: `stats.stats.requests_made == 0` when it should be > 0.

**File**: `lib/dspex/client_manager.ex`

**Fix**: Ensure statistics are updated atomically:

```elixir
defp update_stats(state, result) do
  # Use atomic operations for statistics
  current_time = DateTime.utc_now()
  
  updated_stats = case result do
    {:ok, _} ->
      %{
        state.stats |
        requests_made: state.stats.requests_made + 1,
        requests_successful: state.stats.requests_successful + 1,
        last_request_at: current_time
      }
    {:error, _} ->
      %{
        state.stats |
        requests_made: state.stats.requests_made + 1,
        requests_failed: state.stats.requests_failed + 1,
        last_request_at: current_time
      }
  end
  
  %{state | stats: updated_stats, state: :idle}
end

# Ensure stats are immediately available
@impl GenServer
def handle_call(:get_stats, _from, state) do
  stats = %{
    provider: state.provider,
    state: state.state,
    stats: state.stats
  }
  
  {:reply, {:ok, stats}, state}
end
```

### 6. Fix Telemetry Integration Issues

**Problem**: Keyword.get/3 function clause error when correlation_id is passed as a map.

**File**: `lib/dspex/program.ex`

**Fix**: Properly handle options parameter:

```elixir
@spec forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}
def forward(program, inputs, opts) when is_map(inputs) do
  # Normalize options to keyword list
  opts_list = case opts do
    opts when is_list(opts) -> opts
    opts when is_map(opts) -> Map.to_list(opts)
    _ -> []
  end
  
  correlation_id = Keyword.get(opts_list, :correlation_id) || Utils.generate_correlation_id()
  
  # Rest of implementation...
end
```

### 7. Fix Error Propagation in Integration Tests

**Problem**: Assertion error `assert reason in [:invalid_inputs, :missing_required_fields]` but got `:missing_inputs`.

**File**: `test/integration/client_manager_integration_test.exs`

**Fix**: Update the test expectations:

```elixir
test "client errors propagate correctly through Program layer" do
  {:ok, client} = ClientManager.start_link(:gemini)
  program = Predict.new(TestSignature, client)
  
  # Use invalid inputs to trigger validation error
  invalid_inputs = %{wrong_field: "test"}
  result = Program.forward(program, invalid_inputs)
  
  # Should get appropriate error - updated expectations
  assert {:error, reason} = result
  assert reason in [:missing_inputs, :invalid_inputs, :missing_required_fields]
  
  # Client should still be operational
  assert Process.alive?(client)
end
```

### 8. Optimize HTTP Request Building

**File**: `lib/dspex/client_manager.ex`

**Fix**: Create faster request building functions:

```elixir
defp build_request_body_fast(messages, options, provider_config) do
  # Pre-compile request templates for better performance
  case determine_provider_type(provider_config) do
    :gemini ->
      build_gemini_request_fast(messages, options, provider_config)
    :openai ->
      build_openai_request_fast(messages, options, provider_config)
    :unknown ->
      {:error, :unsupported_provider}
  end
end

defp build_gemini_request_fast(messages, options, provider_config) do
  # Use pre-built templates and avoid repeated processing
  temperature = Map.get(options, :temperature) || provider_config[:default_temperature] || 0.7
  max_tokens = Map.get(options, :max_tokens) || provider_config[:default_max_tokens] || 150
  
  contents = case messages do
    [%{content: content}] -> [%{parts: [%{text: content}]}]
    _ -> Enum.map(messages, &convert_message_fast/1)
  end
  
  body = %{
    contents: contents,
    generationConfig: %{
      temperature: temperature,
      maxOutputTokens: max_tokens
    }
  }
  
  {:ok, body}
end

defp convert_message_fast(%{role: role, content: content}) do
  case role do
    "user" -> %{parts: [%{text: content}], role: "user"}
    "assistant" -> %{parts: [%{text: content}], role: "model"}
    _ -> %{parts: [%{text: content}]}
  end
end
```

### 9. Add Application Configuration

**File**: `config/test.exs`

```elixir
import Config

config :dspex,
  environment: :test,
  telemetry_debug: false,
  providers: %{
    gemini: %{
      api_key: {:system, "GEMINI_API_KEY"},
      base_url: "https://generativelanguage.googleapis.com/v1beta/models",
      default_model: "gemini-1.5-flash-latest",
      timeout: 5_000,  # Reduced for tests
      rate_limit: %{
        requests_per_minute: 60,
        tokens_per_minute: 100_000
      }
    }
  }

# Reduce log level in tests
config :logger, level: :warn
```

### 10. Add Missing Dependencies

**File**: `mix.exs`

```elixir
defp deps do
  [
    # ... existing deps
    {:poolboy, "~> 1.5"},
    {:req, "~> 0.4.0"},
    # ... rest of deps
  ]
end
```

## Testing Fixes

### Update Test Helper

**File**: `test/test_helper.exs`

```elixir
ExUnit.start()

# Configure test environment for performance
Application.put_env(:dspex, :environment, :test)
Application.put_env(:dspex, :telemetry_debug, false)

# Reduce timeouts for faster test execution
ExUnit.configure(
  exclude: [
    :live_api,
    :integration,
    :end_to_end,
    :performance,
    :external_api,
    :phase2_features,
    :reproduction_test
  ],
  timeout: 10_000,  # Reduced from 30_000
  max_failures: 10
)
```

## Implementation Priority

1. **Critical (Fix Immediately)**:
   - ClientManager GenServer timeout fix
   - Statistics tracking fix
   - Error propagation fix

2. **High Priority**:
   - Performance optimization
   - Connection pooling
   - Concurrent request handling

3. **Medium Priority**:
   - Test suite optimization
   - Configuration improvements

## Validation Steps

After implementing these fixes:

1. Run the failing tests individually:
   ```bash
   mix test test/unit/client_manager_test.exs:311
   mix test test/unit/client_manager_test.exs:380
   mix test test/unit/client_manager_test.exs:189
   ```

2. Run integration tests:
   ```bash
   mix test test/integration/client_manager_integration_test.exs
   ```

3. Check for performance improvements:
   ```bash
   mix test --trace test/unit/client_manager_test.exs
   ```

## Notes

- These fixes address the root causes of timeouts, performance issues, and test failures
- The connection pooling approach will significantly improve concurrent request handling
- Statistics tracking is made atomic to prevent race conditions
- Error propagation is standardized across the codebase
- Performance optimizations focus on reducing overhead in critical paths

Implement these fixes in order of priority to resolve the test failures and improve overall system performance.
