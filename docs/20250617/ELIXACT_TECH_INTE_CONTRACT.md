Excellent. Now that the `Elixact` library has been enhanced with a full suite of runtime validation and schema generation capabilities, we can formalize the technical contract for its integration into the `DSPEx` framework.

This document serves as the official technical specification for integrating the newly shored-up `Elixact` into `DSPEx`, replacing the previous manual and limited validation systems.

---

# DSPEx & Elixact: Technical Integration Contract

## 1. Overview & Strategic Goal

The primary objective of this integration is to replace `DSPEx`'s legacy, string-based signature validation and manual JSON schema construction with `Elixact`'s robust, type-safe, and runtime-configurable schema system. This transformation elevates `DSPEx` from a framework with basic validation to one with a production-grade, declarative type safety layer, mirroring the relationship between Python's `DSPy` and `Pydantic`.

This integration will be governed by a formal contract, defining the responsibilities of both `DSPEx` (the consumer) and `Elixact` (the provider) to ensure a clean, maintainable, and powerful architecture.

## 2. The `Elixact` Provider Contract

`Elixact` now provides a comprehensive suite of features that `DSPEx` will consume. These features form the "provider" side of the contract, guaranteeing specific capabilities and APIs.

| Feature | `Elixact` Module(s) | Key Function | `DSPEx` Use Case |
| :--- | :--- | :--- | :--- |
| **Runtime Schema Generation** | `Elixact.Runtime` | `create_schema/2` | Convert `DSPEx.Signature` strings into dynamic, validatable schemas at runtime. |
| **Universal Validation** | `Elixact.EnhancedValidator` | `validate/3` | Validate `inputs` and `outputs` against signatures with runtime configuration. |
| **Type Coercion & Wrapping** | `Elixact.Wrapper` | `wrap_and_validate/4` | Handle and coerce ambiguous LLM outputs for single fields. |
| **Ad-Hoc Type Checking** | `Elixact.TypeAdapter` | `validate/3` | Perform quick, one-off type checks without a full schema. |
| **Dynamic Configuration** | `Elixact.Config` | `create/1`, `preset/1` | Allow `DSPEx.Program`s to be called with different validation rules (e.g., strict, lenient, coercion). |
| **JSON Schema Generation** | `Elixact.Runtime` | `to_json_schema/2` | Automatically generate JSON schemas for LLM "JSON Mode" or "Function Calling". |
| **LLM Schema Optimization**|`Elixact.JsonSchema.Resolver`|`enforce_structured_output/2`| Adapt generated JSON schemas for specific provider requirements (OpenAI, Gemini). |

## 3. The `DSPEx` Consumer Contract & Integration Points

`DSPEx`, as the consumer, will integrate `Elixact` at several key points in its architecture.

### 3.1. The Bridge: `DSPEx.Signature.Elixact`

This module is the central point of contact between the two libraries. It is responsible for translating `DSPEx`'s signature definitions into `Elixact`'s runtime schema representation.

**File:** `dspex/signature/elixact.ex`

**Contract:**
1.  **`to_runtime_schema(signature_module, opts)`**:
    *   **Input**: A compiled `DSPEx.Signature` module.
    *   **Process**:
        *   It will read the `__enhanced_fields__` from the signature module, which are parsed by `DSPEx.Signature.EnhancedParser`.
        *   It will map the enhanced field definitions (name, type, constraints) to the format required by `Elixact.Runtime.create_schema/2`.
        *   It will handle the mapping of DSPEx types (e.g., `:string`, `{:array, :integer}`) to Elixact's internal type representation.
        *   The result, an `Elixact.Runtime.DynamicSchema`, will be cached (e.g., in a `persistent_term` or an `Agent`) to avoid re-computation.
    *   **Output**: `{:ok, Elixact.Runtime.DynamicSchema.t()} | {:error, term()}`.

2.  **`validate(signature_module, data, opts)`**:
    *   **Input**: A signature module, a data map (`inputs` or `outputs`), and options (e.g., `:field_type`, `config: Elixact.Config.t()`).
    *   **Process**:
        *   Calls `to_runtime_schema/2` to get the `Elixact` schema.
        *   If `:field_type` is specified (`:inputs` or `:outputs`), it will create a partial `Elixact` schema on-the-fly containing only the relevant fields.
        *   It will then call `Elixact.EnhancedValidator.validate/3`, passing the schema, data, and any `Elixact.Config` from the options.
    *   **Output**: `{:ok, validated_data} | {:error, [Elixact.Error.t()]}`.

### 3.2. Validation in `DSPEx.Predict`

The core prediction program will be refactored to use the `Elixact` bridge for robust validation.

**File:** `dspex/predict.ex` (within `forward/3`)

**Contract:**
1.  **Input Validation (Pre-LLM call):**
    *   **Current:** Basic check for key presence.
    *   **New Contract:** Before making the `DSPEx.Client.request`, `forward/3` will call `DSPEx.Signature.Elixact.validate(program.signature, inputs, field_type: :inputs, config: Elixact.Config.preset(:lenient))`.
    *   A lenient configuration is used by default for inputs to allow for flexibility, but this can be overridden by an option passed to `forward/3`.
    *   If validation fails, the `forward/3` call immediately returns `{:error, validation_errors}`.

2.  **Output Validation (Post-LLM call):**
    *   **Current:** Simple parsing.
    *   **New Contract:** After a successful `DSPEx.Client.request`, the parsed response will be validated using `DSPEx.Signature.Elixact.validate(program.signature, outputs, field_type: :outputs, config: Elixact.Config.create(coercion: true))`.
    *   Coercion is enabled by default for outputs to handle variations in LLM responses (e.g., numbers returned as strings).
    *   If validation fails, the system can either return an error or trigger a retry mechanism (a feature for `DSPEx.Predict.Retry`).

### 3.3. Structured Prediction (`DSPEx.PredictStructured`)

The integration will replace all manual JSON schema building with `Elixact`'s automated, constraint-aware generation.

**File:** `dspex/adapters/instructor_lite_gemini.ex`

**Contract:**
1.  **`build_json_schema(signature)`**: This internal function will be removed.
2.  **`format_messages(signature, ...)`**:
    *   **Current:** Manually constructs a basic JSON schema.
    *   **New Contract:**
        1.  It will call `DSPEx.Signature.Elixact.to_runtime_schema/1` to get the `Elixact` representation of the signature's **output fields**.
        2.  It will then call `Elixact.Runtime.to_json_schema/1` on the resulting schema.
        3.  Finally, it will pass this generated schema through `Elixact.JsonSchema.Resolver.enforce_structured_output/2` with `provider: :gemini` to ensure API compatibility.
        4.  The final, provider-specific JSON schema is passed to `InstructorLite`.

3.  **`parse_response(signature, instructor_result)`**:
    *   **Current:** Basic check for field presence.
    *   **New Contract:** The parsed data from `InstructorLite` will be validated against the `Elixact` schema using `DSPEx.Signature.Elixact.validate(signature, parsed_data, field_type: :outputs)`. This ensures the structured output not only has the right shape but also respects all type constraints.

### 3.4. Teleprompter and Evaluation Contract

The optimization and evaluation pipelines will leverage `Elixact` to ensure data quality and consistency.

**Files:** `dspex/teleprompter/*.ex`, `dspex/evaluate.ex`

**Contract:**
1.  **Demonstration Validation:**
    *   In `BootstrapFewShot` and `SIMBA`, any newly generated demonstration `DSPEx.Example` will be validated against its corresponding `Elixact` signature.
    *   This ensures that only high-quality, correctly-formatted examples are added to the few-shot context, preventing "garbage-in, garbage-out" optimization cycles.
2.  **Metric Function Stability:**
    *   The `metric_fn` in `DSPEx.Evaluate` and teleprompters receives a `prediction` map. `Elixact` validation on this map guarantees that it has the expected fields and types, making the metric function more robust and less prone to runtime errors.
3.  **Candidate Program Validation:**
    *   Optimizers like `SIMBA` generate new program variants. When a strategy modifies a program (e.g., by adding a rule to the instruction), the change can be validated. For example, if a rule generation strategy adds a constraint, `Elixact` can verify that the constraint is valid for the target field's type.

## 4. Refactoring Plan and Migration

The integration will be rolled out incrementally to ensure stability and maintain backward compatibility.

1.  **Implement `DSPEx.Signature.Elixact` Bridge:** Create the core translation layer. Initially, it will support a subset of types and constraints from the `EnhancedParser`.
2.  **Refactor `PredictStructured`:** This is the first and most impactful integration point. Replace the manual schema generation in `InstructorLiteGemini` adapter. This provides immediate value by enabling complex structured outputs.
3.  **Refactor `Predict`:** Integrate the `Elixact` validation checks for inputs and outputs. This can be placed behind a feature flag in the configuration initially to allow for a graceful rollout.
4.  **Enhance `Elixact` Types:** As needed, add more complex types to `Elixact` (e.g., specific `ReasoningChain` or `ToolCall` types) that can be used directly in `DSPEx` signatures.
5.  **Refactor Teleprompters:** Update `BootstrapFewShot` and other optimizers to validate generated examples. This ensures the integrity of the optimization loop.

By adhering to this contract, `DSPEx` will fully leverage the power of the enhanced `Elixact` library, resulting in a more robust, type-safe, and developer-friendly framework for building and optimizing LLM-based programs.
