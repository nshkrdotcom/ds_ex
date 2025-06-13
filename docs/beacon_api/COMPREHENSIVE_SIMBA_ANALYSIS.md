# Comprehensive SIMBA Contract Analysis & Implementation Status

After reviewing both the API contract specification and the SIMBA implementation draft, here's the complete analysis of what's needed:

## 🔍 SIMBA Implementation Dependencies

### Critical APIs SIMBA Uses Directly

From the SIMBA implementation code, I can see these specific API calls:

```elixir
# 1. SIMBA uses Program.forward with correlation_id - NEEDS forward/3
case Program.forward(teacher, inputs) do

# 2. SIMBA needs program introspection for strategy selection
case student do
  %{demos: _, instruction: _} ->
    # Native support - direct field assignment
  %{demos: _} ->  
    # Partial support - demos only
  _ ->
    # No native support - wrap with OptimizedProgram

# 3. SIMBA uses ConfigManager for provider selection
instruction_model = config.instruction_model || get_default_instruction_model()
ConfigManager.get_with_default([:prediction, :default_provider], :gemini)

# 4. SIMBA wraps programs that don't support demos natively
DSPEx.OptimizedProgram.new(student, demos, %{
  optimization_method: :simba,
  instruction: instruction,
  optimization_score: score
})
```

## 🔴 CRITICAL GAPS - Must Fix Before SIMBA

### 1. **Program.forward/3 Options Support**
**Status:** ❌ MISSING CRITICAL FUNCTIONALITY
**SIMBA Usage:**
```elixir
# SIMBA calls this with correlation_id for tracking
case Program.forward(teacher, inputs) do
```

**Current Problem:** The forward/3 exists but doesn't handle timeout or correlation_id properly.

**Required Fix:**
```elixir
# In lib/dspex/program.ex - ADD timeout wrapper
def forward(program, inputs, opts) when is_map(inputs) and is_list(opts) do
  correlation_id = Keyword.get(opts, :correlation_id) || generate_correlation_id()
  timeout = Keyword.get(opts, :timeout, 30_000)
  
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
```

### 2. **Program Introspection Functions**
**Status:** ❌ COMPLETELY MISSING
**SIMBA Usage:**
```elixir
# SIMBA needs this to determine wrapping strategy
case student do
  %{demos: _, instruction: _} -> # How does SIMBA detect this?
```

**Current Problem:** No way to detect program capabilities.

**Required Implementation:**
```elixir
# Add to lib/dspex/program.ex
def program_type(program) when is_struct(program) do
  case program.__struct__ |> Module.split() |> List.last() do
    "Predict" -> :predict
    "OptimizedProgram" -> :optimized
    _ -> :custom
  end
end

def has_demos?(program) when is_struct(program) do
  Map.has_key?(program, :demos) and is_list(program.demos) and length(program.demos) > 0
end

def safe_program_info(program) when is_struct(program) do
  %{
    type: program_type(program),
    name: program_name(program),
    has_demos: has_demos?(program),
    signature: get_signature_module(program)
  }
end
```

### 3. **ConfigManager SIMBA Paths**
**Status:** ⚠️ PARTIAL - Missing SIMBA-specific config
**SIMBA Usage:**
```elixir
ConfigManager.get_with_default([:teleprompters, :simba, :default_instruction_model], :openai)
```

**Current Problem:** SIMBA config paths don't exist.

**Required Fix:**
```elixir
# In lib/dspex/services/config_manager.ex - ADD to get_default_config()
teleprompters: %{
  simba: %{
    default_instruction_model: :openai,
    default_evaluation_model: :gemini,
    max_concurrent_operations: 20,
    default_timeout: 60_000
  }
}
```

### 4. **OptimizedProgram Metadata Support**
**Status:** ⚠️ PARTIAL - Needs SIMBA metadata validation
**SIMBA Usage:**
```elixir
DSPEx.OptimizedProgram.new(student, demos, %{
  optimization_method: :simba,
  instruction: instruction,
  optimization_score: score,
  optimization_stats: %{...},
  bayesian_trials: [...]
})
```

**Current Problem:** Metadata may not support complex SIMBA structures.

**Required Enhancement:**
```elixir
# Enhance lib/dspex/optimized_program.ex
def supports_native_demos?(program) when is_struct(program) do
  Map.has_key?(program, :demos)
end

def supports_native_instruction?(program) when is_struct(program) do
  Map.has_key?(program, :instruction)
end

def simba_enhancement_strategy(program) when is_struct(program) do
  cond do
    supports_native_demos?(program) and supports_native_instruction?(program) ->
      :native_full
    supports_native_demos?(program) ->
      :native_demos
    true ->
      :wrap_optimized
  end
end
```

### 5. **Client Response Format Stability**
**Status:** ⚠️ PARTIAL - May have provider inconsistencies
**SIMBA Usage:**
```elixir
# SIMBA expects stable response format for instruction generation
response.choices
|> List.first()
|> get_in([Access.key(:message), Access.key(:content)])
```

**Current Problem:** Response format may vary between providers.

## 🟡 HIGH PRIORITY - Implement During SIMBA Integration

### 6. **Telemetry Events for SIMBA**
**Status:** ⚠️ PARTIAL - Missing SIMBA-specific events
**SIMBA Usage:**
```elixir
emit_telemetry([:dspex, :teleprompter, :simba, :start], ...)
emit_telemetry([:dspex, :teleprompter, :simba, :optimization, :start], ...)
```

**Required Addition:**
```elixir
# Add to lib/dspex/services/telemetry_setup.ex
events = [
  # ... existing events
  [:dspex, :teleprompter, :simba, :start],
  [:dspex, :teleprompter, :simba, :stop],
  [:dspex, :teleprompter, :simba, :optimization, :start],
  [:dspex, :teleprompter, :simba, :optimization, :stop],
  [:dspex, :teleprompter, :simba, :instruction, :start],
  [:dspex, :teleprompter, :simba, :instruction, :stop]
]
```

### 7. **BootstrapFewShot Empty Demo Handling**
**Status:** ⚠️ NEEDS VALIDATION - May crash on empty results
**SIMBA Dependency:** SIMBA extends BootstrapFewShot patterns

**Required Fix:**
```elixir
# In lib/dspex/teleprompter/bootstrap_fewshot.ex
defp select_best_demonstrations(quality_demos, config) do
  selected = quality_demos
    |> Enum.sort_by(fn demo -> demo.data[:__quality_score] || 0.0 end, :desc)
    |> Enum.take(config.max_bootstrapped_demos)

  # CRITICAL: Always return selected demonstrations (even if empty)
  {:ok, selected}
end
```

## 📋 Complete Implementation Checklist

### Phase 1: Critical Blockers (Day 1)
- [ ] **Program.forward/3** - Add timeout and correlation_id handling
- [ ] **Program.program_type/1** - Add program type detection
- [ ] **Program.safe_program_info/1** - Add safe program introspection
- [ ] **Program.has_demos?/1** - Add demo detection
- [ ] **ConfigManager SIMBA paths** - Add teleprompter configuration section

### Phase 2: OptimizedProgram Enhancement (Day 1-2)
- [ ] **OptimizedProgram.supports_native_demos?/1** - Add native support detection
- [ ] **OptimizedProgram.supports_native_instruction?/1** - Add instruction support detection  
- [ ] **OptimizedProgram.simba_enhancement_strategy/1** - Add strategy selection
- [ ] **OptimizedProgram metadata validation** - Ensure SIMBA metadata compatibility

### Phase 3: Service Integration (Day 2)
- [ ] **Client response format** - Ensure stability across providers
- [ ] **TelemetrySetup SIMBA events** - Add SIMBA telemetry event support
- [ ] **Foundation service conflicts** - Resolve any service lifecycle issues

### Phase 4: Teleprompter Foundation (Day 2-3)
- [ ] **BootstrapFewShot empty handling** - Fix empty demo scenario crashes
- [ ] **Teleprompter behavior validation** - Ensure all teleprompters work with SIMBA patterns

### Phase 5: Contract Testing (Day 3)
- [ ] **Contract validation tests** - Test all SIMBA-required APIs
- [ ] **Integration smoke tests** - End-to-end SIMBA workflow validation
- [ ] **Performance baseline** - Establish performance characteristics

## 🎯 SIMBA-Specific Requirements Analysis

### Why These APIs Are Critical for SIMBA

1. **Program.forward/3**: SIMBA makes thousands of forward calls during optimization trials
2. **Program introspection**: SIMBA needs to detect program capabilities to choose wrapping strategy
3. **ConfigManager paths**: SIMBA needs provider configuration for instruction generation
4. **OptimizedProgram strategies**: SIMBA wraps programs that don't support demos natively
5. **Stable client responses**: SIMBA generates instructions using LLM calls
6. **Telemetry correlation**: SIMBA optimization tracking requires correlation IDs
7. **Empty demo handling**: SIMBA bootstrap may produce no quality demonstrations

### SIMBA Integration Pattern

```elixir
# This is how SIMBA will work once APIs are implemented:

# 1. Detect program capabilities
strategy = OptimizedProgram.simba_enhancement_strategy(student)

# 2. Generate instruction candidates (needs stable client)
{:ok, instruction} = generate_instruction_candidates(student, trainset, config)

# 3. Run optimization trials (needs forward/3 with correlation_id)
{:ok, result} = Program.forward(trial_program, inputs, correlation_id: correlation_id)

# 4. Create optimized program based on strategy
case strategy do
  :native_full ->
    %{student | demos: best_demos, instruction: best_instruction}
  :native_demos ->
    %{student | demos: best_demos}
  :wrap_optimized ->
    OptimizedProgram.new(student, best_demos, %{instruction: best_instruction})
end
```

## 🚨 Implementation Priority

The APIs marked as **CRITICAL BLOCKERS** must be implemented before SIMBA integration can proceed. Without them:

- SIMBA cannot detect program capabilities → wrong wrapping strategy
- SIMBA cannot track optimization trials → no correlation
- SIMBA cannot access configuration → provider errors  
- SIMBA cannot handle timeouts → hanging optimization
- SIMBA cannot store complex metadata → lost optimization results

## ✅ What's Already Working

- ✅ **Example data structures** - Fully compatible with SIMBA
- ✅ **Basic Program behavior** - SIMBA can use existing programs
- ✅ **Basic Client functionality** - HTTP requests work
- ✅ **OptimizedProgram wrapping** - Basic metadata support exists
- ✅ **BootstrapFewShot foundation** - Core teleprompter pattern works

## 🎉 Success Criteria

SIMBA integration will be ready when:

1. All contract validation tests pass
2. SIMBA can detect program capabilities correctly  
3. Optimization trials can be tracked with correlation IDs
4. Complex metadata can be stored in OptimizedProgram
5. Instruction generation works reliably across providers
6. Empty demo scenarios don't crash the optimization

The implementation roadmap and code patches are comprehensive and should provide everything needed for successful SIMBA integration.
