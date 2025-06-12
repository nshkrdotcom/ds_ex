# DSPEx-SIMBA API Contract Specification

**Version:** 1.0  
**Date:** June 11, 2025  
**Status:** Draft for Implementation  
**Purpose:** Define the formal API contract between DSPEx foundation and SIMBA teleprompter

## Executive Summary

This document defines the formal API contract that SIMBA requires from DSPEx. Based on analysis of the SIMBA implementation in `TODO_03_simbaPlanning/`, this contract ensures SIMBA can reliably perform Bayesian optimization of DSPEx programs.

**Critical Finding:** The current tests expect APIs that don't exist in the implementation. This specification defines what must be implemented.

---

## 1. Core Program Execution Contract

### 1.1 Program.forward/2 Stability Contract

**SIMBA Dependency:** SIMBA calls this thousands of times during optimization trials

```elixir
# Required API in lib/dspex/program.ex
@spec forward(t(), map()) :: {:ok, map()} | {:error, term()}
@spec forward(t(), map(), keyword()) :: {:ok, map()} | {:error, term()}

# Contract Requirements:
# 1. MUST return consistent format: {:ok, outputs} | {:error, reason}
# 2. MUST handle concurrent calls safely (no shared mutable state)
# 3. MUST preserve correlation_id through telemetry
# 4. MUST timeout predictably when given timeout option
# 5. outputs MUST be a map with atom keys matching signature output fields
```

**Current Implementation Gap:**
- ✅ Basic forward/2 exists
- ❌ forward/3 with options not fully implemented
- ❌ Concurrent safety not validated
- ❌ Timeout handling inconsistent

### 1.2 Program Introspection Contract

**SIMBA Dependency:** SIMBA needs program metadata for optimization decisions

```elixir
# Required API additions to lib/dspex/program.ex

@spec program_type(t()) :: :predict | :optimized | :custom | :unknown
def program_type(program)

@spec safe_program_info(t()) :: %{
  type: atom(),
  name: atom(), 
  has_demos: boolean(),
  signature: atom() | nil
}
def safe_program_info(program)

@spec has_demos?(t()) :: boolean()  
def has_demos?(program)
```

**Implementation Requirements:**
```elixir
def program_type(program) when is_struct(program) do
  case program.__struct__ |> Module.split() |> List.last() do
    "Predict" -> :predict
    "OptimizedProgram" -> :optimized  
    _ -> :custom
  end
end
def program_type(_), do: :unknown

def safe_program_info(program) when is_struct(program) do
  %{
    type: program_type(program),
    name: program_name(program),
    has_demos: has_demos?(program),
    signature: get_signature_module(program)
  }
end

def has_demos?(program) when is_struct(program) do
  cond do
    Map.has_key?(program, :demos) and is_list(program.demos) ->
      length(program.demos) > 0
    true -> false
  end
end
```

---

## 2. Client Interface Contract

### 2.1 Client.request/2 Stability Contract

**SIMBA Dependency:** Used for LLM-based instruction generation

```elixir
# Required API in lib/dspex/client.ex
@spec request([message()], map()) :: {:ok, response()} | {:error, error_reason()}

# Contract Requirements:
# 1. messages MUST be list of %{role: string, content: string}
# 2. options MUST support: %{provider: atom, correlation_id: string, timeout: integer}
# 3. response MUST have format: %{choices: [%{message: %{content: string}}]}
# 4. MUST preserve correlation_id in telemetry events
# 5. MUST handle provider switching gracefully
```

**Current Implementation Gap:**
- ✅ Basic request/2 exists
- ❌ Response format not guaranteed to be stable
- ❌ Provider switching may not preserve correlation_id
- ❌ Error recovery patterns not consistent

### 2.2 Client Error Recovery Contract

**SIMBA Dependency:** SIMBA needs predictable fallback behavior

```elixir
# Required error types in lib/dspex/client.ex
@type error_reason :: 
  :timeout | :network_error | :api_error | :rate_limited | 
  :invalid_messages | :provider_not_configured

# Contract Requirements:
# 1. MUST categorize errors consistently
# 2. MUST provide fallback mechanisms for instruction generation
# 3. MUST preserve correlation context through error paths
```

---

## 3. Example Data Structure Contract  

### 3.1 Example Interface Stability

**SIMBA Dependency:** Core to demonstration generation and storage

```elixir
# Required API in lib/dspex/example.ex (ALREADY IMPLEMENTED ✅)
@spec new(map()) :: t()
@spec new(map(), [atom()]) :: t()  
@spec inputs(t()) :: map()
@spec outputs(t()) :: map()
@spec with_inputs(t(), [atom()]) :: t()

# Contract Requirements:
# 1. MUST maintain immutable data structure
# 2. inputs/1 and outputs/1 MUST return consistent field separation
# 3. new/2 MUST properly set input_keys for field separation
# 4. MUST handle serialization/deserialization for demo storage
```

**Current Status:** ✅ FULLY IMPLEMENTED - No gaps identified

---

## 4. OptimizedProgram Wrapper Contract

### 4.1 Program Enhancement Contract

**SIMBA Dependency:** SIMBA wraps programs that lack native demo/instruction support

```elixir
# Required API in lib/dspex/optimized_program.ex

@spec new(struct(), [Example.t()], map()) :: t()
def new(program, demos, metadata \\ %{})

# Contract Requirements:  
# 1. MUST accept any program struct as first argument
# 2. MUST store demos and metadata without restrictions
# 3. MUST implement Program behavior correctly
# 4. metadata MUST support arbitrary SIMBA optimization data
# 5. MUST preserve original program functionality
```

**Current Implementation Gap:**
- ✅ Basic OptimizedProgram.new/3 exists
- ❌ Metadata support may be limited
- ❌ Program behavior forwarding not fully tested
- ❌ SIMBA-specific metadata fields not validated

### 4.2 Native Demo Support Detection

**SIMBA Dependency:** SIMBA chooses wrapping strategy based on program capabilities

```elixir
# Required detection logic for SIMBA optimization strategy
def supports_native_demos?(program) when is_struct(program) do
  Map.has_key?(program, :demos)
end

def supports_native_instruction?(program) when is_struct(program) do  
  Map.has_key?(program, :instruction)
end

# SIMBA Usage Pattern:
case student do
  %{demos: _, instruction: _} ->
    # Native support - direct field assignment
    %{student | demos: best_demos, instruction: best_instruction}
  %{demos: _} ->  
    # Partial support - demos only
    %{student | demos: best_demos}
  _ ->
    # No native support - wrap with OptimizedProgram
    OptimizedProgram.new(student, best_demos, %{instruction: best_instruction})
end
```

---

## 5. Foundation Services Integration Contract

### 5.1 ConfigManager Contract

**SIMBA Dependency:** Provider selection and configuration for instruction generation

```elixir
# Required API in lib/dspex/services/config_manager.ex

@spec get_with_default([atom()], term()) :: term()
def get_with_default(path, default)

# Critical SIMBA Usage:
default_provider = ConfigManager.get_with_default([:prediction, :default_provider], :gemini)

# Contract Requirements:
# 1. MUST return valid provider atoms (:gemini, :openai, etc.)
# 2. MUST handle graceful fallback when Foundation config unavailable  
# 3. MUST support nested path access like [:prediction, :default_provider]
# 4. MUST work during SIMBA initialization without blocking
```

**Current Implementation Gap:**
- ✅ Basic ConfigManager exists
- ❌ get_with_default/2 may not handle all SIMBA config paths
- ❌ Foundation integration may conflict with already-started services
- ❌ Provider validation not enforced

### 5.2 TelemetrySetup Contract  

**SIMBA Dependency:** Progress tracking and observability during optimization

```elixir
# Required telemetry events that SIMBA depends on
[:dspex, :program, :forward, :start]
[:dspex, :program, :forward, :stop]  
[:dspex, :client, :request, :start]
[:dspex, :client, :request, :stop]
[:dspex, :teleprompter, :bootstrap, :start]
[:dspex, :teleprompter, :bootstrap, :stop]

# Contract Requirements:
# 1. MUST include correlation_id in all event metadata
# 2. MUST include consistent measurement structure (duration, success)
# 3. MUST handle Foundation integration without crashes
# 4. MUST work during SIMBA optimization loops
```

---

## 6. Teleprompter Behavior Contract

### 6.1 Bootstrap Teleprompter Contract

**SIMBA Dependency:** SIMBA extends BootstrapFewShot patterns

```elixir
# Required API in lib/dspex/teleprompter/bootstrap_fewshot.ex
@behaviour DSPEx.Teleprompter

@spec compile(t(), struct(), [Example.t()], function(), keyword()) :: 
  {:ok, struct()} | {:error, term()}

# Contract Requirements:
# 1. MUST handle empty demonstration results gracefully
# 2. MUST support custom metric functions safely  
# 3. MUST provide meaningful progress callbacks
# 4. MUST work with concurrent teacher program execution
# 5. MUST return OptimizedProgram with proper metadata
```

**Current Implementation Gap:**
- ✅ Basic BootstrapFewShot exists
- ❌ Empty demo handling may cause crashes (seen in tests)  
- ❌ Concurrent teacher execution not validated
- ❌ Progress callback integration incomplete

---

## 7. SIMBA-Specific API Requirements

### 7.1 Instruction Generation Interface

**SIMBA Usage Pattern:**
```elixir
# SIMBA needs this interface for instruction candidates
case DSPEx.Client.request(messages, %{provider: model, correlation_id: correlation_id}) do
  {:ok, response} ->
    instruction = response.choices
                  |> List.first()  
                  |> get_in([Access.key(:message), Access.key(:content)])
                  |> String.trim()
    {:ok, instruction}
  {:error, reason} -> {:error, reason}
end
```

**Contract Requirements:**
- Response structure MUST be stable
- Content extraction MUST work reliably
- Error handling MUST be predictable

### 7.2 Bayesian Optimization Support

**SIMBA Usage Pattern:**
```elixir
# SIMBA creates trial programs and evaluates them
trial_program = create_trial_program(student, instruction_candidate, demo_candidates)

# Must work reliably:
case Program.forward(trial_program, inputs) do
  {:ok, prediction} -> metric_fn.(example, prediction)
  {:error, _} -> 0.0  # Graceful degradation
end
```

**Contract Requirements:**
- Trial program creation MUST be fast (<100ms)
- Program.forward MUST handle trial programs reliably
- Error recovery MUST not crash optimization loop

---

## 8. Implementation Priority Matrix

### 🔴 CRITICAL BLOCKERS (Must implement before SIMBA)

| Component | Missing API | Impact if Missing |
|-----------|-------------|-------------------|
| Program.forward/3 | Options handling, timeout | SIMBA optimization fails |
| Program utilities | program_type, safe_program_info, has_demos | SIMBA cannot analyze programs |
| Client response format | Stable response.choices structure | Instruction generation fails |
| OptimizedProgram metadata | Custom metadata support | SIMBA results lost |
| ConfigManager.get_with_default | Provider resolution | SIMBA cannot select models |

### 🟡 HIGH PRIORITY (Implement during SIMBA integration)

| Component | Missing API | Impact if Missing |
|-----------|-------------|-------------------|  
| Telemetry correlation | Consistent correlation_id flow | Lost optimization tracking |
| Error categorization | Predictable error types | Poor error recovery |
| Concurrent safety | Thread-safe program execution | Optimization corruption |
| Foundation integration | Service lifecycle management | Startup conflicts |

### 🟢 MEDIUM PRIORITY (Can defer post-SIMBA)

| Component | Missing API | Impact if Missing |
|-----------|-------------|-------------------|
| Advanced introspection | Signature compatibility checking | Advanced optimization features |
| Performance monitoring | Detailed telemetry metrics | Reduced observability |
| Cache integration | Optimization result caching | Slower re-optimization |

---

## 9. Implementation Checklist

### Phase 1: Core Contract Implementation
- [ ] Add Program.forward/3 with options support
- [ ] Implement Program.program_type/1
- [ ] Implement Program.safe_program_info/1  
- [ ] Implement Program.has_demos?/1
- [ ] Validate OptimizedProgram metadata support

### Phase 2: Client Contract Stabilization
- [ ] Ensure Client.request/2 response format stability
- [ ] Implement consistent error categorization
- [ ] Add correlation_id preservation through error paths
- [ ] Validate provider switching reliability

### Phase 3: Service Integration Contracts
- [ ] Fix ConfigManager.get_with_default/2 for all SIMBA paths
- [ ] Resolve TelemetrySetup Foundation integration conflicts
- [ ] Ensure service lifecycle compatibility with SIMBA
- [ ] Add graceful fallback for Foundation unavailability

### Phase 4: Teleprompter Contract Completion  
- [ ] Fix BootstrapFewShot empty demo handling
- [ ] Validate concurrent teacher execution
- [ ] Ensure progress callback integration works
- [ ] Test teleprompter behavior under SIMBA loads

### Phase 5: Contract Validation
- [ ] Write contract compliance tests
- [ ] Validate SIMBA integration scenario
- [ ] Performance baseline establishment  
- [ ] Error recovery scenario testing

---

## 10. Contract Validation Strategy

### 10.1 Automated Contract Testing

```elixir
defmodule DSPEx.SIMBAContractTest do
  # Test that validates the exact APIs SIMBA depends on
  
  test "Program.forward/3 contract compliance" do
    program = create_test_program()
    inputs = %{question: "test"}
    
    # Test basic contract
    assert {:ok, outputs} = Program.forward(program, inputs)
    assert is_map(outputs)
    assert Map.has_key?(outputs, :answer)
    
    # Test options contract  
    opts = [correlation_id: "test-123", timeout: 5000]
    assert {:ok, outputs} = Program.forward(program, inputs, opts)
    
    # Test error contract
    assert {:error, reason} = Program.forward(nil, inputs)
    assert is_atom(reason)
  end
  
  test "SIMBA instruction generation contract" do
    messages = [%{role: "user", content: "Generate instruction"}]
    opts = %{provider: :gemini, correlation_id: "test-456"}
    
    case Client.request(messages, opts) do
      {:ok, response} ->
        # Validate response structure SIMBA expects
        assert %{choices: choices} = response
        assert is_list(choices)
        assert [%{message: %{content: content}} | _] = choices
        assert is_binary(content)
        
      {:error, reason} ->
        # Validate error handling SIMBA expects
        assert reason in [:timeout, :network_error, :api_error, :rate_limited]
    end
  end
end
```

### 10.2 SIMBA Integration Smoke Test

```elixir
defmodule DSPEx.SIMBAIntegrationSmokeTest do
  test "minimal SIMBA workflow compatibility" do
    # This test validates the essential SIMBA workflow
    student = create_simple_student()
    teacher = create_simple_teacher()  
    trainset = create_minimal_trainset()
    metric_fn = &simple_metric/2
    
    # Test bootstrap generation (simplified)
    assert {:ok, demos} = generate_bootstrap_demos(teacher, trainset)
    assert length(demos) > 0
    
    # Test instruction generation  
    assert {:ok, instruction} = generate_test_instruction(student, trainset)
    assert is_binary(instruction)
    
    # Test program enhancement
    enhanced = enhance_program(student, demos, instruction)
    assert is_struct(enhanced)
    
    # Test enhanced program execution
    assert {:ok, result} = Program.forward(enhanced, %{question: "test"})
    assert Map.has_key?(result, :answer)
  end
end
```

---

## 11. Success Criteria

### Contract Implementation Complete When:

1. **All SIMBA contract tests pass** - Every API SIMBA depends on works correctly
2. **Integration smoke test passes** - Minimal SIMBA workflow can execute
3. **No contract violations in existing tests** - Current tests don't break due to contract changes
4. **Performance baselines met** - Contract implementation doesn't degrade performance  
5. **Error recovery validated** - SIMBA can handle all expected error scenarios

### SIMBA Integration Ready When:

1. **All contract APIs implemented and tested**  
2. **Service integration conflicts resolved**
3. **Concurrent execution validated under load**
4. **Error recovery patterns proven reliable**
5. **Foundation integration stable and non-blocking**

---

## 12. Risk Assessment

### High Risk Contract Areas

1. **Program.forward/3 options handling** - Complex interaction with existing code
2. **Foundation service integration** - Already-started service conflicts
3. **Concurrent safety validation** - May reveal architectural issues
4. **Client response format stability** - Provider differences may cause issues

### Mitigation Strategies

1. **Incremental implementation** - Add contracts one at a time with tests
2. **Backward compatibility** - Ensure existing code still works  
3. **Extensive validation** - Test every contract with multiple scenarios
4. **Rollback plans** - Keep contract implementation reversible until proven

### Success Indicators

- ✅ All contract tests pass consistently
- ✅ No regressions in existing functionality
- ✅ SIMBA integration smoke test passes  
- ✅ Performance remains within acceptable bounds
- ✅ Error recovery works under stress conditions

---

This specification provides the formal contract definition needed to bridge DSPEx and SIMBA. Implementation of this contract is **prerequisite to SIMBA integration** and addresses the fundamental issue that tests were expecting APIs that didn't exist in the implementation.
