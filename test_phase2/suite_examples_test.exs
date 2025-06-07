defmodule DSPEx.ExamplesTest do
  use ExUnit.Case, async: false
  
  @moduletag :phase2_features

  alias DSPEx.Examples.SamplePrograms

  setup do
    # Start a supervised client using the mock adapter defined in the examples module.
    # This makes the test self-contained.
    {:ok, client} =
      start_supervised(
        {DSPEx.Client,
         %{
           api_key: "mock_key",
           model: "mock_model",
           adapter: SamplePrograms.MockClient
         }}
      )

    # Use the mock retriever module.
    retriever = SamplePrograms.MockRetriever

    %{client: client, retriever: retriever}
  end

  describe "SimpleQandA example" do
    test "answers a simple question", %{client: client} do
      program = SamplePrograms.SimpleQandA.new(client)
      {:ok, prediction} = SamplePrograms.SimpleQandA.forward(program, %{question: "any"})

      assert prediction.answer == "42"
    end
  end

  describe "MathWithReasoning (ChainOfThought) example" do
    test "generates both reasoning and an answer", %{client: client} do
      program = SamplePrograms.MathWithReasoning.new(client)
      {:ok, prediction} =
        SamplePrograms.MathWithReasoning.forward(program, %{question: "What is 2+2?"})

      assert String.contains?(prediction.reasoning, "arithmetic")
      assert prediction.answer == "4"
    end
  end

  describe "MultiStepAnalysis (Composition) example" do
    test "chains multiple predictors together", %{client: client} do
      program = SamplePrograms.MultiStepAnalysis.new(client)

      # The mock client's logic will route this through the sentiment->summary path.
      # The final summarizer call will hit the default "42" response.
      {:ok, prediction} = SamplePrograms.MultiStepAnalysis.forward(program, %{text: "This is great"})

      # We assert the final output, proving the chain executed.
      assert prediction.answer == "42"
    end
  end

  describe "RAG example" do
    test "retrieves context and generates an answer", %{client: client, retriever: retriever} do
      program = SamplePrograms.RAG.new(retriever, client)
      {:ok, prediction} =
        SamplePrograms.RAG.forward(program, %{question: "What is the capital of France?"})

      assert String.contains?(prediction.answer, "Paris")
    end
  end

  describe "ParallelExecution example" do
    test "processes multiple questions concurrently", %{client: client} do
      questions = ["What is life?", "What is love?", "What is Elixir?"]

      results = SamplePrograms.ParallelExecution.run(questions, client)

      assert length(results) == 3
      assert Enum.all?(results, fn result ->
        assert {:ok, prediction} = result
        assert prediction.answer == "42"
      end)
    end
  end

  describe "OptimizationWorkflow example" do
    test "runs bootstrap few-shot and returns an optimized program", %{client: client} do
      # Capture IO to suppress the puts/inspect from the example.
      ExUnit.CaptureIO.capture_io(fn ->
        optimized_program = SamplePrograms.OptimizationWorkflow.run(client)

        # Assert that the output is a program of the correct type.
        assert is_struct(optimized_program, SamplePrograms.SimpleQandA)

        # Assert that the optimization was successful and added demos.
        assert length(optimized_program.predict.demos) > 0

        # Verify the content of the generated demos.
        demo = hd(optimized_program.predict.demos)
        assert demo.question == "What is 2+2?"
        assert demo.answer == "4"
      end)
    end
  end
end
