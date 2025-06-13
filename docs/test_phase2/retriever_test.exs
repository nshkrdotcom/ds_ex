defmodule DSPEx.RetrieverTest do
  use ExUnit.Case, async: true
  
  @moduletag :phase2_features

  defmodule MockEmbedding do
    def embed(texts) when is_list(texts) do
      # Return mock embeddings based on text content
      Enum.map(texts, fn text ->
        # Simple hash-based mock embedding
        hash = :erlang.phash2(text, 1000)
        for _ <- 1..384, do: :rand.uniform() * hash / 1000
      end)
    end

    def embed(text) when is_binary(text) do
      [embedding] = embed([text])
      embedding
    end
  end

  defmodule MockVectorDB do
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, %{documents: [], embeddings: []}, opts)
    end

    def add_documents(pid, documents, embeddings) do
      GenServer.call(pid, {:add_documents, documents, embeddings})
    end

    def search(pid, query_embedding, k \\ 3) do
      GenServer.call(pid, {:search, query_embedding, k})
    end

    @impl true
    def init(state) do
      {:ok, state}
    end

    @impl true
    def handle_call({:add_documents, documents, embeddings}, _from, state) do
      new_state = %{
        documents: state.documents ++ documents,
        embeddings: state.embeddings ++ embeddings
      }
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call({:search, query_embedding, k}, _from, state) do
      # Simple cosine similarity search
      similarities = Enum.zip(state.documents, state.embeddings)
      |> Enum.with_index()
      |> Enum.map(fn {{doc, embedding}, idx} ->
        similarity = cosine_similarity(query_embedding, embedding)
        {similarity, idx, doc}
      end)
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.take(k)
      |> Enum.map(fn {similarity, _idx, doc} ->
        %{document: doc, score: similarity}
      end)

      {:reply, similarities, state}
    end

    defp cosine_similarity(a, b) do
      dot_product = Enum.zip(a, b) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
      norm_a = :math.sqrt(Enum.map(a, &(&1 * &1)) |> Enum.sum())
      norm_b = :math.sqrt(Enum.map(b, &(&1 * &1)) |> Enum.sum())
      dot_product / (norm_a * norm_b)
    end
  end

  setup do
    {:ok, vector_db} = start_supervised(MockVectorDB)

    # Add some test documents
    documents = [
      "The sky is blue on a clear day.",
      "Paris is the capital of France.",
      "Machine learning is a subset of artificial intelligence.",
      "Dogs are loyal pets and companions.",
      "The ocean contains salt water."
    ]

    embeddings = MockEmbedding.embed(documents)
    MockVectorDB.add_documents(vector_db, documents, embeddings)

    retriever = DSPEx.Retriever.new(
      vector_db: vector_db,
      embedding_fn: &MockEmbedding.embed/1,
      k: 3
    )

    %{retriever: retriever, vector_db: vector_db, documents: documents}
  end

  describe "retriever initialization" do
    test "creates retriever with required components", %{vector_db: vector_db} do
      retriever = DSPEx.Retriever.new(
        vector_db: vector_db,
        embedding_fn: &MockEmbedding.embed/1,
        k: 5
      )

      assert retriever.vector_db == vector_db
      assert is_function(retriever.embedding_fn, 1)
      assert retriever.k == 5
    end

    test "uses default parameters" do
      retriever = DSPEx.Retriever.new(
        vector_db: :mock_db,
        embedding_fn: &MockEmbedding.embed/1
      )

      assert retriever.k == 3  # Default
    end
  end

  describe "document retrieval" do
    test "retrieves relevant documents for query", %{retriever: retriever} do
      results = DSPEx.Retriever.retrieve(retriever, "What is the capital city of France?")

      assert length(results) <= 3
      assert Enum.any?(results, fn result ->
        String.contains?(result.document, "Paris") and
        String.contains?(result.document, "France")
      end)

      # Results should be sorted by relevance score
      scores = Enum.map(results, & &1.score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "returns requested number of documents", %{retriever: retriever} do
      retriever_k2 = %{retriever | k: 2}
      results = DSPEx.Retriever.retrieve(retriever_k2, "blue sky")

      assert length(results) == 2
    end

    test "handles queries with no good matches", %{retriever: retriever} do
      results = DSPEx.Retriever.retrieve(retriever, "completely unrelated quantum physics topic")

      # Should still return documents (though with low scores)
      assert length(results) > 0
      assert Enum.all?(results, fn result -> result.score >= 0 end)
    end

    test "handles empty query", %{retriever: retriever} do
      results = DSPEx.Retriever.retrieve(retriever, "")

      # Should handle gracefully
      assert is_list(results)
    end
  end

  describe "embedding integration" do
    test "uses custom embedding function", %{retriever: retriever, vector_db: _vector_db} do
      custom_embedding_fn = fn text ->
        # Custom embedding that favors certain words
        word_weights = %{"blue" => 1.0, "sky" => 1.0, "Paris" => 1.0}
        words = String.split(String.downcase(text))

        Enum.map(1..384, fn i ->
          Enum.reduce(words, 0.0, fn word, acc ->
            acc + Map.get(word_weights, word, 0.1) * :math.sin(i * String.length(word))
          end)
        end)
      end

      custom_retriever = %{retriever | embedding_fn: custom_embedding_fn}

      results = DSPEx.Retriever.retrieve(custom_retriever, "blue sky")

      # Should still work with custom embeddings
      assert length(results) > 0
      assert Enum.any?(results, fn result ->
        String.contains?(result.document, "blue") or String.contains?(result.document, "sky")
      end)
    end

    test "caches embeddings for repeated queries", %{retriever: retriever} do
      # Add caching to retriever
      {:ok, cache} = start_supervised({Agent, fn -> %{} end})

      cached_embedding_fn = fn text ->
        Agent.get_and_update(cache, fn cache_state ->
          case Map.get(cache_state, text) do
            nil ->
              embedding = MockEmbedding.embed(text)
              {embedding, Map.put(cache_state, text, embedding)}
            cached ->
              {cached, cache_state}
          end
        end)
      end

      cached_retriever = %{retriever | embedding_fn: cached_embedding_fn}

      # First query
      results1 = DSPEx.Retriever.retrieve(cached_retriever, "test query")

      # Second identical query (should use cache)
      results2 = DSPEx.Retriever.retrieve(cached_retriever, "test query")

      assert results1 == results2

      # Verify cache was used
      cache_contents = Agent.get(cache, & &1)
      assert Map.has_key?(cache_contents, "test query")
    end
  end

  describe "retrieval with filtering" do
    test "supports metadata filtering" do
      # This would test filtering documents by metadata
      # Implementation depends on vector DB capabilities
    end

    test "supports semantic filtering" do
      # Test filtering results based on semantic criteria
      # Beyond just similarity scores
    end
  end

  describe "batch retrieval" do
    test "retrieves for multiple queries efficiently", %{retriever: retriever} do
      queries = [
        "What color is the sky?",
        "What is the capital of France?",
        "Tell me about machine learning"
      ]

      start_time = System.monotonic_time(:millisecond)
      results = DSPEx.Retriever.batch_retrieve(retriever, queries)
      end_time = System.monotonic_time(:millisecond)

      _duration = end_time - start_time

      assert length(results) == 3
      assert Enum.all?(results, fn query_results ->
        is_list(query_results) and length(query_results) > 0
      end)

      # Should be faster than sequential retrieval
      # (Implementation would optimize batch embedding and search)
    end
  end
end
