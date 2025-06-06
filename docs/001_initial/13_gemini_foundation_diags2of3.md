Excellent. We will now create the second document in the technical blueprint series. This one focuses on the internal data structures and the flow of data transformations that occur during a single, complete program execution.

This is a critical document for developers, as it clarifies the "shape" of data at every step, from user input to the final structured output.

---

### **`DSPEx` Technical Blueprint - Document 2 of 3**

### **Topic: Core Data Structures & End-to-End Data Flow**

**Objective:** To provide a detailed specification of the primary data structures and to visualize the transformation of data as it flows through the system during a `DSPEx.Predict.forward/2` call. This ensures that all components have a consistent and well-understood data contract.

---

### **Diagram 2.1: Core Data Structures**

*   **Purpose:** To define the Elixir `struct`s that represent the primary data entities in `DSPEx`. This serves as the single source of truth for the shape of data.
*   **Type:** Class Diagram (adapted for Elixir structs).

```mermaid
classDiagram
    direction LR

    class Example {
        <<Struct>>
        +fields: map()
        +input_keys: MapSet.t()
        +dspy_uuid: String.t()
        +new(map)
        +with_inputs(list) %Example
        +inputs() map
        +labels() map
    }

    class Prediction {
        <<Struct>>
        +completions: list(%Example{})
        +lm_usage: map()
        +from_completions(list, module) %Prediction
    }

    class Signature {
        <<Behaviour>>
        +instructions() String.t()
        +input_fields() list(atom)
        +output_fields() list(atom)
    }

    class MySignature {
        <<Module>>
        +__using__(opts)
        +defstruct [:question, :answer]
        +@type t :: %MySignature{}
    }

    Prediction --|> Example : extends
    MySignature ..|> Signature : implements

    note for Example "Represents a single data point (e.g., a training example)."
    note for Prediction "The final output of a Program, containing one or more completions."
    note for Signature "A behaviour defining the I/O contract for a Program."
    note for MySignature "A user-defined module created by the `defsignature` macro."

```

#### **Key Architectural Details:**

1.  **Immutability:** Functions like `with_inputs` on the `Example` struct are specified to return a *new* struct instance, reinforcing Elixir's immutability principles.
2.  **`Prediction` as a Superset:** The `Prediction` struct is an extension of `Example`, inheriting its fields and adding `completions` for multi-turn responses and `lm_usage` for future tracking.
3.  **`Signature` as a Behaviour:** This formalizes the contract that any signature module (whether created by the macro or manually) must adhere to. This allows the rest of the system to polymorphically query any signature for its instructions and fields.
4.  **Metaprogramming Endpoint:** `MySignature` represents the user's code. The `__using__` function (the entry point for the `use` macro) is the mechanism that generates the struct and implements the `Signature` behaviour.

---

### **Diagram 2.2: `DSPEx.Signature` Macro Expansion Flow**

*   **Purpose:** To visualize the compile-time metaprogramming process that transforms a developer's simple declaration into a full-fledged module. This corresponds to **Diagram 4** from the high-level plan, but with more implementation detail.
*   **Type:** Flowchart.

```mermaid
graph TD
    A["Developer writes:<br/>`use DSPEx.Signature, \"question -> answer\"`<br/>in `my_app/signatures/my_qa.ex`"] --> B{`mix compile` runs};

    subgraph "Elixir Compiler"
        B --> C{Compiler invokes `DSPEx.Signature.__using__/1` macro};
        C --> D["**Step 1: Parse String**<br/>- Split on `\"->\"`<br/>- `inputs_str = \"question\"`<br/>- `outputs_str = \"answer\"`"];
        D --> E["**Step 2: Extract Fields**<br/>- Split input/output strings by comma<br/>- `input_fields = [:question]`<br/>- `output_fields = [:answer]`"];
        E --> F["**Step 3: Capture Metadata**<br/>- Read the module's `@moduledoc` attribute"];
        F --> G["**Step 4: Generate Code (AST)**<br/>Use `quote do ... end` to build Elixir code"];
    end

    G --> H["
        **Generated Code Injected into `MyQA` Module:**
        ```elixir
        defstruct [:question, :answer]
        @behaviour DSPEx.Signature

        @impl DSPEx.Signature
        def instructions, do: \"... (from @moduledoc)\"

        @impl DSPEx.Signature
        def input_fields, do: [:question]
        
        @impl DSPEx.Signature
        def output_fields, do: [:answer]
        ```
    "];

    H --> I[Runtime: `MyQA` is a normal, efficient module with a struct and functions];

    style G fill:#cde,stroke:#333,stroke-width:2px
```

#### **Key Architectural Details:**

1.  **Compile-Time Work:** All the heavy lifting of parsing and code generation happens *once* during compilation. There is zero string-parsing overhead at runtime.
2.  **Code Injection:** The macro uses `quote` to generate the Abstract Syntax Tree (AST) for the new functions and struct, which is then injected directly into the user's module. This is Elixir's powerful mechanism for extending the language.
3.  **Source of Truth:** The macro logic is the single place that defines how a signature string maps to a module's structure, ensuring consistency across the entire framework.

---

### **Diagram 2.3: End-to-End Data Transformation Flow (`Predict` call)**

*   **Purpose:** This diagram traces the "shape" of the data as it moves through the system for a single call to `DSPEx.Predict.forward/2`.
*   **Type:** Data Flow Diagram.

```mermaid
graph TD
    direction LR

    subgraph "User Code"
        UserInput["`inputs :: %{...}`<br/>e.g., `%{question: \"...\"}`"]
    end

    subgraph "DSPEx.Predict Module"
        PredictProcess["`ProgramProcess`"]
    end

    subgraph "DSPEx.Client.LM"
        LMClient["`LM GenServer`"]
        IOTask["`I/O Task`"]
    end

    subgraph "External API"
        OpenAI["OpenAI API"]
    end

    subgraph "User Code (Return)"
        PredictionOutput["`%DSPEx.Prediction{}`"]
    end

    UserInput -- "1. `forward(program, inputs)`" --> PredictProcess
    PredictProcess -- "2. Formats `messages` list" --> Messages["`messages :: list(map)`<br/>e.g., `[%{role: \"user\", ...}]`"]
    Messages -- "3. `request(client, messages, ...)`" --> LMClient
    LMClient -- "4. Spawns Task w/ formatted request" --> IOTask
    IOTask -- "5. Sends JSON payload" --> HTTPBody["`http_body :: json_string`"]
    HTTPBody -- "6. HTTP POST" --> OpenAI
    OpenAI -- "7. HTTP Response" --> HTTPResponse["`http_response :: json_string`"]
    HTTPResponse -- "8. Parses JSON" --> IOTask
    IOTask -- "9. Sends `{:ok, completion_map}`" --> CompletionMap["`completion_map :: map`"]
    CompletionMap -- "10. Message to `ProgramProcess`" --> PredictProcess
    PredictProcess -- "11. Formats into Prediction" --> PredictionOutput

    style PredictProcess fill:#f9f,stroke:#333,stroke-width:2px
    style LMClient fill:#f9f,stroke:#333,stroke-width:2px
    style IOTask fill:#f9f,stroke:#333,stroke-width:2px

```

#### **Key Architectural Details:**

1.  **Clear Transformations:** Each arrow is annotated, showing precisely which component is responsible for transforming the data into its next state. For example, `DSPEx.Predict` is responsible for creating the initial `messages` list, while the `I/O Task` is responsible for JSON serialization/deserialization.
2.  **Data Encapsulation:** The raw HTTP request/response logic is fully contained within the `I/O Task`. The `ProgramProcess` only deals with structured Elixir maps and structs.
3.  **Standardized Interfaces:** The flow demonstrates the contract between components. The `ProgramProcess` knows it will receive a `completion_map` from the client's task, and the user knows they will receive a `%DSPEx.Prediction{}` struct. This standardization is key to building composable systems.

This document provides the complete blueprint for the data structures and data flow of `DSPEx` v0.1. The next and final document in this series will detail the dynamic sequence of interactions, including failure scenarios.
