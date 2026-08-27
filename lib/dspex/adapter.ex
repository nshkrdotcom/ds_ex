defmodule DSPEx.Adapter do
  @moduledoc """
  Sinter-backed adapter for turning signatures into prompts and validating/repairing outputs.

  - Validates inputs with the signature's Sinter schema.
  - Builds a prompt that includes instructions, inputs as JSON, and the expected JSON schema.
  - Repairs and validates model outputs using JsonRemedy + Sinter.
  """

  alias DSPEx.Signature.Sinter, as: SignatureSinter
  alias JsonRemedy

  @type signature :: module()
  @type inputs :: map()
  @type outputs :: map()
  @type request :: %{
          prompt: String.t(),
          schema: map(),
          output_fields: [atom()],
          inputs: map()
        }

  @doc """
  Prepare a prompt + schema request for the client.
  """
  @spec prepare(signature(), inputs(), keyword()) :: {:ok, request()} | {:error, term()}
  def prepare(signature, inputs, opts \\ []) do
    normalized_inputs = normalize_inputs(inputs)

    with {:ok, validated_inputs} <- validate_inputs(signature, normalized_inputs),
         {:ok, schema} <- build_output_schema(signature, opts),
         {:ok, prompt} <- build_prompt(signature, validated_inputs, schema, opts) do
      {:ok,
       %{
         prompt: prompt,
         schema: schema,
         output_fields: signature.output_fields(),
         inputs: validated_inputs
       }}
    end
  end

  @doc """
  Parse a raw response (object map or content string) into validated outputs.
  """
  @spec parse_response(signature(), map() | String.t()) :: {:ok, outputs()} | {:error, term()}
  def parse_response(signature, %{object: object}) when is_map(object) do
    normalize_and_validate(signature, object)
  end

  def parse_response(signature, %{content: content}) when is_binary(content) do
    decode_and_validate(signature, content)
  end

  def parse_response(signature, content) when is_binary(content) do
    decode_and_validate(signature, content)
  end

  def parse_response(_signature, _response), do: {:error, :invalid_response}

  # -- Internal helpers -------------------------------------------------------

  defp normalize_inputs(inputs) when is_map(inputs) do
    inputs
    |> normalize_context()
  end

  defp normalize_inputs(other), do: other

  defp normalize_context(%{context: context} = inputs) when is_list(context) do
    encoded =
      context
      |> Enum.map(&normalize_context_item/1)
      |> Jason.encode!()

    Map.put(inputs, :context, encoded)
  end

  defp normalize_context(inputs), do: inputs

  defp normalize_context_item(%{text: text, score: score}) do
    %{text: to_string(text), score: score}
  end

  defp normalize_context_item(%{text: text}) do
    %{text: to_string(text)}
  end

  defp normalize_context_item(text) when is_binary(text), do: %{text: text}
  defp normalize_context_item(other), do: other

  defp validate_inputs(signature, inputs) do
    case SignatureSinter.validate_with_sinter(signature, inputs, field_type: :inputs) do
      {:ok, validated} -> {:ok, validated}
      {:error, reason} -> {:error, {:invalid_inputs, reason}}
    end
  rescue
    _ ->
      case signature.validate_inputs(inputs) do
        :ok -> {:ok, inputs}
        {:error, reason} -> {:error, {:invalid_inputs, reason}}
      end
  end

  defp build_output_schema(signature, opts) do
    provider = Keyword.get(opts, :provider, :generic)
    schema = SignatureSinter.generate_json_schema(signature, field_type: :outputs, provider: provider)
    {:ok, schema}
  rescue
    error -> {:error, {:schema_generation_failed, error}}
  end

  defp build_prompt(signature, inputs, schema, opts) do
    instructions =
      if function_exported?(signature, :instructions, 0) do
        signature.instructions()
      else
        "Given the inputs, return the requested outputs as JSON."
      end

    input_json = Jason.encode!(inputs)
    schema_json = Jason.encode!(schema)
    extra = Keyword.get(opts, :instruction, nil)

    prompt =
      [
        instructions,
        extra,
        "Inputs (JSON):",
        input_json,
        "Return ONLY a JSON object matching this schema:",
        schema_json
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    {:ok, prompt}
  rescue
    error -> {:error, {:prompt_generation_failed, error}}
  end

  defp decode_and_validate(signature, content) do
    case decode_json(content) do
      {:ok, decoded} ->
        normalize_decoded(signature, decoded)

      {:error, _reason} ->
        normalize_decoded(signature, content, raw: true)
    end
  end

  defp decode_json(content) do
    case Jason.decode(content) do
      {:ok, data} ->
        {:ok, data}

      {:error, _} ->
        case JsonRemedy.repair(content) do
          {:ok, data} -> {:ok, data}
          {:ok, data, _logs} -> {:ok, data}
          {:error, reason} -> {:error, {:json_repair_failed, reason}}
        end
    end
  end

  defp normalize_decoded(signature, decoded, _opts \\ []) do
    case decoded do
      map when is_map(map) ->
        normalize_and_validate(signature, map)

      other ->
        wrap_single_field(signature, other)
    end
  end

  defp normalize_and_validate(signature, map) when is_map(map) do
    output_fields = signature.output_fields()
    normalized = normalize_output_keys(map, output_fields)

    case SignatureSinter.validate_with_sinter(signature, normalized, field_type: :outputs) do
      {:ok, validated} -> {:ok, Map.take(validated, output_fields)}
      {:error, reason} -> {:error, {:output_validation_failed, reason}}
    end
  rescue
    _ -> {:error, :output_validation_failed}
  end

  defp normalize_and_validate(_signature, _), do: {:error, :invalid_response_body}

  defp wrap_single_field(signature, value) do
    case signature.output_fields() do
      [field] ->
        normalize_and_validate(signature, %{field => normalize_scalar(value)})

      _ ->
        {:error, :invalid_response_body}
    end
  end

  defp normalize_scalar(value) when is_binary(value), do: value
  defp normalize_scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_scalar(value), do: to_string(value)

  defp normalize_output_keys(map, output_fields) do
    output_lookup = Map.new(output_fields, fn field -> {Atom.to_string(field), field} end)
    output_set = MapSet.new(output_fields)

    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      atom_key =
        cond do
          is_atom(key) and MapSet.member?(output_set, key) -> key
          is_binary(key) and Map.has_key?(output_lookup, key) -> Map.fetch!(output_lookup, key)
          true -> nil
        end

      if atom_key do
        Map.put(acc, atom_key, value)
      else
        acc
      end
    end)
  end
end
