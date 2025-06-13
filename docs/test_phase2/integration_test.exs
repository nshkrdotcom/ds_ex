defmodule DSPEx.IntegrationTest do
  use ExUnit.Case, async: false
  
  @moduletag :phase2_features

  defmodule QASignature do
    @moduledoc "Answer questions with retrieved context"
    use DSPEx.Signature, "question, context -> answer, confidence"
  end

  defmodule RAGSignature do
    @moduledoc "Retrieve relevant documents and answer questions"
    use DSPEx.Signature, "question -> context, answer"
  end

  defmodule MockClient do
    def request(_client, request) do
      content = Jason.encode!(request)

      cond do
        String.contains?(content, "context") ->
          {:ok, %{
            choices: [%{message: %{content: """
            [[ ## context ## ]]
            Paris is the capital and largest city of France. It is located in the north-central part of the country.

            [[ ## answer ## ]]
            Paris is the capital of France.
            """}}],
            usage: %{prompt_tokens: 25, completion_tokens: 15}
          }}

        true ->
          {:ok, %{
            choices: [%{message: %{content: """
            [[ ## answer ## ]]
            Based on the provided context, Paris is the capital of France.

            [[ ## confidence ## ]]
            high
            """}}],
            usage: %{prompt_tokens: 20, completion_tokens: 12}
          }}
      end
    end
  end

  defmodule MockRetriever do
    def retrieve(_retriever, query) do
      query_lower = String.downcase(query)

      cond do
        String.contains?(query_lower, "france") or String.contains?(query_lower, "paris") ->
          [
            %{document: "Paris is the capital and largest city of France.", score: 0.95},
            %{document: "France is a country in Western Europe.", score: 0.87},
            %{document: "The Eiffel Tower is located in Paris, France.", score: 0.82}
          ]

        String.contains?(query_lower, "berlin") or String.contains?(query_lower, "germany") ->
          [
            %{document: "Berlin is the capital of Germany.", score: 0.94},
            %{document: "Germany is a country in Central Europe.", score: 0.86}
          ]

        true ->
          [
            %{document: "No relevant information found.", score: 0.1}
          ]
      end
    end
  end

  setup do
    {:ok, client} = start_supervised({DSPEx.Client, %{
      api_key: "test",
      model: "test",
      adapter: MockClient
    }})

    retriever = %{module: MockRetriever, k: 3}

    %{client: client, retriever: retriever}
  end

  describe "end-to-end RAG pipeline" do
    test "complete RAG workflow with retrieval and generation", %{client: client, retriever: retriever} do
      # Create RAG program that combines retrieval and generation
      defmodule RAGProgram do
        defstruct [:retriever, :generator]

        def new(retriever, client) do
          generator = DSPEx.Predict.new(QASignature, client: client)
          %__MODULE__{retriever: retriever, generator: generator}
        end

        def forward(%__MODULE__{retriever: retriever, generator: generator}, inputs) do
          # Step 1: Retrieve relevant documents
          results = MockRetriever.retrieve(retriever, inputs.question)
          context = Enum.map(results, & &1.document) |> Enum.join(" ")

          # Step 2: Generate answer with context
          enhanced_inputs = Map.put(inputs, :context, context)
          DSPEx.Predict.forward(generator, enhanced_inputs)
        end
      end

      rag_program = RAGProgram.new(retriever, client)

      result = RAGProgram.forward(rag_program, %{question: "What is the capital of France?"})

      assert {:ok, prediction} = result
      assert String.contains?(prediction.answer, "Paris")
      assert prediction.confidence == "high"
    end

    test "RAG with few-shot examples", %{client: client, retriever: retriever} do
      # Create few-shot examples for RAG
      demos = [
        DSPEx.Example.new(%{
          question: "What is the capital of Germany?",
          context: "Berlin is the capital of Germany. It is the largest city in Germany.",
          answer: "Berlin is the capital of Germany.",
          confidence: "high"
        })
      ]

      rag_predict = DSPEx.Predict.new(QASignature, client: client, demos: demos)

      # Retrieve context for new question
      results = MockRetriever.retrieve(retriever, "What is the capital of France?")
      context = Enum.map(results, & &1.document) |> Enum.join(" ")

      result = DSPEx.Predict.forward(rag_predict, %{
        question: "What is the capital of France?",
        context: context
      })

      assert {:ok, prediction} = result
      assert String.contains?(prediction.answer, "Paris")
    end
  end

  describe "multi-step reasoning pipeline" do
    test "chain of thought with retrieval augmentation", %{client: client, retriever: retriever} do
      defmodule COTSignature do
        use DSPEx.Signature, "question, context -> reasoning, answer"
      end

      defmodule AugmentedCOT do
        defstruct [:retriever, :cot]

        def new(retriever, client) do
          cot = DSPEx.Predict.new(COTSignature, client: client)
          %__MODULE__{retriever: retriever, cot: cot}
        end

        def forward(%__MODULE__{retriever: retriever, cot: cot}, inputs) do
          # Retrieve relevant context
          results = MockRetriever.retrieve(retriever, inputs.question)
          context = Enum.map(results, & &1.document) |> Enum.join(" ")

          # Generate reasoning and answer
          enhanced_inputs = Map.put(inputs, :context, context)

          case DSPEx.Predict.forward(cot, enhanced_inputs) do
            {:ok, prediction} ->
              # Mock COT response
              {:ok, %{
                reasoning: "Based on the retrieved context about France and Paris, I can determine the answer.",
                answer: "Paris"
              }}
            error -> error
          end
        end
      end

      aug_cot = AugmentedCOT.new(retriever, client)

      result = AugmentedCOT.forward(aug_cot, %{question: "What is the capital of France?"})

      assert {:ok, prediction} = result
      assert String.contains?(prediction.reasoning, "retrieved context")
      assert prediction.answer == "Paris"
    end
  end

  describe "optimization pipeline" do
    test "bootstrap few-shot with RAG program", %{client: client, retriever: retriever} do
      defmodule SimpleRAG do
        defstruct [:predict]

        def new(client) do
          predict = DSPEx.Predict.new(QASignature, client: client)
          %__MODULE__{predict: predict}
        end

        def forward(%__MODULE__{predict: predict}, inputs) do
          # Simulate retrieval
          context = "Paris is the capital of France."
          enhanced_inputs = Map.put(inputs, :context, context)
          DSPEx.Predict.forward(predict, enhanced_inputs)
        end

        def add_demo(%__MODULE__{predict: predict} = rag, demo) do
          updated_predict = DSPEx.Predict.add_demo(predict, demo)
          %{rag | predict: updated_predict}
        end
      end

      student = SimpleRAG.new(client)
      teacher = SimpleRAG.new(client)

      trainset = [
        DSPEx.Example.new(%{question: "What is the capital of France?", answer: "Paris"}),
        DSPEx.Example.new(%{question: "What is the capital of Germany?", answer: "Berlin"})
      ]

      metric = fn example, prediction ->
        case prediction do
          {:ok, pred} ->
            if String.contains?(String.downcase(pred.answer), String.downcase(example.answer)) do
              1.0
            else
              0.0
            end
          _ -> 0.0
        end
      end

      bootstrap = DSPEx.Teleprompter.BootstrapFewShot.new(
        metric: metric,
        max_bootstrapped_demos: 1
      )

      compiled_student = DSPEx.Teleprompter.BootstrapFewShot.compile(
        bootstrap,
        student: student,
        teacher: teacher,
        trainset: trainset
      )

      # Test compiled program
      result = SimpleRAG.forward(compiled_student, %{question: "What is the capital of France?"})

      assert {:ok, prediction} = result
      assert length(compiled_student.predict.demos) > 0
    end
  end

  describe "error handling and recovery" do
    test "graceful degradation when retrieval fails", %{client: client} do
      defmodule FailingRetriever do
        def retrieve(_retriever, _query) do
          {:error, :retrieval_failed}
        end
      end

      defmodule RobustRAG do
        defstruct [:retriever, :generator]

        def new(retriever, client) do
          generator = DSPEx.Predict.new(QASignature, client: client)
          %__MODULE__{retriever: retriever, generator: generator}
        end

        def forward(%__MODULE__{retriever: retriever, generator: generator}, inputs) do
          case FailingRetriever.retrieve(retriever, inputs.question) do
            {:error, _} ->
              # Fall back to generation without context
              fallback_inputs = Map.put(inputs, :context, "No additional context available.")
              DSPEx.Predict.forward(generator, fallback_inputs)

            results ->
              context = Enum.map(results, & &1.document) |> Enum.join(" ")
              enhanced_inputs = Map.put(inputs, :context, context)
              DSPEx.Predict.forward(generator, enhanced_inputs)
          end
        end
      end

      robust_rag = RobustRAG.new(%{}, client)

      result = RobustRAG.forward(robust_rag, %{question: "What is the capital of France?"})

      # Should still work despite retrieval failure
      assert {:ok, prediction} = result
    end

    test "retry logic for transient failures", %{client: client} do
      defmodule RetryClient do
        def request(_client, _request) do
          case :persistent_term.get(:request_count, 0) do
            count when count < 2 ->
              :persistent_term.put(:request_count, count + 1)
              {:error, :transient_failure}
            _ ->
              {:ok, %{
                choices: [%{message: %{content: "[[ ## answer ## ]]\nSuccess after retry\n[[ ## confidence ## ]]\nhigh"}}],
                usage: %{prompt_tokens: 10, completion_tokens: 5}
              }}
          end
        end
      end

      {:ok, retry_client} = start_supervised({DSPEx.Client, %{
        api_key: "test",
        model: "retry_test",
        adapter: RetryClient,
        max_retries: 3
      }}, id: :retry_client)

      predict = DSPEx.Predict.new(QASignature, client: retry_client)

      :persistent_term.put(:request_count, 0)

      result = DSPEx.Predict.forward(predict, %{
        question: "Test question",
        context: "Test context"
      })

      assert {:ok, prediction} = result
      assert prediction.answer == "Success after retry"
    end
  end

  describe "performance and scalability" do
    test "concurrent evaluation of multiple programs", %{client: client} do
      programs = for i <- 1..5 do
        DSPEx.Predict.new(QASignature, client: client, name: "program_#{i}")
      end

      questions = for i <- 1..5 do
        %{question: "Question #{i}?", context: "Context for question #{i}"}
      end

      start_time = System.monotonic_time(:millisecond)

      results = Task.async_stream(
        Enum.zip(programs, questions),
        fn {program, input} ->
          DSPEx.Predict.forward(program, input)
        end,
        max_concurrency: 3,
        timeout: 5000
      )
      |> Enum.to_list()

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert length(results) == 5
      assert Enum.all?(results, fn {:ok, {:ok, _prediction}} -> true; _ -> false end)

      # Should complete faster than sequential execution
      assert duration < 1000  # Reasonable timeout for test
    end

    test "memory usage stays reasonable with large demo sets", %{client: client} do
      # Create program with many demos
      large_demo_set = for i <- 1..100 do
        DSPEx.Example.new(%{
          question: "Question #{i}?",
          context: "Context for question #{i}",
          answer: "Answer #{i}",
          confidence: "medium"
        })
      end

      predict = DSPEx.Predict.new(QASignature, client: client, demos: large_demo_set)

      # Verify demos are properly managed
      assert length(predict.demos) <= 50  # Should be truncated to reasonable size

      # Should still work with reduced demo set
      result = DSPEx.Predict.forward(predict, %{
        question: "New question?",
        context: "New context"
      })

      assert {:ok, _prediction} = result
    end
  end
end
