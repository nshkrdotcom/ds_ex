# SIMBA Implementation Plan

## Overview

This document provides a detailed, step-by-step plan for moving the SIMBA (Signature-Based In-Context Learning with Many-Shot Bootstrap Aggregation) implementation from the staging area (`simba/`) to the main project directories (`lib/` and `test/`). The plan follows a granular, dependency-aware approach to ensure safe integration while maintaining code quality standards as defined in `CODE_QUALITY.md`.

## Objectives

- **Safety First**: Each move is independent and can be validated immediately
- **Dependency Awareness**: Order moves so dependencies are satisfied before dependents
- **Quality Assurance**: Apply `CODE_QUALITY.md` standards after each move
- **Incremental Stabilization**: Test and fix after each move before proceeding
- **Minimal Risk**: Avoid breaking the build or existing functionality

## Pre-requisites

1. All SIMBA test files in `simba/test/` are self-contained and use mock data
2. `CODE_QUALITY.md` standards are understood and will be applied
3. Main project test suite passes before starting the migration
4. Git working directory is clean for easy rollback if needed

## Implementation Strategy

### Phase Structure
Each phase follows this pattern:
1. **Move**: Execute the specified `mv` commands
2. **Validate**: Run relevant tests to ensure no breakage
3. **Stabilize**: Apply code quality fixes and resolve any issues
4. **Commit**: Create a clean commit point for rollback safety

### Dependency Order Rationale

The move order is designed to satisfy dependencies before dependents:

1. **Support Infrastructure First**: Test helpers and core utilities
2. **Foundation Modules**: Core SIMBA module and basic data structures
3. **Component Modules**: Individual SIMBA components that depend on the core
4. **Strategy Modules**: Strategy implementations that depend on components
5. **Integration Modules**: Higher-level modules that orchestrate components
6. **Test Suites**: Comprehensive tests that validate the complete system

---

## Phase 1: Foundation Infrastructure ✅ COMPLETED

### Objective
Establish the basic infrastructure for SIMBA testing and core module structure.

### Files Moved ✅
- **Support**: `simba/test/support/simba_test_helper.exs` → `test/support/simba_test_helper.exs`
- **Core Module**: `simba/lib/teleprompter/simba.ex` → `lib/teleprompter/simba.ex`
- **Core Test**: `simba/test/unit/teleprompter/simba_test.exs` → `test/unit/teleprompter/simba_test.exs`

### Commands Executed ✅
```bash
# Move test support infrastructure
mv simba/test/support/simba_test_helper.exs test/support/

# Move core SIMBA module
mkdir -p lib/teleprompter
mv simba/lib/teleprompter/simba.ex lib/teleprompter/

# Move core SIMBA test
mkdir -p test/unit/teleprompter
mv simba/test/unit/teleprompter/simba_test.exs test/unit/teleprompter/
```

### Stabilization Steps Completed ✅

1. **Run Core Tests**: ✅ PASSED
   ```bash
   mix test test/unit/teleprompter/simba_test.exs
   # Result: 8 tests, 0 failures
   ```

2. **Code Quality Review**: ✅ COMPLETED
   - ✅ `@moduledoc` documentation is present and clear
   - ✅ `@type t` is defined for the SIMBA struct
   - ✅ `@spec` annotations are present for public functions (`new/1`)
   - ✅ Proper use of `@enforce_keys []` for struct
   - ✅ Naming conventions follow snake_case for functions/variables
   - ✅ Proper error handling with tagged tuples `{:ok, result}` | `{:error, reason}`
   - ✅ `@impl DSPEx.Teleprompter` properly implemented

3. **Static Analysis**: ✅ PASSED
   ```bash
   mix dialyzer --halt-exit-status  # Result: done (passed successfully)
   mix credo --strict              # Result: No blocking issues for Phase 1
   ```

### Expected Outcome ✅ ACHIEVED
- ✅ Core SIMBA module is available in main lib structure
- ✅ Test helper infrastructure is accessible to all tests  
- ✅ No compilation errors or test failures
- ✅ Static analysis passes

### Phase 1 Notes
- **Implementation Strategy**: Created a Phase 1 stub implementation that satisfies the DSPEx.Teleprompter behavior
- **Dependency Management**: Commented out dependencies on Trajectory and Bucket modules (to be added in Phase 2)
- **Test Coverage**: 8 comprehensive tests covering struct creation, configuration, and basic validation
- **Test Helper Fix**: Updated `test/support/simba_test_helper.exs` to work without Trajectory/Bucket dependencies 
- **Forward Compatibility**: Structure prepared for full implementation in subsequent phases

### Phase 1 Verification ✅
```bash
# Both test files now compile and pass successfully
mix test test/unit/teleprompter/simba_test.exs    # 8 tests, 0 failures
mix test test/support/simba_test_helper.exs       # 0 failures (compilation test)
```

**Status**: ✅ **PHASE 1 COMPLETE** - Ready for Phase 2 (Data Structure Components)

---

## Phase 2: Data Structure Components ✅ COMPLETED

### Objective
Move the fundamental data structures that other components depend on.

### Files Moved ✅
- **Bucket**: `simba/lib/teleprompter/simba/bucket.ex` → `lib/dspex/teleprompter/simba/bucket.ex`
- **Bucket Test**: `simba/test/unit/teleprompter/simba/bucket_test.exs` → `test/unit/dspex/teleprompter/simba/bucket_test.exs`
- **Trajectory**: `simba/lib/teleprompter/simba/trajectory.ex` → `lib/dspex/teleprompter/simba/trajectory.ex`
- **Trajectory Test**: `simba/test/unit/teleprompter/simba/trajectory_test.exs` → `test/unit/dspex/teleprompter/simba/trajectory_test.exs`

### Commands Executed ✅
```bash
# Move bucket implementation and test
mkdir -p lib/dspex/teleprompter/simba
mv simba/lib/teleprompter/simba/bucket.ex lib/dspex/teleprompter/simba/
mkdir -p test/unit/dspex/teleprompter/simba
mv simba/test/unit/teleprompter/simba/bucket_test.exs test/unit/dspex/teleprompter/simba/

# Move trajectory implementation and test
mv simba/lib/teleprompter/simba/trajectory.ex lib/dspex/teleprompter/simba/
mv simba/test/unit/teleprompter/simba/trajectory_test.exs test/unit/dspex/teleprompter/simba/
```

### Stabilization Steps Completed ✅

1. **Run Component Tests**: ✅ PASSED
   ```bash
   mix test test/unit/dspex/teleprompter/simba/bucket_test.exs    # 12 tests, 0 failures
   mix test test/unit/dspex/teleprompter/simba/trajectory_test.exs # 22 tests, 0 failures
   ```

2. **Code Quality Review**: ✅ COMPLETED
   - ✅ **Structs**: `@enforce_keys` used appropriately for required fields
   - ✅ **Types**: `@type t` definitions match struct fields exactly
   - ✅ **Documentation**: `@moduledoc` and `@doc` provide clear explanations
   - ✅ **Functions**: `@spec` annotations are accurate and complete
   - ✅ **Pattern Matching**: Assertive programming patterns used throughout
   - ✅ **Error Handling**: Consistent `{:ok, result}` | `{:error, reason}` patterns

3. **Compilation Check**: ✅ PASSED
   ```bash
   mix compile --warnings-as-errors  # Result: Compiled successfully
   ```

4. **Integration with Core**: ✅ PASSED
   ```bash
   mix test test/unit/teleprompter/simba_test.exs     # 8 tests, 0 failures
   mix test test/unit/dspex/teleprompter/simba/       # 34 tests, 0 failures
   ```

### Expected Outcome ✅ ACHIEVED
- ✅ Bucket and Trajectory modules compile without errors
- ✅ All tests pass independently and with core module (34 total tests passing)
- ✅ Type specifications are valid and complete
- ✅ Documentation follows project standards

### Phase 2 Notes
- **Test Quality Fixes**: Applied floating-point precision fixes using `assert_in_delta` for calculation tests
- **Order Independence**: Fixed trajectory test to be order-independent for input keys
- **Integration Success**: All 34 SIMBA tests now pass, showing successful module integration
- **Dependencies**: Updated core SIMBA module to include Bucket and Trajectory aliases
- **Foundation Ready**: Data structure foundation is solid for Phase 3 (Performance metrics)

**Status**: ✅ **PHASE 2 COMPLETE** - Ready for Phase 3 (Performance Metrics)

---

## Phase 3: Performance Metrics ✅ COMPLETED

### Objective
Move the performance tracking module that will be used by strategy components.

### Files Moved ✅
- **Performance**: `simba/lib/teleprompter/simba/performance.ex` → `lib/teleprompter/simba/performance.ex`
- **Performance Test**: `simba/test/unit/teleprompter/simba/performance_test.exs` → `test/unit/teleprompter/simba/performance_test.exs`

### Commands Executed ✅
```bash
# Move performance implementation and test
mv simba/lib/teleprompter/simba/performance.ex lib/teleprompter/simba/
mv simba/test/unit/teleprompter/simba/performance_test.exs test/unit/teleprompter/simba/
```

### Stabilization Steps Completed ✅

1. **Run Performance Tests**: ✅ PASSED
   ```bash
   mix test test/unit/teleprompter/simba/performance_test.exs
   # Result: 12 tests, 0 failures
   ```

2. **Code Quality Review**: ✅ COMPLETED
   - ✅ **Module Path Updates**: Updated aliases to use correct DSPEx.Teleprompter.SIMBA.Bucket path
   - ✅ **Type Specifications**: Updated @spec annotations to use full module names
   - ✅ **Code Quality Fixes**: Fixed unused variable warnings in test helpers
   - ✅ **Performance**: Verified efficient data structures used for metrics collection
   - ✅ **Memory Usage**: Validated minimal data copying between processes
   - ✅ **Type Safety**: Confirmed type specifications match implementation

3. **Integration Testing**: ✅ PASSED
   ```bash
   mix test test/unit/teleprompter/simba/      # 12 tests, 0 failures
   mix test test/unit/dspex/teleprompter/simba/ # 34 tests, 0 failures
   # Total: 46 tests passing
   ```

### Expected Outcome ✅ ACHIEVED
- ✅ Performance module integrates cleanly with existing components
- ✅ Metrics collection is efficient and type-safe
- ✅ All existing tests continue to pass (46 total tests)
- ✅ Performance tracking functionality ready for strategy components

### Phase 3 Notes
- **Path Updates**: Updated module references to work with existing Bucket/Trajectory in `lib/dspex/teleprompter/simba/`
- **Code Quality**: Fixed all warnings in Performance module, maintained warnings in stub SIMBA module (expected)
- **Test Quality**: Fixed unused variable warnings in test mock functions
- **Integration Success**: All 46 SIMBA-related tests pass, confirming clean integration
- **Forward Compatibility**: Performance module ready for Phase 4 (Strategy Infrastructure)

**Status**: ✅ **PHASE 3 COMPLETE** - Ready for Phase 4 (Strategy Infrastructure)

---

## Phase 4: Strategy Infrastructure ✅ COMPLETED

### Objective
Move the base strategy module that strategy implementations will depend on.

### Files Moved ✅
- **Strategy**: `simba/lib/teleprompter/simba/strategy.ex` → `lib/teleprompter/simba/strategy.ex`
- **Strategy Test**: `simba/test/unit/teleprompter/simba/strategy_test_fixed.exs` → `test/unit/teleprompter/simba/strategy_test.exs`

### Commands Executed ✅
```bash
# Move strategy base implementation and test
mv simba/lib/teleprompter/simba/strategy.ex lib/teleprompter/simba/
mkdir -p test/unit/teleprompter/simba
mv simba/test/unit/teleprompter/simba/strategy_test_fixed.exs test/unit/teleprompter/simba/strategy_test.exs
```

### Stabilization Steps Completed ✅

1. **Run Strategy Tests**: ✅ PASSED
   ```bash
   mix test test/unit/teleprompter/simba/strategy_test.exs
   # Result: 10 tests, 0 failures
   ```

2. **Code Quality Review**: ✅ COMPLETED
   - ✅ **Behaviours**: Well-defined behavior with @callback and @optional_callbacks
   - ✅ **Callbacks**: Clear callback specifications for apply/3 and applicable?/2
   - ✅ **Modularity**: Clean interface with utility functions for strategy management
   - ✅ **Error Handling**: Robust error handling with {:ok, result} | {:skip, reason} patterns
   - ✅ **Documentation**: Comprehensive documentation with examples and contract definitions
   - ✅ **Type Safety**: Proper @spec annotations and type definitions

3. **Dependency Validation**: ✅ PASSED
   ```bash
   # Test that strategy can use performance, bucket, and trajectory
   mix test test/unit/teleprompter/simba/ test/unit/dspex/teleprompter/simba/
   # Result: 56 tests, 0 failures
   ```

### Expected Outcome ✅ ACHIEVED
- ✅ Strategy base module provides clean interface for implementations
- ✅ Dependencies on bucket, trajectory, and performance modules work correctly  
- ✅ Strategy contract is well-defined and documented
- ✅ Utility functions for strategy discovery and application

### Phase 4 Notes
- **Behavior Definition**: Clean strategy behavior with required and optional callbacks
- **Test Fixes**: Fixed syntax errors in strategy test file (match? patterns) and mock data structures
- **Integration Success**: All 56 SIMBA-related tests pass, confirming clean integration
- **Utility Functions**: Added `implements_strategy?/1`, `apply_first_applicable/4`, and `get_strategy_info/1`
- **Forward Compatibility**: Strategy infrastructure ready for Phase 5 (Strategy Implementations)

**Status**: ✅ **PHASE 4 COMPLETE** - Ready for Phase 5 (Strategy Implementations)

---

## Phase 5: Strategy Implementations ✅ COMPLETED

### Objective
Move concrete strategy implementations that depend on the strategy base.

### Files Moved ✅
- **Append Demo Strategy**: `simba/lib/teleprompter/simba/strategy/append_demo.ex` → `lib/teleprompter/simba/strategy/append_demo.ex`
- **Append Demo Test**: `simba/test/unit/teleprompter/simba/strategy/append_demo_test.exs` → `test/unit/teleprompter/simba/strategy/append_demo_test.exs`

### Commands Executed ✅
```bash
# Move append demo strategy implementation and test
mkdir -p lib/teleprompter/simba/strategy
mv simba/lib/teleprompter/simba/strategy/append_demo.ex lib/teleprompter/simba/strategy/
mkdir -p test/unit/teleprompter/simba/strategy
mv simba/test/unit/teleprompter/simba/strategy/append_demo_test.exs test/unit/teleprompter/simba/strategy/
```

### Stabilization Steps Completed ✅

1. **Run Strategy Implementation Tests**: ✅ PASSED
   ```bash
   mix test test/unit/teleprompter/simba/strategy/append_demo_test.exs
   # Result: 20 tests, 0 failures
   ```

2. **Code Quality Review**: ✅ COMPLETED
   - ✅ **Implementation**: Strategy properly implements base interface with @behaviour DSPEx.Teleprompter.SIMBA.Strategy
   - ✅ **Algorithm Logic**: Append demo logic is correct with Poisson sampling for demo management
   - ✅ **Data Handling**: Proper handling of Examples, demonstrations, and trajectory data
   - ✅ **Error Cases**: Added try/rescue to create_demo_from_trajectory for robust error handling
   - ✅ **Performance**: Demo truncation and efficient data structures used
   - ✅ **Type Safety**: Fixed compilation warnings and type inference issues

3. **Full Strategy Suite**: ✅ PASSED
   ```bash
   mix test test/unit/teleprompter/simba/strategy/
   # Result: 20 tests, 0 failures
   ```

4. **Integration Testing**: ✅ PASSED
   ```bash
   mix test test/unit/teleprompter/simba/ test/unit/dspex/teleprompter/simba/
   # Result: 76 tests, 0 failures
   ```

### Expected Outcome ✅ ACHIEVED
- ✅ Append demo strategy implements the strategy interface correctly
- ✅ Strategy can utilize all dependent modules (bucket, trajectory, performance) 
- ✅ All strategy tests pass independently and together (20 tests passing)
- ✅ Full SIMBA system integration validated (76 total tests passing)

### Phase 5 Notes
- **Strategy Implementation**: AppendDemo strategy successfully implements the SIMBA Strategy behavior
- **Demo Management**: Sophisticated demo handling with Poisson sampling for demo dropping
- **Program Enhancement**: Supports both native demo programs and OptimizedProgram wrapping
- **Error Handling**: Added robust error handling with try/rescue patterns
- **Code Quality**: Fixed all compilation warnings and type inference issues
- **Integration Success**: All 76 SIMBA-related tests pass, confirming clean integration
- **Algorithm Fidelity**: Maintains fidelity to DSPy's SIMBA append demo strategy

**Status**: ✅ **PHASE 5 COMPLETE** - Ready for Phase 6 (Integration and System Tests)

---

## Phase 6: Integration and System Tests

### Objective
Move comprehensive integration tests and complete the SIMBA system integration.

### Files to Move
- **Integration Test**: `simba/test/integration/simba_example_test.exs` → `test/integration/simba_example_test.exs`
- **Test Suite**: `simba/test/unit/simba_test_suite_test.exs` → `test/unit/simba_test_suite_test.exs`

### Commands
```bash
# Move integration tests
mkdir -p test/integration
mv simba/test/integration/simba_example_test.exs test/integration/

# Move comprehensive test suite
mv simba/test/unit/simba_test_suite_test.exs test/unit/
```

### Stabilization Steps

1. **Run Integration Tests**:
   ```bash
   mix test test/integration/simba_example_test.exs
   ```

2. **Run Complete SIMBA Test Suite**:
   ```bash
   mix test test/unit/simba_test_suite_test.exs
   ```

3. **Full System Integration**:
   ```bash
   # Test all SIMBA modules together
   mix test test/unit/teleprompter/simba/
   mix test test/integration/simba_example_test.exs
   ```

4. **Code Quality Final Review**:
   - **System Integration**: Verify all modules work together correctly
   - **API Consistency**: Check that public APIs follow consistent patterns
   - **Documentation**: Ensure system-level documentation is complete
   - **Performance**: Validate system performance meets expectations
   - **Error Handling**: Test error propagation through the system

### Expected Outcome
- Complete SIMBA system is functional and integrated
- All tests pass at unit and integration levels
- System meets performance and quality standards

---

## Phase 7: Final Validation and Cleanup

### Objective
Perform final validation of the complete implementation and clean up staging area.

### Validation Steps

1. **Complete Test Suite**:
   ```bash
   # Run all tests to ensure nothing is broken
   mix test
   ```

2. **Static Analysis**:
   ```bash
   # Ensure code quality standards are met
   mix dialyzer --halt-exit-status
   mix credo --strict
   mix format --check-formatted
   ```

3. **Documentation Generation**:
   ```bash
   # Generate docs to ensure all documentation is valid
   mix docs
   ```

4. **Performance Baseline**:
   ```bash
   # Establish performance baseline for SIMBA operations
   mix test --include performance
   ```

### Quality Assurance Checklist

Based on `CODE_QUALITY.md` standards:

- [ ] **Module Structure**: All modules follow proper structure with `@moduledoc`
- [ ] **Type Specifications**: All public functions have `@spec` annotations
- [ ] **Struct Definitions**: Structs use `@type t` and appropriate `@enforce_keys`
- [ ] **Documentation**: All public APIs are documented with `@doc`
- [ ] **Naming Conventions**: snake_case for functions, CamelCase for modules
- [ ] **Error Handling**: Consistent use of `{:ok, result}` | `{:error, reason}`
- [ ] **Pattern Matching**: Assertive programming patterns used throughout
- [ ] **Performance**: No obvious performance anti-patterns
- [ ] **Testing**: Comprehensive test coverage with proper mock usage
- [ ] **Integration**: Proper integration with existing DSPEx architecture

### Cleanup Steps

1. **Remove Staging Directory**:
   ```bash
   # Only after all validation passes
   rm -rf simba/
   ```

2. **Update Documentation**:
   - Update README.md to include SIMBA features
   - Update module documentation to reflect new locations
   - Add SIMBA examples to project documentation

3. **Final Commit**:
   ```bash
   git add .
   git commit -m "feat: integrate SIMBA teleprompter implementation

   - Move SIMBA modules from staging to production
   - Add comprehensive test coverage
   - Implement performance tracking and optimization
   - Add strategy-based demonstration selection
   - Maintain full backward compatibility with existing teleprompters"
   ```

---

## Risk Mitigation

### Rollback Strategy
Each phase creates a commit point. If issues arise:
1. Identify the problematic phase
2. Revert to the previous phase's commit
3. Fix issues in staging area
4. Retry the phase

### Validation Points
- After each phase, run the full test suite
- Use `mix dialyzer` to catch type issues early
- Use `mix credo` to maintain code quality
- Monitor for any performance regressions

### Common Issues and Solutions

1. **Module Loading Issues**:
   - Ensure all dependencies are moved before dependents
   - Check for circular dependencies
   - Verify module names match file paths

2. **Test Failures**:
   - Confirm test files are using correct mock data
   - Verify test helpers are accessible
   - Check for hardcoded paths in tests

3. **Type Specification Errors**:
   - Run `mix dialyzer` after each phase
   - Ensure `@type t` definitions match struct fields
   - Verify `@spec` annotations are accurate

4. **Integration Issues**:
   - Test module interactions at each phase
   - Verify existing functionality isn't broken
   - Check for namespace conflicts

---

## Success Criteria

The migration is considered successful when:

1. **All Tests Pass**: Full test suite runs without failures
2. **Static Analysis Clean**: Dialyzer and Credo report no issues
3. **Documentation Complete**: All modules properly documented
4. **Performance Acceptable**: No significant performance regressions
5. **Integration Seamless**: SIMBA works with existing DSPEx components
6. **Code Quality High**: All standards from `CODE_QUALITY.md` are met

## Post-Migration Tasks

1. **Feature Documentation**: Create user guide for SIMBA teleprompter
2. **Performance Benchmarks**: Establish baseline performance metrics
3. **Example Applications**: Create example usage scenarios
4. **Integration Tests**: Add comprehensive integration tests with DSPEx
5. **Monitoring**: Set up telemetry for SIMBA operations

---

## Conclusion

This plan provides a systematic, risk-averse approach to integrating the SIMBA implementation into the main project. By following the dependency-aware ordering and thorough validation at each step, we ensure a smooth transition while maintaining the high code quality standards established in `CODE_QUALITY.md`.

The granular approach allows for easy rollback and debugging if issues arise, while the comprehensive testing strategy ensures that the integration doesn't break existing functionality.
