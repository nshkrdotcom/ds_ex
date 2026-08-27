defmodule DSPEx.RetrievalIndexTest do
  use ExUnit.Case

  test "index builds and searches" do
    {:ok, index} = DSPEx.Retrieve.Index.new(["Paris is nice", "Cats are great"], model: :mock)
    {:ok, results} = DSPEx.Retrieve.Index.search(index, "Paris", top_k: 1)
    [{doc, _score}] = results
    assert doc == "Paris is nice"
  end
end
