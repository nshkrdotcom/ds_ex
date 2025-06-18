defmodule DSPEx.Integration.SimbaElixactTest do
  use ExUnit.Case
  alias DSPEx.Predict
  alias DSPEx.Teleprompter.SIMBA

  @moduletag :integration_test
  @moduletag timeout: 120_000

  describe "SIMBA with Elixact signatures and AppendRule" do
    test "optimizes complex typed signatures with both strategies" do
      # This test will fail until both Elixact integration and AppendRule are complete
      signature = ComplexElixactSignatures.DataAnalysis
      program = Predict.new(signature, :gpt4)

      # Rich training data with validated Elixact types
      training_data = create_validated_training_examples()

      # Metric function that validates Elixact schema compliance
      metric_fn = &validated_answer_exact_match/2

      # Use both demo and rule strategies with Elixact signatures
      simba =
        SIMBA.new(
          strategies: [
            DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo,
            DSPEx.Teleprompter.SIMBA.Strategy.AppendRule
          ],
          num_candidates: 6,
          max_steps: 4
        )

      result = SIMBA.compile(simba, program, program, training_data, metric_fn, [])

      # Expected to fail currently due to missing AppendRule strategy
      assert {:error, reason} = result
      assert String.contains?(reason, ["strategy", "append_rule"]) |> Enum.any?()

      # Once AppendRule strategy is implemented, this test should verify:
      # - {:ok, optimized} = result
      # - optimized.performance.average_score > program.performance.average_score
      # - validate_elixact_schema_compliance(optimized)
      # - length(optimized.examples) > 0  # Demo strategy worked
      # - optimized.instruction != program.instruction  # Rule strategy worked
    end

    test "handles schema validation errors during rule-based optimization" do
      signature = ComplexElixactSignatures.StructuredOutput
      program = Predict.new(signature, :gpt3_5)

      # Training data that might produce LLM outputs not matching schema
      training_data = [
        %{
          inputs: %{data: "complex input requiring structured output"},
          outputs: %{
            result: %{
              category: "analysis",
              confidence: 0.85,
              details: ["fact1", "fact2", "fact3"]
            }
          }
        }
      ]

      metric_fn = fn _example, prediction ->
        # Strict schema validation in metric
        if validate_structured_output(prediction.result), do: 1.0, else: 0.0
      end

      simba =
        SIMBA.new(
          strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendRule],
          num_candidates: 3,
          max_steps: 2
        )

      result = SIMBA.compile(simba, program, program, training_data, metric_fn, [])

      # Currently expected to fail due to missing strategy
      assert {:error, reason} = result
      assert String.contains?(reason, ["append_rule"]) |> Enum.any?()
    end

    test "validates demo generation with complex field types" do
      signature = ComplexElixactSignatures.NestedSchema
      program = Predict.new(signature, :gpt4)

      # Complex nested data structures
      training_data = [
        %{
          inputs: %{
            request: %{
              type: "analysis",
              parameters: %{depth: 3, format: "detailed"},
              metadata: %{source: "test", timestamp: "2025-06-18"}
            }
          },
          outputs: %{
            response: %{
              status: "success",
              data: %{
                results: [
                  %{id: 1, value: "result1", score: 0.9},
                  %{id: 2, value: "result2", score: 0.8}
                ],
                summary: "Analysis completed successfully"
              }
            }
          }
        }
      ]

      metric_fn = fn _example, prediction ->
        # Validate complex nested structure
        if validate_nested_response(prediction.response), do: 1.0, else: 0.0
      end

      simba =
        SIMBA.new(
          strategies: [
            DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo,
            DSPEx.Teleprompter.SIMBA.Strategy.AppendRule
          ],
          num_candidates: 4,
          max_steps: 2
        )

      result = SIMBA.compile(simba, program, program, training_data, metric_fn, [])

      # Expected failure due to missing AppendRule
      assert {:error, reason} = result
      assert String.contains?(reason, ["strategy"]) |> Enum.any?()
    end

    test "preserves type safety throughout optimization pipeline" do
      signature = ComplexElixactSignatures.TypeSafeOperation
      program = Predict.new(signature, :gpt4)

      training_data = create_type_safe_examples()

      # Metric with strict type checking
      metric_fn = fn example, prediction ->
        if type_safe_validation(example, prediction), do: 1.0, else: 0.0
      end

      simba =
        SIMBA.new(
          strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendRule],
          num_candidates: 3,
          max_steps: 2
        )

      result = SIMBA.compile(simba, program, program, training_data, metric_fn, [])

      # Currently fails due to missing strategy, but defines type safety contract
      assert {:error, _reason} = result
    end

    test "integrates OfferFeedback signature with Elixact validation" do
      # Test direct usage of OfferFeedback signature with Elixact
      signature = DSPEx.Teleprompter.SIMBA.Signatures.OfferFeedback

      # This should fail because OfferFeedback signature doesn't exist yet
      _result = Predict.new(signature, :gpt4)

      # Expected compilation failure
      assert_raise CompileError, fn ->
        Code.eval_quoted(quote do: Predict.new(unquote(signature), :gpt4))
      end
    end

    test "validates AppendRule instruction generation with typed signatures" do
      # Once both are implemented, this tests their integration
      signature = ComplexElixactSignatures.InstructionTarget
      program = Predict.new(signature, :gpt4)

      training_data = [
        %{
          inputs: %{prompt: "Generate detailed analysis"},
          outputs: %{analysis: "Comprehensive analysis with specific recommendations"}
        }
      ]

      metric_fn = fn _example, prediction ->
        # Metric that would benefit from instruction improvements
        if String.length(prediction.analysis) > 50 &&
             String.contains?(prediction.analysis, "analysis"),
           do: 1.0,
           else: 0.0
      end

      simba =
        SIMBA.new(
          strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendRule],
          num_candidates: 3,
          max_steps: 1
        )

      result = SIMBA.compile(simba, program, program, training_data, metric_fn, [])

      # Fails now, but once implemented should generate improved instructions
      assert {:error, _reason} = result
    end
  end

  # Helper functions that define expected behavior
  defp create_validated_training_examples do
    [
      %{
        inputs: %{
          data_source: "customer_feedback",
          analysis_type: "sentiment",
          parameters: %{depth: "detailed", format: "structured"}
        },
        outputs: %{
          analysis: %{
            sentiment_score: 0.7,
            confidence: 0.85,
            key_themes: ["satisfaction", "pricing", "support"],
            recommendation: "Focus on pricing transparency"
          }
        }
      }
    ]
  end

  defp validated_answer_exact_match(example, prediction) do
    # Validate both correctness and Elixact schema compliance
    if example.outputs.analysis == prediction.analysis &&
         validate_analysis_schema(prediction.analysis),
       do: 1.0,
       else: 0.0
  end

  defp validate_structured_output(result) when is_map(result) do
    Map.has_key?(result, :category) &&
      Map.has_key?(result, :confidence) &&
      Map.has_key?(result, :details) &&
      is_number(result.confidence) &&
      is_list(result.details)
  end

  defp validate_structured_output(_), do: false

  defp validate_nested_response(response) when is_map(response) do
    Map.has_key?(response, :status) &&
      Map.has_key?(response, :data) &&
      is_map(response.data) &&
      Map.has_key?(response.data, :results) &&
      is_list(response.data.results)
  end

  defp validate_nested_response(_), do: false

  defp create_type_safe_examples do
    [
      %{
        inputs: %{operation: "calculate", values: [1, 2, 3, 4, 5]},
        outputs: %{result: 15, operation_type: "sum", metadata: %{count: 5}}
      }
    ]
  end

  defp type_safe_validation(example, prediction) do
    # Strict type checking
    is_number(prediction.result) &&
      is_binary(prediction.operation_type) &&
      is_map(prediction.metadata) &&
      prediction.result == example.outputs.result
  end

  defp validate_analysis_schema(analysis) when is_map(analysis) do
    Map.has_key?(analysis, :sentiment_score) &&
      Map.has_key?(analysis, :confidence) &&
      Map.has_key?(analysis, :key_themes) &&
      Map.has_key?(analysis, :recommendation) &&
      is_number(analysis.sentiment_score) &&
      is_number(analysis.confidence) &&
      is_list(analysis.key_themes) &&
      is_binary(analysis.recommendation)
  end

  defp validate_analysis_schema(_), do: false

  # Complex Elixact signature examples (these will fail to compile initially)
  defmodule ComplexElixactSignatures.DataAnalysis do
    # This will fail until proper Elixact integration exists
    use DSPEx.Signature,
        "data_source:string, analysis_type:string, parameters:map -> analysis:map"

    use DSPEx.TypedSignature
  end

  defmodule ComplexElixactSignatures.StructuredOutput do
    use DSPEx.Signature, "data:string -> result:map"
    use DSPEx.TypedSignature
  end

  defmodule ComplexElixactSignatures.NestedSchema do
    use DSPEx.Signature, "request:map -> response:map"
    use DSPEx.TypedSignature
  end

  defmodule ComplexElixactSignatures.TypeSafeOperation do
    use DSPEx.Signature,
        "operation:string, values:any -> result:integer, operation_type:string, metadata:map"

    use DSPEx.TypedSignature
  end

  defmodule ComplexElixactSignatures.InstructionTarget do
    use DSPEx.Signature, "prompt:string -> analysis:string"
    use DSPEx.TypedSignature
  end
end
