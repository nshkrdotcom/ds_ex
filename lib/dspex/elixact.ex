defmodule DSPEx.Elixact do
  @moduledoc """
  Enhanced Elixact integration for DSPEx - TDD Cycle 2A.1 Implementation

  This module provides the missing functions identified in the compatibility assessment,
  enabling bidirectional conversion between DSPEx signatures and Elixact schemas.

  Following the TDD Master Reference Phase 2 specifications.
  """

  alias DSPEx.Signature.Elixact, as: SignatureElixact

  @doc """
  Converts an Elixact schema definition to a DSPEx signature.

  This enables importing schemas from other systems into DSPEx.
  """
  @spec schema_to_signature(map()) :: module()
  def schema_to_signature(schema_definition) do
    # Extract fields and metadata from Elixact schema format
    fields = Map.get(schema_definition, :fields, %{})
    meta = Map.get(schema_definition, :__meta__, %{})

    # Determine input vs output fields (simple heuristic for now)
    # In a real implementation, this would be more sophisticated
    field_names = Map.keys(fields)
    {input_fields, output_fields} = split_fields_by_convention(field_names)

    # Create signature string
    signature_string = build_signature_string(input_fields, output_fields, fields)

    # Create a dynamic signature module
    create_dynamic_signature_module(signature_string, fields, meta)
  end

  @doc """
  Generates JSON Schema from DSPEx signature via Elixact.

  Leverages Elixact's robust JSON Schema generation capabilities.
  """
  @spec generate_json_schema(module()) :: map()
  def generate_json_schema(signature_module) do
    # Use the existing DSPEx Elixact integration which handles output-only schemas properly
    case SignatureElixact.to_json_schema(signature_module, field_type: :outputs) do
      {:ok, schema} ->
        schema

      {:error, _reason} ->
        # Fallback to basic JSON schema (outputs only)
        generate_basic_json_schema_outputs_only(signature_module)
    end
  end

  @doc """
  Maps DSPEx constraints to Elixact constraint format.
  """
  @spec map_constraints_to_elixact(map()) :: map()
  def map_constraints_to_elixact(dspex_constraints) do
    Enum.reduce(dspex_constraints, %{}, fn {key, value}, acc ->
      case map_single_constraint(key, value) do
        {:ok, elixact_key, elixact_value} ->
          Map.put(acc, elixact_key, elixact_value)

        {:skip} ->
          acc

        {:preserve} ->
          Map.put(acc, key, value)
      end
    end)
  end

  @doc """
  Converts Elixact errors to DSPEx-compatible format.
  """
  @spec convert_errors_to_dspex(list() | struct()) :: list()
  def convert_errors_to_dspex(elixact_errors) when is_list(elixact_errors) do
    Enum.map(elixact_errors, &convert_single_error_to_dspex/1)
  end

  def convert_errors_to_dspex(elixact_error) do
    [convert_single_error_to_dspex(elixact_error)]
  end

  @doc """
  Creates a dynamic Elixact schema from DSPEx signature definition.
  """
  @spec create_dynamic_schema(map(), String.t()) :: module()
  def create_dynamic_schema(signature_definition, schema_name) do
    input_fields = Map.get(signature_definition, :input_fields, [])
    output_fields = Map.get(signature_definition, :output_fields, [])
    field_types = Map.get(signature_definition, :field_types, %{})
    constraints = Map.get(signature_definition, :constraints, %{})

    all_fields = input_fields ++ output_fields

    # Generate unique module name
    module_name = :"#{schema_name}.#{System.unique_integer([:positive])}"

    # Build field definitions
    field_defs = build_elixact_field_definitions(all_fields, field_types, constraints)

    # Create module definition
    module_def =
      quote do
        defmodule unquote(module_name) do
          use Elixact

          schema unquote(schema_name) do
            (unquote_splicing(field_defs))
          end
        end
      end

    # Compile and return the module
    {_result, _binding} = Code.eval_quoted(module_def)
    module_name
  end

  @doc """
  Extracts schema information from an Elixact schema for DSPEx metadata.
  """
  @spec extract_schema_info(module()) :: map()
  def extract_schema_info(elixact_schema) do
    # Use Elixact's introspection capabilities
    json_schema = Elixact.JsonSchema.from_schema(elixact_schema)

    # Extract field information
    properties = Map.get(json_schema, "properties", %{})
    required = Map.get(json_schema, "required", [])

    fields = extract_fields_from_properties(properties)
    constraints = extract_constraints_from_properties(properties)
    descriptions = extract_descriptions_from_properties(properties)

    %{
      fields: fields,
      constraints: constraints,
      descriptions: descriptions,
      required: required
    }
  end

  # Private helper functions

  defp split_fields_by_convention(field_names) do
    # Simple heuristic: fields ending with common input words vs output words
    input_indicators = ["query", "question", "input", "request", "search", "term"]
    _output_indicators = ["answer", "response", "result", "output", "summary", "reply"]

    {inputs, outputs} =
      Enum.split_with(field_names, fn field ->
        field_str = Atom.to_string(field)
        Enum.any?(input_indicators, &String.contains?(field_str, &1))
      end)

    # If no clear split, assume first field is input, rest are outputs
    case {inputs, outputs} do
      {[], []} -> {[], []}
      {[], all} -> {[hd(all)], tl(all)}
      {inputs, []} -> {inputs, []}
      split -> split
    end
  end

  defp build_signature_string(input_fields, output_fields, _fields) do
    input_str = Enum.map_join(input_fields, ", ", &Atom.to_string/1)
    output_str = Enum.map_join(output_fields, ", ", &Atom.to_string/1)

    "#{input_str} -> #{output_str}"
  end

  defp create_dynamic_signature_module(signature_string, fields, meta) do
    # Generate unique module name
    module_name = :"DynamicSignature.#{System.unique_integer([:positive])}"
    title = Map.get(meta, :title, "Dynamic Signature")

    # Convert fields to enhanced fields format
    enhanced_fields =
      Enum.map(fields, fn {name, field_info} ->
        %{
          name: name,
          type: Map.get(field_info, :type, :string),
          description: Map.get(field_info, :description, ""),
          constraints: Map.get(field_info, :constraints, %{})
        }
      end)

    # Create module definition using DSPEx.Signature
    module_def =
      quote do
        defmodule unquote(module_name) do
          @moduledoc unquote(title)

          def __enhanced_fields__, do: unquote(Macro.escape(enhanced_fields))

          use DSPEx.Signature, unquote(signature_string)
        end
      end

    # Compile and return the module
    {_result, _binding} = Code.eval_quoted(module_def)
    module_name
  end

  defp generate_basic_json_schema_outputs_only(signature_module) do
    # Fallback JSON schema generation for outputs only (for LLM structured output)
    output_fields = signature_module.output_fields()

    properties =
      Enum.reduce(output_fields, %{}, fn field, acc ->
        field_str = Atom.to_string(field)
        Map.put(acc, field_str, %{"type" => "string"})
      end)

    required_fields = Enum.map(output_fields, &Atom.to_string/1)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required_fields
    }
  end

  defp map_single_constraint(key, value) do
    case key do
      # Direct mappings
      key
      when key in [
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
           ] ->
        map_direct_constraint(key, value)

      # Skip internal DSPEx metadata
      key when key in [:default, :optional] ->
        {:skip}

      # Preserve unknown constraints
      _ ->
        {:preserve}
    end
  end

  # Map constraints that have direct mappings
  defp map_direct_constraint(key, value) do
    {:ok, key, value}
  end

  defp convert_single_error_to_dspex(error) when is_struct(error) do
    # Convert Elixact.Error struct to DSPEx format
    %{
      field: extract_field_from_path(Map.get(error, :path, [])),
      path: Map.get(error, :path, []),
      message: Map.get(error, :message, "Validation error"),
      code: Map.get(error, :code, :validation_error),
      type: :elixact_error
    }
  end

  defp convert_single_error_to_dspex(error) when is_map(error) do
    # Convert generic error map to DSPEx format
    %{
      field: Map.get(error, :field) || Map.get(error, "field"),
      message: Map.get(error, :message) || Map.get(error, "message") || "Validation error",
      code: Map.get(error, :code) || Map.get(error, "code") || :validation_error,
      type: :elixact_error
    }
  end

  defp extract_field_from_path([]), do: :unknown
  defp extract_field_from_path([field | _]), do: field

  defp build_elixact_field_definitions(fields, field_types, constraints) do
    Enum.map(fields, fn field ->
      field_type = Map.get(field_types, field, :string)
      field_constraints = Map.get(constraints, field, %{})

      # Convert type to Elixact format
      elixact_type = convert_dspex_type_to_elixact(field_type)

      # Build constraint calls
      constraint_calls = build_elixact_constraint_calls(field_constraints)

      if Enum.empty?(constraint_calls) do
        quote do
          field(unquote(field), unquote(elixact_type))
        end
      else
        quote do
          field unquote(field), unquote(elixact_type) do
            (unquote_splicing(constraint_calls))
          end
        end
      end
    end)
  end

  defp convert_dspex_type_to_elixact(type) do
    case type do
      :string -> :string
      :integer -> :integer
      :float -> :float
      :boolean -> :boolean
      :any -> :any
      {:array, inner_type} -> {:array, convert_dspex_type_to_elixact(inner_type)}
      # Default fallback
      _ -> :string
    end
  end

  defp build_elixact_constraint_calls(constraints) do
    Enum.flat_map(constraints, fn {constraint, value} ->
      case constraint do
        # Length constraints
        constraint when constraint in [:min_length, :max_length] ->
          build_length_constraint(constraint, value)

        # Item count constraints
        constraint when constraint in [:min_items, :max_items] ->
          build_item_constraint(constraint, value)

        # Numeric comparison constraints
        constraint when constraint in [:gteq, :lteq, :gt, :lt] ->
          build_numeric_constraint(constraint, value)

        # Format and choice constraints
        :format ->
          [quote(do: format(unquote(value)))]

        :choices ->
          [quote(do: choices(unquote(value)))]

        # Skip unknown constraints
        _ ->
          []
      end
    end)
  end

  # Build length-related constraints
  defp build_length_constraint(:min_length, value), do: [quote(do: min_length(unquote(value)))]
  defp build_length_constraint(:max_length, value), do: [quote(do: max_length(unquote(value)))]

  # Build item count-related constraints
  defp build_item_constraint(:min_items, value), do: [quote(do: min_items(unquote(value)))]
  defp build_item_constraint(:max_items, value), do: [quote(do: max_items(unquote(value)))]

  # Build numeric comparison constraints
  defp build_numeric_constraint(:gteq, value), do: [quote(do: gteq(unquote(value)))]
  defp build_numeric_constraint(:lteq, value), do: [quote(do: lteq(unquote(value)))]
  defp build_numeric_constraint(:gt, value), do: [quote(do: gt(unquote(value)))]
  defp build_numeric_constraint(:lt, value), do: [quote(do: lt(unquote(value)))]

  defp extract_fields_from_properties(properties) do
    properties
    |> Map.keys()
    |> Enum.map(&String.to_atom/1)
    |> Enum.reduce(%{}, fn field, acc ->
      # Simplified for now
      Map.put(acc, field, :string)
    end)
  end

  defp extract_constraints_from_properties(properties) do
    Enum.reduce(properties, %{}, fn {field_name, field_schema}, acc ->
      field_atom = String.to_atom(field_name)
      constraints = extract_single_field_constraints(field_schema)

      if map_size(constraints) > 0 do
        Map.put(acc, field_atom, constraints)
      else
        acc
      end
    end)
  end

  defp extract_single_field_constraints(field_schema) do
    Enum.reduce(field_schema, %{}, fn {key, value}, acc ->
      case key do
        "minLength" -> Map.put(acc, :min_length, value)
        "maxLength" -> Map.put(acc, :max_length, value)
        "minItems" -> Map.put(acc, :min_items, value)
        "maxItems" -> Map.put(acc, :max_items, value)
        "minimum" -> Map.put(acc, :gteq, value)
        "maximum" -> Map.put(acc, :lteq, value)
        "pattern" -> Map.put(acc, :format, Regex.compile!(value))
        _ -> acc
      end
    end)
  end

  defp extract_descriptions_from_properties(properties) do
    Enum.reduce(properties, %{}, fn {field_name, field_schema}, acc ->
      case Map.get(field_schema, "description") do
        nil -> acc
        description -> Map.put(acc, String.to_atom(field_name), description)
      end
    end)
  end
end
