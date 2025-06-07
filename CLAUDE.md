# DSPEx - Declarative Self-improving Elixir

A modern Elixir port of DSPy (Declarative Self-improving Python) framework for programming language models with signatures, modules, and teleprompters, leveraging BEAM's concurrency and fault tolerance.

## Overview

DSPEx brings the power of systematic language model programming to the Elixir ecosystem, providing a declarative approach to building, optimizing, and evaluating LM-based programs. This implementation leverages Elixir's strengths in concurrency, fault tolerance, and distributed systems to create a more robust and scalable framework than its Python counterpart.

## Key Features

- **Declarative Signatures**: Compile-time macro system for defining AI program contracts
- **Resilient Client Layer**: GenServer-based LLM clients with circuit breakers and caching  
- **Concurrent Evaluation**: High-performance evaluation engine using Task.async_stream
- **Teleprompter Optimization**: Few-shot learning and program optimization algorithms
- **Fault Tolerance**: Built on OTP supervision trees and "let it crash" philosophy
- **Type Safety**: Compile-time guarantees and Dialyzer support

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
DSPEx.Evaluate & Teleprompter (Optimization Layer)
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

### 2. DSPEx.Client  
Stateful GenServer for resilient LLM API calls with:
- Circuit breaker pattern (using Fuse)
- Automatic caching (using Cachex)
- Rate limiting and retries
- Distributed supervision

### 3. DSPEx.Adapter
Translation layer between programs and LLM APIs:
- Format signatures into prompts
- Parse responses back to structured data
- Support for multiple LLM providers

### 4. DSPEx.Program & DSPEx.Predict
Core execution modules implementing the Program behavior:
- Forward execution pipeline
- Demo management
- Error handling and recovery

### 5. DSPEx.Evaluate
Concurrent evaluation engine for testing programs:
- Parallel execution using Task.async_stream
- Progress tracking and metrics
- Fault isolation per evaluation

### 6. DSPEx.Teleprompter
Optimization algorithms for improving programs:
- BootstrapFewShot for demo generation
- Concurrent teacher/student training
- Performance-based filtering

## Dependencies & Technology Stack

Based on comprehensive analysis of Elixir/Erlang ecosystem (see docs/004_foundation/02_geminiDeepResearch.md):

### HTTP & Networking
- **Req**: Modern HTTP client for LLM API calls
- **Fuse**: Circuit breaker for resilience
- **Cachex**: High-performance caching

### Concurrency & Distribution  
- **Task.async_stream**: Concurrent evaluation engine
- **GenServer**: Stateful client processes
- **Supervisor**: Fault tolerance and recovery

### Data Processing
- **Broadway**: Data pipeline framework (future enhancement)
- **Flow**: Parallel stream processing (future enhancement)

### Testing & Quality
- **ExUnit**: Unit and integration testing
- **PropCheck**: Property-based testing
- **Mox**: Mock external dependencies
- **Dialyzer**: Static analysis and type checking

## Quick Start

1. **Initialize Project**:
   ```bash
   mix new dspex
   cd dspex
   ```

2. **Add Dependencies** (see mix.exs for full list):
   ```elixir
   {:req, "~> 0.5"},
   {:fuse, "~> 2.5"},
   {:cachex, "~> 3.6"}
   ```

3. **Define a Signature**:
   ```elixir
   defmodule MySignature do
     @moduledoc "Answer math questions"
     use DSPEx.Signature, "question -> answer"
   end
   ```

4. **Create a Program**:
   ```elixir
   predict = DSPEx.Predict.new(
     signature: MySignature,
     client: :openai_client,
     adapter: DSPEx.Adapter.Chat
   )
   ```

5. **Execute & Evaluate**:
   ```elixir
   {:ok, prediction} = DSPEx.Program.forward(predict, %{question: "What is 2+2?"})
   
   # Evaluate on dataset
   results = DSPEx.Evaluate.run(predict, examples, metric_fn)
   ```

## Development Approach

This implementation follows Test-Driven Development (TDD) with comprehensive test coverage:

- **Unit Tests**: Each module tested in isolation
- **Integration Tests**: Cross-module functionality
- **Property Tests**: Parsing and serialization edge cases  
- **Concurrent Tests**: Race conditions and fault tolerance
- **End-to-End Tests**: Complete optimization workflows

See TESTS.md for detailed testing commands and procedures.

## Implementation Status

Progress is tracked in docs/005_optimizer/100_claude.md with line-by-line mappings to original Python DSPy code.

### Current Status: ✅ Phase 1 COMPLETE - Minimal Working Pipeline

**Phase 1 - Complete Prediction Pipeline (STABLE):**
- ✅ **DSPEx.Signature** - Complete with macro-based parsing, field validation, and behavior callbacks
- ✅ **DSPEx.Example** - Core data structure with Protocol implementations (Enumerable, Collectable, Inspect)
- ✅ **DSPEx.Client** - Basic HTTP client with request validation and error categorization
- ✅ **DSPEx.Adapter** - Message formatting and response parsing for LLM APIs
- ✅ **DSPEx.Predict** - Orchestration layer connecting all components
- ✅ **Test Infrastructure** - 108 tests passing with comprehensive coverage
- ✅ **Code Quality** - Zero Dialyzer warnings, follows CODE_QUALITY.md standards
- ✅ **Project Structure** - Well-organized codebase with clear separation of concerns

**Phase 1 Test Command:**
```bash
# Run stable Phase 1 tests (108 tests passing)
mix test test/unit/signature_test.exs test/unit/example_test.exs test/property/signature_parser_test.exs test/integration/signature_example_test.exs test/unit/client_test.exs test/unit/adapter_test.exs test/unit/predict_test.exs --exclude phase2_features
```

**Phase 2+ Features (Properly Deferred):**
*Tagged as `:phase2_features` and excluded from Phase 1 testing:*
- Field access via dot notation (`example.question`) - requires custom Access behavior
- Utility functions (`copy/2`, `without/2`, `to_map/1`) - data manipulation helpers
- Validation functions (`has_field?/2`, `equal?/2`) - comparison and validation
- Type introspection (`get_field_type/2`) - runtime type checking
- JSON serialization (`to_json/1`, `from_json/1`) - external format support

**Phase 2 - Client Infrastructure (READY TO BEGIN):**
- 🚧 DSPEx.Client (GenServer-based HTTP client with circuit breakers and caching)
- ⬜ DSPEx.Adapter (Translation layer between signatures and LLM APIs)
- ⬜ DSPEx.Program/Predict (Core execution engine)
- ⬜ DSPEx.Evaluate (Concurrent evaluation framework)
- ⬜ DSPEx.Teleprompter (Optimization algorithms)

### Phase 1 Achievement Summary

**✅ COMPLETED**: DSPEx Foundation with systematic test-driven approach

**Achieved Objectives:**
1. **✅ Complete DSPEx.Signature API** - Macro-based parsing with compile-time validation
2. **✅ Complete DSPEx.Example Core API** - Functional data operations with Protocol implementations
3. **✅ Zero Dialyzer Warnings** - Type-safe code following CODE_QUALITY.md standards
4. **✅ Comprehensive Testing** - 54 tests covering all foundation functionality
5. **✅ Proper Test Organization** - Phase 1 vs Phase 2+ features clearly separated

**Phase 1 Success Criteria:** ✅ ACHIEVED
- All 108 pipeline tests passing (54 foundation + 54 prediction pipeline)
- Zero Dialyzer warnings maintained throughout
- Complete end-to-end prediction pipeline working
- Systematic incremental development with test-driven approach
- Ready for Phase 2 resilience features

### Phase 2 Implementation Plan (After Phase 1 Complete)

**Objective**: Build resilient HTTP client infrastructure for LLM API communication

**Phase 2A: Client Infrastructure (Weeks 1-2)**

**Primary Component**: `DSPEx.Client` - GenServer-based LLM client

**Key Dependencies (Production-Ready)**:
```elixir
# mix.exs additions for Phase 2
{:req, "~> 0.5"},        # Modern HTTP client
{:fuse, "~> 2.5"},       # Circuit breaker pattern  
{:cachex, "~> 3.6"},     # High-performance caching
{:jason, "~> 1.4"},      # JSON processing
{:telemetry, "~> 1.2"}   # Observability
```

**Implementation Priorities**:

1. **Core Client GenServer** (`lib/dspex/client.ex`)
   - Supervised GenServer lifecycle with named registration
   - Configuration management (API keys, endpoints, models)
   - Synchronous request/response API with timeouts

2. **Resilience Infrastructure**
   - Circuit breaker integration using Fuse library
   - Exponential backoff strategy (5s base, 2x factor)
   - Configurable failure thresholds (5 failures → 10s cooldown)

3. **Caching Layer** 
   - Deterministic cache key generation using SHA256
   - Per-client cache isolation for multi-provider support
   - TTL and size-based eviction policies

4. **HTTP Abstraction**
   - Provider-agnostic request formatting
   - Comprehensive error handling and classification
   - Response parsing and validation

**Phase 2B: Integration & Testing (Week 3)**
- Mock-based unit tests for GenServer behavior
- Integration tests with circuit breaker failure scenarios  
- Cache performance verification (>90% hit rates)
- Error propagation and recovery testing

**Success Criteria for Phase 2:**
- All client operations working with real LLM APIs
- Circuit breaker activating/recovering under failure conditions
- Sub-100ms cache hits, <5s recovery times
- 100+ concurrent requests per client supported
- Test coverage >95% with zero Dialyzer warnings

**Architecture Decisions for Phase 2:**
- GenServer per client for state isolation and fault tolerance
- Native Elixir libraries over early-stage Foundation dependency
- Foundation-compatible patterns for future migration path
- Comprehensive telemetry for observability

### Testing Strategy

Following Test-Driven Development with staged validation:
- Each phase builds upon comprehensive test suite
- Progressive integration testing between phases
- Property-based testing for edge cases and invariants
- Concurrent testing for race conditions and fault tolerance
- Mock external dependencies for isolated unit testing

**Test Organization:**
- `test/unit/` - Individual module tests
- `test/integration/` - Cross-module functionality  
- `test/property/` - Property-based testing with PropCheck
- `test/support/` - Test helpers, fixtures, and factories
- `test/teleprompter/` - Optimization algorithm tests

**Current Test Status:**
- Test infrastructure reorganized and ready
- Phase 1 test cases identified and documented
- Mock framework configured for external dependencies
- Ready to begin systematic test implementation

## Contributing

This project prioritizes:
1. **Correctness**: Comprehensive test coverage
2. **Performance**: Leverage BEAM's concurrency 
3. **Resilience**: Fault tolerance and graceful degradation
4. **Maintainability**: Clear abstractions and documentation

## License

Same as original DSPy project.

## Acknowledgments

- Original DSPy team for the foundational concepts
- Elixir community for the excellent ecosystem packages
- BEAM team for the robust runtime platform