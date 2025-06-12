# DSPEx SIMBA Integration Implementation Plan

**Plan Date:** June 11, 2025  
**Context:** Critical API contract gap identified - broken tests expect non-existent APIs  
**Current Status:** Must implement DSPEx-SIMBA contract before proceeding with SIMBA integration  
**Priority:** **CRITICAL BLOCKER** - SIMBA integration impossible without this

---

## Executive Summary

**🚨 CRITICAL ISSUE IDENTIFIED:** Recent test modifications revealed that tests were expecting API contracts that don't exist in the DSPEx implementation. The agent updated tests to expect APIs like `Program.safe_program_info/1`, `Program.has_demos?/1`, enhanced `forward/3`, etc., but never implemented these APIs in the library code.

**Root Cause:** No formal API contract was defined between DSPEx and SIMBA, leading to broken assumptions about interfaces.

**Solution:** Implement comprehensive DSPEx-SIMBA API contract using technical artifacts in `/simba_api/` directory.

### Current Situation

1. **❌ Broken Tests**: Tests expect APIs that don't exist in implementation
2. **❌ No API Contract**: No formal specification of what SIMBA needs from DSPEx  
3. **❌ Implementation Gap**: Missing critical introspection and execution APIs
4. **✅ Clear Solution**: Complete technical artifacts ready for implementation in `simba_api/`

---

## TASK 1: DSPEx-SIMBA API Contract Implementation (CRITICAL)

**Priority:** 🔴 **ABSOLUTE BLOCKER** - Must complete before any SIMBA work  
**Timeline:** 2-3 days focused implementation  
**Resources:** Complete technical artifacts available in `simba_api/` directory

### Problem Analysis

The recent git diff showed test modifications that exposed a fundamental issue:

1. **Tests Updated**: Agent modified tests to expect certain DSPEx APIs
2. **No Implementation**: These APIs were never actually implemented in the library code
3. **Parse Errors**: Tests are now broken because they reference non-existent functions
4. **Contract Missing**: No formal API specification exists between DSPEx and SIMBA

### Technical Artifacts Available

The `simba_api/` directory contains complete implementation guidance:

- **`SIMBA_API_CONTRACT_SPEC.md`** - Formal API contract specification
- **`SIMBA_CONTRACT_IMPL_ROADMAP.md`** - 3-day phased implementation plan  
- **`SIMBA_CONTRACT_IMPL_CODE_PATCHES.md`** - Ready-to-apply code modifications
- **`SIMBA_CONTRACT_IMPL_SUMMARY.md`** - Executive summary and timeline
- **`test/integration/simba_contract_validation_test.exs`** - Contract validation tests
- **`test/integration/simba_integration_smoke_test.exs`** - End-to-end workflow tests

### Critical APIs to Implement

#### 1. Program Contract Functions (lib/dspex/program.ex)
```elixir
# Missing functions that SIMBA expects:
@spec forward(t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
@spec program_type(t()) :: :predict | :optimized | :custom | :unknown  
@spec safe_program_info(t()) :: %{type: atom(), name: atom(), has_demos: boolean(), signature: atom()}
@spec has_demos?(t()) :: boolean()
```

#### 2. OptimizedProgram Enhancements (lib/dspex/optimized_program.ex)
```elixir
# SIMBA metadata support
@spec get_simba_metadata(t()) :: map()
@spec put_simba_metadata(t(), map()) :: t()
@spec has_simba_capability?(t(), atom()) :: boolean()
```

#### 3. ConfigManager SIMBA Support (lib/dspex/services/config_manager.ex)
```elixir
# SIMBA configuration paths
@spec get_with_default(String.t(), term()) :: term()
@spec get_simba_config() :: map()
```

#### 4. Client Response Stability (lib/dspex/client.ex)
```elixir
# Stable response format for instruction generation
@spec categorize_error(term()) :: :timeout | :rate_limit | :auth | :server | :network | :unknown
```

### Implementation Strategy

#### Step 1: Discard Broken Tests (Day 1 Morning)
```bash
# Reset test files to working state
git checkout HEAD -- test/integration/error_recovery_test.exs
git checkout HEAD -- test/unit/program_utilities_test.exs
# (any other broken test files from diff)

# Verify system works again
mix test
mix dialyzer
```

#### Step 2: Apply Contract Implementation Patches (Day 1-2)

**Phase 1: Core Program Contract** 
- Apply patches to `lib/dspex/program.ex` for missing introspection functions
- Implement `forward/3` with timeout and correlation_id support
- Add telemetry events for SIMBA tracking

**Phase 2: Service Integration**
- Enhance `lib/dspex/services/config_manager.ex` for SIMBA configuration
- Update `lib/dspex/optimized_program.ex` with metadata support  
- Stabilize `lib/dspex/client.ex` response formats

**Phase 3: Completion** 
- Fix `lib/dspex/teleprompter/bootstrap_fewshot.ex` empty demo handling
- Add SIMBA telemetry events to `lib/dspex/services/telemetry_setup.ex`

#### Step 3: Add Contract Validation Tests (Day 2-3)
```bash
# Copy contract tests from simba_api/test/ to main test/
cp simba_api/test/integration/simba_contract_validation_test.exs test/integration/
cp simba_api/test/integration/simba_integration_smoke_test.exs test/integration/

# Validate all contract requirements
mix test test/integration/simba_contract_validation_test.exs
```

#### Step 4: Validate Implementation (Day 3)
```bash
# Run complete test suite
mix test --include integration

# Run dialyzer for type safety
mix dialyzer

# Verify SIMBA smoke test passes
mix test test/integration/simba_integration_smoke_test.exs
```

### Immediate Action Plan

### Today's Tasks (Day 1)

1. **Morning: Reset Broken State**
   ```bash
   # Check git status for broken test files  
   git status
   
   # Reset broken test files to working state
   git checkout HEAD -- test/integration/error_recovery_test.exs
   git checkout HEAD -- test/unit/program_utilities_test.exs
   # (reset any other broken files from diff)
   
   # Verify system is clean
   mix test
   mix dialyzer
   ```

2. **Afternoon: Begin Contract Implementation**
   ```bash
   # Start with core Program contract functions
   # Apply patches from simba_api/SIMBA_CONTRACT_IMPL_CODE_PATCHES.md
   # to lib/dspex/program.ex
   
   # Test incrementally
   mix test test/unit/program_test.exs
   ```

### Tomorrow's Tasks (Day 2)

1. **Complete Service Integrations**
   - ConfigManager SIMBA support
   - OptimizedProgram metadata handling
   - Client response stabilization

2. **Add Contract Validation Tests**
   - Copy from `simba_api/test/integration/`
   - Validate all implemented contracts

### Day 3: Final Validation

1. **End-to-End Testing**
   - Run complete SIMBA contract validation
   - Execute SIMBA integration smoke test
   - Performance baseline establishment

---

## Key Resources

### Technical Artifacts Directory: `/simba_api/`

- **📋 Contract Specification**: `SIMBA_API_CONTRACT_SPEC.md`
- **🗓️ Implementation Plan**: `SIMBA_CONTRACT_IMPL_ROADMAP.md`  
- **💻 Code Patches**: `SIMBA_CONTRACT_IMPL_CODE_PATCHES.md`
- **📊 Summary**: `SIMBA_CONTRACT_IMPL_SUMMARY.md`
- **🧪 Contract Tests**: `test/integration/simba_contract_validation_test.exs`
- **🔍 Smoke Tests**: `test/integration/simba_integration_smoke_test.exs`

### Implementation Files to Modify

1. **`lib/dspex/program.ex`** - Add introspection functions (`program_type/1`, `safe_program_info/1`, `has_demos?/1`) and enhance `forward/3`
2. **`lib/dspex/optimized_program.ex`** - Add SIMBA metadata support
3. **`lib/dspex/services/config_manager.ex`** - Add SIMBA configuration paths
4. **`lib/dspex/client.ex`** - Stabilize response format and error categorization
5. **`lib/dspex/teleprompter/bootstrap_fewshot.ex`** - Fix empty demo handling
6. **`lib/dspex/services/telemetry_setup.ex`** - Add SIMBA telemetry events

---

## Success Metrics

### Task 1 Completion Criteria

- [ ] All broken tests removed/reset without breaking existing functionality
- [ ] All 15+ contract APIs implemented according to specification
- [ ] Contract validation test suite passes 100%
- [ ] SIMBA integration smoke test passes
- [ ] No regressions in existing test suite (490+ tests still passing)
- [ ] Dialyzer type checking passes
- [ ] Performance benchmarks established for new APIs

### Ready for SIMBA Integration When:

- [ ] Task 1 is 100% complete with all success criteria met
- [ ] Contract validation demonstrates SIMBA requirements satisfied
- [ ] Foundation services integration conflicts resolved
- [ ] Development team confident in API stability

---

## Contact & Support

**Implementation Guidance**: All code patches and detailed steps available in `simba_api/` directory  
**Test Validation**: Contract test suites ready to verify implementation  
**Performance**: Benchmarking infrastructure ready for baseline establishment

---

## Next Steps

1. **Execute Task 1 immediately** - The broken test state is blocking all progress
2. **Use provided technical artifacts** - All implementation guidance is ready in `simba_api/`
3. **Validate incrementally** - Run tests after each phase to catch issues early
4. **Document progress** - Update this plan as implementation proceeds

**🎯 Goal**: Complete Task 1 in 2-3 days and establish solid foundation for SIMBA integration
