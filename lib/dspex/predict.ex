defmodule DSPEx.Predict do
  @moduledoc """
  Core prediction orchestration module with Foundation integration.

  Coordinates between signatures, adapters, and clients to execute
  language model predictions with comprehensive telemetry, error handling,
  and observability through Foundation infrastructure.

  ## Examples

      iex> signature = MySignature  # question -> answer
      iex> inputs = %{question: "What is 2+2?"}
      iex> {:ok, outputs} = DSPEx.Predict.forward(signature, inputs)
      iex> outputs
      %{answer: "4"}

      # With custom options and correlation tracking
      iex> {:ok, outputs} = DSPEx.Predict.forward(signature, inputs, %{
      ...>   provider: :openai,
      ...>   temperature: 0.9,
      ...>   correlation_id: "prediction-123"
      ...> })

  """

  @type signature :: module()
  @type inputs :: map()
  @type outputs :: map()
  @type prediction_options :: %{
          optional(:provider) => atom(),
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer(),
          optional(:correlation_id) => String.t()
        }

  @doc """
  Execute a prediction using the given signature and inputs with Foundation observability.

  This is the main entry point for making language model predictions.
  It orchestrates the full pipeline: input validation, message formatting,
  HTTP request, response parsing, and output validation with comprehensive
  telemetry and error tracking.

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
    correlation_id =
      Map.get(options, :correlation_id) || Foundation.Utils.generate_correlation_id()

    # Start prediction telemetry
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :predict, :start],
      %{
        system_time: System.system_time()
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id,
        input_count: map_size(inputs)
      }
    )

    # Execute the prediction pipeline
    result = execute_prediction_pipeline(signature, inputs, options, correlation_id)

    # Calculate duration and success
    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    # Emit telemetry stop event
    :telemetry.execute(
      [:dspex, :predict, :stop],
      %{
        duration: duration,
        success: success
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id,
        provider: Map.get(options, :provider)
      }
    )

    result
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
    correlation_id =
      Map.get(options, :correlation_id) || Foundation.Utils.generate_correlation_id()

    case forward(signature, inputs, Map.put(options, :correlation_id, correlation_id)) do
      {:ok, outputs} ->
        case Map.fetch(outputs, output_field) do
          {:ok, value} ->
            # Foundation v0.1.3 fixed - re-enabled!
            Foundation.Events.new_event(
              :field_extraction_success,
              %{
                signature: signature_name(signature),
                field: output_field,
                value_type: type_of(value)
              },
              correlation_id: correlation_id
            )
            |> Foundation.Events.store()

            {:ok, value}

          :error ->
            # Foundation v0.1.3 fixed - re-enabled!
            Foundation.Events.new_event(
              :field_extraction_error,
              %{
                signature: signature_name(signature),
                field: output_field,
                available_fields: Map.keys(outputs)
              },
              correlation_id: correlation_id
            )
            |> Foundation.Events.store()

            {:error, :field_not_found}
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
    correlation_id = Foundation.Utils.generate_correlation_id()

    # Start validation telemetry
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :signature, :validation, :start],
      %{
        system_time: System.system_time()
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id
      }
    )

    result =
      case DSPEx.Adapter.format_messages(signature, inputs) do
        {:ok, _messages} -> :ok
        {:error, reason} -> {:error, reason}
      end

    # Stop validation telemetry
    duration = System.monotonic_time() - start_time
    success = result == :ok

    :telemetry.execute(
      [:dspex, :signature, :validation, :stop],
      %{
        duration: duration,
        success: success
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id
      }
    )

    result
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
        description: get_description(signature),
        name: signature_name(signature)
      }

      {:ok, description}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  defp execute_prediction_pipeline(signature, inputs, options, correlation_id) do
    with {:ok, messages} <- format_messages_with_telemetry(signature, inputs, correlation_id),
         {:ok, response} <- make_client_request(messages, options, correlation_id),
         {:ok, outputs} <- parse_response_with_telemetry(signature, response, correlation_id) do
      {:ok, outputs}
    else
      {:error, reason} ->
        # Emit exception telemetry
        :telemetry.execute([:dspex, :predict, :exception], %{}, %{
          signature: signature_name(signature),
          correlation_id: correlation_id,
          error_type: reason
        })

        {:error, reason}
    end
  end

  defp format_messages_with_telemetry(signature, inputs, correlation_id) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :adapter, :format, :start],
      %{
        system_time: System.system_time()
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id
      }
    )

    result = DSPEx.Adapter.format_messages(signature, inputs)

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :adapter, :format, :stop],
      %{
        duration: duration,
        success: success
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id,
        adapter: "default"
      }
    )

    result
  end

  defp make_client_request(messages, options, correlation_id) do
    # Add correlation_id to options for client request
    client_options = Map.put(options, :correlation_id, correlation_id)
    DSPEx.Client.request(messages, client_options)
  end

  defp parse_response_with_telemetry(signature, response, correlation_id) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :adapter, :parse, :start],
      %{
        system_time: System.system_time()
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id
      }
    )

    result = DSPEx.Adapter.parse_response(signature, response)

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :adapter, :parse, :stop],
      %{
        duration: duration,
        success: success
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id,
        adapter: "default"
      }
    )

    result
  end

  defp get_input_fields(signature) do
    if function_exported?(signature, :input_fields, 0) do
      {:ok, signature.input_fields()}
    else
      {:error, :invalid_signature}
    end
  end

  defp get_output_fields(signature) do
    if function_exported?(signature, :output_fields, 0) do
      {:ok, signature.output_fields()}
    else
      {:error, :invalid_signature}
    end
  end

  defp get_description(signature) do
    if function_exported?(signature, :description, 0) do
      signature.description()
    else
      "No description available"
    end
  end

  defp signature_name(signature) when is_atom(signature) do
    signature
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end

  defp signature_name(_signature), do: :unknown

  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_number(value), do: :number
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_map(value), do: :map
  defp type_of(_), do: :unknown
end
