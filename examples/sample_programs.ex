defmodule DSPEx.Examples.SamplePrograms do
  @moduledoc """
  A collection of sample programs demonstrating the capabilities of the DSPEx framework.

  These programs showcase core concepts like simple prediction, chain of thought,
  program composition, RAG, concurrent execution, and optimization. They are
  designed to be runnable using mock components.
  """

  # =================================================================
  # Mocks & Test Signatures (for runnable examples)
  # =================================================================

  defmodule MockClient do
    @doc "A versatile mock client for testing various scenarios."
    def request(_client, request) do
      content = Jason.encode!(request)

      cond do
        String.contains?(content, "reasoning") ->
          {:ok,
           %{
             choices: [
               %{
                 message: %{
                   content: """
                   [[ ## reasoning ## ]]
                   The user wants me to solve a math problem. 2 + 2 is a fundamental arithmetic operation. The sum is 4.
                   [[ ## answer ## ]]
                   4
                   """
                 }
               }
             ],
             usage: %{prompt_tokens: 20, completion_tokens: 18}
           }}

        String.contains?(content, "sentiment") ->
          {:ok,
           %{
             choices: [
               %{
                 message: %{
                   content: """
                   [[ ## sentiment ## ]]
                   positive
                   [[ ## confidence ## ]]
                   0.95
                   """
                 }
               }
             ],
             usage: %{prompt_tokens: 15, completion_tokens: 5}
           }}

        String.contains?(content, "context") ->
          {:ok,
           %{
             choices: [
               %{
                 message: %{
                   content: """
                   [[ ## answer ## ]]
                   Based on the context, Paris is the capital of France.
                   """
                 }
               }
             ],
             usage: %{prompt_tokens: 50, completion_tokens: 10}
           }}

        true ->
          {:ok,
           %{
             choices: [%{message: %{content: "[[ ## answer ## ]]\n42"}}],
             usage: %{prompt_tokens: 10, completion_tokens: 2}
           }}
      end
    end
  end

  defmodule MockRetriever do
    @doc "A simple mock retriever for RAG examples."
    def retrieve(_retriever, "What is the capital of France?") do
      [
        %{document: "Paris is the capital and largest city of France.", score: 0.95},
        %{document: "France is a country in Western Europe.", score: 0.87}
      ]
    end

    def retrieve(_retriever, _query) do
      [%{document: "No relevant information found.", score: 0.1}]
    end
  end

  # =================================================================
  # 1. Simple Question & Answer Program
  # =================================================================

  defmodule SimpleQandA do
    @moduledoc """
    Demonstrates a basic `DSPEx.Predict` program for a simple QA task.
    This is the "Hello, World!" of DSPEx.
    """
    @behaviour DSPEx.Program

    defstruct [:predict]

    def new(client) do
      predict = DSPEx.Predict.new("question -> answer", client: client)
      %__MODULE__{predict: predict}
    end

    def forward(%__MODULE__{predict: predict}, inputs) do
      DSPEx.Predict.forward(predict, inputs)
    end
  end

  # =================================================================
  # 2. Chain of Thought Program
  # =================================================================

  defmodule MathWithReasoning do
    @moduledoc "Demonstrates `DSPEx.ChainOfThought` to solve a problem step-by-step."
    @behaviour DSPEx.Program

    defstruct [:cot]

    def new(client) do
      # The signature includes `reasoning` before `answer` to guide the LLM.
      cot = DSPEx.ChainOfThought.new("question -> reasoning, answer", client: client)
      %__MODULE__{cot: cot}
    end

    def forward(%__MODULE__{cot: cot}, inputs) do
      DSPEx.ChainOfThought.forward(cot, inputs)
    end
  end

  # =================================================================
  # 3. Composed Program (Multi-Step)
  # =================================================================

  defmodule MultiStepAnalysis do
    @moduledoc "Demonstrates composing multiple programs together."
    @behaviour DSPEx.Program

    defstruct [:analyzer, :summarizer]

    def new(client) do
      analyzer = DSPEx.Predict.new("text -> sentiment, confidence", client: client)
      summarizer = DSPEx.Predict.new("text, sentiment -> summary", client: client)
      %__MODULE__{analyzer: analyzer, summarizer: summarizer}
    end

    def forward(%__MODULE__{analyzer: analyzer, summarizer: summarizer}, inputs) do
      # Step 1: Analyze the text
      case DSPEx.Predict.forward(analyzer, inputs) do
        {:ok, analysis} ->
          # Step 2: Use the analysis to guide the summarization
          enhanced_inputs =
            inputs
            |> Map.put(:sentiment, analysis.sentiment)

          DSPEx.Predict.forward(summarizer, enhanced_inputs)

        error ->
          error
      end
    end
  end

  # =================================================================
  # 4. Retrieval-Augmented Generation (RAG) Program
  # =================================================================

  defmodule RAG do
    @moduledoc "Demonstrates a RAG pipeline combining retrieval and generation."
    @behaviour DSPEx.Program

    defstruct [:retriever, :generator]

    def new(retriever, client) do
      generator = DSPEx.Predict.new("context, question -> answer", client: client)
      %__MODULE__{retriever: retriever, generator: generator}
    end

    def forward(%__MODULE__{retriever: retriever, generator: generator}, inputs) do
      # Step 1: Retrieve context
      documents = MockRetriever.retrieve(retriever, inputs.question)
      context = Enum.map_join(documents, "\n\n", & &1.document)

      # Step 2: Generate answer using the retrieved context
      enhanced_inputs = Map.put(inputs, :context, context)
      DSPEx.Predict.forward(generator, enhanced_inputs)
    end
  end

  # =================================================================
  # 5. Concurrent Execution
  # =================================================================

  defmodule ParallelExecution do
    @moduledoc "Demonstrates running multiple predictions concurrently using Task.async_stream."

    def run(questions, client) do
      predictor = DSPEx.Predict.new("question -> answer", client: client)

      questions
      |> Task.async_stream(
        fn question ->
          DSPEx.Predict.forward(predictor, %{question: question})
        end,
        max_concurrency: System.schedulers_online() * 2,
        timeout: 15_000
      )
      |> Enum.map(fn {:ok, result} -> result end)
    end
  end

  # =================================================================
  # 6. Optimization Workflow
  # =================================================================

  defmodule OptimizationWorkflow do
    @moduledoc "Demonstrates the full optimization loop with BootstrapFewShot."

    def run(client) do
      # --- Setup ---
      # 1. Define student and teacher programs (can be the same).
      student = SimpleQandA.new(client)
      teacher = student

      # 2. Create a small training set.
      trainset = [
        %DSPEx.Example{question: "What is 2+2?", answer: "4"},
        %DSPEx.Example{question: "What color is the sky?", answer: "blue"}
      ]

      # 3. Define a metric for success.
      metric = fn example, prediction ->
        case prediction do
          {:ok, pred} when String.trim(pred.answer) == String.trim(example.answer) -> 1.0
          _ -> 0.0
        end
      end

      # --- Optimization ---
      # 4. Initialize the teleprompter.
      bootstrap =
        DSPEx.Teleprompter.BootstrapFewShot.new(metric: metric, max_bootstrapped_demos: 1)

      # 5. Compile the program.
      # This runs the teacher on the trainset to find good few-shot examples.
      compiled_student =
        DSPEx.Teleprompter.BootstrapFewShot.compile(
          bootstrap,
          student: student,
          teacher: teacher,
          trainset: trainset
        )

      # --- Result ---
      # The compiled program now has few-shot demos.
      IO.puts("Optimization complete.")
      IO.puts("Number of demos found: #{length(compiled_student.predict.demos)}")
      IO.inspect(compiled_student.predict.demos)

      compiled_student
    end
  end
end
