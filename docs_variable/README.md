# Documentation for DSPEx Adaptive Optimization System

This directory contains two distinct, AI-generated sets of documentation for the new **Adaptive Optimization System** feature in DSPEx. Each set represents a different approach to generating the technical design and examples. This README serves as a table of contents and summary for these two attempts.

## Table of Contents

-   [Attempt 1: Cursor with Sonnet 4](#attempt-1-cursor-with-sonnet-4)
-   [Attempt 2: Claude Code with Sonnet 4](#attempt-2-claude-code-with-sonnet-4)

---

## Attempt 1: Cursor with Sonnet 4

This set of documents was generated using Cursor with the Sonnet 4 model. It provides a cohesive, end-to-end overview of the system, starting from high-level design, moving to implementation details, and finishing with practical examples and tests. This attempt successfully created a well-structured set of three core documents.

### Summary of Approach

This attempt focuses on creating a complete, user-friendly documentation set. Key innovations highlighted include the Universal Variable Abstraction, automatic strategy selection, and multi-objective evaluation with Nx. The `chat` file provides the full context and summary of what was built.

### Files

-   **Chat & Summary:**
    -   [`cursor_05_chat.md`](./cursor_05_chat.md): The full chat log that generated the documents below, including a final summary of the system. **Start here for an overview of this attempt.**

-   **Core Documents:**
    -   [`cursor_02_ADAPTIVE_OPTIMIZATION_DESIGN.md`](./cursor_02_ADAPTIVE_OPTIMIZATION_DESIGN.md): The main technical design document, outlining the architecture, the `Variable` abstraction, and usage patterns.
    -   [`cursor_03_ADAPTIVE_OPTIMIZATION_IMPLEMENTATION.md`](./cursor_03_ADAPTIVE_OPTIMIZATION_IMPLEMENTATION.md): Detailed implementation code for the core components like the `UniversalOptimizer` and `AdaptiveConfig`.
    -   [`cursor_04_ADAPTIVE_OPTIMIZATION_EXAMPLES.md`](./cursor_04_ADAPTIVE_OPTIMIZATION_EXAMPLES.md): Practical, in-depth examples for Question Answering and Code Generation, along with a comprehensive testing framework.

-   **Alternate/Initial Files:**
    -   [`cursor_01_ADAPTIVE_OPTIMIZATION_SYSTEM.md`](./cursor_01_ADAPTIVE_OPTIMIZATION_SYSTEM.md): An initial version of the design document, largely similar to `cursor_02...`.

---

## Attempt 2: Claude Code with Sonnet 4

This set of documents was generated using Claude Code with the Sonnet 4 model. This attempt took a different path, producing two high-level design documents and then performing a very deep, comprehensive dive into the **Automatic Evaluation and Selection** part of the system.

### Summary of Approach

This attempt excels at exploring the complexity of the evaluation engine. While it doesn't provide a complete implementation or example suite like the first attempt, it offers a much more detailed and robust design for how configurations could be evaluated across multiple dimensions (accuracy, cost, latency, reliability) and how the system could learn from these evaluations over time.

### Files

-   **High-Level Design:**
    -   [`cc_01_ADAPTIVE_OPTIMIZATION_SYSTEM.md`](./cc_01_ADAPTIVE_OPTIMIZATION_SYSTEM.md): A technical design document focusing on the core `Variable` and `VariableSpace` abstractions and the `UniversalOptimizer` interface.
    -   [`cc_02_ADAPTIVE_OPTIMIZATION_DESIGN.md`](./cc_02_ADAPTIVE_OPTIMIZATION_DESIGN.md): A slightly different version of the technical design, also covering the core concepts.

-   **Deep Dive on Evaluation:**
    -   [`cc_03_AUTOMATIC_EVALUATION_SELECTION_SYSTEM.md`](./cc_03_AUTOMATIC_EVALUATION_SELECTION_SYSTEM.md): **The centerpiece of this attempt.** A highly detailed document outlining a multi-dimensional evaluation engine, specialized evaluators, Pareto analysis, and a continuous learning system for performance prediction.
