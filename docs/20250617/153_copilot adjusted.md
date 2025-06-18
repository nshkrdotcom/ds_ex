# DSPEx + Elixact Integration Plan: A Comprehensive Technical Roadmap

## Executive Summary

After analyzing the current DSPEx architecture and the elixact library capabilities, this plan outlines a strategic integration that will transform DSPEx from a clever string-parsing system into a robust, type-safe, and declarative framework that rivals the original DSPy's pydantic-based architecture.

**Core Transformation**: Replace string-based signature parsing (`"question -> answer"`) with elixact's declarative schema DSL, gaining automatic validation, JSON schema generation, and type safety while maintaining backward compatibility.

## Strategic Objectives

### 1. **Comprehensive Type Safety & Validation**
- Move from runtime string parsing to compile-time schema validation
- Automatic input/output validation with structured error reporting
- Type-safe field access and manipulation across all framework components
- Validation for prompt templates, LM configurations, and retrieval systems
- Structured validation for evaluation metrics and benchmark configurations

### 2. **Universal Structured Output Enhancement**
- Eliminate manual JSON schema construction in adapters
- Leverage elixact's automatic JSON schema generation for LLM structured outputs
- Support complex nested schemas and custom types for multi-modal data
- Automatic schema generation for streaming responses and tool calls
- Comprehensive validation for API requests/responses and distributed tasks

### 3. **Enhanced Developer Experience**
- Rich IDE support with compile-time field validation
- Clear, declarative signature definitions with comprehensive metadata
- Comprehensive error messages with path information and context
- Self-documenting schemas with automatic documentation generation
- Type-safe configuration management for all system components

### 4. **Enterprise-Grade Robustness**
- Structured error handling throughout the pipeline
- Validation at every data transformation point
- Consistent data shapes across the entire framework
- Comprehensive audit logging and security policy validation
- Resource quota enforcement and cost tracking
- Version control and migration support for schema evolution

## Detailed Technical Analysis

### Current Architecture Assessment

**Strengths of Current Implementation:**
- Elegant string-based DSL: `"question -> answer"`
- Working teleprompter implementations (SIMBA, BootstrapFewShot, Beacon)
- Solid foundation with telemetry and error handling
- Comprehensive test suite with mock/fallback/live modes

**Pain Points Addressed by Elixact:**
- Manual JSON schema construction in adapters (lines 112-138 in `instructor_lite_gemini.ex`)
- Limited field metadata support (no descriptions, examples, constraints)
- Runtime-only validation with basic error messages
- Fragile string parsing that can fail at runtime
- No IDE autocomplete for signature fields
- Lack of custom type system for domain-specific types (reasoning chains, confidence scores)
- No configuration validation for teleprompters and other components
- Manual data serialization and deserialization
- Limited error context and path information
- No support for complex nested schemas
- Missing field-level validators and constraints
- Inability to generate comprehensive documentation from schemas
- No validation for prompt templates and variable substitution
- Lack of type-safe LM configuration and response parsing
- Missing validation for retrieval system queries and results
- No structured evaluation framework with metric validation
- Absence of streaming response validation and chunking support
- Limited multi-modal data type support (images, audio, video)
- No plugin system with configuration validation
- Missing caching validation and data integrity checks
- Lack of distributed processing task validation
- No API request/response validation framework
- Missing workflow and pipeline validation system
- Absence of monitoring and observability data validation
- No security policy and access control validation
- Missing version control and schema migration support
- Lack of comprehensive testing framework validation
- No resource management and quota enforcement validation

### Comprehensive Elixact Feature Mapping

Based on the analysis of all 38+ categories of Pydantic usage in DSPy, here's the complete mapping:

| DSPy Pydantic Pattern | Current DSPEx Pattern | Elixact Equivalent | Benefits |
|---------------------|---------------------|-------------------|----------|
| **Core Signature System** |
| `class Signature(BaseModel)` | `use DSPEx.Signature, "question -> answer"` | `use Elixact` with `schema do...end` | Type safety, metadata, validation |
| `InputField()`, `OutputField()` | String parsing + field categorization | `input_field/3`, `output_field/3` macros | Rich field definitions with constraints |
| `model_json_schema()` | Manual JSON schema building | `Elixact.JsonSchema.from_schema/1` | Automatic, comprehensive schemas |
| **Custom Types & Validation** |
| `class CustomType(BaseModel)` | Limited custom type support | `use Elixact.Type` | Reusable, validated custom types |
| `@model_validator(mode="before")` | Manual validation in adapters | Built-in field constraints + custom validators | Declarative validation rules |
| `@field_validator` | Runtime validation only | Compile-time + runtime validation | Early error detection |
| **Data Processing** |
| `model_dump()` | Manual map conversion | Automatic serialization via `validate/1` | Consistent data transformation |
| `model_validate()` | Manual struct creation | `MySchema.validate/1` | Type coercion and validation |
| `pydantic.create_model()` | Limited runtime type creation | Macro-based schema generation | Compile-time safety with flexibility |
| **Configuration Management** |
| `class Config(BaseModel)` | Keyword lists and maps | Elixact schemas for configuration | Type-safe configuration |
| **Structured Outputs** |
| Dynamic model creation for OpenAI | Manual schema construction | Automatic JSON schema generation | Robust LLM integration |
| **Error Handling** |
| `ValidationError` with paths | Basic error tuples | `Elixact.ValidationError` with structured errors | Rich error reporting |
| **Prompt Engineering & Templates** |
| `class PromptTemplate(BaseModel)` | String-based templates | Elixact schema with template validation | Type-safe prompt management |
| Template variable validation | Manual substitution | Field constraints and validators | Automatic variable validation |
| **Language Model Integration** |
| `class LMUsage(BaseModel)` | Basic usage tracking | Structured usage schemas | Comprehensive LM monitoring |
| LM configuration validation | Keyword-based config | Type-safe LM configuration schemas | Robust LM parameter validation |
| **Retrieval System** |
| `class RetrievalResult(BaseModel)` | Manual result handling | Structured retrieval schemas | Type-safe retrieval pipeline |
| Query parameter validation | Ad-hoc validation | Schema-based query validation | Robust search parameter handling |
| **Evaluation Framework** |
| `class EvaluationResult(BaseModel)` | Basic evaluation tracking | Comprehensive evaluation schemas | Structured evaluation pipeline |
| Metric configuration | Manual metric setup | Type-safe metric configuration | Robust evaluation metrics |
| **Streaming & Real-time** |
| `class StreamChunk(BaseModel)` | Basic streaming support | Structured streaming schemas | Type-safe streaming pipeline |
| Status message validation | Manual status handling | Schema-based status validation | Robust streaming status management |
| **Multi-modal Support** |
| `class MediaFile(BaseModel)` | Limited media support | Rich media type system | Comprehensive media validation |
| Encoding validation | Manual encoding checks | Schema-based encoding validation | Robust media processing |
| **Plugin & Extension System** |
| `class PluginConfig(BaseModel)` | No plugin system | Plugin configuration schemas | Type-safe plugin management |
| Extension validation | No extension support | Schema-based extension validation | Robust extension system |
| **Caching & Persistence** |
| `class CacheEntry(BaseModel)` | Basic caching | Structured cache schemas | Type-safe caching system |
| Data integrity validation | Manual integrity checks | Schema-based integrity validation | Robust data persistence |
| **Distributed Processing** |
| `class DistributedTask(BaseModel)` | No distributed support | Distributed task schemas | Type-safe distributed computing |
| Worker configuration | No worker management | Schema-based worker configuration | Robust distributed processing |
| **API Integration** |
| `class APIRequest(BaseModel)` | Manual API handling | Structured API schemas | Type-safe API integration |
| `class APIResponse(BaseModel)` | Basic response handling | Comprehensive response schemas | Robust API response management |
| **Workflow Management** |
| `class PipelineStep(BaseModel)` | Basic pipeline support | Workflow step schemas | Type-safe pipeline management |
| Dependency validation | Manual dependency checks | Schema-based dependency validation | Robust workflow orchestration |
| **Monitoring & Observability** |
| `class PerformanceMetric(BaseModel)` | Basic telemetry | Structured monitoring schemas | Comprehensive observability |
| Log entry validation | Manual logging | Schema-based log validation | Robust structured logging |
| **Security & Access Control** |
| `class SecurityPolicy(BaseModel)` | No security framework | Security policy schemas | Type-safe access control |
| Permission validation | Manual permission checks | Schema-based permission validation | Robust security management |
| **Version Control & Migrations** |
| `class ModelVersion(BaseModel)` | No versioning support | Schema versioning system | Type-safe schema evolution |
| Migration validation | No migration support | Schema-based migration validation | Robust schema migrations |
| **Testing & QA** |
| `class TestCase(BaseModel)` | Basic testing | Structured test schemas | Type-safe testing framework |
| Mock data generation | Manual mock creation | Schema-based mock generation | Robust test data management |
| **Resource Management** |
| `class ResourceQuota(BaseModel)` | No resource management | Resource management schemas | Type-safe resource allocation |
| Cost tracking | Manual cost tracking | Schema-based cost validation | Robust resource monitoring |

## Implementation Strategy

### Phase 1: Foundation & Compatibility Layer (Week 1-2)

#### 1.1 Add Elixact Dependency
```elixir
# mix.exs
defp deps do
  [
    # ... existing deps
    {:elixact, "~> 0.1.2"},
    # ... rest
  ]
end
```

#### 1.2 Create DSPEx.Schema Wrapper
**File: `lib/dspex/schema.ex`** (New)
```elixir
defmodule DSPEx.Schema do
  @moduledoc """
  DSPEx wrapper around Elixact providing DSPy-style field semantics.
  
  Provides input_field/3 and output_field/3 macros to distinguish between
  input and output fields, which is crucial for DSPEx's operation.
  """
  
  defmacro __using__(opts \\ []) do
    quote do
      use Elixact, unquote(opts)
      import DSPEx.Schema
      
      @doc "Get all input field names"
      def input_fields do
        __schema__(:fields)
        |> Enum.filter(fn {_name, meta} -> 
          Map.get(meta, :__dspex_field_type) == :input 
        end)
        |> Enum.map(fn {name, _meta} -> name end)
      end
      
      @doc "Get all output field names"  
      def output_fields do
        __schema__(:fields)
        |> Enum.filter(fn {_name, meta} -> 
          Map.get(meta, :__dspex_field_type) == :output 
        end)
        |> Enum.map(fn {name, _meta} -> name end)
      end
      
      @doc "Get all field names"
      def fields do
        __schema__(:fields) |> Enum.map(fn {name, _meta} -> name end)
      end
      
      @doc "Get signature instructions from schema description"
      def instructions do
        __schema__(:description) || ""
      end
      
      @doc "Validate inputs against schema"
      def validate_inputs(inputs) when is_map(inputs) do
        input_field_names = input_fields()
        input_data = Map.take(inputs, input_field_names)
        
        # Create a temporary schema with only input fields for validation
        case validate_partial(input_data, input_field_names) do
          {:ok, _} -> :ok
          {:error, errors} -> {:error, {:missing_inputs, extract_missing_fields(errors)}}
        end
      end
      
      @doc "Validate outputs against schema"
      def validate_outputs(outputs) when is_map(outputs) do
        output_field_names = output_fields()
        output_data = Map.take(outputs, output_field_names)
        
        case validate_partial(output_data, output_field_names) do
          {:ok, _} -> :ok
          {:error, errors} -> {:error, {:missing_outputs, extract_missing_fields(errors)}}
        end
      end
      
      @doc "Full validation equivalent to pydantic's model_validate()"
      def validate(data) when is_map(data) do
        case Elixact.Validator.validate_schema(__MODULE__, data) do
          {:ok, validated_data} -> {:ok, validated_data}
          {:error, errors} -> {:error, errors}
        end
      end
      
      @doc "Serialize to map equivalent to pydantic's model_dump()"
      def dump(validated_data) when is_map(validated_data) do
        # Elixact returns validated maps directly, matching pydantic's model_dump behavior
        validated_data
      end
      
      @doc "Generate JSON schema equivalent to pydantic's model_json_schema()"
      def json_schema do
        Elixact.JsonSchema.from_schema(__MODULE__)
      end
      
      # Private helpers
      defp validate_partial(data, required_fields) do
        # Implementation details for partial validation
        Elixact.Validator.validate_schema(__MODULE__, data)
      end
      
      defp extract_missing_fields(errors) do
        # Extract missing field names from validation errors
        errors
        |> Enum.filter(fn error -> error.code == :required end)
        |> Enum.map(fn error -> List.last(error.path) end)
      end
    end
  end
  
  @doc "Define an input field with DSPEx semantics and rich metadata"
  defmacro input_field(name, type, opts \\ []) do
    quote do
      opts = unquote(opts)
      |> Keyword.put(:__dspex_field_type, :input)
      |> Keyword.put(:required, true)  # Inputs are required by default
      
      field unquote(name), unquote(type), opts
    end
  end
  
  @doc "Define an output field with DSPEx semantics and rich metadata"
  defmacro output_field(name, type, opts \\ []) do
    quote do
      opts = unquote(opts)
      |> Keyword.put(:__dspex_field_type, :output)
      |> Keyword.put(:required, false)  # Outputs are optional until generated
      
      field unquote(name), unquote(type), opts
    end
  end
  
  @doc "Field validator macro similar to pydantic's @field_validator"
  defmacro field_validator(field_name, opts \\ [], do: block) do
    quote do
      # This would integrate with elixact's validation system
      # to provide field-level validation similar to pydantic
      def unquote(:"validate_#{field_name}")(value) do
        unquote(block)
      end
    end
  end
end
```

#### 1.3 Create Backward Compatibility Layer
**File: `lib/dspex/signature_compat.ex`** (New)
```elixir
defmodule DSPEx.SignatureCompat do
  @moduledoc """
  Backward compatibility layer for existing string-based signatures.
  
  Provides a bridge between old string-based signatures and new elixact-based ones.
  Eventually, this module will be deprecated in favor of direct elixact usage.
  """
  
  defmacro __using__(signature_string) when is_binary(signature_string) do
    # Parse the string signature
    {input_fields, output_fields} = DSPEx.Signature.Parser.parse(signature_string)
    all_fields = input_fields ++ output_fields
    
    quote do
      use DSPEx.Schema
      
      # Generate schema dynamically from parsed string
      schema do
        unquote_splicing(
          Enum.map(input_fields, fn field ->
            quote do
              input_field unquote(field), :string, 
                description: "Input field #{unquote(field)}"
            end
          end)
        )
        
        unquote_splicing(
          Enum.map(output_fields, fn field ->
            quote do
              output_field unquote(field), :string,
                description: "Output field #{unquote(field)}"
            end
          end)
        )
        
        # Add configuration to maintain compatibility with existing behavior
        config do
          strict false  # Allow extra fields for backward compatibility
        end
      end
      
      # Maintain struct compatibility
      defstruct unquote(all_fields |> Enum.map(&{&1, nil}))
      
      @type t :: %__MODULE__{
        unquote_splicing(
          all_fields |> Enum.map(fn field ->
            {field, quote(do: any())}
          end)
        )
      }
      
      def new(fields \\ %{}) when is_map(fields) do
        struct(__MODULE__, fields)
      end
    end
  end
end
```

### Phase 2: Core Integration (Week 2-3)

#### 2.1 Refactor DSPEx.Signature
**File: `lib/dspex/signature.ex`** (Modified)
```elixir
defmodule DSPEx.Signature do
  @moduledoc """
  DSPEx Signature behavior and utilities.
  
  DEPRECATED: String-based signatures are deprecated in favor of elixact-based schemas.
  Use `DSPEx.Schema` for new signatures.
  
  ## Migration Path
  
  Old:
  ```elixir
  defmodule QASignature do
    use DSPEx.Signature, "question -> answer"
  end
  ```
  
  New:
  ```elixir
  defmodule QASignature do
    use DSPEx.Schema
    
    @moduledoc "Answer questions with detailed reasoning"
    schema @moduledoc do        input_field :question, :string, 
          description: "The question to be answered",
          min_length: 1,
          example: "What is the capital of France?"
          
        output_field :answer, :string,
          description: "A comprehensive answer to the question",
          min_length: 1
          
        output_field :reasoning, DSPEx.Types.ReasoningChain,
          description: "Step-by-step reasoning leading to the answer",
          optional: true
          
        output_field :confidence, DSPEx.Types.ConfidenceScore,
          description: "Confidence level in the answer (0.0 to 1.0)",
          default: 0.5
          
        # Schema-level configuration
        config do
          title "Question Answering Signature"
          description "Provides comprehensive answers with reasoning and confidence"
          strict true  # Reject extra fields
        end
    end
  end
  ```
  """
  
  # Existing behavior callbacks remain the same
  @callback instructions() :: String.t()
  @callback input_fields() :: [atom()]
  @callback output_fields() :: [atom()]
  @callback fields() :: [atom()]
  
  # Legacy macro now delegates to compatibility layer
  defmacro __using__(signature_string) when is_binary(signature_string) do
    quote do
      use DSPEx.SignatureCompat, unquote(signature_string)
      @behaviour DSPEx.Signature
    end
  end
  
  # ... rest of existing extend/2 functionality remains unchanged
end
```

#### 2.2 Enhance DSPEx.Predict Integration
**File: `lib/dspex/predict.ex`** (Modified)
```elixir
defmodule DSPEx.Predict do
  # ... existing module doc and struct definition
  
  @impl DSPEx.Program
  def forward(program, inputs, opts \\ []) do
    with {:ok, _} <- validate_signature_inputs(program.signature, inputs),
         {:ok, {params, adapter_opts}} <- format_adapter_messages(program, inputs),
         {:ok, raw_response} <- make_request(program.client, params, opts),
         {:ok, parsed_outputs} <- parse_adapter_response(program, raw_response, adapter_opts),
         {:ok, _} <- validate_signature_outputs(program.signature, parsed_outputs) do
      {:ok, parsed_outputs}
    else
      error -> handle_prediction_error(error, program, inputs)
    end
  end
  
  # New: Robust input validation using elixact if available
  defp validate_signature_inputs(signature, inputs) do
    cond do
      function_exported?(signature, :validate_inputs, 1) ->
        # New elixact-based validation
        signature.validate_inputs(inputs)
        
      function_exported?(signature, :input_fields, 0) ->
        # Legacy validation for string-based signatures
        required_inputs = MapSet.new(signature.input_fields())
        provided_inputs = MapSet.new(Map.keys(inputs))
        missing = MapSet.difference(required_inputs, provided_inputs)
        
        if MapSet.size(missing) == 0 do
          :ok
        else
          {:error, {:missing_inputs, MapSet.to_list(missing)}}
        end
        required_inputs = MapSet.new(signature.input_fields())
        provided_inputs = MapSet.new(Map.keys(inputs))
        missing = MapSet.difference(required_inputs, provided_inputs)
        
        if MapSet.size(missing) == 0 do
          :ok
        else
          {:error, {:missing_inputs, MapSet.to_list(missing)}}
        end
        
      true ->
        {:error, {:invalid_signature, "Signature must implement input validation"}}
    end
  end
  
  # New: Robust output validation
  defp validate_signature_outputs(signature, outputs) do
    cond do
      function_exported?(signature, :validate_outputs, 1) ->
        signature.validate_outputs(outputs)
        
      function_exported?(signature, :output_fields, 0) ->
        # Legacy validation - just check presence
        required_outputs = MapSet.new(signature.output_fields())
        provided_outputs = MapSet.new(Map.keys(outputs))
        missing = MapSet.difference(required_outputs, provided_outputs)
        
        if MapSet.size(missing) == 0 do
          :ok
        else
          {:error, {:missing_outputs, MapSet.to_list(missing)}}
        end
        required_outputs = MapSet.new(signature.output_fields())
        provided_outputs = MapSet.new(Map.keys(outputs))
        missing = MapSet.difference(required_outputs, provided_outputs)
        
        if MapSet.size(missing) == 0 do
          :ok
        else
          {:error, {:missing_outputs, MapSet.to_list(missing)}}
        end
        
      true ->
        {:error, {:invalid_signature, "Signature must implement output validation"}}
    end
  end
  
  # ... rest of implementation
end
```

### Phase 3: Adapter Enhancement (Week 3-4)

#### 3.1 Transform InstructorLite Adapter
**File: `lib/dspex/adapters/instructor_lite_gemini.ex`** (Major Refactor)
```elixir
defmodule DSPEx.Adapters.InstructorLiteGemini do
  @moduledoc """
  Enhanced DSPEx adapter using InstructorLite with automatic JSON schema generation.
  
  This adapter now leverages elixact's JSON schema generation capabilities,
  eliminating manual schema construction and supporting complex nested types.
  """
  
  def format_messages(signature, demos, inputs) do
    with {:ok, question_text} <- build_question_text(signature, inputs, demos),
         {:ok, json_schema} <- get_signature_json_schema(signature) do
      
      contents = [%{role: "user", parts: [%{text: question_text}]}]
      params = %{contents: contents}
      
      instructor_opts = [
        json_schema: json_schema,
        adapter: InstructorLite.Adapters.Gemini,
        adapter_context: [
          model: get_gemini_model(),
          api_key: get_gemini_api_key()
        ],
        max_retries: 1
      ]
      
      {:ok, {params, instructor_opts}}
    end
  end
  
  def parse_response(signature, instructor_result) do
    case instructor_result do
      {:ok, parsed_data} when is_map(parsed_data) ->
        # Use elixact validation if available
        if function_exported?(signature, :validate, 1) do
          case signature.validate(parsed_data) do
            {:ok, validated_data} -> {:ok, validated_data}
            {:error, errors} -> {:error, {:validation_failed, errors}}
          end
        else
          # Legacy handling for string-based signatures
          result_map = struct_to_map(parsed_data)
          output_fields = signature.output_fields()
          
          if all_fields_present?(result_map, output_fields) do
            {:ok, result_map}
          else
            {:error, {:missing_fields, output_fields, Map.keys(result_map)}}
          end
        end
        
      {:error, reason} ->
        {:error, {:instructor_lite_error, reason}}
    end
  end
  
  # New: Automatic JSON schema generation
  defp get_signature_json_schema(signature) do
    cond do
      function_exported?(signature, :json_schema, 0) ->
        # Elixact-based signature
        {:ok, signature.json_schema()}
        
      function_exported?(signature, :output_fields, 0) ->
        # Legacy string-based signature - fall back to manual construction
        build_json_schema_legacy(signature)
        
      true ->
        {:error, {:invalid_signature, "Cannot generate JSON schema"}}
    end
  end
  
  # Legacy fallback (eventually to be removed)
  defp build_json_schema_legacy(signature) do
    # ... existing manual schema construction
    # This maintains backward compatibility
  end
  
  # ... rest of implementation
end
```

#### 3.2 Create New Structured Prediction Module
**File: `lib/dspex/predict_structured.ex`** (Enhanced)
```elixir
defmodule DSPEx.PredictStructured do
  @moduledoc """
  Enhanced structured prediction with full elixact integration.
  
  This module now automatically detects elixact schemas and provides
  rich validation and error handling capabilities.
  """
  
  use DSPEx.Program
  
  @enforce_keys [:signature, :client]
  defstruct [:signature, :client, :adapter, :instruction, demos: []]
  
  def new(signature, client, opts \\ []) do
    # Validate that the signature supports structured output
    unless supports_structured_output?(signature) do
      raise ArgumentError, """
      Signature must support structured output generation.
      Use an elixact-based signature with DSPEx.Schema, or ensure
      the signature implements the required callbacks.
      """
    end
    
    adapter = Keyword.get(opts, :adapter, DSPEx.Adapters.InstructorLiteGemini)
    
    %__MODULE__{
      signature: signature,
      client: client,
      adapter: adapter,
      instruction: Keyword.get(opts, :instruction),
      demos: Keyword.get(opts, :demos, [])
    }
  end
  
  @impl DSPEx.Program
  def forward(program, inputs, opts \\ []) do
    # Enhanced validation with elixact support
    with {:ok, validated_inputs} <- validate_and_coerce_inputs(program.signature, inputs),
         {:ok, structured_response} <- generate_structured_response(program, validated_inputs, opts),
         {:ok, validated_outputs} <- validate_and_coerce_outputs(program.signature, structured_response) do
      {:ok, validated_outputs}
    else
      error -> handle_structured_error(error, program, inputs)
    end
  end
  
  defp supports_structured_output?(signature) do
    # Check if signature has elixact capabilities
    function_exported?(signature, :json_schema, 0) or
    function_exported?(signature, :output_fields, 0)
  end
  
  defp validate_and_coerce_inputs(signature, inputs) do
    if function_exported?(signature, :validate, 1) do
      # Full elixact validation with coercion
      case signature.validate(inputs) do
        {:ok, coerced_data} -> {:ok, coerced_data}
        {:error, errors} -> {:error, {:input_validation_failed, errors}}
      end
    else
      # Legacy validation
      case signature.validate_inputs(inputs) do
        :ok -> {:ok, inputs}
        error -> error
      end
    end
  end
  
  defp validate_and_coerce_outputs(signature, outputs) do
    if function_exported?(signature, :validate, 1) do
      # Create a map with only output fields for validation
      output_data = Map.take(outputs, signature.output_fields())
      
      case signature.validate(output_data) do
        {:ok, coerced_data} -> {:ok, coerced_data}
        {:error, errors} -> {:error, {:output_validation_failed, errors}}
      end
    else
      # Legacy validation
      case signature.validate_outputs(outputs) do
        :ok -> {:ok, outputs}
        error -> error
      end
    end
  end
  
  # ... rest of implementation
end
```

### Phase 4: Example & Teleprompter Enhancement (Week 4-5)

#### 4.0 Configuration Schema Management
**File: `lib/dspex/config.ex`** (New - following pydantic patterns)
```elixir
defmodule DSPEx.Config do
  @moduledoc """
  Configuration schemas using elixact, similar to pydantic BaseModel for configuration.
  
  Provides type-safe configuration for teleprompters, clients, and other components.
  """
  
  defmodule TeleprompterConfig do
    use DSPEx.Schema
    
    @moduledoc "Configuration for teleprompter operations"
    schema @moduledoc do
      input_field :max_iterations, :integer, 
        description: "Maximum optimization iterations",
        default: 10,
        gt: 0,
        lt: 100
        
      input_field :batch_size, :integer,
        description: "Batch size for processing examples",
        default: 32,
        gt: 0
        
      input_field :temperature, :float,
        description: "Temperature for sampling",
        default: 0.2,
        ge: 0.0,
        le: 2.0
        
      input_field :strategy_weights, :map,
        description: "Weights for different optimization strategies",
        default: %{},
        optional: true
        
      config do
        title "Teleprompter Configuration"
        strict true
      end
    end
    
    # Custom validator similar to pydantic's @model_validator
    def validate_strategy_weights(%{strategy_weights: weights} = config) 
        when is_map(weights) do
      total_weight = weights |> Map.values() |> Enum.sum()
      
      if abs(total_weight - 1.0) < 0.001 do
        {:ok, config}
      else
        {:error, [%{field: :strategy_weights, code: :invalid_sum, 
                   message: "Strategy weights must sum to 1.0"}]}
      end
    end
    
    def validate_strategy_weights(config), do: {:ok, config}
  end
  
  defmodule ClientConfig do
    use DSPEx.Schema
    
    @moduledoc "Configuration for LLM clients"
    schema @moduledoc do
      input_field :provider, :atom,
        description: "LLM provider (:openai, :anthropic, :gemini)",
        choices: [:openai, :anthropic, :gemini]
        
      input_field :model, :string,
        description: "Model identifier",
        min_length: 1
        
      input_field :api_key, :string,
        description: "API key for the provider",
        min_length: 1
        
      input_field :max_tokens, :integer,
        description: "Maximum tokens in response",
        default: 1000,
        gt: 0
        
      input_field :timeout_ms, :integer,
        description: "Request timeout in milliseconds",
        default: 30_000,
        gt: 0
        
      config do
        title "LLM Client Configuration"
        strict true
      end
    end
  end
end
```

#### 4.1 Schema-Aware Example Structure
**File: `lib/dspex/example.ex`** (Enhanced)
```elixir
defmodule DSPEx.Example do
  @moduledoc """
  Enhanced Example structure with schema awareness and validation.
  
  Now supports automatic validation against signature schemas and
  intelligent input/output field detection.
  """
  
  @enforce_keys [:data]
  defstruct [:data, :input_keys, :signature_module]
  
  @type t :: %__MODULE__{
    data: map(),
    input_keys: MapSet.t(atom()) | nil,
    signature_module: module() | nil
  }
  
  def new(data, opts \\ []) when is_map(data) do
    signature_module = Keyword.get(opts, :signature)
    
    input_keys = case signature_module do
      nil -> 
        # Legacy: require explicit input_keys
        MapSet.new(Keyword.get(opts, :input_keys, []))
      module when is_atom(module) ->
        # Auto-detect from signature
        if function_exported?(module, :input_fields, 0) do
          MapSet.new(module.input_fields())
        else
          MapSet.new([])
        end
    end
    
    %__MODULE__{
      data: data,
      input_keys: input_keys,
      signature_module: signature_module
    }
  end
  
  @doc "Create example with automatic signature detection"
  def from_signature(signature_module, data) when is_atom(signature_module) and is_map(data) do
    # Validate the data against the signature if possible
    validated_data = case function_exported?(signature_module, :validate, 1) do
      true ->
        case signature_module.validate(data) do
          {:ok, validated} -> validated
          {:error, _} -> data # Use original data if validation fails
        end
      false ->
        data
    end
    
    new(validated_data, signature: signature_module)
  end
  
  @doc "Get inputs based on signature or input_keys"
  def inputs(%__MODULE__{data: data, signature_module: sig, input_keys: keys}) do
    cond do
      sig && function_exported?(sig, :input_fields, 0) ->
        Map.take(data, sig.input_fields())
      keys && MapSet.size(keys) > 0 ->
        Map.take(data, MapSet.to_list(keys))
      true ->
        # Default: assume all keys are inputs
        data
    end
  end
  
  @doc "Get outputs based on signature or remaining keys"
  def outputs(%__MODULE__{data: data, signature_module: sig, input_keys: keys}) do
    cond do
      sig && function_exported?(sig, :output_fields, 0) ->
        Map.take(data, sig.output_fields())
      keys && MapSet.size(keys) > 0 ->
        output_keys = data |> Map.keys() |> MapSet.new() |> MapSet.difference(keys)
        Map.take(data, MapSet.to_list(output_keys))
      true ->
        # Default: empty outputs
        %{}
    end
  end
  
  @doc "Validate example against its signature"
  def validate(%__MODULE__{data: data, signature_module: sig}) when is_atom(sig) do
    if function_exported?(sig, :validate, 1) do
      sig.validate(data)
    else
      # Legacy validation
      with :ok <- sig.validate_inputs(inputs(%__MODULE__{data: data, signature_module: sig})),
           :ok <- sig.validate_outputs(outputs(%__MODULE__{data: data, signature_module: sig})) do
        :ok
      end
    end
  end
  
  def validate(_example), do: {:error, :no_signature}
  
  # ... rest of existing functions with schema awareness
end
```

#### 4.2 Enhanced SIMBA with Schema Validation
**File: `lib/dspex/teleprompter/simba.ex`** (Enhanced validation points)
```elixir
defmodule DSPEx.Teleprompter.SIMBA do
  # ... existing implementation
  
  # Enhanced example validation in trajectory collection
  defp collect_trajectory(program, example, opts) do
    # Validate example against program signature before execution
    case DSPEx.Example.validate(example) do
      :ok ->
        execute_trajectory(program, example, opts)
      {:error, validation_errors} ->
        emit_telemetry([:simba, :trajectory, :validation_failed], %{}, %{
          errors: validation_errors,
          example_id: Map.get(example.data, :id, "unknown")
        })
        {:error, {:invalid_example, validation_errors}}
    end
  end
  
  # Enhanced example generation with automatic validation
  defp generate_validated_examples(signature, base_examples, num_needed) do
    Stream.repeatedly(fn -> generate_example_candidate(signature, base_examples) end)
    |> Stream.map(fn candidate ->
      case DSPEx.Example.from_signature(signature, candidate) do
        %DSPEx.Example{} = example ->
          case DSPEx.Example.validate(example) do
            :ok -> {:ok, example}
            {:error, _} -> :error
          end
        _ -> :error
      end
    end)
    |> Stream.filter(fn result -> match?({:ok, _}, result) end)
    |> Stream.map(fn {:ok, example} -> example end)
    |> Enum.take(num_needed)
  end
  
  # ... rest of implementation with validation checkpoints
end
```

### Phase 6: Advanced Integration Points (Week 11-12)

#### 6.1 Prompt Engineering System
**File: `lib/dspex/prompt.ex`** (New)
```elixir
defmodule DSPEx.Prompt do
  @moduledoc """
  Comprehensive prompt engineering system with elixact validation.
  
  Provides type-safe prompt templates, variable validation, and constraint enforcement.
  """
  
  defmodule Template do
    use DSPEx.Schema
    
    @moduledoc "Prompt template with variable validation"
    schema @moduledoc do
      input_field :template, :string,
        description: "Template string with {{variable}} placeholders",
        min_length: 1,
        pattern: ~r/.*\{\{.*\}\}.*/
        
      input_field :variables, :map,
        description: "Variables to substitute in template",
        default: %{}
        
      input_field :constraints, :map,
        description: "Constraints for template variables",
        default: %{},
        optional: true
        
      config do
        title "Prompt Template"
        strict true
      end
    end
    
    def validate_template_variables(%{template: template, variables: variables} = config) do
      required_vars = extract_template_variables(template)
      provided_vars = MapSet.new(Map.keys(variables))
      missing_vars = MapSet.difference(required_vars, provided_vars)
      
      if MapSet.size(missing_vars) == 0 do
        {:ok, config}
      else
        {:error, [%{field: :variables, code: :missing_variables, 
                   message: "Missing variables: #{MapSet.to_list(missing_vars) |> Enum.join(", ")}"}]}
      end
    end
    
    defp extract_template_variables(template) do
      Regex.scan(~r/\{\{(\w+)\}\}/, template)
      |> Enum.map(fn [_, var] -> String.to_atom(var) end)
      |> MapSet.new()
    end
  end
  
  defmodule RenderedPrompt do
    use DSPEx.Schema
    
    @moduledoc "Rendered prompt with metadata"
    schema @moduledoc do
      output_field :content, :string,
        description: "Final rendered prompt content",
        min_length: 1
        
      output_field :variables_used, :map,
        description: "Variables that were substituted"
        
      output_field :token_estimate, :integer,
        description: "Estimated token count",
        optional: true,
        ge: 0
        
      output_field :metadata, :map,
        description: "Additional prompt metadata",
        default: %{}
    end
  end
end
```

#### 6.2 Language Model Integration
**File: `lib/dspex/language_model.ex`** (New)
```elixir
defmodule DSPEx.LanguageModel do
  @moduledoc """
  Comprehensive language model integration with type-safe configuration.
  """
  
  defmodule Configuration do
    use DSPEx.Schema
    
    @moduledoc "LM configuration with comprehensive validation"
    schema @moduledoc do
      input_field :provider, :atom,
        description: "LM provider",
        choices: [:openai, :anthropic, :gemini, :local, :azure]
        
      input_field :model, :string,
        description: "Model identifier",
        min_length: 1
        
      input_field :api_key, :string,
        description: "API key for the provider",
        min_length: 1
        
      input_field :max_tokens, :integer,
        description: "Maximum tokens in response",
        default: 1000,
        gt: 0,
        le: 128000  # Current max for most models
        
      input_field :temperature, :float,
        description: "Sampling temperature",
        default: 0.7,
        ge: 0.0,
        le: 2.0
        
      input_field :top_p, :float,
        description: "Nucleus sampling threshold",
        default: 1.0,
        ge: 0.0,
        le: 1.0
        
      input_field :frequency_penalty, :float,
        description: "Frequency penalty",
        default: 0.0,
        ge: -2.0,
        le: 2.0
        
      input_field :presence_penalty, :float,
        description: "Presence penalty",
        default: 0.0,
        ge: -2.0,
        le: 2.0
        
      input_field :timeout_ms, :integer,
        description: "Request timeout in milliseconds",
        default: 30_000,
        gt: 0
        
      config do
        title "Language Model Configuration"
        strict true
      end
    end
  end
  
  defmodule Usage do
    use DSPEx.Schema
    
    @moduledoc "Token usage tracking with cost calculation"
    schema @moduledoc do
      output_field :prompt_tokens, :integer,
        description: "Tokens in the prompt",
        ge: 0
        
      output_field :completion_tokens, :integer,
        description: "Tokens in the completion",
        ge: 0
        
      output_field :total_tokens, :integer,
        description: "Total tokens used",
        ge: 0
        
      output_field :cost_usd, :float,
        description: "Cost in USD",
        optional: true,
        ge: 0.0
        
      output_field :model, :string,
        description: "Model used for generation"
        
      output_field :provider, :atom,
        description: "Provider used"
    end
    
    def calculate_cost(%{provider: provider, model: model, prompt_tokens: pt, completion_tokens: ct} = usage) do
      cost = get_cost_per_token(provider, model, pt, ct)
      Map.put(usage, :cost_usd, cost)
    end
    
    defp get_cost_per_token(provider, model, prompt_tokens, completion_tokens) do
      # Cost calculation logic based on provider pricing
      pricing = get_pricing_table(provider, model)
      (prompt_tokens * pricing.prompt_cost_per_1k / 1000) +
      (completion_tokens * pricing.completion_cost_per_1k / 1000)
    end
  end
  
  defmodule Response do
    use DSPEx.Schema
    
    @moduledoc "LM response with comprehensive metadata"
    schema @moduledoc do
      output_field :content, :string,
        description: "Generated content",
        min_length: 1
        
      output_field :usage, Usage,
        description: "Token usage information"
        
      output_field :model, :string,
        description: "Model that generated the response"
        
      output_field :finish_reason, :atom,
        description: "Reason for completion",
        choices: [:stop, :length, :content_filter, :tool_calls, :function_call]
        
      output_field :response_time_ms, :integer,
        description: "Response time in milliseconds",
        ge: 0
        
      output_field :metadata, :map,
        description: "Additional response metadata",
        default: %{}
    end
  end
end
```

#### 6.3 Retrieval System Integration
**File: `lib/dspex/retrieval.ex`** (New)
```elixir
defmodule DSPEx.Retrieval do
  @moduledoc """
  Type-safe retrieval system with comprehensive validation.
  """
  
  defmodule Query do
    use DSPEx.Schema
    
    @moduledoc "Retrieval query with validation"
    schema @moduledoc do
      input_field :text, :string,
        description: "Query text",
        min_length: 1,
        max_length: 10000
        
      input_field :top_k, :integer,
        description: "Number of results to retrieve",
        default: 10,
        gt: 0,
        le: 1000
        
      input_field :threshold, :float,
        description: "Minimum similarity threshold",
        default: 0.0,
        ge: 0.0,
        le: 1.0
        
      input_field :filters, :map,
        description: "Additional filters",
        default: %{},
        optional: true
        
      input_field :rerank, :boolean,
        description: "Whether to rerank results",
        default: false
        
      config do
        title "Retrieval Query"
        strict true
      end
    end
  end
  
  defmodule Document do
    use DSPEx.Schema
    
    @moduledoc "Document with metadata validation"
    schema @moduledoc do
      input_field :id, :string,
        description: "Unique document identifier",
        min_length: 1
        
      input_field :content, :string,
        description: "Document content",
        min_length: 1
        
      input_field :metadata, :map,
        description: "Document metadata",
        default: %{}
        
      input_field :embedding, {:array, :float},
        description: "Document embedding vector",
        optional: true
        
      input_field :source, :string,
        description: "Document source",
        optional: true
        
      config do
        title "Document"
        strict false  # Allow additional metadata
      end
    end
  end
  
  defmodule Result do
    use DSPEx.Schema
    
    @moduledoc "Retrieval result with scoring"
    schema @moduledoc do
      output_field :document, Document,
        description: "Retrieved document"
        
      output_field :score, :float,
        description: "Relevance score",
        ge: 0.0,
        le: 1.0
        
      output_field :rank, :integer,
        description: "Result rank",
        ge: 1
        
      output_field :explanation, :string,
        description: "Why this document was retrieved",
        optional: true
        
      config do
        title "Retrieval Result"
        strict true
      end
    end
  end
  
  defmodule ResultSet do
    use DSPEx.Schema
    
    @moduledoc "Complete retrieval result set"
    schema @moduledoc do
      output_field :query, Query,
        description: "Original query"
        
      output_field :results, {:array, Result},
        description: "Retrieved results"
        
      output_field :total_found, :integer,
        description: "Total documents found",
        ge: 0
        
      output_field :retrieval_time_ms, :integer,
        description: "Retrieval time in milliseconds",
        ge: 0
        
      output_field :metadata, :map,
        description: "Additional retrieval metadata",
        default: %{}
        
      config do
        title "Retrieval Result Set"
        strict true
      end
    end
  end
end
```

#### 6.4 Evaluation Framework
**File: `lib/dspex/evaluation.ex`** (New)
```elixir
defmodule DSPEx.Evaluation do
  @moduledoc """
  Comprehensive evaluation framework with type-safe metrics.
  """
  
  defmodule MetricConfig do
    use DSPEx.Schema
    
    @moduledoc "Metric configuration and validation"
    schema @moduledoc do
      input_field :name, :string,
        description: "Metric name",
        min_length: 1
        
      input_field :type, :atom,
        description: "Metric type",
        choices: [:accuracy, :precision, :recall, :f1, :bleu, :rouge, :exact_match, :custom]
        
      input_field :parameters, :map,
        description: "Metric-specific parameters",
        default: %{}
        
      input_field :weight, :float,
        description: "Metric weight in aggregation",
        default: 1.0,
        ge: 0.0
        
      config do
        title "Evaluation Metric Configuration"
        strict true
      end
    end
  end
  
  defmodule Result do
    use DSPEx.Schema
    
    @moduledoc "Individual evaluation result"
    schema @moduledoc do
      output_field :example_id, :string,
        description: "Example identifier"
        
      output_field :prediction, :map,
        description: "Model prediction"
        
      output_field :ground_truth, :map,
        description: "Expected output"
        
      output_field :scores, :map,
        description: "Metric scores"
        
      output_field :metadata, :map,
        description: "Additional evaluation metadata",
        default: %{}
        
      config do
        title "Evaluation Result"
        strict true
      end
    end
  end
  
  defmodule Summary do
    use DSPEx.Schema
    
    @moduledoc "Evaluation summary with aggregated metrics"
    schema @moduledoc do
      output_field :total_examples, :integer,
        description: "Total examples evaluated",
        ge: 0
        
      output_field :metric_scores, :map,
        description: "Aggregated metric scores"
        
      output_field :overall_score, :float,
        description: "Weighted overall score",
        ge: 0.0,
        le: 1.0
        
      output_field :confidence_interval, :map,
        description: "Confidence intervals for metrics",
        optional: true
        
      output_field :evaluation_time_ms, :integer,
        description: "Total evaluation time",
        ge: 0
        
      output_field :timestamp, :string,
        description: "Evaluation timestamp",
        format: "date-time"
        
      config do
        title "Evaluation Summary"
        strict true
      end
    end
  end
end
```

### Phase 7: Enterprise Features (Week 13-14)

#### 7.1 Streaming and Real-time Processing
**File: `lib/dspex/streaming.ex`** (New)
```elixir
defmodule DSPEx.Streaming do
  @moduledoc """
  Type-safe streaming and real-time processing capabilities.
  """
  
  defmodule Chunk do
    use DSPEx.Schema
    
    @moduledoc "Streaming response chunk"
    schema @moduledoc do
      output_field :content, :string,
        description: "Chunk content"
        
      output_field :chunk_type, :atom,
        description: "Type of chunk",
        choices: [:text, :tool_call, :status, :error, :metadata]
        
      output_field :sequence_number, :integer,
        description: "Chunk sequence number",
        ge: 0
        
      output_field :is_final, :boolean,
        description: "Whether this is the final chunk",
        default: false
        
      output_field :metadata, :map,
        description: "Chunk metadata",
        default: %{}
        
      config do
        title "Stream Chunk"
        strict true
      end
    end
  end
  
  defmodule Stream do
    use DSPEx.Schema
    
    @moduledoc "Streaming session configuration"
    schema @moduledoc do
      input_field :stream_id, :string,
        description: "Unique stream identifier",
        min_length: 1
        
      input_field :signature, :atom,
        description: "Signature module for the stream"
        
      input_field :buffer_size, :integer,
        description: "Stream buffer size",
        default: 1024,
        gt: 0
        
      input_field :timeout_ms, :integer,
        description: "Stream timeout",
        default: 30_000,
        gt: 0
        
      config do
        title "Stream Configuration"
        strict true
      end
    end
  end
end
```

#### 7.2 Multi-modal Support Enhancement
**File: `lib/dspex/types/multimodal.ex`** (New)
```elixir
defmodule DSPEx.Types.Multimodal do
  @moduledoc """
  Comprehensive multi-modal type system with validation.
  """
  
  defmodule MediaFile do
    use Elixact.Type
    
    def type_definition, do: :map
    
    def json_schema do
      %{
        "type" => "object",
        "description" => "Media file with comprehensive validation",
        "properties" => %{
          "content" => %{"type" => "string", "description" => "Base64 encoded content"},
          "mime_type" => %{"type" => "string", "pattern" => "^(image|audio|video)/.+"},
          "size_bytes" => %{"type" => "integer", "minimum" => 1, "maximum" => 100_000_000},
          "filename" => %{"type" => "string"},
          "checksum" => %{"type" => "string", "description" => "SHA256 checksum"},
          "metadata" => %{"type" => "object"}
        },
        "required" => ["content", "mime_type", "size_bytes"]
      }
    end
    
    def validate(%{content: content, mime_type: mime_type, size_bytes: size} = file) 
        when is_binary(content) and is_binary(mime_type) and is_integer(size) do
      with :ok <- validate_mime_type(mime_type),
           :ok <- validate_size(size),
           :ok <- validate_content_encoding(content),
           :ok <- validate_content_type_match(content, mime_type) do
        {:ok, add_computed_fields(file)}
      end
    end
    
    def validate(_), do: {:error, [%{code: :invalid_media, message: "Invalid media file format"}]}
    
    defp validate_mime_type(mime_type) do
      if String.match?(mime_type, ~r/^(image|audio|video)\/.+/) do
        :ok
      else
        {:error, [%{code: :invalid_mime_type, message: "Unsupported media type"}]}
      end
    end
    
    defp validate_size(size) when size > 0 and size <= 100_000_000, do: :ok
    defp validate_size(_), do: {:error, [%{code: :invalid_size, message: "File size out of range"}]}
    
    defp validate_content_encoding(content) do
      if String.match?(content, ~r/^[A-Za-z0-9+\/]+=*$/) do
        :ok
      else
        {:error, [%{code: :invalid_encoding, message: "Content must be valid base64"}]}
      end
    end
    
    defp validate_content_type_match(content, mime_type) do
      # Decode first few bytes to validate content type
      try do
        decoded = Base.decode64!(content, padding: false)
        if content_matches_mime_type?(decoded, mime_type) do
          :ok
        else
          {:error, [%{code: :content_mismatch, message: "Content doesn't match MIME type"}]}
        end
      rescue
        _ -> {:error, [%{code: :decode_error, message: "Cannot decode content"}]}
      end
    end
    
    defp content_matches_mime_type?(binary_content, mime_type) do
      # Magic number validation for common types
      case mime_type do
        "image/jpeg" -> String.starts_with?(binary_content, <<0xFF, 0xD8, 0xFF>>)
        "image/png" -> String.starts_with?(binary_content, <<0x89, 0x50, 0x4E, 0x47>>)
        "image/gif" -> String.starts_with?(binary_content, "GIF8")
        "image/webp" -> String.contains?(binary_content, "WEBP")
        _ -> true  # Skip validation for other types
      end
    end
    
    defp add_computed_fields(file) do
      file
      |> Map.put_new(:checksum, compute_checksum(file.content))
      |> Map.put_new(:actual_size, byte_size(file.content))
    end
    
    defp compute_checksum(content) do
      :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    end
  end
  
  defmodule Video do
    use Elixact.Type
    
    def type_definition, do: MediaFile
    
    def json_schema do
      base_schema = MediaFile.json_schema()
      put_in(base_schema, ["properties", "mime_type", "pattern"], "^video/.+")
      |> put_in(["properties", "duration_seconds"], %{"type" => "number", "minimum" => 0})
      |> put_in(["properties", "resolution"], %{
        "type" => "object",
        "properties" => %{
          "width" => %{"type" => "integer", "minimum" => 1},
          "height" => %{"type" => "integer", "minimum" => 1}
        }
      })
    end
    
    def validate(data), do: MediaFile.validate(data)
  end
end
```

### Phase 8: Infrastructure & Operations (Week 15-16)

#### 8.1 Plugin and Extension System
**File: `lib/dspex/plugins.ex`** (New)
```elixir
defmodule DSPEx.Plugins do
  @moduledoc """
  Type-safe plugin and extension system.
  """
  
  defmodule Config do
    use DSPEx.Schema
    
    @moduledoc "Plugin configuration with validation"
    schema @moduledoc do
      input_field :name, :string,
        description: "Plugin name",
        min_length: 1,
        max_length: 100,
        pattern: ~r/^[a-zA-Z][a-zA-Z0-9_-]*$/
        
      input_field :version, :string,
        description: "Plugin version",
        pattern: ~r/^\d+\.\d+\.\d+$/
        
      input_field :dependencies, {:array, :string},
        description: "Plugin dependencies",
        default: []
        
      input_field :config, :map,
        description: "Plugin-specific configuration",
        default: %{}
        
      input_field :enabled, :boolean,
        description: "Whether plugin is enabled",
        default: true
        
      input_field :hooks, {:array, :atom},
        description: "Hook points this plugin registers",
        default: []
        
      config do
        title "Plugin Configuration"
        strict true
      end
    end
  end
  
  defmodule Registry do
    use DSPEx.Schema
    
    @moduledoc "Plugin registry with dependency validation"
    schema @moduledoc do
      output_field :plugins, {:array, Config},
        description: "Registered plugins"
        
      output_field :dependency_graph, :map,
        description: "Plugin dependency graph"
        
      output_field :load_order, {:array, :string},
        description: "Plugin load order"
        
      config do
        title "Plugin Registry"
        strict true
      end
    end
  end
end
```

#### 8.2 Monitoring and Observability
**File: `lib/dspex/monitoring.ex`** (New)
```elixir
defmodule DSPEx.Monitoring do
  @moduledoc """
  Comprehensive monitoring and observability with structured data.
  """
  
  defmodule Metric do
    use DSPEx.Schema
    
    @moduledoc "Performance metric with metadata"
    schema @moduledoc do
      output_field :name, :string,
        description: "Metric name"
        
      output_field :value, :float,
        description: "Metric value"
        
      output_field :unit, :string,
        description: "Metric unit"
        
      output_field :timestamp, :string,
        description: "Metric timestamp",
        format: "date-time"
        
      output_field :tags, :map,
        description: "Metric tags",
        default: %{}
        
      output_field :source, :string,
        description: "Metric source component"
        
      config do
        title "Performance Metric"
        strict true
      end
    end
  end
  
  defmodule LogEntry do
    use DSPEx.Schema
    
    @moduledoc "Structured log entry"
    schema @moduledoc do
      output_field :level, :atom,
        description: "Log level",
        choices: [:debug, :info, :warning, :error, :critical]
        
      output_field :message, :string,
        description: "Log message",
        min_length: 1
        
      output_field :timestamp, :string,
        description: "Log timestamp",
        format: "date-time"
        
      output_field :module, :string,
        description: "Source module"
        
      output_field :metadata, :map,
        description: "Additional log metadata",
        default: %{}
        
      output_field :correlation_id, :string,
        description: "Request correlation ID",
        optional: true
        
      config do
        title "Log Entry"
        strict true
      end
    end
  end
end
```

### Phase 9: Final Integration & Polish (Week 17)

#### 9.1 Resource Management
**File: `lib/dspex/resources.ex`** (New)
```elixir
defmodule DSPEx.Resources do
  @moduledoc """
  Resource management with quota enforcement and cost tracking.
  """
  
  defmodule Quota do
    use DSPEx.Schema
    
    @moduledoc "Resource quota definition"
    schema @moduledoc do
      input_field :cpu_cores, :integer,
        description: "CPU cores allocated",
        ge: 1,
        le: 64
        
      input_field :memory_gb, :integer,
        description: "Memory in GB",
        ge: 1,
        le: 512
        
      input_field :gpu_count, :integer,
        description: "GPU count",
        ge: 0,
        le: 8
        
      input_field :storage_gb, :integer,
        description: "Storage in GB",
        ge: 10,
        le: 10000
        
      input_field :monthly_budget_usd, :float,
        description: "Monthly budget in USD",
        ge: 0.0
        
      input_field :api_calls_per_day, :integer,
        description: "API calls per day limit",
        ge: 0
        
      config do
        title "Resource Quota"
        strict true
      end
    end
  end
  
  defmodule Usage do
    use DSPEx.Schema
    
    @moduledoc "Resource usage tracking"
    schema @moduledoc do
      output_field :quota, Quota,
        description: "Applied quota"
        
      output_field :current_usage, :map,
        description: "Current resource usage"
        
      output_field :cost_to_date_usd, :float,
        description: "Cost to date in USD",
        ge: 0.0
        
      output_field :api_calls_today, :integer,
        description: "API calls made today",
        ge: 0
        
      output_field :projected_monthly_cost, :float,
        description: "Projected monthly cost",
        ge: 0.0
        
      config do
        title "Resource Usage"
        strict true
      end
    end
  end
end
```

#### 5.1 Custom DSPEx Types
**File: `lib/dspex/types.ex`** (New)
```elixir
defmodule DSPEx.Types do
  @moduledoc """
  Custom elixact types for DSPEx-specific use cases.
  
  Provides specialized types for common DSPy patterns like reasoning chains,
  confidence scores, and structured outputs.
  """
  
  defmodule ReasoningChain do
    @moduledoc "Type for chain-of-thought reasoning"
    use Elixact.Type
    
    def type_definition do
      :string
    end
    
    def json_schema do
      %{
        "type" => "string",
        "description" => "Step-by-step reasoning chain",
        "minLength" => 10,
        "pattern" => ".*[.!?]$"  # Must end with punctuation
      }
    end
    
    def validate(value) when is_binary(value) do
      cond do
        String.length(value) < 10 ->
          {:error, [%{code: :too_short, message: "Reasoning must be at least 10 characters"}]}
        not String.match?(value, ~r/[.!?]$/) ->
          {:error, [%{code: :invalid_format, message: "Reasoning must end with punctuation"}]}
        true ->
          {:ok, value}
      end
    end
    
    def validate(_), do: {:error, [%{code: :invalid_type, message: "Must be a string"}]}
  end
  
  defmodule ConfidenceScore do
    @moduledoc "Type for confidence scores (0.0 to 1.0)"
    use Elixact.Type
    
    def type_definition do
      :float
    end
    
    def json_schema do
      %{
        "type" => "number",
        "description" => "Confidence score from 0.0 (no confidence) to 1.0 (full confidence)",
        "minimum" => 0.0,
        "maximum" => 1.0
      }
    end
    
    def validate(value) when is_number(value) and value >= 0.0 and value <= 1.0 do
      {:ok, value / 1.0}  # Ensure float
    end
    
    def validate(value) when is_number(value) do
      {:error, [%{code: :out_of_range, message: "Confidence must be between 0.0 and 1.0"}]}
    end
    
    def validate(_) do
      {:error, [%{code: :invalid_type, message: "Must be a number"}]}
    end
  end
  
  defmodule StructuredAnswer do
    @moduledoc "Type for complex structured answers"
    use Elixact.Type
    
    def type_definition do
      # This would be a nested schema
      :map
    end
    
    def json_schema do
      %{
        "type" => "object",
        "description" => "Structured answer with content and metadata",
        "properties" => %{
          "content" => %{"type" => "string", "minLength" => 1},
          "reasoning" => %{"type" => "string"},
          "confidence" => %{"type" => "number", "minimum" => 0.0, "maximum" => 1.0},
          "sources" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          }
        },
        "required" => ["content"]
      }
    end
    
    def validate(%{content: content} = value) when is_binary(content) and byte_size(content) > 0 do
      {:ok, value}
    end
    
    def validate(_) do
      {:error, [%{code: :invalid_structure, message: "Must have non-empty content field"}]}
    end
  end
end
```

#### 5.2 Migration Utilities
**File: `lib/dspex/migration.ex`** (New)
```elixir
defmodule DSPEx.Migration do
  @moduledoc """
  Utilities for migrating from string-based signatures to elixact schemas.
  
  Provides tools to analyze existing signatures and generate equivalent
  elixact schema definitions.
  """
  
  @doc """
  Generate elixact schema code from a string signature.
  
  ## Examples
  
      iex> DSPEx.Migration.generate_schema_code("question -> answer, confidence")
      '''
      defmodule MySignature do
        use DSPEx.Schema
        
        @moduledoc "TODO: Add description"
        schema @moduledoc do
          input_field :question, :string, description: "TODO: Add description"
          output_field :answer, :string, description: "TODO: Add description"
          output_field :confidence, DSPEx.Types.ConfidenceScore, description: "TODO: Add description"
        end
      end
      '''
  """
  def generate_schema_code(signature_string, opts \\ []) do
    {inputs, outputs} = DSPEx.Signature.Parser.parse(signature_string)
    module_name = Keyword.get(opts, :module_name, "MySignature")
    
    input_fields = Enum.map(inputs, &generate_field_code(&1, :input))
    output_fields = Enum.map(outputs, &generate_field_code(&1, :output))
    
    """
    defmodule #{module_name} do
      use DSPEx.Schema
      
      @moduledoc "TODO: Add description"
      schema @moduledoc do
    #{Enum.join(input_fields ++ output_fields, "\n")}
      end
    end
    """
  end
  
  defp generate_field_code(field_name, field_type) do
    type = infer_elixir_type(field_name)
    "    #{field_type}_field :#{field_name}, #{type}, description: \"TODO: Add description\""
  end
  
  defp infer_elixir_type(field_name) do
    name_str = Atom.to_string(field_name)
    
    cond do
      String.contains?(name_str, "confidence") -> "DSPEx.Types.ConfidenceScore"
      String.contains?(name_str, "reasoning") -> "DSPEx.Types.ReasoningChain"
      String.contains?(name_str, "score") -> ":float"
      String.contains?(name_str, "count") -> ":integer"
      true -> ":string"
    end
  end
  
  @doc "Analyze existing signature usage in a project"
  def analyze_signatures(path \\ ".") do
    path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.flat_map(&extract_signatures_from_file/1)
    |> Enum.group_by(fn {_file, signature} -> signature end)
    |> Enum.map(fn {signature, usages} ->
      files = Enum.map(usages, fn {file, _} -> file end)
      {signature, files}
    end)
  end
  
  defp extract_signatures_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        Regex.scan(~r/use DSPEx\.Signature,\s*"([^"]+)"/, content)
        |> Enum.map(fn [_full, signature] -> {file_path, signature} end)
      {:error, _} ->
        []
    end
  end
end
```

## Migration Strategy & Timeline

### Backward Compatibility Approach

1. **Dual Support**: Both string-based and elixact-based signatures work simultaneously
2. **Gradual Migration**: Existing code continues to work unchanged
3. **Deprecation Warnings**: Gentle nudges toward new patterns
4. **Migration Tools**: Automated conversion utilities

### Timeline

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| Phase 1 | 2 weeks | Elixact integration, compatibility layer, core schema wrapper |
| Phase 2 | 2 weeks | Core DSPEx integration, enhanced validation, prompt templates |
| Phase 3 | 2 weeks | Adapter transformation, automatic JSON schema, LM integration |
| Phase 4 | 2 weeks | Example enhancement, teleprompter validation, retrieval system |
| Phase 5 | 2 weeks | Custom types, migration utilities, evaluation framework |
| Phase 6 | 2 weeks | Streaming support, multi-modal types, plugin system |
| Phase 7 | 2 weeks | Distributed processing, API integration, workflow management |
| Phase 8 | 2 weeks | Monitoring, security, version control, testing framework |
| Phase 9 | 1 week | Resource management, final integration, documentation |
| **Total** | **17 weeks** | **Complete enterprise-grade integration with comprehensive feature parity** |

## Testing Strategy

### Phase-by-Phase Testing

1. **Phase 1**: Compatibility tests ensuring existing signatures still work
2. **Phase 2**: New elixact signature validation tests
3. **Phase 3**: Structured output generation tests with complex schemas
4. **Phase 4**: Teleprompter optimization with validated examples
5. **Phase 5**: Custom type validation and migration tool tests

### Test Categories

- **Unit Tests**: Each new module and enhanced function
- **Integration Tests**: Full pipeline with elixact signatures
- **Migration Tests**: Backward compatibility verification
- **Performance Tests**: Ensure no regression in teleprompter performance
- **Property Tests**: Random signature generation and validation

## Additional Pydantic Feature Integration

Based on the comprehensive analysis of Pydantic usage in DSPy, several additional integration points need to be addressed:

### Runtime Model Creation (pydantic.create_model equivalent)

DSPy heavily uses `pydantic.create_model()` for dynamic type creation, especially in structured outputs. While Elixir favors compile-time generation, we need a solution:

```elixir
defmodule DSPEx.Schema.Dynamic do
  @moduledoc """
  Runtime schema generation capabilities similar to pydantic.create_model().
  
  While Elixir prefers compile-time generation, this module provides utilities
  for creating schemas at runtime when needed for teleprompter optimization.
  """
  
  def create_signature_schema(signature_module, additional_fields \\ %{}) do
    base_fields = get_signature_fields(signature_module)
    all_fields = Map.merge(base_fields, additional_fields)
    
    # Generate a unique module name
    module_name = generate_dynamic_module_name(signature_module, additional_fields)
    
    # Create the module dynamically using Elixir's Code.compile_quoted
    module_ast = generate_schema_ast(module_name, all_fields)
    
    case Code.compile_quoted(module_ast) do
      [{^module_name, _bytecode}] -> {:ok, module_name}
      error -> {:error, error}
    end
  end
  
  defp generate_schema_ast(module_name, fields) do
    quote do
      defmodule unquote(module_name) do
        use DSPEx.Schema
        
        schema "Dynamically generated signature" do
          unquote_splicing(generate_field_asts(fields))
        end
      end
    end
  end
  
  # ... implementation details
end
```

### TypeAdapter Equivalent for Complex Types

```elixir
defmodule DSPEx.TypeAdapter do
  @moduledoc """
  Validates arbitrary data against elixact types, similar to pydantic's TypeAdapter.
  
  Provides validation for complex types that aren't full schemas.
  """
  
  def validate(type_module, data) when is_atom(type_module) do
    if function_exported?(type_module, :validate, 1) do
      type_module.validate(data)
    else
      # Fall back to basic type validation
      validate_basic_type(type_module, data)
    end
  end
  
  def validate(type_spec, data) when is_atom(type_spec) do
    # Handle basic Elixir types
    validate_basic_type(type_spec, data)
  end
  
  defp validate_basic_type(:string, data) when is_binary(data), do: {:ok, data}
  defp validate_basic_type(:integer, data) when is_integer(data), do: {:ok, data}
  defp validate_basic_type(:float, data) when is_float(data), do: {:ok, data}
  defp validate_basic_type(:boolean, data) when is_boolean(data), do: {:ok, data}
  defp validate_basic_type(:list, data) when is_list(data), do: {:ok, data}
  defp validate_basic_type(:map, data) when is_map(data), do: {:ok, data}
  defp validate_basic_type(expected, _data) do
    {:error, [%{code: :type_mismatch, message: "Expected #{expected}"}]}
  end
end
```

### Enhanced Error Handling (ValidationError equivalent)

```elixir
defmodule DSPEx.ValidationError do
  @moduledoc """
  Structured validation errors similar to pydantic's ValidationError.
  
  Provides detailed error information with field paths and error codes.
  """
  
  defexception [:errors, :input_data]
  
  @type error_detail :: %{
    field: atom() | String.t(),
    path: [atom() | String.t()],
    code: atom(),
    message: String.t(),
    input_value: any()
  }
  
  @type t :: %__MODULE__{
    errors: [error_detail()],
    input_data: any()
  }
  
  def new(errors, input_data \\ nil) when is_list(errors) do
    %__MODULE__{errors: errors, input_data: input_data}
  end
  
  def message(%__MODULE__{errors: errors}) do
    errors
    |> Enum.map(&format_error/1)
    |> Enum.join("\n")
  end
  
  defp format_error(%{field: field, path: path, message: message}) do
    path_str = path |> Enum.map(&to_string/1) |> Enum.join(".")
    "#{path_str || field}: #{message}"
  end
  
  # Integration with elixact errors
  def from_elixact_errors(elixact_errors, input_data \\ nil) do
    formatted_errors = Enum.map(elixact_errors, &convert_elixact_error/1)
    new(formatted_errors, input_data)
  end
  
  defp convert_elixact_error(%{path: path, code: code, message: message}) do
    %{
      field: List.last(path) || :root,
      path: path,
      code: code,
      message: message,
      input_value: nil  # Would need to be extracted from context
    }
  end
end
```

## Benefits Realized

### For Developers
- **Type Safety**: Catch errors at compile time with rich type definitions
- **Rich Metadata**: Descriptions, examples, constraints, and documentation in schema definitions
- **IDE Support**: Autocomplete and validation in editors with proper type hints
- **Clear Documentation**: Self-documenting schemas with automatic documentation generation
- **Familiar Patterns**: Pydantic-like API for developers coming from Python/DSPy
- **Field Validators**: Custom validation logic with clear error messages
- **Configuration Management**: Type-safe configuration for all system components

### For DSPEx Framework
- **Robustness**: Structured validation throughout the pipeline with comprehensive error handling
- **Extensibility**: Easy to add custom types and validation rules following established patterns
- **Maintainability**: Declarative schemas easier to understand and modify than string parsing
- **Compatibility**: JSON schemas work seamlessly with modern LLM APIs (OpenAI, Anthropic, etc.)
- **Performance**: Compile-time optimizations and efficient validation
- **Observability**: Structured errors with paths and codes for better debugging
- **Modularity**: Clear separation of concerns with schema, validation, and serialization

### For Advanced Use Cases
- **Complex Schemas**: Nested objects, arrays, custom types with full validation
- **Dynamic Validation**: Runtime schema generation and validation for teleprompter optimization
- **Interoperability**: JSON schemas work with external tools and documentation generators
- **Evolution**: Easy to extend signatures with new fields and types without breaking changes
- **Multi-Modal Support**: Rich type system for images, audio, tools, and other complex data
- **Tool Integration**: Seamless integration with structured output APIs and tool calling
- **Chain-of-Thought**: Specialized types for reasoning chains and confidence scoring

## Risk Mitigation

### Technical Risks
- **Compatibility Breaking**: Mitigated by comprehensive compatibility layer
- **Performance Impact**: Mitigated by optional validation and efficient elixact implementation
- **Learning Curve**: Mitigated by migration tools and extensive documentation

### Adoption Risks
- **Developer Resistance**: Mitigated by gradual migration and clear benefits
- **Ecosystem Fragmentation**: Mitigated by maintaining backward compatibility indefinitely
- **Maintenance Burden**: Mitigated by focusing on core features and community adoption

## Conclusion

This comprehensive integration plan transforms DSPEx from a clever string-parsing framework into a robust, type-safe, and declarative system that not only matches but exceeds the power of the original DSPy's pydantic-based architecture. By leveraging elixact's capabilities and extending them with DSPEx-specific patterns, we achieve:

### Complete Pydantic Feature Parity
- **Signature System**: Full replacement of BaseModel-based signatures with elixact schemas
- **Custom Types**: Complete type system including Image, Audio, Tool, History, and domain-specific types
- **Validation Framework**: Comprehensive validation with field validators, model validators, and structured errors
- **JSON Schema Generation**: Automatic schema generation for structured outputs and API integration
- **Configuration Management**: Type-safe configuration for all system components
- **Runtime Flexibility**: Dynamic schema creation where needed while maintaining compile-time safety

### Elixir-Native Enhancements
- **Compile-time Safety**: Leverage Elixir's macro system for early error detection
- **Functional Patterns**: Immutable data structures with functional transformation pipelines
- **Supervision Trees**: Robust error handling and recovery for long-running optimization processes
- **Distributed Computing**: Natural scaling for teleprompter optimization across nodes
- **Hot Code Reloading**: Development-time benefits for rapid iteration

### Superior Developer Experience
- **Gradual Migration**: Zero breaking changes with clear upgrade path
- **Rich IDE Support**: Full autocomplete and type checking
- **Comprehensive Documentation**: Self-documenting schemas with examples and constraints
- **Migration Tooling**: Automated analysis and conversion utilities
- **Best Practices**: Established patterns for common DSPy use cases

**Key Success Metrics:**
- ✅ Zero breaking changes to existing code
- ✅ 100% JSON schema generation for structured outputs
- ✅ Comprehensive type safety for new signatures
- ✅ Clear migration path for all existing signatures
- ✅ Enhanced developer experience with rich IDE support
- ✅ Complete custom type system for multi-modal AI
- ✅ Structured error handling with detailed diagnostics
- ✅ Configuration validation for all system components

The result will be a DSPEx framework that is not just a port of DSPy, but a superior implementation that showcases the best of both Elixir and modern AI programming paradigms, while maintaining the flexibility and power that made DSPy successful.
