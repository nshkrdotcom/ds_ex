defmodule DSPEx.EvaluateTimeoutTest do
  use ExUnit.Case

  defmodule SlowProg do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, _inputs, _opts) do
      Process.sleep(50)
      {:ok, %{y: "late"}}
    end
  end

  defmodule MixedProg do
    use DSPEx.Program
    defstruct [:signature]

    @impl DSPEx.Program
    def forward(_prog, %{x: "slow"}, _opts) do
      Process.sleep(30)
      {:ok, %{y: "late"}}
    end

    def forward(_prog, %{x: "fail"}, _opts) do
      {:error, :boom}
    end
  end

  test "evaluate respects timeout and counts failures" do
    examples = [DSPEx.Example.new(%{x: "1", y: "late"}, [:x])]
    metric = DSPEx.Metrics.exact_match(:y)

    {:ok, result} =
      DSPEx.Evaluate.run(%SlowProg{signature: DSPEx.TeleprompterGEPATest.SimpleSig}, examples, metric,
        timeout: 10
      )

    assert result.stats.failures == 1
    assert result.stats.errors == 1
  end

  test "return_failures captures timeout exits" do
    examples = [DSPEx.Example.new(%{x: "1", y: "late"}, [:x])]
    metric = DSPEx.Metrics.exact_match(:y)

    {:ok, result} =
      DSPEx.Evaluate.run(%SlowProg{signature: DSPEx.TeleprompterGEPATest.SimpleSig}, examples, metric,
        timeout: 5,
        return_failures: true
      )

    assert [%{reason: {:exit, :timeout}}] = result.failures
  end

  test "return_failures collects exits and program errors" do
    examples = [
      DSPEx.Example.new(%{x: "slow", y: "late"}, [:x]),
      DSPEx.Example.new(%{x: "fail", y: "late"}, [:x])
    ]

    metric = DSPEx.Metrics.exact_match(:y)

    {:ok, result} =
      DSPEx.Evaluate.run(%MixedProg{signature: DSPEx.TeleprompterGEPATest.SimpleSig}, examples, metric,
        timeout: 5,
        return_failures: true
      )

    assert Enum.any?(result.failures, &match?(%{reason: {:exit, :timeout}}, &1))
    assert Enum.any?(result.failures, &match?(%{reason: :boom}, &1))
  end
end
