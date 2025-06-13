defmodule DSPEx.Config.ElixactSchemas do
  @moduledoc """
  Elixact schema definitions for DSPEx configuration validation.

  This module provides schema-based validation for DSPEx configuration
  with enhanced error reporting and path-based validation mapping.
  """

  @doc """
  Maps configuration paths to their corresponding validation function.
  """
  @spec path_to_schema(list(atom())) :: {:ok, module(), list(atom())} | {:error, :unknown_path}
  def path_to_schema(path)

  # Client configuration mappings
  def path_to_schema([:dspex, :client, field])
      when field in [:timeout, :retry_attempts, :backoff_factor] do
    {:ok, ClientConfiguration, [field]}
  end

  # Evaluation configuration mappings  
  def path_to_schema([:dspex, :evaluation, field]) when field in [:batch_size, :parallel_limit] do
    {:ok, EvaluationConfiguration, [field]}
  end

  # Teleprompter configuration mappings
  def path_to_schema([:dspex, :teleprompter, field])
      when field in [:bootstrap_examples, :validation_threshold] do
    {:ok, TeleprompterConfiguration, [field]}
  end

  # Logging configuration mappings
  def path_to_schema([:dspex, :logging, field]) when field in [:level, :correlation_enabled] do
    {:ok, LoggingConfiguration, [field]}
  end

  # Provider configuration mappings (with wildcard support)
  def path_to_schema([:dspex, :providers, _provider, field])
      when field in [:api_key, :base_url, :default_model, :timeout] do
    {:ok, ProviderConfiguration, [field]}
  end

  def path_to_schema([:dspex, :providers, _provider, :rate_limit, field])
      when field in [:requests_per_minute, :tokens_per_minute] do
    {:ok, ProviderConfiguration, [:rate_limit, field]}
  end

  def path_to_schema([:dspex, :providers, _provider, :circuit_breaker, field])
      when field in [:failure_threshold, :recovery_time] do
    {:ok, ProviderConfiguration, [:circuit_breaker, field]}
  end

  # Prediction configuration mappings
  def path_to_schema([:dspex, :prediction, field])
      when field in [
             :default_provider,
             :default_temperature,
             :default_max_tokens,
             :cache_enabled,
             :cache_ttl
           ] do
    {:ok, PredictionConfiguration, [field]}
  end

  # BEACON teleprompter configuration mappings
  def path_to_schema([:dspex, :teleprompters, :beacon, field])
      when field in [
             :default_instruction_model,
             :default_evaluation_model,
             :max_concurrent_operations,
             :default_timeout
           ] do
    {:ok, BEACONConfiguration, [field]}
  end

  def path_to_schema([:dspex, :teleprompters, :beacon, :optimization, field])
      when field in [:max_trials, :convergence_patience, :improvement_threshold] do
    {:ok, BEACONConfiguration, [:optimization, field]}
  end

  def path_to_schema([:dspex, :teleprompters, :beacon, :bayesian_optimization, field])
      when field in [:acquisition_function, :surrogate_model, :exploration_exploitation_tradeoff] do
    {:ok, BEACONConfiguration, [:bayesian_optimization, field]}
  end

  # Telemetry configuration mappings
  def path_to_schema([:dspex, :telemetry, field])
      when field in [:enabled, :detailed_logging, :performance_tracking] do
    {:ok, TelemetryConfiguration, [field]}
  end

  # Unknown path
  def path_to_schema(_path), do: {:error, :unknown_path}

  @doc """
  Validates a configuration value using schema-based validation.
  """
  @spec validate_config_value(list(atom()), term()) :: :ok | {:error, term()}
  def validate_config_value(path, value) do
    case path_to_schema(path) do
      {:ok, schema_module, field_path} ->
        validate_field_with_schema(schema_module, field_path, value)

      {:error, :unknown_path} ->
        {:error, {:unknown_path, path}}
    end
  end

  @doc """
  Lists all available configuration domains.
  """
  @spec list_domains() :: [atom()]
  def list_domains do
    [:client, :provider, :prediction, :evaluation, :teleprompter, :beacon, :logging, :telemetry]
  end

  @doc """
  Exports basic JSON schema for documentation.
  """
  @spec export_json_schema(atom()) :: {:ok, map()} | {:error, term()}
  def export_json_schema(domain) do
    schema =
      case domain do
        :client -> client_json_schema()
        :provider -> provider_json_schema()
        :prediction -> prediction_json_schema()
        :evaluation -> evaluation_json_schema()
        :teleprompter -> teleprompter_json_schema()
        :beacon -> beacon_json_schema()
        :logging -> logging_json_schema()
        :telemetry -> telemetry_json_schema()
        _ -> nil
      end

    if schema do
      {:ok, schema}
    else
      {:error, {:unknown_domain, domain}}
    end
  end

  ## Private validation functions

  # Schema-based field validation with fallback to legacy validation
  @spec validate_field_with_schema(module(), list(atom()), term()) :: :ok | {:error, term()}
  defp validate_field_with_schema(schema_module, field_path, value) do
    # Reject nil values explicitly (even for optional fields)
    cond do
      is_nil(value) ->
        field_name = List.last(field_path)
        error_atom = field_to_error_atom(field_name)
        {:error, {error_atom, "Value cannot be nil"}}

      elixact_supported_field?(field_path) ->
        try do
          # Create a nested map structure for the field path
          test_data = build_nested_map(field_path, value)

          case schema_module.validate(test_data) do
            {:ok, _validated} -> :ok
            {:error, errors} -> {:error, format_elixact_error(errors)}
          end
        rescue
          # Fall back to legacy validation if Elixact fails
          _ -> validate_field_legacy(field_path, value)
        end

      true ->
        # Use legacy validation for unsupported field types
        validate_field_legacy(field_path, value)
    end
  end

  # Build nested map structure from field path and value
  @spec build_nested_map(list(atom()), term()) :: map()
  defp build_nested_map([field], value), do: %{field => value}
  defp build_nested_map([field | rest], value), do: %{field => build_nested_map(rest, value)}

  # Format Elixact errors to match legacy error format
  @spec format_elixact_error([%Elixact.Error{}] | %Elixact.Error{}) :: term()
  defp format_elixact_error([error | _]), do: format_elixact_error(error)

  defp format_elixact_error(%Elixact.Error{path: [field], message: message}) do
    error_atom = field_to_error_atom(field)
    {error_atom, message}
  end

  defp format_elixact_error(%Elixact.Error{message: message}) do
    {:unknown_field, message}
  end

  defp format_elixact_error(_), do: {:unknown_field, "Unknown configuration field"}

  # Map field names to legacy error atoms
  @spec field_to_error_atom(atom()) :: atom()
  defp field_to_error_atom(:timeout), do: :invalid_timeout
  defp field_to_error_atom(:retry_attempts), do: :invalid_retry_attempts
  defp field_to_error_atom(:backoff_factor), do: :invalid_backoff_factor
  defp field_to_error_atom(:api_key), do: :invalid_api_key
  defp field_to_error_atom(:base_url), do: :invalid_base_url
  defp field_to_error_atom(:default_model), do: :invalid_model
  defp field_to_error_atom(:default_provider), do: :invalid_provider
  defp field_to_error_atom(:default_temperature), do: :invalid_temperature
  defp field_to_error_atom(:default_max_tokens), do: :invalid_max_tokens
  defp field_to_error_atom(:cache_enabled), do: :invalid_boolean
  defp field_to_error_atom(:cache_ttl), do: :invalid_cache_ttl
  defp field_to_error_atom(:batch_size), do: :invalid_batch_size
  defp field_to_error_atom(:parallel_limit), do: :invalid_parallel_limit
  defp field_to_error_atom(:bootstrap_examples), do: :invalid_bootstrap_examples
  defp field_to_error_atom(:validation_threshold), do: :invalid_validation_threshold
  defp field_to_error_atom(:level), do: :invalid_log_level
  defp field_to_error_atom(:correlation_enabled), do: :invalid_boolean
  defp field_to_error_atom(:enabled), do: :invalid_boolean
  defp field_to_error_atom(:detailed_logging), do: :invalid_boolean
  defp field_to_error_atom(:performance_tracking), do: :invalid_boolean
  defp field_to_error_atom(_), do: :unknown_field

  # Determines if a field path can be validated with current Elixact capabilities
  @spec elixact_supported_field?(list(atom())) :: boolean()
  defp elixact_supported_field?(field_path) do
    case field_path do
      # Client fields - all supported (string, integer, float)
      [:timeout] -> true
      [:retry_attempts] -> true
      [:backoff_factor] -> true
      # Provider fields - partial support
      # Union type not supported
      [:api_key] -> false
      [:base_url] -> true
      [:default_model] -> true
      # Nested maps - not supported
      [:rate_limit, _] -> false
      [:circuit_breaker, _] -> false
      # Prediction fields - partial support
      # Atom type not supported
      [:default_provider] -> false
      [:default_temperature] -> true
      [:default_max_tokens] -> true
      [:cache_enabled] -> true
      [:cache_ttl] -> true
      # Evaluation fields - supported
      [:batch_size] -> true
      [:parallel_limit] -> true
      # Teleprompter fields - supported
      [:bootstrap_examples] -> true
      [:validation_threshold] -> true
      # Logging fields - partial support
      # Atom type not supported
      [:level] -> false
      [:correlation_enabled] -> true
      # BEACON fields - not supported
      # Atom type
      [:default_instruction_model] -> false
      # Atom type
      [:default_evaluation_model] -> false
      [:max_concurrent_operations] -> true
      [:default_timeout] -> true
      # Nested map
      [:optimization, _] -> false
      # Nested map
      [:bayesian_optimization, _] -> false
      # Telemetry fields - supported
      [:enabled] -> true
      [:detailed_logging] -> true
      [:performance_tracking] -> true
      # Default to unsupported
      _ -> false
    end
  end

  # Legacy validation functions for unsupported Elixact cases
  @spec validate_field_legacy(list(atom()), term()) :: :ok | {:error, term()}
  defp validate_field_legacy(field_path, value) do
    case field_path do
      # Provider API key validation (union type)
      [:api_key] ->
        validate_api_key(value)

      # Atom type validations
      [:default_provider] ->
        validate_provider_atom(value)

      [:level] ->
        validate_log_level(value)

      [:default_instruction_model] ->
        validate_provider_atom(value)

      [:default_evaluation_model] ->
        validate_provider_atom(value)

      # Nested map validations
      [:rate_limit, :requests_per_minute] ->
        validate_positive_integer(value, :invalid_rate_limit)

      [:rate_limit, :tokens_per_minute] ->
        validate_positive_integer(value, :invalid_rate_limit)

      [:circuit_breaker, :failure_threshold] ->
        validate_positive_integer(value, :invalid_failure_threshold)

      [:circuit_breaker, :recovery_time] ->
        validate_positive_integer(value, :invalid_recovery_time)

      [:optimization, :max_trials] ->
        validate_positive_integer(value, :invalid_max_trials)

      [:optimization, :convergence_patience] ->
        validate_positive_integer(value, :invalid_convergence_patience)

      [:optimization, :improvement_threshold] ->
        validate_float_range(value, 0.0, 1.0, :invalid_improvement_threshold)

      [:bayesian_optimization, :acquisition_function] ->
        validate_acquisition_function(value)

      [:bayesian_optimization, :surrogate_model] ->
        validate_surrogate_model(value)

      [:bayesian_optimization, :exploration_exploitation_tradeoff] ->
        validate_float_range(value, 0.0, 1.0, :invalid_tradeoff)

      # Unknown field
      _ ->
        {:error, {:unknown_field, "Unknown configuration field"}}
    end
  end

  # Legacy validation helper functions
  defp validate_api_key(value) when is_binary(value), do: :ok
  defp validate_api_key({:system, env_var}) when is_binary(env_var), do: :ok

  defp validate_api_key(_),
    do: {:error, {:invalid_api_key, "Must be a string or {:system, env_var} tuple"}}

  defp validate_provider_atom(value) when value in [:gemini, :openai], do: :ok
  defp validate_provider_atom(_), do: {:error, {:invalid_provider, "Must be :gemini or :openai"}}

  defp validate_log_level(value)
       when value in [
              :emergency,
              :alert,
              :critical,
              :error,
              :warning,
              :warn,
              :notice,
              :info,
              :debug
            ],
       do: :ok

  defp validate_log_level(_), do: {:error, {:invalid_log_level, "Must be a valid log level"}}

  defp validate_positive_integer(value, _error_atom) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_integer(_, error_atom),
    do: {:error, {error_atom, "Must be a positive integer"}}

  defp validate_float_range(value, min, max, _error_atom)
       when is_float(value) and value >= min and value <= max,
       do: :ok

  defp validate_float_range(_, _, _, error_atom),
    do: {:error, {error_atom, "Must be a float between the specified range"}}

  defp validate_acquisition_function(value)
       when value in [:expected_improvement, :probability_of_improvement, :upper_confidence_bound],
       do: :ok

  defp validate_acquisition_function(_),
    do: {:error, {:invalid_acquisition_function, "Must be a valid acquisition function"}}

  defp validate_surrogate_model(value)
       when value in [:gaussian_process, :random_forest, :extra_trees],
       do: :ok

  defp validate_surrogate_model(_),
    do: {:error, {:invalid_surrogate_model, "Must be a valid surrogate model"}}

  ## JSON Schema definitions for documentation

  defp client_json_schema do
    %{
      "type" => "object",
      "properties" => %{
        "timeout" => %{"type" => "integer", "minimum" => 1},
        "retry_attempts" => %{"type" => "integer", "minimum" => 0},
        "backoff_factor" => %{"type" => "number", "minimum" => 0}
      }
    }
  end

  defp provider_json_schema do
    %{
      "type" => "object",
      "properties" => %{
        "api_key" => %{"type" => "string"},
        "base_url" => %{"type" => "string"},
        "default_model" => %{"type" => "string"},
        "timeout" => %{"type" => "integer", "minimum" => 1},
        "rate_limit" => %{
          "type" => "object",
          "properties" => %{
            "requests_per_minute" => %{"type" => "integer", "minimum" => 1},
            "tokens_per_minute" => %{"type" => "integer", "minimum" => 1}
          }
        }
      }
    }
  end

  defp prediction_json_schema do
    %{
      "type" => "object",
      "properties" => %{
        "default_provider" => %{"type" => "string", "enum" => ["gemini", "openai"]},
        "default_temperature" => %{"type" => "number", "minimum" => 0.0, "maximum" => 2.0},
        "cache_enabled" => %{"type" => "boolean"}
      }
    }
  end

  defp evaluation_json_schema do
    %{
      "type" => "object",
      "properties" => %{
        "batch_size" => %{"type" => "integer", "minimum" => 1},
        "parallel_limit" => %{"type" => "integer", "minimum" => 1}
      }
    }
  end

  defp teleprompter_json_schema do
    %{
      "type" => "object",
      "properties" => %{
        "bootstrap_examples" => %{"type" => "integer", "minimum" => 1},
        "validation_threshold" => %{"type" => "number", "minimum" => 0.0, "maximum" => 1.0}
      }
    }
  end

  defp beacon_json_schema do
    %{
      "type" => "object",
      "properties" => %{
        "default_instruction_model" => %{"type" => "string", "enum" => ["gemini", "openai"]},
        "optimization" => %{
          "type" => "object",
          "properties" => %{
            "max_trials" => %{"type" => "integer", "minimum" => 1}
          }
        }
      }
    }
  end

  defp logging_json_schema do
    %{
      "type" => "object",
      "properties" => %{
        "level" => %{"type" => "string", "enum" => ["debug", "info", "warning", "error"]},
        "correlation_enabled" => %{"type" => "boolean"}
      }
    }
  end

  defp telemetry_json_schema do
    %{
      "type" => "object",
      "properties" => %{
        "enabled" => %{"type" => "boolean"},
        "detailed_logging" => %{"type" => "boolean"},
        "performance_tracking" => %{"type" => "boolean"}
      }
    }
  end
end
