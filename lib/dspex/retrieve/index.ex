defmodule DSPEx.Retrieve.Index do
  @moduledoc """
  In-memory embedding index for simple retrieval.
  """

  alias DSPEx.Retrieve.Embeddings

  defstruct [:model, :texts, :embeddings]

  @type t :: %__MODULE__{
          model: term(),
          texts: [String.t()],
          embeddings: [[float()]]
        }

  @spec new([String.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def new(texts, opts \\ [])

  def new(texts, opts) when is_list(texts) do
    model = Keyword.get(opts, :model, :text_embedding_ada_002)

    with {:ok, embeddings} <- Embeddings.batch_embed(texts, model: model) do
      {:ok, %__MODULE__{model: model, texts: texts, embeddings: embeddings}}
    end
  end

  def new(_, _), do: {:error, :invalid_texts}

  @spec add(t(), [String.t()]) :: {:ok, t()} | {:error, term()}
  def add(%__MODULE__{} = index, texts) when is_list(texts) do
    with {:ok, new_embeddings} <- Embeddings.batch_embed(texts, model: index.model) do
      {:ok,
       %{
         index
         | texts: index.texts ++ texts,
           embeddings: index.embeddings ++ new_embeddings
       }}
    end
  end

  def add(_, _), do: {:error, :invalid_texts}

  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = index) do
    %{index | texts: [], embeddings: []}
  end

  @spec search(t(), String.t(), keyword()) :: {:ok, [{String.t(), float()}]} | {:error, term()}
  def search(index, query, opts \\ [])

  def search(%__MODULE__{} = index, query, opts) when is_binary(query) do
    top_k = Keyword.get(opts, :top_k, 5)

    with {:ok, query_emb} <- Embeddings.embed(query, model: index.model) do
      scored =
        index.texts
        |> Enum.zip(index.embeddings)
        |> Enum.map(fn {text, emb} ->
          score =
            case Embeddings.cosine_similarity(query_emb, emb) do
              {:error, _} -> 0.0
              value -> value
            end

          {text, score}
        end)
        |> Enum.sort_by(fn {_text, score} -> score end, &>=/2)
        |> Enum.take(top_k)

      {:ok, scored}
    end
  end

  def search(_, _, _), do: {:error, :invalid_query}
end
