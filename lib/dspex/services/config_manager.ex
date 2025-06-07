defmodule DSPEx.Services.ConfigManager do
  @moduledoc """
  Configuration manager for DSPEx that integrates with Foundation's config system.
  Sets up DSPEx-specific configuration and provides convenient access methods.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Wait for Foundation to be ready
    :ok = wait_for_foundation()

    # Set up DSPEx configuration schema
    setup_dspex_config()

    # Initialize circuit breakers for each provider
    setup_circuit_breakers()

    # Register with Foundation's service registry
    :ok = Foundation.ServiceRegistry.register(:production, :dspex_config_manager, self())

    # Store fallback config in state due to Foundation Config contract violations
    {:ok, %{fallback_config: get_default_config()}}
  end

  @doc """
  Get DSPEx configuration value
  """
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
  def update(path, value) when is_list(path) do
    Foundation.Config.update([:dspex | path], value)
  end

  def update(key, value) when is_atom(key) do
    Foundation.Config.update([:dspex, key], value)
  end

  @doc """
  Get configuration with default value
  """
  def get_with_default(path, default) when is_list(path) do
    Foundation.Config.get_with_default([:dspex | path], default)
  end

  def get_with_default(key, default) when is_atom(key) do
    Foundation.Config.get_with_default([:dspex, key], default)
  end

  # Private functions

  defp wait_for_foundation do
    case Foundation.available?() do
      true ->
        :ok

      false ->
        Process.sleep(100)
        wait_for_foundation()
    end
  end

  defp get_default_config do
    %{
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
      telemetry: %{
        enabled: true,
        detailed_logging: false,
        performance_tracking: true
      }
    }
  end

  defp get_from_fallback_config(path) do
    case GenServer.call(__MODULE__, {:get_config, path}) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :not_found}
    end
  end

  def handle_call({:get_config, path}, _from, %{fallback_config: config} = state) do
    result = get_nested_value(config, path)

    case result do
      {:ok, value} -> {:reply, {:ok, value}, state}
      :error -> {:reply, :error, state}
    end
  end

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

  defp setup_dspex_config do
    # Set up default DSPEx configuration
    default_config = get_default_config()

    # Apply default configuration - try setting the full structure at once
    case Foundation.Config.update([:dspex], default_config) do
      :ok ->
        Logger.debug("Successfully set DSPEx configuration")

      {:error, reason} ->
        Logger.warning("Failed to set DSPEx configuration: #{inspect(reason)}")
        # Fallback to individual leaf setting
        apply_config_updates(default_config, [:dspex])
    end
  end

  defp apply_config_updates(config, path) when is_map(config) do
    Enum.each(config, fn {key, value} ->
      new_path = path ++ [key]
      apply_config_updates(value, new_path)
    end)
  end

  defp apply_config_updates(value, path) do
    # Only update if the path doesn't already exist
    case Foundation.Config.get(path) do
      {:error, _} ->
        Logger.debug("Setting config at #{inspect(path)} to #{inspect(value)}")
        Foundation.Config.update(path, value)

      {:ok, existing} ->
        Logger.debug("Config at #{inspect(path)} already exists: #{inspect(existing)}")
        # Don't override existing config
        :ok
    end
  end

  defp setup_circuit_breakers do
    # Initialize circuit breakers for each provider (now available in Foundation v0.1.2)
    providers = [:gemini, :openai]

    Enum.each(providers, fn provider ->
      circuit_breaker_name = :"dspex_client_#{provider}"

      circuit_config =
        get_with_default([:providers, provider, :circuit_breaker], %{
          failure_threshold: 5,
          recovery_time: 30_000
        })

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
  end
end
