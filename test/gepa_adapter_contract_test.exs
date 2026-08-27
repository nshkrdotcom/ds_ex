defmodule DSPEx.GEPAAdapterContractTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "x -> y"
  end

  defmodule Student do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, _inputs, _opts), do: {:ok, %{y: "ok"}}
  end

  test "gepa adapter evaluate returns valid batch" do
    metric = fn _ex, _out -> 1.0 end
    adapter = DSPEx.Teleprompter.GEPAAdapter.new(%Student{signature: Sig}, metric)

    {:ok, batch} = adapter.__struct__.evaluate(adapter, [%{x: 1}], %{"instruction" => ""}, false)

    assert length(batch.outputs) == 1
    assert length(batch.scores) == 1
  end
end
