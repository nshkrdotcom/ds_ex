# DSPEx Staged Implementation Plan with Test-Driven Development

## Overview

IMPORTANT: the tests for this context are initially placed in `dspex/test/suite`.

This plan breaks down the DSPEx implementation into 6 stable stages, each with focused test subsets that ensure stability before moving to the next stage. Each stage builds upon the previous one and includes comprehensive testing to validate functionality.

---

## Stage 1: Foundation - Signature System (Weeks 1-2)

### **Goal**: Establish the core signature parsing and module generation system

### **Components to Implement**:
- `DSPEx.Signature` behaviour
- `DSPEx.Signature.Parser` module
- `use DSPEx.Signature` macro
- `DSPEx.Example` struct and basic operations

### **Test Subset - Stage 1**:

```elixir
# test/dspex/signature_test.exs (COMPLETE)
defmodule DSPEx.SignatureTest do
  use ExUnit.Case, async: true
  
  # All signature parsing tests
  describe "signature parsing" do
    test "parses simple input -> output"
    test "parses multiple inputs and outputs" 
    test "handles whitespace gracefully"
    test "raises on invalid format"
    test "raises on duplicate fields"
    test "raises on invalid field names"
    test "handles empty input fields"
    test "handles empty output fields"
  end
  
  # All generated signature module tests  
  describe "generated signature modules" do
    test "implements behaviour correctly"
    test "creates valid struct"
    test "validates inputs correctly"
    test "validates outputs correctly"
  end
  
  # All signature comparison tests
  describe "signature equality and comparison"
  describe "complex signature patterns"
end

# test/dspex/example_test.exs (BASIC SUBSET)
defmodule DSPEx.ExampleTest do
  use ExUnit.Case, async: true
  
  # Core example functionality only
  describe "example creation" do
    test "creates example with basic fields"
    test "creates example from keyword list"
    test "handles additional metadata fields"
  end
  
  describe "input/output field designation" do
    test "designates input fields explicitly"
    test "infers output fields from remaining fields" 
    test "handles empty input designation"
  end
  
  describe "example manipulation" do
    test "copies example with additional fields"
    test "removes fields from example"
    test "converts to plain map"
  end
  
  # Skip serialization, validation, equality tests for now
end

# test/dspex/property_test.exs (SIGNATURE SUBSET)
defmodule DSPEx.PropertyTest do
  use ExUnit.Case
  use PropCheck
  
  # Only signature parsing properties
  describe "signature parsing properties" do
    property "parsed signatures maintain field order"
    property "field validation is consistent"
  end
  
  # Skip example and prediction properties for now
end
```

### **Success Criteria Stage 1**:
- ✅ All signature tests pass
- ✅ Basic example creation/manipulation works
- ✅ Property tests validate signature parsing consistency
- ✅ Compile-time signature validation catches errors
- ✅ Generated modules implement behaviour correctly

### **Deliverables**:
- Working signature parser with comprehensive error handling
- Macro system that generates valid signature modules  
- Basic example structure for data flow
- Complete test coverage for signature system

---

## Stage 2: Client & HTTP Layer (Weeks 3-4)

### **Goal**: Establish reliable HTTP communication with external LLM APIs

### **Components to Implement**:
- `DSPEx.Client` GenServer
- HTTP client with Req/Finch
- Circuit breaker with Fuse
- Basic caching with Cachex
- Retry logic and timeout handling

### **Test Subset - Stage 2**:

```elixir
# test/dspex/client_test.exs (COMPLETE)
defmodule DSPEx.ClientTest do
  use ExUnit.Case, async: false
  
  # All client tests - no dependencies on other stages
  describe "client initialization"
  describe "HTTP requests" 
  describe "circuit breaker"
  describe "caching"
end

# Integration test for Stage 1 + 2
defmodule DSPEx.Stage2IntegrationTest do
  use ExUnit.Case, async: false
  
  test "client can handle signature-based requests" do
    # Verify client works with signature system
    defmodule TestSig do
      use DSPEx.Signature, "question -> answer"
    end
    
    {:ok, client} = DSPEx.Client.start_link(%{
      api_key: "test", 
      model: "test"
    })
    
    # Mock request that uses signature fields
    request = %{
      messages: [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "Test question"}
      ],
      model: "test"
    }
    
    # Should successfully make request
    assert {:ok, _response} = DSPEx.Client.request(client, request)
  end
end
```

### **Success Criteria Stage 2**:
- ✅ Client handles HTTP requests reliably
- ✅ Circuit breaker prevents cascade failures
- ✅ Caching works for identical requests
- ✅ Retry logic handles transient failures
- ✅ Integration with Stage 1 components works

### **Deliverables**:
- Production-ready HTTP client with resilience patterns
- Comprehensive error handling and logging
- Performance optimizations (caching, connection pooling)

---

## Stage 3: Adapters & Message Formatting (Weeks 5-6)

### **Goal**: Transform between DSPEx signatures and LLM API formats

### **Components to Implement**:
- `DSPEx.Adapter` behaviour  
- `DSPEx.Adapter.Chat` implementation
- `DSPEx.Adapter.JSON` implementation
- Message formatting and parsing logic

### **Test Subset - Stage 3**:

```elixir
# test/dspex/adapter_test.exs (COMPLETE)
defmodule DSPEx.AdapterTest do
  use ExUnit.Case, async: true
  
  # All adapter tests using signatures from Stage 1
  describe "chat adapter formatting"
  describe "chat adapter parsing"  
  describe "JSON adapter"
end

# Extended integration test
defmodule DSPEx.Stage3IntegrationTest do
  use ExUnit.Case, async: false
  
  test "end-to-end: signature -> adapter -> client -> parse" do
    defmodule QASig do
      use DSPEx.Signature, "question -> answer"
    end
    
    {:ok, client} = DSPEx.Client.start_link(%{
      api_key: "test",
      model: "test", 
      adapter: MockAdapter  # Returns test response
    })
    
    # Format request using adapter
    inputs = %{question: "What is 2+2?"}
    messages = DSPEx.Adapter.Chat.format(QASig, inputs, [])
    
    # Send via client
    request = %{messages: messages, model: "test"}
    {:ok, response} = DSPEx.Client.request(client, request)
    
    # Parse response
    assert {:ok, parsed} = DSPEx.Adapter.Chat.parse(QASig, response.content)
    assert parsed.answer
  end
end
```

### **Success Criteria Stage 3**:
- ✅ Chat adapter formats/parses correctly
- ✅ JSON adapter handles structured output
- ✅ Few-shot examples integrate properly  
- ✅ Error handling for malformed responses
- ✅ End-to-end message flow works

### **Deliverables**:
- Robust adapter system supporting multiple LLM formats
- Comprehensive parsing with error recovery
- Few-shot example integration

---

## Stage 4: Prediction Engine (Weeks 7-8)

### **Goal**: Core prediction workflow with demo management

### **Components to Implement**:
- `DSPEx.Predict` struct and logic
- `DSPEx.Program` behaviour  
- Demo management and selection
- Batch prediction capabilities

### **Test Subset - Stage 4**:

```elixir
# test/dspex/predict_test.exs (COMPLETE)
defmodule DSPEx.PredictTest do
  use ExUnit.Case, async: false
  
  # All prediction tests using components from Stages 1-3
  describe "prediction initialization"
  describe "forward prediction"
  describe "batch prediction" 
  describe "demo management"
end

# test/dspex/program_test.exs (BASIC SUBSET)
defmodule DSPEx.ProgramTest do
  use ExUnit.Case, async: false
  
  # Core program behavior only
  describe "program behavior implementation"
  describe "program composition"
  
  # Skip state management and metrics for now
end

# Integration test for full prediction pipeline
defmodule DSPEx.Stage4IntegrationTest do
  use ExUnit.Case, async: false
  
  test "complete prediction workflow" do
    defmodule QASig do
      use DSPEx.Signature, "question -> answer" 
    end
    
    {:ok, client} = start_supervised({DSPEx.Client, %{
      api_key: "test",
      model: "test",
      adapter: MockClient
    }})
    
    # Create predictor
    predict = DSPEx.Predict.new(QASig, client: client)
    
    # Add demo
    demo = %DSPEx.Example{question: "What is 1+1?", answer: "2"}
    predict = DSPEx.Predict.add_demo(predict, demo)
    
    # Make prediction
    result = DSPEx.Predict.forward(predict, %{question: "What is 2+2?"})
    
    assert {:ok, prediction} = result
    assert prediction.answer
  end
end
```

### **Success Criteria Stage 4**:
- ✅ Predictions work with real/mock LLM responses
- ✅ Demo management enhances predictions
- ✅ Batch processing handles multiple inputs
- ✅ Error handling and validation work end-to-end
- ✅ Program composition enables complex workflows

### **Deliverables**:
- Working prediction engine with demo support
- Batch processing capabilities
- Program composition framework

---

## Stage 5: Evaluation & Optimization (Weeks 9-10)

### **Goal**: Concurrent evaluation and teleprompter optimization

### **Components to Implement**:
- `DSPEx.Evaluate` with Task.async_stream
- `DSPEx.Teleprompter.BootstrapFewShot` 
- Metric computation and aggregation
- Progress tracking and reporting

### **Test Subset - Stage 5**:

```elixir
# test/dspex/evaluate_test.exs (COMPLETE)
defmodule DSPEx.EvaluateTest do
  use ExUnit.Case, async: false
  
  # All evaluation tests using programs from Stage 4
  describe "evaluation initialization"
  describe "evaluation execution"
  describe "metric functions"
  describe "result aggregation"
end

# test/dspex/teleprompter/bootstrap_fewshot_test.exs (COMPLETE)
defmodule DSPEx.Teleprompter.BootstrapFewShotTest do
  use ExUnit.Case, async: false
  
  # All teleprompter tests  
  describe "bootstrap initialization"
  describe "compilation process"
  describe "demo selection strategy"
  describe "error handling"
end

# Integration test for optimization pipeline
defmodule DSPEx.Stage5IntegrationTest do
  use ExUnit.Case, async: false
  
  test "bootstrap optimization improves performance" do
    # Create student and teacher programs
    # Run evaluation on unoptimized student
    # Run bootstrap optimization  
    # Run evaluation on optimized student
    # Assert improvement in scores
  end
end
```

### **Success Criteria Stage 5**:
- ✅ Concurrent evaluation processes multiple examples efficiently
- ✅ Bootstrap few-shot improves program performance
- ✅ Metrics compute correctly across concurrent executions
- ✅ Progress tracking works for long-running evaluations
- ✅ Teleprompter optimization produces measurable improvements

### **Deliverables**:
- High-performance concurrent evaluation engine
- Working bootstrap few-shot teleprompter
- Comprehensive metrics and reporting

---

## Stage 6: Advanced Features & Production (Weeks 11-12)

### **Goal**: Advanced reasoning, parallel execution, and production readiness

### **Components to Implement**:
- `DSPEx.ChainOfThought`
- `DSPEx.MultiChainComparison`
- `DSPEx.Parallel` execution
- `DSPEx.Retriever` integration
- Production monitoring and observability

### **Test Subset - Stage 6**:

```elixir
# test/dspex/chain_of_thought_test.exs (COMPLETE)
# test/dspex/multi_chain_comparison_test.exs (COMPLETE)  
# test/dspex/parallel_test.exs (COMPLETE)
# test/dspex/retriever_test.exs (COMPLETE)

# Complete integration tests
# test/dspex/integration_test.exs (COMPLETE)
defmodule DSPEx.IntegrationTest do
  use ExUnit.Case, async: false
  
  # All end-to-end scenarios
  describe "end-to-end RAG pipeline"
  describe "multi-step reasoning pipeline"
  describe "optimization pipeline" 
  describe "error handling and recovery"
  describe "performance and scalability"
end

# Complete property tests
# test/dspex/property_test.exs (COMPLETE)
defmodule DSPEx.PropertyTest do
  use ExUnit.Case
  use PropCheck
  
  # All property tests
  describe "signature parsing properties"
  describe "example manipulation properties"
  describe "prediction properties"
end
```

### **Success Criteria Stage 6**:
- ✅ Chain of thought reasoning works reliably
- ✅ Multi-chain comparison selects best responses  
- ✅ Parallel execution scales efficiently
- ✅ RAG pipelines integrate retrieval and generation
- ✅ Property tests validate system invariants
- ✅ Production monitoring and observability ready

### **Deliverables**:
- Complete DSPEx system with all advanced features
- Production-ready monitoring and observability
- Comprehensive documentation and examples

---

## Testing Strategy Per Stage

### **Stage Testing Principles**:

1. **Isolation**: Each stage's tests can run independently
2. **Integration**: Integration tests verify stage boundaries work
3. **Regression**: All previous stage tests continue to pass
4. **Performance**: Each stage includes performance validation
5. **Property**: Property tests validate invariants at each stage

### **Continuous Testing Approach**:

```bash
# Stage 1
mix test test/dspex/signature_test.exs
mix test test/dspex/example_test.exs --only basic
mix test test/dspex/property_test.exs --only signature

# Stage 2  
mix test test/dspex/client_test.exs
mix test test/dspex/stage2_integration_test.exs
mix test --only stage1  # Regression test

# Stage 3
mix test test/dspex/adapter_test.exs  
mix test test/dspex/stage3_integration_test.exs
mix test --only stage1,stage2  # Regression test

# Continue pattern for each stage...

# Final validation
mix test  # All tests should pass
```

### **Quality Gates Per Stage**:

- **Code Coverage**: Minimum 90% for each stage
- **Performance**: No regressions from previous stages
- **Documentation**: All public APIs documented
- **Integration**: Cross-stage functionality validated
- **Property Tests**: All invariants hold

### **Risk Mitigation**:

1. **Rollback Plan**: Each stage is independently deployable
2. **Feature Flags**: Advanced features can be disabled
3. **Monitoring**: Each stage has specific metrics
4. **Testing**: Comprehensive test coverage prevents regressions
5. **Documentation**: Clear interfaces between stages

This staged approach ensures each component is solid before building on top of it, with comprehensive testing at each level to catch issues early and maintain system stability.s











---



I've created a comprehensive 6-stage implementation plan that uses strategic test subsets to ensure stability at each stage. Here's the key approach:

## **Staged Testing Strategy**

### **Stage 1: Foundation (Weeks 1-2)**
- **Focus**: Signature system + basic examples
- **Tests**: Complete signature tests, basic example tests, signature property tests
- **Goal**: Rock-solid foundation that all other components depend on

### **Stage 2: Client Layer (Weeks 3-4)** 
- **Focus**: HTTP client with resilience patterns
- **Tests**: Complete client tests + Stage 1+2 integration tests
- **Goal**: Reliable communication with external APIs

### **Stage 3: Adapters (Weeks 5-6)**
- **Focus**: Message formatting between signatures and LLM APIs
- **Tests**: Complete adapter tests + end-to-end message flow tests
- **Goal**: Robust transformation between DSPEx and LLM formats

### **Stage 4: Prediction Engine (Weeks 7-8)**
- **Focus**: Core prediction workflow with demos
- **Tests**: Complete prediction tests + basic program tests + full pipeline integration
- **Goal**: Working prediction system with few-shot learning

### **Stage 5: Evaluation & Optimization (Weeks 9-10)**
- **Focus**: Concurrent evaluation and teleprompter optimization
- **Tests**: Complete evaluation and bootstrap teleprompter tests + optimization validation
- **Goal**: Performance measurement and improvement capabilities

### **Stage 6: Advanced Features (Weeks 11-12)**
- **Focus**: Chain of thought, multi-chain comparison, parallel execution, RAG
- **Tests**: All remaining tests including complete integration and property tests
- **Goal**: Production-ready system with advanced reasoning capabilities

## **Key Benefits of This Approach**

1. **Progressive Validation**: Each stage validates its dependencies are working before building on top
2. **Early Issue Detection**: Comprehensive testing at each stage catches problems before they compound
3. **Rollback Safety**: Each stage is independently functional, allowing safe rollbacks
4. **Performance Tracking**: Stage-by-stage performance validation prevents regressions
5. **Team Coordination**: Clear boundaries allow different team members to work on different stages

## **Risk Mitigation**

- **Integration Tests**: Each stage includes tests that validate cross-stage functionality
- **Regression Testing**: All previous stage tests continue to run and pass
- **Property Testing**: Stage-appropriate property tests validate system invariants
- **Performance Gates**: Each stage must meet performance criteria before proceeding

This plan ensures that DSPEx is built on a solid foundation with each component thoroughly tested and validated before the next layer is added, resulting in a reliable and maintainable system.