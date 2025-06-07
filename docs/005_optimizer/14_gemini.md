Of course. Having defined the complete test structure, the final piece of the technical plan is to specify the developer experience: the public-facing documentation and API surface. This ensures the framework is not only powerful and well-tested but also intuitive and easy to adopt.

This document concludes the technical specification by outlining the primary `README.md`, module-level documentation (`@moduledoc`), and function-level documentation (`@doc`) that will guide users.

---

### **Document 5: Documentation & Developer Experience**

**Objective:** To define the public-facing documentation and API, ensuring that `DSPEx` is approachable, understandable, and a pleasure to use for Elixir developers. This includes a comprehensive `README.md` for project discovery and high-quality inline documentation for `ExDoc`.

#### **1. Project `README.md`**

This is the front door to the project. It must be clear, concise, and provide a compelling "Quick Start" example that demonstrates the core value proposition of the framework.

```markdown
# DSPEx: A DSPy-inspired Framework for Elixir

**Programming, not just prompting, Large Language Models.**

DSPEx brings the core philosophy of the [DSPy framework](https://github.com/stanford-oval/dspy) to the Elixir ecosystem. It provides a structured, systematic, and composable way to build and optimize powerful applications on top of Large Language Models (LLMs).

Instead of relying on fragile, hand-tuned prompts, DSPEx allows you to define programs that can learn from data. These programs use `Signatures` to declare their I/O contracts and can be automatically optimized using `Teleprompters` to generate high-quality few-shot examples, turning simple models into powerful, specialized agents.

Built on OTP, `DSPEx` is designed from the ground up to be:
*   **Concurrent:** Evaluate and optimize programs against large datasets with maximum efficiency using lightweight Elixir processes.
*   **Resilient:** Isolated, stateful clients with circuit breakers and automatic caching prevent cascading failures and reduce redundant API calls.
*   **Composable:** Every module, from a simple `Predict` to a complex `ChainOfThought`, adheres to the same `Program` behaviour, allowing them to be swapped, nested, and optimized interchangeably.

---

### Quick Start: Building and Optimizing a Q&A Program

This example demonstrates the end-to-end workflow: define, evaluate, optimize, and re-evaluate.

```elixir
# 1. Define the I/O contract for our program.
defmodule QASignature do
  @moduledoc "Answer questions with a short, factual answer."
  use DSPEx.Signature, "question -> answer"
end

# 2. Create a small development set for evaluation and optimization.
devset = [
  %DSPEx.Example{data: %{question: "What is the capital of France?", answer: "Paris"}},
  %DSPEx.Example{data: %{question: "Who wrote '1984'?", answer: "George Orwell"}}
]
|> Enum.map(&DSPEx.Example.with_inputs(&1, [:question]))

# 3. Define a simple metric to score predictions.
metric_fun = fn example, prediction ->
  if String.trim(example.labels.answer) == String.trim(prediction.outputs.answer), do: 1.0, else: 0.0
end

# 4. Start the LLM client (e.g., for OpenAI).
#    This would typically be in your application's supervision tree.
{:ok, client_pid} = DSPEx.Client.start_link(
  name: :openai_client,
  config: %{
    api_key: System.get_env("OPENAI_API_KEY"),
    model: "gpt-4o-mini",
    base_url: "https://api.openai.com/v1/chat/completions"
  }
)

# 5. Create a simple, un-optimized (zero-shot) program.
uncompiled_program = %DSPEx.Predict{signature: QASignature, client: :openai_client}

# 6. Evaluate its baseline performance.
{:ok, baseline_score, _success, _failures} =
  DSPEx.Evaluate.run(uncompiled_program, devset, metric_fun)

IO.puts("Baseline Score: #{baseline_score}")
# => Baseline Score: 0.5 (example output, may vary)

# 7. Use a "teleprompter" to optimize the program by creating few-shot examples.
#    We use the same program as both student and teacher here for simplicity.
teleprompter = %DSPEx.Teleprompter.BootstrapFewShot{metric: metric_fun, max_demos: 1}

# The `compile` step runs the optimization process.
compiled_program = teleprompter.compile(uncompiled_program, trainset: devset)

# 8. Evaluate the newly compiled program.
{:ok, compiled_score, _success, _failures} =
  DSPEx.Evaluate.run(compiled_program, devset, metric_fun)

IO.puts("Compiled Score: #{compiled_score}")
# => Compiled Score: 1.0 (example output)

# The compiled program now has few-shot examples and performs better!
# IO.inspect(compiled_program.demos)
```

### Installation

Add `dspex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dspex, "~> 0.1.0"}
  ]
end
```

### Core Concepts

*   **Signatures:** Declarative I/O contracts for your programs.
*   **Programs:** Executable modules that call LLMs (`Predict`, `ChainOfThought`, etc.).
*   **Adapters:** Translate between abstract signatures and concrete LLM API formats (e.g., OpenAI Chat).
*   **Teleprompters:** Optimizers that "compile" your programs by generating effective few-shot demonstrations.
*   **Evaluation:** A concurrent engine to measure your program's performance against a dataset.

```

#### **2. Inline API Documentation (`@moduledoc` and `@doc`)**

This documentation will be written directly in the source code, allowing `ExDoc` to generate a professional and searchable documentation website.

**`lib/dspex/signature.ex`**

```elixir
defmodule DSPEx.Signature do
  @moduledoc """
  Defines the `@behaviour` and `use` macro for creating DSPEx Signatures.

  A signature declaratively defines the inputs and outputs of a DSPEx program.
  Using this macro at compile-time generates an efficient struct and the necessary
  functions to interact with the framework. All parsing happens at compile time,
  resulting in zero runtime overhead.

  ## Example

      defmodule QASignature do
        @moduledoc "Answer questions with a short, factual answer."
        use DSPEx.Signature, "question -> answer"
      end

      # This creates a module with:
      # - A struct: %QASignature{question: nil, answer: nil}
      # - A type: t :: %QASignature{}
      # - Implementations for all `DSPEx.Signature` callbacks.
  """

  @doc "The instructions for the LLM, derived from the module's `@moduledoc`."
  @callback instructions() :: String.t()

  @doc "A list of atoms representing the signature's input fields."
  @callback input_fields() :: list(atom())

  @doc "A list of atoms representing the signature's output fields."
  @callback output_fields() :: list(atom())

  # ... macro implementation ...
end
```

**`lib/dspex/program.ex`**

```elixir
defmodule DSPEx.Program do
  @moduledoc """
  Defines the behaviour for all executable DSPEx modules.

  This contract ensures that any program, from a simple `Predict` to a complex
  `ChainOfThought`, can be composed, evaluated, and optimized in a consistent way.
  """

  @doc """
  The primary execution function for the program.

  Takes the program's own struct and a map of inputs (matching the
  signature's input fields) and returns a `DSPEx.Prediction` struct on success.
  """
  @callback forward(program :: struct(), inputs :: map()) ::
              {:ok, DSPEx.Prediction.t()} | {:error, any()}

  @doc """
  Configures a program with new parameters, such as few-shot demos.

  This is the key mechanism for optimization. It must return a *new*, configured
  program struct, preserving immutability. The `config` map can contain
  any parameters the specific program type understands (e.g., `%{demos: [...]}`).
  """
  @callback configure(program :: struct(), config :: map()) :: struct()
end
```

**`lib/dspex/predict.ex`**

```elixir
defmodule DSPEx.Predict do
  @moduledoc """
  A simple DSPEx.Program for single-turn predictions.

  This module orchestrates the fundamental "format -> call -> parse" pipeline
  for a single LLM interaction. It is the simplest and most common program.

  ## Example

      # Assume QASignature and :my_client are defined
      predictor = %DSPEx.Predict{signature: QASignature, client: :my_client}
      DSPEx.Program.forward(predictor, %{question: "What is Elixir?"})
  """

  @behaviour DSPEx.Program

  # ... struct and implementation ...
end
```

**`lib/dspex/evaluate.ex`**

```elixir
defmodule DSPEx.Evaluate do
  @moduledoc """
  A concurrent evaluation engine for DSPEx programs.

  Leverages `Task.async_stream` to run a program against a large development
  set with a high degree of I/O-bound concurrency, providing significant
  speedups over sequential or traditional thread-pool-based approaches.
  """

  @doc """
  Runs a given program against a development set and computes a metric.

  Returns a tuple: `{:ok, aggregate_score, successes, failures}`.
  Failures from individual program executions are collected and do not
  crash the overall evaluation run.

  ## Options

    * `:num_threads` - The maximum number of concurrent evaluation processes.
      Defaults to twice the number of online schedulers.
    * `:display_progress` - Whether to show a CLI progress bar. Defaults to `true`.
  """
  def run(program, devset, metric_fun, opts \\ []) do
    # ... implementation ...
  end
end
```