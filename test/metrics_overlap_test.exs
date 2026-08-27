defmodule DSPEx.MetricsOverlapTest do
  use ExUnit.Case
  alias DSPEx.Metrics

  test "f1_tokens gives partial credit" do
    metric = Metrics.f1_tokens(:text)
    assert metric.(%{outputs: %{text: "foo bar"}}, %{text: "foo baz"}) > 0.0
    assert metric.(%{outputs: %{text: nil}}, %{text: "foo"}) == 0.0
  end

  test "rouge1_overlap normalizes by expected tokens" do
    metric = Metrics.rouge1_overlap(:text)
    assert metric.(%{outputs: %{text: "foo"}}, %{text: "foo bar"}) == 1.0
    assert metric.(%{outputs: %{text: "foo bar"}}, %{text: "foo"}) == 0.5
    assert metric.(%{outputs: %{text: ""}}, %{text: "foo"}) == 0.0
  end
end
