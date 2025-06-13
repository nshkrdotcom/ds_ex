Of course. The next logical step is to perform a detailed technical extraction. We will scrutinize the provided codebase and documentation to identify specific implementation details, implicit logic, and external dependencies that are crucial for a successful port. This process will also surface key unanswered questions that must be resolved before implementation can begin.

The output is a technical planning document intended for the engineering team tasked with building `DSPEx`.

---

### **Technical Information Extraction & Unanswered Questions for the `DSPEx` Port**

#### **Objective**

This document details the specific technical information required to implement `DSPEx`. It is based on an analysis of the provided DSPy source code (`repomix-output.xml`) and documentation. The goal is to move from high-level architecture to a concrete implementation checklist, highlighting areas that need further investigation.

---

### **Phase 1: Foundational Core**

| Component / Feature | Required Information / Decision | Source of Truth (in provided files) |
| :--- | :--- | :--- |
| **`DSPEx.Signature` (`defsignature` Macro)** | **1. Exact Type Parsing Logic:** How does Python's `_parse_type_node` handle complex nested types (e.g., `list[dict[str, str]]`), `Literal`, and `Optional`? We must replicate the AST parsing logic to ensure compatibility. <br> **2. Custom Type Registration:** `dspy.Image` and `dspy.History` are special Pydantic models. How does the system discover and use them? We need a mechanism for users of `DSPEx` to register their own custom structs (e.g., `%MyApp.Image{}`) that the macro can resolve from type strings. <br> **3. Field Attribute Mapping:** `InputField` and `OutputField` accept `desc` and `prefix`. How are these precisely used by the `Adapter` layer to construct the final prompt? We need to map this to struct metadata. | `signatures/signature.py` (`_parse_type_node`), `signatures/field.py`, `adapters/types/*` |
| **`DSPEx.Client.LM`** | **1. `litellm` Payload Schema:** What is the exact JSON structure `dspy.LM` passes to `litellm` for both chat and text completion models? This includes keys like `messages`, `model`, `temperature`, `max_tokens`, `n`, `stream`, etc. This schema must be replicated for our `Tesla`-based HTTP client. <br> **2. Text vs. Chat Model Formatting:** The Python code has distinct logic for `'text'` models (`litellm_text_completion`). It appears to concatenate user messages and append `"BEGIN RESPONSE:"`. We must confirm and replicate this specific formatting rule. <br> **3. Streaming Chunk Format:** What is the data structure of a single chunk yielded by `litellm` when `stream=True`? Is it a simple string, or a JSON object with a delta? This is critical for implementing `DSPEx` streaming. | `clients/lm.py` (e.g., `litellm_completion`), `pyproject.toml` (shows `litellm` dependency) |
| **`DSPEx.Adapter` Layer** | **1. Prompt Assembly Logic:** The `ChatAdapter` assembles prompts with `[[ ## field_name ## ]]`. What is the *exact* order of assembly? The documentation suggests System Message -> Demos -> History -> Current Input. We need to trace the `format` method in `adapters/base.py` and `adapters/chat_adapter.py` to confirm the precise construction of the `messages` list. <br> **2. JSON Repair Logic:** The `JSONAdapter` uses the `json-repair` library. What is the scope of repair it performs? Does it handle missing quotes, trailing commas, etc.? We will need to find or write an equivalent Elixir library. <br> **3. Structured Output Generation:** `JSONAdapter` dynamically creates a Pydantic model (`_get_structured_outputs_response_format`). How can we replicate this in Elixir? **Decision Needed:** Should we use a library like `ExJsonSchema` to validate, or dynamically define and compile a temporary module with a struct definition for `Jason` to decode into? | `adapters/base.py`, `adapters/chat_adapter.py`, `adapters/json_adapter.py` |
| **`DSPEx.Evaluate`** | **1. Failure Handling:** When a single evaluation in the thread pool fails, how is it handled? Does it contribute a score of 0, or is it ignored? The `Evaluate` class mentions a `failure_score` parameter, confirming we need to handle this. The `ParallelExecutor` also has a `max_errors` setting. We need to replicate this behavior. | `evaluate/evaluate.py`, `utils/parallelizer.py` |

---

### **Phase 2: Core Optimization Logic (Teleprompters)**

| Component / Feature | Required Information / Decision | Source of Truth (in provided files) |
| :--- | :--- | :--- |
| **`DSPEx.Teleprompter` (General)** | **1. Program State Management:** Optimizers `deepcopy` student programs. What is the exact state that is copied versus reset? The `reset_copy` method is mentioned. We need to define the state boundaries for our `GenServer`-based optimizers. | `primitives/module.py` (`deepcopy`, `reset_copy`), `teleprompt/bootstrap.py` |
| **`BootstrapFewShot`** | **1. Trace Data Structure:** The metric function receives a `trace`. What is its exact structure? It appears to be a list of tuples `(predictor, inputs, outputs)`. We need the precise schema of each element to build our own tracing mechanism (likely via a dedicated process or ETS table). <br> **2. Teacher/Student Logic:** The docs mention that the `teacher` can be a different program. What are the rules for "structural equivalence" (`assert_structural_equivalency`) that allow a teacher to be used with a student? | `teleprompt/bootstrap_finetune.py` (`build_call_data_from_trace`, `assert_structural_equivalency`), `teleprompt/bootstrap.py` |
| **`MIPROv2` (Bayesian Optimization)** | **1. Critical Dependency - `optuna`:** This optimizer relies heavily on the `optuna` library for Bayesian Optimization, specifically `TPESampler`. **This is a major blocker.** **Decision Needed:** <br> a) Find a native Elixir library for Bayesian Optimization. (Unlikely to exist with the same features). <br> b) Implement a simplified version natively. (High effort, high risk). <br> c) Use Python interop via a `Port` to call an `optuna` script. This is the most pragmatic approach but introduces inter-process communication complexity. <br> **2. Hyperparameter Defaults:** The `auto="light"` setting configures many hyperparameters. We need to extract the exact values for `num_trials`, `minibatch_size`, etc., from the `_set_hyperparameters` method. | `teleprompt/mipro_optimizer_v2.py`, `pyproject.toml` (shows `optuna` dependency) |
| **`BootstrapFinetune`** | **1. Finetuning Data Format:** What is the exact JSONL format generated by `BootstrapFinetune`? The `format_finetune_data` method in the `ChatAdapter` and the `_prepare_finetune_data` function are the sources of truth. We must replicate this format precisely for our Python interop script. <br> **2. Provider-Specific Logic:** The finetuning process for different providers (e.g., `databricks`, `openai`) involves different API calls and data upload mechanisms. The `DSPEx` port will need a `Provider` `behaviour` with callbacks like `upload_data/2` and `start_training/3` that provider-specific modules will implement, likely by calling out to a Python script via a `Port`. | `teleprompt/bootstrap_finetune.py`, `clients/databracks.py`, `clients/openai.py`, `adapters/chat_adapter.py` |

---

### **Phase 3: Advanced Modules & Features**

| Component / Feature | Required Information / Decision | Source of Truth (in provided files) |
| :--- | :--- | :--- |
| **`CodeAct` / `ProgramOfThought` (Code Sandbox)** | **1. Sandbox IPC Protocol:** The `PythonInterpreter` communicates with a Deno process (`runner.js`) via stdin/stdout. We need the exact JSON schema for this communication. What does the request (`{"code": "..."}`) contain? What are all possible response formats (`{"output": ...}`, `{"error": ..., "errorType": ...}`)? <br> **2. Tool Serialization:** How are tools (Python functions) passed into the sandbox? The `_inject_variables` function seems to be the key. Does it serialize the function's source code using `inspect.getsource`? The documentation notes that `CodeAct` only accepts pure functions, which supports this hypothesis. This must be confirmed. | `primitives/python_interpreter.py`, `primitives/runner.js`, `predict/code_act.py` |
| **Assertions** | **1. Dynamic Signature Modification:** The `backtrack_handler` adds `feedback` and `past_outputs` fields to the signature. What are the exact contents and types of these fields? For `past_outputs`, is it a single value or a map of all output fields from the failed attempt? Replicating this requires knowing the precise data passed in the retry mechanism. <br> **2. Freezing Modules:** The documentation mentions freezing modules by setting `_compiled = True`. How does this interact with assertions? Does a frozen module still backtrack? | `primitives/assertions.py` (commented out but contains logic), `learn/programming/7-assertions.md`, `faqs.md` |

---

### **Phase 4: Productionization & Developer Experience**

| Component / Feature | Required Information / Decision | Source of Truth (in provided files) |
| :--- | :--- | :--- |
| **Saving & Loading** | **1. `cloudpickle` Usage:** What specific objects are being pickled? Is it the entire module instance, or just the state dictionary returned by `dump_state`? The `save` method on `BaseModule` has a `save_program` flag which controls this. We need to know which path uses `cloudpickle` to replicate it with `:erlang.term_to_binary`. <br> **2. Dependency Versioning:** The `saving.py` module stores dependency versions in the metadata. What is the full list of tracked dependencies? We should replicate this for ensuring compatibility. | `primitives/module.py` (`save`), `utils/saving.py` |
| **Caching** | **1. Cache Key Generation:** The `cache.py` module's `cache_key` function defines the key generation logic. It ignores certain arguments (`api_key`, `base_url`). We must replicate this hashing algorithm and the list of ignored keys exactly if cross-language cache compatibility is desired (even if unlikely). | `clients/cache.py` |

---

### **Summary of Critical Blockers & Dependencies**

1.  **Bayesian Optimization (`optuna`):** `MIPROv2` is a flagship optimizer and is currently blocked by the lack of a native Elixir equivalent for `optuna`. **Decision:** Proceed with Python interop via a `Port` as the initial strategy.
2.  **Finetuning (`transformers`, `sglang`):** `BootstrapFinetune` and local model serving rely on the vast Python ML ecosystem. **Decision:** This will be handled entirely via `Port`-based Python interop. The `DSPEx` side will be responsible for data preparation and job orchestration.
3.  **Local Vector Search (`faiss`, `ragatouille`):** Similar to finetuning, local retrieval models are Python-native. **Decision:** Isolate these into RM client modules that use `Port` interop.
4.  **Code Execution Sandbox (`deno`):** The `CodeAct` module's sandbox is a complex JS/Deno/Python system. **Decision:** Replicate the Inter-Process Communication (IPC) protocol via a `Port` to a long-running Deno process.

The porting effort can proceed in parallel with the investigation of these blockers, but the designs for Phase 2 and 3 are fundamentally dependent on the interop strategy chosen.
