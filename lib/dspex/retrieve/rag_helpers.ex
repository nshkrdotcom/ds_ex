defmodule DSPEx.Retrieve.RAGHelpers do
  @moduledoc """
  Convenience helpers for RAG: build an index from docs and run a query.
  """

  alias DSPEx.Retrieve.{Index, RAG}

  @spec run_with_docs([String.t()], DSPEx.Predict.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run_with_docs(docs, program, query, opts \\ []) do
    with {:ok, index} <- Index.new(docs, opts),
         false <- docs == [] do
      RAG.run(index, program, query, opts)
    else
      true -> {:error, :no_documents}
      {:error, reason} -> {:error, reason}
    end
  end
end
