defmodule DSPEx.AdapterTest do
  @moduledoc """
  Unit tests for DSPEx.Adapter message formatting and response parsing.
  Tests conversion between signatures and LLM API messages.
  """
  use ExUnit.Case, async: true

  @moduletag :phase_1

  # Mock signature for testing
  defmodule MockSignature do
    def input_fields, do: [:question]
    def output_fields, do: [:answer]
    def description, do: "Answer the question"
  end

  defmodule MultiFieldSignature do
    def input_fields, do: [:question, :context]
    def output_fields, do: [:answer, :reasoning]
    def description, do: "Answer with reasoning"
  end

  defmodule NoDescriptionSignature do
    def input_fields, do: [:input]
    def output_fields, do: [:output]
  end

  describe "format_messages/2" do
    test "formats simple signature with single input" do
      inputs = %{question: "What is 2+2?"}

      assert {:ok, messages} = DSPEx.Adapter.format_messages(MockSignature, inputs)
      assert [%{role: "user", content: content}] = messages
      assert content =~ "Answer the question"
      assert content =~ "question: What is 2+2?"
    end

    test "formats signature with multiple inputs" do
      inputs = %{question: "What is AI?", context: "Computer science topic"}

      assert {:ok, messages} = DSPEx.Adapter.format_messages(MultiFieldSignature, inputs)
      assert [%{role: "user", content: content}] = messages
      assert content =~ "Answer with reasoning"
      assert content =~ "question: What is AI?"
      assert content =~ "context: Computer science topic"
    end

    test "handles signature without description" do
      inputs = %{input: "test"}

      assert {:ok, messages} = DSPEx.Adapter.format_messages(NoDescriptionSignature, inputs)
      assert [%{role: "user", content: content}] = messages
      assert content =~ "Please process the following input"
      assert content =~ "input: test"
    end

    test "returns error for missing required inputs" do
      # missing question field
      inputs = %{}

      assert {:error, :missing_inputs} = DSPEx.Adapter.format_messages(MockSignature, inputs)
    end

    test "returns error for invalid signature" do
      inputs = %{question: "test"}

      assert {:error, :invalid_signature} =
               DSPEx.Adapter.format_messages(InvalidSignature, inputs)
    end

    test "accepts extra input fields" do
      inputs = %{question: "What is 2+2?", extra: "field"}

      assert {:ok, messages} = DSPEx.Adapter.format_messages(MockSignature, inputs)
      assert [%{role: "user", content: content}] = messages
      assert content =~ "question: What is 2+2?"
      # Extra fields are ignored for now
    end
  end

  describe "parse_response/2" do
    test "parses response with single output field" do
      response = %{choices: [%{message: %{content: "The answer is 4"}}]}

      assert {:ok, outputs} = DSPEx.Adapter.parse_response(MockSignature, response)
      assert %{answer: "The answer is 4"} = outputs
    end

    test "parses response with multiple output fields from multiple lines" do
      response = %{choices: [%{message: %{content: "4\nBecause 2+2=4"}}]}

      assert {:ok, outputs} = DSPEx.Adapter.parse_response(MultiFieldSignature, response)
      assert %{answer: "4", reasoning: "Because 2+2=4"} = outputs
    end

    test "handles insufficient lines for multiple outputs" do
      response = %{choices: [%{message: %{content: "Just one line"}}]}

      assert {:ok, outputs} = DSPEx.Adapter.parse_response(MultiFieldSignature, response)
      # Should fall back to putting all text in first field
      assert %{answer: "Just one line"} = outputs
    end

    test "trims whitespace from response" do
      response = %{choices: [%{message: %{content: "  The answer is 4  \n"}}]}

      assert {:ok, outputs} = DSPEx.Adapter.parse_response(MockSignature, response)
      assert %{answer: "The answer is 4"} = outputs
    end

    test "returns error for empty choices" do
      response = %{choices: []}

      assert {:error, :invalid_response} = DSPEx.Adapter.parse_response(MockSignature, response)
    end

    test "returns error for malformed response" do
      # missing content
      response = %{choices: [%{message: %{}}]}

      assert {:error, :invalid_response} = DSPEx.Adapter.parse_response(MockSignature, response)
    end

    test "returns error for invalid signature" do
      response = %{choices: [%{message: %{content: "test"}}]}

      assert {:error, :invalid_signature} =
               DSPEx.Adapter.parse_response(InvalidSignature, response)
    end

    test "handles non-string content" do
      response = %{choices: [%{message: %{content: 123}}]}

      assert {:error, :invalid_response} = DSPEx.Adapter.parse_response(MockSignature, response)
    end
  end

  describe "input validation" do
    test "validates all required fields present" do
      inputs = %{question: "test", context: "additional"}

      assert {:ok, _messages} = DSPEx.Adapter.format_messages(MultiFieldSignature, inputs)
    end

    test "reports missing fields" do
      # missing context
      inputs = %{question: "test"}

      assert {:error, :missing_inputs} =
               DSPEx.Adapter.format_messages(MultiFieldSignature, inputs)
    end

    test "handles empty input map" do
      inputs = %{}

      assert {:error, :missing_inputs} = DSPEx.Adapter.format_messages(MockSignature, inputs)
    end
  end
end
