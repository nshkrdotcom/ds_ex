defmodule DSPEx.Unit.SinterErrorReportingTest do
  @moduledoc """
  Unit tests for enhanced error reporting with Sinter integration.
  """

  use ExUnit.Case, async: true

  # Mock signature for testing
  defmodule TestSignature do
    @behaviour DSPEx.Signature

    def input_fields, do: [:question]
    def output_fields, do: [:answer]
    def description, do: "Test signature for error reporting"
    def fields, do: %{question: :input, answer: :output}
    def instructions, do: "Answer test questions"
  end

  describe "Sinter validation graceful degradation" do
    test "prediction validation handles missing Sinter module gracefully" do
      inputs = %{question: "Test question"}

      # This should not crash even if Sinter validation is attempted
      result = DSPEx.Predict.validate_inputs(TestSignature, inputs)
      assert result == :ok
    end
  end

  describe "Performance impact of validation integration" do
    @tag :slow
    test "validation integration has minimal overhead" do
      inputs = %{question: "Performance test"}

      # Measure validation time
      {time, result} =
        :timer.tc(fn ->
          DSPEx.Predict.validate_inputs(TestSignature, inputs)
        end)

      assert result == :ok
      # Should complete very quickly (under 1ms)
      # 1ms in microseconds
      assert time < 1000
    end
  end
end
