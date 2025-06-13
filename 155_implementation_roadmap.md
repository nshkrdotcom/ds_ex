# DSPEx + Elixact Implementation Roadmap: Detailed Technical Guide

## Executive Summary

This document provides a concrete, step-by-step implementation roadmap for the elixact integration, complementing the comprehensive plan (153_copilot adjusted.md) with specific code changes, file modifications, and implementation sequences.

## Pre-Implementation Checklist

### Environment Setup
1. **Elixact Dependency**: Add to `mix.exs`
2. **Development Dependencies**: Add testing and benchmarking tools
3. **Documentation**: Set up ex_doc configuration for new modules
4. **CI/CD**: Update GitHub Actions or similar for new test patterns

### Risk Assessment & Mitigation
- **Backup Strategy**: Create git branch `feature/elixact-integration`
- **Rollback Plan**: Maintain compatibility layer indefinitely  
- **Performance Monitoring**: Establish baseline metrics
- **User Communication**: Prepare migration documentation

## Phase 1: Foundation Implementation (Week 1-2)

### Step 1.1: Add Elixact Dependency
**File**: `mix.exs`
```elixir
defp deps do
  [
    # Existing dependencies...
    {:elixact, "~> 0.1.2"},
    
    # Additional testing dependencies for integration
    {:stream_data, "~> 0.5", only: [:test, :dev]}, # For property testing
    {:benchee, "~> 1.1", only: [:test, :dev]},     # For performance testing
    {:ex_doc, "~> 0.29", only: :dev, runtime: false},
    # ... rest of existing deps
  ]
end
```

### Step 1.2: Create Core Schema Wrapper
**File**: `lib/dspex/schema.ex` (New)

Key implementation considerations:
- Must maintain exact compatibility with existing `DSPEx.Signature` behavior
- Should provide enhanced functionality without breaking changes
- Needs to handle both input and output field differentiation
- Must support JSON schema generation

**Critical Functions to Implement**:
```elixir
# Core behavior functions
def input_fields() - returns list of input field atoms
def output_fields() - returns list of output field atoms  
def fields() - returns all field atoms
def instructions() - returns schema description
def validate_inputs(map) - validates input data only
def validate_outputs(map) - validates output data only
def validate(map) - full validation
def dump(validated_data) - serialization
def json_schema() - JSON schema generation
```

### Step 1.3: Create Compatibility Layer
**File**: `lib/dspex/signature_compat.ex` (New)

This is critical for zero-breaking-change migration:
- Parse existing string signatures at compile time
- Generate elixact schemas dynamically
- Maintain struct compatibility
- Preserve field access patterns

### Step 1.4: Enhanced Error Handling
**File**: `lib/dspex/validation_error.ex` (New)

Structured error handling that provides:
- Field-level error paths
- Clear error messages
- Integration with elixact error format
- Backward compatibility with existing error handling

## Phase 2: Core Integration (Week 2-3)

### Step 2.1: Modify DSPEx.Signature
**File**: `lib/dspex/signature.ex` (Modified)

**Implementation Strategy**:
1. Add deprecation warnings for string-based signatures
2. Delegate to compatibility layer for string signatures
3. Add new elixact-based signature support
4. Maintain all existing behavior callbacks

**Key Changes**:
```elixir
# Add at top of module
@deprecated "String-based signatures are deprecated. Use DSPEx.Schema instead."
defmacro __using__(signature_string) when is_binary(signature_string) do
  IO.warn("""
  String-based signatures are deprecated and will be removed in DSPEx 2.0.
  
  Consider migrating to elixact-based schemas:
  
  Old:
    use DSPEx.Signature, "question -> answer"
  
  New:
    use DSPEx.Schema
    schema do
      input_field :question, :string, description: "The question to answer"
      output_field :answer, :string, description: "The answer to the question"
    end
  """)
  
  quote do
    use DSPEx.SignatureCompat, unquote(signature_string)
    @behaviour DSPEx.Signature
  end
end

# Add new macro for elixact-based signatures
defmacro __using__(:elixact) do
  quote do
    use DSPEx.Schema
    @behaviour DSPEx.Signature
  end
end
```

### Step 2.2: Enhance DSPEx.Predict
**File**: `lib/dspex/predict.ex` (Modified)

**Key Implementation Points**:
1. Add structured validation before LLM calls
2. Add structured validation after LLM responses
3. Maintain backward compatibility with existing signatures
4. Provide clear error handling for validation failures

**Critical Changes**:
```elixir
# In forward/3 function
defp validate_signature_inputs(signature, inputs) do
  cond do
    function_exported?(signature, :validate_inputs, 1) ->
      # New elixact-based validation
      case signature.validate_inputs(inputs) do
        :ok -> :ok
        {:error, errors} -> 
          {:error, {:validation_failed, :inputs, DSPEx.ValidationError.from_elixact_errors(errors, inputs)}}
      end
      
    function_exported?(signature, :input_fields, 0) ->
      # Legacy validation for string-based signatures
      validate_inputs_legacy(signature, inputs)
      
    true ->
      {:error, {:invalid_signature, "Signature must implement input validation"}}
  end
end

# Similar for output validation
defp validate_signature_outputs(signature, outputs) do
  # Implementation similar to input validation
end
```

### Step 2.3: Custom Types System
**File**: `lib/dspex/types.ex` (New)

Create reusable custom types that match DSPy patterns:
```elixir
defmodule DSPEx.Types do
  @moduledoc """
  Custom types for DSPEx schemas, providing DSPy-equivalent functionality.
  """
  
  defmodule ConfidenceScore do
    use Elixact.Type
    
    type :float, 
      min: 0.0, 
      max: 1.0,
      description: "Confidence score between 0.0 and 1.0"
  end
  
  defmodule ReasoningChain do
    use Elixact
    
    schema do
      field :steps, {:array, ReasoningStep}, 
        description: "Individual reasoning steps"
      field :conclusion, :string,
        description: "Final conclusion"
    end
  end
  
  defmodule ReasoningStep do
    use Elixact
    
    schema do
      field :step_number, :integer, min: 1
      field :description, :string, min_length: 1
      field :reasoning, :string, min_length: 1
    end
  end
end
```

## Phase 3: Adapter Enhancement (Week 3-4)

### Step 3.1: Modify Existing Adapters
**Files**: All files in `lib/dspex/adapters/`

**Implementation Strategy**:
1. Replace manual JSON schema construction with elixact generation
2. Add structured output validation
3. Maintain backward compatibility
4. Add comprehensive error handling

**Example for InstructorLite Gemini**:
**File**: `lib/dspex/adapters/instructor_lite_gemini.ex` (Modified)

**Key Changes**:
```elixir
# Replace manual schema construction (lines 112-138) with:
defp build_schema(signature) do
  if function_exported?(signature, :json_schema, 0) do
    # Use elixact-generated schema
    signature.json_schema()
  else
    # Fallback to legacy schema construction
    build_schema_legacy(signature)
  end
end

# Add structured validation
defp validate_structured_response(signature, response) do
  if function_exported?(signature, :validate_outputs, 1) do
    signature.validate_outputs(response)
  else
    # Legacy validation
    :ok
  end
end
```

### Step 3.2: Create New Structured Adapter
**File**: `lib/dspex/adapters/structured_output.ex` (New)

A new adapter specifically designed for elixact schemas:
- Automatic JSON schema generation
- Built-in validation
- Optimized for structured outputs
- Support for complex nested schemas

## Phase 4: Example & Teleprompter Enhancement (Week 4-5)

### Step 4.1: Enhance DSPEx.Example
**File**: `lib/dspex/example.ex` (Modified)

**Key Enhancements**:
1. Add validation for example inputs/outputs
2. Support structured examples with rich metadata
3. Maintain backward compatibility
4. Add example quality validation

### Step 4.2: Enhance Teleprompters
**Files**: `lib/dspex/teleprompter/*.ex` (Modified)

**SIMBA Enhancement**:
- Add example validation during optimization
- Use structured scoring with confidence metrics
- Validate generated examples against signatures
- Maintain performance while adding validation

**BootstrapFewShot Enhancement**:
- Validate generated examples
- Use structured prompts for example generation
- Add metadata to generated examples

## Phase 5: Migration Tools & Utilities (Week 5-6)

### Step 5.1: Migration Analysis Tool
**File**: `lib/mix/tasks/dspex.analyze_signatures.ex` (New)

```elixir
defmodule Mix.Tasks.Dspex.AnalyzeSignatures do
  use Mix.Task
  
  @shortdoc "Analyze DSPEx signatures for elixact migration opportunities"
  
  def run(args) do
    Mix.Task.run("compile")
    
    # Scan codebase for string-based signatures
    signatures = find_string_signatures()
    
    # Analyze complexity and migration recommendations  
    analysis = analyze_signatures(signatures)
    
    # Generate migration report
    generate_report(analysis, parse_options(args))
  end
  
  defp find_string_signatures do
    # Implementation to scan codebase
  end
  
  defp analyze_signatures(signatures) do
    # Implementation to analyze migration complexity
  end
  
  defp generate_report(analysis, opts) do
    # Implementation to generate migration report
  end
end
```

### Step 5.2: Automatic Conversion Tool
**File**: `lib/mix/tasks/dspex.convert_signature.ex` (New)

```elixir
defmodule Mix.Tasks.Dspex.ConvertSignature do
  use Mix.Task
  
  @shortdoc "Convert string-based signature to elixact schema"
  
  def run([file_path, signature_module]) do
    Mix.Task.run("compile")
    
    # Read existing file
    content = File.read!(file_path)
    
    # Parse and convert signature
    converted = convert_signature(content, signature_module)
    
    # Write converted file
    File.write!("#{file_path}.elixact", converted)
    
    # Show diff and migration instructions
    show_conversion_results(file_path, converted)
  end
end
```

## Phase 6: Advanced Integration Points (Week 6+)

### Step 6.1: Prompt Engineering Integration
**File**: `lib/dspex/prompt.ex` (New)

Support for structured prompt templates with validation:
```elixir
defmodule DSPEx.Prompt do
  use DSPEx.Schema
  
  schema do
    field :template, :string, required: true
    field :variables, {:map, :string}, default: %{}
    field :constraints, PromptConstraints, optional: true
  end
  
  def render(prompt, variables \\ %{}) do
    # Validate variables against template
    # Render template with validated variables
  end
end
```

### Step 6.2: Multi-Modal Support
**File**: `lib/dspex/types/media.ex` (New)

Rich media types for multi-modal AI:
```elixir
defmodule DSPEx.Types.Media do
  defmodule Image do
    use Elixact
    
    schema do
      field :data, :string, description: "Base64 encoded image data"
      field :format, ImageFormat, description: "Image format (JPEG, PNG, etc.)"
      field :dimensions, ImageDimensions, optional: true
    end
  end
  
  # Similar for Audio, Video, Document types
end
```

## Implementation Guidelines

### Code Quality Standards
1. **Documentation**: All new modules must have comprehensive @doc strings
2. **Type Specs**: All public functions must have @spec annotations  
3. **Testing**: Minimum 90% test coverage for new code
4. **Performance**: No more than 10% performance regression
5. **Compatibility**: Zero breaking changes to existing APIs

### Error Handling Patterns
1. **Structured Errors**: All validation errors must use DSPEx.ValidationError
2. **Error Paths**: Clear error propagation through the pipeline
3. **User-Friendly Messages**: Error messages must be actionable
4. **Logging**: Structured logging for debugging and monitoring

### Performance Considerations
1. **Lazy Validation**: Only validate when necessary
2. **Caching**: Cache JSON schemas to avoid regeneration
3. **Compilation**: Use macros to move work to compile time
4. **Benchmarking**: Continuous performance monitoring

### Migration Safety
1. **Feature Flags**: Use application config to enable/disable features
2. **Gradual Rollout**: Support mixed old/new signature usage
3. **Monitoring**: Track usage patterns and error rates
4. **Rollback**: Always maintain rollback capability

## Testing Implementation

### Test File Structure
```
test/
├── unit/
│   ├── dspex_schema_test.exs
│   ├── signature_compat_test.exs
│   ├── validation_error_test.exs
│   ├── custom_types_test.exs
│   └── migration_tools_test.exs
├── integration/
│   ├── predict_elixact_test.exs
│   ├── teleprompter_elixact_test.exs
│   └── adapter_structured_test.exs
├── property/
│   ├── schema_validation_properties.exs
│   └── json_schema_properties.exs
├── migration/
│   └── migration_validation_test.exs
└── benchmarks/
    └── validation_overhead_bench.exs
```

### Testing Commands
```bash
# Unit tests for specific phases
mix test test/unit/dspex_schema_test.exs       # Phase 1
mix test test/unit/predict_elixact_test.exs    # Phase 2  
mix test test/integration/                     # Phase 3+

# Property-based tests
mix test test/property/ --include property

# Migration validation
mix test test/migration/ --include migration

# Performance benchmarks
mix test test/benchmarks/ --include benchmark

# Full test suite
mix test --include integration --include property
```

## Deployment Strategy

### Versioning Strategy
- **v1.x**: Current version with backward compatibility
- **v1.y**: Introduce elixact with compatibility layer
- **v1.z**: Feature-complete elixact integration
- **v2.0**: Optional deprecation of string signatures (future)

### Feature Rollout
1. **Internal Testing**: Use in DSPEx development first
2. **Beta Users**: Select power users for early testing
3. **Documentation**: Comprehensive migration guides
4. **Community**: Examples and tutorials
5. **Full Release**: Complete documentation and tooling

### Success Metrics
- **Adoption Rate**: % of signatures migrated to elixact
- **Error Rate**: Validation error frequency
- **Performance**: Response time and throughput metrics
- **Developer Satisfaction**: Migration experience feedback

## Risk Mitigation

### Technical Risks
1. **Breaking Changes**: Comprehensive compatibility testing
2. **Performance Impact**: Continuous benchmarking
3. **Complexity**: Gradual introduction and clear documentation
4. **Dependencies**: Pin elixact version and monitor updates

### Process Risks
1. **Timeline Slippage**: Prioritize core functionality first
2. **Resource Constraints**: Focus on essential features
3. **User Resistance**: Clear migration benefits and tooling
4. **Quality Issues**: Extensive testing and code review

## Conclusion

This implementation roadmap provides the detailed technical guidance needed to successfully integrate elixact into DSPEx while maintaining backward compatibility and achieving the comprehensive feature parity outlined in the main integration plan. The phased approach allows for incremental validation and risk mitigation throughout the integration process.

The combination of this roadmap with the comprehensive plan (153_copilot adjusted.md) and testing strategy (154_testing_integration_validation.md) provides a complete blueprint for transforming DSPEx into a robust, type-safe framework that matches and exceeds the capabilities of the original DSPy implementation.
