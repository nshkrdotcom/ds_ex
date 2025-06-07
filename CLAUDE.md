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

### Current Status: 🚧 Phase 1 Implementation

**Completed:**
- ✅ Project structure and comprehensive documentation
- ✅ Test file reorganization (moved from test/suite/ to test/ with proper merging)
- ✅ Comprehensive specification review (6-stage implementation plan documented)
- ✅ Test infrastructure planning (598+ test cases identified)

**Phase 1 - Foundation (In Progress):**
- 🚧 DSPEx.Signature (Foundation - signature parsing and compilation)
- 🚧 DSPEx.Example (Core data structures)
- ⬜ DSPEx.Client (HTTP Layer)  
- ⬜ DSPEx.Adapter (Translation)
- ⬜ DSPEx.Program/Predict (Execution)
- ⬜ DSPEx.Evaluate (Evaluation)
- ⬜ DSPEx.Teleprompter (Optimization)

### Phase 1 Implementation Plan

**Objective**: Establish foundation layer with Signature system and basic Example operations

**Core Components for Phase 1:**

1. **DSPEx.Signature** - Compile-time macro system
   - Parse signature strings ("question -> answer, reasoning")
   - Generate input/output field specifications
   - Compile-time validation and error handling
   - Support for multi-output signatures

2. **DSPEx.Example** - Data container struct
   - Store input/output pairs with metadata
   - Support for partial examples (inputs only)
   - Serialization/deserialization capabilities
   - Validation against signature contracts

**Phase 1 Test Coverage:**
- Signature parsing for various formats (simple, multi-output, complex)
- Edge cases: malformed signatures, empty strings, special characters
- Example creation, validation, and manipulation
- Property-based tests for signature/example compatibility
- Error handling and meaningful error messages

**Success Criteria for Phase 1:**
- All signature parsing tests pass (approx. 45 test cases)
- Example data structure fully functional (approx. 25 test cases)  
- No dialyzer warnings or errors
- Comprehensive documentation with examples
- Ready for Phase 2 integration (Client layer)

**Phase 1 Architecture Decisions:**
- Use compile-time macros for signature definitions (performance)
- Leverage Elixir pattern matching for validation
- Design for extensibility (support future signature features)
- Maintain compatibility with DSPy signature semantics

**Next Steps After Phase 1:**
- Phase 2: DSPEx.Client (GenServer with circuit breakers, caching)
- Phase 3: DSPEx.Adapter (prompt formatting and response parsing)
- Phase 4: DSPEx.Program/Predict (execution engine)
- Phase 5: DSPEx.Evaluate (concurrent evaluation)
- Phase 6: DSPEx.Teleprompter (optimization algorithms)

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