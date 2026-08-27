defmodule DSPEx.RAGHelpersTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "question, context -> answer"
  end

  test "run_with_docs builds index and predicts" do
    program = DSPEx.Predict.new(Sig)
    {:ok, outputs} =
      DSPEx.Retrieve.RAGHelpers.run_with_docs(
        ["Doc1", "Doc2"],
        program,
        "Q?"
      )

    assert outputs[:answer] == "mock_answer"
  end

  test "run_with_docs errors on empty docs" do
    program = DSPEx.Predict.new(Sig)
    assert {:error, _} = DSPEx.Retrieve.RAGHelpers.run_with_docs([], program, "Q?")
  end
end
