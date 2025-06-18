## Document 1: Elixact Enhancement Plan

This document outlines the required enhancements for the `Elixact` library to support advanced, Pydantic-like features needed for its integration into `DSPEx`.

### **Elixact Enhancement Plan for DSPEx Integration**

---

### **Status Update (as of June 2025)**

#### **Overall Enhancement Status**
- **Runtime Schema Generation**: 🔴 Not Started — No dynamic schema creation or runtime DSL yet. Remains the top priority for Elixact enhancement.
- **TypeAdapter Functionality**: 🔴 Not Started — No runtime type validation or TypeAdapter equivalent implemented.
- **Advanced Reference Resolution**: 🟡 Planned — Design is outlined, but no implementation yet. Some groundwork in JSON schema modules.
- **Wrapper Model Support**: 🟡 Planned — Not implemented, but requirements and API are specified.
- **Advanced Configuration**: 🟡 Planned — No runtime config modification; only compile-time config available.
- **Testing & Integration**: 🟡 Partial — Existing tests cover current features, but no tests for runtime or TypeAdapter features (since not implemented).

#### **Key Risks**
- **Feature Gaps**: DSPEx integration is blocked until runtime and TypeAdapter features are implemented.
- **Performance**: Not yet evaluated for runtime features.
- **API Design**: New APIs must be carefully designed for maintainability and compatibility.

---

### **1. Executive Summary**

Based on a comprehensive analysis of the Elixact repository and DSPy Pydantic pattern requirements, this document details the specific enhancements needed in Elixact to support complete DSPEx integration. While Elixact provides an excellent foundation with its schema DSL, validation engine, and JSON schema generation, **critical runtime capabilities must be added** to match DSPy's dynamic validation patterns.

**Key Finding**: Elixact needs **three major enhancements**—Runtime Schema Generation, TypeAdapter functionality, and Advanced Reference Resolution—to support the advanced Pydantic patterns required by DSPEx.

---

### **2. Current Elixact Architecture Analysis**

#### **Existing Strengths ✅**
- **Solid Core Foundation**: A comprehensive `use Elixact` macro, rich type system (primitives, arrays, objects, unions), and robust constraint system (lengths, ranges, formats).
- **Advanced Validation Engine**: Detailed, structured error reporting with field paths, safe type coercion, and support for custom validator functions.
- **JSON Schema Generation**: Full JSON Schema Draft 7 support with robust reference handling and constraint mapping.

#### **Current Limitations 🔴**
- **Compile-Time Only Schemas**: Schemas can only be defined at compile-time using the `use Elixact.Schema` macro. There is no API for creating schemas dynamically at runtime.
- **No TypeAdapter Equivalent**: There is no public API for performing one-off validation or serialization of a value against a type specification without defining a full schema.
- **Limited Dynamic Configuration**: Configuration can only be set at compile time, with no support for runtime modifications.

---

### **3. Critical Enhancement Requirements**

The following enhancements are required to unblock DSPEx integration and achieve feature parity with Pydantic's dynamic patterns.

#### **Priority 1: Runtime Schema Generation 🔴**
**Requirement**: Enable dynamic schema creation from field definitions at runtime.
**DSPy Pattern**: `pydantic.create_model("DSPyProgramOutputs", **fields)`
**Implementation Plan**: Create a new `Elixact.Runtime` module.

```elixir
# Target: lib/elixact/runtime.ex
defmodule Elixact.Runtime do
  @moduledoc "Runtime schema generation and validation capabilities."

  @doc "Create schema at runtime from field definitions."
  def create_schema(field_definitions, opts \\ [])

  @doc "Validate data against a runtime-created schema."
  def validate(data, dynamic_schema, opts \\ [])

  @doc "Generate JSON schema from a runtime schema."
  def to_json_schema(dynamic_schema, opts \\ [])
end

# Core Implementation: A dynamic schema struct and a parser
defmodule Elixact.Runtime.DynamicSchema do
  defstruct [:name, :fields, :config, :metadata]
end
```

#### **Priority 2: TypeAdapter Implementation 🔴**
**Requirement**: Provide runtime type validation and serialization without a full schema definition.
**DSPy Pattern**: `TypeAdapter(type(value)).validate_python(value)`
**Implementation Plan**: Create a new `Elixact.TypeAdapter` module.

```elixir
# Target: lib/elixact/type_adapter.ex
defmodule Elixact.TypeAdapter do
  @moduledoc "Runtime type validation and serialization without a schema."

  @doc "Validate a value against a type specification."
  def validate(type_spec, value, opts \\ [])

  @doc "Serialize a value according to a type specification."
  def dump(type_spec, value, opts \\ [])

  @doc "Generate JSON schema for a type specification."
  def json_schema(type_spec, opts \\ [])
end
```

#### **Priority 3: Enhanced Reference Resolution 🟡**
**Requirement**: Advanced JSON schema reference handling, including recursive resolution and flattening for LLM provider compatibility.
**DSPy Pattern**: Complex nested schema flattening with `$defs` expansion.
**Implementation Plan**: Enhance the `Elixact.JsonSchema.Resolver` module.

```elixir
# Target: lib/elixact/json_schema/resolver.ex
defmodule Elixact.JsonSchema.Resolver do
  @moduledoc "Advanced JSON schema reference resolution and manipulation."

  @doc "Recursively resolve all $ref entries in a schema."
  def resolve_references(schema, opts \\ [])

  @doc "Flatten nested schemas by expanding all references inline."
  def flatten_schema(schema, opts \\ [])

  @doc "Enforce OpenAI/Anthropic structured output requirements."
  def enforce_structured_output(schema, opts \\ [])
end
```

#### **Priority 4: Wrapper Model Support 🟡**
**Requirement**: Create temporary, single-field validation schemas for complex type coercion.
**DSPy Pattern**: `create_model("Wrapper", value=(target_type, ...))`
**Implementation Plan**: Create a new `Elixact.Wrapper` module.

```elixir
# Target: lib/elixact/wrapper.ex
defmodule Elixact.Wrapper do
  @moduledoc "Temporary validation schemas for type coercion patterns."

  @doc "Create a temporary wrapper schema for validating a single value."
  def create_wrapper(field_name, type_spec, opts \\ [])

  @doc "Validate data using a wrapper schema and extract the value."
  def validate_and_extract(wrapper_schema, data, field_name)
end
```

#### **Priority 5: Advanced Configuration 🟡**
**Requirement**: Allow runtime modification of validation behavior (e.g., strictness, extra fields).
**DSPy Pattern**: `ConfigDict(extra="forbid", frozen=True)`
**Implementation Plan**: Enhance the `Elixact.Config` module to support runtime creation and merging.

```elixir
# Target: lib/elixact/config.ex
defmodule Elixact.Config do
  @moduledoc "Advanced configuration with runtime modification support."

  # Configuration options to support
  # %Elixact.Config{
  #   strict: true,
  #   extra: :forbid,
  #   coercion: :safe
  # }

  def create(opts)
  def merge(base_config, overrides)
end
```

---

### **4. Implementation Strategy**

- **Phase 1: Core Runtime Capabilities (2-3 weeks)**
  1.  **Implement `Elixact.Runtime`**: Build the dynamic schema creation and validation engine.
  2.  **Implement `Elixact.TypeAdapter`**: Create the runtime type validation and serialization module.
  3.  **Integrate & Test**: Ensure both new modules are fully tested and integrated with the existing core.

- **Phase 2: Advanced Features (2-3 weeks)**
  1.  **Enhance `JsonSchema.Resolver`**: Add recursive resolution and schema flattening.
  2.  **Implement `Elixact.Wrapper` and `Elixact.Config`**: Add support for wrapper models and runtime configuration.
  3.  **Optimize & Document**: Benchmark performance, optimize hot paths, and write comprehensive documentation.

- **Phase 3: Final DSPEx Integration (1-2 weeks)**
  1.  **Update DSPEx Bridge**: Work with the DSPEx team to integrate these new capabilities.
  2.  **Create Migration Tools**: Provide utilities and guides for DSPEx users.

---

### **5. Conclusion**

Elixact provides an excellent foundation, but requires significant enhancement to support DSPy's dynamic validation patterns. The three critical enhancements—**Runtime Schema Generation**, **TypeAdapter functionality**, and **Enhanced Reference Resolution**—will transform Elixact into a comprehensive validation library with complete Pydantic feature parity. The top priority is to implement the `Runtime` and `TypeAdapter` modules, as they are the primary blockers for the DSPEx integration.

 