# Elixact-DSPEx Integration Guide

**The Complete Guide to Integrating Elixact's Advanced Schema Validation into DSPEx's AI Framework**

This guide provides comprehensive documentation for integrating Elixact's world-class validation library into DSPEx, enabling sophisticated AI/LLM workflows with robust schema validation, dynamic typing, and DSPy-style programming patterns.

## Table of Contents

- [Overview](#overview)
- [Architecture Integration](#architecture-integration)
- [Core Integration Components](#core-integration-components)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Implementation Roadmap](#implementation-roadmap)
- [Testing Strategy](#testing-strategy)
- [Migration Guide](#migration-guide)

## Overview

### What This Integration Provides

DSPEx + Elixact delivers:

- **World-Class Signatures**: Advanced schema validation with dynamic typing, field metadata, and LLM provider optimization
- **Validated Predict Modules**: Chain of Thought and ReACT with robust input/output validation and intelligent error recovery
- **Enhanced SIMBA Teleprompter**: Type-safe optimization with validated example management and performance tracking
- **Comprehensive Error Handling**: Intelligent repair of malformed LLM outputs with detailed error reporting
- **Provider Optimization**: LLM-specific schema generation and prompt optimization
- **Performance Monitoring**: Validation metrics and optimization tracking

### Integration Philosophy

This integration follows these principles:

1. **Validation First**: Every data structure is validated at creation and transformation
2. **Type Safety**: Compile-time and runtime type checking throughout the pipeline
3. **Intelligent Recovery**: Automatic repair of common LLM output issues
4. **Provider Agnostic**: Works seamlessly with OpenAI, Anthropic, Google, and other providers
5. **Performance Focused**: Optimized validation with caching and batch processing
6. **Developer Experience**: Clear error messages and comprehensive tooling

## Architecture Integration

### High-Level Architecture

```
DSPEx + Elixact Integration
├── Signature System (lib/dspex/signature/)
│   ├── TypedSignature (Enhanced with Elixact)
│   ├── Elixact Integration (Schema generation & validation)
│   └── Enhanced Parser (LLM output parsing with repair)
├── Predict Modules (lib/dspex/predict/)
│   ├── BasePredictorWithElixact (Foundation)
│   ├── ChainOfThought (CoT with validation)
│   └── ReACT (Reasoning + Acting with validation)
├── Teleprompter (lib/dspex/teleprompter/)
│   └── SIMBA (Enhanced with Elixact validation)
├── Configuration (lib/dspex/config/)
│   ├── ElixactConfig (Validation configurations)
│   └── Schemas (Predefined validation schemas)
└── Evaluation (lib/dspex/evaluate/)
    └── Enhanced metrics with validation
```

### Integration Points

1. **Signature Creation**: Elixact schemas replace basic field definitions
2. **Input Validation**: All inputs validated before LLM calls
3. **Output Validation**: LLM outputs validated with intelligent repair
4. **Example Management**: Training examples validated and type-safe
5. **Performance Tracking**: Metrics validated for consistency
6. **Configuration**: All configuration validated at startup

## Core Integration Components

### 1. Enhanced Signature System

The signature system is the foundation of the integration, providing:

- Dynamic schema generation from field definitions
- LLM provider-specific optimization
- Intelligent output parsing and repair
- Rich metadata support for DSPy-style programming

**Key Files:**
- `lib/dspex/signature/elixact.ex` - Core Elixact integration
- `lib/dspex/signature/typed_signature.ex` - Enhanced signature macro
- `lib/dspex/signature/enhanced_parser.ex` - Output parsing with repair

### 2. Validated Predict Modules

Enhanced predict modules with comprehensive validation:

- Input validation before LLM calls
- Multi-step validation for complex reasoning
- Intelligent output repair for malformed responses
- Performance monitoring and optimization

**Key Files:**
- `lib/dspex/predict/base_predictor.ex` - Foundation with Elixact
- `lib/dspex/predict/chain_of_thought.ex` - CoT with step validation
- `lib/dspex/predict/react.ex` - ReACT with action validation

### 3. Enhanced SIMBA Teleprompter

Type-safe optimization with validated components:

- Example validation and scoring
- Performance metrics validation
- Strategy optimization with constraints
- Bucket management with capacity controls

**Key Files:**
- `lib/dspex/teleprompter/simba.ex` - Main SIMBA module
- `lib/dspex/teleprompter/simba/strategy.ex` - Strategy with validation
- `lib/dspex/teleprompter/simba/performance.ex` - Performance tracking
- `lib/dspex/teleprompter/simba/bucket.ex` - Example management

### 4. Configuration Management

Centralized configuration with validation:

- Provider-specific settings
- Validation configurations
- Schema definitions
- Performance tuning parameters

**Key Files:**
- `lib/dspex/config/elixact_config.ex` - Configuration management
- `lib/dspex/config/schemas/` - Predefined schemas
- `lib/dspex/config/validator.ex` - Configuration validation

## Quick Start

### 1. Basic Signature Definition

```elixir
defmodule MyApp.Signatures.QuestionAnswering do
  use DSPEx.Signature.TypedSignature
  
  signature "Answer questions with reasoning" do
    input :question, :string,
      description: "The question to answer",
      required: true,
      min_length: 5,
      max_length: 500
      
    input :context, :string,
      description: "Additional context",
      optional: true
      
    output :answer, :string,
      description: "The answer to the question",
      required: true,
      min_length: 10
      
    output :reasoning, :string,
      description: "Step-by-step reasoning",
      required: true,
      min_length: 20
      
    output :confidence, :float,
      description: "Confidence score",
      required: true,
      gteq: 0.0,
      lteq: 1.0
  end
end
```

### 2. Chain of Thought Prediction

```elixir
# Create predictor with validation
predictor = DSPEx.Predict.ChainOfThought.new(
  MyApp.Signatures.QuestionAnswering,
  client: :openai,
  reasoning_steps: 3,
  step_validation: true
)

# Make prediction with automatic validation
input = %{
  question: "What is the capital of France?",
  context: "We're discussing European geography."
}

case DSPEx.Predict.ChainOfThought.predict(predictor, input) do
  {:ok, result} ->
    IO.puts("Answer: #{result.answer}")
    IO.puts("Confidence: #{result.confidence}")
    IO.inspect(result.reasoning_chain)
    
  {:error, {:input_validation_failed, errors}} ->
    IO.puts("Input validation failed:")
    Enum.each(errors, &IO.puts("  - #{&1.message}"))
    
  {:error, {:output_validation_failed, errors}} ->
    IO.puts("Output validation failed (after repair attempts):")
    Enum.each(errors, &IO.puts("  - #{&1.message}"))
end
```

### 3. SIMBA Optimization

```elixir
# Create SIMBA teleprompter
simba = DSPEx.Teleprompter.Simba.new(
  MyApp.Signatures.QuestionAnswering,
  strategy_name: "qa_optimizer"
)

# Prepare training data
training_data = %{
  examples: [
    %{
      input: %{question: "What is 2+2?", context: "Basic math"},
      output: %{answer: "4", reasoning: "Adding 2 and 2 gives 4", confidence: 0.99}
    },
    # ... more examples
  ]
}

# Compile and optimize
case DSPEx.Teleprompter.Simba.compile(simba, training_data) do
  {:ok, optimized_simba} ->
    # Use optimized predictor
    {:ok, result} = DSPEx.Teleprompter.Simba.predict(optimized_simba, input)
    IO.puts("Optimized answer: #{result.answer}")
    
  {:error, reason} ->
    IO.puts("Optimization failed: #{inspect(reason)}")
end
```

## Configuration

### Elixact Configuration

```elixir
# config/config.exs
config :dspex, DSPEx.Config.ElixactConfig,
  # Global validation settings
  strict_mode: true,
  auto_repair: true,
  max_repair_attempts: 3,
  
  # Provider-specific settings
  providers: %{
    openai: %{
      schema_format: :json_schema,
      repair_strategies: [:type_coercion, :field_completion],
      timeout_ms: 30_000
    },
    anthropic: %{
      schema_format: :structured_output,
      repair_strategies: [:type_coercion, :format_fixing],
      timeout_ms: 45_000
    }
  },
  
  # Performance settings
  validation_cache_size: 1000,
  batch_validation_size: 50,
  
  # Development settings
  debug_validation: Mix.env() == :dev,
  log_validation_errors: true
```

### Schema Definitions

```elixir
# lib/dspex/config/schemas/common_schemas.ex
defmodule DSPEx.Config.Schemas.CommonSchemas do
  def confidence_score_schema do
    Elixact.Runtime.create_schema([
      {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}
    ], title: "Confidence_Score")
  end
  
  def reasoning_step_schema do
    Elixact.Runtime.create_schema([
      {:step_number, :integer, [required: true, gt: 0]},
      {:observation, :string, [required: true, min_length: 10]},
      {:reasoning, :string, [required: true, min_length: 20]},
      {:conclusion, :string, [required: true, min_length: 5]},
      {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}
    ], title: "Reasoning_Step")
  end
end
```

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

1. **Core Integration Setup**
   - [ ] Implement `DSPEx.Signature.Elixact` module
   - [ ] Enhance `TypedSignature` macro with Elixact support
   - [ ] Create `ElixactConfig` configuration system
   - [ ] Set up basic validation pipeline

2. **Basic Signature System**
   - [ ] Field definition with Elixact schemas
   - [ ] Input/output validation
   - [ ] Basic error handling
   - [ ] Schema generation for LLM prompts

### Phase 2: Predict Modules (Week 3-4)

1. **Base Predictor Enhancement**
   - [ ] Implement `BasePredictorWithElixact`
   - [ ] Input validation before LLM calls
   - [ ] Output validation with basic repair
   - [ ] Retry logic with validation

2. **Chain of Thought Integration**
   - [ ] Step-by-step validation
   - [ ] Reasoning chain validation
   - [ ] Multi-step error recovery
   - [ ] Quality assessment

3. **ReACT Integration**
   - [ ] Action validation
   - [ ] Tool parameter validation
   - [ ] Observation validation
   - [ ] Iteration management

### Phase 3: SIMBA Enhancement (Week 5-6)

1. **Strategy Validation**
   - [ ] Example validation and scoring
   - [ ] Strategy parameter validation
   - [ ] Optimization constraint validation
   - [ ] Performance metric validation

2. **Bucket Management**
   - [ ] Type-safe example storage
   - [ ] Capacity management
   - [ ] Selection strategy validation
   - [ ] Quality threshold enforcement

3. **Performance Tracking**
   - [ ] Metric validation and consistency
   - [ ] Trend analysis
   - [ ] Benchmark comparison
   - [ ] Recommendation generation

### Phase 4: Advanced Features (Week 7-8)

1. **Intelligent Output Repair**
   - [ ] Type coercion strategies
   - [ ] Format fixing
   - [ ] Field completion
   - [ ] JSON structure repair

2. **Provider Optimization**
   - [ ] OpenAI schema optimization
   - [ ] Anthropic structured output
   - [ ] Google Gemini integration
   - [ ] Custom provider support

3. **Performance Optimization**
   - [ ] Validation caching
   - [ ] Batch processing
   - [ ] Parallel validation
   - [ ] Memory optimization

### Phase 5: Testing & Documentation (Week 9-10)

1. **Comprehensive Testing**
   - [ ] Unit tests for all modules
   - [ ] Integration tests
   - [ ] Property-based testing
   - [ ] Performance benchmarks

2. **Documentation**
   - [ ] API documentation
   - [ ] Usage examples
   - [ ] Migration guides
   - [ ] Best practices

## Testing Strategy

### Unit Testing

```elixir
defmodule DSPEx.Signature.ElixactTest do
  use ExUnit.Case
  
  describe "signature validation" do
    test "validates input with correct types" do
      signature = create_test_signature()
      input = %{question: "Test question", context: "Test context"}
      
      assert {:ok, validated} = DSPEx.Signature.Elixact.validate_input(signature, input)
      assert validated.question == "Test question"
    end
    
    test "rejects invalid input types" do
      signature = create_test_signature()
      input = %{question: 123, context: "Test context"}  # Invalid type
      
      assert {:error, errors} = DSPEx.Signature.Elixact.validate_input(signature, input)
      assert Enum.any?(errors, &(&1.code == :type))
    end
  end
end
```

### Integration Testing

```elixir
defmodule DSPEx.Integration.ChainOfThoughtTest do
  use ExUnit.Case
  
  test "end-to-end chain of thought with validation" do
    predictor = DSPEx.Predict.ChainOfThought.new(TestSignature)
    input = %{question: "What is machine learning?"}
    
    {:ok, result} = DSPEx.Predict.ChainOfThought.predict(predictor, input)
    
    assert is_binary(result.answer)
    assert is_list(result.reasoning_chain)
    assert is_float(result.confidence)
    assert result.confidence >= 0.0 and result.confidence <= 1.0
  end
end
```

### Property-Based Testing

```elixir
defmodule DSPEx.Property.ValidationTest do
  use ExUnit.Case
  use PropCheck
  
  property "all valid inputs pass validation" do
    forall input <- valid_input_generator() do
      signature = create_test_signature()
      {:ok, _} = DSPEx.Signature.Elixact.validate_input(signature, input)
    end
  end
  
  property "invalid inputs always fail validation" do
    forall input <- invalid_input_generator() do
      signature = create_test_signature()
      {:error, _} = DSPEx.Signature.Elixact.validate_input(signature, input)
    end
  end
end
```

## Migration Guide

### From Basic DSPEx to Elixact Integration

1. **Update Signature Definitions**

   Before:
   ```elixir
   defmodule MySignature do
     use DSPEx.Signature
     
     signature "My signature" do
       input "question", "The question"
       output "answer", "The answer"
     end
   end
   ```

   After:
   ```elixir
   defmodule MySignature do
     use DSPEx.Signature.TypedSignature
     
     signature "My signature" do
       input :question, :string,
         description: "The question",
         required: true,
         min_length: 5
         
       output :answer, :string,
         description: "The answer",
         required: true,
         min_length: 10
     end
   end
   ```

2. **Update Predict Module Usage**

   Before:
   ```elixir
   predictor = DSPEx.Predict.ChainOfThought.new(MySignature)
   {:ok, result} = DSPEx.Predict.ChainOfThought.predict(predictor, input)
   ```

   After:
   ```elixir
   predictor = DSPEx.Predict.ChainOfThought.new(MySignature, step_validation: true)
   
   case DSPEx.Predict.ChainOfThought.predict(predictor, input) do
     {:ok, result} -> handle_success(result)
     {:error, {:input_validation_failed, errors}} -> handle_input_errors(errors)
     {:error, {:output_validation_failed, errors}} -> handle_output_errors(errors)
   end
   ```

3. **Update Configuration**

   Add Elixact configuration to your `config/config.exs`:
   ```elixir
   config :dspex, DSPEx.Config.ElixactConfig,
     strict_mode: true,
     auto_repair: true,
     providers: %{
       openai: %{schema_format: :json_schema}
     }
   ```

This comprehensive integration guide provides the foundation for building robust, validated AI applications with DSPEx and Elixact. The combination delivers world-class schema validation, intelligent error recovery, and optimized performance for production AI systems. 