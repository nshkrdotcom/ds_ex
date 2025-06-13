Excellent. Let's continue by creating the next logical document in our ground-up technical series. We've defined the high-level charter and architectural diagrams. Now, we will create the **Core Component Specification**.

This document will flesh out the code skeletons from the previous discussion. It provides a detailed, implementation-focused view of the key modules, their public APIs, their internal logic, and how they interact. This serves as a direct blueprint for the engineering team building the MVP.

---

### **Document 4: Core Component Specification (MVP)**

**Objective:** To provide a detailed technical specification for the primary components of the `DSPEx` MVP: `Signature`, `Adapter`, `Predict`, and the first `Teleprompter`. This document defines their function signatures, data structures, and core logic.

#### **1. `DSPEx.Signature` - The Declarative Contract**

**Purpose:** To provide a compile-time mechanism for defining the I/O contract of an AI program. The `defsignature` macro is the user-facing entry point.

**File:** `lib/dspex/signature.ex`

```elixir
defmodule DSPEx.Signature do
  @moduledoc """
  Defines the `@behaviour` and `use` macro for creating DSPEx Signatures.
  """

  @callback instructions() :: String.t()
  @callback input_fields() :: list(atom)
  @callback output_fields() :: list(atom)

  defmacro __using__(signature_string) when is_binary(signature_string) do
    quote do
      @behaviour DSPEx.Signature

      # Private function to parse the signature string at compile time.
      {inputs, outputs} = DSPEx.Signature.Parser.parse(unquote(signature_string))
      # Get the module's docstring for the instructions.
      instructions = @moduledoc || "No instructions provided."

      # 1. Define the struct based on the parsed fields.
      defstruct inputs ++ outputs

      # 2. Define a type for this specific signature struct.
      @type t :: %__MODULE__{}

      # 3. Implement the behaviour callbacks.
      @impl DSPEx.Signature
      def instructions, do: instructions

      @impl DSPEx.Signature
      def input_fields, do: unquote(inputs)

      @impl DSPEx.Signature
      def output_fields, do: unquote(outputs)
    end
  end
end

defmodule DSPEx.Signature.Parser do
  @moduledoc false
  def parse(string) do
    case String.split(string, "->", trim: true) do
      [inputs_str, outputs_str] ->
        inputs = parse_fields(inputs_str)
        outputs = parse_fields(outputs_str)
        {inputs, outputs}
      _ ->
        raise CompileError, description: "Invalid DSPEx signature format. Must contain '->'.", file: __ENV__.file, line: __ENV__.line
    end
  end

  defp parse_fields(str), do: String.split(str, ",", trim: true) |> Enum.map(&String.to_atom/1)
end
```
**Rationale:** This implementation ensures that all string parsing happens **once, at compile time**. The runtime artifact is a simple, efficient Elixir struct and module, with zero overhead. The `behaviour` provides a standard interface for other parts of the system (like the `Adapter`) to query the signature's contract.

---

#### **2. `DSPEx.Adapter` - The Translation Layer**

**Purpose:** To translate between the abstract `DSPEx.Signature` and the concrete `messages` format required by an LM client, and to parse the raw LM response back into structured data.

**File:** `lib/dspex/adapter.ex`

```elixir
defmodule DSPEx.Adapter do
  @moduledoc "A behaviour for formatting prompts and parsing responses."

  @callback format(signature :: module(), inputs :: map(), demos :: list()) :: {:ok, list(map())} | {:error, any()}
  @callback parse(signature :: module(), response_body :: map()) :: {:ok, map()} | {:error, any()}
end

defmodule DSPEx.Adapter.Chat do
  @moduledoc "Default adapter for chat-based models."
  @behaviour DSPEx.Adapter

  @impl DSPEx.Adapter
  def format(signature, inputs, demos \\ []) do
    system_message = %{role: "system", content: signature.instructions()}

    demo_messages = Enum.flat_map(demos, fn demo ->
      [
        %{role: "user", content: format_fields(signature.input_fields(), demo.inputs)},
        %{role: "assistant", content: format_fields(signature.output_fields(), demo.outputs)}
      ]
    end)

    user_message = %{role: "user", content: format_fields(signature.input_fields(), inputs)}

    messages = [system_message | (demo_messages ++ [user_message])]
    {:ok, messages}
  end

  @impl DSPEx.Adapter
  def parse(signature, response_body) do
    # Assuming OpenAI-like response structure
    raw_text = get_in(response_body, ["choices", 0, "message", "content"])

    # This is a simple regex-based parser for the '[[ field ]]' format.
    # In a more advanced version, this would be more robust or use a library
    # like Instructor.ex for JSON-based parsing.
    parsed_fields =
      signature.output_fields()
      |> Enum.reduce(%{}, fn field, acc ->
        pattern = ~r/\[\[\s*#{field}\s*\]\]\s*(.*)/s
        case Regex.run(pattern, raw_text, capture: :all_but_first) do
          [content] -> Map.put(acc, field, String.trim(content))
          nil -> acc
        end
      end)
    {:ok, parsed_fields}
  end

  defp format_fields(fields, data) do
    fields
    |> Enum.map_join("\n", fn field ->
      "[[ #{field} ]]\n#{Map.get(data, field)}"
    end)
  end
end
```
**Rationale:** This defines a clear, decoupled contract for prompt formatting. The `Predict` module doesn't need to know *how* to build a prompt; it just delegates to an adapter. This allows us to easily add new adapters (e.g., a JSON adapter using `Instructor.ex`) in the future without changing the core `Predict` logic.

---

#### **3. `DSPEx.Predict` - The Core Executor**

**Purpose:** The simplest program module. Orchestrates the format -> call -> parse pipeline for a single LM interaction.

**File:** `lib/dspex/predict.ex`

```elixir
defmodule DSPEx.Predict do
  @behaviour DSPEx.Program
  defstruct [:signature, :client, adapter: DSPEx.Adapter.Chat, demos: []]

  @impl DSPEx.Program
  def forward(%__MODULE__{} = program, inputs) do
    with {:ok, messages} <- program.adapter.format(program.signature, inputs, program.demos),
         {:ok, response_body} <- DSPEx.Client.request(program.client, messages),
         {:ok, parsed_outputs} <- program.adapter.parse(program.signature, response_body) do

      # Construct the final, structured prediction object
      {:ok, %DSPEx.Prediction{
        inputs: inputs,
        outputs: parsed_outputs,
        raw_response: response_body
      }}
    else
      # Any error from the pipeline steps is propagated.
      {:error, reason} -> {:error, reason}
    end
  end
end
```
**Rationale:** The use of `with` creates a clean, readable "happy path" for the execution flow. The logic is purely orchestrational. It is completely decoupled from the specifics of prompt formatting (handled by the `Adapter`) and API resilience (handled by the `Client`).

---

#### **4. `DSPEx.Teleprompter.BootstrapFewShot` - The First Optimizer**

**Purpose:** To implement the `BootstrapFewShot` algorithm, which uses an LLM to generate high-quality few-shot demonstrations for a program.

**File:** `lib/dspex/teleprompt/bootstrap_fewshot.ex`

```elixir
defmodule DSPEx.Teleprompter.BootstrapFewShot do
  @behaviour DSPEx.Teleprompter
  use GenServer

  # Public API
  def compile(student, teacher, trainset, metric_fun) do
    # This is a synchronous call for simplicity in the MVP.
    # It starts a GenServer to manage the state of the compilation.
    {:ok, pid} = GenServer.start_link(__MODULE__, %{})
    GenServer.call(pid, {:compile, student, teacher, trainset, metric_fun}, :infinity)
  end

  # GenServer Implementation
  def init(_), do: {:ok, %{}}

  def handle_call({:compile, student, teacher, trainset, metric_fun}, _from, state) do
    # 1. Generate traces using the teacher program on the trainset.
    # The metric here is just the identity, so we get the full trace back.
    {:ok, traces} = DSPEx.Evaluate.run(teacher, trainset, &(&1), display_progress: true)

    # 2. Filter for high-quality traces.
    successful_traces = Enum.filter(traces, fn
      # A successful trace is one where the real metric passes.
      {:ok, {_example, prediction, _score}} -> metric_fun.(_example, prediction) == 1.0
      _ -> false
    end)

    # 3. Create demonstrations from the successful traces.
    demos = Enum.map(successful_traces, fn {:ok, {example, _prediction, _score}} ->
      # An Example struct can contain both inputs and labels.
      example
    end)

    # 4. For the MVP, we'll just take a sample. More advanced strategies can be added later.
    final_demos = Enum.take_random(demos, min(4, Enum.count(demos)))

    # 5. Return a *new* student program configured with the generated demos.
    optimized_student = %{student | demos: final_demos}

    {:reply, {:ok, optimized_student}, state}
  end
end
```
**Rationale:** This design clearly separates the optimization logic into discrete, testable steps. It leverages the massively concurrent `DSPEx.Evaluate` engine to perform the most expensive part (trace generation) efficiently. The final output is an immutable, optimized program artifact, which is a core tenet of functional programming and the `DSPEx` design. This completes the core `Predict -> Evaluate -> Optimize` loop.
