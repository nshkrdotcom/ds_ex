# Foundation/ExUnit Race Condition Workaround

## Overview

This document describes the race condition issue between Foundation telemetry handlers and ExUnit test cleanup, along with our comprehensive defensive workaround implemented in DSPEx.

## The Problem

When using Foundation v0.1.3 with ExUnit tests, a race condition occurs during test cleanup:

1. **Test Completion**: ExUnit tests complete successfully
2. **Cleanup Phase**: ExUnit begins shutdown and cleanup procedures
3. **ETS Table Deletion**: ExUnit.Server ETS table gets deleted
4. **Foundation Telemetry**: Foundation telemetry handlers remain active and attempt to access the deleted ETS table
5. **Crash**: `{:badarg, [{:ets, :take, [ExUnit.Server, #PID<...>]}]}` error occurs

This happens **after** tests pass but causes the overall test run to appear failed.

## Root Causes

- **Process Lifecycle Mismatch**: Foundation telemetry processes outlive ExUnit cleanup
- **ETS Access Violations**: Telemetry handlers access deleted ETS tables
- **Asynchronous Cleanup**: Race between Foundation shutdown and ExUnit cleanup

## Our Defensive Workaround

### 1. Enhanced Telemetry Handler Protection

```elixir
def handle_dspex_event(event, measurements, metadata, config) do
  # Enhanced defensive programming with comprehensive error handling
  try do
    if Foundation.available?() do
      do_handle_dspex_event(event, measurements, metadata, config)
    else
      log_telemetry_skip(:foundation_unavailable, event, process_info)
      :ok
    end
  rescue
    ArgumentError ->
      log_telemetry_skip(:ets_unavailable, event, process_info)
      :ok
    SystemLimitError ->
      log_telemetry_skip(:system_limit, event, process_info)
      :ok
    UndefinedFunctionError ->
      log_telemetry_skip(:undefined_function, event, process_info)
      :ok
    FunctionClauseError ->
      log_telemetry_skip(:function_clause, event, process_info)
      :ok
  catch
    :exit, {:noproc, _} ->
      log_telemetry_skip(:process_dead, event, process_info)
      :ok
    :exit, {:badarg, _} ->
      log_telemetry_skip(:ets_corruption, event, process_info)
      :ok
    :exit, {:normal, _} ->
      log_telemetry_skip(:process_shutdown, event, process_info)
      :ok
    kind, reason ->
      log_telemetry_skip({:unexpected_error, kind, reason}, event, process_info)
      :ok
  end
end
```

### 2. Graceful Shutdown Integration

```elixir
defp setup_exunit_integration do
  # Monitor ExUnit completion to prepare for shutdown
  pid = self()
  
  spawn(fn ->
    ref = Process.monitor(ExUnit.Server)
    receive do
      {:DOWN, ^ref, :process, _pid, _reason} ->
        send(pid, :prepare_for_shutdown)
    end
  end)
end

def handle_info(:prepare_for_shutdown, state) do
  Logger.debug("DSPEx Telemetry: Preparing for graceful shutdown")
  graceful_detach_handlers()
  {:noreply, %{state | telemetry_active: false, handlers_attached: false}}
end
```

### 3. Foundation Availability Checking

Before executing any Foundation telemetry calls, we check:

```elixir
if Foundation.available?() do
  # Proceed with telemetry
else
  # Skip gracefully
end
```

### 4. Comprehensive Error Categories Handled

- **ETS Unavailability**: `ArgumentError` when ETS tables are deleted
- **Process Death**: `:exit, {:noproc, _}` when processes are gone
- **ETS Corruption**: `:exit, {:badarg, _}` during table access
- **System Stress**: `SystemLimitError` during high load
- **Function Unavailability**: `UndefinedFunctionError` during shutdown
- **Contract Violations**: `FunctionClauseError` from Foundation changes
- **Normal Shutdown**: `:exit, {:normal, _}` during graceful cleanup

### 5. Debug Monitoring

Configurable debug logging helps track workaround effectiveness:

```elixir
# config/test.exs
config :dspex,
  telemetry_debug: false  # Set to true to debug telemetry issues
```

When enabled, provides detailed logs:

```
DSPEx Telemetry Handler: Skipped event due to :ets_unavailable
Event: [:dspex, :predict, :start]
Process Info: %{pid: #PID<...>, node: :nonode@nohost, ...}

This is expected during test cleanup or Foundation shutdown.
```

## Configuration

### Test Environment

```elixir
# config/test.exs
config :dspex,
  telemetry_debug: false,
  telemetry: %{
    enabled: true,
    defensive_mode: true,
    graceful_shutdown: true
  }
```

### Production Environment

The same defensive patterns work in production, protecting against:
- Application shutdown race conditions
- High-load scenarios
- Network partitions affecting Foundation

## Testing the Workaround

We've implemented comprehensive tests in `test/unit/telemetry_race_condition_test.exs`:

1. **Shutdown Survival Test**: Validates handlers survive Foundation shutdown
2. **ETS Unavailability Test**: Simulates ETS table deletion scenarios
3. **Lifecycle Management Test**: Tests state transitions during shutdown
4. **Stress Test**: High-concurrency telemetry with simulated failures
5. **Availability Check Test**: Validates Foundation availability checking

Run tests with:

```bash
mix test --only telemetry_race_condition
```

## Status and Impact

### ✅ Immediate Protection

- **Tests Run Clean**: No more crashes after successful test completion
- **Graceful Degradation**: Telemetry fails safely when Foundation unavailable
- **Production Stability**: Same protections work in production environments

### 📊 Monitoring

- **Debug Logging**: Optional detailed logging for troubleshooting
- **State Tracking**: Telemetry service state management during lifecycle transitions
- **Process Monitoring**: Enhanced visibility into race conditions

### 🔄 Foundation Integration Maintained

- **Full Feature Support**: All Foundation APIs (Infrastructure, Telemetry, Events) remain functional
- **Performance Tracking**: Comprehensive telemetry continues when Foundation available
- **Backward Compatibility**: Workaround doesn't break existing functionality

## Reported Issue

This race condition has been reported to the Foundation team as [GitHub Issue #4](https://github.com/nshkrdotcom/foundation/issues/4) with:

- **Detailed reproduction steps**
- **Root cause analysis**
- **Recommended fixes for Foundation**
- **Success criteria for resolution**

## Future Improvements

When Foundation team addresses the root cause, we can:

1. **Reduce Defensive Code**: Simplify handlers once race condition is fixed
2. **Remove Workarounds**: Clean up defensive patterns when no longer needed
3. **Enhanced Integration**: Use Foundation's native ExUnit integration when available

## Usage Guidelines

### For DSPEx Developers

1. **Keep Defensive Patterns**: Don't remove defensive code until Foundation issue is resolved
2. **Monitor Debug Logs**: Enable `telemetry_debug: true` when investigating issues
3. **Test Race Conditions**: Run telemetry race condition tests regularly

### For Foundation Users

This workaround pattern can be applied to any Elixir application using Foundation:

1. **Wrap Telemetry Calls**: Use try/catch around Foundation telemetry
2. **Check Availability**: Verify Foundation.available?() before calls
3. **Handle ETS Errors**: Gracefully handle `:badarg` and `:noproc` exits
4. **Monitor Cleanup**: Watch for ExUnit.Server lifecycle if using tests

The defensive programming patterns here provide a robust template for Foundation integration in any application. 