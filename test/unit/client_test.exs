defmodule DSPEx.ClientTest do
  @moduledoc """
  Unit tests for DSPEx.Client basic HTTP functionality.
  Tests message validation, request building, and error handling.
  """
  use ExUnit.Case, async: true

  describe "request/2 message validation" do
    test "rejects empty message list" do
      assert {:error, :invalid_messages} = DSPEx.Client.request([])
    end

    test "rejects messages missing role" do
      messages = [%{content: "hello"}]
      assert {:error, :invalid_messages} = DSPEx.Client.request(messages)
    end

    test "rejects messages missing content" do
      messages = [%{role: "user"}]
      assert {:error, :invalid_messages} = DSPEx.Client.request(messages)
    end

    test "rejects messages with non-string role" do
      messages = [%{role: 123, content: "hello"}]
      assert {:error, :invalid_messages} = DSPEx.Client.request(messages)
    end

    test "rejects messages with non-string content" do
      messages = [%{role: "user", content: 456}]
      assert {:error, :invalid_messages} = DSPEx.Client.request(messages)
    end

    test "rejects non-map messages" do
      messages = ["not a map"]
      assert {:error, :invalid_messages} = DSPEx.Client.request(messages)
    end

    @tag :external_api
    @tag :external_api
    test "accepts valid messages with extra fields" do
      messages = [%{role: "user", content: "hello", extra: "field"}]

      # Should pass validation and may succeed or fail depending on API availability
      case DSPEx.Client.request(messages) do
        {:ok, response} ->
          # API is working - verify response structure
          assert %{choices: choices} = response
          assert is_list(choices)
          assert length(choices) > 0

        {:error, reason} ->
          # API is not available - verify error types
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "accepts multiple valid messages" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"},
        %{role: "user", content: "How are you?"}
      ]

      # Should pass validation and may succeed or fail depending on API availability
      case DSPEx.Client.request(messages) do
        {:ok, response} ->
          # API is working - verify response structure
          assert %{choices: choices} = response
          assert is_list(choices)
          assert length(choices) > 0

        {:error, reason} ->
          # API is not available - verify error types
          assert reason in [:network_error, :api_error, :timeout]
      end
    end
  end

  describe "request/2 with options" do
    @tag :external_api
    @tag :external_api
    test "accepts custom model option" do
      messages = [%{role: "user", content: "Hello"}]
      options = %{model: "different-model"}

      # Should pass validation with custom options
      case DSPEx.Client.request(messages, options) do
        {:ok, response} ->
          assert %{choices: choices} = response
          assert is_list(choices)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    @tag :external_api
    test "accepts custom temperature option" do
      messages = [%{role: "user", content: "Hello"}]
      options = %{temperature: 0.5}

      case DSPEx.Client.request(messages, options) do
        {:ok, response} ->
          assert %{choices: choices} = response
          assert is_list(choices)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "accepts custom max_tokens option" do
      messages = [%{role: "user", content: "Hello"}]
      options = %{max_tokens: 100}

      case DSPEx.Client.request(messages, options) do
        {:ok, response} ->
          assert %{choices: choices} = response
          assert is_list(choices)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "accepts all options together" do
      messages = [%{role: "user", content: "Hello"}]

      options = %{
        model: "different-model",
        temperature: 0.2,
        max_tokens: 50
      }

      case DSPEx.Client.request(messages, options) do
        {:ok, response} ->
          assert %{choices: choices} = response
          assert is_list(choices)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "uses defaults when no options provided" do
      messages = [%{role: "user", content: "Hello"}]

      # Should use default options
      case DSPEx.Client.request(messages) do
        {:ok, response} ->
          assert %{choices: choices} = response
          assert is_list(choices)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end
  end

  describe "error categorization" do
    @tag :external_api
    @tag :external_api
    test "returns consistent error types" do
      messages = [%{role: "user", content: "Hello"}]

      # Should either succeed or return categorized errors
      case DSPEx.Client.request(messages) do
        {:ok, response} ->
          assert %{choices: choices} = response
          assert is_list(choices)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    test "validation errors take precedence over network errors" do
      # Invalid messages should fail validation before attempting network calls
      # missing content
      invalid_messages = [%{role: "user"}]

      assert {:error, :invalid_messages} = DSPEx.Client.request(invalid_messages)
    end
  end
end
