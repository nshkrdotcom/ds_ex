defmodule DSPEx.Unit.ExampleTest do
  @moduledoc """
  Unit tests for DSPEx.Example module focused on Phase 1 requirements.
  Tests core data structure and basic operations needed for foundation.
  """
  use ExUnit.Case, async: true

  @moduletag :phase_1

  alias DSPEx.Example

  describe "example creation and basic structure" do
    test "creates example with empty data" do
      example = Example.new()
      assert %Example{data: %{}, input_keys: input_keys} = example
      assert MapSet.size(input_keys) == 0
    end

    test "creates example with map data" do
      data = %{question: "What is 2+2?", answer: "4"}
      example = Example.new(data)

      assert %Example{data: ^data, input_keys: input_keys} = example
      assert MapSet.size(input_keys) == 0
    end

    test "data is accessible directly" do
      example = Example.new(%{question: "Test", answer: "Response"})
      assert example.data.question == "Test"
      assert example.data.answer == "Response"
    end
  end

  describe "input/output designation - core Phase 1 functionality" do
    setup do
      example =
        Example.new(%{
          question: "What is 2+2?",
          context: "Basic math",
          answer: "4",
          confidence: "high"
        })

      %{example: example}
    end

    test "with_inputs/2 designates input fields", %{example: example} do
      example_with_inputs = Example.with_inputs(example, [:question, :context])

      expected_inputs = MapSet.new([:question, :context])
      assert MapSet.equal?(example_with_inputs.input_keys, expected_inputs)
    end

    test "inputs/1 returns only designated input fields", %{example: example} do
      example_with_inputs = Example.with_inputs(example, [:question, :context])
      inputs = Example.inputs(example_with_inputs)

      assert inputs == %{question: "What is 2+2?", context: "Basic math"}
    end

    test "labels/1 returns only non-input fields", %{example: example} do
      example_with_inputs = Example.with_inputs(example, [:question, :context])
      labels = Example.labels(example_with_inputs)

      assert labels == %{answer: "4", confidence: "high"}
    end

    test "inputs and labels are disjoint", %{example: example} do
      example_with_inputs = Example.with_inputs(example, [:question])
      inputs = Example.inputs(example_with_inputs)
      labels = Example.labels(example_with_inputs)

      input_keys = MapSet.new(Map.keys(inputs))
      label_keys = MapSet.new(Map.keys(labels))

      assert MapSet.disjoint?(input_keys, label_keys)
    end

    test "inputs and labels combined equal all data", %{example: example} do
      example_with_inputs = Example.with_inputs(example, [:question])
      inputs = Example.inputs(example_with_inputs)
      labels = Example.labels(example_with_inputs)

      combined = Map.merge(inputs, labels)
      assert combined == example.data
    end
  end

  describe "edge cases for Phase 1" do
    test "handles example with no designated inputs" do
      example = Example.new(%{answer: "42", confidence: "certain"})
      example_with_inputs = Example.with_inputs(example, [])

      assert Example.inputs(example_with_inputs) == %{}
      assert Example.labels(example_with_inputs) == %{answer: "42", confidence: "certain"}
    end

    test "handles example where all fields are inputs" do
      example = Example.new(%{question: "Test", context: "Context"})
      example_with_inputs = Example.with_inputs(example, [:question, :context])

      assert Example.inputs(example_with_inputs) == %{question: "Test", context: "Context"}
      assert Example.labels(example_with_inputs) == %{}
    end

    test "handles empty example" do
      example = Example.new(%{})
      example_with_inputs = Example.with_inputs(example, [])

      assert Example.inputs(example_with_inputs) == %{}
      assert Example.labels(example_with_inputs) == %{}
    end

    test "with_inputs overwrites previous input designation" do
      example = Example.new(%{a: 1, b: 2, c: 3})

      # First designation
      example1 = Example.with_inputs(example, [:a])
      assert MapSet.equal?(example1.input_keys, MapSet.new([:a]))

      # Second designation overwrites first
      example2 = Example.with_inputs(example1, [:b, :c])
      assert MapSet.equal?(example2.input_keys, MapSet.new([:b, :c]))
    end
  end

  describe "data structure immutability" do
    test "with_inputs returns new struct" do
      original = Example.new(%{test: "data"})
      modified = Example.with_inputs(original, [:test])

      refute original == modified
      assert MapSet.size(original.input_keys) == 0
      assert MapSet.size(modified.input_keys) == 1
    end

    test "original data is preserved" do
      original_data = %{question: "Original", answer: "Original"}
      example = Example.new(original_data)

      Example.with_inputs(example, [:question])

      # Original example data should be unchanged
      assert example.data == original_data
    end
  end
end
