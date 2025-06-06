Excellent. With the detailed engineering plan for Layer 1 established, we can now proceed to create the corresponding documentation. We will start with the **Product Requirements Document (PRD)** for this foundational layer.

This PRD translates the engineering plan into a product-focused document. It defines the "what" and "why" for the initial release of `DSPEx`, outlining the target audience, user problems, features, and success metrics. It serves as a guiding star for the development team and a point of reference for stakeholders.

---

### **Product Requirements Document: `DSPEx` v0.1 (The Core Execution Engine)**

**Document Version:** 1.0
**Date:** October 26, 2024
**Author:** AI Assistant
**Status:** DRAFT

#### **1. Introduction & Vision**

The landscape of AI development is rapidly shifting from monolithic model interactions to complex, multi-step programs. `DSPEx` is an Elixir framework designed to bring structure, reliability, and concurrency to this new paradigm. Inspired by DSPy, `DSPEx` reimagines AI programming for the BEAM virtual machine, leveraging OTP's strengths in fault-tolerance and massive concurrency.

The vision for `DSPEx` is to become the premier framework for building and deploying production-grade, self-optimizing AI systems in the Elixir ecosystem.

This document outlines the requirements for **v0.1**, which focuses exclusively on creating a stable, usable **Core Execution Engine**. This initial version will enable developers to define, configure, and run basic Language Model (LM) programs, establishing a solid foundation for all future advancements.

#### **2. Target Audience & User Problems**

The primary audience for `DSPEx` v0.1 is **Elixir developers who are building applications that integrate with Language Models.**

This audience faces several key challenges that v0.1 aims to solve:

*   **Problem 1: Brittle Prompt Management.** Developers are currently embedding complex, hard-coded prompt strings directly in their code. These are difficult to manage, version, and adapt to new models.
    *   **Our Solution:** `DSPEx` will introduce **Signatures**, a declarative way to separate the *what* (the task's I/O contract) from the *how* (the final prompt text).

*   **Problem 2: Boilerplate and Inconsistent API Interaction.** Interacting with different LLM providers requires writing and maintaining bespoke HTTP clients, authentication logic, and error handling for each one.
    *   **Our Solution:** `DSPEx` will provide a unified **LM Client** interface that abstracts away the complexities of API interaction, starting with a standard for OpenAI-compatible endpoints.

*   **Problem 3: Lack of a Standardized Programming Model.** There is no common structure for building complex, multi-step LLM workflows in Elixir. Code is often ad-hoc and difficult to test or reuse.
    *   **Our Solution:** `DSPEx` will establish a foundational programming model with **Programs** (modules implementing a standard `forward/2` behaviour) and **Primitives** (`Example`, `Prediction`) to structure data flow.

*   **Problem 4: Concurrency and Fault-Tolerance are Hard.** Making concurrent and resilient API calls requires significant OTP expertise, which can be a barrier for developers new to the ecosystem.
    *   **Our Solution:** `DSPEx`'s architecture will handle this transparently. The Core Execution Engine will be built on OTP principles, ensuring that even a simple program call is managed as a supervised, concurrent process, though the most visible user benefits will be realized in later layers.

#### **3. Features & Scope for v0.1**

The scope of v0.1 is tightly focused on the core components required for basic execution. Anything related to optimization, advanced agents, or Python interoperability is explicitly **out of scope** for this release.

| Feature Area | User-Facing Feature | Acceptance Criteria |
| :--- | :--- | :--- |
| **1. Configuration** | **Centralized Settings Management:** A developer can configure LM provider details (API key, model name) in their `config/config.exs` file. | <ul><li>A `DSPEx.Settings` module exists.</li><li>It can reliably read nested configuration from `config :dspex, ...`.</li><li>The system gracefully handles missing configuration by returning `nil` or a specified default.</li></ul> |
| **2. Primitives** | **Declarative Signatures:** A developer can define the I/O contract for a task using a simple, readable macro: `use DSPEx.Signature, "question -> answer"`. | <ul><li>A `defsignature` macro is available.</li><li>It correctly parses simple string formats with single or multiple input/output fields.</li><li>It automatically captures the `@moduledoc` as the default instructions for the signature.</li><li>The macro generates a standard Elixir module with a `defstruct` and helper functions.</li></ul> |
| | **Standardized Data Objects:** Developers can use `DSPEx.Example` to represent data points and receive results in a `DSPEx.Prediction` struct. | <ul><li>`%DSPEx.Example{}` and `%DSPEx.Prediction{}` structs are defined.</li><li>`Example.with_inputs/2` correctly marks fields as inputs.</li><li>`Prediction.from_completions/2` correctly populates a prediction object from a raw LM response.</li></ul> |
| **3. Execution** | **Unified LM Client:** A developer can start and use a single, supervised client to interact with any OpenAI-compatible LLM endpoint. | <ul><li>A `DSPEx.Client.LM` GenServer can be started within an application's supervision tree.</li><li>It correctly uses the configuration from `DSPEx.Settings`.</li><li>It can successfully execute a request and return the parsed JSON response.</li></ul> |
| | **Basic Program Execution (`Predict`):** A developer can create and run a simple, single-step program that takes inputs, calls an LM, and returns a structured prediction. | <ul><li>A `%DSPEx.Predict{}` module implements the `DSPEx.Program` behaviour.</li><li>Calling `DSPEx.Program.forward/2` on a `Predict` instance successfully orchestrates a call to the LM client and returns a valid `%DSPEx.Prediction{}` struct.</li></ul> |

#### **4. Out of Scope for v0.1**

To maintain focus, the following features will **not** be included in the initial release:

*   **All Optimizers/Teleprompters:** No `BootstrapFewShot`, `MIPROv2`, etc.
*   **Advanced Modules:** No `ReAct`, `ProgramOfThought`, `CodeAct`.
*   **Retrieval Models (RMs):** The `RM` client will not be implemented.
*   **Caching:** No in-memory or on-disk caching.
*   **Advanced Adapters:** The initial version may have a very basic, hard-coded adapter. The full, flexible `Adapter` layer will come in Layer 2.
*   **Assertions and Advanced Error Handling:** No `Assert`/`Suggest` or complex retry logic. Failures in API calls will crash the calling process.
*   **Streaming.**
*   **Python Interoperability.**

#### **5. Success Metrics**

The success of `DSPEx` v0.1 will be measured by its ability to provide a stable and intuitive foundation.

*   **Developer Experience:**
    *   **Time to "Hello, World":** A developer familiar with Elixir should be able to set up, configure, and run the basic question-answering example from the "Getting Started" guide in **under 15 minutes**.
*   **Stability & Correctness:**
    *   **Test Coverage:** The core components of Layer 1 must achieve >95% unit test coverage.
    *   **No Regressions:** The foundational APIs (e.g., `defsignature`, `Program.forward`) should be stable enough that they do not require breaking changes when implementing Layer 2.
*   **Adoption (Future-Looking):**
    *   The architecture established in v0.1 must be deemed a viable and correct foundation for building the more complex features of Layers 2-4 without requiring a major refactor. This will be assessed via internal design review upon completion of the layer.

---
This PRD sets a clear, achievable goal for the first version of `DSPEx`. Next, we can proceed to write the **Getting Started Guide** and the detailed **Core Concepts** documentation, which will be based directly on the features defined here.
