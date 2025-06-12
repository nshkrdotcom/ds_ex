# DSPEx SIMBA Integration Implementation Plan

**Plan Date:** June 11, 2025  
**Context:** Comprehensive API contract implementation required before SIMBA integration  
**Current Status:** Codebase stable, ready for systematic implementation  
**Priority:** **CRITICAL FOUNDATION** - API contract must be implemented before SIMBA

---

## Executive Summary

**📋 IMPLEMENTATION STRATEGY:** Two-phase approach with TDD methodology  
**🎯 GOAL:** Implement DSPEx-SIMBA API contract, then integrate SIMBA teleprompter  
**📁 RESOURCES:** Complete technical artifacts available in `/simba_api/` directory  
**⏱️ TIMELINE:** 5-7 days total (3 days contract + 2-4 days SIMBA implementation)

### Phase Overview

1. **Phase 1** (3 days): Implement DSPEx-SIMBA API contract using TDD
2. **Phase 2** (2-4 days): Implement SIMBA teleprompter with Bayesian optimization

### Current Situation

- ✅ **Codebase Stable**: All tests passing, system ready for implementation
- ✅ **Technical Artifacts Complete**: Comprehensive implementation guidance in `simba_api/`
- ✅ **Contract Specification**: Formal API requirements documented
- ⏳ **Ready to Begin**: All blockers removed, implementation can start immediately

---

## PHASE 1: DSPEx-SIMBA API Contract Implementation (Days 1-3)

**Priority:** 🔴 **CRITICAL FOUNDATION** - SIMBA cannot be implemented without these APIs  
**Methodology:** Test-Driven Development (TDD)  
**Resources:** Complete implementation artifacts in `simba_api/`

### Why This Phase Is Critical

The SIMBA implementation requires specific APIs that don't currently exist in DSPEx:

```elixir
# SIMBA needs these APIs for program optimization:
Program.forward(program, inputs, timeout: 30_000, correlation_id: "opt-123")
Program.program_type(student)  # :predict | :optimized | :custom
Program.safe_program_info(student)  # Safe introspection for telemetry
Program.has_demos?(student)  # Demo detection for wrapping strategy

# SIMBA needs configuration access:
ConfigManager.get_with_default([:teleprompters, :simba, :default_instruction_model], :openai)

# SIMBA needs metadata support:
OptimizedProgram.simba_enhancement_strategy(student)  # :native_full | :native_demos | :wrap_optimized
```

### Technical Artifacts Available

- **`SIMBA_API_CONTRACT_SPEC.md`** - Complete formal API contract specification
- **`SIMBA_CONTRACT_IMPL_ROADMAP.md`** - 3-day phased implementation roadmap
- **`SIMBA_CONTRACT_IMPL_CODE_PATCHES.md`** - Ready-to-apply code modifications
- **`COMPREHENSIVE_SIMBA_ANALYSIS.md`** - Detailed gap analysis and requirements
- **Contract validation tests** - Pre-written test suites to verify implementation

### Day 1: Core Program Contract APIs

**TDD Implementation Process:**

```bash
# 1. Create failing test for Program.forward/3
# test/unit/program_contract_test.exs
test "forward/3 supports timeout and correlation_id" do
  program = %DSPEx.Predict{signature: TestSig, client: :test}
  inputs = %{question: "test"}
  
  # Should work with timeout
  assert {:ok, _} = DSPEx.Program.forward(program, inputs, timeout: 5000)
  
  # Should timeout on very short timeout
  assert {:error, :timeout} = DSPEx.Program.forward(program, inputs, timeout: 1)
  
  # Should accept correlation_id
  assert {:ok, _} = DSPEx.Program.forward(program, inputs, correlation_id: "test-123")
end

# 2. Run test (fails)
mix test test/unit/program_contract_test.exs

# 3. Implement Program.forward/3 in lib/dspex/program.ex
def forward(program, inputs, opts) when is_list(opts) do
  timeout = Keyword.get(opts, :timeout, 30_000)
  correlation_id = Keyword.get(opts, :correlation_id) || generate_correlation_id()
  
  task = Task.async(fn ->
    program.__struct__.forward(program, inputs, opts)
  end)
  
  case Task.yield(task, timeout) do
    {:ok, result} -> result
    nil ->
      Task.shutdown(task, :brutal_kill)
      {:error, :timeout}
  end
end

# 4. Test passes, continue with next API
```

**Day 1 APIs to implement:**
- ✅ `Program.forward/3` with timeout and correlation_id
- ✅ `Program.program_type/1` for program classification
- ✅ Basic telemetry integration for correlation tracking

### Day 2: Program Introspection & Configuration

**Day 2 APIs to implement:**
- ✅ `Program.safe_program_info/1` for safe program metadata
- ✅ `Program.has_demos?/1` for demo detection
- ✅ `ConfigManager` SIMBA configuration paths
- ✅ `OptimizedProgram` SIMBA strategy detection

**Example TDD flow:**
```elixir
# Test first
test "safe_program_info/1 returns required fields" do
  predict = %DSPEx.Predict{signature: TestSig, client: :test}
  info = DSPEx.Program.safe_program_info(predict)
  
  assert %{
    type: :predict,
    name: :Predict,
    has_demos: false,
    signature: TestSig
  } = info
end

# Then implement
def safe_program_info(program) when is_struct(program) do
  %{
    type: program_type(program),
    name: program_name(program),
    has_demos: has_demos?(program),
    signature: get_signature_module(program)
  }
end
```

### Day 3: Service Integration & Validation

**Day 3 APIs to implement:**
- ✅ Client response format stabilization
- ✅ Teleprompter empty demo handling fixes
- ✅ SIMBA telemetry event support
- ✅ Contract validation test execution

**Validation Process:**
```bash
# Run contract validation tests
mix test test/integration/simba_contract_validation_test.exs

# Run SIMBA integration smoke test
mix test test/integration/simba_integration_smoke_test.exs

# Verify no regressions
mix test
mix dialyzer
```

### Phase 1 Success Criteria

- [ ] All contract validation tests pass 100%
- [ ] SIMBA integration smoke test passes
- [ ] No regressions in existing test suite
- [ ] Dialyzer type checking passes
- [ ] All 15+ required APIs implemented and documented

---

## PHASE 2: SIMBA Teleprompter Implementation (Days 4-7)

**Priority:** 🟢 **FEATURE IMPLEMENTATION** - Build on solid API foundation  
**Resources:** SIMBA implementation artifacts from `TODO_03_simbaPlanning/`  
**Dependencies:** Phase 1 must be 100% complete

### SIMBA Architecture Overview

```
DSPEx.Teleprompter.SIMBA
├── Core teleprompter (simba.ex)
├── Bayesian optimization engine (bayesian_optimizer.ex)
├── Instruction generation pipeline
├── Demonstration bootstrapping
└── Progress tracking and telemetry
```

### Day 4: Core SIMBA Teleprompter

**Implementation:**
- ✅ Create `lib/dspex/teleprompter/simba.ex`
- ✅ Implement basic SIMBA behavior and structure
- ✅ Add demonstration bootstrapping
- ✅ Integrate with existing BootstrapFewShot patterns

**Key Features:**
```elixir
defmodule DSPEx.Teleprompter.SIMBA do
  @behaviour DSPEx.Teleprompter
  
  def compile(student, teacher, trainset, metric_fn, opts \\ []) do
    # 1. Bootstrap demonstrations using teacher
    # 2. Generate instruction candidates  
    # 3. Run Bayesian optimization
    # 4. Create optimized student with best configuration
  end
end
```

### Day 5: Bayesian Optimization Engine

**Implementation:**
- ✅ Create `lib/dspex/teleprompter/simba/bayesian_optimizer.ex`
- ✅ Implement Gaussian Process surrogate modeling
- ✅ Add Expected Improvement acquisition function
- ✅ Configuration space exploration

**Key Features:**
```elixir
defmodule DSPEx.Teleprompter.SIMBA.BayesianOptimizer do
  def optimize(search_space, objective_function, opts) do
    # 1. Initialize with random samples
    # 2. Fit Gaussian Process to observations
    # 3. Use acquisition function to select next configuration
    # 4. Evaluate and update model
    # 5. Return best configuration found
  end
end
```

### Day 6: Instruction Generation & Integration

**Implementation:**
- ✅ LLM-based instruction candidate generation
- ✅ Integration with DSPEx.Client for stable instruction creation
- ✅ Multi-objective optimization support
- ✅ Progress tracking and telemetry

### Day 7: Testing & Optimization

**Implementation:**
- ✅ Comprehensive test suite for SIMBA
- ✅ Integration with examples and benchmarks
- ✅ Performance optimization and tuning
- ✅ Documentation and usage examples

### Phase 2 Success Criteria

- [ ] SIMBA teleprompter fully functional
- [ ] Bayesian optimization working correctly
- [ ] Instruction generation stable across providers
- [ ] Performance benchmarks established
- [ ] Comprehensive test coverage
- [ ] Real-world examples working

---

## Implementation Guidelines

### TDD Methodology

**For every API implementation:**
1. **Write failing test** - Define expected behavior
2. **Implement minimal code** - Just enough to pass test
3. **Refactor if needed** - Improve code quality
4. **Move to next API** - Systematic progression

### Quality Gates

**After each day:**
- [ ] All new tests pass
- [ ] No regressions in existing tests
- [ ] Dialyzer passes without warnings
- [ ] Code follows project conventions

**Before Phase 2:**
- [ ] Contract validation 100% complete
- [ ] Integration smoke test passes
- [ ] Performance baseline established

### File Structure

**Phase 1 Files to Modify:**
```
lib/dspex/
├── program.ex                          # Add introspection APIs
├── optimized_program.ex               # Add SIMBA strategy detection
├── services/
│   ├── config_manager.ex             # Add SIMBA config paths
│   └── telemetry_setup.ex            # Add SIMBA telemetry events
├── client.ex                         # Stabilize response format
└── teleprompter/
    └── bootstrap_fewshot.ex          # Fix empty demo handling
```

**Phase 2 Files to Create:**
```
lib/dspex/teleprompter/
├── simba.ex                          # Main SIMBA teleprompter
└── simba/
    ├── bayesian_optimizer.ex         # Optimization engine
    ├── examples.ex                   # Usage examples
    └── benchmark.ex                  # Performance benchmarks
```

---

## Technical Resources

### Implementation Artifacts (`simba_api/`)

- **📋 `SIMBA_API_CONTRACT_SPEC.md`** - Complete API specification
- **🗓️ `SIMBA_CONTRACT_IMPL_ROADMAP.md`** - Detailed 3-day roadmap
- **💻 `SIMBA_CONTRACT_IMPL_CODE_PATCHES.md`** - Ready-to-apply code changes
- **📊 `COMPREHENSIVE_SIMBA_ANALYSIS.md`** - Gap analysis and requirements
- **🧪 Contract validation tests** - Test suites to verify implementation

### SIMBA Implementation Artifacts (`TODO_03_simbaPlanning/`)

- **📝 `simba_01_integration_claude.md`** - Complete SIMBA implementation
- **🔬 `simba_02_bayesian_optimizer.md`** - Bayesian optimization engine
- **📚 `simba_04_integration_documentation.md`** - Usage and integration docs
- **🛠️ Utility modules** - Utils, examples, benchmarks, continuous optimizer

### Configuration Requirements

**Add to application config:**
```elixir
# config/config.exs
config :dspex,
  teleprompters: %{
    simba: %{
      default_instruction_model: :openai,
      default_evaluation_model: :gemini,
      max_concurrent_operations: 20,
      default_timeout: 60_000
    }
  }
```

---

## Risk Mitigation

### Phase 1 Risks

**Risk:** API implementation breaks existing functionality  
**Mitigation:** TDD approach with regression testing after each change

**Risk:** Contract requirements misunderstood  
**Mitigation:** Comprehensive artifacts and validation tests available

### Phase 2 Risks

**Risk:** SIMBA complexity causes integration issues  
**Mitigation:** Build on proven API foundation from Phase 1

**Risk:** Performance issues with Bayesian optimization  
**Mitigation:** Benchmark early and optimize incrementally

---

## Success Metrics

### Overall Success Criteria

- [ ] **Phase 1**: All contract APIs implemented and validated
- [ ] **Phase 2**: SIMBA teleprompter fully functional
- [ ] **Integration**: End-to-end optimization workflow works
- [ ] **Performance**: Established benchmarks for optimization quality
- [ ] **Documentation**: Comprehensive usage examples and guides

### Performance Targets

- **Contract APIs**: < 10ms overhead per API call
- **SIMBA Optimization**: Meaningful improvement in < 60 minutes
- **Memory Usage**: < 500MB for typical optimization workloads
- **Throughput**: Handle 500+ training examples efficiently

---

## Next Steps

### Immediate Actions (Today)

1. **Review technical artifacts** in `simba_api/` directory
2. **Start Phase 1 implementation** using TDD methodology
3. **Begin with `Program.forward/3`** - highest priority API

### This Week's Goals

- **Days 1-3**: Complete Phase 1 (API contract implementation)
- **Days 4-7**: Complete Phase 2 (SIMBA teleprompter implementation)
- **End of week**: Full SIMBA integration working with real examples

### Future Enhancements

- Distributed optimization across BEAM clusters
- Advanced Bayesian optimization algorithms
- Integration with vector databases for RAG
- Phoenix LiveView optimization dashboard

---

## Contact & Support

**Implementation Guidance**: All technical artifacts in `simba_api/` and `TODO_03_simbaPlanning/`  
**Test Validation**: Contract test suites ready for validation  
**Performance**: Benchmarking infrastructure included in SIMBA implementation

**🎯 Primary Goal**: Deliver production-ready SIMBA teleprompter with comprehensive API foundation
