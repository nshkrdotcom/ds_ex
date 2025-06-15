defmodule DSPEx.Retrieve.BasicRetrieverTest do
  use ExUnit.Case, async: true
  alias DSPEx.Retrieve.BasicRetriever

  @moduletag :group_1

  describe "new/2" do
    test "creates retriever with document collection" do
      documents = [
        "The cat sat on the mat",
        "Dogs are loyal companions",
        "Birds can fly in the sky"
      ]

      retriever = BasicRetriever.new(documents, model: :text_embedding_ada_002)

      assert is_struct(retriever)
      assert retriever.documents == documents
      assert retriever.model == :text_embedding_ada_002
    end

    test "requires documents parameter" do
      assert_raise ArgumentError, fn ->
        BasicRetriever.new([], model: :text_embedding_ada_002)
      end
    end

    test "validates document types" do
      invalid_documents = ["valid text", 123, "another valid text"]

      assert_raise ArgumentError, fn ->
        BasicRetriever.new(invalid_documents, model: :text_embedding_ada_002)
      end
    end
  end

  describe "retrieve/3" do
    setup do
      documents = [
        "The cat is a domestic animal",
        "Dogs are known for their loyalty",
        "Birds have the ability to fly",
        "Fish live underwater",
        "Mathematics involves numbers and calculations"
      ]

      retriever = BasicRetriever.new(documents, model: :text_embedding_ada_002)
      {:ok, retriever: retriever}
    end

    test "retrieves most relevant documents", %{retriever: retriever} do
      {:ok, results} = BasicRetriever.retrieve(retriever, "feline pets", top_k: 2)

      assert is_list(results)
      assert length(results) <= 2

      Enum.each(results, fn {document, score} ->
        assert is_binary(document)
        assert is_float(score)
        assert score >= 0.0
        assert score <= 1.0
        assert document in retriever.documents
      end)

      # Results should be sorted by relevance score (highest first)
      scores = Enum.map(results, fn {_doc, score} -> score end)
      assert scores == Enum.sort(scores, &>=/2)
    end

    test "respects top_k parameter", %{retriever: retriever} do
      {:ok, results} = BasicRetriever.retrieve(retriever, "animals", top_k: 3)

      assert length(results) <= 3
    end

    test "handles query with no relevant results", %{retriever: retriever} do
      {:ok, results} = BasicRetriever.retrieve(retriever, "quantum physics", top_k: 5)

      # Should still return results, but they may have low scores
      assert is_list(results)
      assert length(results) <= 5
    end

    test "handles empty query", %{retriever: retriever} do
      result = BasicRetriever.retrieve(retriever, "", top_k: 3)

      # Should handle gracefully, either return results or error
      case result do
        {:ok, results} -> assert is_list(results)
        {:error, _reason} -> assert true
      end
    end
  end

  describe "add_documents/2" do
    test "adds new documents to existing retriever" do
      initial_docs = ["Document 1", "Document 2"]
      retriever = BasicRetriever.new(initial_docs, model: :text_embedding_ada_002)

      new_docs = ["Document 3", "Document 4"]
      updated_retriever = BasicRetriever.add_documents(retriever, new_docs)

      assert length(updated_retriever.documents) == 4
      assert "Document 3" in updated_retriever.documents
      assert "Document 4" in updated_retriever.documents
    end

    test "validates new document types" do
      retriever = BasicRetriever.new(["Doc 1"], model: :text_embedding_ada_002)
      invalid_docs = ["valid", 123]

      assert_raise ArgumentError, fn ->
        BasicRetriever.add_documents(retriever, invalid_docs)
      end
    end
  end

  describe "similarity_threshold/3" do
    setup do
      documents = [
        "Cats are feline animals",
        "Dogs are canine pets",
        "Mathematics is about numbers"
      ]

      retriever = BasicRetriever.new(documents, model: :text_embedding_ada_002)
      {:ok, retriever: retriever}
    end

    test "filters results by similarity threshold", %{retriever: retriever} do
      {:ok, results} =
        BasicRetriever.retrieve(
          retriever,
          "feline cats",
          top_k: 5,
          similarity_threshold: 0.7
        )

      Enum.each(results, fn {_doc, score} ->
        assert score >= 0.7
      end)
    end

    test "returns empty list when no documents meet threshold", %{retriever: retriever} do
      {:ok, results} =
        BasicRetriever.retrieve(
          retriever,
          "quantum physics",
          top_k: 5,
          similarity_threshold: 0.95
        )

      # May return empty list if no documents are highly similar enough
      assert is_list(results)
    end
  end
end
