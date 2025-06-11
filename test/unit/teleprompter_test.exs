defmodule DSPEx.TeleprompterTest do
  use ExUnit.Case, async: true

  @moduletag :phase_1

  alias DSPEx.{Teleprompter, Example}

  describe "exact_match/1" do
    test "creates metric function for exact field matching" do
      metric_fn = Teleprompter.exact_match(:answer)

      # Test exact match
      example = Example.new(%{question: "What is 2+2?", answer: "4"})
      example = Example.with_inputs(example, [:question])
      prediction = %{answer: "4"}

      assert metric_fn.(example, prediction) == 1.0
    end

    test "returns 0.0 for non-matching values" do
      metric_fn = Teleprompter.exact_match(:answer)

      example = Example.new(%{question: "What is 2+2?", answer: "4"})
      example = Example.with_inputs(example, [:question])
      prediction = %{answer: "5"}

      assert metric_fn.(example, prediction) == 0.0
    end

    test "handles missing fields gracefully" do
      metric_fn = Teleprompter.exact_match(:answer)

      example = Example.new(%{question: "What is 2+2?", answer: "4"})
      example = Example.with_inputs(example, [:question])
      prediction = %{other_field: "value"}

      assert metric_fn.(example, prediction) == 0.0
    end
  end

  describe "contains_match/1" do
    test "creates metric function for substring matching" do
      metric_fn = Teleprompter.contains_match(:answer)

      example = Example.new(%{question: "What is 2+2?", answer: "four"})
      example = Example.with_inputs(example, [:question])
      prediction = %{answer: "The answer is four."}

      assert metric_fn.(example, prediction) == 1.0
    end

    test "handles case insensitive matching" do
      metric_fn = Teleprompter.contains_match(:answer)

      example = Example.new(%{question: "What is 2+2?", answer: "FOUR"})
      example = Example.with_inputs(example, [:question])
      prediction = %{answer: "The answer is four."}

      assert metric_fn.(example, prediction) == 1.0
    end

    test "falls back to exact match for non-strings" do
      metric_fn = Teleprompter.contains_match(:answer)

      example = Example.new(%{question: "What is 2+2?", answer: 4})
      example = Example.with_inputs(example, [:question])
      prediction = %{answer: 4}

      assert metric_fn.(example, prediction) == 1.0
    end

    test "returns 0.0 when substring not found" do
      metric_fn = Teleprompter.contains_match(:answer)

      example = Example.new(%{question: "What is 2+2?", answer: "four"})
      example = Example.with_inputs(example, [:question])
      prediction = %{answer: "The answer is five."}

      assert metric_fn.(example, prediction) == 0.0
    end
  end

  describe "implements_behavior?/1" do
    test "returns true for modules that implement the behavior" do
      # We'll test this with BootstrapFewShot
      assert Teleprompter.implements_behavior?(DSPEx.Teleprompter.BootstrapFewShot)
    end

    test "returns false for modules that don't implement the behavior" do
      refute Teleprompter.implements_behavior?(String)
    end

    test "returns false for non-existent modules" do
      refute Teleprompter.implements_behavior?(NonExistentModule)
    end
  end
end
