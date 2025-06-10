defmodule DSPEx.PredictTest do
  @moduledoc """
  Unit tests for DSPEx.Predict module orchestration.
  Tests prediction pipeline, input validation, and error handling.
  """
  use ExUnit.Case, async: true

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

  describe "forward/2 and forward/3" do
    test "validates inputs before processing" do
      # missing required question field
      inputs = %{}

      assert {:error, :missing_inputs} = DSPEx.Predict.forward(MockSignature, inputs)
    end

    @tag :external_api
    test "accepts valid inputs and attempts prediction" do
      inputs = %{question: "What is 2+2?"}

      # Should pass input validation and may succeed or fail depending on API availability
      case DSPEx.Predict.forward(MockSignature, inputs) do
        {:ok, outputs} ->
          # API is working - verify output structure
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          # API is not available - verify error types
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "forwards options to client" do
      inputs = %{question: "What is 2+2?"}
      options = %{model: "different-model", temperature: 0.5}

      # Should pass input validation and forward options
      case DSPEx.Predict.forward(MockSignature, inputs, options) do
        {:ok, outputs} ->
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "handles multi-field signatures" do
      inputs = %{question: "What is AI?", context: "Computer science"}

      case DSPEx.Predict.forward(MultiFieldSignature, inputs) do
        {:ok, outputs} ->
          # Should have at least answer field for multi-field signature
          assert Map.has_key?(outputs, :answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    test "returns error for invalid signature" do
      inputs = %{question: "test"}

      assert {:error, :invalid_signature} = DSPEx.Predict.forward(InvalidSignature, inputs)
    end
  end

  describe "predict_field/3 and predict_field/4" do
    test "validates field exists in signature" do
      # We can't test successful field extraction without mocking the full pipeline,
      # but we can test the error path for input validation
      # missing required field
      inputs = %{}

      assert {:error, :missing_inputs} =
               DSPEx.Predict.predict_field(MockSignature, inputs, :answer)
    end

    @tag :external_api
    test "passes through prediction errors" do
      inputs = %{question: "What is 2+2?"}

      # Should either succeed or fail gracefully
      case DSPEx.Predict.predict_field(MockSignature, inputs, :answer) do
        {:ok, answer} ->
          assert is_binary(answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    @tag :external_api
    test "accepts options parameter" do
      inputs = %{question: "What is 2+2?"}
      options = %{temperature: 0.2}

      case DSPEx.Predict.predict_field(MockSignature, inputs, :answer, options) do
        {:ok, answer} ->
          assert is_binary(answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end
  end

  describe "validate_inputs/2" do
    test "returns :ok for valid inputs" do
      inputs = %{question: "What is 2+2?"}

      assert :ok = DSPEx.Predict.validate_inputs(MockSignature, inputs)
    end

    test "returns error for missing required inputs" do
      # missing question
      inputs = %{}

      assert {:error, :missing_inputs} = DSPEx.Predict.validate_inputs(MockSignature, inputs)
    end

    test "returns error for invalid signature" do
      inputs = %{question: "test"}

      assert {:error, :invalid_signature} =
               DSPEx.Predict.validate_inputs(InvalidSignature, inputs)
    end

    test "validates multi-field signatures" do
      # Valid case
      inputs = %{question: "What is AI?", context: "Computer science"}
      assert :ok = DSPEx.Predict.validate_inputs(MultiFieldSignature, inputs)

      # Missing field case
      # missing context
      incomplete_inputs = %{question: "What is AI?"}

      assert {:error, :missing_inputs} =
               DSPEx.Predict.validate_inputs(MultiFieldSignature, incomplete_inputs)
    end

    test "accepts extra input fields" do
      inputs = %{question: "What is 2+2?", extra: "field"}

      assert :ok = DSPEx.Predict.validate_inputs(MockSignature, inputs)
    end
  end

  describe "describe_signature/1" do
    test "returns signature field information" do
      assert {:ok, description} = DSPEx.Predict.describe_signature(MockSignature)

      assert %{
               inputs: [:question],
               outputs: [:answer],
               description: "Answer the question"
             } = description
    end

    test "handles multi-field signatures" do
      assert {:ok, description} = DSPEx.Predict.describe_signature(MultiFieldSignature)

      assert %{
               inputs: [:question, :context],
               outputs: [:answer, :reasoning],
               description: "Answer with reasoning"
             } = description
    end

    test "returns error for invalid signature" do
      assert {:error, :invalid_signature} = DSPEx.Predict.describe_signature(InvalidSignature)
    end

    test "handles signature without description" do
      defmodule NoDescSignature do
        def input_fields, do: [:input]
        def output_fields, do: [:output]
      end

      assert {:ok, description} = DSPEx.Predict.describe_signature(NoDescSignature)
      assert %{description: "No description available"} = description
    end
  end

  describe "error propagation" do
    test "propagates adapter formatting errors" do
      # This will cause missing_inputs error in adapter
      inputs = %{}

      assert {:error, :missing_inputs} = DSPEx.Predict.forward(MockSignature, inputs)
    end

    test "propagates signature validation errors" do
      inputs = %{question: "test"}

      assert {:error, :invalid_signature} = DSPEx.Predict.forward(InvalidSignature, inputs)
    end

    @tag :external_api
    @tag :external_api
    test "propagates client errors" do
      inputs = %{question: "What is 2+2?"}

      # With valid inputs, should either succeed or get categorized errors
      case DSPEx.Predict.forward(MockSignature, inputs) do
        {:ok, outputs} ->
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          assert reason in [:network_error, :api_error, :timeout]
      end
    end
  end

  describe "integration with existing modules" do
    @tag :external_api
    test "uses DSPEx.Adapter for message formatting" do
      inputs = %{question: "What is 2+2?"}

      # This tests that the integration calls work end-to-end
      case DSPEx.Predict.forward(MockSignature, inputs) do
        {:ok, outputs} ->
          # Full pipeline working - verify structure
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          # API not available - verify error handling
          assert reason in [:network_error, :api_error, :timeout]
      end
    end

    @tag :external_api
    test "uses DSPEx.Client for HTTP requests" do
      inputs = %{question: "What is 2+2?"}

      # This tests the full client integration
      case DSPEx.Predict.forward(MockSignature, inputs) do
        {:ok, outputs} ->
          # Client layer working - verify response
          assert %{answer: answer} = outputs
          assert is_binary(answer)

        {:error, reason} ->
          # Client errors are categorized properly
          assert reason in [:network_error, :api_error, :timeout]
      end
    end
  end
end
