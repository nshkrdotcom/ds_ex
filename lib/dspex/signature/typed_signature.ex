defmodule DSPEx.TypedSignature do
  @moduledoc """
  TDD Cycle 2B.1: Type-Safe Signatures Implementation

  Provides runtime type validation and constraint checking for DSPEx signatures.
  Extends the basic signature system with comprehensive type safety, coercion
  capabilities, and detailed error reporting.

  Following the TDD Master Reference Phase 2 specifications.
  """

  @doc """
  Macro to add runtime type validation to a DSPEx signature.

  ## Options
  - `:coercion` - Enable automatic type coercion (default: false)
  - `:strict` - Disable coercion and require exact types (default: false)
  - `:error_messages` - Custom error message overrides

  ## Example
      defmodule MySignature do
        use DSPEx.Signature, "name:string[min_length=1] -> greeting:string[max_length=100]"
        use DSPEx.TypedSignature, coercion: true
      end
  """
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      @typed_signature_opts opts

      @doc """
      Validates input data against the signature's input field types and constraints.

      Returns `{:ok, validated_data}` on success or `{:error, errors}` on failure.
      """
      def validate_input(data) when is_map(data) do
        DSPEx.TypedSignature.Validator.validate_fields(
          data,
          input_fields(),
          __enhanced_fields__(),
          :input,
          @typed_signature_opts
        )
      end

      @doc """
      Validates output data against the signature's output field types and constraints.

      Returns `{:ok, validated_data}` on success or `{:error, errors}` on failure.
      """
      def validate_output(data) when is_map(data) do
        DSPEx.TypedSignature.Validator.validate_fields(
          data,
          output_fields(),
          __enhanced_fields__(),
          :output,
          @typed_signature_opts
        )
      end

      @doc """
      Returns the typed signature configuration options.
      """
      def __typed_signature_opts__, do: @typed_signature_opts
    end
  end
end

defmodule DSPEx.TypedSignature.Validator do
  @moduledoc """
  Core validation logic for typed signatures.
  """

  @doc """
  Validates a map of data against field definitions with type checking and constraints.
  """
  def validate_fields(data, field_names, enhanced_fields, _field_type, opts) do
    coercion_enabled = Keyword.get(opts, :coercion, false)
    strict_mode = Keyword.get(opts, :strict, false)
    custom_errors = Keyword.get(opts, :error_messages, %{})

    # Filter enhanced fields for the specific field type
    relevant_fields = filter_fields_by_type(enhanced_fields, field_names)

    # Validate each field
    results =
      Enum.map(relevant_fields, fn field_def ->
        validate_single_field(data, field_def, coercion_enabled, strict_mode, custom_errors)
      end)

    # Separate successful validations from errors
    {successes, errors} = separate_results(results)

    if Enum.empty?(errors) do
      validated_data = Map.new(successes)
      {:ok, validated_data}
    else
      {:error, List.flatten(errors)}
    end
  end

  # Private helper functions

  defp filter_fields_by_type(enhanced_fields, field_names) do
    enhanced_fields
    |> Enum.filter(fn field -> field.name in field_names end)
  end

  defp validate_single_field(data, field_def, coercion_enabled, strict_mode, custom_errors) do
    field_name = field_def.name
    field_type = Map.get(field_def, :type, :string)
    constraints = Map.get(field_def, :constraints, %{})

    case Map.get(data, field_name) do
      nil ->
        handle_missing_field(field_def, custom_errors)

      value ->
        validate_field_value(
          field_name,
          value,
          field_type,
          constraints,
          coercion_enabled,
          strict_mode,
          custom_errors
        )
    end
  end

  defp handle_missing_field(field_def, custom_errors) do
    field_name = field_def.name
    constraints = Map.get(field_def, :constraints, %{})

    cond do
      # Field has a default value
      Map.has_key?(constraints, :default) ->
        {:ok, {field_name, constraints.default}}

      # Field is optional
      Map.get(constraints, :optional, false) ->
        {:skip}

      # Field is required
      true ->
        error_msg =
          get_custom_error(custom_errors, field_name, :required) ||
            "#{field_name} is required"

        {:error, [error_msg]}
    end
  end

  defp validate_field_value(
         field_name,
         value,
         field_type,
         constraints,
         coercion_enabled,
         strict_mode,
         custom_errors
       ) do
    with {:ok, coerced_value} <-
           maybe_coerce_type(value, field_type, coercion_enabled, strict_mode),
         {:ok, type_validated_value} <-
           validate_type(coerced_value, field_type, field_name, custom_errors),
         {:ok, final_value} <-
           validate_constraints(type_validated_value, constraints, field_name, custom_errors) do
      {:ok, {field_name, final_value}}
    else
      {:error, errors} -> {:error, errors}
    end
  end

  defp maybe_coerce_type(value, field_type, coercion_enabled, strict_mode) do
    if strict_mode or not coercion_enabled do
      {:ok, value}
    else
      coerce_type(value, field_type)
    end
  end

  defp coerce_type(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, ""} -> {:ok, int_val}
      _ -> {:error, ["cannot coerce \"#{value}\" to integer"]}
    end
  end

  defp coerce_type(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float_val, ""} -> {:ok, float_val}
      _ -> {:error, ["cannot coerce \"#{value}\" to float"]}
    end
  end

  defp coerce_type(value, _type), do: {:ok, value}

  defp validate_type(value, :string, _field_name, _custom_errors) when is_binary(value),
    do: {:ok, value}

  defp validate_type(value, :integer, _field_name, _custom_errors) when is_integer(value),
    do: {:ok, value}

  defp validate_type(value, :float, _field_name, _custom_errors) when is_float(value),
    do: {:ok, value}

  defp validate_type(value, :boolean, _field_name, _custom_errors) when is_boolean(value),
    do: {:ok, value}

  defp validate_type(value, :map, _field_name, _custom_errors) when is_map(value),
    do: {:ok, value}

  defp validate_type(value, {:array, inner_type}, field_name, custom_errors)
       when is_list(value) do
    validate_array_elements(value, inner_type, field_name, custom_errors)
  end

  defp validate_type(value, expected_type, field_name, custom_errors) do
    error_msg =
      get_custom_error(custom_errors, field_name, :type) ||
        "#{field_name} must be #{type_name(expected_type)}, got #{type_name(typeof(value))}"

    {:error, [error_msg]}
  end

  defp validate_array_elements(array, inner_type, field_name, custom_errors) do
    results =
      Enum.with_index(array)
      |> Enum.map(fn {element, index} ->
        case validate_type(element, inner_type, "#{field_name}[#{index}]", custom_errors) do
          {:ok, validated_element} -> {:ok, validated_element}
          {:error, errors} -> {:error, errors}
        end
      end)

    {successes, errors} = separate_results(results)

    if Enum.empty?(errors) do
      {:ok, successes}
    else
      {:error, List.flatten(errors)}
    end
  end

  defp validate_constraints(value, constraints, field_name, custom_errors) do
    constraint_results =
      Enum.map(constraints, fn {constraint_type, constraint_value} ->
        validate_single_constraint(
          value,
          constraint_type,
          constraint_value,
          field_name,
          custom_errors
        )
      end)

    errors =
      constraint_results
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.flat_map(fn {:error, errs} -> errs end)

    if Enum.empty?(errors) do
      {:ok, value}
    else
      {:error, errors}
    end
  end

  defp validate_single_constraint(value, :min_length, min_len, field_name, custom_errors)
       when is_binary(value) do
    if String.length(value) >= min_len do
      {:ok, value}
    else
      error_msg =
        get_custom_error(custom_errors, field_name, :min_length) ||
          "#{field_name} must have at least #{min_len} characters"

      {:error, [error_msg]}
    end
  end

  defp validate_single_constraint(value, :max_length, max_len, field_name, custom_errors)
       when is_binary(value) do
    if String.length(value) <= max_len do
      {:ok, value}
    else
      error_msg =
        get_custom_error(custom_errors, field_name, :max_length) ||
          "#{field_name} must have at most #{max_len} characters"

      {:error, [error_msg]}
    end
  end

  defp validate_single_constraint(value, :min_items, min_items, field_name, custom_errors)
       when is_list(value) do
    if length(value) >= min_items do
      {:ok, value}
    else
      error_msg =
        get_custom_error(custom_errors, field_name, :min_items) ||
          "#{field_name} must have at least #{min_items} items"

      {:error, [error_msg]}
    end
  end

  defp validate_single_constraint(value, :max_items, max_items, field_name, custom_errors)
       when is_list(value) do
    if length(value) <= max_items do
      {:ok, value}
    else
      error_msg =
        get_custom_error(custom_errors, field_name, :max_items) ||
          "#{field_name} must have at most #{max_items} items"

      {:error, [error_msg]}
    end
  end

  defp validate_single_constraint(value, :gteq, min_val, field_name, custom_errors)
       when is_number(value) do
    if value >= min_val do
      {:ok, value}
    else
      error_msg =
        get_custom_error(custom_errors, field_name, :gteq) ||
          "#{field_name} must be greater than or equal to #{min_val}"

      {:error, [error_msg]}
    end
  end

  defp validate_single_constraint(value, :lteq, max_val, field_name, custom_errors)
       when is_number(value) do
    if value <= max_val do
      {:ok, value}
    else
      error_msg =
        get_custom_error(custom_errors, field_name, :lteq) ||
          "#{field_name} must be less than or equal to #{max_val}"

      {:error, [error_msg]}
    end
  end

  # Skip validation for internal constraints
  defp validate_single_constraint(
         _value,
         :optional,
         _constraint_value,
         _field_name,
         _custom_errors
       ),
       do: {:ok, :skip}

  defp validate_single_constraint(
         _value,
         :default,
         _constraint_value,
         _field_name,
         _custom_errors
       ),
       do: {:ok, :skip}

  # Unknown constraints are ignored for now
  defp validate_single_constraint(
         _value,
         _constraint_type,
         _constraint_value,
         _field_name,
         _custom_errors
       ),
       do: {:ok, :skip}

  defp get_custom_error(custom_errors, field_name, error_type) do
    custom_errors
    |> Map.get(field_name, %{})
    |> Map.get(error_type)
  end

  defp separate_results(results) do
    results
    |> Enum.reduce({[], []}, fn result, {successes, errors} ->
      case result do
        {:ok, {field_name, value}} -> {[{field_name, value} | successes], errors}
        {:ok, value} -> {[value | successes], errors}
        {:skip} -> {successes, errors}
        {:error, errs} -> {successes, [errs | errors]}
      end
    end)
  end

  defp type_name(:string), do: "string"
  defp type_name(:integer), do: "integer"
  defp type_name(:float), do: "float"
  defp type_name(:boolean), do: "boolean"
  defp type_name(:map), do: "map"
  defp type_name({:array, inner_type}), do: "array(#{type_name(inner_type)})"
  defp type_name(_), do: "unknown"

  defp typeof(value) when is_binary(value), do: :string
  defp typeof(value) when is_integer(value), do: :integer
  defp typeof(value) when is_float(value), do: :float
  defp typeof(value) when is_boolean(value), do: :boolean
  defp typeof(value) when is_map(value), do: :map
  defp typeof(value) when is_list(value), do: :array
  defp typeof(_), do: :unknown
end
