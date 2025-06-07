## Summary

Foundation v0.1.1 has several critical API contract violations that prevent it from being used as intended in real-world applications. These were discovered during DSPEx integration and are demonstrated with a concrete reproduction script.

## Demonstration

A complete reproduction script demonstrates these issues:

**File**: `foundation_contract_violations_demo.exs`
**Run**: `elixir foundation_contract_violations_demo.exs`

## Contract Violations Identified

### 1. Config System Violations ❌

**Issue**: Cannot set application configuration at runtime
- **Error**: `Configuration path [:myapp] cannot be updated at runtime`
- **Expected**: Applications should be able to set their own config namespaces
- **Actual**: Only pre-defined system paths allowed
- **Impact**: Makes Foundation unusable for application configuration

**Issue**: Nested path setting doesn't create intermediate maps
- **Error**: `Configuration path not found: [:myapp, :database]` after setting `[:myapp, :database, :host]`
- **Expected**: Setting nested paths should auto-create parent maps
- **Actual**: Can set leaves but can't retrieve intermediate structures

### 2. Infrastructure API Missing ❌

**Issue**: Circuit breaker functions undefined
- **Error**: `Foundation.Infrastructure.initialize_circuit_breaker/2 undefined`
- **Expected**: Should provide circuit breaker initialization as advertised
- **Actual**: Function doesn't exist
- **Impact**: Cannot use infrastructure protection features

**Issue**: execute_protected fails with circuit breaker not found
- **Error**: `Circuit breaker demo_breaker not found`
- **Expected**: Should work after proper initialization
- **Actual**: No way to initialize circuit breakers

### 3. Telemetry API Inconsistencies ⚠️

**Issue**: Helper methods partially undefined
- **Error**: `Foundation.Telemetry.emit_histogram/3 undefined`
- **Working**: `emit_counter/2` and `emit_gauge/3` exist
- **Expected**: Consistent API across all metric types
- **Impact**: Forces mixed usage of Foundation and standard telemetry

### 4. Documentation vs Reality Gap

Foundation README promises comprehensive infrastructure but key APIs are missing or broken:
- "Circuit breaker patterns (via :fuse)" - Can't initialize circuit breakers
- "Dynamic configuration updates" - Forbidden for application config
- "Telemetry & Monitoring" - Partial API implementation

## Real-World Impact

During DSPEx integration, we had to implement workarounds for:
1. **Config fallback system** using GenServer state instead of Foundation.Config
2. **Direct HTTP calls** instead of Foundation.Infrastructure protection
3. **Standard telemetry** instead of Foundation helpers
4. **Disabled Foundation.Events** due to validation crashes

## Reproduction Evidence

```
--- Config System Violations ---
1. Testing runtime config updates for application namespace...
✗ VIOLATION: Configuration path [:myapp] cannot be updated at runtime
   Expected: Should allow application config updates
   Actual: Only allows pre-defined system paths

2. Testing nested path creation...
✗ VIOLATION: Configuration path not found: [:myapp, :database]
   Expected: Setting nested paths should create intermediate maps
   Actual: Can set leaves but can't retrieve intermediate maps

--- Infrastructure API Violations ---
1. Testing infrastructure protection...
Result: {:error, %Foundation.Types.Error{error_type: :circuit_breaker_not_found, message: "Circuit breaker demo_breaker not found"}}

2. Testing circuit breaker initialization...
✗ VIOLATION: Foundation.Infrastructure.initialize_circuit_breaker/2 undefined
   Expected: Should provide circuit breaker initialization
   Actual: Function doesn't exist

--- Telemetry API Violations ---
Testing Foundation.Telemetry.emit_histogram/3...
✗ VIOLATION: Foundation.Telemetry.emit_histogram/3 undefined
   Expected: Should provide telemetry helper methods
   Actual: Must use standard :telemetry.execute/3 directly
```

## Suggested Fixes for v0.1.2

### Priority 1 (Critical)
1. **Allow application config updates**: Remove restriction on application namespaces
2. **Fix nested config creation**: Auto-create intermediate maps when setting nested paths
3. **Implement missing infrastructure APIs**: Add `initialize_circuit_breaker/2`
4. **Complete telemetry API**: Implement `emit_histogram/3`

### Priority 2 (Important)
1. **Update documentation**: Match actual API capabilities
2. **Add integration tests**: Test with real applications
3. **API contract validation**: Ensure advertised features work

## Context

This issue was discovered during integration with DSPEx (a DSPy-like framework for Elixir). Foundation shows great promise for Elixir infrastructure, but needs API maturity to be production-ready.

Current workaround: Bypass Foundation APIs and implement fallback systems
Preferred solution: Fix Foundation v0.1.2 APIs to match documented contracts

## Environment

- Foundation: v0.1.1
- Elixir: 1.18.3
- OTP: 26+
- Integration context: Real application (DSPEx)

Foundation has excellent architecture and concepts, just needs the APIs to actually work as designed. Happy to test v0.1.2 once these issues are addressed! 