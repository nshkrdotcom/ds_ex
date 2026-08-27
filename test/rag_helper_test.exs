defmodule DSPEx.RAGHelperTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "question, context -> answer"
  end

  defmodule CaptureContextProgram do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, inputs, _opts) do
      send(self(), {:context, inputs.context})
      {:ok, %{answer: "ok"}}
    end
  end

  test "rag helper stitches context and predicts" do
    {:ok, index} = DSPEx.Retrieve.Index.new(["Paris is in France"], model: :mock)
    program = DSPEx.Predict.new(Sig)

    {:ok, outputs} = DSPEx.Retrieve.RAG.run(index, program, "Where is Paris?")

    assert outputs[:answer] == "mock_answer"
  end

  test "rag returns error on empty index" do
    empty = %DSPEx.Retrieve.Index{model: :mock, texts: [], embeddings: []}
    program = DSPEx.Predict.new(Sig)

    assert {:error, _} = DSPEx.Retrieve.RAG.run(empty, program, "hi")
  end

  test "rag filters by threshold" do
    {:ok, index} = DSPEx.Retrieve.Index.new(["Doc1"], model: :mock)
    program = DSPEx.Predict.new(Sig)

    assert {:error, :no_results} =
             DSPEx.Retrieve.RAG.run(index, program, "Q?", threshold: 10.0)
  end

  test "rag supports list context format" do
    {:ok, index} = DSPEx.Retrieve.Index.new(["Doc A", "Doc B"], model: :mock)
    program = DSPEx.Predict.new(Sig)

    {:ok, outputs} =
      DSPEx.Retrieve.RAG.run(index, program, "Q?", context_format: :list)

    assert outputs[:answer] == "mock_answer"
  end

  test "rag threshold still applies when using list context format" do
    {:ok, index} = DSPEx.Retrieve.Index.new(["Doc"], model: :mock)
    program = DSPEx.Predict.new(Sig)

    assert {:error, :no_results} =
             DSPEx.Retrieve.RAG.run(index, program, "Q?",
               threshold: 9.9,
               context_format: :list
             )
  end

  test "rag applies threshold before formatting list context" do
    {:ok, index} = DSPEx.Retrieve.Index.new(["Doc 1", "Doc 2"], model: :mock)
    program = %CaptureContextProgram{signature: Sig}

    {:ok, _outputs} =
      DSPEx.Retrieve.RAG.run(index, program, "Q?",
        context_format: :list,
        threshold: 0.0,
        top_k: 1
      )

    assert_receive {:context, context}
    assert is_list(context)
    assert length(context) == 1

    [%{text: text, score: score}] = context
    assert is_binary(text)
    assert is_number(score)
  end
end
