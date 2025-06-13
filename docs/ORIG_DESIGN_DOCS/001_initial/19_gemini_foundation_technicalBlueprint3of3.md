Excellent. Here is the third and final technical blueprint document for the `DSPEx` core. This document focuses on the dynamic interactions within our newly designed compositional system.

It will detail how `ChainOfThought` works in sequence and how the `Adapter` layer handles the inclusion of few-shot demonstrations, a critical step before we can implement the optimizers in later layers.

---

### **`DSPEx` Technical Blueprint (Foundation-Accelerated) - Document 3 of 3**

### **Topic: Compositional Dynamics & Few-Shot Demonstration Flow**

**Objective:** To provide a detailed blueprint of the runtime interactions within a compositional program (`ChainOfThought`) and to specify the data flow for including few-shot demonstrations in a prompt. This finalizes the design of the core execution engine, making it ready for optimization.

---

### **1. `ChainOfThought` Execution Sequence**

**Purpose:** This diagram illustrates the sequence of events when a user calls `forward` on a `ChainOfThought` module. It highlights how `CoT` acts as an orchestrator, modifying the signature before delegating the core work to its internal `Predict` module.

**Type:** Sequence Diagram.

```mermaid
sequenceDiagram
    actor User
    participant CoT as ChainOfThought Program
    participant Predict as Internal Predict Program
    participant Adapter as DSPEx.Adapter.Chat
    participant Client as LM Client

    User->>+CoT: `forward(cot_program, inputs)`

    Note over CoT: `cot_program` holds an internal `predictor`<br/>with an extended `signature` that includes `:reasoning`.

    CoT->>Predict: `forward(cot_program.predictor, inputs)`
    activate Predict

    Note over Predict: Now executing the `Predict.forward` logic...
    Predict->>Adapter: `format(extended_signature, demos, inputs)`
    activate Adapter
    Note over Adapter: Adapter builds a prompt for the<br/>`question -> reasoning, answer` signature.
    Adapter-->>Predict: returns `messages` list
    deactivate Adapter

    Predict->>Client: `request(client, messages)`
    activate Client
    Note over Client: Uses `foundation` to handle the<br/>HTTP call, pooling, and circuit breaking.
    Client-->>Predict: returns `{:ok, lm_response}`
    deactivate Client

    Predict->>Adapter: `parse(extended_signature, lm_response)`
    activate Adapter
    Note over Adapter: Parses the text completion, extracting<br/>both `reasoning` and `answer` fields.
    Adapter-->>Predict: returns `parsed_fields` map
    deactivate Adapter

    Predict->>Predict: Wraps `parsed_fields` in `%DSPEx.Prediction{}`
    Predict-->>-CoT: returns `{:ok, prediction_with_reasoning}`
    deactivate Predict

    CoT-->>-User: returns `{:ok, prediction_with_reasoning}`
    deactivate CoT
```

#### **Key Architectural Details:**

1.  **Composition in Action:** `ChainOfThought` doesn't talk to the `Adapter` or `Client` directly. It is purely a compositional layer that delegates the execution to its internal `Predict` instance. This is a clean and maintainable design.
2.  **Signature as a Parameter:** The `extended_signature` (the one with the `:reasoning` field) is passed down through the call stack. The `Adapter` uses this modified signature to correctly format the prompt and parse the output, demonstrating how signatures control the behavior of the entire system.
3.  **Black Box Execution:** From the perspective of `ChainOfThought`, the internal `Predict` module is a black box that it trusts to execute the given signature. This encapsulation is key to building large, maintainable programs.

---

### **2. Data Flow for Few-Shot Demonstrations**

**Purpose:** This diagram details how a list of few-shot examples (`demos`) provided to a `Predict` module is processed by the `ChatAdapter` and formatted into a series of user/assistant message pairs in the final prompt.

**Type:** Data Flow Diagram.

```mermaid
graph TD
    subgraph "Input to Predict.forward"
        A["`inputs :: %{...}`"]
        B["`demos :: list(%Example{})`"]
    end

    subgraph "DSPEx.Adapter.Chat"
        C(format/3)
    end
    
    subgraph "Formatted Messages"
        D["System Message<br/>(from signature instructions)"]
        E["Demo 1: User Message<br/>(from demo[0].inputs)"]
        F["Demo 1: Assistant Message<br/>(from demo[0].labels)"]
        G["Demo 2: User Message<br/>(from demo[1].inputs)"]
        H["Demo 2: Assistant Message<br/>(from demo[1].labels)"]
        I["..."]
        J["Final User Message<br/>(from current inputs)"]
    end

    A --> C
    B --> C
    
    C --> D
    C --> E
    E --> F
    F --> G
    G --> H
    H --> I
    I --> J

    note right of C
        The `Adapter.format` function is responsible
        for orchestrating this entire assembly process.
        It loops through the `demos` list to build the
        alternating user/assistant turns.
    end
```

#### **Key Implementation Details for the `Adapter`:**

1.  **Iterating over Demos:** The `DSPEx.Adapter.Chat.format/3` function must contain a loop (e.g., `Enum.flat_map/2`) over the `demos` list.
2.  **Role Alternation:** For each `Example` in the `demos` list, the adapter must generate two messages:
    *   A message with `role: "user"`, where the `content` is formatted from the `example.inputs()`.
    *   A message with `role: "assistant"`, where the `content` is formatted from the `example.labels()`.
3.  **Consistent Formatting:** The formatting logic used to create the content for demo messages (e.g., `[[ ## field_name ## ]]...`) must be the *exact same* logic used to format the final user message from the current `inputs`. This is achieved by having a shared private helper function (e.g., `build_user_message_content/2`).
4.  **Final Assembly:** The final `messages` list must be assembled in the correct order: `[system_message | (demo_messages ++ [final_user_message])]`.

---

### **3. Complete Layer 1 System Architecture**

**Purpose:** To provide a single, holistic view of all Layer 1 components and their primary interactions, now accelerated by the `foundation` library.

**Type:** Component Diagram.

```mermaid
graph TD
    subgraph "User-Defined Application"
        direction TB
        UserCode["User Code<br/>(e.g., `MyDspyApp.ex`)"]
        UserSignature["`MySignature` Module<br/>(created by `defsignature`)"]
    end
    
    subgraph "DSPEx Core Engine"
        direction TB
        Predict["`DSPEx.Predict` Module"]
        CoT["`DSPEx.ChainOfThought` Module"]
        Adapter["`DSPEx.Adapter.Chat` Module"]
        Client["`DSPEx.Client.LM` GenServer"]
    end

    subgraph "Foundation Library"
        direction TB
        Infra["`Foundation.Infrastructure`"]
        Pool["`ConnectionManager` Pool"]
        Fuse["`CircuitBreaker` Fuse"]
    end

    UserCode -- "Instantiates & Calls" --> CoT
    UserCode -- "Defines" --> UserSignature
    
    CoT -- "Contains & Delegates to" --> Predict
    CoT -- "Uses" --> UserSignature
    Predict -- "Uses" --> UserSignature
    Predict -- "Uses" --> Adapter
    Predict -- "Calls" --> Client

    Adapter -- "Formats/Parses Data" --> Predict

    Client -- "Executes via" --> Infra
    Infra -- "Manages" --> Pool
    Infra -- "Manages" --> Fuse
    
    style UserCode fill:#cde,stroke:#333,stroke-width:2px
    style UserSignature fill:#cde,stroke:#333,stroke-width:2px
    style Infra fill:#f9f,stroke:#333,stroke-width:2px
```

#### **Architectural Summary:**

*   **User Layer:** The developer defines their task (`UserSignature`) and orchestrates the program (`UserCode`).
*   **DSPEx Logic Layer:** `CoT` and `Predict` provide the program's control flow. The `Adapter` handles the complex task of prompt generation. These are the core value-add components of `DSPEx` itself.
*   **DSPEx Service Layer:** The `LM Client` acts as a service that abstracts away the details of making an API call.
*   **Foundation Infrastructure Layer:** `Foundation` provides the non-functional, operational backbone—concurrency, resilience, and resource management.

---

### **Conclusion: Foundation Layer Complete**

With these three blueprint documents, the technical design for the `DSPEx` Core Execution Engine is complete. We have specified:
1.  **The static process architecture** and how services are supervised.
2.  **The core data structures** and how they are transformed at compile-time and runtime.
3.  **The dynamic sequence of interactions** for both simple and compositional modules, including the crucial flow for few-shot demonstrations.

The implementation team now has a clear, comprehensive, and actionable plan. The resulting Layer 1 will be a stable, robust, and extensible platform, ready for the addition of advanced optimizers and features in subsequent layers.
