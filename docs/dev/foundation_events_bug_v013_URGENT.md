# 🚨 URGENT: Foundation.Events API Completely Broken in v0.1.2 & v0.1.3

## Issue Summary
**Foundation.Events API crashes with function clause error making it 100% unusable**

**Affected Versions**: v0.1.2, v0.1.3 (**Bug persists across releases**)

**Severity**: **CRITICAL** - Completely blocks any application using Foundation's event system

---

## 📋 Success Criteria (CLEAR FIX REQUIREMENTS)

### ✅ MUST WORK: Basic Event Creation and Storage
```elixir
# This MUST work without any errors
correlation_id = "test-#{System.unique_integer([:positive])}"

Foundation.Events.new_event(:test_event, %{data: "test"}, correlation_id: correlation_id)
|> Foundation.Events.store()

# Expected: {:ok, event_id}
# Actual: GenServer crash with function clause error
```

### ✅ MUST WORK: Event Pipeline Flow
1. `Foundation.Events.new_event/3` → Returns some result
2. `Foundation.Events.store/1` → Accepts that result  
3. Event gets validated and stored without crashes
4. Returns success tuple

### ❌ CURRENT BROKEN BEHAVIOR
```
** (FunctionClauseError) no function clause matching in Foundation.Validation.EventValidator.validate/1

The following arguments were given to Foundation.Validation.EventValidator.validate/1:
    # 1
    {:ok, %Foundation.Types.Event{...}}

Attempted function clauses (showing 1 out of 1):
    def validate(%Foundation.Types.Event{} = event)
```

---

## 🔍 Root Cause Analysis

**The Problem**: API contract mismatch in the event pipeline

1. **`Foundation.Events.new_event/3`** returns `{:ok, %Foundation.Types.Event{}}`
2. **`Foundation.Events.store/1`** passes this **wrapped tuple** to the event store
3. **Event store** calls `Foundation.Validation.EventValidator.validate/1` with the **wrapped tuple**
4. **Validator** expects **unwrapped** `%Foundation.Types.Event{}` but gets `{:ok, %Foundation.Types.Event{}}`
5. **Function clause matching fails** → GenServer crash

**Location**: `Foundation.Services.EventStore.handle_call/3` line 199

---

## 📝 Minimal Reproduction (GUARANTEED TO FAIL)

### Script: `foundation_events_broken.exs`
```elixir
#!/usr/bin/env elixir
Mix.install([{:foundation, "~> 0.1.3"}])

Application.ensure_all_started(:foundation)

# This WILL crash - 100% reproducible
Foundation.Events.new_event(:test, %{data: "test"}, correlation_id: "test-123")
|> Foundation.Events.store()
```

### Command: 
```bash
elixir foundation_events_broken.exs
```

### Result: 
```
** (FunctionClauseError) no function clause matching in Foundation.Validation.EventValidator.validate/1
```

---

## 🛠️ EXACT Fix Required (Choose ONE)

### Option 1: Fix Event Store (RECOMMENDED)
**File**: `lib/foundation/services/event_store.ex:199`

**Current** (broken):
```elixir
# handle_call passes wrapped tuple directly to validator
def handle_call({:store_event, event_data}, _from, state) do
  case Foundation.Validation.EventValidator.validate(event_data) do
    # ...
```

**Fixed**:
```elixir
def handle_call({:store_event, {:ok, event}}, _from, state) do
  case Foundation.Validation.EventValidator.validate(event) do
    # ...

def handle_call({:store_event, event}, _from, state) when is_struct(event, Foundation.Types.Event) do
  case Foundation.Validation.EventValidator.validate(event) do
    # ...
```

### Option 2: Fix Events Module
**File**: `lib/foundation/events.ex`

**Make `new_event/3` return unwrapped event**:
```elixir
# Instead of: {:ok, %Foundation.Types.Event{}}
# Return: %Foundation.Types.Event{}
```

### Option 3: Fix Validator
**File**: `lib/foundation/validation/event_validator.ex:46`

**Add function clause**:
```elixir
def validate({:ok, %Foundation.Types.Event{} = event}), do: validate(event)
def validate(%Foundation.Types.Event{} = event) do
  # existing logic
```

---

## 💥 Real-World Impact

### Production Applications Affected
- **Any app using Foundation.Events crashes immediately**
- **DSPEx project**: Had to disable ALL event calls (commented out 15+ event storage calls)
- **Zero workarounds available** - API is completely broken

### Code That HAD TO BE DISABLED:
```elixir
# ALL of these had to be commented out due to Foundation bug:
# Foundation.Events.new_event(:prediction_complete, data, correlation_id: id) |> Foundation.Events.store()
# Foundation.Events.new_event(:field_extraction_success, data, correlation_id: id) |> Foundation.Events.store()  
# Foundation.Events.new_event(:client_request_success, data, correlation_id: id) |> Foundation.Events.store()
```

---

## 🧪 Test Verification

**After fix, this MUST pass**:
```elixir
test "events API works end-to-end" do
  correlation_id = "test-#{System.unique_integer()}"
  
  result = Foundation.Events.new_event(:test_event, %{test: "data"}, correlation_id: correlation_id)
           |> Foundation.Events.store()
  
  assert {:ok, _event_id} = result
end
```

---

## 📊 Version Status Matrix

| Version | Circuit Breakers | Telemetry | Config | **Events** |
|---------|------------------|-----------|--------|------------|
| v0.1.2  | ✅ Working       | ✅ Working | ✅ Working | ❌ **BROKEN** |
| v0.1.3  | ✅ Working       | ✅ Working | ✅ Working | ❌ **STILL BROKEN** |

**The Events API has been broken across multiple releases!**

---

## 🎯 Clear Success Definition

**This issue is RESOLVED when**:
1. The reproduction script above runs without errors
2. The test case above passes
3. Real applications can use Foundation.Events without crashes
4. The event creation → storage pipeline works end-to-end

**Current Status**: ❌ All success criteria failing in v0.1.2 & v0.1.3

---

## 📞 Priority Justification

**CRITICAL Priority** because:
- Completely blocks Foundation.Events adoption
- Zero workarounds available  
- Affects any production app using events
- Bug persists across releases (not being addressed)
- Simple fix with clear solution paths

---

**NOTE**: Previous issue may not have been clear enough. This issue provides exact reproduction steps, specific fix locations, and crystal clear success criteria. 