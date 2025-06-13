defmodule DSPEx.Config.Validator do
  @moduledoc """
  Validation rules for DSPEx configuration.

  Ensures configuration paths and values are valid before storing them.
  This module provides validation for all supported DSPEx configuration
  paths and their corresponding value types.

  ## Supported Configuration Paths

  - Client configuration: `[:dspex, :client, :timeout]`, etc.
  - Evaluation configuration: `[:dspex, :evaluation, :batch_size]`, etc.
  - Provider configuration: `[:dspex, :providers, :gemini, ...]`, etc.
  - And many more...
  """

  # Valid configuration paths - comprehensive list based on ConfigManager analysis
  @valid_paths [
    # Client configuration
    [:dspex, :client, :timeout],
    [:dspex, :client, :retry_attempts],
    [:dspex, :client, :backoff_factor],

    # Evaluation configuration
    [:dspex, :evaluation, :batch_size],
    [:dspex, :evaluation, :parallel_limit],

    # Teleprompter configuration
    [:dspex, :teleprompter, :bootstrap_examples],
    [:dspex, :teleprompter, :validation_threshold],

    # Logging configuration
    [:dspex, :logging, :level],
    [:dspex, :logging, :correlation_enabled],

    # Provider configurations - Gemini
    [:dspex, :providers, :gemini, :api_key],
    [:dspex, :providers, :gemini, :base_url],
    [:dspex, :providers, :gemini, :default_model],
    [:dspex, :providers, :gemini, :timeout],
    [:dspex, :providers, :gemini, :rate_limit, :requests_per_minute],
    [:dspex, :providers, :gemini, :rate_limit, :tokens_per_minute],
    [:dspex, :providers, :gemini, :circuit_breaker, :failure_threshold],
    [:dspex, :providers, :gemini, :circuit_breaker, :recovery_time],

    # Provider configurations - OpenAI
    [:dspex, :providers, :openai, :api_key],
    [:dspex, :providers, :openai, :base_url],
    [:dspex, :providers, :openai, :default_model],
    [:dspex, :providers, :openai, :timeout],
    [:dspex, :providers, :openai, :rate_limit, :requests_per_minute],
    [:dspex, :providers, :openai, :rate_limit, :tokens_per_minute],
    [:dspex, :providers, :openai, :circuit_breaker, :failure_threshold],
    [:dspex, :providers, :openai, :circuit_breaker, :recovery_time],

    # Prediction configuration
    [:dspex, :prediction, :default_provider],
    [:dspex, :prediction, :default_temperature],
    [:dspex, :prediction, :default_max_tokens],
    [:dspex, :prediction, :cache_enabled],
    [:dspex, :prediction, :cache_ttl],

    # BEACON teleprompter configuration
    [:dspex, :teleprompters, :beacon, :default_instruction_model],
    [:dspex, :teleprompters, :beacon, :default_evaluation_model],
    [:dspex, :teleprompters, :beacon, :max_concurrent_operations],
    [:dspex, :teleprompters, :beacon, :default_timeout],
    [:dspex, :teleprompters, :beacon, :optimization, :max_trials],
    [:dspex, :teleprompters, :beacon, :optimization, :convergence_patience],
    [:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold],
    [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
    [:dspex, :teleprompters, :beacon, :bayesian_optimization, :surrogate_model],
    [:dspex, :teleprompters, :beacon, :bayesian_optimization, :exploration_exploitation_tradeoff],

    # Telemetry configuration
    [:dspex, :telemetry, :enabled],
    [:dspex, :telemetry, :detailed_logging],
    [:dspex, :telemetry, :performance_tracking]
  ]

  # Valid log levels
  @valid_log_levels [
    :emergency,
    :alert,
    :critical,
    :error,
    :warning,
    :warn,
    :notice,
    :info,
    :debug
  ]

  # Valid providers
  @valid_providers [:gemini, :openai]

  # Valid acquisition functions for Bayesian optimization
  @valid_acquisition_functions [
    :expected_improvement,
    :probability_of_improvement,
    :upper_confidence_bound
  ]

  # Valid surrogate models
  @valid_surrogate_models [:gaussian_process, :random_forest, :extra_trees]

  @doc """
  Validate that a configuration path is supported.

  Returns `:ok` if the path is valid, `{:error, :invalid_path}` otherwise.

  ## Examples

      iex> DSPEx.Config.Validator.validate_path([:dspex, :client, :timeout])
      :ok

      iex> DSPEx.Config.Validator.validate_path([:invalid, :path])
      {:error, :invalid_path}
  """
  @spec validate_path(list(atom())) :: :ok | {:error, :invalid_path}
  def validate_path(path) when is_list(path) do
    if path in @valid_paths or path_prefix_valid?(path) do
      :ok
    else
      {:error, :invalid_path}
    end
  end

  def validate_path(_), do: {:error, :invalid_path}

  @doc """
  Validate that a configuration value is appropriate for the given path.

  Returns `:ok` if the value is valid, `{:error, reason}` otherwise.

  ## Examples

      iex> DSPEx.Config.Validator.validate_value([:dspex, :client, :timeout], 30000)
      :ok

      iex> DSPEx.Config.Validator.validate_value([:dspex, :client, :timeout], "invalid")
      {:error, :invalid_timeout}
  """
  @spec validate_value(list(atom()), term()) :: :ok | {:error, term()}
  def validate_value(path, value)

  # Timeout validations (must be positive integer)
  def validate_value([:dspex, :client, :timeout], value) when is_integer(value) and value > 0,
    do: :ok

  def validate_value([:dspex, :client, :timeout], _), do: {:error, :invalid_timeout}

  def validate_value([:dspex, :providers, _, :timeout], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :providers, _, :timeout], _), do: {:error, :invalid_timeout}

  def validate_value([:dspex, :teleprompters, :beacon, :default_timeout], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :teleprompters, :beacon, :default_timeout], _),
    do: {:error, :invalid_timeout}

  # Retry attempts (must be non-negative integer)
  def validate_value([:dspex, :client, :retry_attempts], value)
      when is_integer(value) and value >= 0,
      do: :ok

  def validate_value([:dspex, :client, :retry_attempts], _), do: {:error, :invalid_retry_attempts}

  # Backoff factor (must be positive number)
  def validate_value([:dspex, :client, :backoff_factor], value)
      when is_number(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :client, :backoff_factor], _), do: {:error, :invalid_backoff_factor}

  # Batch size and parallel limits (must be positive integer)
  def validate_value([:dspex, :evaluation, :batch_size], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :evaluation, :batch_size], _), do: {:error, :invalid_batch_size}

  def validate_value([:dspex, :evaluation, :parallel_limit], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :evaluation, :parallel_limit], _),
    do: {:error, :invalid_parallel_limit}

  def validate_value([:dspex, :teleprompters, :beacon, :max_concurrent_operations], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :teleprompters, :beacon, :max_concurrent_operations], _),
    do: {:error, :invalid_concurrent_operations}

  # Bootstrap examples (must be positive integer)
  def validate_value([:dspex, :teleprompter, :bootstrap_examples], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :teleprompter, :bootstrap_examples], _),
    do: {:error, :invalid_bootstrap_examples}

  # Validation threshold (must be float between 0 and 1)
  def validate_value([:dspex, :teleprompter, :validation_threshold], value)
      when is_float(value) and value >= 0.0 and value <= 1.0,
      do: :ok

  def validate_value([:dspex, :teleprompter, :validation_threshold], _),
    do: {:error, :invalid_validation_threshold}

  # Temperature (must be float between 0 and 2)
  def validate_value([:dspex, :prediction, :default_temperature], value)
      when is_float(value) and value >= 0.0 and value <= 2.0,
      do: :ok

  def validate_value([:dspex, :prediction, :default_temperature], _),
    do: {:error, :invalid_temperature}

  # Max tokens (must be positive integer)
  def validate_value([:dspex, :prediction, :default_max_tokens], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :prediction, :default_max_tokens], _),
    do: {:error, :invalid_max_tokens}

  # TTL values (must be positive integer)
  def validate_value([:dspex, :prediction, :cache_ttl], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :prediction, :cache_ttl], _), do: {:error, :invalid_cache_ttl}

  def validate_value([:dspex, :providers, _, :circuit_breaker, :recovery_time], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :providers, _, :circuit_breaker, :recovery_time], _),
    do: {:error, :invalid_recovery_time}

  # Logging level validation
  def validate_value([:dspex, :logging, :level], value) when value in @valid_log_levels, do: :ok
  def validate_value([:dspex, :logging, :level], _), do: {:error, :invalid_log_level}

  # Boolean validations
  def validate_value([:dspex, :logging, :correlation_enabled], value) when is_boolean(value),
    do: :ok

  def validate_value([:dspex, :logging, :correlation_enabled], _), do: {:error, :invalid_boolean}

  def validate_value([:dspex, :prediction, :cache_enabled], value) when is_boolean(value), do: :ok
  def validate_value([:dspex, :prediction, :cache_enabled], _), do: {:error, :invalid_boolean}

  def validate_value([:dspex, :telemetry, :enabled], value) when is_boolean(value), do: :ok
  def validate_value([:dspex, :telemetry, :enabled], _), do: {:error, :invalid_boolean}

  def validate_value([:dspex, :telemetry, :detailed_logging], value) when is_boolean(value),
    do: :ok

  def validate_value([:dspex, :telemetry, :detailed_logging], _), do: {:error, :invalid_boolean}

  def validate_value([:dspex, :telemetry, :performance_tracking], value) when is_boolean(value),
    do: :ok

  def validate_value([:dspex, :telemetry, :performance_tracking], _),
    do: {:error, :invalid_boolean}

  # Provider validation
  def validate_value([:dspex, :prediction, :default_provider], value)
      when value in @valid_providers,
      do: :ok

  def validate_value([:dspex, :prediction, :default_provider], _), do: {:error, :invalid_provider}

  def validate_value([:dspex, :teleprompters, :beacon, :default_instruction_model], value)
      when value in @valid_providers,
      do: :ok

  def validate_value([:dspex, :teleprompters, :beacon, :default_instruction_model], _),
    do: {:error, :invalid_provider}

  def validate_value([:dspex, :teleprompters, :beacon, :default_evaluation_model], value)
      when value in @valid_providers,
      do: :ok

  def validate_value([:dspex, :teleprompters, :beacon, :default_evaluation_model], _),
    do: {:error, :invalid_provider}

  # String validations (API keys, URLs, models)
  def validate_value([:dspex, :providers, _, :api_key], {:system, env_var})
      when is_binary(env_var),
      do: :ok

  def validate_value([:dspex, :providers, _, :api_key], value) when is_binary(value), do: :ok
  def validate_value([:dspex, :providers, _, :api_key], _), do: {:error, :invalid_api_key}

  def validate_value([:dspex, :providers, _, :base_url], value) when is_binary(value), do: :ok
  def validate_value([:dspex, :providers, _, :base_url], _), do: {:error, :invalid_base_url}

  def validate_value([:dspex, :providers, _, :default_model], value) when is_binary(value),
    do: :ok

  def validate_value([:dspex, :providers, _, :default_model], _), do: {:error, :invalid_model}

  # Rate limit validations (must be positive integers)
  def validate_value([:dspex, :providers, _, :rate_limit, :requests_per_minute], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :providers, _, :rate_limit, :requests_per_minute], _),
    do: {:error, :invalid_rate_limit}

  def validate_value([:dspex, :providers, _, :rate_limit, :tokens_per_minute], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :providers, _, :rate_limit, :tokens_per_minute], _),
    do: {:error, :invalid_rate_limit}

  # Circuit breaker validations
  def validate_value([:dspex, :providers, _, :circuit_breaker, :failure_threshold], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :providers, _, :circuit_breaker, :failure_threshold], _),
    do: {:error, :invalid_failure_threshold}

  # BEACON optimization validations
  def validate_value([:dspex, :teleprompters, :beacon, :optimization, :max_trials], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :teleprompters, :beacon, :optimization, :max_trials], _),
    do: {:error, :invalid_max_trials}

  def validate_value(
        [:dspex, :teleprompters, :beacon, :optimization, :convergence_patience],
        value
      )
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value([:dspex, :teleprompters, :beacon, :optimization, :convergence_patience], _),
    do: {:error, :invalid_convergence_patience}

  def validate_value(
        [:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold],
        value
      )
      when is_float(value) and value >= 0.0 and value <= 1.0,
      do: :ok

  def validate_value([:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold], _),
    do: {:error, :invalid_improvement_threshold}

  # Bayesian optimization validations
  def validate_value(
        [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
        value
      )
      when value in @valid_acquisition_functions,
      do: :ok

  def validate_value(
        [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
        _
      ),
      do: {:error, :invalid_acquisition_function}

  def validate_value(
        [:dspex, :teleprompters, :beacon, :bayesian_optimization, :surrogate_model],
        value
      )
      when value in @valid_surrogate_models,
      do: :ok

  def validate_value(
        [:dspex, :teleprompters, :beacon, :bayesian_optimization, :surrogate_model],
        _
      ),
      do: {:error, :invalid_surrogate_model}

  def validate_value(
        [
          :dspex,
          :teleprompters,
          :beacon,
          :bayesian_optimization,
          :exploration_exploitation_tradeoff
        ],
        value
      )
      when is_float(value) and value >= 0.0 and value <= 1.0,
      do: :ok

  def validate_value(
        [
          :dspex,
          :teleprompters,
          :beacon,
          :bayesian_optimization,
          :exploration_exploitation_tradeoff
        ],
        _
      ),
      do: {:error, :invalid_tradeoff}

  # Default case - unknown path
  def validate_value(path, _value) do
    {:error, {:unknown_path, path}}
  end

  ## Private Functions

  # Check if a path has a valid prefix (for nested configurations)
  @spec path_prefix_valid?(list(atom())) :: boolean()
  defp path_prefix_valid?(path) do
    # Allow any path that starts with [:dspex] for extensibility
    # This enables adding new configuration paths without updating the validator
    case path do
      [:dspex | _] -> true
      _ -> false
    end
  end
end
