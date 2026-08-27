defmodule DSPEx.EvaluateEdgesTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "x -> y"
  end

  defmodule FailProg do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, _inputs, _opts), do: {:error, :fail}
  end

  defmodule TupleFailProg do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, _inputs, _opts), do: {:error, {:bad, :thing}}
  end

  test "evaluate handles all failures" do
    examples = [DSPEx.Example.new(%{x: "1", y: "z"}, [:x])]
    metric = DSPEx.Metrics.exact_match(:y)

    {:ok, result} = DSPEx.Evaluate.run(%FailProg{signature: Sig}, examples, metric)

    assert result.score == 0.0
    assert result.stats.failures == 1
    assert result.stats.errors == 1
  end

  test "return_failures includes error tuples" do
    examples = [DSPEx.Example.new(%{x: "1", y: "z"}, [:x])]
    metric = DSPEx.Metrics.exact_match(:y)

    {:ok, result} =
      DSPEx.Evaluate.run(%TupleFailProg{signature: Sig}, examples, metric, return_failures: true)

    assert [%{reason: {:bad, :thing}}] = result.failures
  end
end
