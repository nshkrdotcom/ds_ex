# DSPEx - Declarative Self-improving Elixir

**A BEAM-Native AI Program Optimization Framework**

DSPEx is a sophisticated Elixir port of [DSPy](https://github.com/stanfordnlp/dspy) (Declarative Self-improving Python), reimagined for the BEAM virtual machine. Rather than being a mere transliteration, DSPEx leverages Elixir's unique strengths in concurrency, fault tolerance, and distributed systems to create a more robust and scalable framework for programming language models.

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
  # - Circuit breaker pattern (Fuse library)
  # - Automatic caching (Cachex)  
  # - Rate limiting and exponential backoff
  # - Connection pooling via Finch
  # - Distributed state management
  
  def request(prompt, opts \\ []) do
    GenServer.call(__MODULE__, {:request, prompt, opts})
  end
end
```

**Fault Tolerance**: If the client crashes due to network issues, the supervisor restarts it while preserving cached results and circuit breaker state.

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

Teleprompters (optimizers) are implemented as GenServers for stateful, long-running optimization processes:

```elixir
defmodule DSPEx.Teleprompter.BootstrapFewShot do
  use GenServer
  @behaviour DSPEx.Teleprompter
  
  @impl true
  def compile(student, teacher, trainset, metric_fn, opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, %{
      student: student,
      teacher: teacher, 
      trainset: trainset,
      metric_fn: metric_fn,
      demos: [],
      target_demos: Keyword.get(opts, :max_demos, 16)
    })
    
    GenServer.call(pid, :optimize, :infinity)
  end
  
  def handle_call(:optimize, _from, state) do
    # Bootstrap examples by running teacher on trainset
    bootstrapped_demos = 
      state.trainset
      |> Task.async_stream(fn example ->
        with {:ok, prediction} <- DSPEx.Program.forward(state.teacher, example.inputs),
             score when score > 0.7 <- state.metric_fn.(example, prediction) do
          {:ok, %DSPEx.Example{inputs: example.inputs, outputs: prediction.outputs}}
        else
          _ -> {:skip}
        end
      end, max_concurrency: 50)
      |> Stream.filter(fn {:ok, result} -> result != {:skip} end)
      |> Stream.map(fn {:ok, {:ok, demo}} -> demo end)
      |> Enum.take(state.target_demos)
    
    # Create optimized student with bootstrapped demos
    optimized_student = %{state.student | demos: bootstrapped_demos}
    
    {:reply, {:ok, optimized_student}, state}
  end
end
```

## Technology Stack & Dependencies

DSPEx leverages best-in-class Elixir libraries:

| Component | Library | Rationale |
|-----------|---------|-----------|
| HTTP Client | `Req` + `Finch` | Modern, composable HTTP with connection pooling |
| Circuit Breaker | `Fuse` | Battle-tested circuit breaker implementation |
| Caching | `Cachex` | High-performance in-memory caching with TTL |
| JSON | `Jason` | Fast JSON encoding/decoding |
| Testing | `Mox` + `PropCheck` | Mocking and property-based testing |
| Observability | `:telemetry` | Built-in instrumentation and metrics |

## Implementation Status & Roadmap

### Current Status: 🚧 Phase 1 Implementation

**Completed:**
- ✅ Comprehensive architectural documentation
- ✅ 6-stage implementation plan with 598+ test cases
- ✅ Technology stack selection and dependency analysis
- ✅ Line-by-line mapping to Python DSPy source

**Phase 1 - Foundation (In Progress):**
- 🚧 DSPEx.Signature (compile-time parsing and validation)
- 🚧 DSPEx.Example (core data structures)
- ⬜ DSPEx.Client (resilient HTTP layer)
- ⬜ DSPEx.Adapter (translation layer)
- ⬜ DSPEx.Program/Predict (execution engine)
- ⬜ DSPEx.Evaluate (concurrent evaluation)
- ⬜ DSPEx.Teleprompter (optimization algorithms)

### Planned Features

**Phase 2 - Advanced Programs:**
- ChainOfThought reasoning
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

### 3. Distributed Computing
Scale optimization across multiple BEAM nodes with minimal code changes:

```elixir
# Distribute evaluation across cluster nodes
DSPEx.Evaluate.run_distributed(program, large_dataset, metric, 
                               nodes: [:node1@host, :node2@host])
```

### 4. Memory Efficiency
BEAM's copying garbage collector and process isolation prevent memory leaks common in long-running Python optimization jobs.

### 5. Built-in Observability
`:telemetry` events provide deep insights without external monitoring infrastructure:

```elixir
# Automatic metrics for every LLM call
:telemetry.attach("dspex-metrics", [:dspex, :lm, :request, :stop], 
                 &MyApp.Metrics.handle_event/4)
```

## Performance Characteristics

Based on architectural analysis and BEAM characteristics:

| Scenario | Python DSPy | DSPEx Advantage |
|----------|-------------|-----------------|
| 10K evaluations | ~30 minutes (thread-limited) | ~5 minutes (process-limited by API) |
| Fault recovery | Manual restart required | Automatic supervision recovery |
| Memory usage | Grows with dataset size | Constant per process |
| Monitoring | External tools required | Built-in telemetry |
| Distribution | Complex setup | Native BEAM clustering |

## Target Use Cases

DSPEx excels in scenarios that leverage BEAM's strengths:

### 1. High-Throughput API Orchestration
Building systems that make thousands of concurrent calls to LLM APIs, vector databases, and other web services.

### 2. Production AI Services  
Applications requiring 99.9% uptime where individual component failures shouldn't crash the entire system.

### 3. Distributed Optimization
Large-scale prompt optimization jobs distributed across multiple BEAM nodes.

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
    {:fuse, "~> 2.4"},
    {:cachex, "~> 3.6"},
    {:jason, "~> 1.4"},
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
program = %DSPEx.Predict{
  signature: QASignature,
  client: DSPEx.Client.OpenAI.new(api_key: "your-key"),
  adapter: DSPEx.Adapter.Chat
}

# 3. Run predictions
{:ok, prediction} = DSPEx.Program.forward(program, %{question: "What is Elixir?"})

# 4. Evaluate performance
examples = [%DSPEx.Example{inputs: %{question: "What is OTP?"}, outputs: %{answer: "..."}}]
score = DSPEx.Evaluate.run(program, examples, &accuracy_metric/2)

# 5. Optimize with teleprompter
teacher = %DSPEx.Predict{signature: QASignature, client: advanced_client}
{:ok, optimized} = DSPEx.Teleprompter.BootstrapFewShot.compile(
  program, teacher, training_set, &accuracy_metric/2
)
```

## Documentation & Resources

- **Architecture Deep Dive**: `docs/001_initial/101_claude.md`
- **Implementation Plan**: `docs/005_optimizer/100_claude.md` 
- **Staged Development**: `docs/005_optimizer/102_CLAUDE_STAGED_IMPL.md`
- **Critical Assessment**: `docs/001_initial/28_gemini_criticalValueAssessment.md`
- **Foundation Integration**: `docs/001_initial/104_claude_synthesizeGemini_foundationIntegrationGuide.md`

## Contributing

DSPEx follows a rigorous test-driven development approach with 6 implementation stages. See `TESTS.md` for the comprehensive testing strategy covering 598+ test cases.

## License

Same as original DSPy project.

## Acknowledgments

- **Stanford DSPy Team**: For the foundational concepts and research
- **Elixir Community**: For the excellent ecosystem packages
- **BEAM Team**: For the robust runtime platform that makes this vision possible

---

**Note for Senior Engineers**: This README reflects a production-ready architectural vision. The current implementation is in Phase 1, with comprehensive documentation available in the `docs/` directory. The project prioritizes correctness, observability, and BEAM-native patterns over rapid prototyping.

