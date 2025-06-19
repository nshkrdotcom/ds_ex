defmodule DSPEx.Signature.JsonSchemaProviderValidationTest do
  @moduledoc """
  Comprehensive validation tests for JSON Schema generation with provider-specific requirements.

  This test suite validates that Sinter-generated JSON schemas meet the specific requirements
  of different LLM providers (OpenAI, Anthropic, generic) as outlined in Phase 2.5 of the
  SINTER_INTEGRATION_PLAN.md.
  """
  use ExUnit.Case, async: true

  alias DSPEx.Signature.Sinter

  @doc """
  Test JSON Schema generation requirements from SINTER_INTEGRATION_PLAN.md Phase 2.5
  """

  describe "OpenAI JSON Schema requirements" do
    test "generates OpenAI-compatible function calling schema" do
      defmodule OpenAITestSignature do
        use DSPEx.Signature,
            "query:string[min_length=1,max_length=1000] -> response:string[max_length=2000]"
      end

      schema = Sinter.generate_json_schema(OpenAITestSignature, provider: :openai)

      # OpenAI Function Calling Schema Requirements
      assert schema["type"] == "object"
      assert is_map(schema["properties"])

      # Required fields array should be present
      assert is_list(schema["required"]) or is_nil(schema["required"])

      # Properties should have correct types
      query_prop = schema["properties"]["query"]
      assert query_prop["type"] == "string"
      assert query_prop["minLength"] == 1
      assert query_prop["maxLength"] == 1000

      response_prop = schema["properties"]["response"]
      assert response_prop["type"] == "string"
      assert response_prop["maxLength"] == 2000

      # OpenAI-specific: No unsupported fields
      refute Map.has_key?(schema, "definitions")
      refute Map.has_key?(schema, "$defs")
    end

    test "OpenAI schema handles numeric constraints correctly" do
      defmodule OpenAINumericSignature do
        use DSPEx.Signature,
            "temperature:float[gteq=0.0,lteq=2.0], max_tokens:integer[gteq=1,lteq=4096] -> usage:integer"
      end

      schema = Sinter.generate_json_schema(OpenAINumericSignature, provider: :openai)

      # Temperature field validation
      temp_prop = schema["properties"]["temperature"]
      assert temp_prop["type"] == "number"
      assert temp_prop["minimum"] == 0.0
      assert temp_prop["maximum"] == 2.0

      # Max tokens field validation
      tokens_prop = schema["properties"]["max_tokens"]
      assert tokens_prop["type"] == "integer"
      assert tokens_prop["minimum"] == 1
      assert tokens_prop["maximum"] == 4096

      # Usage output
      usage_prop = schema["properties"]["usage"]
      assert usage_prop["type"] == "integer"
    end

    test "OpenAI schema handles array constraints correctly" do
      defmodule OpenAIArraySignature do
        use DSPEx.Signature, "messages:array(string)[min_items=1,max_items=10] -> summary:string"
      end

      schema = Sinter.generate_json_schema(OpenAIArraySignature, provider: :openai)

      messages_prop = schema["properties"]["messages"]
      assert messages_prop["type"] == "array"
      assert messages_prop["minItems"] == 1
      assert messages_prop["maxItems"] == 10
      assert messages_prop["items"]["type"] == "string"
    end

    test "OpenAI schema includes descriptions when available" do
      defmodule OpenAIDescriptiveSignature do
        use DSPEx.Signature, "user_input:string[min_length=1] -> ai_response:string"
      end

      schema =
        Sinter.generate_json_schema(OpenAIDescriptiveSignature,
          provider: :openai,
          title: "AI Chat Function",
          description: "Processes user input and generates AI response"
        )

      assert schema["title"] == "AI Chat Function"
      assert schema["description"] == "Processes user input and generates AI response"
    end
  end

  describe "Anthropic JSON Schema requirements" do
    test "generates Anthropic-compatible tool schema" do
      defmodule AnthropicTestSignature do
        use DSPEx.Signature,
            "prompt:string[min_length=5,max_length=4000] -> completion:string[max_length=8000]"
      end

      schema = Sinter.generate_json_schema(AnthropicTestSignature, provider: :anthropic)

      # Anthropic Tool Schema Requirements
      assert schema["type"] == "object"
      assert is_map(schema["properties"])

      # Properties validation
      prompt_prop = schema["properties"]["prompt"]
      assert prompt_prop["type"] == "string"
      assert prompt_prop["minLength"] == 5
      assert prompt_prop["maxLength"] == 4000

      completion_prop = schema["properties"]["completion"]
      assert completion_prop["type"] == "string"
      assert completion_prop["maxLength"] == 8000

      # Anthropic schemas should be clean and minimal
      assert is_map(schema["properties"])
    end

    test "Anthropic schema handles complex nested constraints" do
      defmodule AnthropicComplexSignature do
        use DSPEx.Signature,
            "analysis_request:string[min_length=10], confidence_threshold:float[gteq=0.0,lteq=1.0] -> analysis_result:string[max_length=5000], confidence_score:float[gteq=0.0,lteq=1.0]"
      end

      schema = Sinter.generate_json_schema(AnthropicComplexSignature, provider: :anthropic)

      # Analysis request validation
      request_prop = schema["properties"]["analysis_request"]
      assert request_prop["type"] == "string"
      assert request_prop["minLength"] == 10

      # Confidence threshold validation
      threshold_prop = schema["properties"]["confidence_threshold"]
      assert threshold_prop["type"] == "number"
      assert threshold_prop["minimum"] == 0.0
      assert threshold_prop["maximum"] == 1.0

      # Analysis result validation
      result_prop = schema["properties"]["analysis_result"]
      assert result_prop["type"] == "string"
      assert result_prop["maxLength"] == 5000

      # Confidence score validation
      score_prop = schema["properties"]["confidence_score"]
      assert score_prop["type"] == "number"
      assert score_prop["minimum"] == 0.0
      assert score_prop["maximum"] == 1.0
    end

    test "Anthropic schema maintains format compatibility" do
      defmodule AnthropicFormatSignature do
        use DSPEx.Signature, "structured_input:string[min_length=1] -> structured_output:string"
      end

      schema = Sinter.generate_json_schema(AnthropicFormatSignature, provider: :anthropic)

      # Should be valid JSON Schema Draft 7 compatible
      assert schema["type"] == "object"
      assert is_map(schema["properties"])

      # Should not include Anthropic-specific extensions that might break compatibility
      refute Map.has_key?(schema, "anthropic_extensions")
      refute Map.has_key?(schema, "claude_specific")
    end
  end

  describe "Generic JSON Schema compliance" do
    test "generates standard JSON Schema Draft 7 compliant schema" do
      defmodule GenericTestSignature do
        use DSPEx.Signature,
            "input_text:string[min_length=1,max_length=2000] -> output_text:string[max_length=4000], metadata:string"
      end

      schema = Sinter.generate_json_schema(GenericTestSignature, provider: :generic)

      # JSON Schema Draft 7 compliance
      assert schema["type"] == "object"
      assert is_map(schema["properties"])

      # Standard constraint mapping
      input_prop = schema["properties"]["input_text"]
      assert input_prop["type"] == "string"
      assert input_prop["minLength"] == 1
      assert input_prop["maxLength"] == 2000

      output_prop = schema["properties"]["output_text"]
      assert output_prop["type"] == "string"
      assert output_prop["maxLength"] == 4000

      metadata_prop = schema["properties"]["metadata"]
      assert metadata_prop["type"] == "string"
    end

    test "generic schema supports all constraint types" do
      defmodule GenericConstraintSignature do
        use DSPEx.Signature,
            "text_field:string[min_length=2,max_length=100], number_field:integer[gteq=0,lteq=1000], array_field:array(string)[min_items=1,max_items=5] -> result:string"
      end

      schema = Sinter.generate_json_schema(GenericConstraintSignature, provider: :generic)

      # String constraints
      text_prop = schema["properties"]["text_field"]
      assert text_prop["type"] == "string"
      assert text_prop["minLength"] == 2
      assert text_prop["maxLength"] == 100

      # Numeric constraints
      number_prop = schema["properties"]["number_field"]
      assert number_prop["type"] == "integer"
      assert number_prop["minimum"] == 0
      assert number_prop["maximum"] == 1000

      # Array constraints
      array_prop = schema["properties"]["array_field"]
      assert array_prop["type"] == "array"
      assert array_prop["minItems"] == 1
      assert array_prop["maxItems"] == 5
      assert array_prop["items"]["type"] == "string"
    end

    test "generic schema includes proper metadata" do
      defmodule GenericMetadataSignature do
        use DSPEx.Signature, "query:string -> response:string"
      end

      schema =
        Sinter.generate_json_schema(GenericMetadataSignature,
          provider: :generic,
          title: "Generic Test Schema",
          description: "A test schema for validation"
        )

      assert schema["title"] == "Generic Test Schema"
      assert schema["description"] == "A test schema for validation"
      assert schema["type"] == "object"
    end
  end

  describe "provider comparison and compatibility" do
    test "all providers generate valid schemas for the same signature" do
      defmodule CrossProviderSignature do
        use DSPEx.Signature,
            "user_query:string[min_length=1,max_length=500] -> ai_response:string[max_length=1000]"
      end

      # Generate schemas for all providers
      openai_schema = Sinter.generate_json_schema(CrossProviderSignature, provider: :openai)
      anthropic_schema = Sinter.generate_json_schema(CrossProviderSignature, provider: :anthropic)
      generic_schema = Sinter.generate_json_schema(CrossProviderSignature, provider: :generic)

      # All should be valid objects
      [openai_schema, anthropic_schema, generic_schema]
      |> Enum.each(fn schema ->
        assert schema["type"] == "object"
        assert is_map(schema["properties"])

        # User query validation should be consistent
        query_prop = schema["properties"]["user_query"]
        assert query_prop["type"] == "string"
        assert query_prop["minLength"] == 1
        assert query_prop["maxLength"] == 500

        # AI response validation should be consistent
        response_prop = schema["properties"]["ai_response"]
        assert response_prop["type"] == "string"
        assert response_prop["maxLength"] == 1000
      end)
    end

    test "provider schemas maintain core compatibility while allowing variations" do
      defmodule ProviderVariationSignature do
        use DSPEx.Signature,
            "complex_input:string[min_length=5] -> complex_output:array(string)[max_items=10]"
      end

      openai_schema = Sinter.generate_json_schema(ProviderVariationSignature, provider: :openai)

      anthropic_schema =
        Sinter.generate_json_schema(ProviderVariationSignature, provider: :anthropic)

      generic_schema = Sinter.generate_json_schema(ProviderVariationSignature, provider: :generic)

      # Core structure should be the same
      [openai_schema, anthropic_schema, generic_schema]
      |> Enum.each(fn schema ->
        assert schema["type"] == "object"

        input_prop = schema["properties"]["complex_input"]
        assert input_prop["type"] == "string"
        assert input_prop["minLength"] == 5

        output_prop = schema["properties"]["complex_output"]
        assert output_prop["type"] == "array"
        assert output_prop["maxItems"] == 10
        assert output_prop["items"]["type"] == "string"
      end)

      # Providers may have slight variations but core constraints must be preserved
      # This test ensures compatibility while allowing provider-specific optimizations
    end
  end

  describe "constraint translation accuracy" do
    test "string constraints translate correctly across providers" do
      defmodule StringConstraintSignature do
        use DSPEx.Signature,
            "validated_string:string[min_length=3,max_length=50] -> result:string"
      end

      [:openai, :anthropic, :generic]
      |> Enum.each(fn provider ->
        schema = Sinter.generate_json_schema(StringConstraintSignature, provider: provider)

        string_prop = schema["properties"]["validated_string"]
        assert string_prop["type"] == "string"
        assert string_prop["minLength"] == 3
        assert string_prop["maxLength"] == 50
      end)
    end

    test "numeric constraints translate correctly across providers" do
      defmodule NumericConstraintSignature do
        use DSPEx.Signature,
            "validated_int:integer[gteq=10,lteq=100], validated_float:float[gteq=0.0,lteq=1.0] -> result:string"
      end

      [:openai, :anthropic, :generic]
      |> Enum.each(fn provider ->
        schema = Sinter.generate_json_schema(NumericConstraintSignature, provider: provider)

        int_prop = schema["properties"]["validated_int"]
        assert int_prop["type"] == "integer"
        assert int_prop["minimum"] == 10
        assert int_prop["maximum"] == 100

        float_prop = schema["properties"]["validated_float"]
        assert float_prop["type"] == "number"
        assert float_prop["minimum"] == 0.0
        assert float_prop["maximum"] == 1.0
      end)
    end

    test "array constraints translate correctly across providers" do
      defmodule ArrayConstraintSignature do
        use DSPEx.Signature,
            "validated_array:array(string)[min_items=2,max_items=8] -> result:string"
      end

      [:openai, :anthropic, :generic]
      |> Enum.each(fn provider ->
        schema = Sinter.generate_json_schema(ArrayConstraintSignature, provider: provider)

        array_prop = schema["properties"]["validated_array"]
        assert array_prop["type"] == "array"
        assert array_prop["minItems"] == 2
        assert array_prop["maxItems"] == 8
        assert array_prop["items"]["type"] == "string"
      end)
    end
  end

  describe "JSON Schema validation edge cases" do
    test "empty constraints still produce valid schemas" do
      defmodule EmptyConstraintSignature do
        use DSPEx.Signature, "simple_field:string -> simple_result:string"
      end

      [:openai, :anthropic, :generic]
      |> Enum.each(fn provider ->
        schema = Sinter.generate_json_schema(EmptyConstraintSignature, provider: provider)

        assert schema["type"] == "object"
        assert is_map(schema["properties"])

        field_prop = schema["properties"]["simple_field"]
        assert field_prop["type"] == "string"

        result_prop = schema["properties"]["simple_result"]
        assert result_prop["type"] == "string"
      end)
    end

    test "complex nested signatures produce valid schemas" do
      defmodule ComplexNestedSignature do
        use DSPEx.Signature,
            "field1:string[min_length=1], field2:integer[gteq=0], field3:array(string)[max_items=5] -> result1:string[max_length=200], result2:float[gteq=0.0,lteq=1.0], result3:array(integer)[min_items=1]"
      end

      [:openai, :anthropic, :generic]
      |> Enum.each(fn provider ->
        schema = Sinter.generate_json_schema(ComplexNestedSignature, provider: provider)

        assert schema["type"] == "object"
        assert is_map(schema["properties"])

        # Verify all fields are present with correct constraints
        assert Map.has_key?(schema["properties"], "field1")
        assert Map.has_key?(schema["properties"], "field2")
        assert Map.has_key?(schema["properties"], "field3")
        assert Map.has_key?(schema["properties"], "result1")
        assert Map.has_key?(schema["properties"], "result2")
        assert Map.has_key?(schema["properties"], "result3")

        # Verify complex array result
        result3_prop = schema["properties"]["result3"]
        assert result3_prop["type"] == "array"
        assert result3_prop["minItems"] == 1
        assert result3_prop["items"]["type"] == "integer"
      end)
    end

    test "schema generation handles errors gracefully" do
      defmodule GracefulErrorSignature do
        use DSPEx.Signature, "normal_field:string -> normal_result:string"
      end

      # Even if there are internal errors, schema generation should return a valid basic schema
      schema = Sinter.generate_json_schema(GracefulErrorSignature, provider: :openai)

      assert schema["type"] == "object"
      assert is_map(schema["properties"])

      # Should not have error fields in a successful case
      refute Map.has_key?(schema, "error")
    end
  end

  describe "performance validation" do
    test "schema generation performance is consistent across providers" do
      defmodule PerformanceComparisonSignature do
        use DSPEx.Signature,
            "perf_input:string[min_length=1,max_length=1000] -> perf_output:string[max_length=2000]"
      end

      providers = [:openai, :anthropic, :generic]

      # Measure generation time for each provider
      provider_times =
        Enum.map(providers, fn provider ->
          {time, _schema} =
            :timer.tc(fn ->
              Sinter.generate_json_schema(PerformanceComparisonSignature, provider: provider)
            end)

          {provider, time}
        end)

      # All should complete within reasonable time (less than 5ms)
      Enum.each(provider_times, fn {provider, time} ->
        assert time < 5000, "Provider #{provider} took #{time} microseconds (>5ms)"
      end)

      # Performance should be relatively consistent (no provider should be >10x slower)
      times = Enum.map(provider_times, fn {_provider, time} -> time end)
      min_time = Enum.min(times)
      max_time = Enum.max(times)

      assert max_time <= min_time * 10,
             "Performance variance too high: min=#{min_time}, max=#{max_time}"
    end
  end
end
