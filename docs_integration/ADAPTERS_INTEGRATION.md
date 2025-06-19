# DSPEx Adapter System Integration - Elixir-Native Design

## Overview

This document provides a comprehensive analysis of DSPy's adapter system and outlines the design for an Elixir-native adapter architecture for DSPEx. The adapter layer is crucial for bridging signatures and LLM APIs, handling message formatting, response parsing, and provider-specific optimizations.

## DSPy Adapter Architecture Analysis

### 🏗️ Core Design Principles

#### 1. Base Adapter Pattern (`dspy/adapters/base.py`)
**Key Features**:
- **Callback System**: Decorates `format()` and `parse()` methods with callbacks
- **Tool Calling Integration**: Native function calling support via LiteLLM
- **Preprocessing/Postprocessing**: Handles tool calls and response formatting
- **Message Structure**: Standardized multi-turn conversation format

**Core Interface**:
```python
class Adapter:
    def format(signature, demos, inputs) -> list[dict[str, Any]]
    def parse(signature, completion) -> dict[str, Any]
    def __call__(lm, lm_kwargs, signature, demos, inputs) -> list[dict[str, Any]]
```

**Message Format Standard**:
```python
[
    {"role": "system", "content": system_message},
    # Few-shot examples
    {"role": "user", "content": example_input},
    {"role": "assistant", "content": example_output},
    # Conversation history
    {"role": "user", "content": history_input},
    {"role": "assistant", "content": history_output},
    # Current request
    {"role": "user", "content": current_input},
]
```

#### 2. ChatAdapter Implementation (`dspy/adapters/chat_adapter.py`)
**Formatting Strategy**:
- **Field Markers**: Uses `[[ ## field_name ## ]]` markers for structured parsing
- **Completion Indicator**: `[[ ## completed ## ]]` marker for output termination
- **Fallback Mechanism**: Falls back to JSONAdapter on context window exceeded
- **Type Hints**: Provides field type information in prompts

**Example Output Format**:
```
[[ ## answer ## ]]
The capital of France is Paris.

[[ ## confidence ## ]]
high

[[ ## completed ## ]]
```

#### 3. JSONAdapter Implementation (`dspy/adapters/json_adapter.py`)
**Advanced Features**:
- **Structured Outputs**: Uses OpenAI's structured output API when available
- **JSON Schema Generation**: Automatic Pydantic model creation from signatures
- **Graceful Degradation**: Falls back to JSON object mode if structured outputs fail
- **Open-ended Mapping Detection**: Handles `dict[str, Any]` types appropriately

**JSON Response Format**:
```json
{
  "answer": "The capital of France is Paris.",
  "confidence": "high"
}
```

#### 4. Custom Type System (`dspy/adapters/types/`)
**BaseType Architecture**:
- **Format Method**: Each type implements `format()` returning content blocks
- **Content Blocks**: Returns OpenAI-style content arrays
- **Serialization**: Custom JSON serialization with identifiers
- **Extraction**: Recursive type extraction from complex annotations

**Supported Types**:
- **Image**: Vision inputs with URL support
- **Audio**: Audio file processing
- **Tool**: Function calling definitions
- **History**: Conversation state management

### 🎯 DSPy Adapter Strengths

1. **Provider Agnostic**: Works across different LLM providers
2. **Structured Output Support**: Native JSON schema generation
3. **Tool Integration**: Built-in function calling support
4. **Type Safety**: Strong typing with Pydantic integration
5. **Graceful Fallbacks**: Multiple adaptation strategies
6. **Multimodal Support**: Vision, audio, and text inputs

### ❌ DSPy Adapter Limitations

1. **Python-Specific**: Heavy reliance on Python introspection
2. **Complex Dependencies**: LiteLLM, Pydantic, json_repair dependencies
3. **Parsing Brittleness**: Regex-based parsing for structured outputs
4. **Limited Extensibility**: Hard to add custom formatting strategies
5. **Callback Overhead**: Decorator-based callback system complexity

## Current DSPEx Adapter Analysis

### ✅ Current Implementation (`lib/dspex/adapter.ex`)

**Features**:
- **Simple Interface**: Basic `format_messages/2` and `parse_response/2`
- **Input Validation**: Validates required signature fields
- **Error Handling**: Categorized error reasons
- **Prompt Building**: Basic prompt construction from inputs

**Current Limitations**:
```elixir
# Limited to single-field outputs
defp parse_output_text([single_field], response_text) do
  {:ok, %{single_field => String.trim(response_text)}}
end

# No structured output support
# No multi-modal inputs
# No demonstration handling
# No conversation history
```

### 🚫 Missing Components

1. **No Behaviour Definition**: No formal adapter contract
2. **No Demonstration Support**: Can't handle few-shot examples
3. **No Structured Outputs**: No JSON schema generation
4. **No Multi-modal Support**: Text only
5. **No Provider Optimization**: One-size-fits-all approach
6. **No Tool Integration**: No function calling support

## Elixir-Native Adapter Design

### 🎯 Design Philosophy

**Leverage Elixir Strengths**:
- **Pattern Matching**: Use pattern matching for response parsing
- **Behaviours**: Define clear contracts with behaviours
- **Protocols**: Enable polymorphic formatting across types
- **Supervision**: Robust error handling with supervision trees
- **Concurrency**: Parallel processing of demonstrations
- **Immutability**: Safe transformations without side effects

### 📋 Core Behaviour Definition

```elixir
# lib/dspex/adapter.ex
defmodule DSPEx.Adapter do
  @moduledoc """
  Behaviour for adapting DSPEx signatures to LLM providers.
  
  Adapters handle the translation between DSPEx's structured signatures
  and provider-specific message formats, including demonstration formatting,
  structured output generation, and response parsing.
  """
  
  @type signature :: module()
  @type inputs :: map()
  @type outputs :: map()
  @type demonstrations :: [%{inputs: inputs(), outputs: outputs()}]
  @type message :: %{role: String.t(), content: term()}
  @type messages :: [message()]
  @type api_response :: term()
  @type adapter_options :: %{
    optional(:provider) => atom(),
    optional(:structured_output) => boolean(),
    optional(:include_examples) => boolean(),
    optional(:conversation_history) => [message()],
    optional(:custom_instructions) => String.t()
  }
  
  @doc """
  Format signature inputs and demonstrations into LLM messages.
  
  Converts DSPEx signature inputs along with optional demonstrations
  and conversation history into a message format suitable for the LLM.
  """
  @callback format_messages(
    signature(),
    inputs(),
    demonstrations(),
    adapter_options()
  ) :: {:ok, messages()} | {:error, term()}
  
  @doc """
  Parse LLM response back to signature outputs.
  
  Extracts structured outputs from the LLM response according to
  the signature's output field definitions.
  """
  @callback parse_response(
    signature(), 
    api_response(),
    adapter_options()
  ) :: {:ok, outputs()} | {:error, term()}
  
  @doc """
  Generate provider-specific optimization parameters.
  
  Returns provider-specific parameters that can improve performance,
  such as response format specifications, temperature adjustments,
  or max token limits.
  """
  @callback optimize_for_provider(
    signature(),
    atom(),
    adapter_options()
  ) :: {:ok, map()} | {:error, term()}
  
  @optional_callbacks [optimize_for_provider: 3]
end
```

### 🔧 Protocol-Based Multi-Modal Support

```elixir
# lib/dspex/adapters/protocols/formattable.ex
defprotocol DSPEx.Adapters.Formattable do
  @moduledoc """
  Protocol for formatting different input types into LLM-compatible content.
  
  Enables polymorphic formatting of text, images, audio, and custom types
  without requiring adapters to handle each type explicitly.
  """
  
  @doc """
  Format the input into LLM content blocks.
  
  Returns either a string for simple text content or a list of content
  blocks for complex multi-modal inputs.
  """
  @spec format(t()) :: String.t() | [%{type: String.t(), content: term()}]
  def format(input)
  
  @doc """
  Get the content type for provider compatibility checking.
  """
  @spec content_type(t()) :: :text | :image | :audio | :custom
  def content_type(input)
end

# Text implementation
defimpl DSPEx.Adapters.Formattable, for: BitString do
  def format(text), do: text
  def content_type(_), do: :text
end

# Image support
defmodule DSPEx.Adapters.Image do
  @enforce_keys [:url]
  defstruct [:url, :detail]
  
  @type t :: %__MODULE__{
    url: String.t(),
    detail: :low | :high | nil
  }
end

defimpl DSPEx.Adapters.Formattable, for: DSPEx.Adapters.Image do
  def format(%{url: url, detail: detail}) do
    content = %{type: "image_url", image_url: %{url: url}}
    if detail, do: put_in(content.image_url.detail, detail), else: content
  end
  
  def content_type(_), do: :image
end

# List support for mixed content
defimpl DSPEx.Adapters.Formattable, for: List do
  def format(items) do
    Enum.flat_map(items, fn item ->
      case DSPEx.Adapters.Formattable.format(item) do
        content when is_binary(content) ->
          [%{type: "text", text: content}]
        content when is_map(content) ->
          [content]
        content when is_list(content) ->
          content
      end
    end)
  end
  
  def content_type(items) do
    types = Enum.map(items, &DSPEx.Adapters.Formattable.content_type/1)
    if Enum.all?(types, &(&1 == :text)), do: :text, else: :mixed
  end
end
```

### 🏗️ Concrete Adapter Implementations

#### 1. Chat Adapter with Elixir Pattern Matching

```elixir
# lib/dspex/adapters/chat_adapter.ex
defmodule DSPEx.Adapters.ChatAdapter do
  @moduledoc """
  Chat-based adapter using field markers for structured parsing.
  
  Uses Elixir pattern matching for robust response parsing and
  provides clear field delineation for LLM understanding.
  """
  
  @behaviour DSPEx.Adapter
  
  require Logger
  
  @field_marker_regex ~r/\[\[\s*##\s*(\w+)\s*##\s*\]\]/
  @completion_marker "[[ ## completed ## ]]"
  
  @impl DSPEx.Adapter
  def format_messages(signature, inputs, demonstrations, options) do
    with {:ok, system_message} <- build_system_message(signature, options),
         {:ok, demo_messages} <- format_demonstrations(signature, demonstrations),
         {:ok, user_message} <- build_user_message(signature, inputs, options) do
      
      messages = [
        %{role: "system", content: system_message}
        | demo_messages
      ] ++ [%{role: "user", content: user_message}]
      
      {:ok, messages}
    end
  end
  
  @impl DSPEx.Adapter
  def parse_response(signature, response, _options) do
    with {:ok, content} <- extract_content(response),
         {:ok, sections} <- parse_field_sections(content),
         {:ok, outputs} <- validate_and_convert_outputs(signature, sections) do
      {:ok, outputs}
    end
  end
  
  @impl DSPEx.Adapter
  def optimize_for_provider(signature, provider, options) do
    base_params = %{
      temperature: 0.7,
      max_tokens: calculate_max_tokens(signature)
    }
    
    provider_params = case provider do
      :openai ->
        Map.put(base_params, :response_format, %{type: "text"})
      
      :anthropic ->
        # Claude performs better with explicit instructions
        Map.put(base_params, :system_role_supported, true)
      
      :gemini ->
        # Gemini benefits from lower temperature for structured outputs
        Map.put(base_params, :temperature, 0.3)
      
      _ ->
        base_params
    end
    
    {:ok, provider_params}
  end
  
  # Private implementation functions
  
  defp build_system_message(signature, options) do
    instructions = [
      build_field_descriptions(signature),
      build_output_format_instructions(signature),
      build_task_description(signature),
      Map.get(options, :custom_instructions)
    ]
    |> Enum.filter(& &1)
    |> Enum.join("\n\n")
    
    {:ok, instructions}
  end
  
  defp build_field_descriptions(signature) do
    input_desc = format_field_list(signature.input_fields(), "Input")
    output_desc = format_field_list(signature.output_fields(), "Output")
    
    "#{input_desc}\n\n#{output_desc}"
  end
  
  defp format_field_list(fields, role) do
    field_descriptions = 
      Enum.map_join(fields, "\n", fn field ->
        "- #{field}: #{get_field_description(field)}"
      end)
    
    "#{role} fields:\n#{field_descriptions}"
  end
  
  defp build_output_format_instructions(signature) do
    field_markers = 
      Enum.map_join(signature.output_fields(), "\n", fn field ->
        "[[ ## #{field} ## ]]\n{your #{field} here}"
      end)
    
    """
    Structure your response using these exact field markers:
    
    #{field_markers}
    
    #{@completion_marker}
    """
  end
  
  defp format_demonstrations(signature, demonstrations) do
    messages = 
      Enum.flat_map(demonstrations, fn demo ->
        user_content = format_demo_inputs(signature, demo.inputs)
        assistant_content = format_demo_outputs(signature, demo.outputs)
        
        [
          %{role: "user", content: user_content},
          %{role: "assistant", content: assistant_content}
        ]
      end)
    
    {:ok, messages}
  end
  
  defp format_demo_inputs(signature, inputs) do
    Enum.map_join(signature.input_fields(), "\n", fn field ->
      value = Map.get(inputs, field)
      formatted_value = DSPEx.Adapters.Formattable.format(value)
      
      case formatted_value do
        content when is_binary(content) -> "#{field}: #{content}"
        _complex_content -> "#{field}: [complex content]"
      end
    end)
  end
  
  defp format_demo_outputs(signature, outputs) do
    field_content = 
      Enum.map_join(signature.output_fields(), "\n\n", fn field ->
        value = Map.get(outputs, field, "")
        "[[ ## #{field} ## ]]\n#{value}"
      end)
    
    "#{field_content}\n\n#{@completion_marker}"
  end
  
  defp parse_field_sections(content) do
    # Split content by field markers using regex
    sections = 
      @field_marker_regex
      |> Regex.split(content, include_captures: true, trim: true)
      |> parse_sections_list()
    
    {:ok, sections}
  end
  
  defp parse_sections_list(parts) do
    parts
    |> Enum.chunk_every(2)
    |> Enum.reduce(%{}, fn
      [field_name, field_content], acc ->
        cleaned_content = 
          field_content
          |> String.replace(@completion_marker, "")
          |> String.trim()
        
        Map.put(acc, String.to_existing_atom(field_name), cleaned_content)
      
      _incomplete_chunk, acc ->
        acc
    end)
  rescue
    ArgumentError ->
      # Handle case where field name doesn't exist as atom
      Logger.warning("Unknown field encountered in response parsing")
      %{}
  end
  
  defp validate_and_convert_outputs(signature, sections) do
    expected_fields = signature.output_fields()
    
    case Map.keys(sections) -- expected_fields do
      [] ->
        # All required fields present
        converted_outputs = 
          Enum.reduce(expected_fields, %{}, fn field, acc ->
            raw_value = Map.get(sections, field, "")
            converted_value = convert_output_value(field, raw_value, signature)
            Map.put(acc, field, converted_value)
          end)
        
        {:ok, converted_outputs}
      
      missing_fields ->
        {:error, {:missing_fields, missing_fields}}
    end
  end
  
  defp convert_output_value(field, raw_value, signature) do
    # Get expected type from signature metadata if available
    field_type = get_field_type(signature, field)
    
    case field_type do
      :integer ->
        case Integer.parse(raw_value) do
          {int_val, _} -> int_val
          :error -> raw_value
        end
      
      :float ->
        case Float.parse(raw_value) do
          {float_val, _} -> float_val
          :error -> raw_value
        end
      
      :boolean ->
        case String.downcase(String.trim(raw_value)) do
          val when val in ["true", "yes", "1"] -> true
          val when val in ["false", "no", "0"] -> false
          _ -> raw_value
        end
      
      _ ->
        String.trim(raw_value)
    end
  end
  
  defp get_field_type(signature, field) do
    # Try to get type information from signature metadata
    if function_exported?(signature, :field_types, 0) do
      signature.field_types()
      |> Map.get(field, :string)
    else
      :string
    end
  end
end
```

#### 2. JSON Adapter with Schema Generation

```elixir
# lib/dspex/adapters/json_adapter.ex
defmodule DSPEx.Adapters.JSONAdapter do
  @moduledoc """
  JSON-based adapter with automatic schema generation.
  
  Leverages ExLLM's structured output capabilities and provides
  robust JSON parsing with graceful fallbacks.
  """
  
  @behaviour DSPEx.Adapter
  
  require Logger
  
  @impl DSPEx.Adapter
  def format_messages(signature, inputs, demonstrations, options) do
    with {:ok, system_message} <- build_json_system_message(signature, options),
         {:ok, demo_messages} <- format_json_demonstrations(signature, demonstrations),
         {:ok, user_message} <- build_json_user_message(signature, inputs, options) do
      
      messages = [
        %{role: "system", content: system_message}
        | demo_messages
      ] ++ [%{role: "user", content: user_message}]
      
      {:ok, messages}
    end
  end
  
  @impl DSPEx.Adapter
  def parse_response(signature, response, options) do
    with {:ok, content} <- extract_content(response),
         {:ok, parsed_json} <- parse_json_response(content),
         {:ok, validated_outputs} <- validate_json_outputs(signature, parsed_json) do
      {:ok, validated_outputs}
    else
      {:error, :invalid_json} ->
        # Fallback to regex extraction
        fallback_json_parsing(signature, response, options)
      
      error ->
        error
    end
  end
  
  @impl DSPEx.Adapter
  def optimize_for_provider(signature, provider, options) do
    base_params = %{
      temperature: 0.3,  # Lower temperature for structured outputs
      max_tokens: calculate_max_tokens(signature)
    }
    
    structured_output_params = case {provider, supports_structured_output?(provider)} do
      {:openai, true} ->
        schema = generate_json_schema(signature)
        Map.merge(base_params, %{
          response_format: %{
            type: "json_schema",
            json_schema: %{
              name: "#{signature}_response",
              schema: schema,
              strict: true
            }
          }
        })
      
      {_, true} ->
        # Basic JSON object mode
        Map.put(base_params, :response_format, %{type: "json_object"})
      
      _ ->
        # No structured output support
        base_params
    end
    
    {:ok, structured_output_params}
  end
  
  # Private implementation functions
  
  defp build_json_system_message(signature, options) do
    schema = generate_json_schema(signature)
    schema_text = Jason.encode!(schema, pretty: true)
    
    instructions = """
    You will respond with a valid JSON object that matches the following schema exactly:
    
    ```json
    #{schema_text}
    ```
    
    #{build_field_descriptions(signature)}
    
    #{signature.instructions()}
    
    #{Map.get(options, :custom_instructions, "")}
    
    Ensure your response contains only valid JSON and includes all required fields.
    """
    
    {:ok, String.trim(instructions)}
  end
  
  defp generate_json_schema(signature) do
    properties = 
      signature.output_fields()
      |> Enum.map(fn field ->
        {to_string(field), infer_json_type(signature, field)}
      end)
      |> Enum.into(%{})
    
    %{
      type: "object",
      properties: properties,
      required: Enum.map(signature.output_fields(), &to_string/1),
      additionalProperties: false
    }
  end
  
  defp infer_json_type(signature, field) do
    # Try to get type information from signature
    case get_field_type(signature, field) do
      :integer -> %{type: "integer"}
      :float -> %{type: "number"}
      :boolean -> %{type: "boolean"}
      :list -> %{type: "array", items: %{type: "string"}}
      _ -> %{type: "string"}
    end
  end
  
  defp format_json_demonstrations(signature, demonstrations) do
    messages = 
      Enum.flat_map(demonstrations, fn demo ->
        user_content = format_demo_inputs(signature, demo.inputs)
        assistant_content = Jason.encode!(demo.outputs, pretty: true)
        
        [
          %{role: "user", content: user_content},
          %{role: "assistant", content: assistant_content}
        ]
      end)
    
    {:ok, messages}
  end
  
  defp parse_json_response(content) do
    # Try to extract JSON from response using regex
    json_pattern = ~r/\{(?:[^{}]|(?R))*\}/
    
    case Regex.run(json_pattern, content) do
      [json_string] ->
        case Jason.decode(json_string) do
          {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
          {:ok, _} -> {:error, :invalid_json_structure}
          {:error, _} -> {:error, :invalid_json}
        end
      
      nil ->
        # Try parsing the entire content as JSON
        case Jason.decode(content) do
          {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
          _ -> {:error, :invalid_json}
        end
    end
  end
  
  defp validate_json_outputs(signature, parsed_json) do
    expected_fields = signature.output_fields()
    
    # Convert string keys to atom keys
    atom_json = 
      parsed_json
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Enum.into(%{})
    
    # Check for missing fields
    missing_fields = expected_fields -- Map.keys(atom_json)
    
    case missing_fields do
      [] ->
        # Type conversion if needed
        converted_outputs = 
          Enum.reduce(expected_fields, %{}, fn field, acc ->
            raw_value = Map.get(atom_json, field)
            converted_value = convert_json_value(field, raw_value, signature)
            Map.put(acc, field, converted_value)
          end)
        
        {:ok, converted_outputs}
      
      _ ->
        {:error, {:missing_fields, missing_fields}}
    end
  rescue
    ArgumentError ->
      {:error, :unknown_fields_in_response}
  end
  
  defp supports_structured_output?(provider) do
    # Check if provider supports structured outputs
    case provider do
      :openai -> true
      :anthropic -> false  # Claude doesn't support structured outputs yet
      :gemini -> true
      :groq -> true
      _ -> false
    end
  end
end
```

#### 3. Multi-Modal Adapter

```elixir
# lib/dspex/adapters/multimodal_adapter.ex
defmodule DSPEx.Adapters.MultiModalAdapter do
  @moduledoc """
  Multi-modal adapter supporting text, images, audio, and custom types.
  
  Uses the Formattable protocol to handle different input types and
  generates appropriate content blocks for vision-enabled models.
  """
  
  @behaviour DSPEx.Adapter
  
  @impl DSPEx.Adapter
  def format_messages(signature, inputs, demonstrations, options) do
    with {:ok, system_message} <- build_multimodal_system_message(signature, options),
         {:ok, demo_messages} <- format_multimodal_demonstrations(signature, demonstrations),
         {:ok, user_message} <- build_multimodal_user_message(signature, inputs, options) do
      
      messages = [
        %{role: "system", content: system_message}
        | demo_messages
      ] ++ [user_message]
      
      {:ok, messages}
    end
  end
  
  @impl DSPEx.Adapter
  def parse_response(signature, response, options) do
    # Use JSON parsing for structured outputs
    DSPEx.Adapters.JSONAdapter.parse_response(signature, response, options)
  end
  
  @impl DSPEx.Adapter
  def optimize_for_provider(signature, provider, options) do
    # Check if provider supports vision
    vision_support = supports_vision?(provider)
    
    base_params = %{
      temperature: 0.7,
      max_tokens: calculate_multimodal_max_tokens(signature, options)
    }
    
    vision_params = if vision_support do
      Map.put(base_params, :model, get_vision_model(provider))
    else
      base_params
    end
    
    {:ok, vision_params}
  end
  
  # Private implementation functions
  
  defp build_multimodal_user_message(signature, inputs, _options) do
    content_blocks = 
      signature.input_fields()
      |> Enum.flat_map(fn field ->
        value = Map.get(inputs, field)
        format_input_field(field, value)
      end)
    
    # If all content is text, return simple string content
    if all_text_content?(content_blocks) do
      text_content = 
        content_blocks
        |> Enum.map_join("\n", fn %{text: text} -> text end)
      
      {:ok, %{role: "user", content: text_content}}
    else
      {:ok, %{role: "user", content: content_blocks}}
    end
  end
  
  defp format_input_field(field, value) do
    formatted = DSPEx.Adapters.Formattable.format(value)
    
    case formatted do
      text when is_binary(text) ->
        [%{type: "text", text: "#{field}: #{text}"}]
      
      content_block when is_map(content_block) ->
        [content_block]
      
      content_blocks when is_list(content_blocks) ->
        [%{type: "text", text: "#{field}:"}] ++ content_blocks
    end
  end
  
  defp all_text_content?(content_blocks) do
    Enum.all?(content_blocks, fn block ->
      Map.get(block, :type) == "text"
    end)
  end
  
  defp supports_vision?(provider) do
    case provider do
      :openai -> true
      :anthropic -> true
      :gemini -> true
      :groq -> false
      _ -> false
    end
  end
  
  defp get_vision_model(provider) do
    case provider do
      :openai -> "gpt-4o"
      :anthropic -> "claude-3-5-sonnet-20241022"
      :gemini -> "gemini-pro-vision"
      _ -> nil
    end
  end
end
```

### 🔧 Adapter Factory and Selection

```elixir
# lib/dspex/adapters/factory.ex
defmodule DSPEx.Adapters.Factory do
  @moduledoc """
  Factory for selecting and configuring adapters based on requirements.
  
  Analyzes signature characteristics and provider capabilities to
  recommend the optimal adapter for a given use case.
  """
  
  @type adapter_type :: :chat | :json | :multimodal | :custom
  @type recommendation :: %{
    adapter: module(),
    reason: String.t(),
    confidence: float(),
    alternatives: [module()]
  }
  
  @doc """
  Recommend the best adapter for a signature and provider combination.
  """
  @spec recommend_adapter(module(), atom(), map()) :: recommendation()
  def recommend_adapter(signature, provider, options \\ %{}) do
    signature_analysis = analyze_signature(signature)
    provider_capabilities = analyze_provider(provider)
    
    recommendations = [
      evaluate_multimodal_adapter(signature_analysis, provider_capabilities),
      evaluate_json_adapter(signature_analysis, provider_capabilities),
      evaluate_chat_adapter(signature_analysis, provider_capabilities)
    ]
    |> Enum.sort_by(& &1.confidence, :desc)
    |> List.first()
    
    recommendations
  end
  
  @doc """
  Create an adapter instance with optimal configuration.
  """
  @spec create_adapter(adapter_type(), map()) :: {:ok, module()} | {:error, term()}
  def create_adapter(adapter_type, config \\ %{}) do
    case adapter_type do
      :chat -> {:ok, DSPEx.Adapters.ChatAdapter}
      :json -> {:ok, DSPEx.Adapters.JSONAdapter}
      :multimodal -> {:ok, DSPEx.Adapters.MultiModalAdapter}
      :custom -> create_custom_adapter(config)
      _ -> {:error, :unknown_adapter_type}
    end
  end
  
  # Private analysis functions
  
  defp analyze_signature(signature) do
    %{
      input_count: length(signature.input_fields()),
      output_count: length(signature.output_fields()),
      has_multimodal_inputs: has_multimodal_fields?(signature),
      complexity: calculate_complexity(signature),
      structured_outputs: requires_structured_outputs?(signature)
    }
  end
  
  defp analyze_provider(provider) do
    %{
      supports_vision: supports_vision?(provider),
      supports_structured_output: supports_structured_output?(provider),
      supports_function_calling: supports_function_calling?(provider),
      context_window: get_context_window(provider),
      performance_tier: get_performance_tier(provider)
    }
  end
  
  defp evaluate_multimodal_adapter(sig_analysis, provider_caps) do
    confidence = case {sig_analysis.has_multimodal_inputs, provider_caps.supports_vision} do
      {true, true} -> 0.95
      {true, false} -> 0.1  # Needs vision but provider doesn't support
      {false, _} -> 0.3     # Could still be useful
    end
    
    %{
      adapter: DSPEx.Adapters.MultiModalAdapter,
      reason: "Best for multi-modal inputs with vision support",
      confidence: confidence,
      alternatives: [DSPEx.Adapters.JSONAdapter]
    }
  end
  
  defp evaluate_json_adapter(sig_analysis, provider_caps) do
    confidence = case {sig_analysis.structured_outputs, provider_caps.supports_structured_output} do
      {true, true} -> 0.9
      {true, false} -> 0.7   # Structured needed but basic JSON mode
      {false, _} -> 0.6      # Always decent fallback
    end
    
    %{
      adapter: DSPEx.Adapters.JSONAdapter,
      reason: "Optimal for structured outputs and complex types",
      confidence: confidence,
      alternatives: [DSPEx.Adapters.ChatAdapter]
    }
  end
  
  defp evaluate_chat_adapter(sig_analysis, _provider_caps) do
    # Chat adapter works everywhere but may not be optimal
    confidence = case sig_analysis.complexity do
      :low -> 0.8
      :medium -> 0.6
      :high -> 0.4
    end
    
    %{
      adapter: DSPEx.Adapters.ChatAdapter,
      reason: "Reliable fallback with broad compatibility",
      confidence: confidence,
      alternatives: []
    }
  end
end
```

### 🧪 Testing Infrastructure

```elixir
# test/support/adapter_test_helpers.ex
defmodule DSPEx.AdapterTestHelpers do
  @moduledoc """
  Test helpers for adapter testing with property-based validation.
  """
  
  import ExUnit.Assertions
  import Mox
  
  @doc """
  Test adapter round-trip consistency.
  
  Verifies that format_messages -> LLM -> parse_response produces
  consistent outputs for a given signature and input set.
  """
  def test_adapter_roundtrip(adapter, signature, inputs, demonstrations \\ []) do
    options = %{}
    
    # Format messages
    {:ok, messages} = adapter.format_messages(signature, inputs, demonstrations, options)
    
    # Mock LLM response
    mock_response = generate_mock_response(signature, inputs)
    
    # Parse response
    {:ok, outputs} = adapter.parse_response(signature, mock_response, options)
    
    # Validate output structure
    assert Map.keys(outputs) == signature.output_fields()
    
    # Validate output types if signature provides type information
    if function_exported?(signature, :field_types, 0) do
      validate_output_types(signature, outputs)
    end
    
    outputs
  end
  
  @doc """
  Property test generator for signature inputs.
  """
  def generate_signature_inputs(signature) do
    signature.input_fields()
    |> Enum.map(fn field ->
      {field, generate_field_value(field, signature)}
    end)
    |> Enum.into(%{})
  end
  
  @doc """
  Validate adapter behavior across different provider configurations.
  """
  def test_provider_compatibility(adapter, signature, providers) do
    inputs = generate_signature_inputs(signature)
    
    Enum.each(providers, fn provider ->
      {:ok, optimization_params} = adapter.optimize_for_provider(signature, provider, %{})
      
      # Verify optimization params are valid
      assert is_map(optimization_params)
      
      # Test message formatting works with provider-specific options
      {:ok, messages} = adapter.format_messages(signature, inputs, [], %{provider: provider})
      
      # Verify message structure is valid
      assert is_list(messages)
      assert Enum.all?(messages, &valid_message?/1)
    end)
  end
  
  # Private test helpers
  
  defp generate_mock_response(signature, _inputs) do
    # Generate appropriate mock response based on signature
    outputs = 
      signature.output_fields()
      |> Enum.map(fn field -> {field, "mock_#{field}_value"} end)
      |> Enum.into(%{})
    
    # Format as API response
    %{
      choices: [
        %{
          message: %{
            role: "assistant",
            content: format_mock_content(signature, outputs)
          }
        }
      ]
    }
  end
  
  defp format_mock_content(signature, outputs) do
    # Check if signature expects JSON or field markers
    if requires_json_format?(signature) do
      Jason.encode!(outputs)
    else
      format_chat_style_response(signature, outputs)
    end
  end
  
  defp format_chat_style_response(signature, outputs) do
    field_content = 
      Enum.map_join(signature.output_fields(), "\n\n", fn field ->
        value = Map.get(outputs, field, "")
        "[[ ## #{field} ## ]]\n#{value}"
      end)
    
    "#{field_content}\n\n[[ ## completed ## ]]"
  end
end

# Example property-based test
defmodule DSPEx.Adapters.ChatAdapterTest do
  use ExUnit.Case
  use PropCheck
  
  import DSPEx.AdapterTestHelpers
  
  alias DSPEx.Adapters.ChatAdapter
  
  defmodule TestSignature do
    use DSPEx.Signature, "question -> answer, confidence"
    
    def field_types do
      %{
        question: :string,
        answer: :string,
        confidence: :string
      }
    end
  end
  
  property "chat adapter handles valid inputs consistently" do
    forall inputs <- generate_signature_inputs(TestSignature) do
      outputs = test_adapter_roundtrip(ChatAdapter, TestSignature, inputs)
      
      # Verify required fields are present
      assert Map.has_key?(outputs, :answer)
      assert Map.has_key?(outputs, :confidence)
      
      # Verify outputs are strings
      assert is_binary(outputs.answer)
      assert is_binary(outputs.confidence)
    end
  end
  
  test "provider optimization generates valid parameters" do
    test_provider_compatibility(ChatAdapter, TestSignature, [:openai, :anthropic, :gemini])
  end
end
```

## Implementation Roadmap

### Phase 1: Core Behaviour & Protocol (Week 1)
- [ ] Define `DSPEx.Adapter` behaviour with callbacks
- [ ] Implement `DSPEx.Adapters.Formattable` protocol
- [ ] Create basic multi-modal type structs (Image, Audio)
- [ ] Update existing adapter to implement behaviour

### Phase 2: Chat Adapter Enhancement (Week 1-2)
- [ ] Implement robust `DSPEx.Adapters.ChatAdapter`
- [ ] Add field marker parsing with pattern matching
- [ ] Support demonstration formatting
- [ ] Provider-specific optimizations

### Phase 3: JSON Adapter with Schema Generation (Week 2-3)
- [ ] Implement `DSPEx.Adapters.JSONAdapter`
- [ ] JSON schema generation from signatures
- [ ] Structured output integration with ExLLM
- [ ] Graceful fallback strategies

### Phase 4: Multi-Modal Support (Week 3)
- [ ] Implement `DSPEx.Adapters.MultiModalAdapter`
- [ ] Vision input support via protocol
- [ ] Content block generation
- [ ] Provider vision capability detection

### Phase 5: Factory & Selection (Week 3-4)
- [ ] Implement `DSPEx.Adapters.Factory`
- [ ] Adapter recommendation algorithms
- [ ] Provider capability analysis
- [ ] Configuration optimization

### Phase 6: Testing & Validation (Week 4)
- [ ] Property-based test helpers
- [ ] Round-trip consistency testing
- [ ] Provider compatibility validation
- [ ] Performance benchmarking

## Benefits Summary

### 🚀 **Elixir-Native Advantages**
- **Pattern Matching**: Robust response parsing without regex brittleness
- **Behaviours**: Clear contracts with compile-time checking
- **Protocols**: Polymorphic multi-modal support
- **Concurrency**: Parallel demonstration processing
- **Error Handling**: Graceful degradation with supervision

### 🎯 **Superior Architecture**
- **Type Safety**: Compile-time adapter contract verification
- **Extensibility**: Easy custom adapter development
- **Provider Agnostic**: Works with any ExLLM-supported provider
- **Performance**: Optimized for each provider's capabilities
- **Testing**: Property-based validation with comprehensive coverage

### 📈 **Maintenance Benefits**
- **Less Complexity**: No external parsing dependencies
- **Clear Separation**: Protocol-based type handling
- **Flexible Selection**: Automatic adapter recommendation
- **Future-Proof**: Easy integration of new LLM features
- **Documentation**: Clear behaviour contracts with examples

This Elixir-native adapter system leverages the language's strengths while providing superior functionality compared to DSPy's Python-centric approach, resulting in more robust, maintainable, and performant prompt engineering capabilities.