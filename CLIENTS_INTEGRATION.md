# DSPEx Client Integration with ExLLM - Migration Strategy

## Overview

This document outlines the comprehensive migration strategy for DSPEx's client layer from the current custom implementation to [ExLLM](https://hexdocs.pm/ex_llm/ExLLM.html), a unified Elixir client library for Large Language Models. This migration will eliminate the `instructor_lite` dependency and provide a more robust, standardized client foundation. Additionally, this integration includes Nx support for client analytics, response processing, and embedding operations.

## Nx Integration for Client Analytics

### Enhanced Client Performance with Nx

```elixir
# lib/dspex/clients/nx_analytics.ex
defmodule DSPEx.Clients.NxAnalytics do
  @moduledoc """
  Nx-powered client analytics for performance monitoring and optimization.
  
  Provides numerical analysis of client performance metrics, response quality,
  and provider comparison using Nx tensor operations.
  """
  
  import Nx.Defn
  
  @doc """
  Analyze client response times and performance patterns.
  
  ## Examples
      
      iex> response_times = [120, 150, 89, 200, 95]
      iex> NxAnalytics.analyze_performance(response_times)
      %{mean_time: 130.8, p95: 200, stability_score: 0.78}
  """
  def analyze_performance(response_times) when is_list(response_times) do
    tensor = Nx.tensor(response_times)
    analyze_performance_impl(tensor)
  end
  
  defn analyze_performance_impl(times) do
    mean_time = Nx.mean(times)
    std_time = Nx.standard_deviation(times)
    min_time = Nx.reduce_min(times)
    max_time = Nx.reduce_max(times)
    
    # Calculate stability score (lower std = higher stability)
    stability_score = 1.0 / (1.0 + std_time / mean_time)
    
    %{
      mean_time: mean_time,
      std_time: std_time,
      min_time: min_time,
      max_time: max_time,
      stability_score: stability_score
    }
  end
  
  @doc """
  Compare performance across different providers using statistical analysis.
  """
  def compare_providers(provider_metrics) when is_map(provider_metrics) do
    providers = Map.keys(provider_metrics)
    
    comparisons = 
      for provider_a <- providers,
          provider_b <- providers,
          provider_a != provider_b do
        
        metrics_a = Map.get(provider_metrics, provider_a, [])
        metrics_b = Map.get(provider_metrics, provider_b, [])
        
        comparison = compare_provider_pair(metrics_a, metrics_b)
        {{provider_a, provider_b}, comparison}
      end
      |> Enum.into(%{})
    
    # Overall ranking based on performance
    rankings = calculate_provider_rankings(provider_metrics)
    
    %{
      pairwise_comparisons: comparisons,
      rankings: rankings,
      recommendation: recommend_best_provider(rankings)
    }
  end
  
  # Additional implementation details...
  # [Implementation continues as shown in previous examples]
end
```

### Nx Configuration for Client Operations

```elixir
# config/config.exs - Dependencies and Nx Configuration
config :dspex, :clients,
  # Dependencies
  client_library: :ex_llm,
  
  # Nx backend configuration
  nx_backend: {Nx.BinaryBackend, []},
  
  # Performance monitoring settings
  analytics: %{
    enabled: true,
    performance_tracking: true,
    embedding_analysis: true,
    health_monitoring: true,
    window_size: 100,
    anomaly_threshold: 0.4
  },
  
  # Provider comparison settings
  provider_comparison: %{
    enabled: true,
    min_samples: 20,
    confidence_threshold: 0.8,
    auto_switch: false  # Set to true for automatic provider switching
  },
  
  # Embedding processing
  embeddings: %{
    similarity_threshold: 0.7,
    dimension_validation: true,
    normalization: :l2
  }
```

## Current Client Architecture Analysis

### ✅ Current Implementation Strengths

#### 1. DSPEx.Client (Core Module)
**Location**: `lib/dspex/client.ex` (808 lines)
**Features**:
- SIMBA stability enhancements
- Response format normalization 
- Telemetry integration with Foundation
- Test mode behavior management
- Circuit breaker patterns
- Error categorization

**Key Capabilities**:
```elixir
@type response :: %{choices: [%{message: message()}]}
@type error_reason :: :timeout | :network_error | :invalid_response | 
                      :api_error | :circuit_open | :rate_limited | 
                      :invalid_messages | :provider_not_configured | 
                      :unsupported_provider | :unexpected_result
```

#### 2. DSPEx.ClientManager (GenServer)
**Location**: `lib/dspex/client_manager.ex` (787 lines)
**Features**:
- Persistent stateful connections
- OTP supervision integration
- Client statistics tracking
- Connection pooling foundation
- Process-based isolation

**State Management**:
```elixir
@type client_state :: :idle | :active | :throttled | :circuit_open
@type client_stats :: %{
  requests_made: non_neg_integer(),
  requests_successful: non_neg_integer(),
  requests_failed: non_neg_integer(),
  last_request_at: DateTime.t() | nil,
  circuit_failures: non_neg_integer()
}
```

### ❌ Current Limitations & Problems

#### 1. Provider Support Gaps
- **Limited providers**: Only OpenAI, Gemini, basic HTTP
- **Inconsistent APIs**: Different providers handled differently
- **Configuration complexity**: Custom config management for each provider

#### 2. InstructorLite Dependency Issues
**Files to Remove**:
- `lib/dspex/adapters/instructor_lite_gemini.ex` (242 lines)
- `lib/dspex/predict_structured.ex` (partial - structured output logic)
- Mix dependency: `{:instructor_lite, "~> 0.3.0"}`

**Problems**:
- **Single provider limitation**: Only works with Gemini
- **Maintenance burden**: Custom adapter implementation
- **Limited schema support**: Basic JSON schema generation
- **Error handling complexity**: Custom error translation

#### 3. Testing Complexity
- **Custom mock system**: `DSPEx.MockClientManager`
- **Provider-specific mocking**: Different mock strategies
- **Scattered test utilities**: Mock helpers spread across files

## ExLLM Integration Benefits

### 🚀 ExLLM Advantages

Based on [ExLLM documentation](https://hexdocs.pm/ex_llm/ExLLM.html):

#### 1. Unified Provider Support
**Supported Providers** (12+ providers):
- `:anthropic` - Claude models
- `:openai` - GPT models  
- `:groq` - Fast inference
- `:lmstudio` - Local models via LM Studio
- `:mistral` - Mistral AI models
- `:perplexity` - Search-augmented models
- `:openrouter` - 300+ models from multiple providers
- `:ollama` - Local models
- `:bedrock` - AWS Bedrock (multiple providers)
- `:gemini` - Google Gemini models
- `:xai` - X.AI Grok models
- `:bumblebee` - Local models via Bumblebee
- `:mock` - Built-in testing support

#### 2. Advanced Features
- **Streaming Support**: Built-in streaming with error recovery
- **Function Calling**: Unified interface for tool use
- **Model Discovery**: Query and compare model capabilities
- **Automatic Retries**: Exponential backoff with provider-specific policies
- **Cost Tracking**: Automatic usage and cost calculation
- **Context Management**: Automatic message truncation
- **Session Management**: Conversation state tracking
- **Structured Outputs**: Schema validation via instructor integration
- **No Process Dependencies**: Pure functional core

#### 3. Configuration Flexibility
```elixir
# Environment variables (automatic)
export ANTHROPIC_API_KEY="api-..."
export OPENAI_API_KEY="sk-..."

# Static configuration
config = %{
  anthropic: %{api_key: "api-...", model: "claude-3-5-sonnet-20241022"},
  openai: %{api_key: "sk-...", model: "gpt-4"},
  openrouter: %{api_key: "sk-or-...", model: "openai/gpt-4o"}
}

# Custom configuration provider
defmodule MyConfigProvider do
  @behaviour ExLLM.Infrastructure.ConfigProvider
  def get([:anthropic, :api_key]), do: MyApp.get_secret("anthropic_key")
  def get(_), do: nil
end
```

#### 4. Built-in Testing
```elixir
# Mock provider included
{:ok, response} = ExLLM.chat(:mock, messages)

# Check if configured
if ExLLM.configured?(:anthropic) do
  {:ok, response} = ExLLM.chat(:anthropic, messages)
end
```

## Migration Strategy

### Phase 1: Dependency Management (Week 1)

#### 1.1 Update mix.exs Dependencies
```elixir
# REMOVE
{:instructor_lite, "~> 0.3.0"},

# ADD  
{:ex_llm, "~> 0.8.1"},        # Unified LLM client library
{:nx, "~> 0.6"},              # Numerical computing for analytics and embeddings
```

#### 1.2 Remove InstructorLite Files
**Files to Delete**:
1. `lib/dspex/adapters/instructor_lite_gemini.ex`
2. Update `lib/dspex/predict_structured.ex` to remove InstructorLite logic

#### 1.3 Update Application Configuration
```elixir
# config/config.exs
config :dspex,
  # Remove old client configuration
  client_provider: ExLLM,  # New provider
  default_model_config: %{
    anthropic: %{model: "claude-3-5-sonnet-20241022"},
    openai: %{model: "gpt-4"},
    gemini: %{model: "gemini-pro"}
  }
```

### Phase 2: Client Behaviour Implementation (Week 1)

#### 2.1 Define DSPEx.Client Behaviour
```elixir
# lib/dspex/client.ex - Add behaviour definition
defmodule DSPEx.Client do
  @type message :: %{role: String.t(), content: String.t()}
  @type request_options :: %{
    optional(:provider) => atom(),
    optional(:model) => String.t(),
    optional(:temperature) => float(),
    optional(:max_tokens) => pos_integer(),
    optional(:correlation_id) => String.t(),
    optional(:timeout) => pos_integer()
  }
  @type response :: %{choices: [%{message: message()}]}
  @type error_reason :: :timeout | :network_error | :invalid_response | 
                        :api_error | :circuit_open | :rate_limited | 
                        :invalid_messages | :provider_not_configured | 
                        :unsupported_provider | :unexpected_result

  @callback request(messages :: [message()]) :: 
    {:ok, response()} | {:error, error_reason()}
  @callback request(messages :: [message()], opts :: request_options()) :: 
    {:ok, response()} | {:error, error_reason()}
  @callback request(client_id :: atom(), messages :: [message()], opts :: request_options()) :: 
    {:ok, response()} | {:error, error_reason()}

  # Keep existing functions as default implementation
end
```

#### 2.2 Create ExLLM Adapter
```elixir
# lib/dspex/clients/ex_llm_client.ex
defmodule DSPEx.Clients.ExLLMClient do
  @moduledoc """
  ExLLM-based client implementation with DSPEx compatibility.
  
  Provides a DSPEx.Client behaviour implementation using ExLLM as the
  underlying provider, with response format normalization and error mapping.
  """
  
  @behaviour DSPEx.Client
  
  require Logger
  
  alias DSPEx.Services.ConfigManager
  
  @impl DSPEx.Client
  def request(messages) do
    request(messages, %{})
  end
  
  @impl DSPEx.Client  
  def request(messages, options) do
    request(:default, messages, options)
  end
  
  @impl DSPEx.Client
  def request(client_id, messages, options) do
    # Extract provider and configuration
    provider = resolve_provider(client_id, options)
    
    # Convert DSPEx options to ExLLM options
    ex_llm_options = convert_options(options)
    
    # Add correlation tracking
    correlation_id = Map.get(options, :correlation_id) || generate_correlation_id()
    
    # Emit telemetry start
    start_time = System.monotonic_time()
    emit_telemetry_start(provider, correlation_id, messages, options)
    
    # Execute ExLLM request with error mapping
    result = case ExLLM.configured?(provider) do
      true ->
        execute_ex_llm_request(provider, messages, ex_llm_options)
      false ->
        {:error, :provider_not_configured}
    end
    
    # Emit telemetry stop
    duration = System.monotonic_time() - start_time
    emit_telemetry_stop(provider, correlation_id, result, duration)
    
    result
  end
  
  # Private functions
  
  defp execute_ex_llm_request(provider, messages, options) do
    case ExLLM.chat(provider, messages, options) do
      {:ok, %ExLLM.Types.ChatResponse{} = response} ->
        # Normalize ExLLM response to DSPEx format
        {:ok, normalize_ex_llm_response(response)}
      
      {:error, reason} ->
        # Map ExLLM errors to DSPEx error reasons
        {:error, map_ex_llm_error(reason)}
    end
  end
  
  defp normalize_ex_llm_response(%ExLLM.Types.ChatResponse{content: content, role: role}) do
    %{
      choices: [
        %{
          message: %{
            role: role || "assistant",
            content: content
          }
        }
      ]
    }
  end
  
  defp convert_options(dspex_options) do
    # Convert DSPEx options to ExLLM format
    dspex_options
    |> Map.take([:model, :temperature, :max_tokens, :timeout])
    |> Enum.into([])
  end
  
  defp map_ex_llm_error(:timeout), do: :timeout
  defp map_ex_llm_error(:network_error), do: :network_error
  defp map_ex_llm_error(:invalid_response), do: :invalid_response
  defp map_ex_llm_error(:api_error), do: :api_error
  defp map_ex_llm_error(_), do: :unexpected_result
  
  defp resolve_provider(client_id, options) do
    cond do
      provider = Map.get(options, :provider) -> provider
      client_id != :default -> client_id
      true -> Application.get_env(:dspex, :default_provider, :openai)
    end
  end
  
  defp generate_correlation_id do
    "exllm-#{System.unique_integer([:positive])}"
  end
  
  defp emit_telemetry_start(provider, correlation_id, messages, options) do
    :telemetry.execute(
      [:dspex, :client, :request, :start],
      %{system_time: System.system_time()},
      %{
        provider: provider,
        correlation_id: correlation_id,
        message_count: length(messages),
        temperature: Map.get(options, :temperature),
        client_type: :ex_llm
      }
    )
  end
  
  defp emit_telemetry_stop(provider, correlation_id, result, duration) do
    success = match?({:ok, _}, result)
    
    :telemetry.execute(
      [:dspex, :client, :request, :stop],
      %{duration: duration, success: success},
      %{
        provider: provider,
        correlation_id: correlation_id,
        client_type: :ex_llm
      }
    )
  end
end
```

### Phase 3: Enhanced Client Manager (Week 2)

#### 3.1 Update ClientManager for ExLLM
```elixir
# lib/dspex/client_manager.ex - Enhanced with ExLLM
defmodule DSPEx.ClientManager do
  use GenServer
  
  @behaviour DSPEx.Client
  
  # Add ExLLM session management
  defstruct [
    :provider,
    :config,
    :state,
    :stats,
    :ex_llm_session  # New: ExLLM session for conversation tracking
  ]
  
  @impl DSPEx.Client
  def request(client_pid, messages, options) when is_pid(client_pid) do
    GenServer.call(client_pid, {:request, messages, options}, get_timeout(options))
  end
  
  def request(messages, options) do
    # Use ExLLM directly for stateless requests
    DSPEx.Clients.ExLLMClient.request(messages, options)
  end
  
  def request(client_id, messages, options) do
    DSPEx.Clients.ExLLMClient.request(client_id, messages, options)
  end
  
  # Enhanced session management with ExLLM
  def start_session(provider, opts \\ []) do
    GenServer.start_link(__MODULE__, {provider, opts})
  end
  
  def chat_with_session(client_pid, content, options \\ []) do
    GenServer.call(client_pid, {:session_chat, content, options})
  end
  
  def get_session_history(client_pid, limit \\ nil) do
    GenServer.call(client_pid, {:get_session_history, limit})
  end
  
  # GenServer callbacks with ExLLM integration
  @impl GenServer
  def init({provider, config}) do
    # Create ExLLM session
    session_opts = [
      provider: provider,
      model: get_model_config(provider, config)
    ]
    
    case ExLLM.new_session(provider, session_opts) do
      {:ok, ex_llm_session} ->
        state = %__MODULE__{
          provider: provider,
          config: config,
          state: :idle,
          stats: initial_stats(),
          ex_llm_session: ex_llm_session
        }
        {:ok, state}
      
      {:error, reason} ->
        {:stop, {:failed_to_create_session, reason}}
    end
  end
  
  @impl GenServer
  def handle_call({:session_chat, content, options}, _from, state) do
    # Use ExLLM session for conversation tracking
    case ExLLM.chat_with_session(state.ex_llm_session, content, options) do
      {:ok, response} ->
        # Update stats and normalize response
        updated_state = update_stats(state, :success)
        normalized_response = normalize_session_response(response)
        {:reply, {:ok, normalized_response}, updated_state}
      
      {:error, reason} ->
        updated_state = update_stats(state, :failure)
        {:reply, {:error, map_ex_llm_error(reason)}, updated_state}
    end
  end
  
  @impl GenServer  
  def handle_call({:get_session_history, limit}, _from, state) do
    messages = ExLLM.get_session_messages(state.ex_llm_session, limit)
    {:reply, {:ok, messages}, state}
  end
  
  # Helper functions
  defp normalize_session_response(response) do
    # Convert ExLLM session response to DSPEx format
    %{
      choices: [
        %{
          message: %{
            role: "assistant",
            content: response.content
          }
        }
      ],
      session_stats: %{
        total_tokens: response.usage.total_tokens || 0,
        prompt_tokens: response.usage.prompt_tokens || 0,
        completion_tokens: response.usage.completion_tokens || 0
      }
    }
  end
end
```

### Phase 4: Structured Output Migration (Week 2-3)

#### 4.1 Replace InstructorLite with ExLLM Structured Outputs
```elixir
# lib/dspex/adapters/ex_llm_structured.ex
defmodule DSPEx.Adapters.ExLLMStructured do
  @moduledoc """
  DSPEx adapter using ExLLM's built-in structured output capabilities.
  
  Replaces the InstructorLite integration with ExLLM's native structured
  output support, providing better performance and broader provider support.
  """
  
  @behaviour DSPEx.Adapter
  
  @impl DSPEx.Adapter
  def format_messages(signature, inputs) do
    # Build prompt with schema instructions
    with {:ok, prompt} <- build_structured_prompt(signature, inputs),
         {:ok, schema} <- generate_json_schema(signature) do
      
      messages = [%{role: "user", content: prompt}]
      
      # Add structured output metadata
      metadata = %{
        json_schema: schema,
        output_fields: signature.output_fields(),
        signature_type: :structured
      }
      
      {:ok, {messages, metadata}}
    end
  end
  
  @impl DSPEx.Adapter
  def parse_response(signature, {response, metadata}) do
    case Map.get(metadata, :signature_type) do
      :structured ->
        parse_structured_response(signature, response, metadata)
      _ ->
        parse_standard_response(signature, response)
    end
  end
  
  # Make structured request using ExLLM
  def request_structured(provider, signature, inputs, options \\ []) do
    with {:ok, {messages, metadata}} <- format_messages(signature, inputs),
         {:ok, ex_llm_options} <- prepare_structured_options(metadata, options),
         {:ok, response} <- ExLLM.chat(provider, messages, ex_llm_options) do
      parse_response(signature, {response, metadata})
    end
  end
  
  # Private functions
  
  defp build_structured_prompt(signature, inputs) do
    instructions = signature.instructions()
    input_text = format_inputs(signature, inputs)
    schema_text = format_schema_instructions(signature)
    
    prompt = """
    #{instructions}
    
    Input:
    #{input_text}
    
    Please respond with a valid JSON object matching this schema:
    #{schema_text}
    
    Ensure your response is valid JSON and includes all required fields.
    """
    
    {:ok, prompt}
  end
  
  defp generate_json_schema(signature) do
    output_fields = signature.output_fields()
    
    properties = 
      output_fields
      |> Enum.map(fn field -> {to_string(field), infer_field_schema(field)} end)
      |> Enum.into(%{})
    
    schema = %{
      type: "object",
      required: Enum.map(output_fields, &to_string/1),
      properties: properties,
      additionalProperties: false
    }
    
    {:ok, schema}
  end
  
  defp infer_field_schema(:confidence), do: %{type: "string", enum: ["low", "medium", "high"]}
  defp infer_field_schema(:reasoning), do: %{type: "string", description: "Step-by-step reasoning"}
  defp infer_field_schema(:score), do: %{type: "number", minimum: 0, maximum: 1}
  defp infer_field_schema(:answer), do: %{type: "string", description: "The main answer"}
  defp infer_field_schema(_), do: %{type: "string"}
  
  defp prepare_structured_options(metadata, options) do
    # ExLLM structured output options
    ex_llm_options = options
    |> Keyword.put(:response_format, %{type: "json_object"})
    |> Keyword.put(:json_schema, metadata.json_schema)
    
    {:ok, ex_llm_options}
  end
  
  defp parse_structured_response(signature, response, _metadata) do
    case response.content do
      content when is_binary(content) ->
        case Jason.decode(content) do
          {:ok, json_data} when is_map(json_data) ->
            # Convert string keys to atom keys for consistency
            atom_data = for {k, v} <- json_data, into: %{}, do: {String.to_existing_atom(k), v}
            validate_structured_output(signature, atom_data)
          
          {:error, _} ->
            {:error, :invalid_json_response}
        end
      
      _ ->
        {:error, :missing_content}
    end
  end
  
  defp validate_structured_output(signature, data) do
    output_fields = signature.output_fields()
    
    missing_fields = output_fields -- Map.keys(data)
    
    case missing_fields do
      [] -> {:ok, data}
      _ -> {:error, {:missing_fields, missing_fields}}
    end
  end
end
```

#### 4.2 Update Predict Structured
```elixir
# lib/dspex/predict_structured.ex - Remove InstructorLite, use ExLLM
defmodule DSPEx.PredictStructured do
  @moduledoc """
  Structured prediction using ExLLM's native structured output capabilities.
  
  Provides guaranteed JSON schema compliance using ExLLM's built-in
  structured output support across multiple providers.
  """
  
  @behaviour DSPEx.Program
  
  defstruct [
    :signature,
    :provider, 
    :adapter,
    :model,
    :temperature,
    :max_tokens,
    :demonstrations
  ]
  
  def new(signature, provider, opts \\ []) do
    %__MODULE__{
      signature: signature,
      provider: provider,
      adapter: DSPEx.Adapters.ExLLMStructured,
      model: Keyword.get(opts, :model),
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens, 1000),
      demonstrations: Keyword.get(opts, :demonstrations, [])
    }
  end
  
  @impl DSPEx.Program
  def forward(program, inputs, opts \\ []) do
    # Use ExLLM structured adapter
    request_options = [
      model: program.model,
      temperature: program.temperature,
      max_tokens: program.max_tokens
    ] |> Keyword.merge(opts)
    
    DSPEx.Adapters.ExLLMStructured.request_structured(
      program.provider,
      program.signature,
      inputs,
      request_options
    )
  end
end
```

### Phase 5: Testing Infrastructure (Week 3)

#### 5.1 Update Mock Infrastructure
```elixir
# test/support/ex_llm_mocks.ex
defmodule DSPEx.ExLLMMocks do
  @moduledoc """
  Mock support for ExLLM integration testing.
  """
  
  import Mox
  
  def setup_ex_llm_mock(provider \\ :openai, responses \\ []) do
    # Mock ExLLM.chat/3
    expect(ExLLM.Mock, :chat, fn ^provider, _messages, _opts ->
      response = get_mock_response(responses)
      {:ok, %ExLLM.Types.ChatResponse{
        content: response,
        role: "assistant",
        usage: %{total_tokens: 100, prompt_tokens: 50, completion_tokens: 50}
      }}
    end)
    
    # Mock ExLLM.configured?/1
    expect(ExLLM.Mock, :configured?, fn ^provider -> true end)
  end
  
  def setup_ex_llm_session_mock(provider \\ :openai) do
    session = %ExLLM.Types.Session{
      provider: provider,
      messages: [],
      metadata: %{}
    }
    
    expect(ExLLM.Mock, :new_session, fn ^provider, _opts ->
      {:ok, session}
    end)
    
    expect(ExLLM.Mock, :chat_with_session, fn _session, content, _opts ->
      {:ok, %ExLLM.Types.ChatResponse{
        content: "Mock response to: #{content}",
        role: "assistant",
        usage: %{total_tokens: 75}
      }}
    end)
  end
  
  def setup_structured_output_mock(json_response) do
    expect(ExLLM.Mock, :chat, fn _provider, _messages, opts ->
      # Check if structured output is requested
      case Keyword.get(opts, :response_format) do
        %{type: "json_object"} ->
          {:ok, %ExLLM.Types.ChatResponse{
            content: Jason.encode!(json_response),
            role: "assistant"
          }}
        
        _ ->
          {:ok, %ExLLM.Types.ChatResponse{
            content: "Standard response",
            role: "assistant"
          }}
      end
    end)
  end
  
  defp get_mock_response([]), do: "Default mock response"
  defp get_mock_response([response | _]), do: response
end
```

#### 5.2 Update Behaviour Mocks
```elixir
# test/support/behaviour_mocks.exs - Update for ExLLM
defmodule DSPEx.BehaviourMocks do
  import Mox
  
  def setup_ex_llm_client_mock(provider \\ :openai) do
    expect(DSPEx.MockClient, :request, fn messages, opts ->
      # Simulate ExLLM client behavior
      content = generate_contextual_response(messages)
      
      {:ok, %{
        choices: [
          %{
            message: %{
              role: "assistant", 
              content: content
            }
          }
        ]
      }}
    end)
  end
  
  def setup_structured_client_mock(json_output) do
    expect(DSPEx.MockClient, :request, fn _messages, opts ->
      # Check if structured output is expected
      case Map.get(opts, :response_format) do
        %{type: "json_object"} ->
          {:ok, %{
            choices: [
              %{
                message: %{
                  role: "assistant",
                  content: Jason.encode!(json_output)
                }
              }
            ]
          }}
        
        _ ->
          setup_ex_llm_client_mock()
      end
    end)
  end
  
  defp generate_contextual_response(messages) do
    last_message = List.last(messages)
    content = Map.get(last_message, :content, "")
    
    cond do
      String.contains?(content, "JSON") -> ~s({"answer": "mock", "confidence": "high"})
      String.contains?(content, "structured") -> ~s({"result": "structured response"})
      String.contains?(content, "2+2") -> "4"
      true -> "Mock response for: #{String.slice(content, 0, 30)}"
    end
  end
end
```

### Phase 6: Configuration & Environment (Week 3-4)

#### 6.1 Update Application Configuration
```elixir
# config/config.exs
config :dspex,
  # Client configuration
  client_provider: DSPEx.Clients.ExLLMClient,
  default_provider: :openai,
  
  # ExLLM default configuration
  ex_llm_config: %{
    anthropic: %{model: "claude-3-5-sonnet-20241022"},
    openai: %{model: "gpt-4"},
    gemini: %{model: "gemini-pro"},
    groq: %{model: "llama2-70b-4096"},
    ollama: %{model: "llama2", base_url: "http://localhost:11434"}
  }

# config/test.exs  
config :dspex,
  client_provider: DSPEx.MockClient,
  test_mode: :mock

# Use ExLLM mock provider
config :ex_llm,
  default_provider: :mock
```

#### 6.2 Environment Setup Guide
```bash
# .env.example
# OpenAI
export OPENAI_API_KEY="sk-..."

# Anthropic Claude
export ANTHROPIC_API_KEY="api-..."

# Google Gemini  
export GOOGLE_API_KEY="your-key"

# Groq
export GROQ_API_KEY="gsk-..."

# OpenRouter (300+ models)
export OPENROUTER_API_KEY="sk-or-..."

# Local Ollama
export OLLAMA_API_BASE="http://localhost:11434"

# AWS Bedrock
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"

# X.AI Grok
export XAI_API_KEY="xai-..."
```

### Phase 7: Documentation & Migration (Week 4)

#### 7.1 Migration Documentation
```elixir
# guides/migrating_from_instructor_lite.md
defmodule MigrationGuide do
  @moduledoc """
  # Migrating from InstructorLite to ExLLM
  
  ## Before (InstructorLite)
  ```elixir
  # Limited to Gemini only
  program = DSPEx.PredictStructured.new(
    QASignature, 
    :gemini,
    adapter: DSPEx.Adapters.InstructorLiteGemini
  )
  ```
  
  ## After (ExLLM)
  ```elixir
  # Works with all ExLLM providers
  program = DSPEx.PredictStructured.new(QASignature, :anthropic)
  program = DSPEx.PredictStructured.new(QASignature, :openai)  
  program = DSPEx.PredictStructured.new(QASignature, :gemini)
  program = DSPEx.PredictStructured.new(QASignature, :groq)
  ```
  
  ## Benefits
  - 12+ provider support vs 1
  - Built-in streaming and function calling
  - Better error handling and retries
  - Native cost tracking
  - Session management
  - No custom adapter maintenance
  """
end
```

#### 7.2 Usage Examples
```elixir
# examples/ex_llm_client_examples.ex
defmodule DSPEx.Examples.ExLLMClient do
  @moduledoc """
  Examples of using DSPEx with ExLLM integration.
  """
  
  # Basic chat across providers
  def multi_provider_example do
    messages = [%{role: "user", content: "What is Elixir?"}]
    
    # OpenAI
    {:ok, response1} = DSPEx.Client.request(messages, %{provider: :openai})
    
    # Anthropic Claude
    {:ok, response2} = DSPEx.Client.request(messages, %{provider: :anthropic})
    
    # Google Gemini
    {:ok, response3} = DSPEx.Client.request(messages, %{provider: :gemini})
    
    # Local Ollama
    {:ok, response4} = DSPEx.Client.request(messages, %{provider: :ollama})
    
    [response1, response2, response3, response4]
  end
  
  # Structured outputs with ExLLM
  def structured_output_example do
    defmodule AnalysisSignature do
      use DSPEx.Signature, "text -> sentiment, confidence, reasoning"
    end
    
    program = DSPEx.PredictStructured.new(AnalysisSignature, :anthropic)
    
    {:ok, result} = DSPEx.Program.forward(program, %{
      text: "I love programming in Elixir!"
    })
    
    # result => %{
    #   sentiment: "positive",
    #   confidence: "high", 
    #   reasoning: "The text expresses clear enthusiasm..."
    # }
  end
  
  # Session-based conversations
  def session_example do
    {:ok, client} = DSPEx.ClientManager.start_session(:anthropic)
    
    {:ok, response1} = DSPEx.ClientManager.chat_with_session(
      client, 
      "Hello, I'm learning Elixir"
    )
    
    {:ok, response2} = DSPEx.ClientManager.chat_with_session(
      client,
      "Can you explain GenServers?"
    )
    
    {:ok, history} = DSPEx.ClientManager.get_session_history(client)
    
    {response1, response2, history}
  end
  
  # Provider capability checking
  def capability_example do
    # Check what's configured
    configured_providers = Enum.filter(
      [:openai, :anthropic, :gemini, :groq, :ollama],
      &ExLLM.configured?/1
    )
    
    # Find providers with specific features
    vision_providers = Enum.filter(
      configured_providers,
      fn provider -> ExLLM.provider_supports?(provider, :vision) end
    )
    
    # Get model recommendations
    recommendations = ExLLM.recommend_models(
      features: [:streaming, :function_calling],
      max_cost_per_1k_tokens: 10.0
    )
    
    {configured_providers, vision_providers, recommendations}
  end
end
```

## Implementation Timeline

### Week 1: Foundation
- [ ] Update dependencies (remove instructor_lite, add ex_llm)
- [ ] Define DSPEx.Client behaviour
- [ ] Create DSPEx.Clients.ExLLMClient
- [ ] Remove InstructorLite files

### Week 2: Core Integration  
- [ ] Update ClientManager with ExLLM sessions
- [ ] Create ExLLM structured output adapter
- [ ] Update PredictStructured without InstructorLite
- [ ] Basic integration testing

### Week 3: Testing & Validation
- [ ] Update mock infrastructure for ExLLM
- [ ] Migrate existing tests to new client
- [ ] Add contract verification tests
- [ ] Performance testing

### Week 4: Documentation & Polish
- [ ] Complete migration documentation  
- [ ] Add usage examples
- [ ] Update configuration guides
- [ ] Final integration testing

## Benefits Summary

### 🚀 Performance & Reliability
- **12+ provider support** vs single provider (Gemini)
- **Built-in retries** with exponential backoff
- **Automatic error recovery** and circuit breakers
- **Native streaming support** with error recovery

### 🛠️ Developer Experience  
- **Unified API** across all providers
- **Built-in testing** with mock provider
- **Configuration flexibility** (env vars, static, custom)
- **Cost tracking** and usage monitoring

### 🏗️ Architecture
- **Behaviour-based design** enables better testing
- **Session management** for conversation tracking
- **Function calling** support across providers
- **Structured outputs** without custom adapters

### 📈 Maintenance
- **Reduced code** - eliminate custom provider implementations
- **Community support** - leverage ExLLM ecosystem
- **Future-proof** - automatic new provider support
- **Less complexity** - remove custom error handling

This migration positions DSPEx as having best-in-class LLM client infrastructure while significantly reducing maintenance burden and increasing provider support.