defmodule DSPEx.AdapterSuiteTest do
  use ExUnit.Case, async: true
  
  @moduletag :phase2_features

  defmodule TestSignature do
    @moduledoc "Test signature for adapter tests"
    use DSPEx.Signature, "question, context -> answer, confidence"
  end

  describe "chat adapter formatting" do
    test "formats basic signature with inputs" do
      inputs = %{question: "What is the capital of France?", context: "European geography"}
      demos = []

      messages = DSPEx.Adapter.Chat.format(TestSignature, inputs, demos)

      assert length(messages) == 2
      assert [system_msg, user_msg] = messages

      assert system_msg.role == "system"
      assert String.contains?(system_msg.content, "Test signature for adapter tests")
      assert String.contains?(system_msg.content, "question")
      assert String.contains?(system_msg.content, "answer")

      assert user_msg.role == "user"
      assert String.contains?(user_msg.content, "What is the capital of France?")
      assert String.contains?(user_msg.content, "European geography")
    end

    test "includes few-shot examples in formatting" do
      inputs = %{question: "What is 2+2?", context: "math"}
      demos = [
        DSPEx.Example.new(%{
          question: "What is 1+1?",
          context: "basic math",
          answer: "2",
          confidence: "high"
        })
      ]

      messages = DSPEx.Adapter.Chat.format(TestSignature, inputs, demos)

      # Should have system + demo (user+assistant) + current user
      assert length(messages) == 4

      # Check demo is included
      demo_user = Enum.at(messages, 1)
      demo_assistant = Enum.at(messages, 2)

      assert demo_user.role == "user"
      assert String.contains?(demo_user.content, "What is 1+1?")

      assert demo_assistant.role == "assistant"
      assert String.contains?(demo_assistant.content, "answer: 2")
      assert String.contains?(demo_assistant.content, "confidence: high")
    end

    test "handles empty inputs gracefully" do
      messages = DSPEx.Adapter.Chat.format(TestSignature, %{}, [])

      assert length(messages) == 2
      assert [_system_msg, user_msg] = messages
      assert user_msg.content != ""
    end
  end

  describe "chat adapter parsing" do
    test "parses well-formatted response" do
      response_text = """
      Let me think about this step by step.

      [[ ## answer ## ]]
      Paris

      [[ ## confidence ## ]]
      high
      """

      result = DSPEx.Adapter.Chat.parse(TestSignature, response_text)

      assert {:ok, parsed} = result
      assert parsed.answer == "Paris"
      assert parsed.confidence == "high"
    end

    test "handles missing fields" do
      response_text = """
      [[ ## answer ## ]]
      Paris
      """

      result = DSPEx.Adapter.Chat.parse(TestSignature, response_text)

      assert {:error, reason} = result
      assert reason =~ "missing"
      assert reason =~ "confidence"
    end

    test "parses response with extra text" do
      response_text = """
      Here's my analysis of the question.

      [[ ## answer ## ]]
      Paris

      [[ ## confidence ## ]]
      high

      This is based on my knowledge of geography.
      """

      result = DSPEx.Adapter.Chat.parse(TestSignature, response_text)

      assert {:ok, parsed} = result
      assert parsed.answer == "Paris"
      assert parsed.confidence == "high"
    end

    test "handles malformed field markers" do
      response_text = """
      ## answer ##
      Paris

      [confidence]
      high
      """

      result = DSPEx.Adapter.Chat.parse(TestSignature, response_text)
      assert {:error, _reason} = result
    end
  end

  describe "JSON adapter" do
    test "formats signature for JSON output" do
      inputs = %{question: "What is the capital?"}

      messages = DSPEx.Adapter.JSON.format(TestSignature, inputs, [])

      assert length(messages) == 2
      assert [system_msg, _user_msg] = messages

      # System message should include JSON schema
      assert String.contains?(system_msg.content, "JSON")
      assert String.contains?(system_msg.content, "answer")
      assert String.contains?(system_msg.content, "confidence")
    end

    test "parses valid JSON response" do
      response_text = """
      {
        "answer": "Paris",
        "confidence": "high"
      }
      """

      result = DSPEx.Adapter.JSON.parse(TestSignature, response_text)

      assert {:ok, parsed} = result
      assert parsed.answer == "Paris"
      assert parsed.confidence == "high"
    end

    test "handles invalid JSON" do
      response_text = """
      {
        "answer": "Paris"
        "confidence": high
      }
      """

      result = DSPEx.Adapter.JSON.parse(TestSignature, response_text)
      assert {:error, _reason} = result
    end

    test "validates required fields in JSON" do
      response_text = """
      {
        "answer": "Paris"
      }
      """

      result = DSPEx.Adapter.JSON.parse(TestSignature, response_text)
      assert {:error, reason} = result
      assert reason =~ "confidence"
    end
  end
end
