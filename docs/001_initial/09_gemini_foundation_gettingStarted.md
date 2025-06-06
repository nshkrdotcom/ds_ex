Excellent. We will now build out the next piece of documentation based on the v0.1 PRD: the **Getting Started Guide**.

This guide is the most critical piece of user-facing documentation for an initial release. It provides a direct, hands-on path for a developer to experience the value of the framework. It will walk through the exact features defined in the PRD for Layer 1, demonstrating how they come together to solve a simple problem.

---

### **`DSPEx` Documentation: Getting Started**

Welcome to `DSPEx`! This guide will walk you through building your first program: a simple Question Answering (QA) system that uses a Language Model (LM) to answer questions based on provided context. In under 15 minutes, you will learn how to:

1.  **Configure** an LM client.
2.  **Define** a task with a `DSPEx.Signature`.
3.  **Execute** your program to get a structured answer.

Let's begin.

#### **Prerequisites**

*   Elixir v1.15+ installed.
*   An API key for an OpenAI-compatible LM provider.

---

### **Step 1: Create a New Mix Project**

First, let's create a new Elixir project and navigate into the directory.

```bash
mix new my_dspy_app
cd my_dspy_app
```

Next, add `dspex` and an HTTP client to your dependencies in `mix.exs`. We'll use `tesla` and `jason` for this guide.

```elixir
# mix.exs
def deps do
  [
    {:dspex, "~> 0.1.0"},
    {:tesla, "~> 1.4"},
    {:jason, "~> 1.4"}
  ]
end
```

Fetch the new dependencies by running:

```bash
mix deps.get
```

---

### **Step 2: Configure Your Language Model**

`DSPEx` uses your application's configuration file to manage secrets and settings. This keeps them out of your source code.

Open `config/config.exs` and add the following, replacing `"YOUR_OPENAI_API_KEY"` with your actual key.

```elixir
# config/config.exs
import Config

# Configure the DSPEx framework.
config :dspex,
  # Define a named provider configuration. We'll call this one :default_openai.
  default_openai: [
    provider: :openai,
    api_key: "YOUR_OPENAI_API_KEY",
    model: "gpt-4o-mini"
  ]
```

This configuration tells `DSPEx` how to connect to the OpenAI API. You can define multiple provider configurations if you use different models or services.

---

### **Step 3: Define Your Task with a Signature**

In DSPy, a **Signature** is a declarative way to define what a program should do. It specifies the inputs and outputs without getting bogged down in the details of how to prompt the LM.

Create a new file `lib/my_dspy_app/signatures.ex` and define a signature for our QA task.

```elixir
# lib/my_dspy_app/signatures.ex
defmodule MyDspyApp.Signatures.BasicQA do
  @moduledoc """
  Given a context and a question, provide a concise answer.
  """
  use DSPEx.Signature, "context, question -> answer"
end
```

What just happened here?
*   The `use DSPEx.Signature, "..."` line is a macro that transforms this module.
*   It parses the string `"context, question -> answer"` to understand that your task takes `context` and `question` as inputs and produces an `answer` as output.
*   It uses the `@moduledoc` as the high-level instructions for the language model.

This simple, declarative style is at the heart of `DSPEx`.

---

### **Step 4: Start the LM Client**

`DSPEx` clients are long-running, supervised processes that manage external API connections. They need to be started as part of your application's supervision tree.

Open `lib/my_dspy_app/application.ex` and add the `DSPEx.Client.LM` to the list of children.

```elixir
# lib/my_dspy_app/application.ex
defmodule MyDspyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the DSPEx LM Client.
      # We give it a name so we can refer to it later.
      # The `:config_key` tells it to use our :default_openai settings.
      {DSPEx.Client.LM, name: MyDspyApp.OpenAIClient, config_key: :default_openai}
    ]

    opts = [strategy: :one_for_one, name: MyDspyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

By adding the client to the supervisor, you ensure that it's automatically started and restarted by OTP, making your application robust.

---

### **Step 5: Build and Run Your Program**

Now it's time to tie everything together. We will use `DSPEx.Predict`, a built-in module for executing single-step LM predictions.

Open `lib/my_dspy_app.ex` and create a function to run our QA program.

```elixir
# lib/my_dspy_app.ex
defmodule MyDspyApp do
  alias MyDspyApp.Signatures.BasicQA

  def run_simple_qa do
    # 1. Instantiate the Predict program.
    #    - `signature`: The task definition from Step 3.
    #    - `client`: The name of the running LM client process from Step 4.
    qa_program = %DSPEx.Predict{
      signature: BasicQA,
      client: MyDspyApp.OpenAIClient
    }

    # 2. Define the inputs for this specific run.
    inputs = %{
      question: "What is the primary benefit of the BEAM virtual machine?",
      context: "The BEAM, Erlang's virtual machine, is designed for building concurrent, fault-tolerant, and distributed systems. Its key features include lightweight processes and preemptive scheduling."
    }

    # 3. Execute the program by calling `forward/2`.
    prediction = DSPEx.Program.forward(qa_program, inputs)

    # 4. Inspect the result.
    IO.puts("Question: #{inputs.question}")
    IO.puts("Predicted Answer: #{prediction.answer}")
  end
end
```

#### **Execute It!**

You're ready to run your first `DSPEx` program. Start an interactive Elixir session and call your function:

```bash
iex -S mix
```

Inside `iex`:

```elixir
iex> MyDspyApp.run_simple_qa()
Question: What is the primary benefit of the BEAM virtual machine?
Predicted Answer: The primary benefit of the BEAM virtual machine is its design for building concurrent, fault-tolerant, and distributed systems.
```

Congratulations! You've successfully built and run your first `DSPEx` program.

---

### **Recap & Next Steps**

In this guide, you learned the fundamental workflow of `DSPEx` v0.1:
- You **configured** your LM settings securely.
- You **declared** your task's I/O using a `DSPEx.Signature`.
- You **instantiated** a `DSPEx.Predict` program.
- You **executed** the program to get a structured, predictable output.

This simple `Predict` module is just the beginning. The foundational components you've used—`Signature`, `Program`, and `Client`—are the building blocks for creating far more complex and powerful AI systems.

From here, you can explore:
*   Creating multi-step programs by composing modules (Layer 2).
*   Evaluating your program's performance with `DSPEx.Evaluate` (Layer 2).
*   Automatically optimizing your programs with `DSPEx` teleprompters (Future Layers).
