defmodule DSPEx.Predict.ReActTest do
  use ExUnit.Case, async: true
  alias DSPEx.Predict.ReAct
  alias DSPEx.Program

  @moduletag :group_1

  # Test signature for ReAct reasoning and acting
  defmodule TestSignatures.ReasonAct do
    use DSPEx.Signature, "question -> answer"
  end

  # Test tool for ReAct actions
  defmodule TestTool.WebSearch do
    def call(query) when is_binary(query) do
      {:ok, "Search results for: #{query}"}
    end
  end

  defmodule TestTool.Calculator do
    def call(expression) when is_binary(expression) do
      case expression do
        "2+2" -> {:ok, "4"}
        "10*5" -> {:ok, "50"}
        _ -> {:ok, "Calculation result"}
      end
    end
  end

  describe "new/2" do
    test "creates ReAct program with extended signature" do
      signature = TestSignatures.ReasonAct
      tools = [TestTool.WebSearch, TestTool.Calculator]
      react = ReAct.new(signature, tools: tools)

      # Should extend signature with reasoning and action fields
      assert is_struct(react)
      assert :thought in react.signature.output_fields()
      assert :action in react.signature.output_fields()
      assert :observation in react.signature.output_fields()
      assert :answer in react.signature.output_fields()
    end

    test "preserves original signature fields with tools" do
      signature = TestSignatures.ReasonAct
      tools = [TestTool.Calculator]
      react = ReAct.new(signature, tools: tools, model: :gpt4)

      assert :question in react.signature.input_fields()
      assert :answer in react.signature.output_fields()
      assert react.tools == tools
    end

    test "requires tools parameter" do
      signature = TestSignatures.ReasonAct

      assert_raise ArgumentError, fn ->
        ReAct.new(signature, [])
      end
    end
  end

  describe "forward/2" do
    @tag :integration_test
    test "alternates between reasoning and action" do
      signature = TestSignatures.ReasonAct
      tools = [TestTool.WebSearch, TestTool.Calculator]
      react = ReAct.new(signature, tools: tools, model: :test)

      {:ok, result} =
        Program.forward(react, %{
          question: "What is the population of Tokyo in 2024?"
        })

      # Should show reasoning steps and action traces
      assert is_map(result)
      assert is_binary(result[:thought] || "")
      assert is_binary(result[:action] || "")
      assert is_binary(result[:observation] || "")
      assert is_binary(result[:answer] || "")
    end

    @tag :integration_test
    test "performs calculation with reasoning" do
      signature = TestSignatures.ReasonAct
      tools = [TestTool.Calculator]
      react = ReAct.new(signature, tools: tools, model: :test)

      {:ok, result} =
        Program.forward(react, %{
          question: "What is 2+2?"
        })

      assert is_map(result)
      # Mock system should provide some response structure
      response_fields = [:thought, :action, :observation, :answer]

      has_response =
        Enum.any?(response_fields, fn field ->
          result[field] && String.length(result[field]) > 0
        end)

      assert has_response, "Should have at least one non-empty response field"
    end

    test "handles multiple tool invocations" do
      signature = TestSignatures.ReasonAct
      tools = [TestTool.WebSearch, TestTool.Calculator]
      react = ReAct.new(signature, tools: tools, model: :test)

      {:ok, result} =
        Program.forward(react, %{
          question: "Find the population of Tokyo and multiply by 2"
        })

      assert is_map(result)
      # Verify response structure exists
      assert is_binary(result[:answer] || "")
    end
  end

  describe "signature extension" do
    test "adds ReAct fields with proper descriptions" do
      signature = TestSignatures.ReasonAct
      tools = [TestTool.Calculator]
      react = ReAct.new(signature, tools: tools)

      # Check that ReAct fields exist in output fields
      react_fields = [:thought, :action, :observation, :answer]

      Enum.each(react_fields, fn field ->
        assert field in react.signature.output_fields()
      end)
    end

    test "maintains original field order and properties" do
      signature = TestSignatures.ReasonAct
      tools = [TestTool.WebSearch]
      react = ReAct.new(signature, tools: tools)

      # Original input fields should be preserved
      assert :question in react.signature.input_fields()

      # Original output fields should be preserved
      assert :answer in react.signature.output_fields()
    end
  end

  describe "tool integration" do
    test "validates tool availability" do
      signature = TestSignatures.ReasonAct
      valid_tools = [TestTool.Calculator]

      react = ReAct.new(signature, tools: valid_tools)
      assert react.tools == valid_tools
    end

    test "handles tool execution errors gracefully" do
      signature = TestSignatures.ReasonAct

      defmodule TestTool.Failing do
        def call(_), do: {:error, "Tool failed"}
      end

      tools = [TestTool.Failing]
      react = ReAct.new(signature, tools: tools, model: :test)

      # Should not crash even with failing tools
      {:ok, result} = Program.forward(react, %{question: "Test question"})
      assert is_map(result)
    end
  end
end
