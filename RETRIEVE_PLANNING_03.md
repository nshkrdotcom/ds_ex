Of course. Here is a detailed, actionable build-out plan for **Part 1: The Foundational Retrieval Framework**.

This phase focuses on creating the core abstractions (`DSPEx.Retrieve`, `DSPEx.RetrieverModel`, and `DSPEx.Services.RetrieverManager`). These components establish the standardized contract and workflow for retrieval within `dspex` without implementing a specific database connector yet.

---

### **Part 1: Building the Retrieval Framework**

**Objective:** To create the foundational modules that allow developers to declaratively use retrieval in their programs and provide a clear contract for adding new retrieval backends.

---

#### **Component 1: The Program Module (`DSPEx.Retrieve`)**

This is the primary, user-facing component. Developers will use this module inside their own programs to signify a retrieval step.

**File:** `dspex/retrieve.ex`

**Purpose:** To act as a standard `DSPEx.Program` that, when executed, delegates the retrieval task to a globally configured or runtime-specified `RetrieverModel`.

**Key Design Decisions:**

1.  **Implements `DSPEx.Program`:** This makes it a first-class citizen in the `dspex` ecosystem, composable with `DSPEx.Predict` and other programs.
2.  **Stateless by Design:** The `DSPEx.Retrieve` struct itself is lightweight. It only holds parameters for the retrieval call (like `k`), not the connection or retrieval logic.
3.  **Configurable `k`:** The number of documents to retrieve is a fundamental parameter, so it's a field in the struct, allowing for `DSPEx.Retrieve.new(k: 5)`.
4.  **Runtime Override (`rm`):** An optional `:rm` field allows advanced users to specify a non-default retriever model for a specific call, crucial for complex pipelines or A/B testing.

**Code Implementation (`dspex/retrieve.ex`):**
```elixir
defmodule DSPEx.Retrieve do
  @moduledoc """
  A standard DSPEx program that retrieves passages from a configured knowledge source.

  This module is a declarative placeholder within a program. When its `forward/3`
  function is called, it uses the RetrieverManager to find the appropriate
  RetrieverModel and delegates the actual retrieval logic to it.

  ### Example Usage:

      # In your program's definition
      defstruct retrieve: DSPEx.Retrieve.new(k: 5), ...

      # In your program's forward function
      DSPEx.Program.forward(program.retrieve, %{query: "your search query"})
  """
  use DSPEx.Program

  # k: The number of passages to retrieve.
  # rm: Optional. An atom identifying a specific retriever model to use,
  #     overriding the globally configured default.
  @enforce_keys []
  defstruct k: 3, rm: nil

  @impl DSPEx.Program
  def forward(%__MODULE__{k: k, rm: rm_override}, %{query: query}, _opts) do
    # The core logic is delegation. It finds the correct retriever and calls it.
    with {:ok, rm_module} <- DSPEx.Services.RetrieverManager.get_rm(rm_override) do
      # All retriever models will implement the `retrieve/2` function.
      rm_module.retrieve(query, k)
    else
      # Handle cases where the retriever is not configured.
      {:error, :retriever_not_configured} = error -> error
      {:error, reason} -> {:error, {:retriever_manager_error, reason}}
    end
  end

  # Handle calls where the input map is missing the required :query key.
  def forward(_, inputs, _) when not is_map_key(inputs, :query) do
    {:error, {:invalid_input, "DSPEx.Retrieve requires a `:query` key in its inputs."}}
  end
end
```

---

#### **Component 2: The Contract (`DSPEx.RetrieverModel`)**

This `behaviour` defines the universal API that every retrieval connector must adhere to. It is the key to the system's extensibility.

**File:** `dspex/retriever_model.ex`

**Purpose:** To establish a clear, enforceable contract for any module that connects to an external data source, ensuring they can be used interchangeably by `DSPEx.Retrieve`.

**Key Design Decisions:**

1.  **`@behaviour`:** This is the Elixir-idiomatic way to define an interface or contract.
2.  **`retrieve/2` Callback:** This is the single most important function. It standardizes the input (a query string, `k`) and the output.
3.  **Return Type `[DSPEx.Example.t()]`:** The `retrieve` function will return a list of `DSPEx.Example` structs. This is a crucial decision because:
    *   It reuses a core, well-understood data structure from `dspex`.
    *   It's highly flexible. The main passage text can be stored in a `:long_text` field (for `dspy` compatibility), while other metadata like `score`, `id`, or `source_name` can be added to the example's data map.
4.  **`validate_config/1` Callback:** This provides a hook for each retriever to self-validate its configuration from `config.exs` before attempting to make a network call, enabling fast failures and clear error messages.

**Code Implementation (`dspex/retriever_model.ex`):**
```elixir
defmodule DSPEx.RetrieverModel do
  @moduledoc """
  A behaviour for implementing retrieval models (RMs).

  Any module that connects to a vector store, search API, or other knowledge
  source must implement this behaviour to be used by `DSPEx.Retrieve`.
  """

  @typedoc "A map containing configuration for the retriever (e.g., host, api_key)."
  @type config :: map()

  @typedoc "A list of retrieved passages, each as a DSPEx.Example."
  @type results :: {:ok, [DSPEx.Example.t()]} | {:error, term()}

  @doc """
  Initializes the retriever with its configuration.
  This is where connection clients can be started or validated.
  """
  @callback init(config :: config()) :: :ok | {:error, term()}

  @doc """
  Retrieves the top-k passages for a given query string.

  The returned passages should be a list of `DSPEx.Example` structs.
  The main passage text should be in the `:long_text` field. Additional
  metadata like `score` or `id` can be included in the example's data.
  """
  @callback retrieve(query :: String.t(), k :: non_neg_integer()) :: results

  @optional_callbacks init: 1
end
```
*Note: I've added an optional `init/1` callback. This is a common pattern for behaviours that might need to manage stateful resources like a database connection pool.*

---

#### **Component 3: The Manager (`DSPEx.Services.RetrieverManager`)**

This service is the "glue" that connects the abstract `DSPEx.Retrieve` program to a concrete `RetrieverModel` implementation at runtime.

**File:** `dspex/services/retriever_manager.ex`

**Purpose:** To read from the central `DSPEx.Config` and resolve which retriever module should be used for a given request.

**Key Design Decisions:**

1.  **Simple Module, Not a GenServer:** This service is purely for configuration lookup. It doesn't need to manage state, so a simple module with functions is more efficient and straightforward than a process.
2.  **Integrates with `DSPEx.Config`:** It uses the existing `DSPEx.Config.get/1` function, ensuring it fits perfectly into the `dspex` ecosystem without reinventing configuration management.
3.  **Default and Override Logic:** The `get_rm/1` function handles two cases:
    *   `get_rm(nil)`: The standard case, which looks up the `:default` retriever defined in the config.
    *   `get_rm(:my_retriever)`: The override case, which allows a specific retriever to be requested.
4.  **Returns a Module Atom:** It returns the module name (e.g., `DSPEx.Retrievers.ChromaDB`) rather than an instance, which is idiomatic in Elixir for calling module-level functions.

**Code Implementation (`dspex/services/retriever_manager.ex`):**
```elixir
defmodule DSPEx.Services.RetrieverManager do
  @moduledoc "Manages and provides access to configured retriever models."

  alias DSPEx.Config

  @spec get_rm(rm_atom :: atom() | nil) :: {:ok, module()} | {:error, term()}
  def get_rm(nil) do
    # If no specific retriever is requested, fetch the default one from config.
    case Config.get([:dspex, :retrievers, :default]) do
      {:ok, default_rm_atom} when is_atom(default_rm_atom) ->
        get_rm(default_rm_atom)
      _ ->
        {:error, :no_default_retriever_configured}
    end
  end

  def get_rm(rm_atom) when is_atom(rm_atom) do
    # A specific retriever was requested. Look up its configuration.
    with {:ok, rm_config} <- Config.get([:dspex, :retrievers, rm_atom]),
         # The configuration must specify which module implements the logic.
         module = rm_config[:module],
         :ok <- validate_module(module) do
      {:ok, module}
    else
      # Handle configuration errors gracefully.
      {:error, :not_found} ->
        {:error, {:retriever_not_configured, rm_atom}}
      {:error, :invalid_rm_module} = error ->
        error
      _ ->
        {:error, {:invalid_retriever_config, rm_atom}}
    end
  end

  defp validate_module(module) do
    if is_atom(module) and function_exported?(module, :__info__, 1) and
       :behaviour in module.__info__(:attributes) and
       DSPEx.RetrieverModel in module.__info__(:attributes)[:behaviour] do
      :ok
    else
      {:error, :invalid_rm_module}
    end
  end
end
```

---

#### **Summary of Part 1 Deliverables**

By completing this phase, we will have:
-   [x] **`dspex/retrieve.ex`**: A user-facing `Program` module that developers can instantiate and use.
-   [x] **`dspex/retriever_model.ex`**: A `behaviour` that defines a clear, extensible contract for all future retrieval connectors.
-   [x] **`dspex/services/retriever_manager.ex`**: A service that bridges the gap between configuration and execution.
-   [x] **Defined Configuration Schema**: A clear structure for how retrievers should be defined in `config.exs`.
-   [x] **Established Workflow**: A complete, albeit abstract, execution path from a program calling `Retrieve` to the point where a specific RM would be invoked.

This foundation is now ready for the next part: building the first concrete implementation, `DSPEx.Retrievers.ChromaDB`.
