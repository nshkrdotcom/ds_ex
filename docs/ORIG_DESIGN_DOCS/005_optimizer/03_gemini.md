Excellent. Let's proceed with the final document in the ground-up technical series for the `DSPEx` MVP. We've specified the core execution modules; now we need to define the underlying **Behaviours and Data Primitives** that make them work together cohesively.

This document details the contracts (`behaviours`) and data structures (`structs`) that form the "type system" and public API of the framework. Getting these right is critical for creating a system that is both powerful and easy for developers to reason about.

---

### **Document 5: Supporting Primitives & Behaviours (MVP)**

**Objective:** To provide a detailed specification for the core abstractions (`Program`, `Teleprompter`) and data containers (`Prediction`, `Example`) that underpin the entire `DSPEx` framework. These components ensure consistency, composability, and a clean developer experience.

#### **1. `DSPEx.Program` (The Core Behaviour)**

**Purpose:** To establish a uniform interface for all executable modules. Whether it's a simple `Predict` or a complex, multi-step `ReAct` agent (in future layers), it must adhere to this contract. This allows any program to be used interchangeably within the `DSPEx.Evaluate` and `DSPEx.Teleprompter` systems.

**File:** `lib/dspex/program.ex`

```elixir
defmodule DSPEx.Program do
  @moduledoc """
  Defines the behaviour for all executable DSPEx modules.

  This contract ensures that any program can be composed, evaluated, and
  optimized in a consistent way.
  """

  @doc """
  The primary execution function for the program.

  Takes the program's own struct and a map of inputs (matching the
  signature's input fields) and returns a `DSPEx.Prediction` struct.
  """
  @callback forward(program :: struct(), inputs :: map()) ::
              {:ok, DSPEx.Prediction.t()} | {:error, any()}

  @doc """
  Allows an optimizer to configure a program with new parameters.

  This is key for optimization. It must return a *new*, configured
  program struct, preserving immutability.
  """
  @callback configure(program :: struct(), config :: map()) :: struct()

  @doc """
  A helper function to easily execute any module that implements this behaviour.
  """
  def forward(program, inputs) do
    # Dynamically dispatch to the correct module's `forward` implementation.
    program.__struct__.forward(program, inputs)
  end
end
```
**Rationale:**
*   **Polymorphism:** The `behaviour` allows different program types to be treated identically by the evaluation and optimization engines.
*   **Immutability:** The `configure/2` callback is designed for a functional approach. Optimizers don't mutate programs; they create new, improved versions.
*   **Developer Experience:** The `DSPEx.Program.forward/2` helper provides a clean, unified entry point for users, abstracting away the dynamic dispatch.

---

#### **2. `DSPEx.Prediction` (The Standard Output)**

**Purpose:** To provide a standardized, structured container for the output of any `Program.forward/2` call. It holds not just the final answer, but also the context of how that answer was generated.

**File:** `lib/dspex/prediction.ex`

```elixir
defmodule DSPEx.Prediction do
  @moduledoc "A struct representing the output of a DSPEx Program."

  # Implements the Access behaviour to allow dot-notation access to output fields.
  # e.g., `my_prediction.answer` instead of `my_prediction.outputs[:answer]`
  @behaviour Access

  defstruct [
    :inputs,       # The map of inputs that generated this prediction.
    :outputs,      # A map of the predicted output fields (e.g., %{answer: "..."}).
    :raw_response  # The full, unprocessed response from the LM client for debugging.
  ]

  @type t :: %__MODULE__{
    inputs: map(),
    outputs: map(),
    raw_response: map() | nil
  }

  @doc "Creates a new Prediction struct."
  def new(fields \\ %{}) do
    struct(__MODULE__, fields)
  end

  # --- Access Behaviour Implementation ---
  @impl Access
  def fetch(%__MODULE__{outputs: outputs}, key), do: Map.fetch(outputs, key)

  @impl Access
  def get_and_update(%__MODULE__{} = prediction, key, fun) do
    {value, new_outputs} = Map.get_and_update(prediction.outputs, key, fun)
    {value, %{prediction | outputs: new_outputs}}
  end

  @impl Access
  def pop(%__MODULE__{} = prediction, key) do
    {value, new_outputs} = Map.pop(prediction.outputs, key)
    {value, %{prediction | outputs: new_outputs}}
  end
end
```
**Rationale:**
*   **Standardization:** Every program returns the same shape of data, making composition and evaluation predictable.
*   **Rich Context:** Including `inputs` and `raw_response` is crucial for debugging, evaluation, and tracing. The `metric_fun` in `DSPEx.Evaluate` needs access to the original inputs to compare against the predicted outputs.
*   **Ergonomics:** Implementing the `Access` behaviour provides a huge quality-of-life improvement for developers, making the prediction struct feel like a simple, easy-to-use map.

---

#### **3. `DSPEx.Example` (The Standard Input)**

**Purpose:** To provide a standardized data container for examples in a `trainset` or `devset`. It cleanly separates input fields from ground-truth label fields.

**File:** `lib/dspex/example.ex`

```elixir
defmodule DSPEx.Example do
  @moduledoc "A struct representing a single data example, with designated inputs and labels."

  defstruct [
    :data,        # A map holding all key-value data for the example.
    :input_keys   # A MapSet of keys that are considered inputs.
  ]

  @type t :: %__MODULE__{data: map(), input_keys: MapSet.t()}

  @doc "Creates a new Example from a map of data."
  def new(data \\ %{}) when is_map(data) do
    %__MODULE__{data: data, input_keys: MapSet.new()}
  end

  @doc """
  Designates which keys from the data should be treated as inputs.

  Returns a *new* example struct.
  """
  def with_inputs(%__MODULE__{} = example, keys) do
    %{example | input_keys: MapSet.new(keys)}
  end

  @doc "Returns a map containing only the input fields."
  def inputs(%__MODULE__{data: data, input_keys: input_keys}) do
    Map.take(data, MapSet.to_list(input_keys))
  end

  @doc "Returns a map containing only the label fields (i.e., non-inputs)."
  def labels(%__MODULE__{data: data, input_keys: input_keys}) do
    Map.drop(data, MapSet.to_list(input_keys))
  end
end
```
**Rationale:**
*   **Clarity:** This structure makes the role of each field explicit. There is no ambiguity about which data is for prompting (inputs) and which is for evaluation (labels).
*   **Flexibility:** The same `Example` can be used in different ways. For instance, in a `student -> teacher` optimization, the `answer` field might be an *input* for the teacher program but a *label* for the student. The `with_inputs/2` function allows for this dynamic designation.
*   **Efficiency:** Using a `MapSet` for `input_keys` provides efficient lookups when partitioning the data into inputs and labels.

---

#### **4. `DSPEx.Teleprompter` (The Optimizer Contract)**

**Purpose:** To define a standard interface for all optimizers. This allows the system to treat `BootstrapFewShot`, `MIPROv2`, and other future optimizers as interchangeable "compilers."

**File:** `lib/dspex/teleprompter.ex`

```elixir
defmodule DSPEx.Teleprompter do
  @moduledoc "A behaviour for all DSPEx optimizers (aka 'teleprompters')."

  @doc """
  The main entry point for an optimizer.

  It takes a program to be optimized (the "student"), a training set,
  a metric function, and options. It returns a new, optimized version
  of the student program.
  """
  @callback compile(
              student :: DSPEx.Program.t(),
              trainset :: list(DSPEx.Example.t()),
              metric_fun :: (DSPEx.Example.t(), DSPEx.Prediction.t() -> 0.0..1.0),
              opts :: keyword()
            ) :: {:ok, DSPEx.Program.t()} | {:error, any()}
end
```
**Rationale:**
*   **Standard Interface:** This `behaviour` creates a clear contract for what an optimizer does: it takes a program and returns a better program.
*   **Decoupling:** High-level application code can invoke an optimizer without needing to know the specific details of its algorithm (e.g., whether it's doing few-shot learning or instruction tuning).

---

### **Conclusion of MVP Specification**

With these four supporting components specified, the MVP is fully defined. We have:
1.  A way to **define a task** (`Signature`).
2.  A way to **execute the task** (`Program` and `Predict`).
3.  Standard formats for **input and output** (`Example` and `Prediction`).
4.  A way to **translate** between the task and the LM (`Adapter`).
5.  A way to **evaluate** the task's performance (`Evaluate`).
6.  A way to **optimize** the task (`Teleprompter` and `BootstrapFewShot`).

This completes a fully-closed loop, delivering on the core promise of `DSPy` in a robust, concurrent, and idiomatic Elixir package. This is a solid foundation upon which all more advanced features can be built.
