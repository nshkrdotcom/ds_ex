# DSPEx Signature System with Elixact Integration

This guide covers integrating Elixact's validation capabilities into DSPEx's signature system for robust AI/LLM interactions.

## Overview

DSPEx's signature system leverages Elixact to provide:
- Type Safety with compile-time and runtime validation
- Dynamic schema generation for adaptive AI workflows  
- LLM provider optimization (OpenAI, Anthropic, etc.)
- Rich metadata with DSPy-style field annotations
- Intelligent error handling and LLM output repair

## Basic Signature Definition

```elixir
defmodule MyApp.Signatures.QuestionAnswering do
  use DSPEx.Signature.TypedSignature
  
  signature "Answer questions with reasoning" do
    input :question, :string,
      description: "The question to answer",
      required: true,
      min_length: 5
    
    input :context, :string,
      description: "Relevant context",
      required: true,
      min_length: 10
    
    output :reasoning, :string,
      description: "Step-by-step reasoning",
      required: true,
      min_length: 20
    
    output :answer, :string,
      description: "Direct answer",
      required: true,
      min_length: 1
    
    output :confidence, :float,
      description: "Confidence 0.0-1.0",
      required: true,
      gteq: 0.0,
      lteq: 1.0
    
    instruction "Answer based on context with reasoning"
    provider :openai
  end
end
```

## Field Metadata for DSPy Integration

```elixir
signature "DSPy integration example" do
  input :query, :string,
    extra: %{
      "__dspy_field_type" => "input",
      "prefix" => "Query:",
      "format_hints" => ["concise"]
    }
  
  output :reasoning, :string,
    extra: %{
      "__dspy_field_type" => "output", 
      "prefix" => "Reasoning:",
      "format_hints" => ["step-by-step"],
      "render_as" => "markdown"
    }
end
```

## Runtime Schema Generation

```elixir
def create_adaptive_signature(task_description, sample_input, sample_output) do
  input_fields = infer_input_fields(sample_input)
  output_fields = infer_output_fields(sample_output)
  
  DSPEx.Signature.new(input_fields, output_fields,
    instruction: generate_instruction(task_description),
    provider: :openai,
    examples: [%{input: sample_input, output: sample_output}]
  )
end
```

## Validation Pipeline

```elixir
def validate_input(signature, input_data) do
  config = DSPEx.Config.ElixactConfig.dspy_signature_config(signature.provider)
  Elixact.EnhancedValidator.validate(signature.input_schema, input_data, config: config)
end

def validate_output(signature, output_data) do
  config = DSPEx.Config.ElixactConfig.llm_output_config(signature.provider)
  
  case Elixact.EnhancedValidator.validate(signature.output_schema, output_data, config: config) do
    {:ok, validated} -> {:ok, validated}
    {:error, errors} -> attempt_output_repair(signature, output_data, errors)
  end
end
```

## Provider Optimization

```elixir
def generate_provider_schema(signature, provider) do
  case provider do
    :openai -> 
      Elixact.JsonSchema.EnhancedResolver.resolve_enhanced(
        signature.output_schema,
        optimize_for_provider: :openai,
        function_calling_mode: true
      )
    :anthropic ->
      Elixact.JsonSchema.EnhancedResolver.resolve_enhanced(
        signature.output_schema,
        optimize_for_provider: :anthropic,
        tool_use_mode: true
      )
  end
end
```

This signature system provides the foundation for robust, type-safe AI applications with comprehensive validation and intelligent error recovery. 