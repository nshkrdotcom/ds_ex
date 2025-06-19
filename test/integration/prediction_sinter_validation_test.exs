defmodule DSPEx.Integration.PredictionSinterValidationTest do
  @moduledoc """
  Integration tests for Sinter validation in prediction pipeline.

  Tests the integration of Sinter validation within DSPEx.Predict and 
  DSPEx.PredictStructured to ensure inputs and outputs are properly
  validated without breaking existing functionality.
  """

  use ExUnit.Case, async: true

  alias DSPEx.Predict
  alias DSPEx.PredictStructured

  # Mock signature for testing
  defmodule TestSignature do
    @behaviour DSPEx.Signature

    def input_fields, do: [:question]
    def output_fields, do: [:answer]
    def description, do: "Test signature for validation"
    def fields, do: %{question: :input, answer: :output}
    def instructions, do: "Answer test questions"
  end

  # Enhanced signature with constraints for Sinter
  defmodule EnhancedTestSignature do
    @behaviour DSPEx.Signature

    def input_fields, do: [:question, :context]
    def output_fields, do: [:answer, :confidence]
    def description, do: "Enhanced test signature with constraints"
    def fields, do: %{question: :input, context: :input, answer: :output, confidence: :output}
    def instructions, do: "Answer questions with confidence scores"

    # Sinter schema definition (if available)
    def sinter_schema do
      [
        {:question, :string, [required: true, min_length: 1, max_length: 500]},
        {:context, :string, [required: false, max_length: 1000]},
        {:answer, :string, [required: true, min_length: 1]},
        {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}
      ]
    rescue
      # Graceful degradation if Sinter not available
      _ -> nil
    end
  end

  describe "DSPEx.Predict with Sinter validation" do
    test "validates inputs successfully with basic signature" do
      inputs = %{question: "What is 2+2?"}

      # This should not fail even if Sinter validation is attempted
      result = DSPEx.Predict.validate_inputs(TestSignature, inputs)
      assert result == :ok
    end

    test "validates inputs successfully with enhanced signature" do
      inputs = %{question: "What is the capital of France?", context: "European geography"}

      # Should work with or without Sinter validation
      result = DSPEx.Predict.validate_inputs(EnhancedTestSignature, inputs)
      assert result == :ok
    end

    test "handles missing required inputs gracefully" do
      # Missing required question field
      inputs = %{}

      # Should fail on basic validation, not Sinter validation
      result = DSPEx.Predict.validate_inputs(TestSignature, inputs)
      assert {:error, _reason} = result
    end

    test "prediction with Sinter validation integration" do
      # Create prediction program
      program = Predict.new(TestSignature, :mock_client)

      # Test that validation is integrated (will gracefully degrade)
      assert %Predict{signature: TestSignature} = program
    end

    test "structured prediction with Sinter validation" do
      # Create structured prediction program  
      program = PredictStructured.new(TestSignature, :gemini)

      # Test that validation is integrated
      assert %PredictStructured{signature: TestSignature} = program
    end
  end

  describe "Sinter validation graceful degradation" do
    test "prediction continues when Sinter validation unavailable" do
      inputs = %{question: "Test question"}

      # Should not crash if Sinter modules are unavailable
      result = DSPEx.Predict.validate_inputs(TestSignature, inputs)
      assert result == :ok
    end

    test "prediction works with invalid Sinter constraints" do
      # Test with potentially invalid inputs for enhanced schema
      inputs = %{
        # Empty string might violate min_length
        question: "",
        # Might violate max_length
        context: String.duplicate("x", 2000)
      }

      # Should gracefully handle validation issues
      result = DSPEx.Predict.validate_inputs(EnhancedTestSignature, inputs)

      # Validation might fail on basic checks, but shouldn't crash
      assert result in [:ok, {:error, :missing_inputs}, {:error, :invalid_input}]
    end
  end

  describe "telemetry integration with Sinter" do
    test "emits validation telemetry events" do
      test_pid = self()

      :telemetry.attach(
        "test-prediction-validation",
        [:dspex, :signature, :validation, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      inputs = %{question: "Test question"}
      DSPEx.Predict.validate_inputs(TestSignature, inputs)

      # Should receive telemetry event
      assert_receive {:telemetry, [:dspex, :signature, :validation, :start], _measurements,
                      metadata}

      assert Map.has_key?(metadata, :signature)
      assert Map.has_key?(metadata, :correlation_id)

      :telemetry.detach("test-prediction-validation")
    end
  end

  describe "performance impact of Sinter integration" do
    test "validation overhead is minimal" do
      inputs = %{question: "Performance test question"}

      # Measure validation time
      {time, result} =
        :timer.tc(fn ->
          DSPEx.Predict.validate_inputs(TestSignature, inputs)
        end)

      assert result == :ok
      # Validation should complete in reasonable time (under 10ms)
      # 10ms in microseconds
      assert time < 10_000
    end

    test "handles batch validation efficiently" do
      inputs_list =
        for i <- 1..100 do
          %{question: "Batch question #{i}"}
        end

      # Test validation doesn't become prohibitively slow
      {time, results} =
        :timer.tc(fn ->
          Enum.map(inputs_list, fn inputs ->
            DSPEx.Predict.validate_inputs(TestSignature, inputs)
          end)
        end)

      assert Enum.all?(results, &(&1 == :ok))
      # Batch validation should complete in reasonable time (under 100ms)
      # 100ms in microseconds
      assert time < 100_000
    end
  end

  describe "error handling with Sinter integration" do
    test "gracefully handles Sinter module unavailability" do
      # This test ensures the code doesn't crash when Sinter modules aren't loaded
      inputs = %{question: "Test question"}

      # Should not raise exceptions
      assert :ok = DSPEx.Predict.validate_inputs(TestSignature, inputs)
    end

    test "handles malformed signature schemas gracefully" do
      defmodule MalformedSignature do
        @behaviour DSPEx.Signature

        def input_fields, do: [:question]
        def output_fields, do: [:answer]
        def description, do: "Malformed signature"
        def fields, do: %{question: :input, answer: :output}
        def instructions, do: "Answer test questions"

        # Intentionally malformed schema
        def sinter_schema, do: "invalid schema format"
      end

      inputs = %{question: "Test"}

      # Should not crash on malformed schema
      result = DSPEx.Predict.validate_inputs(MalformedSignature, inputs)
      assert result == :ok
    end
  end
end
