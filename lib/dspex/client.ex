defmodule DSPEx.Client do
  @moduledoc """
  Thin client wrapper over ReqLLM with mock mode and simple normalization.
  """

  @type request :: %{prompt: String.t(), schema: map(), output_fields: [atom()], inputs: map()}

  @doc """
  Execute a structured generation request.

  In `:mock` mode (default) returns placeholder outputs using the signature output fields.
  In `:live` mode uses ReqLLM.generate_object/4.
  """
  def request(request, opts \\ [])

  def request(messages, opts) when is_list(messages) do
    prompt =
      messages
      |> Enum.map_join("\n", fn
        %{role: role, content: content} -> "#{role}: #{content}"
        other -> to_string(other)
      end)

    request(%{prompt: prompt, schema: %{"type" => "object", "properties" => %{}}, output_fields: []}, opts)
  end

  @spec request(request(), keyword()) :: {:ok, map()} | {:error, term()}
  def request(%{prompt: prompt, schema: schema, output_fields: fields} = _req, opts) do
    mode = Keyword.get(opts, :mode, default_mode())
    llm = Keyword.get(opts, :llm_module, ReqLLM)

    case mode do
      :mock ->
        {:ok, %{object: mock_outputs(fields)}}

      :live ->
        do_request(llm, prompt, schema, opts)

      :fallback ->
        case do_request(llm, prompt, schema, opts) do
          {:ok, _} = ok -> ok
          {:error, _} -> {:ok, %{object: mock_outputs(fields)}}
        end
    end
  end

  @doc """
  Generate embeddings for text or a list of texts.

  Mock mode returns zero vectors; live mode uses ReqLLM.embed/3.
  """
  @spec embed(String.t() | [String.t()], keyword()) :: {:ok, list()} | {:error, term()}
  def embed(texts, opts \\ []) do
    mode = Keyword.get(opts, :mode, default_mode())
    model_spec = Keyword.get(opts, :model, default_embedding_model())
    dimensions = Keyword.get(opts, :dimensions, 3)
    mock_vector = Keyword.get(opts, :mock_embedding, nil)
    llm = Keyword.get(opts, :llm_module, ReqLLM)

    case mode do
      :mock ->
        {:ok, mock_embeddings(texts, dimensions, mock_vector)}

      :fallback ->
        case llm.embed(model_spec, texts, sanitize_embedding_opts(llm, opts)) do
          {:ok, _} = ok -> ok
          {:error, _} -> {:ok, mock_embeddings(texts, dimensions, mock_vector)}
        end

      :live ->
        llm.embed(model_spec, texts, sanitize_embedding_opts(llm, opts))
    end
  end

  # -- Internals --------------------------------------------------------------

  defp do_request(llm, prompt, schema, opts) do
    model_spec = resolve_model(opts)

    llm_opts = sanitize_generation_opts(llm, opts)

    case llm.generate_object(model_spec, prompt, schema, llm_opts) do
      {:ok, %ReqLLM.Response{} = response} ->
        {:ok, normalize_response(response)}

      {:ok, %{} = response} ->
        {:ok, normalize_response(response)}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp normalize_response(%ReqLLM.Response{object: object} = response) when is_map(object) do
    %{object: object, usage: response.usage}
  end

  defp normalize_response(%ReqLLM.Response{} = response) do
    %{content: ReqLLM.Response.text(response) || "", usage: response.usage}
  end

  defp normalize_response(%{object: object} = response) when is_map(object) do
    %{object: object, usage: Map.get(response, :usage)}
  end

  defp normalize_response(%{content: content} = response) when is_binary(content) do
    %{content: content, usage: Map.get(response, :usage)}
  end

  defp normalize_response(%{text: text} = response) when is_binary(text) do
    %{content: text, usage: Map.get(response, :usage)}
  end

  defp default_mode do
    case System.get_env("DSPEX_TEST_MODE") do
      "live" -> :live
      "fallback" -> :fallback
      _ -> :mock
    end
  end

  defp resolve_model(opts) do
    case Keyword.fetch(opts, :model) do
      {:ok, model_spec} -> model_spec
      :error -> System.get_env("DSPEX_MODEL") || "google:gemini-2.5-flash"
    end
  end

  defp default_embedding_model do
    System.get_env("DSPEX_EMBEDDING_MODEL") || "openai:text-embedding-3-small"
  end

  defp mock_outputs(fields) do
    fields
    |> Enum.map(fn field -> {field, "mock_#{field}"} end)
    |> Enum.into(%{})
  end

  defp sanitize_generation_opts(ReqLLM, opts),
    do: Keyword.drop(opts, [:mode, :model, :llm_module, :demos, :instruction])

  defp sanitize_generation_opts(_llm, opts), do: opts

  defp sanitize_embedding_opts(ReqLLM, opts),
    do: Keyword.drop(opts, [:mode, :llm_module, :mock_embedding, :dimensions, :model])

  defp sanitize_embedding_opts(_llm, opts), do: opts

  defp mock_embeddings(texts, dimensions, mock_vector) when is_list(texts) do
    Enum.map(texts, fn _ -> mock_vector || for _ <- 1..dimensions, do: 0.0 end)
  end

  defp mock_embeddings(_single, dimensions, mock_vector) do
    embedding = mock_vector || for _ <- 1..dimensions, do: 0.0
    [embedding]
  end
end
