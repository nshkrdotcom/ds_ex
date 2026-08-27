defmodule DSPEx.Retrieve.RAG do
  @moduledoc """
  Minimal RAG helper: search an index and call Predict with retrieved docs.
  """

  alias DSPEx.Retrieve.Index

  @spec run(Index.t(), struct(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run(%Index{} = index, program, query, opts \\ []) when is_struct(program) do
    top_k = Keyword.get(opts, :top_k, 3)
    threshold = Keyword.get(opts, :threshold, nil)

    call_opts = Keyword.drop(opts, [:context_format, :threshold, :top_k])

    with {:ok, results} <- Index.search(index, query, top_k: top_k),
         filtered <- apply_threshold(results, threshold),
         false <- filtered == [] || filtered == nil,
         context <- format_context(filtered, opts),
         {:ok, outputs} <-
           DSPEx.Program.forward(program, %{question: query, context: context}, call_opts) do
      {:ok, outputs}
    else
      {:error, reason} -> {:error, reason}
      true -> {:error, :no_results}
    end
  end

  defp apply_threshold(results, nil), do: results

  defp apply_threshold(results, threshold) do
    Enum.filter(results, fn {_doc, score} -> is_number(score) and score >= threshold end)
  end

  defp format_context(results, opts) do
    case Keyword.get(opts, :context_format, :string) do
      :list -> Enum.map(results, fn {doc, score} -> %{text: doc, score: score} end)
      _ -> results |> Enum.map_join("\n\n", fn {doc, _score} -> doc end)
    end
  end
end
