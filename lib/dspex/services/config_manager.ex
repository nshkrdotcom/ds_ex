defmodule DSPEx.Services.ConfigManager do
  @moduledoc """
  Configuration manager for DSPEx that integrates with Foundation's config system.
  Sets up DSPEx-specific configuration and provides convenient access methods.
  """

  use GenServer
  require Logger

  @doc """
  Starts the configuration manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes the configuration manager.
  """
  @impl GenServer
  @spec init(term()) :: {:ok, map()}
  def init(_opts) do
    # Wait for Foundation to be ready
    :ok = wait_for_foundation()

    # Set up DSPEx configuration schema
    setup_dspex_config()

    # Initialize circuit breakers for each provider
    setup_circuit_breakers()

    # Register with Foundation's service registry using a valid service name
    # Use :config_server as it's in the allowed list
    :ok = Foundation.ServiceRegistry.register(:production, :config_server, self())

    # Store fallback config in state due to Foundation Config contract violations
    {:ok, %{fallback_config: get_default_config()}}
  end

  @doc """
  Get DSPEx configuration value
  """
  @spec get(list(atom()) | atom()) :: {:ok, term()} | {:error, atom()}
  def get(path) when is_list(path) do
    # Foundation Config has contract violations - use fallback until fixed
    get_from_fallback_config(path)
  end

  def get(key) when is_atom(key) do
    get_from_fallback_config([key])
  end

  @doc """
  Update DSPEx configuration value
  """
  @spec update(list(atom()) | atom(), term()) :: :ok | {:error, term()}
  def update(path, value) when is_list(path) do
    Foundation.Config.update([:dspex | path], value)
  end

  def update(key, value) when is_atom(key) do
    Foundation.Config.update([:dspex, key], value)
  end

  @doc """
  Get configuration with default value
  """
  @spec get_with_default(list(atom()) | atom(), term()) :: term()
  def get_with_default(path, default) when is_list(path) do
    case get_from_fallback_config(path) do
      {:ok, value} -> value
      {:error, _} -> default
    end
  end

  def get_with_default(key, default) when is_atom(key) do
    get_with_default([key], default)
  end

  # Private functions

  @spec wait_for_foundation() :: :ok
  defp wait_for_foundation do
    case Foundation.available?() do
      true ->
        :ok

      false ->
        Process.sleep(100)
        wait_for_foundation()
    end
  end

  @spec get_default_config() :: map()
  defp get_default_config do
    base_config = %{
      providers: %{
        gemini: %{
          api_key: {:system, "GEMINI_API_KEY"},
          base_url: "https://generativelanguage.googleapis.com/v1beta/models",
          default_model: "gemini-2.5-flash-preview-05-20",
          timeout: 30_000,
          rate_limit: %{
            requests_per_minute: 60,
            tokens_per_minute: 100_000
          },
          circuit_breaker: %{
            failure_threshold: 5,
            recovery_time: 30_000
          }
        },
        openai: %{
          api_key: {:system, "OPENAI_API_KEY"},
          base_url: "https://api.openai.com/v1",
          default_model: "gpt-4",
          timeout: 30_000,
          rate_limit: %{
            requests_per_minute: 50,
            tokens_per_minute: 150_000
          },
          circuit_breaker: %{
            failure_threshold: 3,
            recovery_time: 15_000
          }
        }
      },
      prediction: %{
        default_provider: :gemini,
        default_temperature: 0.7,
        default_max_tokens: 150,
        cache_enabled: true,
        cache_ttl: 3600
      },
      teleprompters: %{
        beacon: %{
          default_instruction_model: :openai,
          default_evaluation_model: :gemini,
          max_concurrent_operations: 20,
          default_timeout: 60_000,
          optimization: %{
            max_trials: 100,
            convergence_patience: 5,
            improvement_threshold: 0.01
          },
          bayesian_optimization: %{
            acquisition_function: :expected_improvement,
            surrogate_model: :gaussian_process,
            exploration_exploitation_tradeoff: 0.1
          }
        }
      },
      telemetry: %{
        enabled: true,
        detailed_logging: false,
        performance_tracking: true
      }
    }

    # Merge with Mix config (config/test.exs, config/dev.exs, etc.)
    mix_config = Application.get_env(:dspex, :providers, %{})
    mix_prediction_config = Application.get_env(:dspex, :prediction, %{})
    mix_teleprompter_config = Application.get_env(:dspex, :teleprompters, %{})
    mix_telemetry_config = Application.get_env(:dspex, :telemetry, %{})

    base_config
    |> put_in([:providers], Map.merge(base_config.providers, mix_config))
    |> put_in([:prediction], Map.merge(base_config.prediction, mix_prediction_config))
    |> put_in([:teleprompters], Map.merge(base_config.teleprompters, mix_teleprompter_config))
    |> put_in([:telemetry], Map.merge(base_config.telemetry, mix_telemetry_config))
  end

  @spec get_from_fallback_config(list(atom())) :: {:ok, term()} | {:error, atom()}
  defp get_from_fallback_config(path) do
    case GenServer.call(__MODULE__, {:get_config, path}) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :not_found}
    end
  end

  @impl GenServer
  @spec handle_call({:get_config, list(atom())}, GenServer.from(), map()) ::
          {:reply, {:ok, term()} | :error, map()}
  def handle_call({:get_config, path}, _from, %{fallback_config: config} = state) do
    result = get_nested_value(config, path)

    case result do
      {:ok, value} -> {:reply, {:ok, value}, state}
      :error -> {:reply, :error, state}
    end
  end

  @spec get_nested_value(map() | term(), list(atom())) :: {:ok, term()} | :error
  defp get_nested_value(config, []) do
    {:ok, config}
  end

  defp get_nested_value(config, [key | rest]) when is_map(config) do
    case Map.get(config, key) do
      nil -> :error
      value -> get_nested_value(value, rest)
    end
  end

  defp get_nested_value(_, _), do: :error

  @spec setup_dspex_config() :: :ok
  defp setup_dspex_config do
    # Set up default DSPEx configuration
    default_config = get_default_config()

    # Try to apply default configuration - Foundation may restrict some paths
    # Foundation.Config may throw errors despite Dialyzer thinking it only returns :ok
    try do
      # Dialyzer expects this to only return :ok, but runtime may differ
      :ok = Foundation.Config.update([:dspex], default_config)
      Logger.debug("Successfully set DSPEx configuration")
    rescue
      # Handle MatchError when Foundation.Config.update returns an error tuple
      error in MatchError ->
        case error.term do
          {:error, %{error_type: :config_update_forbidden}} ->
            Logger.debug("DSPEx config path is restricted - using fallback config only")

          {:error, reason} ->
            Logger.warning("Failed to set DSPEx configuration: #{inspect(reason)}")

          other ->
            Logger.warning("Unexpected MatchError term: #{inspect(other)}")
        end

      error ->
        Logger.warning("Exception setting DSPEx configuration: #{inspect(error)}")
    catch
      # Handle thrown values (less common)
      kind, reason ->
        Logger.warning(
          "Unexpected thrown value setting DSPEx configuration: #{kind} #{inspect(reason)}"
        )
    end

    :ok
  end

  @spec setup_circuit_breakers() :: :ok
  defp setup_circuit_breakers do
    # Initialize circuit breakers for each provider (now available in Foundation v0.1.2)
    providers = [:gemini, :openai]
    fallback_config = get_default_config()

    Enum.each(providers, fn provider ->
      circuit_breaker_name = :"dspex_client_#{provider}"

      # Get circuit breaker config directly from fallback config during init
      circuit_config =
        get_in(fallback_config, [:providers, provider, :circuit_breaker]) ||
          %{
            failure_threshold: 5,
            recovery_time: 30_000
          }

      # Initialize circuit breaker with Foundation's infrastructure service
      case Foundation.Infrastructure.initialize_circuit_breaker(
             circuit_breaker_name,
             circuit_config
           ) do
        :ok ->
          Logger.debug("Initialized circuit breaker for #{provider}")

        {:error, reason} ->
          Logger.warning(
            "Failed to initialize circuit breaker for #{provider}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  # Required GenServer callbacks for complete implementation
  @impl GenServer
  def handle_cast(_msg, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, _state), do: :ok
end
