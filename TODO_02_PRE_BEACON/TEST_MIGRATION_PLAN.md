# DSPEx Test Migration Plan: TODO_02_PRE_SIMBA → test/

**Plan Date:** June 10, 2025  
**Scope:** Systematic migration of tests from `TODO_02_PRE_SIMBA/test/` and `test_phase2/` to `test/`  
**Dependencies:** Critical gaps identified in `GAP_ANALYSIS_claude.md` must be implemented during migration

## Executive Summary

This plan details a **6-phase, incrementally validated migration strategy** that moves test files in small, logical groups while implementing the missing functionality identified in the gap analysis. Each phase builds confidence in the system's readiness for SIMBA integration.

**Key Principles:**
1. **Migrate in small batches** - 2-4 test files per phase to enable quick debugging
2. **Implement missing functionality just-in-time** - Add utilities only when tests require them  
3. **Validate after each phase** - Run full test suite to ensure no regressions
4. **Address critical gaps first** - Prioritize Category 1 tests from `test_phase2_priorities.md`
5. **Build incrementally** - Each phase creates foundation for the next

**Total Duration Estimate:** 8-12 days across 6 phases

---

## Phase 0: Pre-Migration Validation (Day 1)

### Objective
Establish baseline health and prepare infrastructure for migration.

### Tasks

#### Task 0.1: Validate Current Test Suite
```bash
cd /home/home/p/g/n/ds_ex
mix test --cover
```
**Expected:** All existing tests pass, establish baseline coverage metrics

#### Task 0.2: Create Migration Infrastructure
**Files to Create:**
- `test/support/migration_test_helper.ex` - Utilities for migrated tests
- `test/support/simba_test_mocks.ex` - Enhanced mocking for SIMBA workflows

#### Task 0.3: Document Current Test Inventory
Create `test/MIGRATION_STATUS.md` tracking:
- ✅ Tests already migrated and passing
- 🚧 Tests in migration (current phase)  
- ⏳ Tests pending migration
- ❌ Tests that failed migration (with reasons)

**Deliverables:**
- Baseline test metrics documented
- Migration infrastructure in place
- Clear inventory of what needs to move

---

## Phase 1: Critical Program Utilities (Days 2-3)

### Objective
Migrate core utility tests while implementing missing Program and Signature utilities identified as 🔴 CRITICAL BLOCKERS in the gap analysis.

### Implementation First: Missing Critical Functions

#### Task 1.1: Implement Missing Program Utilities
**File:** `lib/dspex/program.ex`

**Add Functions:**
```elixir
@spec program_type(t()) :: :predict | :optimized | :custom
def program_type(program)

@spec safe_program_info(t()) :: %{type: atom(), has_demos: boolean(), name: String.t()}
def safe_program_info(program)

@spec has_demos?(t()) :: boolean()
def has_demos?(program)
```

**Implementation Requirements:**
- `program_type/1`: Return `:predict` for `%Predict{}`, `:optimized` for `%OptimizedProgram{}`, `:custom` for others
- `safe_program_info/1`: Return sanitized info without exposing sensitive data (prompts, API keys)
- `has_demos?/1`: Check if program contains demonstration examples

#### Task 1.2: Implement Missing Signature Introspection  
**File:** `lib/dspex/signature.ex`

**Add Functions:**
```elixir
@spec validate_signature_compatibility(module(), module()) :: :ok | {:error, String.t()}
def validate_signature_compatibility(producer_sig, consumer_sig)

@spec introspect(module()) :: {:ok, map()} | {:error, String.t()}  
def introspect(signature_module)

@spec validate_signature_implementation(module()) :: :ok | {:error, String.t()}
def validate_signature_implementation(module)

@spec field_statistics(module()) :: %{input_count: integer(), output_count: integer()}
def field_statistics(signature_module)
```

### Migration Second: Related Tests

#### Task 1.3: Migrate Core Utility Tests
**Source → Destination:**
```
TODO_02_PRE_SIMBA/test/unit/program_utilities_2_test.exs → test/unit/program_utilities_test.exs
TODO_02_PRE_SIMBA/test/unit/signature_extension_2_test.exs → test/unit/signature_introspection_test.exs
```

**Expected Test Coverage:**
- All new Program utility functions work correctly  
- Signature introspection handles edge cases
- Functions integrate properly with existing codebase

#### Task 1.4: Validation Checkpoint
```bash
mix test test/unit/program_utilities_test.exs
mix test test/unit/signature_introspection_test.exs  
mix test # Full suite regression check
```

**Success Criteria:**
- ✅ New utility functions fully tested
- ✅ No regressions in existing tests
- ✅ Code coverage maintained or improved

---

## Phase 2: Enhanced Test Infrastructure (Days 4-5)

### Objective
Build sophisticated mocking and testing infrastructure needed for SIMBA workflows before migrating complex tests.

### Implementation: SIMBA Mock Provider

#### Task 2.1: Create Enhanced Mock Provider
**File:** `test/support/simba_mock_provider.ex`

**Based on Requirements from `mock_provider_test.exs`:**
```elixir
defmodule DSPEx.Test.SimbaMockProvider do
  @moduledoc """
  Enhanced mocking infrastructure for SIMBA optimization workflows.
  Extends existing DSPEx.MockClientManager with specialized mocking.
  """

  @spec setup_bootstrap_mocks(list()) :: :ok
  def setup_bootstrap_mocks(teacher_responses)
  
  @spec setup_instruction_generation_mocks(list()) :: :ok  
  def setup_instruction_generation_mocks(instruction_responses)
  
  @spec setup_evaluation_mocks(map()) :: :ok
  def setup_evaluation_mocks(score_map)
  
  @spec setup_simba_optimization_mocks(map()) :: :ok
  def setup_simba_optimization_mocks(config)
  
  @spec reset_all_simba_mocks() :: :ok
  def reset_all_simba_mocks()
end
```

#### Task 2.2: Enhance Test Helper
**File:** `test/support/migration_test_helper.ex`

**Add Migration-Specific Utilities:**
```elixir
defmodule DSPEx.Test.MigrationTestHelper do
  # Helper functions for complex optimization test scenarios
  def create_mock_optimization_config(opts \\ [])
  def simulate_concurrent_optimization_run(program, examples, concurrency)
  def assert_optimization_improves_performance(before_scores, after_scores)
  def create_test_program_with_demos(signature, demo_count)
end
```

### Migration: Enhanced Test Infrastructure Tests

#### Task 2.3: Migrate Mock Provider Tests
**Source → Destination:**
```
TODO_02_PRE_SIMBA/test/unit/mock_provider_test.exs → test/unit/simba_mock_provider_test.exs
```

**Validation Requirements:**
- Mock provider can simulate complex SIMBA workflows
- Mocks integrate cleanly with existing test infrastructure  
- Deterministic test execution under mocked conditions

#### Task 2.4: Validation Checkpoint
```bash
mix test test/unit/simba_mock_provider_test.exs
mix test test/support/ # Test the test infrastructure itself
mix test # Full regression check
```

**Success Criteria:**
- ✅ SIMBA mock provider works correctly
- ✅ Enhanced test helpers are reliable  
- ✅ Foundation ready for complex optimization tests

---

## Phase 3: Critical Concurrent Tests - Category 1 (Days 6-8)

### Objective  
Migrate and implement the **Category 1 tests** identified as "Required Now, Unique, Applicable for SIMBA" in `test_phase2_priorities.md`. These are critical for validating the system can handle SIMBA's demanding concurrent workloads.

### Migration Strategy: One Critical Test at a Time

#### Task 3.1: Client Concurrent Stress Tests
**Source → Destination:**
```
test_phase2/concurrent/client_concurrent_test.exs → test/concurrent/client_stress_test.exs
```

**Implementation Dependencies:**
- Verify `DSPEx.Client` GenServer can handle 100+ concurrent requests
- May require circuit breaker tuning or connection pool adjustments
- Stress test caching consistency under concurrent access

**Expected Challenges:**
- GenServer bottlenecks under high concurrency
- Cache invalidation race conditions  
- Circuit breaker threshold tuning

**Validation:**
```bash
mix test test/concurrent/client_stress_test.exs --max-failures 1
```

#### Task 3.2: Evaluation Concurrent Tests
**Source → Destination:**  
```
test_phase2/concurrent/evaluate_concurrent_test.exs → test/concurrent/evaluate_stress_test.exs
```

**Implementation Dependencies:**
- Ensure `DSPEx.Evaluate` can run parallel evaluations safely
- Validate resource cleanup between concurrent evaluations
- Test evaluation result consistency under load

**Expected Challenges:**
- Evaluation state isolation between concurrent runs
- Resource exhaustion with large concurrent evaluations
- Scoring consistency under load

#### Task 3.3: Teleprompter Concurrent Tests
**Source → Destination:**
```
test_phase2/concurrent/teleprompter_concurrent_test.exs → test/concurrent/teleprompter_stress_test.exs  
```

**Implementation Dependencies:**
- This tests the **core SIMBA workflow** under concurrent load
- Validates concurrent "teacher" program executions
- Ensures optimization results are consistent under concurrency

**Expected Challenges:**
- This is the most complex test - may reveal fundamental architectural issues
- Teacher program state management under concurrency
- Optimization result determinism

**Critical Success Criteria:**
- Must pass reliably - this validates SIMBA foundation
- Performance must be acceptable for 100+ concurrent optimizations
- No memory leaks or resource exhaustion

#### Task 3.4: Validation Checkpoint  
```bash
mix test test/concurrent/ --max-failures 1
mix test # Full regression check with stress tests  
```

**Success Criteria:**
- ✅ All concurrent stress tests pass consistently
- ✅ System remains stable under 100+ concurrent requests  
- ✅ Performance baselines established for SIMBA planning

---

## Phase 4: End-to-End Workflow Validation (Days 9-10)

### Objective
Migrate end-to-end tests that validate complete optimization workflows - the ultimate test of SIMBA readiness.

#### Task 4.1: Performance Benchmark Tests
**Source → Destination:**
```
test_phase2/end_to_end/benchmark_test.exs → test/performance/optimization_benchmarks_test.exs
```

**Implementation Dependencies:**
- Establish performance baselines for optimization workflows
- Measure concurrency speedup vs sequential execution
- Validate caching effectiveness under realistic workloads

**Critical Metrics to Establish:**
- Baseline optimization time for small/medium/large datasets
- Concurrency scaling characteristics  
- Memory usage patterns during optimization
- Cache hit/miss ratios

#### Task 4.2: Complete Workflow Integration Tests
**Source → Destination:**
```
test_phase2/end_to_end/complete_workflow_test.exs → test/integration/full_optimization_workflow_test.exs
```

**Implementation Dependencies:**
- Tests entire pipeline: Signature → Program → Evaluate → Optimize → Validate Improvement
- Validates the exact workflow SIMBA will depend on
- Ensures optimization actually improves program performance

**Critical Validations:**
- End-to-end optimization produces measurable improvement
- Optimized programs maintain signature compatibility
- Full workflow handles errors gracefully
- Integration between all components is seamless

#### Task 4.3: Performance Regression Testing  
**Create New File:** `test/performance/regression_benchmarks_test.exs`

**Purpose:**
- Automated performance regression detection
- Baseline metrics for SIMBA performance comparison
- Early warning system for performance degradation

#### Task 4.4: Validation Checkpoint
```bash
mix test test/performance/ --max-failures 1
mix test test/integration/full_optimization_workflow_test.exs
mix test # Complete system validation
```

**Success Criteria:**
- ✅ End-to-end optimization workflows complete successfully
- ✅ Performance baselines documented and acceptable
- ✅ Full system integration validated
- ✅ Ready for SIMBA layer implementation

---

## Phase 5: Secondary Utility Tests (Days 11-12)

### Objective
Migrate remaining utility and edge case tests that provide comprehensive coverage and debugging capabilities.

### Batch 1: Enhanced Program Tests

#### Task 5.1: Advanced Program Utility Tests
**Source → Destination:**
```
TODO_02_PRE_SIMBA/test/unit/optimized_program_2_test.exs → test/unit/optimized_program_advanced_test.exs
TODO_02_PRE_SIMBA/test/unit/teleprompter_2_test.exs → test/unit/teleprompter_advanced_test.exs
```

**Implementation Dependencies:**
- May require additional utility functions based on test requirements
- Enhanced program introspection capabilities
- Advanced teleprompter state management

### Batch 2: Edge Case and Error Handling Tests

#### Task 5.2: Edge Case Tests  
**Source → Destination:**
```
TODO_02_PRE_SIMBA/test/unit/edge_cases_test.exs → test/unit/system_edge_cases_test.exs
```

**Focus:**
- Malformed input handling
- Resource exhaustion scenarios  
- Network failure simulation
- Graceful degradation testing

#### Task 5.3: Bootstrap and Teleprompter Edge Cases
**Source → Destination:**
```
TODO_02_PRE_SIMBA/test/unit/bootstrap_fewshot_test.exs → test/unit/bootstrap_advanced_test.exs
```

**Implementation Dependencies:**
- Advanced bootstrap generation scenarios
- Error recovery in teleprompter workflows
- Edge cases in few-shot learning

### Batch 3: Integration Test Migrations

#### Task 5.4: Performance Integration Tests
**Source → Destination:**  
```
TODO_02_PRE_SIMBA/test/performance/ → test/performance/
```

**Merge Strategy:**
- Integrate with existing performance tests
- Avoid duplication with Phase 4 benchmark tests
- Focus on component-level performance validation

#### Task 5.5: Final Validation Checkpoint
```bash
mix test test/unit/ --max-failures 1  
mix test test/performance/ --max-failures 1
mix test # Full system validation
```

**Success Criteria:**
- ✅ All utility functions thoroughly tested
- ✅ Edge cases handled gracefully
- ✅ Performance characteristics well understood
- ✅ System ready for production workloads

---

## Phase 6: Final Integration and Cleanup (Day 13)

### Objective
Complete migration, clean up redundancies, and prepare for SIMBA implementation.

#### Task 6.1: Handle Remaining Special Cases
**Files to Review:**
```
test_phase2/examples/client_adapter_example_test.exs
test_phase2/integration_test.exs  
test_phase2/example_test.exs
```

**Strategy:**
- Merge valuable parts into existing test structure
- Convert examples to documentation if not test-worthy
- Delete redundant files identified in `test_phase2_priorities.md` Category 3

#### Task 6.2: Clean Up Migration Artifacts
**Tasks:**
- Remove empty directories from `TODO_02_PRE_SIMBA/test/` and `test_phase2/`
- Update documentation to reflect new test structure
- Archive migration plan and gap analysis in `docs/migration/`

#### Task 6.3: Final System Validation
**Complete Test Suite Run:**
```bash
mix test --cover --max-failures 5
mix dialyzer  
mix credo --strict
```

**Documentation Updates:**
- Update `README.md` with new test structure  
- Document performance baselines for SIMBA team
- Create `TESTING.md` guide for contributors

#### Task 6.4: SIMBA Readiness Assessment  
**Create:** `SIMBA_READINESS_REPORT.md`

**Content:**
- Validation that all critical gaps from `GAP_ANALYSIS_claude.md` are addressed
- Performance baseline documentation
- Test coverage analysis  
- Known limitations and recommendations for SIMBA implementation

---

## Risk Management and Contingency Plans

### High-Risk Phases

#### Phase 3 (Concurrent Tests) - Highest Risk
**Risk:** Concurrent stress tests may reveal fundamental architectural issues

**Mitigation:**
- Start with lower concurrency levels and scale up gradually
- Have architecture review scheduled if major issues emerge  
- Fallback to sequential execution patterns if needed

**Contingency:** If concurrent tests fail consistently:
1. Document specific failure modes
2. Implement fixes for critical issues only
3. Defer complex concurrency to post-SIMBA if non-critical

#### Phase 4 (End-to-End) - Medium Risk  
**Risk:** Full workflow tests may expose integration issues

**Mitigation:**
- Break down workflow tests into smaller components
- Isolate issues to specific integration points
- Have rollback plan for each integration test

### Low-Risk Contingencies

#### Missing Utility Functions
**If implementation is more complex than expected:**
- Implement minimal viable versions first
- Add comprehensive features in follow-up phases
- Document technical debt for post-SIMBA cleanup

#### Test Migration Conflicts
**If tests conflict with existing suite:**
- Rename conflicting tests with `_migrated` suffix
- Merge similar tests rather than duplicate
- Archive conflicting tests for later analysis

---

## Success Metrics and Validation

### Phase-Level Success Criteria

**Phase 1-2 Success:**
- All utility functions implemented and tested
- Enhanced mock infrastructure operational
- No regression in existing test suite

**Phase 3-4 Success (Critical for SIMBA):**
- 100+ concurrent request handling validated
- End-to-end optimization workflows operational  
- Performance baselines established and documented

**Phase 5-6 Success:**
- Comprehensive edge case coverage
- Clean, maintainable test suite structure
- Full system validation passing

### Overall Migration Success Criteria

#### Functional Validation
- [ ] All migrated tests pass consistently
- [ ] No regressions in existing functionality  
- [ ] All critical gaps from gap analysis addressed
- [ ] Performance meets SIMBA requirements

#### Quality Validation  
- [ ] Test coverage maintained or improved
- [ ] Code quality metrics (Credo, Dialyzer) pass
- [ ] Documentation updated and accurate
- [ ] Technical debt properly documented

#### SIMBA Readiness Validation
- [ ] Concurrent optimization workflows validated
- [ ] Performance baselines meet SIMBA needs
- [ ] All Category 1 tests from `test_phase2_priorities.md` implemented
- [ ] System architecture ready for SIMBA layer

---

## Post-Migration Actions

### Immediate (Days 14-15)
1. **Archive migration materials** in `docs/migration/`
2. **Create SIMBA integration guide** based on lessons learned
3. **Update team documentation** with new test procedures  
4. **Performance baseline documentation** for SIMBA planning

### Medium-term (Weeks 3-4)
1. **Monitor system stability** under normal workloads
2. **Gather performance data** from production-like scenarios
3. **Refine test suite** based on real-world usage patterns
4. **Begin SIMBA implementation** with confidence in foundation

---

## Conclusion

This migration plan addresses the critical finding from `GAP_ANALYSIS_claude.md` that **"the DSPEx foundation is much more complete than originally assessed"** while systematically implementing the missing pieces needed for SIMBA integration.

**Key Strategic Decisions:**
1. **Prioritize Category 1 tests** identified as critical for SIMBA
2. **Implement missing utilities just-in-time** during migration
3. **Validate incrementally** to catch issues early
4. **Build comprehensive test infrastructure** to support SIMBA development

**Expected Outcome:** 
A robust, well-tested foundation ready for SIMBA integration with:
- ✅ All critical utility functions implemented  
- ✅ Concurrent workflow validation complete
- ✅ Performance baselines established
- ✅ **SIMBA Integration Readiness: 🟢 95% Ready**

The plan transforms the current **🟡 85% Ready** assessment to **🟢 95% Ready** through systematic gap closure and comprehensive validation.
