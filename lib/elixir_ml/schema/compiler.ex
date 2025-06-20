defmodule ElixirML.Schema.Compiler do
  @moduledoc """
  Compile-time schema compilation for maximum performance.
  Generates optimized validation functions and metadata.
  """

  defmacro __before_compile__(env) do
    fields = Module.get_attribute(env.module, :fields, [])
    validations = Module.get_attribute(env.module, :validations, [])
    transforms = Module.get_attribute(env.module, :transforms, [])
    variables = Module.get_attribute(env.module, :variables, [])
    metadata = Module.get_attribute(env.module, :metadata, %{})

    quote do
      # Store compiled schema data
      def __fields__, do: unquote(Macro.escape(fields))
      def __validations__, do: unquote(Macro.escape(validations))
      def __transforms__, do: unquote(Macro.escape(transforms))
      def __variables__, do: unquote(Macro.escape(variables))
      def __metadata__, do: unquote(Macro.escape(metadata))

      # Generate optimized validation function
      def validate(data) do
        with {:ok, validated} <- validate_fields(data),
             {:ok, transformed} <- apply_transforms(validated),
             {:ok, final} <- apply_validations(transformed) do
          {:ok, final}
        else
          {:error, reason} ->
            {:error,
             %ElixirML.Schema.ValidationError{
               message: reason,
               schema: __MODULE__,
               data: data
             }}
        end
      end

      # Generate field validation
      defp validate_fields(data) do
        unquote(generate_field_validation(fields))
      end

      # Generate transform application
      defp apply_transforms(data) do
        unquote(generate_transform_application(transforms))
      end

      # Generate validation application
      defp apply_validations(data) do
        unquote(generate_validation_application(validations))
      end

      # Generate JSON schema
      def to_json_schema do
        unquote(generate_json_schema(fields, metadata))
      end

      # Generate field accessors for compile-time optimization
      unquote(generate_field_accessors(fields))
    end
  end

  # Generate optimized field validation code
  defp generate_field_validation(fields) do
    field_validations =
      Enum.map(fields, fn {name, type, opts} ->
        required = Keyword.get(opts, :required, false)
        default = Keyword.get(opts, :default)

        quote do
          case Map.get(data, unquote(name)) do
            nil when unquote(required) ->
              {:error, "Field #{unquote(name)} is required"}

            nil ->
              # Use default if provided
              case unquote(default) do
                nil -> data
                default_value -> Map.put(data, unquote(name), default_value)
              end

            value ->
              case ElixirML.Schema.Types.validate_type(value, unquote(type)) do
                {:ok, validated_value} ->
                  Map.put(data, unquote(name), validated_value)

                {:error, reason} ->
                  {:error, "Field #{unquote(name)}: #{reason}"}
              end
          end
        end
      end)

    # Chain all field validations
    Enum.reduce(field_validations, quote(do: {:ok, data}), fn validation, acc ->
      quote do
        case unquote(acc) do
          {:ok, data} ->
            case unquote(validation) do
              {:error, reason} -> {:error, reason}
              updated_data -> {:ok, updated_data}
            end

          error ->
            error
        end
      end
    end)
  end

  # Generate transform application code
  defp generate_transform_application(transforms) do
    if Enum.empty?(transforms) do
      quote do: {:ok, data}
    else
      transform_applications =
        Enum.map(transforms, fn {_name, transform_fn} ->
          # Generate a function call instead of trying to escape the function
          quote do
            case apply(unquote(transform_fn), [data]) do
              {:ok, transformed} -> transformed
              {:error, reason} -> {:error, reason}
              # Assume success if no tuple returned
              transformed -> transformed
            end
          end
        end)

      # Chain all transforms
      Enum.reduce(transform_applications, quote(do: data), fn transform, acc ->
        quote do
          case unquote(acc) do
            {:error, reason} -> {:error, reason}
            data -> unquote(transform)
          end
        end
      end)
      |> wrap_ok()
    end
  end

  # Generate validation application code
  defp generate_validation_application(validations) do
    if Enum.empty?(validations) do
      quote do: {:ok, data}
    else
      validation_applications =
        Enum.map(validations, fn {_name, validation_fn} ->
          # Generate a function call instead of trying to escape the function
          quote do
            case apply(unquote(validation_fn), [data]) do
              {:ok, _} -> :ok
              {:error, reason} -> {:error, reason}
              true -> :ok
              false -> {:error, "Validation failed"}
              # Assume success for other return values
              _ -> :ok
            end
          end
        end)

      # Chain all validations
      validation_chain =
        Enum.reduce(validation_applications, quote(do: :ok), fn validation, acc ->
          quote do
            case unquote(acc) do
              :ok -> unquote(validation)
              error -> error
            end
          end
        end)

      quote do
        case unquote(validation_chain) do
          :ok -> {:ok, data}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  # Generate JSON schema representation
  defp generate_json_schema(fields, metadata) do
    properties =
      Enum.reduce(fields, %{}, fn {name, type, opts}, acc ->
        field_schema = %{
          "type" => json_type_for(type),
          "description" => Keyword.get(opts, :description, "")
        }

        # Add constraints
        field_schema =
          case type do
            :embedding ->
              Map.merge(field_schema, %{
                "type" => "array",
                "items" => %{"type" => "number"},
                "minItems" => 1
              })

            :probability ->
              Map.merge(field_schema, %{
                "type" => "number",
                "minimum" => 0.0,
                "maximum" => 1.0
              })

            :token_list ->
              Map.merge(field_schema, %{
                "type" => "array",
                "items" => %{"type" => ["string", "integer"]}
              })

            _ ->
              field_schema
          end

        Map.put(acc, to_string(name), field_schema)
      end)

    required_fields =
      fields
      |> Enum.filter(fn {_name, _type, opts} -> Keyword.get(opts, :required, false) end)
      |> Enum.map(fn {name, _type, _opts} -> to_string(name) end)

    quote do
      %{
        "type" => "object",
        "properties" => unquote(Macro.escape(properties)),
        "required" => unquote(required_fields),
        "additionalProperties" => false,
        "metadata" => unquote(Macro.escape(metadata))
      }
    end
  end

  # Generate field accessor functions for optimization
  defp generate_field_accessors(fields) do
    Enum.map(fields, fn {name, _type, _opts} ->
      quote do
        def unquote(:"get_#{name}")(data) do
          Map.get(data, unquote(name))
        end

        def unquote(:"put_#{name}")(data, value) do
          Map.put(data, unquote(name), value)
        end
      end
    end)
  end

  # Helper to wrap result in {:ok, ...}
  defp wrap_ok(expr) do
    quote do
      case unquote(expr) do
        {:error, reason} -> {:error, reason}
        result -> {:ok, result}
      end
    end
  end

  # Convert ML type to JSON schema type
  defp json_type_for(:embedding), do: "array"
  defp json_type_for(:tensor), do: "array"
  defp json_type_for(:token_list), do: "array"
  defp json_type_for(:probability), do: "number"
  defp json_type_for(:confidence_score), do: "number"
  defp json_type_for(:model_response), do: "object"
  defp json_type_for(:variable_config), do: "object"
  defp json_type_for(:reasoning_chain), do: "array"
  defp json_type_for(:attention_weights), do: "array"
  defp json_type_for(:string), do: "string"
  defp json_type_for(:integer), do: "integer"
  defp json_type_for(:float), do: "number"
  defp json_type_for(:boolean), do: "boolean"
  defp json_type_for(:map), do: "object"
  defp json_type_for(:list), do: "array"
  defp json_type_for(_), do: "string"
end
