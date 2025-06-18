defmodule DSPEx.Signature.Elixact do
  @moduledoc """
  Bridge module between DSPEx signatures and Elixact schema validation.

  This module provides conversion utilities to translate DSPEx signature
  definitions into Elixact schemas for enhanced validation, type safety,
  and JSON schema generation.

  ## Key Features

  - Convert DSPEx signatures to Elixact schemas
  - Validate inputs/outputs using Elixact validation
  - Generate JSON schemas from DSPEx signatures
  - Maintain backward compatibility with existing signature system
  - Enhanced error reporting with field-level validation details

  ## Usage

      # Convert existing DSPEx signature to Elixact schema
      defmodule QASignature do
        use DSPEx.Signature, "question -> answer"
      end

      # Generate Elixact schema
      {:ok, elixact_schema} = DSPEx.Signature.Elixact.signature_to_schema(QASignature)

      # Validate data using Elixact
      {:ok, validated} = DSPEx.Signature.Elixact.validate_with_elixact(QASignature, %{
        question: "What is 2+2?"
      })

      # Generate JSON schema
      json_schema = DSPEx.Signature.Elixact.to_json_schema(QASignature)

  ## Enhanced Validation

  The bridge supports enhanced field definitions through options:

      defmodule EnhancedSignature do
        use DSPEx.Signature, "question:string[min_length=1,max_length=500] -> answer:string[max_length=1000]"
      end

  """

  alias DSPEx.Signature
  alias Elixact.JsonSchema

  @type signature_module :: module()
  @type field_constraints :: %{
          optional(:min_length) => non_neg_integer(),
          optional(:max_length) => non_neg_integer(),
          optional(:min_items) => non_neg_integer(),
          optional(:max_items) => non_neg_integer(),
          optional(:format) => Regex.t(),
          optional(:choices) => [term()],
          optional(:gteq) => number(),
          optional(:lteq) => number(),
          optional(:gt) => number(),
          optional(:lt) => number()
        }
  @type field_definition :: %{
          name: atom(),
          type: atom() | tuple(),
          constraints: field_constraints(),
          required: boolean(),
          default: term()
        }

  @doc """
  Converts a DSPEx signature module to an Elixact schema definition.

  This function analyzes the signature's input and output fields and creates
  an equivalent Elixact schema that can be used for enhanced validation.

  ## Parameters

  - `signature` - The DSPEx signature module to convert

  ## Returns

  - `{:ok, schema_module}` - Generated Elixact schema module
  - `{:error, reason}` - Error if conversion fails

  ## Examples

      iex> defmodule TestSignature do
      ...>   use DSPEx.Signature, "name -> greeting"
      ...> end
      iex> {:ok, schema} = DSPEx.Signature.Elixact.signature_to_schema(TestSignature)
      iex> is_atom(schema)
      true

  """
  @spec signature_to_schema(signature_module()) :: {:ok, module()} | {:error, term()}
  def signature_to_schema(signature) when is_atom(signature) do
    with :ok <- validate_signature_module(signature),
         {:ok, field_definitions} <- extract_field_definitions(signature),
         {:ok, schema_module} <- generate_elixact_schema(signature, field_definitions) do
      {:ok, schema_module}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, {:conversion_failed, error}}
  end

  @doc """
  Validates data against a DSPEx signature using Elixact validation.

  This function converts the signature to an Elixact schema and validates
  the provided data, returning enhanced error information if validation fails.

  ## Parameters

  - `signature` - The DSPEx signature module
  - `data` - The data to validate (typically inputs or outputs)
  - `opts` - Optional validation options

  ## Options

  - `:field_type` - `:inputs` (default) or `:outputs` to validate specific field types
  - `:strict` - Boolean to enable strict validation (default: false)

  ## Returns

  - `{:ok, validated_data}` - Successfully validated data
  - `{:error, validation_errors}` - Detailed validation errors

  ## Examples

      iex> defmodule SimpleSignature do
      ...>   use DSPEx.Signature, "name -> greeting"
      ...> end
      iex> {:ok, validated} = DSPEx.Signature.Elixact.validate_with_elixact(SimpleSignature, %{name: "Alice"})
      iex> validated.name
      "Alice"

  """
  @spec validate_with_elixact(signature_module(), map(), keyword()) ::
          {:ok, map()} | {:error, [Elixact.Error.t()]}
  def validate_with_elixact(signature, data, opts \\ [])
      when is_atom(signature) and is_map(data) do
    field_type = Keyword.get(opts, :field_type, :inputs)

    with {:ok, schema_module} <- signature_to_schema_for_field_type(signature, field_type),
         {:ok, filtered_data} <- filter_data_by_field_type(signature, data, field_type) do
      case schema_module.validate(filtered_data) do
        {:ok, validated_data} -> {:ok, validated_data}
        {:error, errors} -> {:error, normalize_elixact_errors(errors)}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, {:validation_failed, error}}
  end

  @doc """
  Generates a JSON Schema from a DSPEx signature.

  This function converts the signature to an Elixact schema and then
  generates a JSON Schema representation, useful for API documentation
  and client-side validation.

  ## Parameters

  - `signature` - The DSPEx signature module
  - `opts` - Optional generation options

  ## Options

  - `:field_type` - `:inputs`, `:outputs`, or `:all` (default)
  - `:title` - Custom title for the schema
  - `:description` - Custom description for the schema

  ## Returns

  - `{:ok, json_schema}` - Generated JSON Schema as a map
  - `{:error, reason}` - Error if generation fails

  ## Examples

      iex> defmodule JsonSignature do
      ...>   use DSPEx.Signature, "question -> answer"
      ...> end
      iex> {:ok, json_schema} = DSPEx.Signature.Elixact.to_json_schema(JsonSignature)
      iex> json_schema["type"]
      "object"

  """
  @spec to_json_schema(signature_module(), keyword()) :: {:ok, map()} | {:error, term()}
  def to_json_schema(signature, opts \\ []) when is_atom(signature) do
    case signature_to_schema(signature) do
      {:ok, schema_module} ->
        try do
          json_schema = JsonSchema.from_schema(schema_module)

          # Customize the schema based on options
          customized_schema = customize_json_schema(json_schema, signature, opts)

          {:ok, customized_schema}
        rescue
          error -> {:error, {:json_schema_generation_failed, error}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Converts DSPEx validation errors to Elixact-compatible error format.

  This function provides a bridge for error handling, converting standard
  DSPEx validation errors (like :missing_inputs) to Elixact.Error structs
  for consistent error reporting.

  ## Parameters

  - `dspex_error` - DSPEx error (atom or tuple)

  ## Returns

  - List of Elixact.Error structs

  ## Examples

      iex> errors = DSPEx.Signature.Elixact.dspex_errors_to_elixact(:missing_inputs)
      iex> hd(errors).code
      :missing_inputs

  """
  @spec dspex_errors_to_elixact(atom() | tuple()) :: [Elixact.Error.t()]
  def dspex_errors_to_elixact(error) do
    case error do
      :missing_inputs ->
        [
          %Elixact.Error{
            path: [],
            code: :missing_inputs,
            message: "Required input fields are missing"
          }
        ]

      :missing_outputs ->
        [
          %Elixact.Error{
            path: [],
            code: :missing_outputs,
            message: "Required output fields are missing"
          }
        ]

      {:missing_inputs, fields} when is_list(fields) ->
        Enum.map(fields, fn field ->
          %Elixact.Error{
            path: [field],
            code: :required,
            message: "Field '#{field}' is required but missing"
          }
        end)

      {:missing_outputs, fields} when is_list(fields) ->
        Enum.map(fields, fn field ->
          %Elixact.Error{
            path: [field],
            code: :required,
            message: "Output field '#{field}' is required but missing"
          }
        end)

      :invalid_signature ->
        [
          %Elixact.Error{
            path: [],
            code: :invalid_signature,
            message: "Invalid signature: does not implement DSPEx.Signature behavior"
          }
        ]

      other ->
        [
          %Elixact.Error{
            path: [],
            code: :unknown_error,
            message: "Unknown validation error: #{inspect(other)}"
          }
        ]
    end
  end

  # Private implementation functions

  # Gets enhanced field definitions from a signature module if available
  @spec get_enhanced_field_definitions(signature_module()) ::
          {:ok, [DSPEx.Signature.EnhancedParser.enhanced_field()]} | {:error, :no_enhanced_fields}
  defp get_enhanced_field_definitions(signature) do
    # Check if the signature module has enhanced field definitions stored
    # This would be set by the enhanced DSPEx.Signature.__using__ macro
    if function_exported?(signature, :__enhanced_fields__, 0) do
      try do
        enhanced_fields = signature.__enhanced_fields__()
        {:ok, enhanced_fields}
      rescue
        _ -> {:error, :no_enhanced_fields}
      end
    else
      {:error, :no_enhanced_fields}
    end
  end

  # Converts enhanced field definition to our field_definition format
  @spec convert_enhanced_to_field_definition(DSPEx.Signature.EnhancedParser.enhanced_field()) ::
          field_definition()
  defp convert_enhanced_to_field_definition(enhanced_field) do
    # Map enhanced constraints to Elixact-compatible constraints
    elixact_constraints = map_enhanced_constraints_to_elixact(enhanced_field.constraints)

    %{
      name: enhanced_field.name,
      type: enhanced_field.type,
      constraints: elixact_constraints,
      required: enhanced_field.required,
      default: enhanced_field.default
    }
  end

  # Maps enhanced parser constraints to Elixact validator constraints
  @spec map_enhanced_constraints_to_elixact(%{atom() => term()}) :: field_constraints()
  defp map_enhanced_constraints_to_elixact(constraints) do
    Enum.reduce(constraints, %{}, fn {constraint_name, value}, acc ->
      case map_single_constraint_to_elixact(constraint_name, value) do
        {:ok, elixact_constraint, elixact_value} ->
          Map.put(acc, elixact_constraint, elixact_value)

        {:skip} ->
          # Some constraints might not map directly to Elixact
          acc
      end
    end)
  end

  # Maps individual constraint types from enhanced parser to Elixact
  @spec map_single_constraint_to_elixact(atom(), term()) ::
          {:ok, atom(), term()} | {:skip}
  defp map_single_constraint_to_elixact(constraint_name, value) do
    cond do
      constraint_name in [:default, :optional] -> {:skip}
      direct_mapping_constraint?(constraint_name) -> {:ok, constraint_name, value}
      true -> {:ok, constraint_name, value}
    end
  end

  defp direct_mapping_constraint?(constraint_name) do
    constraint_name in [
      :min_length,
      :max_length,
      :min_items,
      :max_items,
      :format,
      :choices,
      :gteq,
      :lteq,
      :gt,
      :lt
    ]
  end

  @spec signature_to_schema_for_field_type(signature_module(), atom()) ::
          {:ok, module()} | {:error, term()}
  defp signature_to_schema_for_field_type(signature, field_type) do
    with :ok <- validate_signature_module(signature),
         {:ok, field_definitions} <- extract_field_definitions_for_type(signature, field_type),
         {:ok, schema_module} <- generate_elixact_schema(signature, field_definitions) do
      {:ok, schema_module}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, {:conversion_failed, error}}
  end

  @spec validate_signature_module(signature_module()) :: :ok | {:error, term()}
  defp validate_signature_module(signature) do
    case Signature.validate_signature_implementation(signature) do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_signature, reason}}
    end
  end

  @spec extract_field_definitions(signature_module()) ::
          {:ok, [field_definition()]} | {:error, term()}
  defp extract_field_definitions(signature) do
    try do
      # Check if this signature has enhanced field definitions stored
      case get_enhanced_field_definitions(signature) do
        {:ok, enhanced_fields} ->
          # Convert enhanced fields to our field_definition format
          converted_fields =
            Enum.map(enhanced_fields, &convert_enhanced_to_field_definition/1)

          {:ok, converted_fields}

        {:error, :no_enhanced_fields} ->
          # Fall back to basic field definitions for compatibility
          input_fields = signature.input_fields()
          output_fields = signature.output_fields()

          input_definitions =
            Enum.map(input_fields, fn field ->
              %{
                name: field,
                type: :string,
                constraints: %{},
                required: true,
                default: nil
              }
            end)

          output_definitions =
            Enum.map(output_fields, fn field ->
              %{
                name: field,
                type: :string,
                constraints: %{},
                required: true,
                default: nil
              }
            end)

          {:ok, input_definitions ++ output_definitions}
      end
    rescue
      error -> {:error, {:field_extraction_failed, error}}
    end
  end

  @spec extract_field_definitions_for_type(signature_module(), atom()) ::
          {:ok, [field_definition()]} | {:error, term()}
  defp extract_field_definitions_for_type(signature, field_type) do
    try do
      case field_type do
        :inputs ->
          extract_filtered_field_definitions(signature, signature.input_fields())

        :outputs ->
          extract_filtered_field_definitions(signature, signature.output_fields())

        :all ->
          extract_field_definitions(signature)

        _ ->
          {:error, {:invalid_field_type, field_type}}
      end
    rescue
      error -> {:error, {:field_extraction_failed, error}}
    end
  end

  @spec extract_filtered_field_definitions(signature_module(), [atom()]) ::
          {:ok, [field_definition()]} | {:error, term()}
  defp extract_filtered_field_definitions(signature, field_names) do
    case get_enhanced_field_definitions(signature) do
      {:ok, enhanced_fields} ->
        field_names_set = MapSet.new(field_names)

        filtered_fields =
          enhanced_fields
          |> Enum.filter(&MapSet.member?(field_names_set, &1.name))
          |> Enum.map(&convert_enhanced_to_field_definition/1)

        {:ok, filtered_fields}

      {:error, :no_enhanced_fields} ->
        definitions =
          Enum.map(field_names, fn field ->
            %{
              name: field,
              type: :string,
              constraints: %{},
              required: true,
              default: nil
            }
          end)

        {:ok, definitions}
    end
  end

  @spec generate_elixact_schema(signature_module(), [field_definition()]) ::
          {:ok, module()} | {:error, term()}
  defp generate_elixact_schema(signature, field_definitions) do
    # Generate a unique module name based on the signature
    schema_name = :"#{signature}.ElixactSchema.#{System.unique_integer([:positive])}"

    # Build the module definition using Elixact DSL
    module_definition = build_schema_module(schema_name, signature, field_definitions)

    try do
      # Compile and load the new module
      {_result, _binding} = Code.eval_quoted(module_definition)
      {:ok, schema_name}
    rescue
      error -> {:error, {:schema_compilation_failed, error}}
    end
  end

  @spec build_schema_module(atom(), signature_module(), [field_definition()]) :: Macro.t()
  defp build_schema_module(schema_name, signature, field_definitions) do
    description = get_signature_description(signature)

    # Generate field definitions for the schema
    field_defs = Enum.map(field_definitions, &build_field_definition/1)

    quote do
      defmodule unquote(schema_name) do
        use Elixact

        schema unquote(description) do
          (unquote_splicing(field_defs))
        end
      end
    end
  end

  @spec build_field_definition(field_definition()) :: Macro.t()
  defp build_field_definition(%{
         name: name,
         type: type,
         constraints: constraints,
         required: required,
         default: default
       }) do
    # Convert type to Elixact-compatible format
    elixact_type = convert_type_to_elixact(type)

    # Build constraint applications
    constraint_calls = build_constraint_calls(constraints)

    # Handle optional/default fields
    requirement_calls = build_requirement_calls(required, default)

    # Combine all calls
    all_calls = constraint_calls ++ requirement_calls

    if Enum.empty?(all_calls) do
      quote do
        field(unquote(name), unquote(elixact_type))
      end
    else
      quote do
        field unquote(name), unquote(elixact_type) do
          (unquote_splicing(all_calls))
        end
      end
    end
  end

  # Converts enhanced parser types to Elixact-compatible type specifications
  @spec convert_type_to_elixact(atom() | tuple()) :: term()
  defp convert_type_to_elixact(type) do
    case type do
      # Basic types - direct mapping
      basic_type when basic_type in [:string, :integer, :float, :boolean, :any, :map] ->
        basic_type

      # Array types - convert to Elixact array format
      {:array, inner_type} ->
        converted_inner = convert_type_to_elixact(inner_type)
        {:array, converted_inner}

      # Object types (for future nested object support)
      {:object, fields} when is_list(fields) ->
        {:object, Enum.map(fields, &convert_object_field_to_elixact/1)}

      # Custom module types - preserve as-is
      module_type when is_atom(module_type) ->
        handle_module_type(module_type)

      # Fallback for other types
      unknown_type ->
        IO.warn("Unknown type format #{inspect(unknown_type)}, defaulting to :string")
        :string
    end
  end

  defp handle_module_type(module_type) do
    type_str = Atom.to_string(module_type)

    if String.match?(type_str, ~r/^[A-Z]/) do
      module_type
    else
      IO.warn("Unknown type #{inspect(module_type)}, defaulting to :string")
      :string
    end
  end

  # Converts object field definitions to Elixact format
  @spec convert_object_field_to_elixact(term()) :: term()
  defp convert_object_field_to_elixact({field_name, field_type}) do
    {field_name, convert_type_to_elixact(field_type)}
  end

  defp convert_object_field_to_elixact(field_definition) when is_map(field_definition) do
    %{
      name: field_definition.name,
      type: convert_type_to_elixact(field_definition.type),
      constraints: field_definition.constraints,
      required: field_definition.required,
      default: field_definition.default
    }
  end

  defp convert_object_field_to_elixact(other) do
    IO.warn("Unknown object field format #{inspect(other)}")
    other
  end

  @spec build_constraint_calls(field_constraints()) :: [Macro.t()]
  defp build_constraint_calls(constraints) do
    Enum.flat_map(constraints, fn
      {:min_length, value} ->
        [quote(do: min_length(unquote(value)))]

      {:max_length, value} ->
        [quote(do: max_length(unquote(value)))]

      {:min_items, value} ->
        [quote(do: min_items(unquote(value)))]

      {:max_items, value} ->
        [quote(do: max_items(unquote(value)))]

      {:format, regex} ->
        [quote(do: format(unquote(regex)))]

      {:choices, values} ->
        [quote(do: choices(unquote(values)))]

      {:gteq, value} ->
        [quote(do: gteq(unquote(value)))]

      {:lteq, value} ->
        [quote(do: lteq(unquote(value)))]

      {:gt, value} ->
        [quote(do: gt(unquote(value)))]

      {:lt, value} ->
        [quote(do: lt(unquote(value)))]

      _ ->
        []
    end)
  end

  @spec build_requirement_calls(boolean(), term()) :: [Macro.t()]
  defp build_requirement_calls(required, default) do
    cond do
      not is_nil(default) ->
        [quote(do: default(unquote(default)))]

      not required ->
        [quote(do: optional())]

      true ->
        # Required is the default
        []
    end
  end

  @spec get_signature_description(signature_module()) :: String.t()
  defp get_signature_description(signature) do
    if function_exported?(signature, :instructions, 0) do
      signature.instructions()
    else
      "Generated schema for #{inspect(signature)}"
    end
  end

  @spec filter_data_by_field_type(signature_module(), map(), atom()) ::
          {:ok, map()} | {:error, term()}
  defp filter_data_by_field_type(signature, data, field_type) do
    try do
      case field_type do
        :inputs ->
          input_fields = signature.input_fields()
          filtered = Map.take(data, input_fields)
          {:ok, filtered}

        :outputs ->
          output_fields = signature.output_fields()
          filtered = Map.take(data, output_fields)
          {:ok, filtered}

        :all ->
          {:ok, data}

        _ ->
          {:error, {:invalid_field_type, field_type}}
      end
    rescue
      error -> {:error, {:field_filtering_failed, error}}
    end
  end

  @spec normalize_elixact_errors(term()) :: [Elixact.Error.t()]
  defp normalize_elixact_errors(errors) do
    # Elixact might return a single error or a list
    if is_list(errors) do
      errors
    else
      [errors]
    end
  end

  @spec customize_json_schema(map(), signature_module(), keyword()) :: map()
  defp customize_json_schema(json_schema, signature, opts) do
    json_schema
    |> maybe_add_title(signature, opts)
    |> maybe_add_description(signature, opts)
    |> maybe_filter_fields(signature, opts)
  end

  @spec maybe_add_title(map(), signature_module(), keyword()) :: map()
  defp maybe_add_title(schema, signature, opts) do
    case Keyword.get(opts, :title) do
      nil ->
        # Use signature name as title
        title = signature |> Module.split() |> List.last()
        Map.put(schema, "title", title)

      custom_title ->
        Map.put(schema, "title", custom_title)
    end
  end

  @spec maybe_add_description(map(), signature_module(), keyword()) :: map()
  defp maybe_add_description(schema, signature, opts) do
    case Keyword.get(opts, :description) do
      nil ->
        # Use signature instructions as description if available
        if function_exported?(signature, :instructions, 0) do
          Map.put(schema, "description", signature.instructions())
        else
          schema
        end

      custom_description ->
        Map.put(schema, "description", custom_description)
    end
  end

  @spec maybe_filter_fields(map(), signature_module(), keyword()) :: map()
  defp maybe_filter_fields(schema, signature, opts) do
    case Keyword.get(opts, :field_type, :all) do
      :all ->
        schema

      :inputs ->
        filter_properties_by_fields(schema, signature.input_fields())

      :outputs ->
        filter_properties_by_fields(schema, signature.output_fields())

      _ ->
        schema
    end
  end

  @spec filter_properties_by_fields(map(), [atom()]) :: map()
  defp filter_properties_by_fields(schema, allowed_fields) do
    properties = Map.get(schema, "properties", %{})
    allowed_field_strings = Enum.map(allowed_fields, &Atom.to_string/1)

    filtered_properties = Map.take(properties, allowed_field_strings)

    schema
    |> Map.put("properties", filtered_properties)
    |> Map.update("required", [], fn required ->
      Enum.filter(required, &(&1 in allowed_field_strings))
    end)
  end
end
