# DSPEx MVP Implementation Plan & Progress Checklist

## Dependency Graph

```
DSPEx.Signature (Foundation)
    ↓
DSPEx.Adapter (Translation Layer)
    ↓
DSPEx.Client (HTTP/LLM Interface)
    ↓
DSPEx.Program/Predict (Execution Engine)
    ↓
DSPEx.Evaluate & Teleprompter (Optimization Layer)
```

## Core Components Mapping to Python DSPy

### 1. DSPEx.Signature
**Elixir Target**: `lib/dspex/signature.ex`
**Python Source**: `signatures/signature.py` (lines 1-300)

**Key Mappings**:
- `defsignature` macro → `Signature()` constructor (line 150-180)
- Field parsing → `_parse_signature()` (line 250-280)
- Instructions → `signature.instructions` property (line 85-90)
- Input/output fields → `input_fields`/`output_fields` properties (line 95-110)

**Status**: ⬜ Not Started
**Dependencies**: None
**Test Strategy**: Unit tests for macro expansion and field parsing

---

### 2. DSPEx.Adapter
**Elixir Target**: `lib/dspex/adapter.ex`
**Python Source**: `adapters/chat_adapter.py` (lines 1-200)

**Key Mappings**:
- `format/3` → `format()` method (line 50-80)
- `parse/2` → `parse()` method (line 180-200)
- Demo formatting → `format_demos()` (line 120-150)
- Field parsing → `field_header_pattern` regex (line 15-20)

**Status**: ⬜ Not Started
**Dependencies**: DSPEx.Signature
**Test Strategy**: Format/parse roundtrip tests

---

### 3. DSPEx.Client
**Elixir Target**: `lib/dspex/client.ex`
**Python Source**: `clients/lm.py` (lines 1-400)

**Key Mappings**:
- GenServer state → `LM.__init__()` (line 30-60)
- `request/3` → `forward()` method (line 180-220)
- Circuit breaker → Built into resilience patterns
- Caching → `cache` parameter handling (line 45-50)

**Status**: ⬜ Not Started
**Dependencies**: None (can use mock HTTP)
**Test Strategy**: HTTP mocking, circuit breaker simulation

---

### 4. DSPEx.Program & DSPEx.Predict
**Elixir Target**: `lib/dspex/program.ex`, `lib/dspex/predict.ex`
**Python Source**: `predict/predict.py` (lines 1-500)

**Key Mappings**:
- `forward/2` → `__call__()` method (line 150-200)
- Demo handling → `demos` property (line 80-90)
- Pipeline → `_forward_preprocess()` + `forward()` + `_forward_postprocess()` (lines 250-350)
- Error handling → Exception handling in `__call__()` (line 180-200)

**Status**: ⬜ Not Started
**Dependencies**: DSPEx.Signature, DSPEx.Adapter, DSPEx.Client
**Test Strategy**: End-to-end prediction tests

---

### 5. DSPEx.Evaluate
**Elixir Target**: `lib/dspex/evaluate.ex`
**Python Source**: `evaluate/evaluate.py` (lines 1-400)

**Key Mappings**:
- `run/4` → `__call__()` method (line 100-200)
- Concurrent execution → `ParallelExecutor` usage (line 150-180)
- Progress tracking → `display_progress` handling (line 90-100)
- Result aggregation → `_construct_result_table()` (line 250-300)

**Status**: ⬜ Not Started
**Dependencies**: DSPEx.Program
**Test Strategy**: Concurrent evaluation with mock programs

---

### 6. DSPEx.Teleprompter.BootstrapFewShot
**Elixir Target**: `lib/dspex/teleprompter/bootstrap_fewshot.ex`
**Python Source**: `teleprompt/bootstrap.py` (lines 1-600)

**Key Mappings**:
- `compile/4` → `compile()` method (line 50-100)
- Demo generation → `_bootstrap()` method (line 200-400)
- Teacher/student logic → Teacher program setup (line 80-120)
- Filtering logic → Success criteria checking (line 350-400)

**Status**: ⬜ Not Started
**Dependencies**: DSPEx.Evaluate, DSPEx.Program
**Test Strategy**: Integration test with mock LLM responses

---

## Supporting Data Structures

### DSPEx.Example
**Python Source**: `primitives/example.py` (lines 1-200)
- `new/1` → `Example.__init__()` (line 20-40)
- `with_inputs/2` → `with_inputs()` method (line 80-90)
- `inputs/1` → `inputs()` method (line 95-105)
- `labels/1` → `labels()` method (line 110-120)

### DSPEx.Prediction  
**Python Source**: `primitives/prediction.py` (lines 1-150)
- Struct fields → `Prediction.__init__()` (line 15-25)
- Access behavior → `__getitem__()` and similar (line 50-80)

## Implementation Priority Order

1. **DSPEx.Signature** (Foundation - can test in isolation)
2. **DSPEx.Client** (HTTP layer - can test with mocks)
3. **DSPEx.Adapter** (Translation - needs Signature)
4. **DSPEx.Program/Predict** (Execution - needs all above)
5. **DSPEx.Evaluate** (Evaluation - needs Program)
6. **DSPEx.Teleprompter** (Optimization - needs Evaluate)

## Testing Strategy Per Module

- **Unit Tests**: Each module in isolation with mocks
- **Integration Tests**: Cross-module functionality
- **Property Tests**: Especially for parsing and serialization
- **Concurrent Tests**: Evaluation engine stress testing
- **End-to-End Tests**: Full optimization loop

## Success Criteria

✅ **Signature**: Can parse "question -> answer" into input/output fields  
✅ **Client**: Can make HTTP calls to OpenAI with circuit breaking  
✅ **Adapter**: Can format prompts and parse responses  
✅ **Predict**: Can execute a simple Q&A program  
✅ **Evaluate**: Can run 100 predictions concurrently  
✅ **Teleprompter**: Can improve a program with few-shot examples  

## Checkboxes for Progress Tracking

### DSPEx.Signature
- ⬜ `use DSPEx.Signature` macro implementation
- ⬜ Signature string parser 
- ⬜ Field extraction and validation
- ⬜ Behaviour callbacks implementation
- ⬜ Unit tests with edge cases

### DSPEx.Client  
- ⬜ GenServer implementation
- ⬜ HTTP client integration (Req)
- ⬜ Circuit breaker integration (Fuse)
- ⬜ Caching integration (Cachex)
- ⬜ Error handling and retries

### DSPEx.Adapter
- ⬜ Chat adapter format implementation
- ⬜ Response parsing with regex
- ⬜ Demo formatting
- ⬜ Error handling for malformed responses
- ⬜ Roundtrip tests

### DSPEx.Program & Predict
- ⬜ Program behaviour definition
- ⬜ Predict struct and implementation
- ⬜ Forward pipeline orchestration
- ⬜ Demo management
- ⬜ Integration tests

### DSPEx.Evaluate
- ⬜ Concurrent Task.async_stream implementation
- ⬜ Progress bar integration
- ⬜ Result aggregation and error handling
- ⬜ Metrics calculation
- ⬜ Load testing

### DSPEx.Teleprompter
- ⬜ BootstrapFewShot GenServer
- ⬜ Teacher trace generation
- ⬜ Demo filtering and selection
- ⬜ Student program optimization
- ⬜ End-to-end optimization test