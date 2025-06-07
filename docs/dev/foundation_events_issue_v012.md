# Foundation Events API Bug in v0.1.2

## Summary
Foundation.Events API in v0.1.2 has a critical bug where the event validator crashes with a function clause error. The `Foundation.Validation.EventValidator.validate/1` function expects `%Foundation.Types.Event{}` but receives `{:ok, %Foundation.Types.Event{}}`.

## Environment
- **Foundation Version**: 0.1.2
- **Elixir Version**: 1.18.3
- **OTP Version**: 26

## Expected Behavior (Based on API Documentation)
According to Foundation's API, the Events workflow should be:

```elixir
# Create and store an event
Foundation.Events.new_event(:my_event_type, %{key: "value"}, correlation_id: "123")
|> Foundation.Events.store()
```

This should successfully create and store the event without errors.

## Actual Behavior
The event storage crashes with a GenServer termination:

```
** (FunctionClauseError) no function clause matching in Foundation.Validation.EventValidator.validate/1

The following arguments were given to Foundation.Validation.EventValidator.validate/1:

    # 1
    {:ok, %Foundation.Types.Event{event_type: :prediction_complete, event_id: 692607320, ...}}

Attempted function clauses (showing 1 out of 1):

    def validate(%Foundation.Types.Event{} = event)
```

## Root Cause Analysis
The issue is in the Foundation.Events pipeline:

1. `Foundation.Events.new_event/3` returns `{:ok, %Foundation.Types.Event{}}`
2. `Foundation.Events.store/1` passes this wrapped result to the event store
3. The event store calls `Foundation.Validation.EventValidator.validate/1` 
4. The validator expects `%Foundation.Types.Event{}` but receives `{:ok, %Foundation.Types.Event{}}`
5. Function clause matching fails → GenServer crash

## Detailed Reproduction Steps

### 1. Create Minimal Reproduction Script

```elixir
#!/usr/bin/env elixir

Mix.install([
  {:foundation, "~> 0.1.2"}
])

# Start Foundation application
Application.ensure_all_started(:foundation)

# Try to create and store a simple event
correlation_id = "test-#{System.unique_integer([:positive])}"

try do
  Foundation.Events.new_event(:test_event, %{test: "data"}, correlation_id: correlation_id)
  |> Foundation.Events.store()
  
  IO.puts("✅ Event stored successfully")
rescue
  error ->
    IO.puts("❌ Event storage failed: #{inspect(error)}")
end
```

### 2. Run the Script

```bash
elixir foundation_events_repro.exs
```

### 3. Observe the Error

The script will crash with the GenServer termination:

```
18:44:24.378 [error] GenServer {Foundation.ProcessRegistry, {:production, :event_store}} terminating
** (FunctionClauseError) no function clause matching in Foundation.Validation.EventValidator.validate/1
    (foundation 0.1.2) lib/foundation/validation/event_validator.ex:46: Foundation.Validation.EventValidator.validate({:ok, %Foundation.Types.Event{event_type: :test_event, event_id: 4334064499, timestamp: -576460751496, wall_time: ~U[2025-06-07 04:44:24.359731Z], node: :nonode@nohost, pid: #PID<0.95.0>, correlation_id: "test-4164", parent_id: nil, data: %{timestamp: ~U[2025-06-07 04:44:24.355720Z], test: "data"}}})
    (foundation 0.1.2) lib/foundation/services/event_store.ex:199: Foundation.Services.EventStore.handle_call/3
```

**Key observation**: The `Foundation.Events.new_event/3` returns `{:ok, %Foundation.Types.Event{}}` but `Foundation.Validation.EventValidator.validate/1` expects just `%Foundation.Types.Event{}`.

## Real-World Impact

This bug affects any application trying to use Foundation's event system. In our DSPEx project, we had to disable all Foundation.Events calls:

```elixir
# All these calls had to be commented out due to the bug
# Foundation.Events.new_event(:prediction_complete, data, correlation_id: id)
# |> Foundation.Events.store()
```

## Specific Error Examples from Our Tests

```
18:42:09.973 [error] GenServer {Foundation.ProcessRegistry, {:production, :event_store}} terminating
** (FunctionClauseError) no function clause matching in Foundation.Validation.EventValidator.validate/1
    (foundation 0.1.2) lib/foundation/validation/event_validator.ex:46: Foundation.Validation.EventValidator.validate({:ok, %Foundation.Types.Event{event_type: :prediction_complete, event_id: 692607320, timestamp: -576460750442, wall_time: ~U[2025-06-07 04:42:09.964389Z], node: :nonode@nohost, pid: #PID<0.416.0>, correlation_id: "8104a81e-b77a-4674-ac84-ca314047e6f2", parent_id: nil, data: %{signature: :MockSignature, success: true, output_fields: [:answer], duration_ms: 852}}})
    (foundation 0.1.2) lib/foundation/services/event_store.ex:199: Foundation.Services.EventStore.handle_call/3
```

## Suggested Fix

The issue appears to be in either:

1. **Foundation.Events.new_event/3** - Should return `%Foundation.Types.Event{}` instead of `{:ok, %Foundation.Types.Event{}}`
2. **Foundation.Services.EventStore.handle_call/3** - Should unwrap `{:ok, event}` before passing to validator
3. **Foundation.Validation.EventValidator.validate/1** - Should handle wrapped events

The cleanest fix would be option 2: unwrap the event in the event store before validation.

## Priority Assessment

**Priority: High**

This completely breaks the Foundation Events API, making it unusable in production. Any application relying on Foundation's event system will crash.

## Testing Notes

- ✅ Foundation.Infrastructure (circuit breakers) work correctly in v0.1.2  
- ✅ Foundation.Telemetry (emit_histogram, emit_counter) work correctly in v0.1.2
- ✅ Foundation.Config security whitelist working as intended
- ❌ Foundation.Events completely broken due to this validation bug

## Related Issues

This is a regression from our previous report where Foundation Events had validation issues. While the validator logic may have been updated, the function signature contract was not properly aligned with the data flow. 