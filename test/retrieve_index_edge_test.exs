defmodule DSPEx.RetrieveIndexEdgeTest do
  use ExUnit.Case

  test "clear resets index" do
    {:ok, index} = DSPEx.Retrieve.Index.new(["a", "b"], model: :mock)
    cleared = DSPEx.Retrieve.Index.clear(index)
    assert cleared.texts == []
    assert cleared.embeddings == []
  end

  test "invalid inputs return errors" do
    assert {:error, :invalid_texts} = DSPEx.Retrieve.Index.new(:bad, [])
    assert {:error, :invalid_texts} = DSPEx.Retrieve.Index.add(%DSPEx.Retrieve.Index{}, :bad)
    assert {:error, :invalid_query} = DSPEx.Retrieve.Index.search(%DSPEx.Retrieve.Index{}, :bad)
  end
end
