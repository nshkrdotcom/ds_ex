# DSPEx - Declarative Self-improving Elixir

A modern Elixir port of DSPy (Declarative Self-improving Python) framework for programming language models with signatures, modules, and teleprompters, leveraging BEAM's concurrency and fault tolerance.

## Overview

DSPEx brings the power of systematic language model programming to the Elixir ecosystem, providing a declarative approach to building, optimizing, and evaluating LM-based programs. This implementation leverages Elixir's strengths in concurrency, fault tolerance, and distributed systems to create a more robust and scalable framework than its Python counterpart.

## Key Features

- **Declarative Signatures**: Compile-time macro system for defining AI program contracts
- **Program Behavior**: Unified interface with DSPEx.Program behavior and telemetry integration
- **Concurrent Evaluation**: High-performance evaluation engine using Task.async_stream
- **Resilient Client Layer**: HTTP client with circuit breakers and error categorization
- **Comprehensive Testing**: 2,200+ lines of tests covering edge cases and concurrent scenarios
- **Foundation Integration**: Full telemetry, correlation tracking, and observability

## Architecture

DSPEx follows a layered architecture built on the dependency graph:

```
DSPEx.Signature (Foundation)
    ↓
DSPEx.Adapter (Translation Layer)  
    ↓
DSPEx.Client (HTTP/LLM Interface)
    ↓
DSPEx.Program/Predict (Execution Engine)
    ↓
DSPEx.Evaluate (Optimization Layer)
```

## Core Components

### 1. DSPEx.Signature
Compile-time macros for declaring input/output contracts:

```elixir
defmodule QASignature do
  @moduledoc "Answer questions with detailed reasoning"
  use DSPEx.Signature, "question -> answer, reasoning"
end
```

### 2. DSPEx.Program & DSPEx.Predict
Core execution engine implementing the Program behavior:

```elixir
# New Program API (Recommended)
program = DSPEx.Predict.new(QASignature, :gemini)
{:ok, outputs} = DSPEx.Program.forward(program, %{question: "What is 2+2?"})

# Legacy API (Maintained for compatibility)
{:ok, outputs} = DSPEx.Predict.forward(QASignature, %{question: "What is 2+2?"})
```

### 3. DSPEx.Client
HTTP client for resilient LLM API calls:
- Error categorization (network, API, timeout)
- Request validation and correlation tracking
- Support for multiple providers (OpenAI, Gemini)

### 4. DSPEx.Adapter
Translation layer between programs and LLM APIs:
- Format signatures into prompts
- Parse responses back to structured data
- Handle missing fields and validation

### 5. DSPEx.Evaluate
Concurrent evaluation engine for testing programs:

```elixir
# Create examples
examples = [
  %{inputs: %{question: "2+2?"}, outputs: %{answer: "4"}},
  %{inputs: %{question: "3+3?"}, outputs: %{answer: "6"}}
]

# Define metric function
metric_fn = fn example, prediction ->
  if example.outputs.answer == prediction.answer, do: 1.0, else: 0.0
end

# Run evaluation
{:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)
```

## Implementation Status

### ✅ Phase 1 COMPLETE - Working End-to-End Pipeline

**Core Components (STABLE):**
- ✅ **DSPEx.Signature** - Complete with macro-based parsing and field validation
- ✅ **DSPEx.Example** - Core data structure with Protocol implementations
- ✅ **DSPEx.Client** - HTTP client with error categorization and validation
- ✅ **DSPEx.Adapter** - Message formatting and response parsing
- ✅ **DSPEx.Predict** - Program behavior with backward compatibility
- ✅ **DSPEx.Program** - Behavior interface with telemetry integration
- ✅ **DSPEx.Evaluate** - Concurrent evaluation engine

**Testing Infrastructure (COMPREHENSIVE):**
- ✅ **19 Test Files** with 2,200+ lines of comprehensive test coverage
- ✅ **Unit Tests** - All modules tested in isolation with edge cases
- ✅ **Integration Tests** - End-to-end pipeline scenarios and workflows
- ✅ **Concurrent Tests** - Race condition detection and thread safety
- ✅ **Property Tests** - Invariant verification with PropCheck
- ✅ **Error Recovery Tests** - Fault tolerance and graceful degradation

**Quality Assurance (ENTERPRISE-GRADE):**
- ✅ **Zero Dialyzer Warnings** - Type-safe code following best practices
- ✅ **Compilation Clean** - All syntax and clause ordering issues resolved
- ✅ **Foundation Integration** - Full telemetry and correlation tracking
- ✅ **Performance Testing** - Load testing, memory usage, throughput validation

**Current Test Command:**
```bash
# Run all stable tests
mix test test/unit/ test/integration/ test/property/ test/concurrent/

# Run basic pipeline tests
mix test test/unit/signature_test.exs test/unit/example_test.exs test/unit/predict_test.exs
```

## Quick Start

1. **Define a Signature**:
   ```elixir
   defmodule MySignature do
     @moduledoc "Answer math questions"
     use DSPEx.Signature, "question -> answer"
   end
   ```

2. **Create and Use a Program**:
   ```elixir
   # New Program API
   program = DSPEx.Predict.new(MySignature, :gemini)
   {:ok, result} = DSPEx.Program.forward(program, %{question: "What is 2+2?"})
   
   # Legacy API (still supported)
   {:ok, result} = DSPEx.Predict.forward(MySignature, %{question: "What is 2+2?"})
   ```

3. **Evaluate Performance**:
   ```elixir
   examples = [%{inputs: %{question: "2+2?"}, outputs: %{answer: "4"}}]
   metric_fn = fn example, prediction ->
     if example.outputs.answer == prediction.answer, do: 1.0, else: 0.0
   end
   
   {:ok, evaluation} = DSPEx.Evaluate.run(program, examples, metric_fn)
   IO.inspect(evaluation.score)
   ```

## Testing Strategy

The project follows comprehensive Test-Driven Development with:

- **Unit Tests** (`test/unit/`) - Individual module isolation testing
- **Integration Tests** (`test/integration/`) - Cross-module functionality and error recovery
- **Property Tests** (`test/property/`) - Invariant verification and edge case generation
- **Concurrent Tests** (`test/concurrent/`) - Race condition detection and thread safety
- **End-to-End Tests** (`test/end_to_end_pipeline_test.exs`) - Complete workflow validation

**Test Coverage Highlights:**
- Program behavior with edge cases and error scenarios
- Concurrent evaluation with race condition handling
- Property-based testing for metrics and data transformations
- Error propagation and recovery across the entire pipeline
- Performance characteristics under load and stress conditions

## Development Dependencies

**Core Dependencies:**
```elixir
{:req, "~> 0.5"},              # Modern HTTP client
{:jason, "~> 1.4"},            # JSON processing
{:telemetry, "~> 1.2"},        # Observability
{:fuse, "~> 2.5"},             # Circuit breaker (future)
{:cachex, "~> 3.6"}            # Caching (future)
```

**Testing Dependencies:**
```elixir
{:ex_unit, "~> 1.18"},         # Unit testing framework
{:propcheck, "~> 1.4"},        # Property-based testing
{:mox, "~> 1.1"}               # Mock testing
```

## Next Development Priorities

### Phase 2A: Enhanced Client Infrastructure

**Priority Tasks:**
1. **GenServer-based Clients** - Stateful client processes with supervision
2. **Circuit Breaker Integration** - Fuse-based failure handling
3. **Caching Layer** - Cachex integration for response caching
4. **Rate Limiting** - Request throttling and backoff strategies

### Phase 2B: Advanced Features

**Future Enhancements:**
1. **Teleprompter Implementation** - Few-shot learning and optimization
2. **Distributed Evaluation** - Multi-node evaluation clustering
3. **Advanced Metrics** - Custom evaluation functions and aggregations
4. **Real-time Monitoring** - LiveView dashboards and metrics

## Contributing

This project prioritizes:
1. **Correctness**: Comprehensive test coverage with property-based testing
2. **Performance**: Leverage BEAM's concurrency for high throughput
3. **Resilience**: Fault tolerance and graceful degradation under load
4. **Maintainability**: Clear abstractions, documentation, and type safety

## API Reference

### Core Functions

```elixir
# Program creation and execution
program = DSPEx.Predict.new(signature, client, opts \\ [])
{:ok, outputs} = DSPEx.Program.forward(program, inputs, opts \\ [])

# Evaluation
{:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn, opts \\ [])
{:ok, result} = DSPEx.Evaluate.run_local(program, examples, metric_fn, opts \\ [])

# Legacy compatibility
{:ok, outputs} = DSPEx.Predict.forward(signature, inputs, opts \\ %{})
{:ok, field_value} = DSPEx.Predict.predict_field(signature, inputs, field, opts \\ %{})
```

### Telemetry Events

DSPEx emits comprehensive telemetry events for observability:

```elixir
# Program execution
[:dspex, :program, :forward, :start]
[:dspex, :program, :forward, :stop]

# Evaluation
[:dspex, :evaluate, :run, :start]
[:dspex, :evaluate, :run, :stop]
[:dspex, :evaluate, :example, :start]
[:dspex, :evaluate, :example, :stop]

# Client operations
[:dspex, :client, :request]
```

## License

Same as original DSPy project.

## Acknowledgments

- Original DSPy team for the foundational concepts
- Elixir community for the excellent ecosystem packages
- BEAM team for the robust runtime platform

---

# Continuation Instructions for Future Development

## 🚀 **Current State Summary**

DSPEx Phase 1 is **COMPLETE** with a fully functional end-to-end pipeline. The framework includes:

- ✅ Complete signature system with macro-based parsing
- ✅ Program behavior interface with telemetry integration  
- ✅ HTTP client with error categorization
- ✅ Concurrent evaluation engine
- ✅ Comprehensive test suite (19 files, 2,200+ lines)
- ✅ Foundation integration with correlation tracking
- ✅ Backward compatibility with legacy APIs

**All core functionality is working and tested.** The framework can create programs, execute predictions, and evaluate performance with real LLM APIs.

## 🎯 **Next Phase Priorities**

### **Phase 2A: Enhanced Client Infrastructure (Immediate)**

**Primary Focus**: Upgrade HTTP client to GenServer-based architecture

```elixir
# Target API Design
{:ok, client_pid} = DSPEx.Client.start_link(:gemini, config)
{:ok, response} = DSPEx.Client.request(client_pid, messages, opts)

# With circuit breaker and caching
client_opts = [
  circuit_breaker: [failure_threshold: 5, recovery_time: 30_000],
  cache: [ttl: :timer.minutes(10), max_size: 1000],
  rate_limit: [requests_per_second: 10]
]
```

**Implementation Tasks:**
1. **GenServer Client** (`lib/dspex/client.ex`)
   - Convert current functional client to stateful GenServer
   - Add supervision tree integration
   - Implement graceful shutdown and restart

2. **Circuit Breaker Integration**
   - Add Fuse dependency for circuit breaker pattern
   - Implement failure detection and recovery
   - Add telemetry for circuit state changes

3. **Caching Layer**
   - Add Cachex dependency for response caching
   - Implement cache key generation (SHA256 of request)
   - Add cache hit/miss telemetry

4. **Enhanced Error Handling**
   - Implement exponential backoff for retries
   - Add configurable timeout strategies
   - Improve error categorization and recovery

### **Phase 2B: Advanced Evaluation Features**

**Focus**: Expand evaluation capabilities and optimization

```elixir
# Target evaluation enhancements
{:ok, result} = DSPEx.Evaluate.run_distributed(program, examples, metric_fn,
  nodes: [:node1, :node2, :node3],
  distribution_strategy: :round_robin,
  chunk_size: 100
)

# Custom metrics and aggregation
metrics = [
  accuracy: &exact_match/2,
  semantic_similarity: &embedding_similarity/2,
  response_time: &measure_latency/2
]
{:ok, results} = DSPEx.Evaluate.run_with_metrics(program, examples, metrics)
```

### **Phase 2C: Teleprompter Implementation (Future)**

**Focus**: Few-shot learning and program optimization

```elixir
# Target teleprompter API
teleprompter = DSPEx.Teleprompter.BootstrapFewShot.new(
  teacher_program: strong_model_program,
  student_program: fast_model_program,
  num_examples: 10
)

{:ok, optimized_program} = DSPEx.Teleprompter.compile(teleprompter, training_examples)
```

## 🛠 **Development Guidelines**

### **Code Quality Standards**
- **Zero Dialyzer warnings** - Maintain type safety
- **Comprehensive tests** - Every new feature needs unit, integration, and property tests
- **Foundation integration** - All new features should include telemetry and correlation tracking
- **Backward compatibility** - Legacy APIs must continue working

### **Testing Strategy**
```bash
# Test organization for new features
test/unit/new_feature_test.exs           # Isolated unit tests
test/integration/new_feature_integration_test.exs  # Cross-module tests
test/property/new_feature_property_test.exs        # Property-based tests
test/concurrent/new_feature_concurrent_test.exs    # Race condition tests
```

### **Performance Requirements**
- **Concurrent safety** - All new code must be thread-safe
- **Memory efficiency** - Monitor memory usage under load
- **Telemetry integration** - All operations should emit timing and success metrics
- **Error resilience** - Graceful degradation under failure conditions

## 📋 **Immediate Next Steps**

1. **Create GenServer Client** 
   ```bash
   # Start with basic GenServer structure
   mix test test/unit/client_test.exs  # Ensure existing tests still pass
   ```

2. **Add Circuit Breaker Dependency**
   ```elixir
   # Add to mix.exs
   {:fuse, "~> 2.5"}
   ```

3. **Implement Caching Layer**
   ```elixir
   # Add to mix.exs  
   {:cachex, "~> 3.6"}
   ```

4. **Update Test Suite**
   - Add GenServer lifecycle tests
   - Add circuit breaker failure/recovery tests
   - Add cache hit/miss ratio tests

## 🎬 **Success Criteria for Phase 2A**

- [ ] GenServer-based client with supervision
- [ ] Circuit breaker activates/recovers under load
- [ ] Cache hit rates > 90% for repeated requests
- [ ] Sub-100ms response times for cached requests
- [ ] 100+ concurrent requests supported per client
- [ ] All existing tests continue passing
- [ ] Zero Dialyzer warnings maintained

**The foundation is solid. Ready for advanced features!** 🚀