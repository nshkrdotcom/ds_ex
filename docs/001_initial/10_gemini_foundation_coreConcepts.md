Excellent. Now that the `DSPEx` v0.1 PRD and Getting Started guide are drafted, we'll create the final piece of foundational documentation: the **Core Concepts Guide**.

This guide will provide a more in-depth, conceptual explanation of the components introduced in the tutorial. It solidifies the user's understanding, explains the "why" behind the architecture, and serves as a reference for developers as they start building their own custom programs. This document directly corresponds to the components defined in the Layer 1 engineering plan.

---

### **`DSPEx` Documentation: Core Concepts**

Welcome to the conceptual guide for `DSPEx`. The "Getting Started" tutorial showed you how to build a basic program. This guide explains the core abstractions that make it all work: **Signatures**, **Programs**, and **Clients**.

Understanding these concepts is key to unlocking the full power of `DSPEx`, enabling you to build modular, maintainable, and optimizable AI systems in Elixir.

---

### **1. Signatures: The "What"**

A **Signature** is the declarative heart of any `DSPEx` module. It defines the *I/O contract* of a task—what information it needs and what it is expected to produce.

**Key Idea:** A Signature separates the *intent* of a task from its *implementation*. You declare *what* you want to achieve, and `DSPEx` handles *how* to ask the Language Model to do it.

#### **Defining a Signature**

As you saw in the tutorial, the simplest way to define a signature is with the `use DSPEx.Signature` macro inside a module:

```elixir
defmodule MyApp.Signatures.SummarizeArticle do
  @moduledoc "Generate a concise, one-paragraph summary of the given article."

  use DSPEx.Signature, "article_text -> summary"
end
```

This short declaration provides `DSPEx` with three critical pieces of information:

1.  **Input Fields:** The fields to the left of `->` (e.g., `article_text`) are the inputs. Their names provide semantic meaning to the LM.
2.  **Output Fields:** The fields to the right of `->` (e.g., `summary`) are the outputs the LM is expected to generate.
3.  **Instructions:** The module's docstring (`@moduledoc`) serves as the high-level instructions for the task.

At compile time, this declarative syntax is transformed into a standard Elixir module with a struct, making it highly efficient at runtime. This aligns with **Diagram 4** from our architectural plans, emphasizing the separation of developer ergonomics from runtime performance.

---

### **2. Programs: The "How"**

A **Program** is an executable module that implements the logic of your AI system. Every `DSPEx` Program adheres to a standard interface, defined by the `DSPEx.Program` behaviour. This makes them predictable and, most importantly, composable.

The `DSPEx.Program` behaviour requires a single function:

*   **`forward(program_struct, inputs)`**: This function takes the program's own struct (which may contain configuration) and a map of inputs. It executes the program's logic and must return a `%DSPEx.Prediction{}` struct.

#### **Built-in Programs: `DSPEx.Predict`**

For many common tasks, you don't need to write your own program logic. `DSPEx` v0.1 provides the most fundamental program: `DSPEx.Predict`.

`DSPEx.Predict` is a simple program whose `forward` function performs a single, direct call to a Language Model. It uses the provided signature to format the inputs and parse the outputs.

```elixir
# Create an instance of the Predict program
sentiment_predictor = %DSPEx.Predict{
  signature: MyApp.Signatures.SentimentAnalysis,
  client: MyApp.LM_Client
}

# Execute it
prediction = DSPEx.Program.forward(sentiment_predictor, %{text: "DSPEx is amazing!"})
```

By encapsulating the "single LLM call" pattern into a standard `Program`, `DSPEx` makes even the simplest interaction a composable building block.

#### **Composing Programs**

Because all programs share the `forward/2` interface, you can easily build complex workflows by composing them. While advanced composition is a feature of later layers, it's important to understand the concept now. A hypothetical RAG (Retrieval-Augmented Generation) program would look like this:

```elixir
# This is a conceptual example for a future layer.
defmodule MyApp.RAG do
  @behaviour DSPEx.Program
  defstruct [:retriever, :generator] # It holds other programs!

  def forward(program, inputs) do
    # Call the first program (the retriever)
    retrieved_docs = DSPEx.Program.forward(program.retriever, %{query: inputs.question})

    # Use its output as input to the second program (the generator)
    DSPEx.Program.forward(program.generator, %{context: retrieved_docs.passages, question: inputs.question})
  end
end
```

---

### **3. Clients: The Bridge to the World**

A **Client** is the component that communicates with external services, such as LLM APIs. In `DSPEx`, clients are designed as robust, stateful OTP processes (`GenServer`s) to handle the complexities of network communication and state management.

#### **Why a `GenServer`?**

Using a `GenServer` for the `DSPEx.Client.LM` provides three key benefits inherent to the BEAM:

1.  **State Encapsulation:** The client process holds its configuration (API keys, model name, endpoint URL) in its internal state. This is safer and more manageable than passing configuration around or relying on global settings.
2.  **Concurrency Management:** In future layers, the client can manage request queues or connection pools to handle rate limits and ensure your application doesn't overwhelm the external API.
3.  **Fault Tolerance:** As part of your application's supervision tree, the client is automatically restarted by OTP if it ever crashes. This means a transient failure in a connection library won't bring down your entire application.

#### **The Execution Flow**

When your program runs, it doesn't make an HTTP request directly. Instead, it sends a message to the Client process. This interaction model is a core part of `DSPEx`'s resilience and is visualized in **Diagram 2**:

1.  `DSPEx.Program.forward/2` is called in your main application process.
2.  It sends an asynchronous message (`cast`) to the named `LM` Client `GenServer`.
3.  The `LM` Client receives the message and immediately spawns a new, lightweight `Task` process to handle the blocking HTTP request.
4.  The `LM` Client is now free to accept other requests, preventing it from becoming a bottleneck.
5.  The `Task` performs the network call and sends the result directly back to the original `Program` process.
6.  If the network call fails, only the `Task` crashes. The `Program` process (its supervisor) can then decide how to handle the failure, such as by retrying.

This architecture ensures that your application remains responsive and resilient, even when dealing with slow or unreliable network services.

---

### **Summary: The Core Workflow**

These three concepts form a simple but powerful workflow:

> You define **What** you want with a **Signature**. You define **How** it gets done with a **Program**. The Program uses a **Client** to interact with the outside world.

Mastering this foundational layer will prepare you for the more advanced features of `DSPEx`, where you will learn to compose these blocks into sophisticated pipelines and use **Optimizers** to automatically tune them for maximum performance.
