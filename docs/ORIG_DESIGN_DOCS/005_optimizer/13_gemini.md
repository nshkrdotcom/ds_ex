Excellent. Having specified the execution and evaluation layers, we've reached the top of the MVP hierarchy. The final step is to define the optimizer that uses these underlying components to improve a program.

This document specifies the `Teleprompter` behaviour—the generic contract for all optimizers—and provides the full implementation for our first and most crucial optimizer, `BootstrapFewShot`.

---

### **Document 4: The First Optimizer (`BootstrapFewShot`)**

**Objective:** To provide a detailed technical specification for the optimization layer of the `DSPEx` MVP. This includes the generic `Teleprompter` behaviour and the concrete `BootstrapFewShot` module, which closes the `Predict -> Evaluate -> Optimize` loop.

#### **1. `DSPEx.Teleprompter` (The Optimizer Contract)**

**Purpose:** To define a standard interface for all optimizers. This allows the system to treat `BootstrapFewShot`, `MIPRO`, and other future optimizers as interchangeable "compilers." A user can swap out optimization strategies with minimal code changes, focusing on results rather than implementation details.

**File:** `lib/dspex/teleprompter.ex`

```elixir
defmodule DSPEx.Teleprompter do
  @moduledoc """
  A behaviour for all DSPEx optimizers (aka 'teleprompters').

  An optimizer's job is to take a program and a dataset and produce a new,
  more performant version of that program.
  """

  alias DSPEx.{Example, Prediction, Program}

  @doc """
  The main entry point for an optimizer.

  It takes a program to be optimized (the "student"), an optional "teacher"
  program, a training set, and a metric function. It returns a new,
  optimized version of the student program.
  """
  @callback compile(
              student :: Program.t(),
              teacher :: Program.t(),
              trainset :: list(Example.t()),
              metric_fun :: (Example.t(), Prediction.t() -> float()),
              opts :: keyword()
            ) :: {:ok, Program.t()} | {:error, any()}
end
```
**Rationale:**
*   **Standard Interface:** This `behaviour` creates a clear, predictable contract for what every optimizer does: it takes a program and returns a better program.
*   **Decoupling:** High-level application code can invoke an optimizer without needing to know the specific details of its algorithm (e.g., whether it's doing few-shot learning, instruction tuning, or something else). This promotes modularity and makes the system easier to extend.

---

#### **2. `DSPEx.Teleprompter.BootstrapFewShot` (The First Optimizer)**

**Purpose:** To implement the `BootstrapFewShot` algorithm. This optimizer uses a "teacher" program (which can be the "student" program itself in a zero-shot configuration) to generate high-quality few-shot demonstrations. It runs the teacher on a training set, filters for the most successful examples according to a metric, and then uses those successful examples as demonstrations to configure a new, improved student program.

**File:** `lib/dspex/teleprompt/bootstrap_fewshot.ex`

```elixir
defmodule DSPEx.Teleprompter.BootstrapFewShot do
  @moduledoc """
  A Teleprompter that generates few-shot examples by bootstrapping.

  It runs a `teacher` program on a `trainset` to find high-quality examples,
  which are then used as demonstrations for the `student` program.
  """
  @behaviour DSPEx.Teleprompter

  use GenServer

  alias DSPEx.{Evaluate, Example, Prediction, Program}

  @default_opts [
    max_demos: 4
  ]

  # =================================================================
  # Public API
  # =================================================================

  @impl DSPEx.Teleprompter
  def compile(student, teacher, trainset, metric_fun, opts \\ []) do
    # For the MVP, the public API is a synchronous, blocking call.
    # It starts a GenServer to manage the state of the compilation process,
    # but the caller waits for the result. This simplifies the user experience.
    state = %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fun: metric_fun,
      opts: Keyword.merge(@default_opts, opts)
    }

    # Start the GenServer and make a blocking call with an infinite timeout.
    # The timeout is handled by the underlying HTTP client, not here.
    {:ok, pid} = GenServer.start_link(__MODULE__, state, name: __MODULE__)
    GenServer.call(pid, :compile, :infinity)
  end

  # =================================================================
  # GenServer Callbacks
  # =================================================================

  @impl true
  def init(state) do
    # The state is passed directly from the compile function.
    {:ok, state}
  end

  @impl true
  def handle_call(:compile, _from, state) do
    # Deconstruct the state for the compilation logic.
    %{
      student: student,
      teacher: teacher,
      trainset: trainset,
      metric_fun: metric_fun,
      opts: opts
    } = state

    max_demos = opts[:max_demos]

    # --- Step 1: Generate Traces ---
    # We run the teacher program on the trainset.
    # The "metric" we pass to Evaluate here is a special function that doesn't
    # calculate a score, but instead just returns the full prediction object.
    # This gives us the `prediction` for each example, which we need for the real metric.
    {:ok, _score, teacher_traces, _failures} =
      Evaluate.run(teacher, trainset, &elem(&1, 1))

    # --- Step 2: Filter for High-Quality Demonstrations ---
    # Now, we apply the *real* metric to the traces we generated.
    # A successful trace is one where the metric passes (e.g., returns 1.0).
    high_quality_traces =
      Enum.filter(teacher_traces, fn {example, prediction, _score} ->
        # The score here is the prediction from the line above. We ignore it.
        # We now apply the user-provided metric function.
        metric_fun.(example, prediction) >= 1.0
      end)

    # --- Step 3: Create Demonstrations from Successful Traces ---
    # The `example` from a successful trace is a perfect demonstration,
    # as it contains both the inputs and the ground-truth labels.
    demos =
      Enum.map(high_quality_traces, fn {example, _prediction, _score} ->
        example
      end)

    # --- Step 4: Select Final Demonstrations ---
    # For the MVP, we'll just take a random sample. More advanced strategies
    # (e.g., maximizing diversity) can be added later.
    final_demos = Enum.take_random(demos, min(max_demos, Enum.count(demos)))

    # --- Step 5: Configure and Return the Optimized Student ---
    # We use the `configure` callback from the Program behaviour to create a
    # new student program configured with the demos we just discovered.
    optimized_student = Program.configure(student, %{demos: final_demos})

    {:reply, {:ok, optimized_student}, state}
  end
end
```
**Rationale:**
*   **Stateful but Synchronous:** Using a `GenServer` provides a robust, stateful container for the optimization process, which can become complex. However, exposing the `compile` function as a simple, blocking call makes the public API much easier to use for the MVP. Asynchronous compilation can be added later as an option.
*   **Leveraging `Evaluate`:** This module is a prime example of component reuse. It delegates the most computationally expensive part—running the teacher program against the entire training set—to the highly concurrent `DSPEx.Evaluate` engine, ensuring the process is as fast and efficient as possible.
*   **Closing the Loop:** This implementation clearly demonstrates the full `DSPEx` optimization loop:
    1.  It takes a `student` `Program`.
    2.  It uses `Evaluate` to run a `teacher` `Program`.
    3.  It uses a `metric_fun` and `Example` structs to identify good demonstrations.
    4.  It creates a new, optimized `student` `Program` by using `configure/2` to inject the discovered demos.

This completes the core `Predict -> Evaluate -> Optimize` loop, delivering on the promise of `DSPy` in a robust, concurrent, and idiomatic Elixir package. This set of specifications provides a solid and complete foundation for building the MVP.