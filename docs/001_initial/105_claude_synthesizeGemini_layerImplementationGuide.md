# DSPEx Adapter Layer Implementation Guide

## Overview

The Adapter layer is the crucial bridge between DSPEx's declarative signatures and the specific prompt formats required by different language models. This document provides detailed implementation guidance for building a robust, extensible adapter system that handles the complexities of prompt construction, demonstration formatting, and response parsing.

## Core Adapter Architecture

### 1. Adapter Behaviour Definition

```elixir
defmodule DSPEx.Adapter do
  @moduledoc """
  Behaviour defining the contract for all DSPEx adapters.
  
  Adapters are responsible for translating between high-level DSPEx abstractions
  (signatures, examples, predictions) and the specific formats required by 
  language model APIs.
  """
  
  alias DSPEx.{Signature, Example, Prediction}
  
  @doc """
  Format a request for the language model.
  
  Takes a signature, list of demonstration examples, and current inputs,
  and produces the messages list that will be sent to the LM API.
  """
  @callback format(
    signature :: module(), 
    demos :: list(Example.t()), 
    inputs :: map(),
    opts :: keyword()
  ) :: {:ok, list(map())} | {:error, term()}
  
  @doc """
  Parse a language model response into structured outputs.
  
  Takes the raw response from the LM API and extracts the structured
  outputs defined by the signature.
  """
  @callback parse(
    signature :: module(), 
    response :: map(),
    opts :: keyword()
  ) :: {:ok, map()} | {:error, term()}
  
  @doc """
  Check if this adapter supports streaming responses.
  """
  @callback supports_streaming?() :: boolean()
  
  @doc """
  Get the name/identifier for this adapter.
  """
  @callback name() :: atom()
  
  @optional_callbacks [supports_streaming?: 0]
end
```

### 2. Chat Adapter Implementation

```elixir
defmodule DSPEx.Adapter.Chat do
  @behaviour DSPEx.Adapter
  
  require Logger
  
  @impl DSPEx.Adapter
  def format(signature, demos, inputs, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id)
    
    context = Foundation.ErrorContext.new(__MODULE__, :format,
      correlation_id: correlation_id,
      metadata: %{
        signature: signature,
        demo_count: length(demos),
        input_fields: Map.keys(inputs)
      }
    )
    
    Foundation.ErrorContext.with_context(context, fn ->
      with {:ok, system_message} <- build_system_message(signature, opts),
           {:ok, demo_messages} <- build_demo_messages(signature, demos, opts),
           {:ok, user_message} <- build_user_message(signature, inputs, opts) do
        
        messages = [system_message] ++ demo_messages ++ [user_message]
        
        # Emit formatting telemetry
        Foundation.Telemetry.emit_counter([:dspex, :adapter, :format, :success], %{
          adapter: :chat,
          signature: signature,
          demo_count: length(demos),
          correlation_id: correlation_id
        })
        
        {:ok, messages}
      else
        {:error, reason} ->
          Foundation.Telemetry.emit_counter([:dspex, :adapter, :format, :error], %{
            adapter: :chat,
            signature: signature,
            error_type: reason,
            correlation_id: correlation_id
          })
          
          {:error, DSPEx.Error.adapter_format_error(reason, %{
            signature: signature,
            correlation_id: correlation_id
          })}
      end
    end)
  end
  
  @impl DSPEx.Adapter
  def parse(signature, response, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id)
    
    context = Foundation.ErrorContext.new(__MODULE__, :parse,
      correlation_id: correlation_id,
      metadata: %{signature: signature}
    )
    
    Foundation.ErrorContext.with_context(context, fn ->
      with {:ok, content} <- extract_content(response),
           {:ok, parsed_fields} <- parse_field_markers(signature, content) do
        
        # Validate that all required output fields are present
        case validate_parsed_outputs(signature, parsed_fields) do
          :ok ->
            Foundation.Telemetry.emit_counter([:dspex, :adapter, :parse, :success], %{
              adapter: :chat,
              signature: signature,
              correlation_id: correlation_id
            })
            
            {:ok, parsed_fields}
            
          {:error, missing_fields} ->
            error = DSPEx.Error.prediction_parse_error(
              content, 
              signature,
              %{missing_fields: missing_fields, correlation_id: correlation_id}
            )
            
            Foundation.Telemetry.emit_counter([:dspex, :adapter, :parse, :error], %{
              adapter: :chat,
              signature: signature,
              error_type: :missing_fields,
              correlation_id: correlation_id
            })
            
            {:error, error}
        end
      end
    end)
  end
  
  @impl DSPEx.Adapter
  def supports_streaming?, do: true
  
  @impl DSPEx.Adapter
  def name, do: :chat
  
  # --- Private Implementation Functions ---
  
  defp build_system_message(signature, _opts) do
    instructions = signature.instructions()
    field_descriptions = build_field_descriptions(signature)
    format_instructions = build_format_instructions(signature)
    
    content = """
    #{instructions}
    
    #{field_descriptions}
    
    #{format_instructions}
    """
    
    message = %{
      role: "system",
      content: String.trim(content)
    }
    
    {:ok, message}
  end
  
  defp build_field_descriptions(signature) do
    input_desc = describe_fields(signature.input_fields(), "Input")
    output_desc = describe_fields(signature.output_fields(), "Output")
    
    """
    #{input_desc}
    
    #{output_desc}
    """
  end
  
  defp describe_fields(fields, label) do
    if Enum.empty?(fields) do
      ""
    else
      field_list = 
        fields
        |> Enum.map(fn field_name ->
          # Get field metadata if available
          desc = get_field_description(field_name)
          "- #{field_name}: #{desc}"
        end)
        |> Enum.join("\n")
      
      """
      #{label} Fields:
      #{field_list}
      """
    end
  end
  
  defp get_field_description(field_name) do
    # This could be enhanced to pull from signature metadata
    "#{field_name |> to_string() |> String.replace("_", " ") |> String.capitalize()}"
  end
  
  defp build_format_instructions(signature) do
    output_fields = signature.output_fields()
    
    if Enum.empty?(output_fields) do
      ""
    else
      field_examples = 
        output_fields
        |> Enum.map(fn field_name ->
          "[[ ## #{field_name} ## ]]"
        end)
        |> Enum.join("\n")
      
      """
      Please format your response using these field markers:
      #{field_examples}
      
      Place your response for each field immediately after its marker.
      """
    end
  end
  
  defp build_demo_messages(signature, demos, _opts) do
    messages = 
      demos
      |> Enum.flat_map(fn demo ->
        [
          build_demo_user_message(signature, demo),
          build_demo_assistant_message(signature, demo)
        ]
      end)
    
    {:ok, messages}
  end
  
  defp build_demo_user_message(signature, demo) do
    content = format_inputs_with_markers(signature.input_fields(), demo.inputs())
    
    %{
      role: "user",
      content: content
    }
  end
  
  defp build_demo_assistant_message(signature, demo) do
    content = format_outputs_with_markers(signature.output_fields(), demo.labels())
    
    %{
      role: "assistant", 
      content: content
    }
  end
  
  defp build_user_message(signature, inputs, _opts) do
    content = format_inputs_with_markers(signature.input_fields(), inputs)
    
    message = %{
      role: "user",
      content: content
    }
    
    {:ok, message}
  end
  
  defp format_inputs_with_markers(input_fields, data) do
    input_fields
    |> Enum.map(fn field_name ->
      value = Map.get(data, field_name, "")
      "[[ ## #{field_name} ## ]]\n#{value}"
    end)
    |> Enum.join("\n\n")
  end
  
  defp format_outputs_with_markers(output_fields, data) do
    output_fields
    |> Enum.map(fn field_name ->
      value = Map.get(data, field_name, "")
      "[[ ## #{field_name} ## ]]\n#{value}"
    end)
    |> Enum.join("\n\n")
  end
  
  defp extract_content(response) do
    case get_in(response, ["choices", 0, "message", "content"]) do
      content when is_binary(content) -> {:ok, content}
      nil -> {:error, :missing_content}
      _ -> {:error, :invalid_content_format}
    end
  end
  
  defp parse_field_markers(signature, content) do
    output_fields = signature.output_fields()
    
    parsed = 
      output_fields
      |> Enum.reduce(%{}, fn field_name, acc ->
        case extract_field_content(content, field_name) do
          {:ok, field_content} -> Map.put(acc, field_name, field_content)
          {:error, _} -> acc
        end
      end)
    
    {:ok, parsed}
  end
  
  defp extract_field_content(content, field_name) do
    # Regex pattern to match field markers and capture content
    # This handles multi-line content and stops at the next marker or end of string
    pattern = ~r/\[\[\s*##\s*#{Regex.escape(to_string(field_name))}\s*##\s*\]\]\s*(.*?)(?=\[\[\s*##\s*\w+\s*##\s*\]\]|\z)/s
    
    case Regex.run(pattern, content, capture: :all_but_first) do
      [captured_content] ->
        cleaned_content = 
          captured_content
          |> String.trim()
          |> remove_trailing_markers()
        
        {:ok, cleaned_content}
      
      nil ->
        {:error, :field_not_found}
    end
  end
  
  defp remove_trailing_markers(content) do
    # Remove any trailing field markers that might have been included
    String.replace(content, ~r/\[\[\s*##.*?##\s*\]\].*$/s, "")
    |> String.trim()
  end
  
  defp validate_parsed_outputs(signature, parsed_fields) do
    required_fields = signature.output_fields()
    missing_fields = 
      required_fields
      |> Enum.reject(fn field_name ->
        Map.has_key?(parsed_fields, field_name) and 
        not_empty?(Map.get(parsed_fields, field_name))
      end)
    
    case missing_fields do
      [] -> :ok
      fields -> {:error, fields}
    end
  end
  
  defp not_empty?(nil), do: false
  defp not_empty?(""), do: false
  defp not_empty?(content) when is_binary(content), do: String.trim(content) != ""
  defp not_empty?(_), do: true
end
```

## JSON Adapter Implementation

For structured output scenarios, a JSON adapter provides more reliable parsing:

```elixir
defmodule DSPEx.Adapter.JSON do
  @behaviour DSPEx.Adapter
  
  @impl DSPEx.Adapter
  def format(signature, demos, inputs, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id)
    
    context = Foundation.ErrorContext.new(__MODULE__, :format,
      correlation_id: correlation_id,
      metadata: %{signature: signature, demo_count: length(demos)}
    )
    
    Foundation.ErrorContext.with_context(context, fn ->
      with {:ok, system_message} <- build_json_system_message(signature),
           {:ok, demo_messages} <- build_json_demo_messages(signature, demos),
           {:ok, user_message} <- build_json_user_message(signature, inputs) do
        
        messages = [system_message] ++ demo_messages ++ [user_message]
        {:ok, messages}
      end
    end)
  end
  
  @impl DSPEx.Adapter
  def parse(signature, response, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id)
    
    context = Foundation.ErrorContext.new(__MODULE__, :parse,
      correlation_id: correlation_id,
      metadata: %{signature: signature}
    )
    
    Foundation.ErrorContext.with_context(context, fn ->
      with {:ok, content} <- extract_content(response),
           {:ok, json_content} <- extract_json_from_content(content),
           {:ok, parsed_json} <- parse_json(json_content),
           {:ok, validated_output} <- validate_json_output(signature, parsed_json) do
        
        {:ok, validated_output}
      else
        {:error, :json_parse_error} = error ->
          # Attempt JSON repair if available
          attempt_json_repair(content, signature, correlation_id)
        
        {:error, reason} ->
          {:error, DSPEx.Error.prediction_parse_error(content, signature, %{
            reason: reason,
            correlation_id: correlation_id
          })}
      end
    end)
  end
  
  @impl DSPEx.Adapter
  def supports_streaming?, do: false
  
  @impl DSPEx.Adapter
  def name, do: :json
  
  # --- Private Implementation Functions ---
  
  defp build_json_system_message(signature) do
    schema = build_json_schema(signature)
    
    content = """
    #{signature.instructions()}
    
    Please respond with valid JSON that matches this exact schema:
    
    #{Jason.encode!(schema, pretty: true)}
    
    Do not include any text outside of the JSON response.
    """
    
    message = %{
      role: "system",
      content: content
    }
    
    {:ok, message}
  end
  
  defp build_json_schema(signature) do
    properties = 
      signature.output_fields()
      |> Enum.reduce(%{}, fn field_name, acc ->
        Map.put(acc, field_name, %{
          type: "string",  # Can be enhanced for different types
          description: get_field_description(field_name)
        })
      end)
    
    required_fields = signature.output_fields()
    
    %{
      type: "object",
      properties: properties,
      required: required_fields,
      additionalProperties: false
    }
  end
  
  defp build_json_demo_messages(signature, demos) do
    messages = 
      demos
      |> Enum.flat_map(fn demo ->
        user_content = format_json_inputs(signature, demo.inputs())
        assistant_content = Jason.encode!(demo.labels())
        
        [
          %{role: "user", content: user_content},
          %{role: "assistant", content: assistant_content}
        ]
      end)
    
    {:ok, messages}
  end
  
  defp build_json_user_message(signature, inputs) do
    content = format_json_inputs(signature, inputs)
    
    message = %{
      role: "user",
      content: content
    }
    
    {:ok, message}
  end
  
  defp format_json_inputs(signature, inputs) do
    input_text = 
      signature.input_fields()
      |> Enum.map(fn field_name ->
        value = Map.get(inputs, field_name, "")
        "#{field_name}: #{value}"
      end)
      |> Enum.join("\n")
    
    "#{input_text}\n\nPlease respond with JSON:"
  end
  
  defp extract_json_from_content(content) do
    # Try to extract JSON from content that might have extra text
    json_pattern = ~r/\{.*\}/s
    
    case Regex.run(json_pattern, content) do
      [json_str] -> {:ok, json_str}
      nil -> {:error, :no_json_found}
    end
  end
  
  defp parse_json(json_content) do
    case Jason.decode(json_content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, :json_parse_error}
    end
  end
  
  defp validate_json_output(signature, parsed_json) do
    required_fields = signature.output_fields()
    
    # Convert string keys to atoms to match signature field names
    normalized_output = 
      parsed_json
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Enum.into(%{})
      |> Map.take(required_fields)
    
    missing_fields = required_fields -- Map.keys(normalized_output)
    
    case missing_fields do
      [] -> {:ok, normalized_output}
      fields -> {:error, {:missing_fields, fields}}
    end
  rescue
    ArgumentError ->
      {:error, :invalid_field_names}
  end
  
  defp attempt_json_repair(content, signature, correlation_id) do
    # Placeholder for JSON repair logic
    # In a full implementation, this could use a Port to call
    # a Python script with json-repair library
    Logger.warn("JSON parsing failed, repair not implemented", 
      correlation_id: correlation_id)
    
    {:error, :json_repair_not_available}
  end
  
  defp get_field_description(field_name) do
    # Enhanced version could pull from signature metadata
    field_name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
  
  defp extract_content(response) do
    case get_in(response, ["choices", 0, "message", "content"]) do
      content when is_binary(content) -> {:ok, content}
      nil -> {:error, :missing_content}
      _ -> {:error, :invalid_content_format}
    end
  end
end
```

## Adapter Selection and Configuration

```elixir
defmodule DSPEx.Adapter.Registry do
  @moduledoc """
  Registry for managing available adapters and their selection logic.
  """
  
  @adapters %{
    chat: DSPEx.Adapter.Chat,
    json: DSPEx.Adapter.JSON
  }
  
  def get_adapter(name) when is_atom(name) do
    case Map.get(@adapters, name) do
      nil -> {:error, :adapter_not_found}
      adapter_module -> {:ok, adapter_module}
    end
  end
  
  def list_adapters do
    Map.keys(@adapters)
  end
  
  def select_adapter_for_signature(signature, opts \\ []) do
    preferred = Keyword.get(opts, :adapter)
    
    cond do
      preferred && Map.has_key?(@adapters, preferred) ->
        {:ok, Map.get(@adapters, preferred)}
      
      structured_output_required?(signature) ->
        {:ok, DSPEx.Adapter.JSON}
      
      true ->
        {:ok, DSPEx.Adapter.Chat}
    end
  end
  
  defp structured_output_required?(signature) do
    # Logic to determine if structured output is needed
    # Could be based on signature metadata, field types, etc.
    output_fields = signature.output_fields()
    length(output_fields) > 3  # Simple heuristic
  end
end
```

## Streaming Adapter Support

```elixir
defmodule DSPEx.Adapter.Streaming do
  @moduledoc """
  Utilities for handling streaming responses in adapters.
  """
  
  defmodule StreamParser do
    defstruct [:signature, :adapter, :buffer, :state, :correlation_id]
    
    def new(signature, adapter, correlation_id) do
      %__MODULE__{
        signature: signature,
        adapter: adapter,
        buffer: "",
        state: :collecting,
        correlation_id: correlation_id
      }
    end
    
    def process_chunk(parser, chunk) do
      updated_buffer = parser.buffer <> chunk.content
      
      case parser.state do
        :collecting ->
          # Check if we have complete field markers
          if complete_response?(updated_buffer, parser.signature) do
            case parser.adapter.parse(parser.signature, format_for_parsing(updated_buffer)) do
              {:ok, parsed} ->
                {:complete, %{parser | buffer: updated_buffer, state: :complete}, parsed}
              
              {:error, _} ->
                {:continue, %{parser | buffer: updated_buffer}}
            end
          else
            {:continue, %{parser | buffer: updated_buffer}}
          end
        
        :complete ->
          {:complete, parser, :already_complete}
      end
    end
    
    defp complete_response?(buffer, signature) do
      required_fields = signature.output_fields()
      
      Enum.all?(required_fields, fn field_name ->
        String.contains?(buffer, "[[ ## #{field_name} ## ]]")
      end)
    end
    
    defp format_for_parsing(buffer) do
      # Format the accumulated buffer as a standard LM response
      %{
        "choices" => [
          %{
            "message" => %{
              "content" => buffer
            }
          }
        ]
      }
    end
  end
end
```

## Testing Infrastructure for Adapters

```elixir
defmodule DSPEx.Adapter.Test.Support do
  @moduledoc """
  Testing utilities for adapter implementations.
  """
  
  def create_test_signature(input_fields, output_fields, instructions \\ "Test instructions") do
    # Dynamically create a test signature module
    test_module = Module.concat([DSPEx.Test, :TestSignature, :unique_ref()])
    
    contents = quote do
      @behaviour DSPEx.Signature
      
      def instructions, do: unquote(instructions)
      def input_fields, do: unquote(input_fields)
      def output_fields, do: unquote(output_fields)
    end
    
    Module.create(test_module, contents, Macro.Env.location(__ENV__))
    test_module
  end
  
  def create_test_examples(signature, count \\ 3) do
    input_fields = signature.input_fields()
    output_fields = signature.output_fields()
    
    1..count
    |> Enum.map(fn i ->
      inputs = 
        input_fields
        |> Enum.map(fn field -> {field, "test_input_#{field}_#{i}"} end)
        |> Enum.into(%{})
      
      outputs = 
        output_fields
        |> Enum.map(fn field -> {field, "test_output_#{field}_#{i}"} end)
        |> Enum.into(%{})
      
      DSPEx.Example.new(Map.merge(inputs, outputs))
      |> DSPEx.Example.with_inputs(input_fields)
    end)
  end
  
  def mock_lm_response(content) do
    %{
      "choices" => [
        %{
          "message" => %{
            "content" => content,
            "role" => "assistant"
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      }
    }
  end
  
  defp unique_ref do
    System.unique_integer([:positive])
  end
end
```

This adapter implementation provides a solid foundation for DSPEx's prompt formatting and response parsing capabilities, with full integration into the Foundation library's error handling, telemetry, and observability systems.
