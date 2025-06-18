## Document 2: DSPEx Integration Plan

This document outlines the technical requirements, integration points, and implementation strategy for integrating the `Elixact` library into `DSPEx`.

### **DSPEx Integration Plan for Elixact**

---

### **Status Update (as of June 2025)**

#### **Overall Integration Status**
- **Foundation Integration**: ✅ Complete (Elixact bridge, enhanced parser, and config schema are implemented)
- **Enhanced JSON Schema Generation**: 🟡 Partial (Available in some adapters, but manual fallback remains)
- **Validation Pipeline Integration**: 🟡 Partial (Available but not default; legacy validation still present)
- **Enhanced Type System Support**: 🟡 Partial (Basic types supported; complex types in progress)
- **Runtime Schema & TypeAdapter Use**: 🔴 Not Started (Blocked by Elixact enhancements)
- **Comprehensive Test Coverage**: ✅ Complete (Core integration is tested; new features will require new tests)

#### **Key Risks**
- **Migration Complexity**: Tools for migrating existing DSPEx signatures have not been started.
- **External Dependencies**: Integration is blocked pending critical runtime enhancements in the Elixact library.

---

### **1. Executive Summary**

This document outlines the technical requirements and implementation strategy for integrating Elixact into DSPEx to provide robust, Pydantic-like type safety and validation.

**Key Finding**: DSPEx already has a **solid foundation** for Elixact integration, including a bridge module, an enhanced signature parser, and comprehensive test coverage. The integration path is **low-risk** and builds on existing, working code. The primary work involves replacing manual validation and schema generation logic with more powerful, automated Elixact-based systems.

---

### **2. Current DSPEx Architecture & Integration Points**

DSPEx has been architected with this integration in mind and already includes several key components.

#### **Existing Foundation (✅ Already Implemented)**
- **`ElixactBridge` (`/lib/dspex/elixact_bridge.ex`)**: A module to convert DSPEx signatures into Elixact schemas.
- **`EnhancedParser` (`/lib/dspex/signature/enhanced_parser.ex`)**: A signature parser that understands type annotations (`question:string -> answer:string`) and constraints.
- **`Config.Schema` (`/lib/dspex/config/schema.ex`)**: A system for type-safe configuration validation.
- **Test Infrastructure**: A suite of 13+ integration tests validating the bridge, parser, and configuration.

#### **Key Integration Points**
1.  **Input/Output Validation** (`/lib/dspex/predict.ex`): Currently uses basic, manual field presence and type checks.
2.  **Adapter Validation** (`/lib/dspex/adapters/*.ex`): Adapters like `InstructorLiteGemini` use manual JSON schema construction to guide LLM output.
3.  **Configuration Validation** (`/lib/dspex/config/schema.ex`): Uses a bespoke schema system that can be migrated to use Elixact for consistency.

---

### **3. Integration Plan & Requirements**

The integration will proceed by replacing manual logic at key points with Elixact-powered features.

#### **Priority 1: Enhanced JSON Schema Generation 🟡**
**Goal**: Replace manual JSON schema construction in adapters with automatic, constraint-aware generation from Elixact.
**Location**: `/lib/dspex/adapters/instructor_lite_gemini.ex` (and other adapters)

```elixir
# Current manual approach
defp build_json_schema(signature) do
  properties = signature.output_fields()
    |> Enum.map(fn field -> {to_string(field), %{"type" => "string"}} end)
    |> Enum.into(%{})
  %{ "type" => "object", "properties" => properties, ... }
end

# --- ENHANCEMENT REQUIRED ---

# Enhanced approach with Elixact
defp build_json_schema(signature) do
  with {:ok, elixact_schema} <- DSPEx.ElixactBridge.signature_to_schema(signature),
       {:ok, json_schema} <- Elixact.JsonSchema.from_schema(elixact_schema) do
    {:ok, json_schema}
  else
    _error -> # Fallback to legacy
  end
end
```
**Benefits**: Automatic support for complex types (nested objects, arrays), constraints (min/max), and rich field descriptions, leading to more reliable structured output from LLMs.

#### **Priority 2: Validation Pipeline Integration 🟡**
**Goal**: Replace basic input/output validation with comprehensive, type-safe validation from Elixact.
**Location**: `/lib/dspex/predict.ex`

```elixir
# Current basic validation
defp validate_inputs(signature, inputs) do
  missing_fields = signature.input_fields() -- Map.keys(inputs)
  if missing_fields == [], do: :ok, else: {:error, {:missing_fields, missing_fields}}
end

# --- ENHANCEMENT REQUIRED ---

# Enhanced validation with Elixact
defp validate_inputs(signature, inputs) do
  case DSPEx.ElixactBridge.signature_to_schema(signature) do
    {:ok, elixact_schema} ->
      # Extract only the input part of the schema for validation
      input_schema = extract_input_schema(elixact_schema)
      Elixact.validate(inputs, input_schema)
    {:error, _reason} -> # Fallback to basic validation
  end
end
```
**Benefits**: Rich type validation, constraint enforcement (length, range), structured error reporting, and automatic type coercion.

#### **Priority 3: Enhanced Type System Support 🟡**
**Goal**: Expand the `EnhancedParser` to understand and translate complex types and constraints into Elixact schemas.
**Location**: `/lib/dspex/signature/enhanced_parser.ex`

```elixir
# Current basic type support
defp parse_type_annotation("string"), do: {:ok, :string}
defp parse_type_annotation("integer"), do: {:ok, :integer}

# --- ENHANCEMENT REQUIRED ---

# Enhanced type support
defp parse_type_annotation("string(min=1,max=100)") do
  {:ok, {:string, [min_length: 1, max_length: 100]}}
end
defp parse_type_annotation("array(string)") do
  {:ok, {:array, :string}}
end
defp parse_type_annotation("object{name:string,age:integer}") do
  {:ok, {:object, [name: :string, age: :integer]}}
end
```
**Benefits**: Enables users to define complex nested objects, arrays, and unions directly in the signature string, providing compile-time and runtime type safety.

---

### **4. Implementation Strategy**

The integration will be phased to minimize risk and deliver value incrementally.

- **Phase 1: Core Integration (2-3 weeks)**
  1.  **Update Validation Pipeline**: Integrate Elixact validation in the `Predict` module for inputs and outputs, enhancing error handling.
  2.  **Enhance Adapters**: Replace manual JSON schema generation in all adapters with Elixact-based generation.
  3.  **Test**: Ensure all changes are covered by tests and work across OpenAI, Anthropic, and Gemini APIs.

- **Phase 2: Advanced Features (2-3 weeks, pending Elixact enhancements)**
  1.  **Enhance Type System**: Implement parsing for complex types (nested objects, unions, arrays) in the signature parser.
  2.  **Enhance Configuration**: Migrate the DSPEx configuration system to use Elixact schemas for validation.
  3.  **Optimize & Document**: Benchmark performance and write comprehensive documentation for the new features.

- **Phase 3: Migration (2-3 weeks)**
  1.  **Develop Migration Tools**: Create utilities to help users migrate their existing signatures to the new, typed format.
  2.  **Write Guides**: Provide clear documentation and guides for migration and best practices.

---

### **5. Success Metrics**
- **Technical**: Zero breaking changes, enhanced validation with rich type checking, high-quality JSON schema generation, and <10% validation overhead.
- **User Experience**: A simple migration process, clear documentation, actionable error messages, and robust type safety at runtime.

---

### **6. Conclusion**

DSPEx is exceptionally well-positioned for full Elixact integration. The foundational components are already complete, providing a low-risk path to adding substantial type safety and validation capabilities. By following the incremental plan outlined here, DSPEx can replace manual, error-prone logic with a powerful, automated system, achieving Pydantic feature parity while leveraging Elixir's strengths for superior performance and reliability.