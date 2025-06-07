defmodule DSPEx.Predict do
  @moduledoc """
  Core prediction orchestration module.

  Coordinates between signatures, adapters, and clients to execute
  language model predictions. Provides a simple, functional interface
  for making predictions based on DSPEx signatures.

  ## Examples

      iex> signature = MySignature  # question -> answer
      iex> inputs = %{question: "What is 2+2?"}
      iex> {:ok, outputs} = DSPEx.Predict.forward(signature, inputs)
      iex> outputs
      %{answer: "4"}

  """

  @type signature :: module()
  @type inputs :: map()
  @type outputs :: map()
  @type prediction_options :: %{
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer()
        }

  @doc """
  Execute a prediction using the given signature and inputs.

  This is the main entry point for making language model predictions.
  It orchestrates the full pipeline: input validation, message formatting,
  HTTP request, response parsing, and output validation.

  ## Parameters

  - `signature` - Signature module defining input/output contract
  - `inputs` - Map of input field values
  - `options` - Optional prediction configuration

  ## Returns

  - `{:ok, outputs}` - Successful prediction with parsed outputs
  - `{:error, reason}` - Error at any stage of the pipeline

  """
  @spec forward(signature(), inputs()) :: {:ok, outputs()} | {:error, atom()}
  def forward(signature, inputs) do
    forward(signature, inputs, %{})
  end

  @spec forward(signature(), inputs(), prediction_options()) ::
          {:ok, outputs()} | {:error, atom()}
  def forward(signature, inputs, options) do
    with {:ok, messages} <- DSPEx.Adapter.format_messages(signature, inputs),
         {:ok, response} <- DSPEx.Client.request(messages, options),
         {:ok, outputs} <- DSPEx.Adapter.parse_response(signature, response) do
      {:ok, outputs}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Execute a prediction and return the result for a specific output field.

  Convenience function for signatures with a single primary output field.

  ## Parameters

  - `signature` - Signature module
  - `inputs` - Input field values
  - `output_field` - The specific output field to extract
  - `options` - Optional prediction configuration

  ## Returns

  - `{:ok, value}` - The value of the specified output field
  - `{:error, reason}` - Error during prediction or field not found

  """
  @spec predict_field(signature(), inputs(), atom()) :: {:ok, any()} | {:error, atom()}
  def predict_field(signature, inputs, output_field) do
    predict_field(signature, inputs, output_field, %{})
  end

  @spec predict_field(signature(), inputs(), atom(), prediction_options()) ::
          {:ok, any()} | {:error, atom()}
  def predict_field(signature, inputs, output_field, options) do
    case forward(signature, inputs, options) do
      {:ok, outputs} ->
        case Map.fetch(outputs, output_field) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, :field_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validate that a signature is compatible with given inputs.

  Checks that all required input fields are present without making
  an actual prediction. Useful for validation before batch processing.

  ## Parameters

  - `signature` - Signature module
  - `inputs` - Input field values to validate

  ## Returns

  - `:ok` - All required fields present
  - `{:error, reason}` - Validation failed

  """
  @spec validate_inputs(signature(), inputs()) :: :ok | {:error, atom()}
  def validate_inputs(signature, inputs) do
    case DSPEx.Adapter.format_messages(signature, inputs) do
      {:ok, _messages} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the expected input and output fields for a signature.

  Utility function for introspecting signature requirements.

  ## Parameters

  - `signature` - Signature module

  ## Returns

  - `{:ok, %{inputs: [...], outputs: [...]}}` - Field lists
  - `{:error, reason}` - Invalid signature

  """
  @spec describe_signature(signature()) :: {:ok, map()} | {:error, atom()}
  def describe_signature(signature) do
    with {:ok, inputs} <- get_input_fields(signature),
         {:ok, outputs} <- get_output_fields(signature) do
      description = %{
        inputs: inputs,
        outputs: outputs,
        description: get_description(signature)
      }

      {:ok, description}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  @spec get_input_fields(signature()) :: {:ok, [atom()]} | {:error, :invalid_signature}
  defp get_input_fields(signature) do
    if function_exported?(signature, :input_fields, 0) do
      {:ok, signature.input_fields()}
    else
      {:error, :invalid_signature}
    end
  end

  @spec get_output_fields(signature()) :: {:ok, [atom()]} | {:error, :invalid_signature}
  defp get_output_fields(signature) do
    if function_exported?(signature, :output_fields, 0) do
      {:ok, signature.output_fields()}
    else
      {:error, :invalid_signature}
    end
  end

  @spec get_description(signature()) :: String.t()
  defp get_description(signature) do
    if function_exported?(signature, :description, 0) do
      signature.description()
    else
      "No description available"
    end
  end
end
