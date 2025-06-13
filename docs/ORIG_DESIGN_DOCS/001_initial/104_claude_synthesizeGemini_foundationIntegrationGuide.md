# DSPEx Foundation Integration Guide

## Overview

This document provides detailed guidance on integrating the `foundation` library into DSPEx's core architecture, building upon the established plans for porting DSPy to Elixir. The `foundation` library accelerates development by providing production-grade infrastructure components, allowing DSPEx to focus on its core value proposition: declarative language model programming.

## Foundation Library Components Integration

### 1. Infrastructure Management

The `foundation` library's `Infrastructure.ConnectionManager` and protection mechanisms replace much of the complexity we would have built manually:

```elixir
# DSPEx application startup with foundation integration
defmodule DSPEx.Application do
  use Application
  
  def start(_type, _args) do
    # Configure foundation infrastructure first
    Foundation.Config.put([:dspex], dspex_config())
    
    children = [
      # Foundation services start first
      {Foundation.ServiceRegistry, namespace: :dspex},
      {Foundation.Events, []},
      {Foundation.Telemetry, []},
      
      # DSPEx core services
      {DSPEx.Client.LM.Supervisor, []},
      {DSPEx.Cache.Manager, []},
      {DSPEx.Module.Registry, []},
      
      # Dynamic supervisors for request handling
      {DynamicSupervisor, name: DSPEx.Request.Supervisor, strategy: :one_for_one}
    ]
    
    opts = [strategy: :one_for_one, name: DSPEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  defp dspex_config do
    %{
      providers: %{
        openai: %{
          api_key: {:system, "OPENAI_API_KEY"},
          base_url: "https://api.openai.com/v1",
          default_model: "gpt-4",
          pool_size: 10,
          circuit_breaker: %{
            failure_threshold: 5,
            recovery_time: 30_000
          },
          rate_limiter: %{
            scale: 60_000,
            limit: 100
          }
        }
      }
    }
  end
end
```

### 2. Enhanced LM Client with Foundation

```elixir
defmodule DSPEx.Client.LM do
  use GenServer
  require Logger
  
  def start_link(opts) do
    provider = Keyword.fetch!(opts, :provider)
    GenServer.start_link(__MODULE__, opts, 
      name: Foundation.ServiceRegistry.via_tuple(:dspex, {:lm_client, provider}))
  end
  
  def request(provider, messages, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || Foundation.Utils.generate_correlation_id()
    
    # Use foundation's service registry for discovery
    case Foundation.ServiceRegistry.lookup(:dspex, {:lm_client, provider}) do
      {:ok, pid} ->
        GenServer.call(pid, {:request, messages, opts ++ [correlation_id: correlation_id]})
      {:error, :not_found} ->
        {:error, Foundation.Error.new(:provider_not_found, "LM provider #{provider} not configured")}
    end
  end
  
  def init(opts) do
    provider = opts[:provider]
    
    # Get configuration from foundation
    {:ok, config} = Foundation.Config.get([:dspex, :providers, provider])
    
    # Configure foundation infrastructure for this provider
    pool_name = :"lm_pool_#{provider}"
    protection_key = :"lm_protection_#{provider}"
    
    # Start connection pool
    Foundation.Infrastructure.ConnectionManager.start_pool(pool_name, %{
      worker_module: DSPEx.Client.LM.Worker,
      worker_args: [config: config],
      size: config.pool_size || 5,
      max_overflow: 3
    })
    
    # Configure circuit breaker and rate limiter
    Foundation.Infrastructure.configure_protection(protection_key, %{
      circuit_breaker: config.circuit_breaker,
      rate_limiter: config.rate_limiter
    })
    
    state = %{
      provider: provider,
      config: config,
      pool_name: pool_name,
      protection_key: protection_key
    }
    
    {:ok, state}
  end
  
  def handle_call({:request, messages, opts}, _from, state) do
    correlation_id = Keyword.get(opts, :correlation_id)
    
    # Create execution context for foundation
    context = Foundation.ErrorContext.new(__MODULE__, :handle_request,
      correlation_id: correlation_id,
      metadata: %{provider: state.provider, message_count: length(messages)}
    )
    
    result = Foundation.ErrorContext.with_context(context, fn ->
      # Define the work to be protected
      api_call_fn = fn worker_pid ->
        DSPEx.Client.LM.Worker.complete(worker_pid, messages, opts)
      end
      
      # Execute with full foundation protection
      Foundation.Infrastructure.execute_protected(
        state.protection_key,
        [
          connection_pool: state.pool_name,
          rate_limiter: {:api_calls, opts[:user_id] || :global}
        ],
        api_call_fn
      )
    end)
    
    # Emit telemetry
    case result do
      {:ok, completion} ->
        Foundation.Telemetry.emit_counter([:dspex, :lm, :request, :success], %{
          provider: state.provider,
          correlation_id: correlation_id
        })
        
      {:error, error} ->
        Foundation.Telemetry.emit_counter([:dspex, :lm, :request, :error], %{
          provider: state.provider,
          error_type: Foundation.Error.type(error),
          correlation_id: correlation_id
        })
    end
    
    {:reply, result, state}
  end
end
```

### 3. Foundation-Powered Module Execution

```elixir
defmodule DSPEx.Predict do
  @behaviour DSPEx.Program
  defstruct [:signature, :client, :adapter, :demos]
  
  @impl DSPEx.Program
  def forward(program, inputs, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || Foundation.Utils.generate_correlation_id()
    
    # Create comprehensive error context
    context = Foundation.ErrorContext.new(__MODULE__, :forward,
      correlation_id: correlation_id,
      metadata: %{
        signature: program.signature,
        client: program.client,
        input_fields: Map.keys(inputs),
        demo_count: length(program.demos || [])
      }
    )
    
    Foundation.ErrorContext.with_context(context, fn ->
      # Emit start event
      Foundation.Events.new_event(:module_execution_start, %{
        module_type: :predict,
        signature: program.signature,
        inputs: sanitize_inputs(inputs)
      }, correlation_id: correlation_id)
      |> Foundation.Events.store()
      
      # Execute the prediction pipeline
      result = execute_prediction_pipeline(program, inputs, correlation_id)
      
      # Emit completion event
      Foundation.Events.new_event(:module_execution_complete, %{
        module_type: :predict,
        signature: program.signature,
        success: match?({:ok, _}, result)
      }, correlation_id: correlation_id)
      |> Foundation.Events.store()
      
      result
    end)
  end
  
  defp execute_prediction_pipeline(program, inputs, correlation_id) do
    with {:ok, messages} <- format_messages(program, inputs),
         {:ok, completion} <- call_lm_client(program.client, messages, correlation_id),
         {:ok, parsed} <- parse_completion(program, completion) do
      
      prediction = %DSPEx.Prediction{
        signature: program.signature,
        inputs: inputs,
        outputs: parsed,
        correlation_id: correlation_id,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, prediction}
    end
  end
  
  defp call_lm_client(client, messages, correlation_id) do
    # This leverages the foundation-powered LM client
    DSPEx.Client.LM.request(client, messages, correlation_id: correlation_id)
  end
  
  # Sanitize inputs for event logging (remove PII, etc.)
  defp sanitize_inputs(inputs) do
    inputs
    |> Enum.map(fn {k, v} -> {k, String.slice(to_string(v), 0, 100)} end)
    |> Enum.into(%{})
  end
end
```

## Enhanced Error Handling Strategy

### 1. Foundation Error Types for DSPEx

```elixir
defmodule DSPEx.Error do
  @moduledoc """
  DSPEx-specific error types that integrate with Foundation's error system.
  """
  
  def signature_parse_error(details, context \\ %{}) do
    Foundation.Error.new(
      :signature_parse_error,
      "Failed to parse signature definition",
      context: Map.merge(context, %{details: details, module: __MODULE__})
    )
  end
  
  def adapter_format_error(reason, context \\ %{}) do
    Foundation.Error.new(
      :adapter_format_error,
      "Failed to format messages for LM",
      context: Map.merge(context, %{reason: reason, module: __MODULE__})
    )
  end
  
  def prediction_parse_error(completion, signature, context \\ %{}) do
    Foundation.Error.new(
      :prediction_parse_error,
      "Failed to parse LM completion into structured output",
      context: Map.merge(context, %{
        completion_preview: String.slice(completion, 0, 200),
        signature: signature,
        module: __MODULE__
      })
    )
  end
end
```

### 2. Comprehensive Telemetry Integration

```elixir
defmodule DSPEx.Telemetry do
  @moduledoc """
  Telemetry integration for DSPEx using Foundation's telemetry system.
  """
  
  def setup() do
    events = [
      [:dspex, :module, :execution, :start],
      [:dspex, :module, :execution, :stop],
      [:dspex, :module, :execution, :exception],
      [:dspex, :lm, :request, :start],
      [:dspex, :lm, :request, :stop],
      [:dspex, :signature, :parse, :start],
      [:dspex, :signature, :parse, :stop],
      [:dspex, :adapter, :format, :start],
      [:dspex, :adapter, :format, :stop]
    ]
    
    Foundation.Telemetry.attach_handlers(events)
    
    # Attach our custom handlers
    :telemetry.attach_many(
      "dspex-telemetry",
      events,
      &handle_telemetry_event/4,
      %{}
    )
  end
  
  def handle_telemetry_event([:dspex, :module, :execution, :stop], measurements, metadata, _config) do
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :module_execution_time],
      measurements.duration,
      %{
        module_type: metadata.module_type,
        signature: metadata.signature,
        success: metadata.success
      }
    )
    
    # Track token usage if available
    if token_usage = metadata[:token_usage] do
      Foundation.Telemetry.emit_gauge(
        [:dspex, :usage, :tokens_consumed],
        token_usage.total_tokens,
        %{
          provider: metadata.provider,
          model: metadata.model
        }
      )
    end
  end
  
  def handle_telemetry_event([:dspex, :lm, :request, :stop], measurements, metadata, _config) do
    Foundation.Telemetry.emit_counter(
      [:dspex, :lm, :requests_total],
      %{
        provider: metadata.provider,
        model: metadata.model,
        status: if(metadata.success, do: "success", else: "error")
      }
    )
    
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :lm_request_time],
      measurements.duration,
      %{provider: metadata.provider, model: metadata.model}
    )
  end
  
  def handle_telemetry_event(event, measurements, metadata, config) do
    # Fallback handler for unmatched events
    Logger.debug("Unhandled telemetry event: #{inspect(event)}")
  end
end
```

## Advanced Signature System with Foundation

### 1. Enhanced Signature Macro

```elixir
defmodule DSPEx.Signature do
  @moduledoc """
  Enhanced signature system with Foundation integration for better error handling
  and observability.
  """
  
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Logger
      
      # Parse the signature at compile time
      {signature_string, field_opts} = case opts do
        s when is_binary(s) -> {s, []}
        [signature: s] -> {s, Keyword.delete(opts, :signature)}
        [signature: s | rest] -> {s, rest}
        _ -> raise ArgumentError, "Invalid signature format"
      end
      
      # Use Foundation's error context for compilation errors
      correlation_id = Foundation.Utils.generate_correlation_id()
      context = Foundation.ErrorContext.new(DSPEx.Signature, :compile_signature,
        correlation_id: correlation_id,
        metadata: %{module: __MODULE__, signature_string: signature_string}
      )
      
      {input_fields, output_fields, instructions} = 
        Foundation.ErrorContext.with_context(context, fn ->
          DSPEx.Signature.Parser.parse(signature_string, __MODULE__)
        end)
      
      # Generate the struct and behaviour implementation
      DSPEx.Signature.Generator.generate_signature_module(
        __MODULE__,
        input_fields,
        output_fields,
        instructions,
        field_opts
      )
    end
  end
end

defmodule DSPEx.Signature.Parser do
  def parse(signature_string, calling_module) do
    # Enhanced parsing with better error messages
    case String.split(signature_string, "->", parts: 2) do
      [inputs_str, outputs_str] ->
        input_fields = parse_fields(String.trim(inputs_str), :input)
        output_fields = parse_fields(String.trim(outputs_str), :output)
        instructions = get_module_doc(calling_module)
        
        {input_fields, output_fields, instructions}
        
      _ ->
        raise DSPEx.Error.signature_parse_error(
          "Signature must contain '->' separator",
          %{signature_string: signature_string, calling_module: calling_module}
        )
    end
  end
  
  defp parse_fields(fields_str, field_type) do
    fields_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn field_name ->
      {String.to_atom(field_name), %{type: field_type, annotation: :string}}
    end)
    |> Enum.into(%{})
  end
  
  defp get_module_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => module_doc}, _, _} -> module_doc
      _ -> "No instructions provided"
    end
  end
end
```

## Configuration Management with Foundation

### 1. DSPEx Configuration Schema

```elixir
defmodule DSPEx.Config do
  @moduledoc """
  Configuration management for DSPEx using Foundation's config system.
  """
  
  def validate_config(config) do
    schema = %{
      providers: %{
        type: :map,
        required: true,
        properties: %{
          "*" => %{
            type: :map,
            properties: %{
              api_key: %{type: [:string, :tuple], required: true},
              base_url: %{type: :string, required: true},
              default_model: %{type: :string, required: true},
              pool_size: %{type: :integer, default: 5},
              circuit_breaker: %{
                type: :map,
                properties: %{
                  failure_threshold: %{type: :integer, default: 5},
                  recovery_time: %{type: :integer, default: 30_000}
                }
              },
              rate_limiter: %{
                type: :map,
                properties: %{
                  scale: %{type: :integer, default: 60_000},
                  limit: %{type: :integer, default: 100}
                }
              }
            }
          }
        }
      },
      cache: %{
        type: :map,
        properties: %{
          enabled: %{type: :boolean, default: true},
          memory_size: %{type: :integer, default: 1000},
          disk_path: %{type: :string, default: "./cache"}
        }
      }
    }
    
    Foundation.Config.validate(config, schema)
  end
  
  def get_provider_config(provider_name) do
    case Foundation.Config.get([:dspex, :providers, provider_name]) do
      {:ok, config} -> {:ok, config}
      {:error, _} -> {:error, Foundation.Error.new(
        :provider_not_configured,
        "Provider #{provider_name} is not configured",
        context: %{provider: provider_name}
      )}
    end
  end
end
```

## Testing Infrastructure

### 1. Foundation-Integrated Test Helpers

```elixir
defmodule DSPEx.Test.Support do
  @moduledoc """
  Test support utilities that integrate with Foundation's testing infrastructure.
  """
  
  def setup_test_environment do
    # Create isolated foundation environment for testing
    test_ref = make_ref()
    namespace = {:test, test_ref}
    
    # Start minimal foundation services for testing
    {:ok, _} = Foundation.ServiceRegistry.start_link(namespace: namespace)
    {:ok, _} = Foundation.Events.start_link([])
    {:ok, _} = Foundation.Telemetry.start_link([])
    
    # Configure test-specific settings
    Foundation.Config.put([:dspex], test_config())
    
    on_exit(fn ->
      Foundation.ServiceRegistry.cleanup_test_namespace(test_ref)
    end)
    
    %{namespace: namespace, test_ref: test_ref}
  end
  
  def mock_lm_client(responses) when is_list(responses) do
    # Create a mock LM client that returns predefined responses
    Agent.start_link(fn -> responses end, name: :mock_lm_responses)
    
    mock_client = fn _provider, _messages, _opts ->
      case Agent.get_and_update(:mock_lm_responses, fn 
        [response | rest] -> {response, rest}
        [] -> {{:error, :no_more_responses}, []}
      end) do
        {:error, reason} -> {:error, reason}
        response -> {:ok, response}
      end
    end
    
    # Override the LM client request function
    :meck.new(DSPEx.Client.LM, [:passthrough])
    :meck.expect(DSPEx.Client.LM, :request, mock_client)
    
    on_exit(fn ->
      :meck.unload(DSPEx.Client.LM)
      Agent.stop(:mock_lm_responses)
    end)
    
    :ok
  end
  
  defp test_config do
    %{
      providers: %{
        test: %{
          api_key: "test-key",
          base_url: "http://localhost:8080",
          default_model: "test-model",
          pool_size: 1,
          circuit_breaker: %{failure_threshold: 1, recovery_time: 100},
          rate_limiter: %{scale: 1000, limit: 10}
        }
      },
      cache: %{enabled: false}
    }
  end
end
```

## Implementation Checklist

### Phase 1: Foundation Integration (Immediate)
- [ ] Set up Foundation as a dependency
- [ ] Implement basic configuration schema
- [ ] Create Foundation-integrated LM client
- [ ] Set up telemetry and events
- [ ] Implement basic error handling

### Phase 2: Core Modules (Week 2-3)
- [ ] Enhanced signature system with Foundation error handling
- [ ] Basic Predict module with full observability
- [ ] Adapter layer with proper error propagation
- [ ] Test infrastructure with Foundation integration

### Phase 3: Advanced Features (Week 4-5)
- [ ] ChainOfThought module with state management
- [ ] Evaluation system with parallel execution
- [ ] Cache system integration
- [ ] Performance optimization and monitoring

This integration plan ensures that DSPEx leverages Foundation's capabilities from day one, providing production-grade infrastructure while maintaining focus on the core DSPy functionality. The result will be a more robust, observable, and maintainable system that exemplifies best practices in the Elixir ecosystem.
