Excellent. Now that we've established the `foundation` library as a core dependency, we can create a new series of technical documents that reflect this "accelerated" plan. These documents will be more focused on the DSPy-specific logic, assuming the underlying infrastructure (pooling, circuit-breaking, etc.) is provided by `foundation`.

This first document in the new series will detail the design of the `LM Client` and the `Predict` module, showing how they are simplified and made more robust by leveraging `foundation`.

---

### **`DSPEx` Technical Blueprint (Foundation-Accelerated) - Document 1 of 3**

### **Topic: The `LM` Client & `Predict` Module on `foundation`**

**Objective:** To provide a detailed engineering blueprint for the core request-response loop of `DSPEx`. This document specifies how `DSPEx.Client.LM` and `DSPEx.Predict` are implemented by leveraging the `Foundation` library for infrastructure concerns like connection pooling and fault tolerance.

---

### **1. `DSPEx.Client.LM` Architecture**

**Previous Design:** A complex `GenServer` that would need to manage its own task supervision and HTTP workers.

**New Design:** A much simpler `GenServer` that acts as an orchestrator, delegating all infrastructure concerns to `foundation`.

#### **1.1. Component Diagram**

This diagram shows the new relationship. The `LM Client` no longer builds infrastructure; it uses it.

```mermaid
graph TD
    subgraph "DSPEx Components"
        A(Predict Program)
        B(LM Client GenServer)
    end

    subgraph "Foundation Library Components"
        C(Foundation.Infrastructure)
        D(ConnectionManager Pool)
        E(CircuitBreaker :fuse)
        F(RateLimiter :hammer)
    end
    
    A -- "1. Sends request" --> B
    B -- "2. Uses `execute_protected`" --> C
    C -- "3a. Checks Rate Limiter" --> F
    C -- "3b. Checks Circuit Breaker" --> E
    C -- "3c. Gets HTTP Worker from Pool" --> D

    note right of B
        <b>Simplified Role:</b><br/>
        - Manages model-specific logic (e.g., prompt formatting).<br/>
        - Holds provider configuration.<br/>
        - Delegates execution to `foundation`.
    end
```

#### **1.2. State and Initialization**

The `LM Client` `GenServer` is started by the application's main supervisor. Its primary job on startup is to configure the necessary `foundation` pools and protection mechanisms.

**File:** `lib/dspex/client/lm.ex`

```elixir
defmodule DSPEx.Client.LM do
  use GenServer

  # --- Public API ---
  def start_link(opts) do
    # opts = [name: MyClient, config_key: :my_openai_config]
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def request(client, messages, config \\ %{}) do
    GenServer.call(client, {:request, messages, config})
  end

  # --- GenServer Callbacks ---
  @impl true
  def init(opts) do
    config_key = Keyword.fetch!(opts, :config_key)
    # Get provider config (api_key, model, etc.) from foundation's config
    {:ok, provider_config} = Foundation.Config.get([:dspex, config_key])
    
    pool_name = :"#{config_key}_pool"
    
    # Configure and start a connection pool for this client using foundation
    Foundation.Infrastructure.ConnectionManager.start_pool(pool_name,
      worker_module: DSPEx.Client.HttpWorker,
      worker_args: [base_url: provider_config.base_url],
      size: 10
    )

    # Configure circuit breaker for this client
    Foundation.Infrastructure.configure_protection(config_key, %{
      circuit_breaker: %{failure_threshold: 5, recovery_time: 30_000}
    })

    {:ok, %{config: provider_config, pool_name: pool_name}}
  end

  @impl true
  def handle_call({:request, messages, call_config}, _from, state) do
    # The actual execution logic
    response = do_request(messages, call_config, state)
    {:reply, response, state}
  end

  # --- Private Execution Logic ---
  defp do_request(messages, call_config, state) do
    # The function to be executed by foundation
    api_call_fun = fn http_worker ->
      # http_worker is a PID from the pool
      # This worker would know how to make the actual HTTP call
      DSPEx.Client.HttpWorker.post(http_worker, "/v1/chat/completions", %{
        model: state.config.model,
        messages: messages,
        temperature: call_config[:temperature] || 0.0
      })
    end

    # Wrap the function call with foundation's protection
    Foundation.Infrastructure.execute_protected(
      state.config.provider, # e.g., :openai
      [
        connection_pool: state.pool_name,
        circuit_breaker: state.config.provider # Use provider name for fuse
      ],
      api_call_fun
    )
  end
end
```

**Key Improvements from `foundation`:**

1.  **Declarative Infrastructure Setup:** The `init/1` callback becomes a configuration entry point. It declaratively sets up the connection pool and circuit breaker via `foundation`'s API, instead of managing `poolboy` and `:fuse` supervisors manually.
2.  **Simplified `request` Logic:** The core logic inside `handle_call` is now incredibly clean. It defines the single unit of work (the `api_call_fun`) and then hands it over to `Foundation.Infrastructure.execute_protected/3` to handle pooling, retries, and fault tolerance.
3.  **No Manual Task Supervision:** We no longer need to manage `Task` processes or trap exits. `foundation`'s `CircuitBreaker` and `ConnectionManager` handle failures internally and return a standardized `{:error, reason}` tuple.

---

### **2. `DSPEx.Predict` Architecture**

The `Predict` module is a "program" that orchestrates a call to the `LM Client`. Its design is also simplified, as it can now expect a cleaner, more predictable response from the client.

#### **2.1. `Predict.forward` Sequence Diagram (Leveraging `foundation`)**

This diagram shows the updated flow. Note the reduced complexity within the `ProgramProcess`.

```mermaid
sequenceDiagram
    actor User
    participant Prog as ProgramProcess<br/>(executing `Predict.forward`)
    participant LM as LM_Client<br/>(GenServer)
    participant Foundation as Foundation.Infrastructure

    User->>+Prog: `DSPEx.Program.forward(predict_module, inputs)`
    Note over Prog: Formats inputs into `messages` list.

    Prog->>LM: `GenServer.call(client_pid, {:request, ...})`
    activate LM
    Note right of LM: This is a synchronous call.<br/>The ProgramProcess will block here.

    LM->>+Foundation: `execute_protected(..., api_call_fun)`
    Note over Foundation: Foundation now handles:<br/>- Circuit Breaker check<br/>- Pool Checkout<br/>- Execution<br/>- Pool Checkin<br/>- Error handling
    
    alt Successful Call
        Foundation-->>-LM: `{:ok, http_response}`
    else Infrastructure Failure (e.g., Fuse Open)
        Foundation-->>-LM: `{:error, :circuit_open}`
    end

    LM-->>Prog: Returns the result from Foundation
    deactivate LM

    alt Success
        Prog->>Prog: Formats `http_response` into `%DSPEx.Prediction{}`
        Prog-->>-User: Returns `%DSPEx.Prediction{}`
    else Failure
        Prog->>Prog: Wraps error and returns
        Prog-->>-User: Returns `{:error, ...}`
    end
    deactivate Prog
```

#### **2.2. `Predict` Module Implementation**

The code becomes simpler and more focused on its core responsibility: data transformation.

**File:** `lib/dspex/predict.ex`

```elixir
defmodule DSPEx.Predict do
  @behaviour DSPEx.Program
  defstruct [:signature, :client]

  @impl DSPEx.Program
  def forward(program, inputs) do
    # 1. Use the signature to format the input map into a messages list.
    # (Adapter logic will be added in Layer 2; for now, it's simple).
    messages = format_messages(program.signature, inputs)
    
    # 2. Call the LM client. The client call now blocks, but the complex
    #    concurrency and fault tolerance is handled one level down by `foundation`.
    case DSPEx.Client.LM.request(program.client, messages) do
      {:ok, lm_response} ->
        # 3. On success, parse the response and format the Prediction struct.
        #    `lm_response` is the parsed JSON body from the API.
        completions = lm_response["choices"]
        prediction = DSPEx.Prediction.from_completions(completions, program.signature)
        {:ok, prediction}
        
      {:error, reason} ->
        # 4. On failure, the reason is already a structured error from foundation.
        #    Just pass it up.
        {:error, reason}
    end
  end

  # For Layer 1, a very simple formatter. This will be replaced by the Adapter layer.
  defp format_messages(signature, inputs) do
    instructions = signature.instructions()
    
    # Simplified prompt construction
    prompt_content = instructions <> "\n---\n" <> 
      Enum.map_join(inputs, "\n", fn {k, v} -> "#{k}: #{v}" end)

    [
      %{role: "system", content: instructions},
      %{role: "user", content: prompt_content}
    ]
  end
end
```

**Key Improvements from `foundation`:**

1.  **Synchronous, Simpler Logic:** The `Predict.forward` function can now use a synchronous `GenServer.call`. This simplifies the code immensely, as there is no need for a `receive` block or manual message handling. The blocking is acceptable because the heavy lifting and potential long waits are managed efficiently by `foundation`'s pools and circuit breakers.
2.  **Standardized Error Handling:** The `case` statement handles a clear `{:ok, response}` or `{:error, reason}` tuple. The `reason` is a structured error from `foundation` (e.g., `:circuit_open`, `:rate_limited`), making error handling in the `Predict` module clean and predictable.

---

### **Conclusion and Next Steps**

By leveraging the `foundation` library, the architecture of `DSPEx`'s core execution engine is both **simpler to implement** and **more robust from the outset**. We have effectively offloaded complex infrastructure management, allowing the `DSPEx` codebase to focus purely on the logic of programming with Language Models.

The next technical document will build upon this, detailing the **`Adapter` layer and the `ChainOfThought` module**, showing how we can handle more complex prompt construction and module composition on top of this solid, `foundation`-powered base.
