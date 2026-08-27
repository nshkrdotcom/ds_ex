defmodule DSPEx.PredictSpecializedTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "question -> answer"
  end

  defmodule Tool do
    def description, do: "Echo tool"
  end

  test "chain of thought wraps signature and returns rationale and answer" do
    program = DSPEx.Predict.ChainOfThought.new(Sig)

    {:ok, outputs} = DSPEx.Program.forward(program, %{question: "hi"})

    assert Map.has_key?(outputs, :rationale)
    assert Map.has_key?(outputs, :answer)
  end

  test "react wraps signature and returns thought/action/observation/answer" do
    program =
      DSPEx.Predict.ReAct.new(Sig,
        tools: [Tool]
      )

    {:ok, outputs} = DSPEx.Program.forward(program, %{question: "hi"})

    assert Map.has_key?(outputs, :thought)
    assert Map.has_key?(outputs, :action)
    assert Map.has_key?(outputs, :observation)
    assert Map.has_key?(outputs, :answer)
  end
end
