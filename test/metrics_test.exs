defmodule DSPEx.MetricsTest do
  use ExUnit.Case
  alias DSPEx.Metrics

  test "exact_match returns 1.0 on match" do
    metric = Metrics.exact_match(:answer)
    assert metric.(%{outputs: %{answer: "yes"}}, %{answer: "yes"}) == 1.0
    assert metric.(%{outputs: %{answer: "no"}}, %{answer: "yes"}) == 0.0
  end

  test "contains is case-insensitive" do
    metric = Metrics.contains(:answer)
    assert metric.(%{outputs: %{answer: "Paris"}}, %{answer: "The capital is PARIS"}) == 1.0
    assert metric.(%{outputs: %{answer: "Paris"}}, %{answer: "London"}) == 0.0
  end

  test "f1_boolean matches booleans" do
    metric = Metrics.f1_boolean(:ok?)
    assert metric.(%{outputs: %{ok?: true}}, %{ok?: true}) == 1.0
    assert metric.(%{outputs: %{ok?: false}}, %{ok?: true}) == 0.0
  end
end
