# DSPEx + Elixact Integration Plan: A Comprehensive Technical Roadmap

## Executive Summary

After analyzing the current DSPEx architecture and the elixact library capabilities, this plan outlines a strategic integration that will transform DSPEx from a clever string-parsing system into a robust, type-safe, and declarative framework that rivals the original DSPy's pydantic-based architecture.

**Core Transformation**: Replace string-based signature parsing (`"question -> answer"`) with elixact's declarative schema DSL, gaining automatic validation, JSON schema generation, and type safety while maintaining backward compatibility.

## Strategic Objectives

### 1. **Type Safety & Validation**
- Move from runtime string parsing to compile-time schema validation
- Automatic input/output validation with structured error reporting
- Type-safe field access and manipulation

### 2. **Structured Output Enhancement**
- Eliminate manual JSON schema construction in adapters
- Leverage elixact's automatic JSON schema generation for LLM structured outputs
- Support complex nested schemas and custom types

### 3. **Developer Experience**
- Rich IDE support with compile-time field validation
- Clear, declarative signature definitions
- Comprehensive error messages with path information

### 4. **Robustness**
- Structured error handling throughout the pipeline
- Validation at every data transformation point
- Consistent data shapes across the entire framework

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

### Comprehensive Elixact Feature Mapping

Based on the analysis of Pydantic usage in DSPy, here's the complete mapping:

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

### Phase 5: Advanced Features & Polish (Week 5-6)

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
| Phase 1 | 2 weeks | Elixact integration, compatibility layer |
| Phase 2 | 1 week | Core DSPEx integration, enhanced validation |
| Phase 3 | 1 week | Adapter transformation, automatic JSON schema |
| Phase 4 | 1 week | Example enhancement, teleprompter validation |
| Phase 5 | 1 week | Custom types, migration utilities |
| **Total** | **6 weeks** | **Complete integration with migration path** |

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
