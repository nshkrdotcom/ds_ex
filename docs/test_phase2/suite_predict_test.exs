defmodule DSPEx.PredictSuiteTest do
  use ExUnit.Case, async: false
  
  @moduletag :phase2_features

  defmodule QASignature do
    @moduledoc "Question answering signature"
    use DSPEx.Signature, "question -> answer"
  end

  defmodule MockClient do
    def request(_client, _request) do
      {:ok, %{
        choices: [%{message: %{content: "[[ ## answer ## ]]\nParis"}}],
        usage: %{prompt_tokens: 10, completion_tokens: 3}
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

  describe "prediction initialization" do
    test "creates predict with signature", %{client: client} do
      predict = DSPEx.Predict.new(QASignature, client: client)

      assert predict.signature_module == QASignature
      assert predict.client == client
      assert predict.adapter == DSPEx.Adapter.Chat
      assert predict.demos == []
    end

    test "accepts custom adapter", %{client: client} do
      predict = DSPEx.Predict.new(QASignature,
        client: client,
        adapter: DSPEx.Adapter.JSON
      )

      assert predict.adapter == DSPEx.Adapter.JSON
    end

    test "accepts initial demos", %{client: client} do
      demo = DSPEx.Example.new(%{question: "Test?", answer: "Yes"})
      predict = DSPEx.Predict.new(QASignature,
        client: client,
        demos: [demo]
      )

      assert predict.demos == [demo]
    end
  end

  describe "forward prediction" do
    test "makes successful prediction", %{client: client} do
      predict = DSPEx.Predict.new(QASignature, client: client)

      result = DSPEx.Predict.forward(predict, %{question: "What is the capital of France?"})

      assert {:ok, prediction} = result
      assert prediction.answer == "Paris"
      assert prediction.usage.prompt_tokens == 10
      assert prediction.usage.completion_tokens == 3
    end

    test "validates input fields", %{client: client} do
      predict = DSPEx.Predict.new(QASignature, client: client)

      result = DSPEx.Predict.forward(predict, %{wrong_field: "test"})

      assert {:error, {:missing_inputs, [:question]}} = result
    end

    test "includes demos in request", %{client: client} do
      demo = DSPEx.Example.new(%{question: "What is 1+1?", answer: "2"})
      predict = DSPEx.Predict.new(QASignature, client: client, demos: [demo])

      # Mock adapter to verify demos are included
      defmodule TestAdapter do
        def format(signature, inputs, demos) do
          send(self(), {:format_called, signature, inputs, demos})
          [%{role: "user", content: "test"}]
        end

        def parse(_signature, response) do
          {:ok, %{answer: "test"}}
        end
      end

      predict = %{predict | adapter: TestAdapter}
      DSPEx.Predict.forward(predict, %{question: "Test?"})

      assert_received {:format_called, QASignature, %{question: "Test?"}, [^demo]}
    end
  end

  describe "batch prediction" do
    test "processes multiple inputs", %{client: client} do
      predict = DSPEx.Predict.new(QASignature, client: client)

      inputs = [
        %{question: "What is 1+1?"},
        %{question: "What is 2+2?"},
        %{question: "What is 3+3?"}
      ]

      results = DSPEx.Predict.batch(predict, inputs)

      assert length(results) == 3
      Enum.each(results, fn result ->
        assert {:ok, prediction} = result
        assert prediction.answer
      end)
    end

    test "handles partial failures in batch", %{client: client} do
      defmodule FailingClient do
        def request(_client, request) do
          case request.messages do
            [%{content: content}] when content =~ "fail" ->
              {:error, :api_error}
            _ ->
              {:ok, %{
                choices: [%{message: %{content: "[[ ## answer ## ]]\nSuccess"}}],
                usage: %{prompt_tokens: 5, completion_tokens: 2}
              }}
          end
        end
      end

      predict = DSPEx.Predict.new(QASignature, client: {FailingClient, nil})

      inputs = [
        %{question: "This will succeed"},
        %{question: "This will fail"},
        %{question: "This will also succeed"}
      ]

      results = DSPEx.Predict.batch(predict, inputs)

      assert length(results) == 3
      assert {:ok, _} = Enum.at(results, 0)
      assert {:error, _} = Enum.at(results, 1)
      assert {:ok, _} = Enum.at(results, 2)
    end
  end

  describe "demo management" do
    test "adds demos to existing predict", %{client: client} do
      predict = DSPEx.Predict.new(QASignature, client: client)
      demo = DSPEx.Example.new(%{question: "Test?", answer: "Yes"})

      updated_predict = DSPEx.Predict.add_demo(predict, demo)

      assert updated_predict.demos == [demo]
      assert predict.demos == []  # Original unchanged
    end

    test "limits number of demos", %{client: client} do
      predict = DSPEx.Predict.new(QASignature, client: client, max_demos: 2)

      demos = [
        DSPEx.Example.new(%{question: "Q1?", answer: "A1"}),
        DSPEx.Example.new(%{question: "Q2?", answer: "A2"}),
        DSPEx.Example.new(%{question: "Q3?", answer: "A3"})
      ]

      updated_predict = Enum.reduce(demos, predict, &DSPEx.Predict.add_demo(&2, &1))

      assert length(updated_predict.demos) == 2
      # Should keep most recent demos
      assert Enum.at(updated_predict.demos, 0).question == "Q2?"
      assert Enum.at(updated_predict.demos, 1).question == "Q3?"
    end

    test "clears all demos", %{client: client} do
      demo = DSPEx.Example.new(%{question: "Test?", answer: "Yes"})
      predict = DSPEx.Predict.new(QASignature, client: client, demos: [demo])

      cleared_predict = DSPEx.Predict.clear_demos(predict)

      assert cleared_predict.demos == []
    end
  end
end
