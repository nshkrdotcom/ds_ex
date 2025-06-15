defmodule DSPEx.Retrieve.EmbeddingsTest do
  use ExUnit.Case, async: true
  alias DSPEx.Retrieve.Embeddings

  @moduletag :group_1

  describe "embed/2" do
    test "generates embeddings for text" do
      {:ok, embedding} = Embeddings.embed("Hello world", model: :text_embedding_ada_002)

      assert is_list(embedding)
      # Ada-002 dimensions
      assert length(embedding) == 1536
      assert Enum.all?(embedding, &is_float/1)
    end

    test "handles empty text" do
      {:ok, embedding} = Embeddings.embed("", model: :text_embedding_ada_002)

      assert is_list(embedding)
      assert length(embedding) == 1536
    end

    test "returns error for invalid input" do
      result = Embeddings.embed(123, model: :text_embedding_ada_002)

      assert {:error, _reason} = result
    end

    test "supports different embedding models" do
      {:ok, ada_embedding} = Embeddings.embed("Test text", model: :text_embedding_ada_002)
      {:ok, small_embedding} = Embeddings.embed("Test text", model: :text_embedding_small)

      assert is_list(ada_embedding)
      assert is_list(small_embedding)
      # Different models may have different dimensions
      assert length(ada_embedding) > 0
      assert length(small_embedding) > 0
    end

    @tag :integration_test
    test "generates different embeddings for different texts" do
      {:ok, embedding1} =
        Embeddings.embed("The cat sat on the mat", model: :text_embedding_ada_002)

      {:ok, embedding2} =
        Embeddings.embed("Quantum physics is complex", model: :text_embedding_ada_002)

      assert embedding1 != embedding2
      assert length(embedding1) == length(embedding2)
    end
  end

  describe "cosine_similarity/2" do
    test "computes similarity between embeddings" do
      # Create test embeddings (normalized)
      emb1 = [0.6, 0.8, 0.0]
      emb2 = [0.8, 0.6, 0.0]
      emb3 = [0.0, 0.0, 1.0]

      sim_similar = Embeddings.cosine_similarity(emb1, emb2)
      sim_different = Embeddings.cosine_similarity(emb1, emb3)

      assert sim_similar > sim_different
      assert sim_similar >= 0.0
      assert sim_similar <= 1.0
      assert sim_different >= 0.0
      assert sim_different <= 1.0
    end

    test "handles identical embeddings" do
      embedding = [0.6, 0.8, 0.0]

      similarity = Embeddings.cosine_similarity(embedding, embedding)

      assert_in_delta similarity, 1.0, 0.0001
    end

    test "handles orthogonal embeddings" do
      emb1 = [1.0, 0.0, 0.0]
      emb2 = [0.0, 1.0, 0.0]

      similarity = Embeddings.cosine_similarity(emb1, emb2)

      assert_in_delta similarity, 0.0, 0.0001
    end

    test "handles opposite embeddings" do
      emb1 = [1.0, 0.0, 0.0]
      emb2 = [-1.0, 0.0, 0.0]

      similarity = Embeddings.cosine_similarity(emb1, emb2)

      assert similarity < 0.0
      assert_in_delta similarity, -1.0, 0.0001
    end

    test "handles different embedding dimensions" do
      emb1 = [1.0, 0.0]
      emb2 = [1.0, 0.0, 0.0]

      result = Embeddings.cosine_similarity(emb1, emb2)

      assert {:error, _reason} = result
    end

    test "handles zero vectors" do
      emb1 = [0.0, 0.0, 0.0]
      emb2 = [1.0, 0.0, 0.0]

      result = Embeddings.cosine_similarity(emb1, emb2)

      assert {:error, _reason} = result
    end
  end

  describe "batch_embed/2" do
    test "generates embeddings for multiple texts" do
      texts = ["Hello world", "Goodbye world", "Test text"]

      {:ok, embeddings} = Embeddings.batch_embed(texts, model: :text_embedding_ada_002)

      assert is_list(embeddings)
      assert length(embeddings) == 3

      Enum.each(embeddings, fn embedding ->
        assert is_list(embedding)
        assert length(embedding) == 1536
        assert Enum.all?(embedding, &is_float/1)
      end)
    end

    test "handles empty list" do
      {:ok, embeddings} = Embeddings.batch_embed([], model: :text_embedding_ada_002)

      assert embeddings == []
    end

    test "handles mixed valid and invalid inputs" do
      texts = ["Valid text", 123, "Another valid text"]

      result = Embeddings.batch_embed(texts, model: :text_embedding_ada_002)

      assert {:error, _reason} = result
    end
  end

  describe "semantic_search/3" do
    test "finds most similar texts" do
      query = "feline animal"

      texts = [
        "The cat is sleeping",
        "Dogs are loyal pets",
        "A lion is a big cat",
        "Mathematics is complex"
      ]

      {:ok, results} = Embeddings.semantic_search(query, texts, top_k: 2)

      assert is_list(results)
      assert length(results) <= 2

      Enum.each(results, fn {text, score} ->
        assert is_binary(text)
        assert is_float(score)
        assert score >= 0.0
        assert score <= 1.0
      end)

      # Results should be sorted by score (highest first)
      scores = Enum.map(results, fn {_text, score} -> score end)
      assert scores == Enum.sort(scores, &>=/2)
    end

    test "handles empty text list" do
      {:ok, results} = Embeddings.semantic_search("query", [], top_k: 5)

      assert results == []
    end

    test "respects top_k parameter" do
      query = "test"
      texts = ["text1", "text2", "text3", "text4", "text5"]

      {:ok, results} = Embeddings.semantic_search(query, texts, top_k: 3)

      assert length(results) <= 3
    end
  end
end
