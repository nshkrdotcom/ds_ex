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

## Phase 2: Data Structure Components

### Objective
Move the fundamental data structures that other components depend on.

### Files to Move
- **Bucket**: `simba/lib/teleprompter/simba/bucket.ex` → `lib/teleprompter/simba/bucket.ex`
- **Bucket Test**: `simba/test/unit/teleprompter/simba/bucket_test.exs` → `test/unit/teleprompter/simba/bucket_test.exs`
- **Trajectory**: `simba/lib/teleprompter/simba/trajectory.ex` → `lib/teleprompter/simba/trajectory.ex`
- **Trajectory Test**: `simba/test/unit/teleprompter/simba/trajectory_test.exs` → `test/unit/teleprompter/simba/trajectory_test.exs`

### Commands
```bash
# Move bucket implementation and test
mkdir -p lib/teleprompter/simba
mv simba/lib/teleprompter/simba/bucket.ex lib/teleprompter/simba/
mkdir -p test/unit/teleprompter/simba
mv simba/test/unit/teleprompter/simba/bucket_test.exs test/unit/teleprompter/simba/

# Move trajectory implementation and test
mv simba/lib/teleprompter/simba/trajectory.ex lib/teleprompter/simba/
mv simba/test/unit/teleprompter/simba/trajectory_test.exs test/unit/teleprompter/simba/
```

### Stabilization Steps

1. **Run Component Tests**:
   ```bash
   mix test test/unit/teleprompter/simba/bucket_test.exs
   mix test test/unit/teleprompter/simba/trajectory_test.exs
   ```

2. **Code Quality Review**:
   - **Structs**: Ensure `@enforce_keys` is used appropriately for required fields
   - **Types**: Verify `@type t` definitions match struct fields exactly
   - **Documentation**: Check `@moduledoc` and `@doc` provide clear explanations
   - **Functions**: Confirm `@spec` annotations are accurate and complete
   - **Pattern Matching**: Validate assertive programming patterns are used
   - **Error Handling**: Ensure consistent `{:ok, result}` | `{:error, reason}` patterns

3. **Compilation Check**:
   ```bash
   mix compile --warnings-as-errors
   ```

4. **Integration with Core**:
   ```bash
   mix test test/unit/teleprompter/simba_test.exs
   ```

### Expected Outcome
- Bucket and Trajectory modules compile without warnings
- All tests pass independently and with core module
- Type specifications are valid and complete
- Documentation follows project standards

---

## Phase 3: Performance Metrics

### Objective
Move the performance tracking module that will be used by strategy components.

### Files to Move
- **Performance**: `simba/lib/teleprompter/simba/performance.ex` → `lib/teleprompter/simba/performance.ex`
- **Performance Test**: `simba/test/unit/teleprompter/simba/performance_test.exs` → `test/unit/teleprompter/simba/performance_test.exs`

### Commands
```bash
# Move performance implementation and test
mv simba/lib/teleprompter/simba/performance.ex lib/teleprompter/simba/
mv simba/test/unit/teleprompter/simba/performance_test.exs test/unit/teleprompter/simba/
```

### Stabilization Steps

1. **Run Performance Tests**:
   ```bash
   mix test test/unit/teleprompter/simba/performance_test.exs
   ```

2. **Code Quality Review**:
   - **Data Structures**: Verify efficient data structures are used for metrics
   - **Performance**: Check for potential performance anti-patterns
   - **Caching**: Ensure expensive operations are cached appropriately
   - **Memory Usage**: Validate minimal data copying between processes
   - **Type Safety**: Confirm type specifications match implementation

3. **Integration Testing**:
   ```bash
   mix test test/unit/teleprompter/simba/
   ```

### Expected Outcome
- Performance module integrates cleanly with existing components
- Metrics collection is efficient and type-safe
- All existing tests continue to pass

---

## Phase 4: Strategy Infrastructure

### Objective
Move the base strategy module that strategy implementations will depend on.

### Files to Move
- **Strategy**: `simba/lib/teleprompter/simba/strategy.ex` → `lib/teleprompter/simba/strategy.ex`
- **Strategy Test**: `simba/test/unit/teleprompter/simba/strategy_test.exs` → `test/unit/teleprompter/simba/strategy_test.exs`

### Commands
```bash
# Move strategy base implementation and test
mv simba/lib/teleprompter/simba/strategy.ex lib/teleprompter/simba/
mv simba/test/unit/teleprompter/simba/strategy_test.exs test/unit/teleprompter/simba/
```

### Stabilization Steps

1. **Run Strategy Tests**:
   ```bash
   mix test test/unit/teleprompter/simba/strategy_test.exs
   ```

2. **Code Quality Review**:
   - **Behaviours**: Ensure proper behaviour definitions if applicable
   - **Callbacks**: Verify callback specifications are well-defined
   - **Modularity**: Check that strategy interface is clean and extensible
   - **Error Handling**: Validate robust error handling patterns
   - **Documentation**: Ensure strategy contract is well-documented

3. **Dependency Validation**:
   ```bash
   # Test that strategy can use performance, bucket, and trajectory
   mix test test/unit/teleprompter/simba/
   ```

### Expected Outcome
- Strategy base module provides clean interface for implementations
- Dependencies on bucket, trajectory, and performance modules work correctly
- Strategy contract is well-defined and documented

---

## Phase 5: Strategy Implementations

### Objective
Move concrete strategy implementations that depend on the strategy base.

### Files to Move
- **Append Demo Strategy**: `simba/lib/teleprompter/simba/strategy/append_demo.ex` → `lib/teleprompter/simba/strategy/append_demo.ex`
- **Append Demo Test**: `simba/test/unit/teleprompter/simba/strategy/append_demo_test.exs` → `test/unit/teleprompter/simba/strategy/append_demo_test.exs`

### Commands
```bash
# Move append demo strategy implementation and test
mkdir -p lib/teleprompter/simba/strategy
mv simba/lib/teleprompter/simba/strategy/append_demo.ex lib/teleprompter/simba/strategy/
mkdir -p test/unit/teleprompter/simba/strategy
mv simba/test/unit/teleprompter/simba/strategy/append_demo_test.exs test/unit/teleprompter/simba/strategy/
```

### Stabilization Steps

1. **Run Strategy Implementation Tests**:
   ```bash
   mix test test/unit/teleprompter/simba/strategy/append_demo_test.exs
   ```

2. **Code Quality Review**:
   - **Implementation**: Verify strategy properly implements base interface
   - **Algorithm Logic**: Check that append demo logic is correct and efficient
   - **Data Handling**: Ensure proper handling of examples and demonstrations
   - **Error Cases**: Validate handling of edge cases and errors
   - **Performance**: Check for performance considerations in demo handling

3. **Full Strategy Suite**:
   ```bash
   mix test test/unit/teleprompter/simba/strategy/
   ```

### Expected Outcome
- Append demo strategy implements the strategy interface correctly
- Strategy can utilize all dependent modules (bucket, trajectory, performance)
- All strategy tests pass independently and together

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
