# DSPEx Adaptive Optimization System

This directory contains two proposed versions of a new **Adaptive Optimization System** for DSPEx. This feature is designed to address a critical need in the DSPy/DSPEx ecosystem: the ability to automatically discover the optimal combination of adapters, modules, and parameters for a given task.

The core problem, as articulated by the DSPy community, is:
> "Do we have optimizers that permute through adapters and modules? (e.g., JSON vs Markdown tool calling, Predict vs CoT vs PoT)... all evaluated and selected automatically."

Both versions presented here aim to solve this problem by introducing a powerful `Variable` abstraction that decouples parameter declaration from the optimization process, allowing any optimizer to tune any parameter.

---

## Versions

Two distinct versions of the feature are provided for review and comparison:

1.  **Cursor (with Sonnet 4):** A practical, implementation-focused solution.
2.  **Claude Code (with Sonnet 4):** A comprehensive, architectural solution.

---

## Version 1: Cursor's Implementation-Focused Approach

This version provides a direct and comprehensive solution centered around a `UniversalOptimizer`. It's designed to be a practical, end-to-end system with a clear implementation path, detailed examples, and a full test suite.

### Key Documents

-   `cursor_05_chat.md`: A high-level summary of the proposed solution.
-   `cursor_01_ADAPTIVE_OPTIMIZATION_SYSTEM.md` & `cursor_02_ADAPTIVE_OPTIMIZATION_DESIGN.md`: The core technical design document.
-   `cursor_03_ADAPTIVE_OPTIMIZATION_IMPLEMENTATION.md`: Detailed Elixir code for the core implementation.
-   `cursor_04_ADAPTIVE_OPTIMIZATION_EXAMPLES.md`: Practical usage examples and a full testing framework.

### Key Features & Innovations

-   **Universal Variable Abstraction:** A simple yet powerful way to define discrete, continuous, and hybrid parameters that are decoupled from the optimizers.
    ```elixir
    # Decoupled variable declaration for any optimizer to use
    Variable.discrete(:adapter, [JSONAdapter, ChatAdapter, MarkdownAdapter])
    Variable.continuous(:temperature, {0.0, 2.0})
    Variable.hybrid(:model_config, [:gpt4, :claude], [{0.1, 2.0}, {0.1, 2.0}])
    ```
-   **Automatic Strategy Selection:** The `UniversalOptimizer` intelligently chooses the best optimization strategy (e.g., Grid Search, Bayesian Optimization, Genetic Algorithm) based on the characteristics of the variable space.
-   **Multi-Objective Evaluation with Nx:** Balances multiple competing objectives like accuracy, cost, and latency using high-performance numerical operations powered by Elixir's `Nx` library.
-   **End-to-End Implementation:** Provides a complete solution from design and implementation to practical examples and a comprehensive test suite.

---

## Version 2: Claude Code's Architectural Approach

This version presents a deeply architectural and highly modular solution. It breaks the problem down into specialized, interconnected systems for evaluation, selection, and continuous learning, with a strong emphasis on design patterns, extensibility, and long-term evolution.

### Key Documents

-   `cc_01_VARIABLE_ABSTRACTION_DESIGN.md`: The foundational design for the `Variable` abstraction system.
-   `cc_02_ADAPTER_MODULE_SELECTION_FRAMEWORK.md`: A dedicated framework for the intelligent selection of adapters and reasoning modules.
-   `cc_03_OPTIMIZER_INTEGRATION_PLAN.md`: A detailed plan for integrating the variable system with all existing DSPEx optimizers (SIMBA, BEACON, etc.).
-   `cc_04_VARIABLE_SYSTEM_TECHNICAL_ARCHITECTURE.md`: A high-level technical architecture of the entire system.
-   `cc_05_AUTOMATIC_EVALUATION_SELECTION_SYSTEM.md`: A comprehensive design for a multi-dimensional evaluation and selection engine, including a continuous learning component.

### Key Features & Innovations

-   **Layered Architecture:** The system is broken down into clear layers (Variable Definition, Program Integration, Optimizer Integration, Configuration Management, etc.), promoting separation of concerns.
-   **Specialized Multi-Dimensional Evaluators:** Goes beyond a single evaluation function, proposing distinct, sophisticated evaluators for accuracy, cost, latency, and reliability.
    ```mermaid
    graph TD
        A[Evaluation Engine] --> B[Objective Evaluators]
        A --> C[Evaluation Orchestrator]
        B --> E[Accuracy Evaluator]
        B --> F[Cost Evaluator]
        B --> G[Latency Evaluator]
        B --> H[Reliability Evaluator]
    ```
-   **Advanced Selection Engine:** Utilizes Pareto analysis to handle trade-offs in multi-objective optimization, identifying a frontier of optimal solutions rather than a single "best" one.
-   **Continuous Learning System:** Includes a machine learning component to predict configuration performance and adapt selection strategies over time based on historical data and user feedback.

---

## Next Steps

We recommend reviewing both versions to understand the different approaches to solving this challenge:
-   **The Cursor version** offers a pragmatic and complete starting point that is nearly implementation-ready.
-   **The Claude Code version** provides a robust, forward-looking architecture that, while more complex to implement, is designed for greater extensibility and intelligence.

A final implementation can be created by combining the strengths of both proposals: the practical examples and ready-to-use code from the Cursor version with the architectural depth and advanced features (like the learning system) from the Claude Code version.
