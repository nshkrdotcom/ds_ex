defmodule DSPEx.AdapterAndPredictTest do
  use ExUnit.Case

  defmodule QASignature do
    @moduledoc false
    use DSPEx.Signature, "question -> answer"
  end

  defmodule ContextSignature do
    @moduledoc false
    use DSPEx.Signature, "question, context -> answer"
  end

  defmodule ContentLLM do
    def generate_object(_model, _prompt, _schema, _opts) do
      {:ok, %{content: ~s({"answer": "content_ok"})}}
    end
  end

  defmodule PlainTextLLM do
    def generate_object(_model, _prompt, _schema, _opts) do
      {:ok, %{content: "plain content answer"}}
    end
  end

  test "adapter prepares prompt and repairs malformed JSON" do
    inputs = %{question: "What is the capital of France?"}

    {:ok, request} = DSPEx.Adapter.prepare(QASignature, inputs)

    assert is_binary(request.prompt)
    assert request.schema["type"] == "object"

    raw = %{content: ~s({"answer": "Paris",})}

    assert {:ok, %{answer: "Paris"}} =
             DSPEx.Adapter.parse_response(QASignature, raw)
  end

  test "adapter rejects invalid input" do
    assert {:error, {:invalid_inputs, _}} =
             DSPEx.Adapter.prepare(QASignature, %{})
  end

  test "predict uses mock client by default" do
    program = DSPEx.Predict.new(QASignature)

    {:ok, outputs} = DSPEx.Program.forward(program, %{question: "test"})

    assert outputs[:answer] == "mock_answer"
  end

  test "adapter normalizes list context to string for validation" do
    inputs = %{
      question: "Q",
      context: [
        %{text: "Doc1", score: 0.8},
        %{text: "Doc2", score: 0.6}
      ]
    }

    {:ok, request} = DSPEx.Adapter.prepare(ContextSignature, inputs)

    assert is_binary(request.inputs.context)
    assert request.inputs.context =~ "Doc1"
    assert request.inputs.context =~ "Doc2"
  end

  test "predict handles content responses via adapter" do
    program = DSPEx.Predict.new(QASignature)

    {:ok, outputs} =
      DSPEx.Program.forward(program, %{question: "test"},
        mode: :live,
        llm_module: ContentLLM
      )

    assert outputs[:answer] == "content_ok"
  end

  test "predict normalizes plain content responses into output map" do
    program = DSPEx.Predict.new(QASignature)

    {:ok, outputs} =
      DSPEx.Program.forward(program, %{question: "test"},
        mode: :live,
        llm_module: PlainTextLLM
      )

    assert outputs[:answer] == "plain content answer"
  end
end
