defmodule DSPEx.Config.ElixactSchemas do
  @moduledoc """
  Elixact schema definitions for DSPEx configuration validation.

  This module provides schema-based validation for DSPEx configuration
  with enhanced error reporting and path-based validation mapping.
  """

  # Configuration constants from validator
  @valid_log_levels [
    :emergency, :alert, :critical, :error, :warning, :warn, :notice, :info, :debug
  ]
  @valid_providers [:gemini, :openai]
  @valid_acquisition_functions [:expected_improvement, :probability_of_improvement, :upper_confidence_bound]
  @valid_surrogate_models [:gaussian_process, :random_forest, :extra_trees]

  @doc """
  Maps configuration paths to their corresponding validation function.
  """
  @spec path_to_schema(list(atom())) :: {:ok, atom(), list(atom())} | {:error, :unknown_path}
  def path_to_schema(path)

  # Client configuration mappings
  def path_to_schema([:dspex, :client, field]) when field in [:timeout, :retry_attempts, :backoff_factor] do
    {:ok, :client, [field]}
  end

  # Evaluation configuration mappings  
  def path_to_schema([:dspex, :evaluation, field]) when field in [:batch_size, :parallel_limit] do
    {:ok, :evaluation, [field]}
  end

  # Teleprompter configuration mappings
  def path_to_schema([:dspex, :teleprompter, field]) when field in [:bootstrap_examples, :validation_threshold] do
    {:ok, :teleprompter, [field]}
  end

  # Logging configuration mappings
  def path_to_schema([:dspex, :logging, field]) when field in [:level, :correlation_enabled] do
    {:ok, :logging, [field]}
  end

  # Provider configuration mappings (with wildcard support)
  def path_to_schema([:dspex, :providers, _provider, field]) 
      when field in [:api_key, :base_url, :default_model, :timeout] do
    {:ok, :provider, [field]}
  end

  def path_to_schema([:dspex, :providers, _provider, :rate_limit, field])
      when field in [:requests_per_minute, :tokens_per_minute] do
    {:ok, :provider, [:rate_limit, field]}
  end

  def path_to_schema([:dspex, :providers, _provider, :circuit_breaker, field])
      when field in [:failure_threshold, :recovery_time] do
    {:ok, :provider, [:circuit_breaker, field]}
  end

  # Prediction configuration mappings
  def path_to_schema([:dspex, :prediction, field]) 
      when field in [:default_provider, :default_temperature, :default_max_tokens, :cache_enabled, :cache_ttl] do
    {:ok, :prediction, [field]}
  end

  # BEACON teleprompter configuration mappings
  def path_to_schema([:dspex, :teleprompters, :beacon, field])
      when field in [:default_instruction_model, :default_evaluation_model, :max_concurrent_operations, :default_timeout] do
    {:ok, :beacon, [field]}
  end

  def path_to_schema([:dspex, :teleprompters, :beacon, :optimization, field])
      when field in [:max_trials, :convergence_patience, :improvement_threshold] do
    {:ok, :beacon, [:optimization, field]}
  end

  def path_to_schema([:dspex, :teleprompters, :beacon, :bayesian_optimization, field])
      when field in [:acquisition_function, :surrogate_model, :exploration_exploitation_tradeoff] do
    {:ok, :beacon, [:bayesian_optimization, field]}
  end

  # Telemetry configuration mappings
  def path_to_schema([:dspex, :telemetry, field])
      when field in [:enabled, :detailed_logging, :performance_tracking] do
    {:ok, :telemetry, [field]}
  end

  # Unknown path
  def path_to_schema(_path), do: {:error, :unknown_path}

  @doc """
  Validates a configuration value using schema-based validation.
  """
  @spec validate_config_value(list(atom()), term()) :: :ok | {:error, term()}
  def validate_config_value(path, value) do
    case path_to_schema(path) do
      {:ok, domain, field_path} ->
        validate_domain_field(domain, field_path, value)
      
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
    schema = case domain do
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

  # Domain-specific validation
  @spec validate_domain_field(atom(), list(atom()), term()) :: :ok | {:error, term()}
  defp validate_domain_field(:client, [:timeout], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:client, [:timeout], _), do: {:error, {:invalid_timeout, "Must be a positive integer"}}

  defp validate_domain_field(:client, [:retry_attempts], value) when is_integer(value) and value >= 0, do: :ok
  defp validate_domain_field(:client, [:retry_attempts], _), do: {:error, {:invalid_retry_attempts, "Must be a non-negative integer"}}

  defp validate_domain_field(:client, [:backoff_factor], value) when is_number(value) and value > 0, do: :ok
  defp validate_domain_field(:client, [:backoff_factor], _), do: {:error, {:invalid_backoff_factor, "Must be a positive number"}}

  # Provider validations
  defp validate_domain_field(:provider, [:api_key], value) when is_binary(value), do: :ok
  defp validate_domain_field(:provider, [:api_key], {:system, env_var}) when is_binary(env_var), do: :ok
  defp validate_domain_field(:provider, [:api_key], _), do: {:error, {:invalid_api_key, "Must be a string or {:system, env_var} tuple"}}

  defp validate_domain_field(:provider, [:base_url], value) when is_binary(value), do: :ok
  defp validate_domain_field(:provider, [:base_url], _), do: {:error, {:invalid_base_url, "Must be a string"}}

  defp validate_domain_field(:provider, [:default_model], value) when is_binary(value), do: :ok
  defp validate_domain_field(:provider, [:default_model], _), do: {:error, {:invalid_model, "Must be a string"}}

  defp validate_domain_field(:provider, [:timeout], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:provider, [:timeout], _), do: {:error, {:invalid_timeout, "Must be a positive integer"}}

  defp validate_domain_field(:provider, [:rate_limit, :requests_per_minute], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:provider, [:rate_limit, :requests_per_minute], _), do: {:error, {:invalid_rate_limit, "Must be a positive integer"}}

  defp validate_domain_field(:provider, [:rate_limit, :tokens_per_minute], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:provider, [:rate_limit, :tokens_per_minute], _), do: {:error, {:invalid_rate_limit, "Must be a positive integer"}}

  defp validate_domain_field(:provider, [:circuit_breaker, :failure_threshold], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:provider, [:circuit_breaker, :failure_threshold], _), do: {:error, {:invalid_failure_threshold, "Must be a positive integer"}}

  defp validate_domain_field(:provider, [:circuit_breaker, :recovery_time], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:provider, [:circuit_breaker, :recovery_time], _), do: {:error, {:invalid_recovery_time, "Must be a positive integer"}}

  # Prediction validations
  defp validate_domain_field(:prediction, [:default_provider], value) when value in @valid_providers, do: :ok
  defp validate_domain_field(:prediction, [:default_provider], _), do: {:error, {:invalid_provider, "Must be :gemini or :openai"}}

  defp validate_domain_field(:prediction, [:default_temperature], value) when is_float(value) and value >= 0.0 and value <= 2.0, do: :ok
  defp validate_domain_field(:prediction, [:default_temperature], _), do: {:error, {:invalid_temperature, "Must be a float between 0.0 and 2.0"}}

  defp validate_domain_field(:prediction, [:default_max_tokens], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:prediction, [:default_max_tokens], _), do: {:error, {:invalid_max_tokens, "Must be a positive integer"}}

  defp validate_domain_field(:prediction, [:cache_enabled], value) when is_boolean(value), do: :ok
  defp validate_domain_field(:prediction, [:cache_enabled], _), do: {:error, {:invalid_boolean, "Must be true or false"}}

  defp validate_domain_field(:prediction, [:cache_ttl], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:prediction, [:cache_ttl], _), do: {:error, {:invalid_cache_ttl, "Must be a positive integer"}}

  # Evaluation validations
  defp validate_domain_field(:evaluation, [:batch_size], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:evaluation, [:batch_size], _), do: {:error, {:invalid_batch_size, "Must be a positive integer"}}

  defp validate_domain_field(:evaluation, [:parallel_limit], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:evaluation, [:parallel_limit], _), do: {:error, {:invalid_parallel_limit, "Must be a positive integer"}}

  # Teleprompter validations
  defp validate_domain_field(:teleprompter, [:bootstrap_examples], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:teleprompter, [:bootstrap_examples], _), do: {:error, {:invalid_bootstrap_examples, "Must be a positive integer"}}

  defp validate_domain_field(:teleprompter, [:validation_threshold], value) when is_float(value) and value >= 0.0 and value <= 1.0, do: :ok
  defp validate_domain_field(:teleprompter, [:validation_threshold], _), do: {:error, {:invalid_validation_threshold, "Must be a float between 0.0 and 1.0"}}

  # BEACON validations
  defp validate_domain_field(:beacon, [:default_instruction_model], value) when value in @valid_providers, do: :ok
  defp validate_domain_field(:beacon, [:default_instruction_model], _), do: {:error, {:invalid_provider, "Must be :gemini or :openai"}}

  defp validate_domain_field(:beacon, [:default_evaluation_model], value) when value in @valid_providers, do: :ok
  defp validate_domain_field(:beacon, [:default_evaluation_model], _), do: {:error, {:invalid_provider, "Must be :gemini or :openai"}}

  defp validate_domain_field(:beacon, [:max_concurrent_operations], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:beacon, [:max_concurrent_operations], _), do: {:error, {:invalid_concurrent_operations, "Must be a positive integer"}}

  defp validate_domain_field(:beacon, [:default_timeout], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:beacon, [:default_timeout], _), do: {:error, {:invalid_timeout, "Must be a positive integer"}}

  defp validate_domain_field(:beacon, [:optimization, :max_trials], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:beacon, [:optimization, :max_trials], _), do: {:error, {:invalid_max_trials, "Must be a positive integer"}}

  defp validate_domain_field(:beacon, [:optimization, :convergence_patience], value) when is_integer(value) and value > 0, do: :ok
  defp validate_domain_field(:beacon, [:optimization, :convergence_patience], _), do: {:error, {:invalid_convergence_patience, "Must be a positive integer"}}

  defp validate_domain_field(:beacon, [:optimization, :improvement_threshold], value) when is_float(value) and value >= 0.0 and value <= 1.0, do: :ok
  defp validate_domain_field(:beacon, [:optimization, :improvement_threshold], _), do: {:error, {:invalid_improvement_threshold, "Must be a float between 0.0 and 1.0"}}

  defp validate_domain_field(:beacon, [:bayesian_optimization, :acquisition_function], value) when value in @valid_acquisition_functions, do: :ok
  defp validate_domain_field(:beacon, [:bayesian_optimization, :acquisition_function], _), do: {:error, {:invalid_acquisition_function, "Must be a valid acquisition function"}}

  defp validate_domain_field(:beacon, [:bayesian_optimization, :surrogate_model], value) when value in @valid_surrogate_models, do: :ok
  defp validate_domain_field(:beacon, [:bayesian_optimization, :surrogate_model], _), do: {:error, {:invalid_surrogate_model, "Must be a valid surrogate model"}}

  defp validate_domain_field(:beacon, [:bayesian_optimization, :exploration_exploitation_tradeoff], value) when is_float(value) and value >= 0.0 and value <= 1.0, do: :ok
  defp validate_domain_field(:beacon, [:bayesian_optimization, :exploration_exploitation_tradeoff], _), do: {:error, {:invalid_tradeoff, "Must be a float between 0.0 and 1.0"}}

  # Logging validations
  defp validate_domain_field(:logging, [:level], value) when value in @valid_log_levels, do: :ok
  defp validate_domain_field(:logging, [:level], _), do: {:error, {:invalid_log_level, "Must be a valid log level"}}

  defp validate_domain_field(:logging, [:correlation_enabled], value) when is_boolean(value), do: :ok
  defp validate_domain_field(:logging, [:correlation_enabled], _), do: {:error, {:invalid_boolean, "Must be true or false"}}

  # Telemetry validations
  defp validate_domain_field(:telemetry, [:enabled], value) when is_boolean(value), do: :ok
  defp validate_domain_field(:telemetry, [:enabled], _), do: {:error, {:invalid_boolean, "Must be true or false"}}

  defp validate_domain_field(:telemetry, [:detailed_logging], value) when is_boolean(value), do: :ok
  defp validate_domain_field(:telemetry, [:detailed_logging], _), do: {:error, {:invalid_boolean, "Must be true or false"}}

  defp validate_domain_field(:telemetry, [:performance_tracking], value) when is_boolean(value), do: :ok
  defp validate_domain_field(:telemetry, [:performance_tracking], _), do: {:error, {:invalid_boolean, "Must be true or false"}}

  # Unknown field
  defp validate_domain_field(_domain, _field_path, _value), do: {:error, {:unknown_field, "Unknown configuration field"}}

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