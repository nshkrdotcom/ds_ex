Excellent. Let's create a detailed engineering plan for **Layer 1: The Core Execution Engine**. This plan will serve as the blueprint for the initial implementation, breaking down each component into its required data structures, functions, and interactions. This detailed exploration is the necessary prerequisite before we can write the Product Requirements Document (PRD) for this foundational layer.

---

### **Engineering Plan: `DSPEx` Layer 1 - Core Execution Engine**

**Objective:** To implement the minimum set of components required to define a task, configure an LM client, and execute a single predictive call to a language model. This layer must be stable, testable, and form a solid foundation for all subsequent layers.

---

#### **1. Component: `DSPEx.Settings` (Configuration Management)**

*   **File:** `lib/dspex/settings.ex`
*   **Purpose:** Provide a centralized, safe way to access application-wide configuration. Avoids global mutable state.
*   **Implementation Details:**
    *   A single public function: `get(path, default \\ nil)`.
    *   Example Usage: `DSPEx.Settings.get([:openai, :api_key])`
    *   Internal Logic: This function will wrap `Application.get_env(:dspex, path, default)`. This ensures all `DSPEx` configurations are neatly namespaced under the `:dspex` key in the user's `config/config.exs`.
*   **Testing Strategy:**
    *   Write a unit test that uses `Application.put_env/3` to set mock configuration.
    *   Call `DSPEx.Settings.get/2` and assert that the correct mock value is returned.
    *   Test the default value is returned when the key is not set.

---

#### **2. Component: Core Data Structs (`DSPEx.Primitives`)**

*   **File:** `lib/dspex/primitives/example.ex`, `lib/dspex/primitives/prediction.ex`
*   **Purpose:** Define the fundamental data containers for the framework.

##### **2.1. `DSPEx.Example`**

*   **Data Structure (`defstruct`):**
    *   `fields :: map()`: A map to hold all key-value data (e.g., `%{question: "...", answer: "..."}`).
    *   `input_keys :: MapSet.t()`: A `MapSet` to store the keys that are designated as inputs. Defaults to an empty set.
    *   `dspy_uuid :: String.t()`: A unique identifier for the example, generated on creation.
*   **Public Functions:**
    *   `new(fields \\ %{})`: Constructor that takes a map and generates a UUID.
    *   `with_inputs(example, keys)`: Takes a list of atoms/strings. Returns a *new* `%DSPEx.Example{}` struct with the `input_keys` field updated. This enforces immutability.
    *   `inputs(example)`: Returns a map containing only the key-value pairs marked as inputs.
    *   `labels(example)`: Returns a map containing only the key-value pairs *not* marked as inputs.
*   **Protocols:** Implement the `Access` behaviour to allow easy field access (e.g., `my_example.question`).
*   **Testing Strategy:**
    *   Test `new/1` to ensure fields and UUID are set correctly.
    *   Test `with_inputs/2` to ensure it returns a new struct and does not mutate the original.
    *   Test `inputs/1` and `labels/1` to ensure correct field filtering.

##### **2.2. `DSPEx.Prediction`**

*   **Data Structure (`defstruct`):**
    *   Inherits all fields from `DSPEx.Example`.
    *   `completions :: list(%DSPEx.Example{})`: A list of all generated outputs from the LM when `n > 1`.
    *   `lm_usage :: map()`: A map to hold token usage data, to be used in later layers.
*   **Public Functions:**
    *   `from_completions(completions, signature)`: A constructor that takes a list of raw completion maps from the LM client and the signature, and builds a `%DSPEx.Prediction{}` struct. It will populate the primary fields (e.g., `prediction.answer`) from the *first* completion.
*   **Testing Strategy:**
    *   Test `from_completions/2` with a mock list of completions and a mock signature to ensure the final struct is built correctly.

---

#### **3. Component: `DSPEx.Signature` (Metaprogramming)**

*   **File:** `lib/dspex/signature.ex`
*   **Purpose:** To provide a clean, declarative API for defining a module's I/O contract.

*   **Implementation Details (`defsignature` Macro):**
    *   The `use DSPEx.Signature, "question -> answer"` macro will be the primary user-facing API.
    *   **Macro Logic:**
        1.  It receives the signature string `"question -> answer"`.
        2.  It parses this string to identify input fields (`question`) and output fields (`answer`).
        3.  It captures the calling module's `@moduledoc` attribute.
        4.  It injects the following code (AST) into the calling module:
            ```elixir
            # Injected into the module that `use`s DSPEx.Signature
            defstruct [:question, :answer] # Based on parsed fields
            @type t :: %__MODULE__{question: String.t(), answer: String.t()} # Initial support for String only
            @behaviour DSPEx.Signature

            @impl DSPEx.Signature
            def instructions, do: "The module's @moduledoc content"

            @impl DSPEx.Signature
            def input_fields, do: [:question]

            @impl DSPEx.Signature
            def output_fields, do: [:answer]
            ```
    *   A companion `DSPEx.Signature` `behaviour` will be defined to formalize the callbacks (`instructions/0`, `input_fields/0`, `output_fields/0`).
*   **Testing Strategy:**
    *   Define a test module `TestSignature` that `use DSPEx.Signature, "in1, in2 -> out1"`.
    *   Write compile-time tests using `assert_raise` to check for invalid signature strings.
    *   Write runtime tests to assert that `%TestSignature{}` exists and that calls to `TestSignature.instructions()` and `TestSignature.input_fields()` return the expected values.

---

#### **4. Component: `DSPEx.Program` (Core Behaviour)**

*   **File:** `lib/dspex/program.ex`
*   **Purpose:** To establish a uniform interface for all executable modules.
*   **Implementation Details:**
    *   A simple `behaviour` with one callback: `@callback forward(module :: struct(), inputs :: map()) :: %DSPEx.Prediction{}`.
*   **Testing Strategy:**
    *   No direct tests needed for the behaviour itself. Its correctness will be tested via modules that implement it, like `DSPEx.Predict`.

---

#### **5. Component: Basic `DSPEx.Client.LM` (`GenServer`)**

*   **File:** `lib/dspex/client/lm.ex`
*   **Purpose:** To manage and execute requests to a Language Model API.
*   **Implementation Details:**
    *   **`GenServer` State:** `defstruct [:provider, :model, :config]` where `config` is a map holding the API key, etc.
    *   **Public API:**
        *   `start_link(opts)`: Standard `GenServer` start function. It will be called by the application's supervisor. `opts` will include `[name: MyApp.MyClient, provider: :openai, model: "gpt-4o-mini"]`.
        *   `request(client_name_or_pid, messages, config)`: The main entry point. This function will `GenServer.cast/2` the request to the client process.
    *   **`GenServer` Logic (`handle_cast`):**
        1.  Receives the request tuple `{:request, caller_pid, messages, config}`.
        2.  Spawns a `Task` to run the private `do_http_request/2` function.
        3.  The `Task` will send its result (or failure) directly back to the `caller_pid`. This avoids the `GenServer` becoming a bottleneck for responses.
    *   **Private `do_http_request/2` function:**
        1.  Uses `Tesla` to build and execute the HTTP POST request to the provider's endpoint.
        2.  The request body will be a JSON-encoded map matching the provider's schema (e.g., OpenAI's chat completions API).
        3.  Upon success, it parses the JSON response and returns `{:ok, completion_map}`.
        4.  Upon failure, it lets the `Tesla` exception crash the `Task`.
*   **Testing Strategy:**
    *   Use a mock HTTP client library (like `Tesla.Mock`) to avoid making real API calls.
    *   Start the `LM` `GenServer` within the test suite's supervision tree.
    *   Call `request/3` and assert that the mock HTTP endpoint was called with the correct payload.
    *   Test that the `caller_pid` receives the correct `{:ok, ...}` message.

---

#### **6. Component: `DSPEx.Predict` (The First Program)**

*   **File:** `lib/dspex/predict.ex`
*   **Purpose:** The simplest possible program module. It ties all other Layer 1 components together.
*   **Implementation Details:**
    *   **Data Structure:** `defstruct [:signature, :client]`
    *   **`@behaviour DSPEx.Program`**
    *   **`forward/2` Implementation:**
        1.  Takes the `program` struct and `inputs` map.
        2.  Retrieves the signature from `program.signature`.
        3.  Constructs the `messages` list for the LM API call (initially, just a simple user role message).
        4.  Calls `DSPEx.Client.LM.request(program.client, messages, %{})`, passing its own `self()` as the `caller_pid`.
        5.  Enters a `receive` block to wait for the response from the `Task` spawned by the LM client.
        6.  Once the `{:ok, completion_map}` is received, it calls `DSPEx.Prediction.from_completions/2` to format the final result.
        7.  Returns the `%DSPEx.Prediction{}`.
*   **Testing Strategy:**
    *   This is the final integration test for Layer 1.
    *   The test will instantiate a `%DSPEx.Predict{}` module with a mock signature and a mock `LM` client `GenServer`.
    *   The mock client will be configured to send a pre-defined successful response.
    *   Call `DSPEx.Program.forward/2` and assert that the final prediction struct has the correct fields and values based on the mock response.

By completing these six components, we will have a fully functional, albeit minimal, version of `DSPEx`. Every part is designed with OTP principles in mind, setting a robust precedent for all future layers.
