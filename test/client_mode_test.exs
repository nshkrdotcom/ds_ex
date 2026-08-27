defmodule DSPEx.ClientModeTest do
  use ExUnit.Case

  test "request mock mode returns mock outputs" do
    {:ok, response} =
      DSPEx.Client.request(%{prompt: "hi", schema: %{}, output_fields: [:answer]}, mode: :mock)

    assert response.object[:answer] == "mock_answer"
  end

  test "embed mock mode returns zero vector" do
    {:ok, [vec]} = DSPEx.Client.embed("hello", mode: :mock, dimensions: 5)
    assert length(vec) == 5
    assert Enum.all?(vec, &(&1 == 0.0))
  end

  test "fallback mode uses mock on error" do
    # Force fallback to error by using an invalid model spec
    assert {:ok, _emb} = DSPEx.Client.embed("hi", mode: :fallback, model: "invalid:model")
  end

  test "embed mock can be overridden with mock_embedding option" do
    {:ok, [vec]} =
      DSPEx.Client.embed("hello", mode: :mock, dimensions: 2, mock_embedding: [1.0, 2.0])

    assert vec == [1.0, 2.0]
  end
end
