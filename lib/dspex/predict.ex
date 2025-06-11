defmodule DSPEx.Predict do
  @moduledoc """
  Core prediction orchestration program with Foundation integration.

  Implements the DSPEx.Program behavior to provide a structured interface
  for language model predictions with comprehensive telemetry, error handling,
  and observability through Foundation infrastructure.

  ## Usage as a Program

      iex> predict = %DSPEx.Predict{
      ...>   signature: MySignature,
      ...>   client: :openai,
      ...>   adapter: DSPEx.Adapter.Chat
      ...> }
      iex> inputs = %{question: "What is 2+2?"}
      iex> {:ok, outputs} = DSPEx.Program.forward(predict, inputs)
      iex> outputs
      %{answer: "4"}

  ## Legacy API (maintained for compatibility)

      iex> signature = MySignature  # question -> answer
      iex> inputs = %{question: "What is 2+2?"}
      iex> {:ok, outputs} = DSPEx.Predict.forward(signature, inputs)
      iex> outputs
      %{answer: "4"}

  """

  use DSPEx.Program

  defstruct [:signature, :client, :adapter, demos: []]

  @type t :: %__MODULE__{
          signature: module(),
          client: atom() | map(),
          adapter: module() | nil,
          demos: [map()]
        }
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
  Create a new Predict program.

  ## Parameters

  - `signature` - Signature module defining input/output contract
  - `client` - Client identifier (atom) or client configuration
  - `opts` - Optional configuration

  ## Options

  - `:adapter` - Adapter module (default: nil, uses DSPEx.Adapter fallback)
  - `:demos` - List of demonstration examples

  """
  @spec new(signature(), atom() | map(), keyword() | map()) :: t()
  def new(signature, client, opts \\ []) do
    %__MODULE__{
      signature: signature,
      client: client,
      adapter: get_option(opts, :adapter, nil),
      demos: get_option(opts, :demos, [])
    }
  end

  # Helper function to get options from either keyword list or map
  defp get_option(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp get_option(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)

  # DSPEx.Program behavior implementation - override the macro-generated defaults
  @impl DSPEx.Program
  def forward(program_or_signature, inputs, opts)

  def forward(program, inputs, opts) when is_struct(program, __MODULE__) do
    # Only generate correlation_id if not provided - avoid expensive UUID generation
    correlation_id =
      case Keyword.get(opts, :correlation_id) do
        nil -> Foundation.Utils.generate_correlation_id()
        existing_id -> existing_id
      end

    with {:ok, messages} <- format_messages(program, inputs, correlation_id),
         {:ok, response} <- make_request(program, messages, opts, correlation_id),
         {:ok, outputs} <- parse_response(program, response, correlation_id) do
      {:ok, outputs}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Legacy API for backward compatibility - signature as first argument
  @doc """
  Legacy forward API for backward compatibility - signature as first argument.

  Delegates to predict/2 for compatibility with existing code.
  """
  def forward(signature, inputs, opts) when is_atom(signature) do
    case opts do
      opts when is_map(opts) -> predict(signature, inputs, opts)
      [] -> predict(signature, inputs)
      opts when is_list(opts) -> predict(signature, inputs, Enum.into(opts, %{}))
    end
  end

  # Private helper functions for Program implementation

  defp format_messages(program, inputs, correlation_id) do
    start_time = System.monotonic_time()

    # Cache signature name to avoid repeated Module.split operations
    sig_name = signature_name(program.signature)

    :telemetry.execute(
      [:dspex, :adapter, :format, :start],
      %{system_time: System.system_time()},
      %{
        signature: sig_name,
        correlation_id: correlation_id
      }
    )

    # Use adapter to format messages with signature and demos
    result =
      if program.adapter && function_exported?(program.adapter, :format_messages, 3) do
        program.adapter.format_messages(program.signature, program.demos, inputs)
      else
        # Fallback to basic adapter
        DSPEx.Adapter.format_messages(program.signature, inputs)
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :adapter, :format, :stop],
      %{duration: duration, success: success},
      %{
        signature: sig_name,
        correlation_id: correlation_id,
        adapter: adapter_name(program.adapter)
      }
    )

    result
  end

  defp make_request(program, messages, opts, correlation_id) do
    # Build client options
    client_opts =
      opts
      |> Keyword.put(:correlation_id, correlation_id)
      |> Enum.into(%{})

    # Make request through client
    DSPEx.Client.request(program.client, messages, client_opts)
  end

  defp parse_response(program, response, correlation_id) do
    start_time = System.monotonic_time()

    # Cache signature name to avoid repeated Module.split operations
    sig_name = signature_name(program.signature)

    :telemetry.execute(
      [:dspex, :adapter, :parse, :start],
      %{system_time: System.system_time()},
      %{
        signature: sig_name,
        correlation_id: correlation_id
      }
    )

    # Use adapter to parse response
    result =
      if program.adapter && function_exported?(program.adapter, :parse_response, 2) do
        program.adapter.parse_response(program.signature, response)
      else
        # Fallback to basic adapter
        DSPEx.Adapter.parse_response(program.signature, response)
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :adapter, :parse, :stop],
      %{duration: duration, success: success},
      %{
        signature: sig_name,
        correlation_id: correlation_id,
        adapter: adapter_name(program.adapter)
      }
    )

    result
  end

  defp adapter_name(nil), do: "default"

  defp adapter_name(adapter) when is_atom(adapter) do
    adapter
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end

  defp adapter_name(_), do: "unknown"

  @doc """
  Execute a prediction using the given signature and inputs with Foundation observability.

  Legacy API for backward compatibility. For new code, prefer creating a DSPEx.Predict
  struct and using DSPEx.Program.forward/2.

  ## Parameters

  - `signature` - Signature module defining input/output contract
  - `inputs` - Map of input field values
  - `options` - Optional prediction configuration

  ## Returns

  - `{:ok, outputs}` - Successful prediction with parsed outputs
  - `{:error, reason}` - Error at any stage of the pipeline

  """
  @spec predict(signature(), inputs()) :: {:ok, outputs()} | {:error, atom()}
  def predict(signature, inputs) do
    predict(signature, inputs, %{})
  end

  @spec predict(signature(), inputs(), prediction_options()) ::
          {:ok, outputs()} | {:error, atom()}
  def predict(signature, inputs, options) do
    # Only generate correlation_id if not provided - avoid expensive UUID generation
    correlation_id =
      case Map.get(options, :correlation_id) do
        nil -> Foundation.Utils.generate_correlation_id()
        existing_id -> existing_id
      end

    # Start prediction telemetry
    start_time = System.monotonic_time()

    # Cache signature name to avoid repeated Module.split operations
    sig_name = signature_name(signature)

    :telemetry.execute(
      [:dspex, :predict, :start],
      %{
        system_time: System.system_time()
      },
      %{
        signature: sig_name,
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
        signature: sig_name,
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
    # Only generate correlation_id if not provided - avoid expensive UUID generation
    correlation_id =
      case Map.get(options, :correlation_id) do
        nil -> Foundation.Utils.generate_correlation_id()
        existing_id -> existing_id
      end

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
