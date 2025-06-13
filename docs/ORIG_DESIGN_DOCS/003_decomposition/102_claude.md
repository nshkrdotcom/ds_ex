# Minimal DSPy Foundational Layer

## Core Principle
**The smallest reusable unit that enables building any prompt engineering system**

## Foundation Components (4 Core Abstractions)

### 1. **Execution Primitive** (`primitives/module.py`)
```python
class BaseModule:
    """The fundamental execution unit - anything that can process inputs"""
    def forward(self, **kwargs) -> dict
    def __call__(self, **kwargs) -> dict  # handles tracing, callbacks
    def named_parameters(self) -> Iterator[Tuple[str, Any]]
    def dump_state(self) -> dict
    def load_state(self, state: dict) -> None
```

**Why Essential**: Every prompt engineering system needs composable execution units. This is the PyTorch.nn.Module equivalent.

### 2. **Interface Contract** (`signatures/signature.py`)
```python
class Signature:
    """Declarative I/O specification for any AI interaction"""
    input_fields: Dict[str, FieldInfo]
    output_fields: Dict[str, FieldInfo] 
    instructions: str
    
    @classmethod
    def from_string(cls, signature_str: str) -> 'Signature'
```

**Why Essential**: Every AI system needs to specify what goes in and what comes out. This is reusable across any AI modality.

### 3. **Backend Interface** (`clients/base_lm.py`)
```python
class BaseBackend:
    """Abstract interface to any AI service (LM, Vision, Audio, etc.)"""
    def __call__(self, prompt=None, messages=None, **kwargs) -> Any
    async def acall(self, prompt=None, messages=None, **kwargs) -> Any
```

**Why Essential**: Any prompt engineering system needs to talk to AI services. This abstraction works for LLMs, vision models, audio models, etc.

### 4. **Format Bridge** (`adapters/base.py`)
```python
class Adapter:
    """Converts between structured contracts and raw backend formats"""
    def format(self, signature: Signature, inputs: dict, **kwargs) -> Any
    def parse(self, signature: Signature, response: Any) -> dict
```

**Why Essential**: The gap between "what you want" (Signature) and "what the service expects" (strings/JSON/etc.) always exists.

## Data Containers (2 Essential Types)

### 5. **Data Primitive** (`primitives/example.py`)
```python
class Example:
    """Universal data container for AI interactions"""
    def __init__(self, **kwargs)
    def inputs(self) -> dict
    def labels(self) -> dict
    def with_inputs(self, *keys) -> 'Example'
```

### 6. **Configuration Context** (`utils/settings.py`)
```python
class Settings:
    """Thread-safe global configuration"""
    def configure(self, **kwargs)
    def context(self, **kwargs) -> ContextManager
```

## What's NOT Included (Deliberately)

- **No specific modules** (ChainOfThought, ReAct) - these are implementations
- **No specific adapters** (ChatAdapter, JSONAdapter) - these are implementations  
- **No specific backends** (OpenAI, Anthropic) - these are implementations
- **No optimization** (Teleprompters) - this is a higher-level concern
- **No evaluation** - this is application-level
- **No retrieval** - this is domain-specific

## Size and Dependencies

**Lines of Code**: ~2,000 lines (vs. 50,000+ in full DSPy)

**Dependencies**: 
- `pydantic` (for Signature field validation)
- `typing_extensions` (for Python <3.9 compatibility)
- That's it.

## Reusability Validation Test

This foundation enables building:

1. **Traditional prompt engineering**: `Signature` + `Adapter` + `Backend`
2. **Agent frameworks**: `BaseModule` composition + tool integration via `Adapter`
3. **Multi-modal systems**: Same abstractions work for vision, audio, etc.
4. **Different paradigms**: Function calling, structured output, reasoning chains
5. **Any language**: These abstractions translate to Go, Rust, Elixir, etc.

## Decoupling Achievement

✅ **Zero knowledge of**: Specific LLM providers, prompt formats, optimization strategies
✅ **Zero dependencies on**: Heavy ML libraries, specific service SDKs, optimization frameworks
✅ **Maximum reuse**: Same foundation works for chatbots, agents, analysis tools, creative apps

## Example Usage

```python
# This foundation enables any prompt engineering pattern:

# Simple completion
signature = Signature.from_string("question -> answer")
result = backend(adapter.format(signature, {"question": "What is AI?"}))
output = adapter.parse(signature, result)

# Complex multi-step reasoning  
class ReasoningModule(BaseModule):
    def forward(self, **kwargs):
        # Any reasoning pattern can be built
        pass

# Tool-using agent
class AgentModule(BaseModule):
    def forward(self, **kwargs):
        # Any agent pattern can be built
        pass
```

## Why This is the Right Boundary

1. **Maximum Reusability**: These 6 components appear in every prompt engineering system
2. **Achievable Decoupling**: No circular dependencies, clean interfaces
3. **Minimal Size**: Small enough to understand, maintain, and trust
4. **Complete Foundation**: Sufficient to build any higher-level pattern
5. **Future-Proof**: Abstractions that won't change as AI evolves

This is the **Linux kernel** of prompt engineering - minimal, stable, and universally useful.
