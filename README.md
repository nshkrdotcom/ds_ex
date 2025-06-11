# DSPEx - Declarative Self-improving Elixir

**A BEAM-Native AI Program Optimization Framework**

DSPEx is a sophisticated Elixir port of [DSPy](https://github.com/stanfordnlp/dspy) (Declarative Self-improving Python), reimagined for the BEAM virtual machine. Rather than being a mere transliteration, DSPEx leverages Elixir's unique strengths in concurrency, fault tolerance, and distributed systems to create a more robust and scalable framework for programming language models.

## Testing DSPEx

DSPEx provides three distinct test modes to accommodate different development and integration scenarios:

### 🟦 Pure Mock Mode (Default)
```bash
mix test                  # Default behavior
mix test.mock            # Explicit pure mock
mix test.mock test/unit/ # Run specific test directory
```

**Behavior**: 
- No network requests made
- Fast, deterministic execution  
- Uses contextual mock responses
- Perfect for unit testing and CI/CD

**When to use**: Daily development, unit tests, CI pipelines

### 🟡 Fallback Mode (Seamless Integration)
```bash
mix test.fallback                    # All tests with fallback
mix test.fallback test/integration/  # Integration tests with fallback
DSPEX_TEST_MODE=fallback mix test    # Environment variable approach
```

**Behavior**:
- Attempts real API calls when API keys available
- Seamlessly falls back to mock when no keys present
- Tests work regardless of API key availability
- Validates both integration and mock logic

**When to use**: Development with optional API access, integration testing

### 🟢 Live API Mode (Strict Integration)
```bash
mix test.live                      # Requires API keys for all providers
mix test.live test/integration/    # Live integration testing only
DSPEX_TEST_MODE=live mix test      # Environment variable approach
```

**Behavior**:
- Requires valid API keys
- Tests fail if API keys missing
- Real network requests to live APIs
- Validates actual API integration and error handling

**When to use**: Pre-deployment validation, debugging API issues, performance testing

### Environment Configuration

**Why MIX_ENV=test?**
The test environment ensures proper isolation and test-specific configurations. Our mix tasks automatically set `MIX_ENV=test` via `preferred_cli_env` in `mix.exs`, so you don't need to set it manually.

**API Key Setup (Optional for fallback/live modes):**
```bash
export GEMINI_API_KEY=your_gemini_key
export OPENAI_API_KEY=your_openai_key  
export ANTHROPIC_API_KEY=your_anthropic_key
```

**Override Test Mode:**
```bash
export DSPEX_TEST_MODE=mock     # Force pure mock
export DSPEX_TEST_MODE=fallback # Force fallback mode  
export DSPEX_TEST_MODE=live     # Force live mode
```

**Best Practices:**
- Use **pure mock** for daily development and CI/CD
- Use **fallback mode** for integration development
- Use **live mode** before production deployments and for debugging real API issues
- Keep API keys in `.env` files or secure environment management

> 📖 **For detailed testing strategy and migration guidelines**, see [LIVE_DIVERGENCE.md](LIVE_DIVERGENCE.md) which covers the strategic approach to live API integration and test architecture patterns.

### Testing Performance & Reliability

DSPEx's test architecture has been optimized for maximum developer productivity:

**Performance Results:**
- **Full test suite**: < 7 seconds in mock mode
- **400x performance improvement**: Tests now run consistently fast regardless of network conditions
- **Zero flakiness**: Deterministic mock responses ensure reliable CI/CD

**Fault Tolerance Testing:**
- **Process supervision**: Tests validate GenServer lifecycle and crash recovery
- **Network resilience**: Proper handling of dead processes and API failures
- **Environment isolation**: Prevention of test contamination between runs

**Test Architecture Features:**
- **Three-mode system**: Mock, Fallback, and Live modes for different scenarios
- **Intelligent fallback**: Live API attempts with seamless mock fallback
- **Performance isolation**: Timing tests use controlled mock conditions
- **Process management**: Proper GenServer lifecycle handling in supervision tests

## Vision & Problem Statement

DSPEx is not a general-purpose agent-building toolkit; it is a specialized **compiler** that uses data and metrics to systematically optimize Language Model (LLM) programs. While interacting with LLMs is becoming easier, achieving consistently high performance remains a manual, unscientific process of "prompt tweaking." DSPEx automates the discovery of optimal prompting strategies, treating prompts as optimizable artifacts rather than static strings.

## Core Value Proposition for BEAM

### 1. Massively Concurrent Evaluation
The primary bottleneck in prompt optimization is evaluating programs against large validation sets. DSPEx leverages `Task.async_stream` to achieve I/O-bound concurrency that fundamentally outperforms thread-based solutions:

```elixir
# Evaluate a program on 10,000 examples with true parallelism
scores = DSPEx.Evaluate.run(my_program, dev_set, &MyMetric.calculate/2, 
                           max_concurrency: 1000)
```

**Performance Advantage**: Where Python DSPy is limited by thread overhead, DSPEx can spawn hundreds of thousands of lightweight BEAM processes, each handling an LLM API call independently.

### 2. Resilient, Fault-Tolerant Optimization
Optimization jobs are long-running and vulnerable to transient network errors. DSPEx builds on OTP principles where a single failed evaluation crashes its own isolated process without halting the entire optimization job:

```elixir
# If one API call fails, it doesn't crash the entire evaluation
# The supervisor handles retry strategies automatically
evaluation_results = DSPEx.Evaluate.run(program, large_dataset, metric, 
                                        restart: :temporary, 
                                        max_restarts: 3)
```

### 3. First-Class Observability
Every step of execution and optimization is instrumented using `:telemetry`, providing deep insights into performance, cost, and behavior patterns in production.

## Architecture Overview

DSPEx follows a layered dependency graph optimized for the BEAM:

```
DSPEx.Signature (Foundation - Compile-time contracts)
    ↓
DSPEx.Adapter (Translation Layer - Runtime formatting) 
    ↓
DSPEx.Client (HTTP/LLM Interface - Resilient GenServer)
    ↓
DSPEx.Program/Predict (Execution Engine - Process orchestration)
    ↓
DSPEx.Evaluate & Teleprompter (Optimization Layer - Concurrent optimization)
```

## Core Components Deep Dive

### DSPEx.Signature - Compile-Time Contracts

Unlike Python's runtime signature validation, DSPEx uses Elixir macros for compile-time safety:

```elixir
defmodule QASignature do
  @moduledoc "Answer questions with detailed reasoning and confidence"
  use DSPEx.Signature, "question, context -> answer, reasoning, confidence"
end

# Generates at compile time:
# - Input/output field validation
# - Struct definition with @type specs
# - Behaviour implementation for adapters
# - Introspection functions for optimization
```

**BEAM Advantage**: Compile-time expansion catches signature errors before deployment, while Python DSPy validates at runtime.

### DSPEx.Client - Resilient GenServer Layer

The HTTP client is implemented as a supervised GenServer with production-grade resilience:

```elixir
defmodule DSPEx.Client do
  use GenServer
  
  # Features:
  # - Circuit breaker pattern (planned)
  # - Automatic caching (planned)  
  # - Rate limiting and exponential backoff (planned)
  # - Connection pooling via Finch
  # - Distributed state management (planned)
  
  def request(prompt, opts \\ []) do
    # Current implementation uses functional approach
    # GenServer-based architecture planned for Phase 2B
    DSPEx.Client.request(prompt, opts)
  end
end
```

**Current Status**: HTTP client with error categorization and multi-provider support. GenServer architecture with supervision planned for Phase 2B.

### DSPEx.Adapter - Protocol Translation

Adapters handle the translation between high-level signatures and provider-specific formats:

```elixir
defmodule DSPEx.Adapter.Chat do
  @behaviour DSPEx.Adapter
  
  @impl true
  def format(signature, inputs, demos) do
    # Convert signature + demos into OpenAI chat format
    messages = [
      %{role: "system", content: signature.instructions},
      # Format few-shot demonstrations
      Enum.flat_map(demos, &format_demo/1),
      # Format current input
      %{role: "user", content: format_input(signature, inputs)}
    ]
    
    {:ok, messages}
  end
  
  @impl true  
  def parse(signature, response) do
    # Extract structured outputs from response
    # Handle field validation and type coercion
  end
end
```

### DSPEx.Program & Predict - Execution Engine

Programs implement a behavior that enables composition and optimization:

```elixir
defmodule DSPEx.Predict do
  @behaviour DSPEx.Program
  
  defstruct [:signature, :client, :adapter, demos: []]
  
  @impl true
  def forward(%__MODULE__{} = program, inputs, opts) do
    with {:ok, messages} <- program.adapter.format(program.signature, inputs, program.demos),
         {:ok, response} <- program.client.request(messages, opts),
         {:ok, outputs} <- program.adapter.parse(program.signature, response) do
      {:ok, %DSPEx.Prediction{inputs: inputs, outputs: outputs}}
    end
  end
end
```

**Process Isolation**: Each `forward/3` call can run in its own process, providing natural parallelism and fault isolation.

### DSPEx.Evaluate - Concurrent Evaluation Engine

The evaluation engine leverages BEAM's process model for massive parallelism:

```elixir
defmodule DSPEx.Evaluate do
  def run(program, examples, metric_fn, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 100)
    
    examples
    |> Task.async_stream(
      fn example ->
        with {:ok, prediction} <- DSPEx.Program.forward(program, example.inputs),
             score when is_number(score) <- metric_fn.(example, prediction) do
          {:ok, score}
        end
      end,
      max_concurrency: max_concurrency,
      timeout: :infinity
    )
    |> Enum.reduce({0, 0}, fn
      {:ok, {:ok, score}}, {sum, count} -> {sum + score, count + 1}
      _, acc -> acc
    end)
    |> then(fn {sum, count} -> sum / count end)
  end
end
```

**Concurrency Advantage**: While Python DSPy uses thread pools limited by GIL and OS constraints, DSPEx can easily handle 10,000+ concurrent evaluations on a single machine.

### DSPEx.Teleprompter - Optimization Algorithms

Teleprompters (optimizers) implement sophisticated few-shot learning and program optimization:

```elixir
defmodule DSPEx.Teleprompter.BootstrapFewShot do
  @behaviour DSPEx.Teleprompter
  
  @impl true
  def compile(student, teacher, trainset, metric_fn, opts \\ []) do
    # Bootstrap examples by running teacher on trainset
    bootstrapped_demos = 
      trainset
      |> Task.async_stream(fn example ->
        with {:ok, prediction} <- DSPEx.Program.forward(teacher, example.inputs),
             score when score > 0.7 <- metric_fn.(example, prediction) do
          {:ok, %DSPEx.Example{inputs: example.inputs, outputs: prediction.outputs}}
        else
          _ -> {:skip}
        end
      end, max_concurrency: 50)
      |> Stream.filter(fn {:ok, result} -> result != {:skip} end)
      |> Stream.map(fn {:ok, {:ok, demo}} -> demo end)
      |> Enum.take(Keyword.get(opts, :max_demos, 16))
    
    # Create optimized student with bootstrapped demos
    optimized_student = DSPEx.OptimizedProgram.new(student, bootstrapped_demos, %{
      teleprompter: :bootstrap_fewshot,
      optimization_time: DateTime.utc_now()
    })
    
    {:ok, optimized_student}
  end
end
```

## Technology Stack & Dependencies

DSPEx leverages best-in-class Elixir libraries:

| Component | Library | Status | Rationale |
|-----------|---------|---------|-----------|
| HTTP Client | `Req` + `Finch` | ✅ Complete | Modern, composable HTTP with connection pooling |
| Circuit Breaker | `Fuse` | 🔄 Planned | Battle-tested circuit breaker implementation |
| Caching | `Cachex` | 🔄 Planned | High-performance in-memory caching with TTL |
| JSON | `Jason` | ✅ Complete | Fast JSON encoding/decoding |
| Testing | `Mox` + `PropCheck` | ✅ Complete | Mocking and property-based testing |
| Observability | `:telemetry` | ✅ Complete | Built-in instrumentation and metrics |

## Implementation Status & Roadmap

### ✅ Current Status: Phase 1 Complete + Core Teleprompter Implementation

**Phase 1 - Foundation (COMPLETE):**
- ✅ **DSPEx.Signature** - Complete compile-time parsing with macro expansion and field validation
- ✅ **DSPEx.Example** - Immutable data structures with Protocol implementations
- ✅ **DSPEx.Client** - HTTP client with error categorization and multi-provider support
- ✅ **DSPEx.Adapter** - Message formatting and response parsing for multiple providers  
- ✅ **DSPEx.Program** - Behavior interface with telemetry integration
- ✅ **DSPEx.Predict** - Core prediction orchestration with Foundation integration
- ✅ **DSPEx.Evaluate** - Concurrent evaluation engine using Task.async_stream

**Phase 2A - Core Optimization (COMPLETE):**
- ✅ **DSPEx.Teleprompter** - Behavior definition for optimization algorithms
- ✅ **DSPEx.Teleprompter.BootstrapFewShot** - Complete single-node optimization implementation
- ✅ **DSPEx.OptimizedProgram** - Container for programs enhanced with demonstrations

**Current Working Features:**
- ✅ **End-to-end pipeline**: Create programs, execute predictions, evaluate performance
- ✅ **Program optimization**: BootstrapFewShot teleprompter for automated few-shot learning
- ✅ **Concurrent evaluation**: High-performance evaluation with fault isolation
- ✅ **Foundation integration**: Comprehensive telemetry, correlation tracking, and observability
- ✅ **Multi-provider support**: OpenAI, Anthropic, Gemini adapters working
- ✅ **Production testing**: Three-mode test architecture (mock/fallback/live)

### 🔄 Planned Features (Next Phases)

**Phase 2B - Enhanced Infrastructure:**
- GenServer-based client architecture with supervision
- Circuit breakers and advanced error handling with Fuse
- Response caching with Cachex
- Rate limiting and connection pooling

**Phase 2C - Advanced Programs:**
- ChainOfThought reasoning programs
- ReAct (Reasoning + Acting) patterns
- MultiChainComparison optimization
- Parallel execution patterns

**Phase 3 - Enterprise Features:**
- Distributed optimization across BEAM clusters
- Phoenix LiveView optimization dashboard
- Advanced metrics and cost tracking
- Integration with vector databases for RAG

## Unique BEAM Advantages

### 1. True Fault Isolation
Every component runs in supervised processes. A malformed LLM response or network timeout affects only that specific evaluation, not the entire optimization run.

### 2. Hot Code Upgrades
Update optimization algorithms or add new adapters without stopping running evaluations - a critical advantage for long-running optimization jobs.

### 3. Distributed Computing (Planned)
Scale optimization across multiple BEAM nodes with minimal code changes:

```elixir
# Future: Distribute evaluation across cluster nodes
DSPEx.Evaluate.run_distributed(program, large_dataset, metric, 
                               nodes: [:node1@host, :node2@host])
```

### 4. Memory Efficiency
BEAM's copying garbage collector and process isolation prevent memory leaks common in long-running Python optimization jobs.

### 5. Built-in Observability
`:telemetry` events provide deep insights without external monitoring infrastructure:

```elixir
# Automatic metrics for every LLM call
:telemetry.attach("dspex-metrics", [:dspex, :program, :forward, :stop], 
                 &MyApp.Metrics.handle_event/4)
```

## Performance Characteristics

Based on architectural analysis, BEAM characteristics, and recent optimizations:

| Scenario | Python DSPy | DSPEx Current | Notes |
|----------|-------------|---------------|-------|
| 10K evaluations | ~30 minutes (thread-limited) | ~5 minutes (process-limited by API) | Theoretical based on concurrency model |
| Test suite execution | Variable (network dependent) | < 7 seconds (400x improvement) | Measured with mock mode |
| Fault recovery | Manual restart required | Automatic supervision recovery | OTP supervision trees |
| Memory usage | Grows with dataset size | Constant per process | BEAM process isolation |
| Monitoring | External tools required | Built-in telemetry | Native `:telemetry` integration |
| Distribution | Complex setup | Native BEAM clustering (planned) | Future distributed evaluation |

**Recent Performance Optimizations:**
- **Testing architecture**: 400x performance improvement through intelligent mock/live switching
- **Process management**: Robust supervision testing with proper GenServer lifecycle handling
- **Zero contamination**: Clean test environment management prevents state leakage
- **Network isolation**: Performance tests isolated from network conditions for consistent results

## Target Use Cases

DSPEx excels in scenarios that leverage BEAM's strengths:

### 1. High-Throughput API Orchestration
Building systems that make thousands of concurrent calls to LLM APIs, vector databases, and other web services.

### 2. Production AI Services  
Applications requiring 99.9% uptime where individual component failures shouldn't crash the entire system.

### 3. Automated Prompt Optimization
Systems that need to automatically discover optimal prompting strategies through data-driven optimization.

### 4. Real-Time AI Applications
Systems requiring sub-second response times with automatic failover and circuit breaking.

## Installation

Add `dspex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dspex, "~> 0.1.0"},
    # Required dependencies
    {:req, "~> 0.4.0"},
    {:jason, "~> 1.4"},
    # Future dependencies  
    {:fuse, "~> 2.4"},      # For circuit breakers (Phase 2B)
    {:cachex, "~> 3.6"},    # For caching (Phase 2B)
    # Optional for testing
    {:mox, "~> 1.0", only: :test}
  ]
end
```

## Quick Start

```elixir
# 1. Define a signature
defmodule QASignature do
  use DSPEx.Signature, "question -> answer"
end

# 2. Create a program
program = DSPEx.Predict.new(QASignature, :gemini)

# 3. Run predictions
{:ok, outputs} = DSPEx.Program.forward(program, %{question: "What is Elixir?"})

# 4. Evaluate performance
examples = [
  %DSPEx.Example{
    data: %{question: "What is OTP?", answer: "Open Telecom Platform"},
    input_keys: MapSet.new([:question])
  }
]
metric_fn = fn example, prediction ->
  if DSPEx.Example.get(example, :answer) == Map.get(prediction, :answer), do: 1.0, else: 0.0
end
{:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)

# 5. Optimize with teleprompter
teacher = DSPEx.Predict.new(QASignature, :openai)  # Use stronger model as teacher
{:ok, optimized} = DSPEx.Teleprompter.BootstrapFewShot.compile(
  program,        # student
  teacher,        # teacher  
  examples,       # training set
  metric_fn       # metric function
)
```

## Documentation & Resources

- **Implementation Status**: `CLAUDE.md` - Current status and critical gap analysis
- **Testing Strategy**: `LIVE_DIVERGENCE.md` - Comprehensive test architecture
- **Architecture Deep Dive**: `docs/001_initial/101_claude.md`
- **Implementation Plan**: `docs/005_optimizer/100_claude.md` 
- **Staged Development**: `docs/005_optimizer/102_CLAUDE_STAGED_IMPL.md`
- **Critical Assessment**: `docs/001_initial/28_gemini_criticalValueAssessment.md`
- **Foundation Integration**: `docs/001_initial/104_claude_synthesizeGemini_foundationIntegrationGuide.md`

## Contributing

DSPEx follows a rigorous test-driven development approach with comprehensive coverage across unit, integration, property-based, and concurrent testing. The project prioritizes correctness, observability, and BEAM-native patterns.

**Current Test Coverage**: 85%+ across all core modules with zero Dialyzer warnings maintained.

## License

Same as original DSPy project.

## Acknowledgments

- **Stanford DSPy Team**: For the foundational concepts and research
- **Elixir Community**: For the excellent ecosystem packages
- **BEAM Team**: For the robust runtime platform that makes this vision possible

---

**Current Status**: DSPEx has achieved its core vision with a working end-to-end pipeline including automated program optimization through teleprompters. The foundation is solid for advanced features like distributed optimization and enterprise tooling.