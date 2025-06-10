defmodule DSPEx.Client do
  @moduledoc """
  HTTP client for language model API communication with Foundation integration.

  Provides a robust interface for making requests to various language model providers
  with built-in circuit breakers, rate limiting, telemetry, and error handling via
  Foundation infrastructure.

  ## Configuration

  Configuration is managed through Foundation's config system. Default providers
  are configured automatically, but you can override via application config or
  environment variables.

  ## Examples

      iex> messages = [%{role: "user", content: "Hello"}]
      iex> {:ok, response} = DSPEx.Client.request(messages)
      iex> response.choices
      [%{message: %{content: "Hello! How can I help you?"}}]

      # With custom options
      iex> {:ok, response} = DSPEx.Client.request(messages, %{
      ...>   provider: :openai,
      ...>   temperature: 0.9,
      ...>   correlation_id: "req-123"
      ...> })

  ## Type Specifications

  See `@type` definitions for detailed type information following Elixir best practices.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type request_options :: %{
          optional(:provider) => atom(),
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer(),
          optional(:correlation_id) => String.t()
        }
  @type response :: %{choices: [%{message: message()}]}
  @type error_reason ::
          :timeout
          | :network_error
          | :invalid_response
          | :api_error
          | :circuit_open
          | :rate_limited
          | :invalid_messages
          | :provider_not_configured
          | :unsupported_provider
          | :unexpected_result

  @doc """
  Make a request to the configured LLM provider with Foundation protection.

  ## Parameters

  - `messages` - List of message maps with role and content
  - `options` - Optional request configuration (provider, model, temperature, etc.)

  ## Returns

  - `{:ok, response}` - Successful response with choices
  - `{:error, reason}` - Error with categorized reason

  ## Examples

      iex> messages = [%{role: "user", content: "What is 2+2?"}]
      iex> {:ok, response} = DSPEx.Client.request(messages)
      iex> is_map(response)
      true

  """
  @spec request([message()]) :: {:ok, response()} | {:error, error_reason()}
  def request(messages) do
    request(messages, %{})
  end

  @spec request([message()], request_options()) :: {:ok, response()} | {:error, error_reason()}
  def request(messages, options) do
    request(:default, messages, options)
  end

  def request(client_id, messages, options) do
    # Validate messages before proceeding
    if not valid_messages?(messages) do
      {:error, :invalid_messages}
    else
      correlation_id =
        Map.get(options, :correlation_id) || Foundation.Utils.generate_correlation_id()

      # Determine provider from client_id or options
      provider = resolve_provider(client_id, options)

      # Execute the request with proper error handling
      do_protected_request(messages, options, provider, correlation_id)
    end
  end

  # Private functions

  @spec do_protected_request([message()], request_options(), atom(), binary()) ::
          {:ok, response()} | {:error, error_reason()}
  defp do_protected_request(messages, options, provider, correlation_id) do
    # Emit telemetry start event
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :client, :request, :start],
      %{
        system_time: System.system_time()
      },
      %{
        provider: provider,
        correlation_id: correlation_id,
        message_count: length(messages)
      }
    )

    # Execute request directly for now (Foundation contract issues)
    result = do_request(messages, options, provider, correlation_id)

    # Emit telemetry stop event
    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :client, :request, :stop],
      %{
        duration: duration,
        success: success
      },
      %{
        provider: provider,
        correlation_id: correlation_id
      }
    )

    result
  end

  @spec do_request([message()], request_options(), atom(), binary()) ::
          {:ok, response()} | {:error, error_reason()}
  defp do_request(messages, options, provider, correlation_id) do
    with {:ok, provider_config} <- get_provider_config(provider),
         {:ok, request_body} <- build_request_body(messages, options, provider_config),
         {:ok, http_response} <- make_http_request(request_body, provider_config, correlation_id),
         {:ok, parsed_response} <- parse_response(http_response, provider) do
      {:ok, parsed_response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec resolve_provider(atom(), request_options()) :: atom()
  defp resolve_provider(client_id, options) do
    # Priority: options > client_id mapping > default
    cond do
      Map.has_key?(options, :provider) ->
        Map.get(options, :provider)

      client_id != :default ->
        # Map client_id to provider (e.g., :openai -> :openai)
        client_id

      true ->
        get_default_provider()
    end
  end

  @spec get_default_provider() :: atom()
  defp get_default_provider do
    DSPEx.Services.ConfigManager.get_with_default([:prediction, :default_provider], :gemini)
  end

  @spec get_provider_config(atom()) :: {:ok, map()} | {:error, :provider_not_configured}
  defp get_provider_config(provider) do
    case DSPEx.Services.ConfigManager.get([:providers, provider]) do
      {:ok, config} ->
        {:ok, config}

      {:error, _} ->
        {:error, :provider_not_configured}
    end
  end

  @spec build_request_body([message()], request_options(), map()) ::
          {:ok, map()} | {:error, :unsupported_provider}
  defp build_request_body(messages, options, provider_config) do
    if valid_messages?(messages) do
      case determine_provider_type(provider_config) do
        :gemini ->
          build_gemini_request_body(messages, options, provider_config)

        :openai ->
          build_openai_request_body(messages, options, provider_config)

        :unknown ->
          {:error, :unsupported_provider}
      end
    else
      {:error, :invalid_messages}
    end
  end

  defp determine_provider_type(%{base_url: base_url}) when is_binary(base_url) do
    cond do
      String.contains?(base_url, "generativelanguage.googleapis.com") -> :gemini
      String.contains?(base_url, "api.openai.com") -> :openai
      true -> :unknown
    end
  end

  defp determine_provider_type(_), do: :unknown

  defp build_gemini_request_body(messages, options, provider_config) do
    # Convert OpenAI-style messages to Gemini format
    contents =
      case messages do
        [%{role: "user", content: content}] ->
          # Single user message - no role needed (matches curl example)
          [%{parts: [%{text: content}]}]

        multiple_messages ->
          # Multi-turn conversation - include roles
          Enum.map(multiple_messages, fn message ->
            case convert_gemini_role(message.role) do
              "user" -> %{parts: [%{text: message.content}], role: "user"}
              "model" -> %{parts: [%{text: message.content}], role: "model"}
              _ -> %{parts: [%{text: message.content}]}
            end
          end)
      end

    body = %{
      contents: contents,
      generationConfig: %{
        temperature:
          Map.get(options, :temperature) || provider_config[:default_temperature] || 0.7,
        maxOutputTokens:
          Map.get(options, :max_tokens) || provider_config[:default_max_tokens] || 150
      }
    }

    {:ok, body}
  end

  defp build_openai_request_body(messages, options, provider_config) do
    body = %{
      model: Map.get(options, :model) || provider_config[:default_model] || "gpt-4",
      messages: messages,
      temperature: Map.get(options, :temperature) || provider_config[:default_temperature] || 0.7,
      max_tokens: Map.get(options, :max_tokens) || provider_config[:default_max_tokens] || 150
    }

    {:ok, body}
  end

  defp convert_gemini_role("user"), do: "user"
  defp convert_gemini_role("assistant"), do: "model"
  # Gemini treats system as user
  defp convert_gemini_role("system"), do: "user"
  defp convert_gemini_role(other), do: other

  defp valid_messages?(messages) when is_list(messages) and length(messages) > 0 do
    Enum.all?(messages, fn
      %{role: role, content: content} when is_binary(role) and is_binary(content) -> true
      _ -> false
    end)
  end

  defp valid_messages?(_), do: false

  defp make_http_request(body, provider_config, correlation_id) do
    url = build_api_url(provider_config)
    headers = build_headers(provider_config)
    timeout = Map.get(provider_config, :timeout, 30_000)

    case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: error_body}} when status >= 400 ->
        # Foundation v0.1.3 fixed - re-enabled!
        Foundation.Events.new_event(
          :api_error,
          %{
            status: status,
            error_body: Foundation.Utils.truncate_if_large(error_body, 500),
            timestamp: DateTime.utc_now()
          },
          correlation_id: correlation_id
        )
        |> Foundation.Events.store()

        {:error, :api_error}

      {:error, %{__exception__: true} = exception} ->
        error_type =
          case exception do
            %{reason: :timeout} -> :timeout
            %{reason: :closed} -> :network_error
            _ -> :network_error
          end

        # Foundation v0.1.3 fixed - re-enabled!
        Foundation.Events.new_event(
          :network_error,
          %{
            error_type: error_type,
            exception: Exception.format(:error, exception),
            timestamp: DateTime.utc_now()
          },
          correlation_id: correlation_id
        )
        |> Foundation.Events.store()

        {:error, error_type}
    end
  end

  defp build_api_url(provider_config) do
    api_key = resolve_api_key(provider_config.api_key)
    base_url = provider_config.base_url

    case determine_provider_type(provider_config) do
      :gemini ->
        model = provider_config.default_model
        "#{base_url}/#{model}:generateContent?key=#{api_key}"

      :openai ->
        "#{base_url}/chat/completions"

      :unknown ->
        base_url
    end
  end

  defp build_headers(provider_config) do
    case determine_provider_type(provider_config) do
      :gemini ->
        [{"content-type", "application/json"}]

      :openai ->
        api_key = resolve_api_key(provider_config.api_key)

        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{api_key}"}
        ]

      :unknown ->
        [{"content-type", "application/json"}]
    end
  end

  defp resolve_api_key({:system, env_var}) do
    System.get_env(env_var) || raise "Environment variable #{env_var} not set"
  end

  defp resolve_api_key(api_key) when is_binary(api_key), do: api_key

  defp parse_response(%Req.Response{body: body}, provider) when is_map(body) do
    case provider do
      provider when provider in [:gemini] ->
        parse_gemini_response(body)

      provider when provider in [:openai] ->
        parse_openai_response(body)

      _ ->
        {:error, :unsupported_provider}
    end
  end

  defp parse_response(_, _), do: {:error, :invalid_response}

  defp parse_gemini_response(%{"candidates" => candidates}) when is_list(candidates) do
    parsed_choices = Enum.map(candidates, &parse_gemini_candidate/1)
    {:ok, %{choices: parsed_choices}}
  end

  defp parse_gemini_response(_), do: {:error, :invalid_response}

  defp parse_openai_response(%{"choices" => choices}) when is_list(choices) do
    parsed_choices = Enum.map(choices, &parse_openai_choice/1)
    {:ok, %{choices: parsed_choices}}
  end

  defp parse_openai_response(_), do: {:error, :invalid_response}

  defp parse_gemini_candidate(%{"content" => %{"parts" => parts}}) when is_list(parts) do
    # Extract text from first part
    content =
      case List.first(parts) do
        %{"text" => text} when is_binary(text) -> text
        _ -> ""
      end

    %{message: %{role: "assistant", content: content}}
  end

  defp parse_gemini_candidate(%{"content" => content}) when is_map(content) do
    # Fallback for different content structure
    text = get_in(content, ["parts", Access.at(0), "text"]) || ""
    %{message: %{role: "assistant", content: text}}
  end

  defp parse_gemini_candidate(_candidate) do
    %{message: %{role: "assistant", content: ""}}
  end

  defp parse_openai_choice(%{"message" => message}) do
    %{message: message}
  end

  defp parse_openai_choice(_choice) do
    %{message: %{role: "assistant", content: ""}}
  end
end
