defmodule DSPEx.Integration.Phase3AdvancedFeaturesTest do
  use ExUnit.Case, async: true

  alias DSPEx.Predict.{ChainOfThought, ReAct}
  alias DSPEx.Retrieve.{Embeddings, BasicRetriever}
  # alias DSPEx.{Program, Teleprompter}
  alias DSPEx.Program

  @moduletag :integration_test

  # Test signature for Phase 3 features
  defmodule TestSignatures.AdvancedQA do
    use DSPEx.Signature, "question, context -> answer"
  end

  defmodule TestSignatures.BasicQA do
    use DSPEx.Signature, "question -> answer"
  end

  # Test tools for ReAct integration
  defmodule TestTool.SearchTool do
    def description, do: "Search for information"

    def call(query) when is_binary(query) do
      case query do
        "population of Tokyo" -> {:ok, "Tokyo has approximately 14 million people"}
        "2+2" -> {:ok, "Mathematical calculation: 2+2 = 4"}
        _ -> {:ok, "General search result for: #{query}"}
      end
    end
  end

  defmodule TestTool.CalculatorTool do
    def description, do: "Perform mathematical calculations"

    def call(expression) when is_binary(expression) do
      case expression do
        "2+2" -> {:ok, "4"}
        "10*5" -> {:ok, "50"}
        "100/4" -> {:ok, "25"}
        _ -> {:ok, "Calculated result"}
      end
    end
  end

  describe "Chain of Thought Integration" do
    test "Chain of Thought with SIMBA optimization" do
      signature = TestSignatures.BasicQA
      cot = ChainOfThought.new(signature, model: :test)

      # Create some training examples (for future optimization testing)
      _examples = [
        %{
          inputs: %{question: "What is 2+2?"},
          outputs: %{answer: "4", rationale: "Simple addition"}
        },
        %{
          inputs: %{question: "What is 3+3?"},
          outputs: %{answer: "6", rationale: "Another addition"}
        }
      ]

      # Basic metric function for CoT (for future optimization testing)
      _metric_fn = fn example, prediction ->
        if example.outputs.answer == (prediction[:answer] || prediction["answer"]) do
          1.0
        else
          0.0
        end
      end

      # This would normally optimize, but for testing we just verify structure
      assert is_struct(cot)
      assert :rationale in cot.signature.output_fields()
      assert :answer in cot.signature.output_fields()

      # Test forward pass
      {:ok, result} = Program.forward(cot, %{question: "What is 4+4?"})
      assert is_map(result)
    end

    test "Chain of Thought maintains signature fields" do
      signature = TestSignatures.AdvancedQA
      cot = ChainOfThought.new(signature, model: :test)

      # Should preserve original fields and add rationale
      assert :question in cot.signature.input_fields()
      assert :context in cot.signature.input_fields()
      assert :rationale in cot.signature.output_fields()
      assert :answer in cot.signature.output_fields()
    end
  end

  describe "ReAct Integration" do
    test "ReAct with multiple tools" do
      signature = TestSignatures.BasicQA
      tools = [TestTool.SearchTool, TestTool.CalculatorTool]
      react = ReAct.new(signature, tools: tools, model: :test)

      # Verify ReAct structure
      assert is_struct(react)
      assert react.tools == tools
      assert :thought in react.signature.output_fields()
      assert :action in react.signature.output_fields()
      assert :observation in react.signature.output_fields()
      assert :answer in react.signature.output_fields()

      # Test forward pass
      {:ok, result} = Program.forward(react, %{question: "What is the population of Tokyo?"})
      assert is_map(result)
    end

    test "ReAct with SIMBA optimization potential" do
      signature = TestSignatures.BasicQA
      tools = [TestTool.CalculatorTool]
      react = ReAct.new(signature, tools: tools, model: :test)

      # Create examples for potential optimization (for future testing)
      _examples = [
        %{
          inputs: %{question: "What is 10*5?"},
          outputs: %{
            thought: "I need to calculate 10*5",
            action: "Use calculator",
            observation: "Result is 50",
            answer: "50"
          }
        }
      ]

      # Verify ReAct can be used with optimization frameworks
      assert is_struct(react)
      assert length(react.tools) == 1
    end
  end

  describe "Embeddings and Retrieval Integration" do
    test "embeddings with different models work consistently" do
      text = "The cat sat on the mat"

      {:ok, ada_embedding} = Embeddings.embed(text, model: :text_embedding_ada_002)
      {:ok, small_embedding} = Embeddings.embed(text, model: :text_embedding_small)

      assert length(ada_embedding) == 1536
      assert length(small_embedding) == 768
      assert Enum.all?(ada_embedding, &is_float/1)
      assert Enum.all?(small_embedding, &is_float/1)
    end

    test "semantic search with retrieval system" do
      documents = [
        "Cats are domestic feline animals",
        "Dogs are loyal canine pets",
        "Birds can fly in the sky",
        "Fish live underwater in oceans and rivers"
      ]

      {:ok, results} =
        Embeddings.semantic_search(
          "feline pets",
          documents,
          top_k: 2,
          model: :text_embedding_ada_002
        )

      assert is_list(results)
      assert length(results) <= 2

      Enum.each(results, fn {doc, score} ->
        assert is_binary(doc)
        assert is_float(score)
        assert score >= 0.0
        assert score <= 1.0
      end)
    end

    test "BasicRetriever integration workflow" do
      documents = [
        "Machine learning is a subset of artificial intelligence",
        "Neural networks are inspired by biological neurons",
        "Deep learning uses multiple layers in neural networks",
        "Natural language processing helps computers understand text"
      ]

      retriever = BasicRetriever.new(documents, model: :text_embedding_ada_002)

      # Test retrieval
      {:ok, results} = BasicRetriever.retrieve(retriever, "artificial intelligence", top_k: 2)

      assert is_list(results)
      assert length(results) <= 2

      # Add more documents
      new_docs = [
        "Computer vision enables image recognition",
        "Reinforcement learning uses rewards"
      ]

      updated_retriever = BasicRetriever.add_documents(retriever, new_docs)

      assert BasicRetriever.document_count(updated_retriever) == 6

      # Test retrieval with updated documents
      {:ok, new_results} =
        BasicRetriever.retrieve(updated_retriever, "image recognition", top_k: 1)

      assert is_list(new_results)
    end
  end

  describe "Advanced Features with Existing Teleprompters" do
    test "Chain of Thought signature compatibility with existing systems" do
      signature = TestSignatures.BasicQA
      cot = ChainOfThought.new(signature, model: :test)

      # Should work with existing program infrastructure
      assert :question in cot.signature.input_fields()
      assert :answer in cot.signature.output_fields()
      assert :rationale in cot.signature.output_fields()

      # Test basic forward functionality
      {:ok, result} = Program.forward(cot, %{question: "Test question"})
      assert is_map(result)
    end

    test "ReAct signature compatibility with program systems" do
      signature = TestSignatures.BasicQA
      tools = [TestTool.SearchTool]
      react = ReAct.new(signature, tools: tools, model: :test)

      # Should integrate with existing Program.forward
      {:ok, result} = Program.forward(react, %{question: "Test question"})
      assert is_map(result)
    end

    test "Embeddings can support RAG-style workflows" do
      # Create a knowledge base
      knowledge_base = [
        "DSPEx is an Elixir framework for AI programming",
        "Chain of Thought enables step-by-step reasoning",
        "ReAct combines reasoning with action taking",
        "SIMBA optimization improves program performance"
      ]

      retriever = BasicRetriever.new(knowledge_base, model: :text_embedding_ada_002)

      # Simulate RAG workflow
      query = "What is Chain of Thought?"
      {:ok, relevant_docs} = BasicRetriever.retrieve(retriever, query, top_k: 2)

      # Create context from retrieved documents
      context = Enum.map_join(relevant_docs, " ", fn {doc, _score} -> doc end)

      # Use with Chain of Thought for enhanced reasoning
      signature = TestSignatures.AdvancedQA
      cot = ChainOfThought.new(signature, model: :test)

      {:ok, result} =
        Program.forward(cot, %{
          question: query,
          context: context
        })

      assert is_map(result)
      assert is_binary(context)
      assert String.length(context) > 0
    end
  end

  describe "Performance and Integration Validation" do
    test "all advanced features work without breaking existing functionality" do
      # Test that new features don't interfere with existing code

      # 1. Basic signature still works
      basic_signature = TestSignatures.BasicQA
      assert :question in basic_signature.input_fields()
      assert :answer in basic_signature.output_fields()

      # 2. Chain of Thought extends properly
      cot = ChainOfThought.new(basic_signature, model: :test)
      assert :rationale in cot.signature.output_fields()

      # 3. ReAct extends properly
      tools = [TestTool.CalculatorTool]
      react = ReAct.new(basic_signature, tools: tools, model: :test)
      assert :thought in react.signature.output_fields()
      assert :action in react.signature.output_fields()

      # 4. Embeddings work independently
      {:ok, embedding} = Embeddings.embed("test", model: :text_embedding_ada_002)
      assert is_list(embedding)
      assert length(embedding) == 1536

      # 5. All can be used with Program.forward
      {:ok, cot_result} = Program.forward(cot, %{question: "Test"})
      {:ok, react_result} = Program.forward(react, %{question: "Test"})

      assert is_map(cot_result)
      assert is_map(react_result)
    end

    test "embeddings performance is consistent" do
      texts = for i <- 1..10, do: "Text #{i}"

      {:ok, embeddings} = Embeddings.batch_embed(texts, model: :text_embedding_ada_002)

      assert length(embeddings) == 10

      Enum.each(embeddings, fn embedding ->
        assert length(embedding) == 1536
        assert Enum.all?(embedding, &is_float/1)
      end)
    end
  end
end
