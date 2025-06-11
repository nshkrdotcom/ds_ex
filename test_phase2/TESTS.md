# DSPEx Testing Guide

This document provides comprehensive testing commands and strategies for DSPEx development following the **6-Stage Test-Driven Development** methodology.

## Test Structure

DSPEx follows a comprehensive testing strategy with five types of tests across six core modules, organized by our 6-stage implementation plan:

### Test Types
- **Unit Tests**: Individual module functionality in isolation
- **Integration Tests**: Cross-module interactions  
- **Property Tests**: Property-based testing with PropCheck
- **Concurrent Tests**: Race conditions and concurrent behavior
- **End-to-End Tests**: Complete workflows and benchmarks

### Core Modules (6-Stage Implementation)
1. **Stage 1 - Foundation**: DSPEx.Signature + DSPEx.Example  
2. **Stage 2 - Client Layer**: DSPEx.Client (GenServer with resilience)
3. **Stage 3 - Adapters**: DSPEx.Adapter (LLM message formatting)
4. **Stage 4 - Prediction Engine**: DSPEx.Program/Predict (execution)
5. **Stage 5 - Evaluation**: DSPEx.Evaluate + DSPEx.Teleprompter (optimization)
6. **Stage 6 - Advanced Features**: ChainOfThought, MultiChain, Parallel, RAG

## Quick Start Commands

### Install Dependencies
```bash
# Install all dependencies including test tools
mix deps.get

# Compile with warnings as errors for strict development
mix compile --warnings-as-errors
```

### Basic Test Commands
```bash
# Run all tests
mix test

# Run tests with coverage report
mix test --cover

# Run specific test types
mix test test/unit/
mix test test/integration/
mix test test/property/
mix test test/concurrent/
mix test test/end_to_end/

# Run specific module tests
mix test test/unit/signature_test.exs
mix test test/unit/example_test.exs
```

## 6-Stage Progressive Development Workflow

### Stage 1: Foundation ✅ COMPLETE - Signature System & Examples
```bash
# Core signature parsing and macro behavior (IMPLEMENTED)
mix test test/unit/signature_test.exs

# Example data structure operations (IMPLEMENTED)
mix test test/unit/example_test.exs

# Property-based tests for parser edge cases (IMPLEMENTED)
mix test test/property/signature_parser_test.exs

# Signature-example integration (IMPLEMENTED)
mix test test/integration/signature_example_test.exs

# Run all Stage 1 tests
mix test test/unit/signature_test.exs test/unit/example_test.exs test/property/signature_parser_test.exs test/integration/signature_example_test.exs
```

### Stage 2: Client & HTTP Layer (NEXT) - Resilient API Communication
```bash
# Test client functionality with mocks
mix test test/unit/client_test.exs

# Test concurrent client behavior
mix test test/concurrent/client_concurrent_test.exs

# Test cache key properties
mix test test/property/cache_key_test.exs

# Run all Stage 2 tests (after implementation)
mix test test/unit/client_test.exs test/concurrent/client_concurrent_test.exs test/property/cache_key_test.exs
```

### Stage 3: Translation Layer (Adapters) - Message Formatting
```bash
# Test adapter formatting and parsing
mix test test/unit/adapter_test.exs

# Test adapter roundtrip properties
mix test test/property/adapter_roundtrip_test.exs

# Test client-adapter integration
mix test test/integration/client_adapter_test.exs

# Test signature-adapter integration
mix test test/integration/signature_adapter_test.exs

# Run all Stage 3 tests
mix test test/unit/adapter_test.exs test/property/adapter_roundtrip_test.exs test/integration/client_adapter_test.exs test/integration/signature_adapter_test.exs
```

### Stage 4: Prediction Engine - Core Execution
```bash
# Test program behavior and prediction
mix test test/unit/program_test.exs
mix test test/unit/predict_test.exs

# Test complete prediction pipeline
mix test test/integration/predict_pipeline_test.exs

# Test evaluate-predict integration
mix test test/integration/evaluate_predict_test.exs

# Run all Stage 4 tests
mix test test/unit/program_test.exs test/unit/predict_test.exs test/integration/predict_pipeline_test.exs test/integration/evaluate_predict_test.exs
```

### Stage 5: Evaluation & Optimization - Concurrent Engine & Teleprompters
```bash
# Test evaluation logic
mix test test/unit/evaluate_test.exs

# Test optimization algorithms
mix test test/unit/teleprompter_test.exs

# Test concurrent evaluation
mix test test/concurrent/evaluate_concurrent_test.exs

# Test concurrent optimization
mix test test/concurrent/teleprompter_concurrent_test.exs

# Test full optimization workflow
mix test test/integration/teleprompter_full_test.exs

# Run all Stage 5 tests
mix test test/unit/evaluate_test.exs test/unit/teleprompter_test.exs test/concurrent/evaluate_concurrent_test.exs test/concurrent/teleprompter_concurrent_test.exs test/integration/teleprompter_full_test.exs
```

### Stage 6: Advanced Features - ChainOfThought, MultiChain, Parallel, RAG
```bash
# Test advanced reasoning modules
mix test test/chain_of_thought_test.exs
mix test test/multi_chain_comparison_test.exs
mix test test/parallel_test.exs
mix test test/retriever_test.exs

# Test complete workflows
mix test test/end_to_end/complete_workflow_test.exs

# Run performance benchmarks
mix test test/end_to_end/benchmark_test.exs --include benchmark

# Run all Stage 6 tests
mix test test/chain_of_thought_test.exs test/multi_chain_comparison_test.exs test/parallel_test.exs test/retriever_test.exs test/end_to_end/
```

## Advanced Testing Commands

### Progressive Stage Testing
```bash
# Test current implementation status
mix test test/unit/signature_test.exs test/unit/example_test.exs  # Stage 1 ✅

# Test stage dependencies (run after each stage completion)
mix test --only stage1
mix test --only stage2  
mix test --only stage3
mix test --only stage4
mix test --only stage5
mix test --only stage6
```

### Property-Based Testing
```bash
# Run property tests with more examples
mix test test/property/ --include property

# Run property tests with specific number of examples
PROPCHECK_NUMTESTS=1000 mix test test/property/

# Stage 1 property tests (IMPLEMENTED)
mix test test/property/signature_parser_test.exs
```

### Concurrent and Load Testing
```bash
# Run concurrent tests
mix test test/concurrent/ --include concurrent

# Stress test with multiple processes
mix test test/concurrent/ --max-cases 10
```

### Integration Testing by Stage
```bash
# Stage 1 Integration (IMPLEMENTED)
mix test test/integration/signature_example_test.exs

# Cross-stage integration (after Stage 2+)
mix test test/integration/client_adapter_test.exs
mix test test/integration/predict_pipeline_test.exs
mix test test/integration/teleprompter_full_test.exs
```

### External Integration Testing
```bash
# Run tests requiring external APIs (skip in CI)
mix test --include external_api

# Run integration tests with real services
mix test --include integration
```

### Performance and Benchmarking
```bash
# Run benchmark tests
mix test --include benchmark

# Run performance comparison tests
mix test --include comparison

# Monitor memory usage during tests
mix test --include benchmark --trace
```

## Code Quality Commands

### Static Analysis
```bash
# Run Dialyzer for type checking
mix dialyzer

# Run Credo for code style
mix credo

# Run both quality checks
mix credo && mix dialyzer
```

### Documentation
```bash
# Generate documentation
mix docs

# Check documentation coverage
mix docs --formatter html --check-links
```

### Formatting
```bash
# Format code
mix format

# Check if code is formatted
mix format --check-formatted
```

## Test-Driven Development Workflow

### Red-Green-Refactor Cycle
```bash
# 1. RED: Write failing test
mix test test/unit/new_feature_test.exs

# 2. GREEN: Implement minimal code to pass
mix test test/unit/new_feature_test.exs

# 3. REFACTOR: Clean up code
mix credo lib/dspex/new_feature.ex
mix test test/unit/new_feature_test.exs
```

### Staged Module Development Order
1. **Start with unit tests** for individual functions (Phase 1 ✅)
2. **Add property tests** for edge cases and invariants (Phase 1 ✅)
3. **Write integration tests** for module interactions (Phase 1 ✅)
4. **Add concurrent tests** for GenServer modules (Phase 2+)
5. **Create end-to-end tests** for complete workflows (Phase 6)

## Current Implementation Status

### ✅ STABLE: Phase 1 - Minimal Working Pipeline (108 tests passing)
- **DSPEx.Signature** - Complete with macro-based parsing, field validation, behavior callbacks
- **DSPEx.Example** - Core data structure with Protocol implementations (Enumerable, Collectable, Inspect)
- **DSPEx.Client** - Basic HTTP client with validation and error handling (15 tests)
- **DSPEx.Adapter** - Message formatting and response parsing (17 tests)
- **DSPEx.Predict** - Orchestration layer connecting all components (22 tests)
- **Property-based testing** - Signature parser edge case validation
- **Integration testing** - Cross-module functionality

**Phase 1 Test Commands:**
```bash
# Run stable Phase 1 complete pipeline tests (excludes Phase 2+ features)
mix test test/unit/signature_test.exs test/unit/example_test.exs test/property/signature_parser_test.exs test/integration/signature_example_test.exs test/unit/client_test.exs test/unit/adapter_test.exs test/unit/predict_test.exs --exclude phase2_features

# Verify zero Dialyzer warnings
mix dialyzer --quiet
```

**Phase 1 Success Criteria:** ✅ ACHIEVED
- All 108 tests passing (54 foundation + 54 pipeline)
- Zero Dialyzer warnings maintained
- Complete end-to-end prediction pipeline working
- Proper error handling and validation throughout
- Ready for Phase 2 resilience features (circuit breakers, caching, etc.)

### 🚧 Phase 2+ Features (Deferred from Phase 1)
**Tagged as `:phase2_features` to exclude from Phase 1 testing:**
- Dot notation field access (`example.question`) - requires custom Access behavior
- `copy/2`, `without/2`, `to_map/1` - utility functions for data manipulation
- `has_field?/2`, `equal?/2` - validation and comparison functions  
- `get_field_type/2` - type introspection capabilities
- `to_json/1`, `from_json/1` - JSON serialization support

### 🎯 Next: Phase 2 - Client & HTTP Layer
**Prerequisites:** Phase 1 foundation must remain stable (54 tests passing)
- DSPEx.Client GenServer implementation with supervision
- HTTP client with Req integration and resilience patterns
- Circuit breaker with Fuse (5 failures → 10s cooldown)
- Caching with Cachex (deterministic key generation)
- Retry logic and timeout handling

## Continuous Integration Commands

### Full Test Suite
```bash
# Complete CI test suite
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test --cover
mix dialyzer
```

### Stage-Specific CI
```bash
# Stage 1 CI (current)
mix test test/unit/signature_test.exs test/unit/example_test.exs test/property/signature_parser_test.exs test/integration/signature_example_test.exs --cover

# Progressive CI (add stages as completed)
mix test --only stage1,stage2  # After Stage 2
mix test --only stage1,stage2,stage3  # After Stage 3
# etc.
```

### Coverage Analysis
```bash
# Generate detailed coverage report
mix test --cover --export-coverage default
mix test.coverage
```

### Performance Regression Testing
```bash
# Run benchmarks and compare to baseline
mix test --include benchmark > current_benchmarks.txt
# Compare with previous results
```

## Test Configuration

### Environment Variables
```bash
# Configure test concurrency
export MIX_TEST_ASYNC=true

# Set property test iterations
export PROPCHECK_NUMTESTS=100

# Configure mock timeouts
export TEST_TIMEOUT=5000
```

### Test Tags and Filtering
```bash
# Run only fast tests (exclude slow end-to-end)
mix test --exclude end_to_end

# Run only property tests
mix test --only property

# Skip external API tests
mix test --exclude external_api

# Run specific stage groups
mix test --only stage1  # Foundation (current)
mix test --only stage2  # Client layer
mix test --only stage3  # Adapters
mix test --only stage4  # Prediction engine
mix test --only stage5  # Evaluation & optimization
mix test --only stage6  # Advanced features
```

## Debugging Test Failures

### Verbose Output
```bash
# Run tests with detailed output
mix test --trace

# Run specific failing test with debug
mix test test/unit/failing_test.exs:42 --trace
```

### Mock Debugging
```bash
# Verify mock expectations
mix test --trace | grep "expected.*called"

# Debug mock setup
mix test --trace | grep "Mox"
```

### Property Test Debugging
```bash
# Get property test counterexamples
PROPCHECK_VERBOSE=true mix test test/property/

# Shrink failing property test cases
PROPCHECK_SHRINK=true mix test test/property/
```

## Test Data Management

### Example Datasets
```bash
# Generate test datasets
mix run scripts/generate_test_data.exs

# Validate test data quality
mix test test/test_data_validation.exs
```

### Mock Management
```bash
# Verify all mocks are being used
mix test --warnings-as-errors

# Check for unused mocks
mix credo --only unused
```

## Performance Monitoring

### Memory Usage
```bash
# Monitor memory during tests
mix test --include benchmark --trace | grep memory

# Profile memory allocation
mix test --profile memory
```

### Test Execution Time
```bash
# Time individual test suites
time mix test test/unit/
time mix test test/integration/

# Profile slow tests
mix test --slowest 10
```

This 6-stage testing strategy ensures comprehensive coverage while maintaining fast feedback loops during development. Stage 1 (Foundation) is complete and ready to support the actual DSPEx.Signature and DSPEx.Example implementations.