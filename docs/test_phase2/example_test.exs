defmodule DSPEx.ExampleTest do
  use ExUnit.Case, async: true

  describe "example creation" do
    @tag :phase2_features
    test "creates example with basic fields" do
      example = DSPEx.Example.new(%{question: "What is 2+2?", answer: "4"})

      # Dot notation requires custom Access implementation (Phase 2+ feature)
      assert example.question == "What is 2+2?"
      assert example.answer == "4"
    end

    @tag :phase2_features
    test "creates example from keyword list" do
      example = DSPEx.Example.new(question: "Test", answer: "Response")

      assert example.question == "Test"
      assert example.answer == "Response"
    end

    @tag :phase2_features 
    test "handles additional metadata fields" do
      example = DSPEx.Example.new(%{
        question: "What is the capital?",
        answer: "Paris",
        metadata: %{difficulty: "easy", topic: "geography"}
      })

      assert example.question == "What is the capital?"
      assert example.answer == "Paris"
      assert example.metadata.difficulty == "easy"
    end
  end

  describe "input/output field designation" do
    test "designates input fields explicitly" do
      example = DSPEx.Example.new(%{
        question: "What is 2+2?",
        context: "math problem",
        answer: "4"
      })

      example_with_inputs = DSPEx.Example.with_inputs(example, [:question, :context])

      inputs = DSPEx.Example.inputs(example_with_inputs)
      assert inputs == %{question: "What is 2+2?", context: "math problem"}

      labels = DSPEx.Example.labels(example_with_inputs)
      assert labels == %{answer: "4"}
    end

    test "infers output fields from remaining fields" do
      example = DSPEx.Example.new(%{
        question: "Test",
        context: "Some context",
        answer: "Response",
        confidence: "high"
      })

      example_with_inputs = DSPEx.Example.with_inputs(example, [:question, :context])

      labels = DSPEx.Example.labels(example_with_inputs)
      assert labels == %{answer: "Response", confidence: "high"}
    end

    test "handles empty input designation" do
      example = DSPEx.Example.new(%{answer: "42"})
      example_with_inputs = DSPEx.Example.with_inputs(example, [])

      inputs = DSPEx.Example.inputs(example_with_inputs)
      assert inputs == %{}

      labels = DSPEx.Example.labels(example_with_inputs)
      assert labels == %{answer: "42"}
    end
  end

  describe "example manipulation" do
    @tag :phase2_features
    test "copies example with additional fields" do
      original = DSPEx.Example.new(%{question: "Test", answer: "Response"})

      copied = DSPEx.Example.copy(original, %{confidence: "high", reasoning: "because"})

      assert copied.question == "Test"
      assert copied.answer == "Response"
      assert copied.confidence == "high"
      assert copied.reasoning == "because"

      # Original should be unchanged
      refute Map.has_key?(original, :confidence)
    end

    @tag :phase2_features
    test "removes fields from example" do
      example = DSPEx.Example.new(%{
        question: "Test",
        answer: "Response",
        metadata: "extra"
      })

      filtered = DSPEx.Example.without(example, [:metadata])

      assert filtered.question == "Test"
      assert filtered.answer == "Response"
      refute Map.has_key?(filtered, :metadata)
    end

    @tag :phase2_features
    test "converts to plain map" do
      example = DSPEx.Example.new(%{question: "Test", answer: "Response"})

      map = DSPEx.Example.to_map(example)

      assert map == %{question: "Test", answer: "Response"}
      assert is_map(map)
      refute is_struct(map)
    end
  end

  describe "example validation" do
    @tag :phase2_features
    test "validates required fields are present" do
      example = DSPEx.Example.new(%{question: "Test"})

      assert DSPEx.Example.has_field?(example, :question)
      refute DSPEx.Example.has_field?(example, :answer)
    end

    @tag :phase2_features
    test "validates field types" do
      example = DSPEx.Example.new(%{
        question: "Test",
        answer: "Response",
        score: 0.95,
        tags: ["test", "example"]
      })

      assert DSPEx.Example.get_field_type(example, :question) == :string
      assert DSPEx.Example.get_field_type(example, :score) == :number
      assert DSPEx.Example.get_field_type(example, :tags) == :list
    end
  end

  describe "example serialization" do
    @tag :phase2_features
    test "serializes to JSON" do
      example = DSPEx.Example.new(%{
        question: "What is 2+2?",
        answer: "4",
        metadata: %{difficulty: "easy"}
      })

      json = DSPEx.Example.to_json(example)
      parsed = Jason.decode!(json)

      assert parsed["question"] == "What is 2+2?"
      assert parsed["answer"] == "4"
      assert parsed["metadata"]["difficulty"] == "easy"
    end

    @tag :phase2_features
    test "deserializes from JSON" do
      json = """
      {
        "question": "What is the capital of France?",
        "answer": "Paris",
        "confidence": "high"
      }
      """

      example = DSPEx.Example.from_json(json)

      assert example.question == "What is the capital of France?"
      assert example.answer == "Paris"
      assert example.confidence == "high"
    end
  end

  describe "example equality and comparison" do
    @tag :phase2_features
    test "examples with same fields are equal" do
      example1 = DSPEx.Example.new(%{question: "Test", answer: "Response"})
      example2 = DSPEx.Example.new(%{question: "Test", answer: "Response"})

      assert DSPEx.Example.equal?(example1, example2)
    end

    @tag :phase2_features
    test "examples with different fields are not equal" do
      example1 = DSPEx.Example.new(%{question: "Test1", answer: "Response"})
      example2 = DSPEx.Example.new(%{question: "Test2", answer: "Response"})

      refute DSPEx.Example.equal?(example1, example2)
    end

    test "examples can be hashed for sets and maps" do
      example1 = DSPEx.Example.new(%{question: "Test", answer: "Response"})
      example2 = DSPEx.Example.new(%{question: "Test", answer: "Response"})
      example3 = DSPEx.Example.new(%{question: "Different", answer: "Response"})

      set = MapSet.new([example1, example2, example3])

      # Should have 2 unique examples (example1 == example2)
      assert MapSet.size(set) == 2
    end
  end
end
