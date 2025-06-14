Read file: elixact/lib/elixact/schema.ex
Read file: elixact/lib/elixact/schema.ex
Read file: elixact/lib/elixact/schema.ex
Read file: elixact/lib/elixact/schema.ex
Here is a comprehensive, evidence-based report on the Elixact type system and its alignment with the requirements and limitations described in `ELIXACT_TODO.md` and your integration task list.

---

# ELIXACT_TODO_cursor.md

## 1. **Does Elixact Actually Support What DSPEx Needs?**

### **A. Atom Type Support**

- **Claimed Limitation:**  
  `ELIXACT_TODO.md` says Elixact does not support `:atom` types (e.g., for enums like `:gemini`, `:openai`).
- **Reality in Code:**  
  - There is **no explicit `:atom` type** in `Elixact.Types` or the type system.
  - The only basic types are `:string`, `:integer`, `:float`, `:boolean`, and `:any`.
  - If you use a type like `:atom`, it is treated as a schema reference, not a primitive type.
  - There is **no validation logic for atom values** (e.g., `def validate(:atom, ...)` does not exist).
  - The `choices/1` constraint works for values, but only if the base type supports those values.

**Conclusion:**  
- **ELIXACT_TODO.md is correct:** Elixact does *not* natively support atom types as a primitive, so fields like `:default_provider` (which should be an atom) cannot be validated as atoms.

---

### **B. Union Type Support**

- **Claimed Limitation:**  
  Elixact cannot validate fields that accept multiple types (e.g., `string | {:system, env_var}`).
- **Reality in Code:**  
  - The type system and validator *do* support union types:  
    - `Types.union([Types.string(), ...])` and `{:union, ...}` are handled in both the type system and validator.
    - The validator will try each type in the union and accept if any match.
  - However, there is **no built-in support for tuple types** (e.g., `{:system, "ENV_VAR"}`) as a primitive.
  - If you want to support a union like `string | {:system, env_var}`, you would need to define a custom type or schema for the tuple.

**Conclusion:**  
- **Partial support:** Unions are supported, but not for arbitrary tuple types unless you define a custom schema/type for the tuple.

---

### **C. Map/Nested Map Validation**

- **Claimed Limitation:**  
  Elixact cannot validate the internal structure of nested maps (e.g., `rate_limit: %{requests_per_minute: 100}`).
- **Reality in Code:**  
  - The type system supports map types: `Types.map(key_type, value_type)`.
  - The validator will recursively validate keys and values.
  - However, **there is no support for validating specific keys with specific types** (e.g., a map with exactly `:requests_per_minute` and `:tokens_per_minute` as integer fields).
  - All keys/values are validated against the same type, not a schema for a specific map structure.

**Conclusion:**  
- **ELIXACT_TODO.md is correct:** Elixact supports maps, but not "object" maps with fixed keys and types (like a struct or schema).

---

### **D. Nil Handling for Optional Fields**

- **Claimed Limitation:**  
  Optional fields incorrectly accept `nil` values.
- **Reality in Code:**  
  - In the validator, if a field is missing and is optional, it is skipped.
  - If a field is present with `nil`, it is treated as missing and skipped if optional, otherwise triggers a required error.
  - There is **no explicit check to reject `nil` for optional fields if present**.

**Conclusion:**  
- **ELIXACT_TODO.md is correct:** The current logic does not reject `nil` for optional fields if present.

---

### **E. Custom Error Messages, Custom Validation Functions, and Wildcard Path Support**

- **Custom error messages:** Not supported per-field; only generic messages.
- **Custom validation functions:** No macro or API for user-defined validation logic.
- **Wildcard path support:** Not present; schemas are for fixed structures.

---

## 2. **Summary Table**

| Feature                        | Supported? | Notes                                                                 |
|------------------------------- |-----------|-----------------------------------------------------------------------|
| Atom type                      | ❌        | No native support; treated as schema ref                              |
| Union type                     | ✅ (partial) | Works for basic types, not for tuple/struct unless custom defined     |
| Map type (object/struct)       | ❌        | Only homogeneous key/value maps, not fixed-key objects                |
| Nil handling for optional      | ❌        | Does not reject `nil` for optional fields if present                  |
| Custom error messages          | ❌        | Only generic error messages                                           |
| Custom validation functions    | ❌        | No macro/API for user-defined validation                              |
| Wildcard path support          | ❌        | No support for dynamic/wildcard schema matching                       |

---

## 3. **What Works Well**

- Basic types (`:string`, `:integer`, `:float`, `:boolean`, `:any`)
- Arrays of any type
- Unions of basic types
- Map types with homogeneous key/value types
- Constraint macros (min/max, choices, etc.)
- Recursive validation for arrays, maps, and unions

---

## 4. **What Needs to be Added or Fixed**

- **Atom type**: Add `:atom` as a first-class type, with support for `choices/1`.
- **Tuple/struct/union**: Add tuple type support, or allow unions with tuple types.
- **Object map**: Add support for maps with fixed keys and types (object/struct validation).
- **Nil handling**: Explicitly reject `nil` for optional fields if present.
- **Custom error messages**: Allow per-field custom error messages.
- **Custom validation functions**: Allow user-defined validation logic.
- **Wildcard path support**: Allow schemas to match dynamic/wildcard paths.

---

## 5. **Conclusion**

- The limitations described in `ELIXACT_TODO.md` are accurate and reflect the current state of the Elixact codebase.
- Some features (like union types) are partially supported, but not to the level required for full DSPEx integration.
- The most critical missing features are atom type support, object map validation, and correct nil handling for optional fields.

---

**Next Steps:**  
- Use this report to guide Elixact enhancements.
- Prioritize adding atom type, tuple/object map support, and nil handling fixes.

 