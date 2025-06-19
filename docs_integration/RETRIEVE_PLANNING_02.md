Of course. Here is a detailed build-out plan for introducing a first-class retrieval system into `dspex`, mirroring the power and decoupling of `dspy.Retrieve`.

This plan outlines the necessary components, their responsibilities, a concrete first implementation, and a roadmap for future enhancements.

---

### **Project: `dspex.Retrieve` Build-Out**

**Objective:** To introduce a standardized, extensible, and concurrent retrieval system into `dspex` that allows programs to seamlessly query external knowledge sources (like vector stores) as a native step in their execution flow.

#### **1. Guiding Principles & Philosophy**

1.  **Decoupling (The DSPy Way):** Programs should declare a *need* for retrieval (`DSPEx.Retrieve`) without being tightly coupled to a specific implementation (e.g., ChromaDB, Pinecone). The concrete retrieval model (RM) will be configured globally or at runtime.
2.  **Extensibility (The Elixir Way):** The system must be built around a core `behaviour` (`DSPEx.RetrieverModel`). This will allow developers to easily add new connectors for any vector store or search API by simply implementing the required callbacks.
3.  **Concurrency First:** Leverage the BEAM's strengths. The system should be designed from the ground up to handle batch queries concurrently, using tools like `Task.async_stream` for high-throughput evaluation and processing.
4.  **Configuration-Driven:** All retriever-specific details (API keys, hosts, collection names) should be managed through the new `DSPEx.Config.Store`, ensuring a clean separation of code and configuration.

#### **2. Core Architectural Components**

To achieve this, we will introduce three main components:

| Component | Type | Responsibility |
| :--- | :--- | :--- |
| **`DSPEx.Retrieve`** | `Program` | The user-facing module used within programs. It acts as a declarative placeholder for a retrieval step. |
| **`DSPEx.RetrieverModel`** | `Behaviour` | The contract that all specific retrieval connectors (e.g., Chroma, Pinecone) must implement. |
| **`DSPEx.Services.RetrieverManager`** | `Service` | A configuration manager that reads from `DSPEx.Config` to know which `RetrieverModel` to use by default. |

---

#### **3. Detailed Component Build-Out**

##### **Component 1: `DSPEx.Retrieve` (The Program Module)**

This is what developers will use in their `dspex` programs.

**File:** `dspex/retrieve.ex`

```elixir
defmodule DSPEx.Retrieve do
  @moduledoc """
  A DSPEx program that retrieves passages from a configured knowledge source.
  This module delegates the actual retrieval logic to a configured RetrieverModel.
  """
  use DSPEx.Program

  @enforce_keys []
  defstruct k: 3, rm: nil # Default k, rm can be overridden

  @impl DSPEx.Program
  def forward(%__MODULE__{k: k, rm: rm_override}, %{query: query}, _opts) do
    # 1. Get the configured retriever model module. Use override if provided.
    with {:ok, rm_module} <- DSPEx.Services.RetrieverManager.get_rm(rm_override) do
      # 2. Delegate the actual retrieval call.
      rm_module.retrieve(query, k)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def forward(_, inputs, _) when not is_map_key(inputs, :query) do
    {:error, "DSPEx.Retrieve requires a `:query` key in its inputs."}
  end
end
```

**Key Responsibilities:**

*   Implements the `DSPEx.Program` behaviour, making it a standard building block.
*   Its `forward/3` function expects inputs to contain a `:query` key.
*   It calls the `RetrieverManager` to get the currently active retriever module.
*   It delegates the core logic to the `retrieve/2` function of the active RM.

##### **Component 2: `DSPEx.RetrieverModel` (The Behaviour)**

This defines the contract for any retrieval backend.

**File:** `dspex/retriever_model.ex`

```elixir
defmodule DSPEx.RetrieverModel do
  @moduledoc """
  A behaviour for implementing retrieval models (RMs).

  Any module that connects to a vector store or search API must
  implement this behaviour to be compatible with `DSPEx.Retrieve`.
  """

  @typedoc "A map containing configuration for the retriever (e.g., host, api_key)."
  @type config :: map()

  @typedoc "A list of retrieved passages, each as a DSPEx.Example."
  @type results :: {:ok, [DSPEx.Example.t()]} | {:error, term()}

  @doc "Retrieves the top-k passages for a given query."
  @callback retrieve(query :: String.t(), k :: non_neg_integer()) :: results

  @doc "Validates the retriever's configuration."
  @callback validate_config(config :: config()) :: :ok | {:error, term()}
end
```

**Key Responsibilities:**

*   `retrieve(query, k)`: The core function. Takes a string query and `k`, returns a list of `DSPEx.Example`s. We use `Example` because it's a known struct in `dspex` and can flexibly hold metadata like `score` and `id` alongside the text. The main text will be stored in a `:long_text` field for `dspy` compatibility.
*   `validate_config(config)`: A hook to ensure the necessary configuration (e.g., `:host`, `:api_key`) is present.

##### **Component 3: `DSPEx.Services.RetrieverManager` (The Service)**

This service connects the `Retrieve` program to the correct `RetrieverModel` implementation based on the application's config.

**File:** `dspex/services/retriever_manager.ex`

```elixir
defmodule DSPEx.Services.RetrieverManager do
  @moduledoc "Manages and provides access to configured retriever models."

  alias DSPEx.Config

  @spec get_rm(rm_atom :: atom() | nil) :: {:ok, module()} | {:error, term()}
  def get_rm(nil) do
    # Get the default RM from config
    case Config.get([:dspex, :retrievers, :default]) do
      {:ok, default_rm_atom} -> get_rm(default_rm_atom)
      _ -> {:error, :no_default_retriever_configured}
    end
  end

  def get_rm(rm_atom) when is_atom(rm_atom) do
    with {:ok, rm_config} <- Config.get([:dspex, :retrievers, rm_atom]),
         module = rm_config[:module],
         :ok <- validate_module(module) do
      {:ok, module}
    else
      _ -> {:error, {:retriever_not_configured, rm_atom}}
    end
  end

  defp validate_module(module) do
    # In a real impl, this would check if it implements the behaviour
    if is_atom(module), do: :ok, else: {:error, :invalid_rm_module}
  end
end
```

---

#### **4. First Implementation (MVP): `DSPEx.Retrievers.ChromaDB`**

To make this concrete, we'll build the first RM connector for ChromaDB, a popular and easy-to-use vector store with a simple REST API.

**File:** `dspex/retrievers/chromadb.ex`

```elixir
defmodule DSPEx.Retrievers.ChromaDB do
  @moduledoc "A RetrieverModel for ChromaDB."
  @behaviour DSPEx.RetrieverModel

  alias DSPEx.{Config, Example}

  # This would be a real implementation of the behaviour
  @impl DSPEx.RetrieverModel
  def retrieve(query, k) do
    with {:ok, config} <- Config.get([:dspex, :retrievers, :chroma]),
         :ok <- validate_config(config),
         # In a real implementation, we'd need an embedder.
         # For the MVP, we assume ChromaDB handles embedding or we send text.
         # Let's assume we need to embed it first.
         {:ok, query_vector} <- embed_query(query) do

      # Prepare the HTTP request to ChromaDB's /query endpoint
      url = "#{config[:host]}:#{config[:port]}/api/v1/collections/#{config[:collection_name]}/query"
      headers = [{"Content-Type", "application/json"}]
      body = %{
        "query_embeddings" => [query_vector],
        "n_results" => k,
        "include" => ["metadatas", "documents", "distances"]
      }

      case Finch.build(:post, url, headers, Jason.encode!(body)) |> Finch.request(DSPEx.Finch) do
        {:ok, %{status: 200, body: body}} ->
          parse_chroma_response(body)
        {:ok, %{status: status, body: body}} ->
          {:error, {:chroma_api_error, status, body}}
        {:error, reason} ->
          {:error, {:network_error, reason}}
      end
    end
  end

  # Dummy embedder for now. This should be its own extensible component later.
  defp embed_query(query) do
    # In a real scenario, this calls an embedding model (e.g., via DSPEx.Client).
    # Returning a dummy vector for structure.
    dummy_vector = List.duplicate(0.1, 1536) # Simulating a 1536-dim vector
    {:ok, dummy_vector}
  end

  defp parse_chroma_response(raw_body) do
    # Chroma response is a map with keys "ids", "documents", "metadatas", "distances".
    # Each is a list of lists (one inner list per query).
    case Jason.decode(raw_body) do
      {:ok, body} ->
        passages =
          body
          |> Map.get("documents", [[]])
          |> List.first() # Get results for the first (and only) query
          |> Enum.with_index()
          |> Enum.map(fn {text, i} ->
            score = 1.0 - Enum.at(body["distances"] |> List.first(), i) # Convert distance to similarity
            id = Enum.at(body["ids"] |> List.first(), i)
            Example.new(%{long_text: text, score: score, id: id})
          end)
        {:ok, passages}
      _ ->
        {:error, :json_parsing_failed}
    end
  end

  @impl DSPEx.RetrieverModel
  def validate_config(config) do
    required_keys = [:host, :port, :collection_name, :module]
    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true -> :ok
      false -> {:error, {:missing_chroma_config, required_keys}}
    end
  end
end
```

---

#### **5. Developer Workflow**

With these components in place, here is how a developer would use the new retrieval system:

**Step 1: Configure the Retriever in `config/config.exs`**

```elixir
config :dspex,
  retrievers: [
    default: :chroma, # Set the default RM
    chroma: [
      module: DSPEx.Retrievers.ChromaDB,
      host: "http://localhost",
      port: 8000,
      collection_name: "my_documents"
    ],
    # pinecone: [ ... ] # Future addition
  ]
```

**Step 2: Use `DSPEx.Retrieve` in a Program**

```elixir
defmodule MyRAG do
  use DSPEx.Program

  # Define the sub-modules this program will use.
  defstruct retrieve: DSPEx.Retrieve.new(k: 3),
            generate: DSPEx.Predict.new(MyRAGSignature)

  # Define the signature for the LLM call.
  defmodule MyRAGSignature do
    use DSPEx.Signature, "context, question -> answer"
  end

  @impl DSPEx.Program
  def forward(%__MODULE__{} = program, %{question: question}, _opts) do
    # 1. Retrieve context. This calls the configured ChromaDB retriever.
    {:ok, %{context: context_passages}} = DSPEx.Program.forward(program.retrieve, %{query: question})

    # Format the context for the LLM.
    context_str = Enum.map_join(context_passages, "\n---\n", &(&1.data.long_text))

    # 2. Generate the answer using the retrieved context.
    DSPEx.Program.forward(program.generate, %{context: context_str, question: question})
  end
end
```

---

#### **6. Roadmap & Future Enhancements**

1.  **Batch Retrieval:**
    *   Add `retrieve_batch(queries, k)` to the `RetrieverModel` behaviour.
    *   The default implementation in `DSPEx.Retrieve`'s `forward` function can use `Task.async_stream` to call the single `retrieve` function in parallel.
    *   Specific RMs (like ChromaDB) can provide an optimized batch implementation that uses the backend's batch query endpoint.

2.  **`DSPEx.Embedder` Component:**
    *   Abstract the `embed_query/1` logic into its own behaviour, `DSPEx.Embedder`.
    *   Create implementations like `DSPEx.Embedders.OpenAI` that use `DSPEx.Client`.
    *   Configure the embedder in `config.exs` and have `RetrieverManager` provide it to the RM.

3.  **More Connectors:** Add implementations for other popular services like Weaviate, Pinecone, and Azure AI Search, following the `ChromaDB` template.

4.  **`DSPEx.ReRank` Module:** Introduce a `ReRank` program that takes passages and a query, and uses an LLM to re-sort them for higher relevance before they are used as context.
