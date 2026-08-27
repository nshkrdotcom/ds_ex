defmodule DSPEx.EvaluateTest do
  use ExUnit.Case

  defmodule Sig do
    @moduledoc false
    use DSPEx.Signature, "x -> y"
  end

  test "evaluate computes average score" do
    program = DSPEx.Predict.new(Sig)

    examples = [
      DSPEx.Example.new(%{x: "1", y: "mock_y"}, [:x]),
      DSPEx.Example.new(%{x: "2", y: "wrong"}, [:x])
    ]

    metric = DSPEx.Metrics.exact_match(:y)

    {:ok, result} = DSPEx.Evaluate.run(program, examples, metric)

    assert result.score > 0.0
    assert result.stats.total == 2
  end
end
