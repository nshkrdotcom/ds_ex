defmodule DSPEx.EvaluateExceptionTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "x -> y"
  end

  defmodule OkProg do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, _inputs, _opts), do: {:ok, %{y: "val"}}
  end

  test "metric_fn exceptions are counted as failures" do
    examples = [DSPEx.Example.new(%{x: "1", y: "val"}, [:x])]

    metric = fn _example, _out -> raise "boom" end

    {:ok, result} = DSPEx.Evaluate.run(%OkProg{signature: Sig}, examples, metric)

    assert result.stats.failures == 1
  end

  test "scores_only option returns just scores" do
    examples = [DSPEx.Example.new(%{x: "1", y: "val"}, [:x])]
    metric = DSPEx.Metrics.exact_match(:y)

    {:ok, result} =
      DSPEx.Evaluate.run(%OkProg{signature: Sig}, examples, metric, scores_only: true)

    assert result[:scores] == [1.0]
    refute Map.has_key?(result, :stats)
  end

  test "return_failures includes failure details and invalid scores" do
    examples = [DSPEx.Example.new(%{x: "1", y: "val"}, [:x])]

    metric = fn _example, _out -> "not-a-number" end

    {:ok, result} =
      DSPEx.Evaluate.run(%OkProg{signature: Sig}, examples, metric, return_failures: true)

    assert result.stats.failures == 1
    assert [%{reason: :invalid_score, example: _}] = result.failures
  end
end
