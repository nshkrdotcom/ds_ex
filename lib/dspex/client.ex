defmodule DSPEx.Client do
  @moduledoc """
  HTTP client for Google Gemini API communication.

  Provides a simple, synchronous interface for making requests to Google's
  Gemini language models via the AI Studio API. Built with Req for HTTP
  and includes basic error handling.

  ## Configuration

  Set your Gemini API key via environment variable:

      export GEMINI_API_KEY="your-api-key-here"

  Or configure via application config:

      config :dspex,
        gemini_api_key: "your-api-key-here",
        model: "gemini-2.5-flash-preview-05-20"

  ## Examples

      iex> messages = [%{role: "user", content: "Hello"}]
      iex> {:ok, response} = DSPEx.Client.request(messages)
      iex> response.choices
      [%{message: %{content: "Hello! How can I help you?"}}]

  """

  @type message :: %{role: String.t(), content: String.t()}
  @type request_options :: %{
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer()
        }
  @type response :: %{choices: [%{message: message()}]}
  @type error_reason :: :timeout | :network_error | :invalid_response | :api_error

  @doc """
  Make a request to the configured LLM provider.

  ## Parameters

  - `messages` - List of message maps with role and content
  - `options` - Optional request configuration (model, temperature, etc.)

  ## Returns

  - `{:ok, response}` - Successful response with choices
  - `{:error, reason}` - Error with categorized reason

  """
  @spec request([message()]) :: {:ok, response()} | {:error, error_reason()}
  def request(messages) do
    request(messages, %{})
  end

  @spec request([message()], request_options()) :: {:ok, response()} | {:error, error_reason()}
  def request(messages, options) do
    with {:ok, request_body} <- build_request_body(messages, options),
         {:ok, http_response} <- make_http_request(request_body),
         {:ok, parsed_response} <- parse_response(http_response) do
      {:ok, parsed_response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  @spec build_request_body([message()], request_options()) ::
          {:ok, map()} | {:error, :invalid_messages}
  defp build_request_body(messages, options) do
    if valid_messages?(messages) do
      # Convert OpenAI-style messages to Gemini format
      # For single user message, omit role. For multi-turn, include roles.
      contents =
        case messages do
          [%{role: "user", content: content}] ->
            # Single user message - no role needed (matches curl example)
            [%{parts: [%{text: content}]}]

          multiple_messages ->
            # Multi-turn conversation - include roles
            Enum.map(multiple_messages, fn message ->
              case convert_role(message.role) do
                "user" -> %{parts: [%{text: message.content}], role: "user"}
                "model" -> %{parts: [%{text: message.content}], role: "model"}
                _ -> %{parts: [%{text: message.content}]}
              end
            end)
        end

      body = %{
        contents: contents,
        generationConfig: %{
          temperature: Map.get(options, :temperature, 0.7),
          maxOutputTokens: Map.get(options, :max_tokens, 150)
        }
      }

      {:ok, body}
    else
      {:error, :invalid_messages}
    end
  end

  @spec convert_role(String.t()) :: String.t()
  defp convert_role("user"), do: "user"
  defp convert_role("assistant"), do: "model"
  # Gemini treats system as user
  defp convert_role("system"), do: "user"
  defp convert_role(other), do: other

  @spec valid_messages?([message()]) :: boolean()
  defp valid_messages?(messages) when is_list(messages) and length(messages) > 0 do
    Enum.all?(messages, fn
      %{role: role, content: content} when is_binary(role) and is_binary(content) -> true
      _ -> false
    end)
  end

  defp valid_messages?(_), do: false

  @spec make_http_request(map()) :: {:ok, Req.Response.t()} | {:error, error_reason()}
  defp make_http_request(body) do
    url = get_api_url()
    headers = get_headers()

    case Req.post(url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, %Req.Response{status: status}} when status >= 400 ->
        {:error, :api_error}

      {:error, %{__exception__: true} = exception} ->
        case exception do
          %{reason: :timeout} -> {:error, :timeout}
          %{reason: :closed} -> {:error, :network_error}
          _ -> {:error, :network_error}
        end
    end
  end

  @spec parse_response(Req.Response.t()) :: {:ok, response()} | {:error, :invalid_response}
  defp parse_response(%Req.Response{body: body}) when is_map(body) do
    case body do
      %{"candidates" => candidates} when is_list(candidates) ->
        parsed_choices = Enum.map(candidates, &parse_candidate/1)
        {:ok, %{choices: parsed_choices}}

      _ ->
        {:error, :invalid_response}
    end
  end

  defp parse_response(_), do: {:error, :invalid_response}

  @spec parse_candidate(map()) :: %{message: message()}
  defp parse_candidate(%{"content" => %{"parts" => parts}}) when is_list(parts) do
    # Extract text from first part
    content =
      case List.first(parts) do
        %{"text" => text} when is_binary(text) -> text
        _ -> ""
      end

    %{message: %{role: "assistant", content: content}}
  end

  defp parse_candidate(%{"content" => content}) when is_map(content) do
    # Fallback for different content structure
    text = get_in(content, ["parts", Access.at(0), "text"]) || ""
    %{message: %{role: "assistant", content: text}}
  end

  defp parse_candidate(_candidate) do
    %{message: %{role: "assistant", content: ""}}
  end

  @spec get_api_url() :: String.t()
  defp get_api_url do
    api_key = get_api_key()

    base_url =
      Application.get_env(
        :dspex,
        :api_url,
        "https://generativelanguage.googleapis.com/v1beta/models"
      )

    model = Application.get_env(:dspex, :model, "gemini-2.5-flash-preview-05-20")
    "#{base_url}/#{model}:generateContent?key=#{api_key}"
  end

  @spec get_headers() :: [{String.t(), String.t()}]
  defp get_headers do
    [
      {"content-type", "application/json"}
    ]
  end

  @spec get_api_key() :: String.t()
  defp get_api_key do
    Application.get_env(
      :dspex,
      :gemini_api_key,
      System.get_env("GEMINI_API_KEY", "mock-gemini-key")
    )
  end
end
