Of course. We are making excellent progress. Having defined the foundational client and the abstract primitives, we can now specify the modules that bring them to life: the core execution and evaluation engines.

This document details `DSPEx.Predict`, our first concrete program, and `DSPEx.Evaluate`, the concurrent engine that will run it and any other program we build.

---

### **Document 3: Core Execution & Evaluation Engine**

**Objective:** To provide a detailed technical specification for `DSPEx.Predict`, the primary module for single-turn inference, and `DSPEx.Evaluate`, the concurrent engine for measuring program performance. This document connects the abstract behaviours and data structures from Document 2 to the resilient client from Document 1.

#### **1. `DSPEx.Predict` (The Core Executor)**

**Purpose:** The simplest and most fundamental `DSPEx.Program`. `Predict` orchestrates the "format -> call -> parse" pipeline for a single LLM interaction. It is completely stateless in its execution, relying on the `Client` for network operations and the `Adapter` for prompt engineering.

**File:** `lib/dspex/predict.ex`

```elixir
defmodule DSPEx.Predict do
  @moduledoc """
  A simple DSPEx.Program for single-turn predictions.

  This module orchestrates the process of formatting a request using an adapter,
  sending it to a client, and parsing the response.
  """

  @behaviour DSPEx.Program

  alias DSPEx.{Client, Prediction, Adapter.Chat}

  defstruct [
    :signature,
    :client,
    adapter: Chat, # The adapter module, defaults to Chat
    demos: []      # A list of DSPEx.Example structs for few-shot demonstrations
  ]

  @type t :: %__MODULE__{
    signature: module(),
    client: atom(),
    adapter: module(),
    demos: list(DSPEx.Example.t())
  }

  @impl DSPEx.Program
  def forward(%__MODULE__{} = program, inputs) do
    with {:ok, messages} <- program.adapter.format(program.signature, inputs, program.demos),
         {:ok, response_body} <- Client.request(program.client, messages),
         {:ok, parsed_outputs} <- program.adapter.parse(program.signature, response_body) do

      # On the happy path, construct the final, structured prediction object.
      prediction = %Prediction{
        inputs: inputs,
        outputs: parsed_outputs,
        raw_response: response_body
      }
      {:ok, prediction}
    else
      # Any error from the adapter or client pipeline steps is propagated.
      # The error will be a tuple like {:error, reason}, which we return directly.
      error -> error
    end
  end

  @impl DSPEx.Program
  def configure(%__MODULE__{} = program, config) when is_map(config) do
    # Returns a *new* struct with the updated values from the config map.
    # This is how optimizers will inject new demos into the program.
    # Example: configure(program, %{demos: new_demos_list})
    Map.merge(program, config)
  end
end
```
**Rationale:**
*   **Clean Orchestration:** The use of `with` creates a clean, readable "happy path" for the execution flow. The logic is purely orchestrational, making it easy to understand and test.
*   **Decoupling:** `Predict` is completely decoupled from the specifics of prompt formatting (handled by the `Adapter`) and API resilience (handled by the `Client`). This is a cornerstone of the framework's design, allowing for easy extension and maintenance.
*   **Immutability:** The `configure/2` function adheres to functional principles by returning a new, modified struct rather than mutating the program in place. This makes the state of the system predictable, especially during complex optimization runs.

---

#### **2. `DSPEx.Evaluate` (The Concurrent Engine)**

**Purpose:** To provide a massively concurrent and fault-tolerant engine for evaluating any `DSPEx.Program`. It leverages `Task.async_stream` to run a program against a large development set, achieving a level of I/O-bound concurrency that is fundamentally more scalable and efficient than thread-based solutions in other languages.

**File:** `lib/dspex/evaluate.ex`

```elixir
defmodule DSPEx.Evaluate do
  @moduledoc """
  A concurrent evaluation engine for DSPEx programs.
  """

  alias DSPEx.Program

  @default_opts [
    num_threads: System.schedulers_online() * 2,
    display_progress: true
  ]

  @doc """
  Runs a given program against a development set and computes a metric.

  Returns a tuple: `{:ok, aggregate_score, successes, failures}`.

  ## Options
    * `:num_threads` - The maximum number of concurrent processes. Defaults to
      twice the number of online schedulers.
    * `:display_progress` - Whether to show a progress bar. Defaults to `true`.
  """
  def run(program, devset, metric_fun, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    num_threads = opts[:num_threads]
    pbar = if opts[:display_progress], do: pbar(devset), else: nil

    results =
      devset
      |> Task.async_stream(&evaluate_example(&1, program, metric_fun),
        max_concurrency: num_threads,
        on_timeout: :kill_task
      )
      |> Stream.map(fn {:ok, result} ->
        if pbar, do: ProgressBar.tick(pbar)
        result
      end)
      |> Enum.to_list()

    if pbar, do: ProgressBar.done(pbar)

    process_results(results)
  end

  # This is the private function executed by each concurrent process.
  defp evaluate_example(example, program, metric_fun) do
    case Program.forward(program, example.inputs) do
      {:ok, prediction} ->
        # The metric function compares the original example (with labels)
        # to the prediction and returns a score (typically 0.0 to 1.0).
        score = metric_fun.(example, prediction)
        {:ok, {example, prediction, score}}

      {:error, reason} ->
        # A single failure does not stop the stream. It is returned as an error tuple.
        {:error, {example, reason}}
    end
  end

  # Processes the collected results from all tasks.
  defp process_results(results) do
    {successes, failures} = Enum.partition(results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)

    successes = Enum.map(successes, fn {:ok, res} -> res end)
    failures = Enum.map(failures, fn {:error, res} -> res end)

    # Calculate the aggregate score (e.g., average).
    total_score =
      successes
      |> Enum.map(fn {_ex, _pred, score} -> score end)
      |> Enum.sum()

    aggregate_score =
      if Enum.empty?(successes),
        do: 0.0,
        else: total_score / length(successes)

    {:ok, aggregate_score, successes, failures}
  end

  defp pbar(devset) do
    ProgressBar.new(
      total: Enum.count(devset),
      title: "Evaluating",
      format: ":title [:bar] :percent/:total | Rate: :rate/s | ETA: :eta"
    )
  end
end
```
**Rationale:**
*   **Scalability & Fault Tolerance:** `Task.async_stream` is the perfect tool for this job. Each evaluation is an isolated process. If one API call to an LLM hangs or returns a 500 error, that single task will fail and be reported as an error, but it will *not* crash the entire evaluation run. This makes the evaluation engine dramatically more robust than traditional sequential or thread-pool-based approaches.
*   **Efficiency:** For I/O-bound workloads like hitting an LLM API, Elixir's lightweight processes allow for a very high degree of concurrency (`System.schedulers_online() * 2` is a conservative starting point) with minimal overhead, leading to faster evaluation cycles.
*   **Clarity:** The code clearly separates the concerns of task orchestration (`run/4`), individual task work (`evaluate_example/3`), and result aggregation (`process_results/1`), making it easy to maintain and understand.