defmodule DSPEx.ChainOfThoughtTest do
  use ExUnit.Case, async: false

  defmodule COTSignature do
    @moduledoc "Chain of thought reasoning signature"
    use DSPEx.Signature, "question -> reasoning, answer"
  end

  defmodule MockClient do
    def request(_client, _request) do
      {:ok, %{
        choices: [%{message: %{content: """
        [[ ## reasoning ## ]]
        Let me think step by step. First, I need to understand what 2+2 means.
        This is basic arithmetic. 2 plus 2 equals 4.

        [[ ## answer ## ]]
        4
        """}}],
        usage: %{prompt_tokens: 20, completion_tokens: 15}
      }}
    end
  end

  setup do
    {:ok, client} = start_supervised({DSPEx.Client, %{
      api_key: "test",
      model: "test",
      adapter: MockClient
    }})

    %{client: client}
  end

  describe "chain of thought initialization" do
    test "creates COT program with reasoning signature", %{client: client} do
      cot = DSPEx.ChainOfThought.new(COTSignature, client: client)

      assert cot.signature_module == COTSignature
      assert cot.client == client
    end

    test "accepts string signature", %{client: client} do
      cot = DSPEx.ChainOfThought.new("question -> reasoning, answer", client: client)

      # Should create dynamic signature
      assert is_atom(cot.signature_module)
    end
  end

  describe "chain of thought reasoning" do
    test "generates reasoning and answer", %{client: client} do
      cot = DSPEx.ChainOfThought.new(COTSignature, client: client)

      result = DSPEx.ChainOfThought.forward(cot, %{question: "What is 2+2?"})

      assert {:ok, prediction} = result
      assert String.contains?(prediction.reasoning, "step by step")
      assert String.contains?(prediction.reasoning, "arithmetic")
      assert prediction.answer == "4"
    end

    test "validates input requirements", %{client: client} do
      cot = DSPEx.ChainOfThought.new(COTSignature, client: client)

      result = DSPEx.ChainOfThought.forward(cot, %{wrong_field: "test"})

      assert {:error, {:missing_inputs, [:question]}} = result
    end

    test "includes reasoning in few-shot examples", %{client: client} do
      demo = %DSPEx.Example{
        question: "What is 1+1?",
        reasoning: "This is basic addition. 1 plus 1 equals 2.",
        answer: "2"
      }

      cot = DSPEx.ChainOfThought.new(COTSignature, client: client, demos: [demo])

      # Mock adapter to verify reasoning is included
      defmodule TestAdapter do
        def format(signature, inputs, demos) do
          send(self(), {:format_called, signature, inputs, demos})
          [%{role: "user", content: "test"}]
        end

        def parse(_signature, response) do
          {:ok, %{reasoning: "test reasoning", answer: "test"}}
        end
      end

      cot = %{cot | adapter: TestAdapter}
      DSPEx.ChainOfThought.forward(cot, %{question: "Test?"})

      assert_received {:format_called, COTSignature, %{question: "Test?"}, [demo]}

      # Verify demo includes reasoning
      assert demo.reasoning == "This is basic addition. 1 plus 1 equals 2."
    end
  end

  describe "reasoning quality" do
    test "produces structured reasoning steps" do
      defmodule StructuredMockClient do
        def request(_client, _request) do
          {:ok, %{
            choices: [%{message: %{content: """
            [[ ## reasoning ## ]]
            Step 1: Identify the problem type - This is a mathematical addition problem.
            Step 2: Apply addition rules - When adding 2 + 2, we combine the values.
            Step 3: Calculate the result - 2 + 2 = 4.

            [[ ## answer ## ]]
            4
            """}}],
            usage: %{prompt_tokens: 25, completion_tokens: 20}
          }}
        end
      end

      {:ok, client} = start_supervised({DSPEx.Client, %{
        api_key: "test",
        model: "structured_test",
        adapter: StructuredMockClient
      }}, id: :structured_client)

      cot = DSPEx.ChainOfThought.new(COTSignature, client: client)

      result = DSPEx.ChainOfThought.forward(cot, %{question: "What is 2+2?"})

      assert {:ok, prediction} = result
      assert String.contains?(prediction.reasoning, "Step 1:")
      assert String.contains?(prediction.reasoning, "Step 2:")
      assert String.contains?(prediction.reasoning, "Step 3:")
      assert prediction.answer == "4"
    end
  end

  describe "chain of thought optimization" do
    test "reasoning improves with examples" do
      # This would test that COT with good examples produces better reasoning
      # Implementation would depend on quality metrics for reasoning
    end

    test "supports reasoning-focused teleprompters" do
      # Test integration with teleprompters that optimize reasoning quality
      # Rather than just final answer accuracy
    end
  end
end
