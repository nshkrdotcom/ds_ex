Excellent. Let's proceed with the next logical document in our ground-up technical series. We've specified the foundational `Client`; now we must define the core abstractions and data structures that will use it.

This document details the contracts (`behaviours`) and data containers (`structs`) that form the "type system" and public API of the framework. Getting these right is critical for creating a system that is both powerful and easy for developers to reason about.

---

### **Document 2: Core Behaviours and Data Primitives**

**Objective:** To provide a detailed specification for the core abstractions (`Program`, `Signature`, `Adapter`) and data containers (`Prediction`, `Example`) that underpin the entire `DSPEx` framework. These components ensure consistency, composability, and a clean developer experience.

#### **1. `DSPEx.Program` (The Core Behaviour)**

**Purpose:** To establish a uniform interface for all executable modules. Whether it's a simple `Predict` or a complex, multi-step agent (in future versions), it must adhere to this contract. This polymorphism allows any program to be used interchangeably within the `DSPEx.Evaluate` and `DSPEx.Teleprompter` systems.

**File:** `lib/dspex/program.ex`

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
  Allows an optimizer to configure a program with new parameters, such as demos.

  This is key for optimization. It must return a *new*, configured
  program struct, preserving immutability. The `config` map can contain
  any parameters the specific program type understands (e.g., `%{demos: [...]}`).
  """
  @callback configure(program :: struct(), config :: map()) :: struct()

  @doc """
  A helper function to easily execute any module that implements this behaviour.
  This provides a clean, unified entry point for users.
  """
  def forward(program, inputs) do
    # Dynamically dispatch to the correct module's `forward` implementation.
    # This works because the `program` variable is a struct, and we can
    # access its module name via `.__struct__`.
    program.__struct__.forward(program, inputs)
  end
end
```
**Rationale:**
*   **Polymorphism:** This behaviour is the Elixir equivalent of a base class or interface. It's the core of `DSPEx`'s composability, allowing different program types to be treated identically by the evaluation and optimization engines.
*   **Immutability:** The `configure/2` callback is designed for a functional approach. Optimizers don't mutate programs; they create new, improved versions. This avoids side effects and makes the optimization process easier to reason about.
*   **Developer Experience:** The `DSPEx.Program.forward/2` helper provides a clean, unified API for users, abstracting away the dynamic dispatch.

---

#### **2. `DSPEx.Signature` (The Declarative Contract)**

**Purpose:** To provide a compile-time mechanism for defining the I/O contract of an AI program. The `defsignature` macro is the user-facing entry point, ensuring zero runtime cost for parsing or reflection.

**File:** `lib/dspex/signature.ex`

```elixir
defmodule DSPEx.Signature do
  @moduledoc """
  Defines the `@behaviour` and `use` macro for creating DSPEx Signatures.

  A signature declaratively defines the inputs and outputs of a DSPEx program.
  Using this macro at compile-time generates an efficient struct and the necessary
  functions to interact with the framework.
  """

  @callback instructions() :: String.t()
  @callback input_fields() :: list(atom())
  @callback output_fields() :: list(atom())

  defmacro __using__(signature_string) when is_binary(signature_string) do
    quote do
      @behaviour DSPEx.Signature

      # Private function to parse the signature string once at compile time.
      {inputs, outputs} = DSPEx.Signature.Parser.parse(unquote(signature_string))

      # Get the module's docstring for the instructions.
      # This is a convention that makes the signature definition clean.
      instructions =
        @moduledoc ||
          "Given the fields #{inspect(inputs)}, produce the fields #{inspect(outputs)}."

      # 1. Define the struct based on the parsed fields.
      # This struct can be used for creating examples.
      defstruct inputs ++ outputs

      # 2. Define a type for this specific signature struct for static analysis.
      @type t :: %__MODULE__{}

      # 3. Implement the behaviour callbacks with the compile-time values.
      @impl DSPEx.Signature
      def instructions, do: instructions

      @impl DSPEx.Signature
      def input_fields, do: unquote(Macro.escape(inputs))

      @impl DSPEx.Signature
      def output_fields, do: unquote(Macro.escape(outputs))
    end
  end
end

defmodule DSPEx.Signature.Parser do
  @moduledoc false
  # This module is private and only used by the macro at compile time.
  def parse(string) do
    case String.split(string, "->", trim: true) do
      [inputs_str, outputs_str] ->
        inputs = parse_fields(inputs_str)
        outputs = parse_fields(outputs_str)
        {inputs, outputs}
      _ ->
        # This will raise a CompileError, halting compilation with a clear message.
        raise "Invalid DSPEx signature format. Must contain '->'. Example: 'question -> answer'"
    end
  end

  defp parse_fields(str),
    do: String.split(str, ",", trim: true) |> Enum.map(&String.to_atom/1)
end
```
**Rationale:** This implementation fully leverages Elixir's metaprogramming capabilities. All string parsing happens **once, at compile time**. The runtime artifact is a simple, efficient Elixir struct and a module implementing the `DSPEx.Signature` behaviour, with zero overhead. This is a significant advantage over runtime reflection.

---

#### **3. `DSPEx.Example` & `DSPEx.Prediction` (The Standard Data Containers)**

**Purpose:** To provide standardized, structured containers for data flowing into (`Example`) and out of (`Prediction`) any `DSPEx.Program`. This ensures consistency and provides rich context for evaluation and debugging.

**File:** `lib/dspex/example.ex`
```elixir
defmodule DSPEx.Example do
  @moduledoc "A struct representing a single data example for training or evaluation."

  defstruct [
    :data,        # A map holding all key-value data for the example.
    :input_keys   # A MapSet of keys that are considered inputs for a program.
  ]

  @type t :: %__MODULE__{data: map(), input_keys: MapSet.t()}

  def new(data \\ %{}) when is_map(data), do: %__MODULE__{data: data, input_keys: MapSet.new()}

  @doc "Designates which keys from the data should be treated as inputs. Returns a new example."
  def with_inputs(%__MODULE__{} = example, keys), do: %{example | input_keys: MapSet.new(keys)}

  @doc "Returns a map containing only the input fields."
  def inputs(%__MODULE__{data: data, input_keys: input_keys}), do: Map.take(data, MapSet.to_list(input_keys))

  @doc "Returns a map containing only the label fields (i.e., non-inputs)."
  def labels(%__MODULE__{data: data, input_keys: input_keys}), do: Map.drop(data, MapSet.to_list(input_keys))
end
```

**File:** `lib/dspex/prediction.ex`
```elixir
defmodule DSPEx.Prediction do
  @moduledoc "A struct representing the output of a DSPEx Program."
  @behaviour Access

  defstruct [
    :inputs,       # The map of inputs that generated this prediction.
    :outputs,      # A map of the predicted output fields (e.g., %{answer: "..."}).
    :raw_response  # The full, unprocessed response from the LM client for debugging.
  ]

  @type t :: %__MODULE__{inputs: map(), outputs: map(), raw_response: map() | nil}

  # --- Access Behaviour Implementation ---
  # This allows developers to use dot-notation (prediction.answer) to access
  # fields within the `outputs` map, which is a major ergonomic improvement.
  def fetch(%__MODULE__{outputs: outputs}, key), do: Map.fetch(outputs, key)
  def get_and_update(%__MODULE__{} = p, key, fun), do: Map.get_and_update(p.outputs, key, fun) |> then(fn {v, o} -> {v, %{p | outputs: o}} end)
  def pop(%__MODULE__{} = p, key), do: Map.pop(p.outputs, key) |> then(fn {v, o} -> {v, %{p | outputs: o}} end)
end
```
**Rationale:**
*   **Clarity & Flexibility (`Example`):** The `Example` struct makes the role of each data field explicit. The `with_inputs/2` function is crucial, as it allows the same data point to be used in different ways (e.g., a field can be a label for a student program but an input for a teacher program).
*   **Rich Context & Ergonomics (`Prediction`):** Including `inputs` and `raw_response` is vital for debugging and evaluation. The `metric_fun` in `DSPEx.Evaluate` needs the original `example` (which has the inputs and labels) to compare against the predicted `outputs`. Implementing the `Access` behaviour is a key ergonomic decision that makes using the framework much more pleasant.

---

#### **4. `DSPEx.Adapter` (The Translation Layer)**

**Purpose:** To translate between the abstract `DSPEx.Program` world and the concrete API world. It decouples core program logic from the specifics of how to format a prompt for a particular model (e.g., OpenAI Chat vs. Anthropic Messages) or how to parse its response.

**File:** `lib/dspex/adapter.ex`

```elixir
defmodule DSPEx.Adapter do
  @moduledoc "A behaviour for formatting prompts and parsing LM responses."

  @doc "Formats inputs and demos into a list of messages for an LLM client."
  @callback format(signature :: module(), inputs :: map(), demos :: list(DSPEx.Example.t())) ::
              {:ok, list(map())} | {:error, any()}

  @doc "Parses the raw response body from an LLM client into a map of output fields."
  @callback parse(signature :: module(), response_body :: map()) ::
              {:ok, map()} | {:error, any()}
end

# We will also define a default implementation for the MVP.
defmodule DSPEx.Adapter.Chat do
  @moduledoc "Default adapter for chat-based models like OpenAI's."
  @behaviour DSPEx.Adapter

  @impl DSPEx.Adapter
  def format(signature, inputs, demos \\ []) do
    system_message = %{role: "system", content: build_system_prompt(signature)}

    demo_messages =
      Enum.flat_map(demos, fn demo ->
        [
          %{role: "user", content: format_fields(signature.input_fields(), demo.inputs())},
          %{role: "assistant", content: format_fields(signature.output_fields(), demo.labels())}
        ]
      end)

    user_message = %{role: "user", content: format_fields(signature.input_fields(), inputs)}

    messages = [system_message | demo_messages ++ [user_message]]
    {:ok, messages}
  end

  @impl DSPEx.Adapter
  def parse(signature, response_body) do
    # Simple parsing for the MVP. Assumes a '[[ field ]]' format in the response.
    # In a real implementation, this could use Instructor.ex or more robust regex.
    raw_text = get_in(response_body, ["choices", 0, "message", "content"]) || ""

    parsed_fields =
      signature.output_fields()
      |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, acc} ->
        # Regex to find '[[ field ]]' and capture everything until the next '[[' or end of string.
        pattern = ~r/\[\[\s*#{field}\s*\]\]\s*(.*?)(?=\[\[|$)/s
        case Regex.run(pattern, raw_text) do
          [_, content] -> {:cont, {:ok, Map.put(acc, field, String.trim(content))}}
          nil -> {:halt, {:error, "Failed to parse field: #{field}"}}
        end
      end)

    parsed_fields
  end

  # --- Private Helpers for Chat Adapter ---

  defp build_system_prompt(signature) do
    """
    #{signature.instructions()}

    Follow the following format for your response.

    #{format_fields(signature.output_fields(), %{}, placeholder: true)}
    """
  end

  defp format_fields(fields, data, opts \\ []) do
    placeholder? = Keyword.get(opts, :placeholder, false)

    fields
    |> Enum.map_join("\n", fn field ->
      value = if placeholder?, do: "...", else: Map.get(data, field, "")
      "[[ #{field} ]]\n#{value}"
    end)
  end
end
```
**Rationale:** This design defines a clear, decoupled contract for prompt engineering. The `Predict` module doesn't need to know *how* to build a prompt; it just delegates to an adapter. This allows us to easily add new adapters (e.g., a JSON adapter using `Instructor.ex`, or an adapter for a different provider like Anthropic) in the future without changing any of the core `Program` or `Evaluate` logic.