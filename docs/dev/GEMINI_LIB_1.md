Excellent. Now that we have a comprehensive set of tests and sample programs, the next logical step is to implement the core library modules that these tests and examples depend on.

I will now provide the source code for the foundational modules of `DSPEx`, ensuring they align with the established tests and design principles. We will implement:

1.  **`DSPEx.Client`**: The resilient, stateful GenServer for interacting with LLM APIs.
2.  **`DSPEx.Adapter`**: The translation layer between DSPEx signatures and concrete API formats.
3.  **`DSPEx.Program`**: The core behaviour for all executable modules, and the `Prediction` struct.
4.  **`DSPEx.Predict`**: The primary module for executing single-turn predictions.

This will bring the project much closer to a complete, runnable state.

---

### **New File: `dspex/lib/dspex/client.ex`**

This module implements the resilient, concurrent client using a `GenServer`, `Req` for HTTP requests, `Cachex` for caching, and `Fuse` for circuit breaking.

```elixir
defmodule DSPEx.Client do
  @moduledoc """
  A stateful, resilient GenServer for making requests to an LLM API.

  Each `Client` process is configured for a specific LLM provider and model
  and manages its own cache, API keys, and circuit breaker state. This ensures
  that contention or failures with one provider do not affect others.
  """
  use GenServer, restart: :transient

  require Logger

  alias DSPEx.Adapter.Chat

  # =================================================================
  # Public API
  # =================================================================

  @doc """
  Starts a `DSPEx.Client` GenServer.

  ## Options

    * `:name` (optional) - A unique atom to register the client process.
    * `:adapter` (optional) - The adapter module. Defaults to `DSPEx.Adapter.Chat`.
    * `:api_key` (required) - The API key for the LLM provider.
    * `:model` (required) - The model name (e.g., "gpt-4o-mini").
    * `:base_url` (optional) - The API base URL. Defaults to OpenAI's.
    * `:max_retries` (optional) - Number of retries on failure. Defaults to 3.
    * `:timeout` (optional) - Request timeout in ms. Defaults to 30_000.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Makes a synchronous request to the LLM API.

  This is the primary way to interact with the client. It blocks until a
  response is received, the request times out, or the circuit breaker opens.
  """
  @spec request(pid() | atom(), map()) :: {:ok, map()} | {:error, any()}
  def request(client, request_data) do
    # Default timeout for the GenServer call.
    GenServer.call(client, {:request, request_data}, 60_000)
  end

  # =================================================================
  # GenServer Callbacks
  # =================================================================

  @impl true
  def init(opts) do
    # Validate and set configuration
    api_key = Keyword.get(opts, :api_key) || System.get_env("OPENAI_API_KEY")
    model = Keyword.fetch!(opts, :model)
    adapter = Keyword.get(opts, :adapter, Chat)
    base_url = Keyword.get(opts, :base_url, "https://api.openai.com/v1/chat/completions")
    max_retries = Keyword.get(opts, :max_retries, 3)
    timeout = Keyword.get(opts, :timeout, 30_000)

    unless api_key, do: raise("Missing required :api_key or OPENAI_API_KEY env var")

    # Set up names for dependent services, scoped to this client
    # This ensures multiple clients don't share caches or fuses.
    client_id = :erlang.unique_integer([:positive, :monotonic])
    fuse_name = :"fuse_#{client_id}"
    cache_name = :"cache_#{client_id}"

    # Start the cache for this client
    :ok = Cachex.start_link(name: cache_name)

    # Configure and install the circuit breaker
    fuse_opts = [
      strategy: {Fuse.Strategy.ExponentialBackoff, {1000, 2.0}},
      reset_timeout: 10_000,
      failure_threshold: 5
    ]
    :ok = Fuse.install(fuse_name, fuse_opts)

    Logger.info("DSPEx.Client for model '#{model}' started.")

    state = %{
      config: %{
        api_key: api_key,
        model: model,
        base_url: base_url,
        max_retries: max_retries,
        timeout: timeout,
        adapter: adapter
      },
      fuse_name: fuse_name,
      cache_name: cache_name
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:request, request_data}, _from, state) do
    cache_key = build_cache_key(request_data, state.config.model)

    response =
      Cachex.get_or_set(state.cache_name, cache_key, fn ->
        Fuse.call({:default, state.fuse_name}, fn ->
          http_request_with_retry(request_data, state.config)
        end)
      end)

    {:reply, response, state}
  end

  # =================================================================
  # Private Helpers
  # =================================================================

  defp http_request_with_retry(request_data, config, attempt \\ 1) do
    case http_post(request_data, config) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} = error ->
        if attempt < config.max_retries do
          # Exponential backoff for retries
          Process.sleep(100 * round(:math.pow(2, attempt)))
          http_request_with_retry(request_data, config, attempt + 1)
        else
          Logger.error("Request failed after #{config.max_retries} attempts. Reason: #{inspect(reason)}")
          # Raise to trip the circuit breaker after all retries fail.
          raise "API request failed: #{inspect(reason)}"
        end
    end
  end

  defp http_post(request_data, config) do
    headers = [
      {"Authorization", "Bearer #{config.api_key}"},
      {"Content-Type", "application/json"}
    ]

    # Merge model into the request body
    body = Map.merge(request_data, %{model: config.model})

    case Req.post(config.base_url, json: body, headers: headers, timeout: config.timeout) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: status, body: error_body}} ->
        {:error, {:api_error, status, error_body}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp build_cache_key(request_data, model) do
    term_to_hash = {request_data, model}
    :crypto.hash(:sha256, :erlang.term_to_binary(term_to_hash))
  end
end
```

---

### **New File: `dspex/lib/dspex/adapter.ex`**

This module defines the `Adapter` behaviour and provides the default `Chat` implementation for formatting prompts and parsing responses.

```elixir
defmodule DSPEx.Adapter do
  @moduledoc "A behaviour for formatting prompts and parsing LLM responses."

  @doc "Formats inputs and demos into a list of messages for an LLM client."
  @callback format(signature :: module(), inputs :: map(), demos :: list(DSPEx.Example.t())) ::
              {:ok, list(map())} | {:error, any()}

  @doc "Parses the raw response body from an LLM client into a map of output fields."
  @callback parse(signature :: module(), raw_response :: map() | String.t()) ::
              {:ok, map()} | {:error, any()}
end

defmodule DSPEx.Adapter.Chat do
  @moduledoc "Default adapter for chat-based models like OpenAI's."
  @behaviour DSPEx.Adapter

  @impl DSPEx.Adapter
  def format(signature_module, inputs, demos \\ []) do
    system_message = %{
      role: "system",
      content: build_system_prompt(signature_module)
    }

    demo_messages =
      Enum.flat_map(demos, fn demo ->
        [
          %{role: "user", content: format_fields(signature_module.input_fields(), demo)},
          %{role: "assistant", content: format_fields(signature_module.output_fields(), demo)}
        ]
      end)

    user_message = %{
      role: "user",
      content: format_fields(signature_module.input_fields(), inputs)
    }

    {:ok, [system_message | demo_messages] ++ [user_message]}
  end

  @impl DSPEx.Adapter
  def parse(signature_module, raw_response) when is_map(raw_response) do
    # Handle structured JSON response from client
    raw_text = get_in(raw_response, ["choices", 0, "message", "content"]) || ""
    parse(signature_module, raw_text)
  end

  def parse(signature_module, raw_text) when is_binary(raw_text) do
    # Simple parsing for the '[[ field ]]' format.
    output_fields = signature_module.output_fields()

    parsed =
      Enum.reduce(output_fields, %{}, fn field, acc ->
        pattern = ~r/\[\[\s*#{Atom.to_string(field)}\s*\]\]\s*(.*?)(?=\[\[|$)/s

        case Regex.run(pattern, raw_text, capture: :all_but_first) do
          [content] -> Map.put(acc, field, String.trim(content))
          nil -> acc
        end
      end)

    missing_fields =
      Enum.filter(output_fields, fn field ->
        not Map.has_key?(parsed, field)
      end)

    if Enum.empty?(missing_fields) do
      {:ok, parsed}
    else
      {:error, "Failed to parse fields: #{inspect(missing_fields)}"}
    end
  end

  defp build_system_prompt(signature_module) do
    """
    #{signature_module.instructions()}

    Follow the following format for your response. Do not add any other text.

    #{format_output_placeholders(signature_module.output_fields())}
    """
  end

  defp format_fields(fields, data) when is_map(data) do
    fields
    |> Enum.map_join("\n\n", fn field ->
      "[[ #{field} ]]\n#{Map.get(data, field, "")}"
    end)
  end

  defp format_fields(fields, %DSPEx.Example{data: data}) do
    format_fields(fields, data)
  end

  defp format_output_placeholders(fields) do
    fields
    |> Enum.map_join("\n\n", fn field ->
      "[[ #{field} ]]\n..."
    end)
  end
end
```

---

### **New File: `dspex/lib/dspex/program.ex`**

This central file defines the `DSPEx.Program` behaviour that all executable modules must implement. It also defines the standard `DSPEx.Prediction` struct that `forward/2` calls return.

```elixir
defmodule DSPEx.Program do
  @moduledoc """
  Defines the behaviour for all executable DSPEx modules.

  This contract ensures that any program can be composed, evaluated, and
  optimized in a consistent way.
  """

  @doc """
  The primary execution function for the program.
  Takes the program's own struct and a map of inputs (matching the
  signature's input fields) and returns a `DSPEx.Prediction` struct.
  """
  @callback forward(program :: struct(), inputs :: map()) ::
              {:ok, DSPEx.Prediction.t()} | {:error, any()}

  @doc """
  Returns a list of the program's named predictors.
  This is essential for the teleprompter to know which parts of the
  program to optimize. The format is `[{name, predictor}]`.
  """
  @callback named_predictors(program :: struct()) :: [{String.t(), struct()}]

  @doc """
  Returns a new program with a specific predictor updated.
  This is the mechanism used by the teleprompter to apply optimizations.
  """
  @callback update_predictor(program :: struct(), name :: String.t(), new_predictor :: struct()) ::
              struct()

  # Helper functions to provide a clean, unified API.
  def forward(program, inputs), do: program.__struct__.forward(program, inputs)
  def named_predictors(program), do: program.__struct__.named_predictors(program)
  def update_predictor(program, name, new_predictor), do: program.__struct__.update_predictor(program, name, new_predictor)

  # Convenience functions for program state management, mapping to predictor state.
  def save_state(program) do
    program
    |> named_predictors()
    |> Enum.map(fn {name, predictor} -> {name, predictor.demos} end)
    |> Enum.into(%{})
  end

  def load_state(program, state) do
    Enum.reduce(state, program, fn {name, demos}, acc_program ->
      # Find predictor by name
      {_name, predictor} =
        Enum.find(named_predictors(acc_program), fn {p_name, _} -> p_name == name end)

      # Update predictor with loaded demos
      new_predictor = %{predictor | demos: demos}
      update_predictor(acc_program, name, new_predictor)
    end)
  end

  def reset(program) do
    load_state(program, %{})
  end
end

defmodule DSPEx.Prediction do
  @moduledoc "A struct representing the output of a DSPEx Program."
  @enforce_keys [:outputs]
  defstruct [:inputs, :outputs, :usage, :raw_response]

  @type t :: %__MODULE__{
          inputs: map() | nil,
          outputs: map(),
          usage: map() | nil,
          raw_response: map() | nil
        }

  # Make the prediction struct act like a map for accessing output fields.
  defimpl Access do
    def fetch(%DSPEx.Prediction{outputs: outputs}, key), do: Map.fetch(outputs, key)
    def get(%DSPEx.Prediction{outputs: outputs}, key, default), do: Map.get(outputs, key, default)

    def get_and_update(%DSPEx.Prediction{} = p, key, fun) do
      {value, new_outputs} = Map.get_and_update(p.outputs, key, fun)
      {value, %{p | outputs: new_outputs}}
    end

    def pop(%DSPEx.Prediction{} = p, key) do
      {value, new_outputs} = Map.pop(p.outputs, key)
      {value, %{p | outputs: new_outputs}}
    end
  end
end
```

---

### **New File: `dspex/lib/dspex/predict.ex`**

This is the concrete implementation of the simplest `DSPEx.Program`, which orchestrates a single prediction.

```elixir
defmodule DSPEx.Predict do
  @moduledoc """
  A simple DSPEx.Program for single-turn predictions.

  This module orchestrates the process of formatting a request using an adapter,
  sending it to a client, and parsing the response. It is the core building
  block for more complex programs.
  """
  alias DSPEx.{Client, Prediction, Example}

  defstruct [
    :signature_module,
    :client,
    :adapter,
    demos: [],
    max_demos: 5,
    name: "predictor" # Default name for teleprompter targeting
  ]

  @type t :: %__MODULE__{
          signature_module: module(),
          client: pid() | atom(),
          adapter: module(),
          demos: list(Example.t()),
          max_demos: non_neg_integer(),
          name: String.t()
        }

  @doc "Creates a new Predict struct."
  def new(signature, opts \\ []) do
    signature_module =
      if is_binary(signature) do
        # Dynamically create a signature module if a string is passed.
        # This is a convenience for simple, on-the-fly signatures.
        id = :erlang.unique_integer([:positive, :monotonic])
        module_name = :"Elixir.DSPEx.DynamicSignature#{id}"
        {:module, ^module_name, _, _} = Code.string_to_quoted!("defmodule #{module_name} do\n  use DSPEx.Signature, \"#{signature}\"\nend")
        Code.eval_quoted(module_name)
        module_name
      else
        signature
      end

    adapter = Keyword.get(opts, :adapter, DSPEx.Adapter.Chat)
    client = Keyword.fetch!(opts, :client)

    struct(__MODULE__, [
      signature_module: signature_module,
      client: client,
      adapter: adapter
      | Keyword.drop(opts, [:client, :adapter])
    ])
  end

  @doc "The main execution function for Predict."
  def forward(%__MODULE__{} = program, inputs) do
    with :ok <- program.signature_module.validate_inputs(inputs),
         {:ok, messages} <- program.adapter.format(program.signature_module, inputs, program.demos),
         {:ok, response_body} <- Client.request(program.client, %{messages: messages}),
         {:ok, parsed_outputs} <- program.adapter.parse(program.signature_module, response_body) do
      prediction = %Prediction{
        inputs: inputs,
        outputs: parsed_outputs,
        usage: response_body["usage"],
        raw_response: response_body
      }

      {:ok, prediction}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Adds a demonstration example to the predictor, returning a new predictor."
  def add_demo(%__MODULE__{} = program, demo) do
    new_demos =
      (program.demos ++ [demo])
      |> Enum.take(-program.max_demos)

    %{program | demos: new_demos}
  end

  @doc "Clears all demos from the predictor."
  def clear_demos(%__MODULE__{} = program) do
    %{program | demos: []}
  end

  @doc "Processes a batch of inputs, typically concurrently."
  def batch(%__MODULE__{} = program, inputs_list) do
    inputs_list
    |> Task.async_stream(&forward(program, &1), max_concurrency: 10)
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
```