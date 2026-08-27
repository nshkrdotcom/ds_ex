defmodule DSPEx.ClientLLMModuleTest do
  use ExUnit.Case

  defmodule StubLLMSuccess do
    def generate_object(model, prompt, schema, opts) do
      send(self(), {:generate_object, model, prompt, schema, opts})
      {:ok, %{object: %{answer: "stubbed"}, usage: %{provider: model}}}
    end

    def embed(model, texts, opts) do
      send(self(), {:embed, model, texts, opts})
      {:ok, [[0.1, 0.2]]}
    end
  end

  defmodule StubLLMError do
    def generate_object(model, _prompt, _schema, _opts) do
      send(self(), {:generate_object_error, model})
      {:error, :boom}
    end

    def embed(model, texts, _opts) do
      send(self(), {:embed_error, model, texts})
      {:error, :explode}
    end
  end

  test "request in live mode uses injected llm module" do
    {:ok, response} =
      DSPEx.Client.request(
        %{prompt: "hi", schema: %{}, output_fields: [:answer]},
        mode: :live,
        llm_module: StubLLMSuccess,
        model: "google:gemini-1.5-flash"
      )

    assert response.object[:answer] == "stubbed"

    assert_received {:generate_object, "google:gemini-1.5-flash", "hi", %{}, opts}
    assert Keyword.get(opts, :llm_module) == StubLLMSuccess
  end

  test "fallback mode uses mock outputs when llm returns error" do
    {:ok, response} =
      DSPEx.Client.request(
        %{prompt: "hi", schema: %{}, output_fields: [:answer]},
        mode: :fallback,
        llm_module: StubLLMError
      )

    assert response.object[:answer] == "mock_answer"
    assert_received {:generate_object_error, _model}
  end

  test "embed live mode uses injected llm module" do
    {:ok, [vec]} =
      DSPEx.Client.embed(
        ["hello"],
        mode: :live,
        llm_module: StubLLMSuccess,
        model: "custom:model"
      )

    assert vec == [0.1, 0.2]
    assert_received {:embed, "custom:model", ["hello"], opts}
    assert Keyword.get(opts, :llm_module) == StubLLMSuccess
  end

  test "embed fallback uses mock when llm errors" do
    {:ok, [vec]} =
      DSPEx.Client.embed(
        ["hi"],
        mode: :fallback,
        dimensions: 4,
        mock_embedding: [1.0, 2.0, 3.0, 4.0],
        llm_module: StubLLMError,
        model: "custom:model"
      )

    assert vec == [1.0, 2.0, 3.0, 4.0]
    assert_received {:embed_error, "custom:model", ["hi"]}
  end
end
