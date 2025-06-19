defmodule DSPEx.Config.SinterSchemasTest do
  use ExUnit.Case, async: true

  alias DSPEx.Config.SinterSchemas

  @moduletag :phase_1
  @moduletag :sinter_test

  describe "path to schema mapping" do
    test "maps client configuration paths correctly" do
      assert {:ok, schema, [:timeout]} = SinterSchemas.path_to_schema([:dspex, :client, :timeout])
      assert is_map(schema)

      assert {:ok, schema, [:retry_attempts]} =
               SinterSchemas.path_to_schema([:dspex, :client, :retry_attempts])

      assert is_map(schema)

      assert {:ok, schema, [:backoff_factor]} =
               SinterSchemas.path_to_schema([:dspex, :client, :backoff_factor])

      assert is_map(schema)
    end

    test "maps provider configuration paths correctly" do
      assert {:ok, schema, [:api_key]} =
               SinterSchemas.path_to_schema([:dspex, :providers, :openai, :api_key])

      assert is_map(schema)

      assert {:ok, schema, [:requests_per_minute]} =
               SinterSchemas.path_to_schema([
                 :dspex,
                 :providers,
                 :openai,
                 :rate_limit,
                 :requests_per_minute
               ])

      assert is_map(schema)

      assert {:ok, schema, [:failure_threshold]} =
               SinterSchemas.path_to_schema([
                 :dspex,
                 :providers,
                 :anthropic,
                 :circuit_breaker,
                 :failure_threshold
               ])

      assert is_map(schema)
    end

    test "maps teleprompter configuration paths correctly" do
      assert {:ok, schema, [:bootstrap_examples]} =
               SinterSchemas.path_to_schema([:dspex, :teleprompter, :bootstrap_examples])

      assert is_map(schema)

      assert {:ok, schema, [:validation_threshold]} =
               SinterSchemas.path_to_schema([:dspex, :teleprompter, :validation_threshold])

      assert is_map(schema)
    end

    test "maps BEACON configuration paths correctly" do
      assert {:ok, schema, [:default_instruction_model]} =
               SinterSchemas.path_to_schema([
                 :dspex,
                 :teleprompters,
                 :beacon,
                 :default_instruction_model
               ])

      assert is_map(schema)

      assert {:ok, schema, [:max_trials]} =
               SinterSchemas.path_to_schema([
                 :dspex,
                 :teleprompters,
                 :beacon,
                 :optimization,
                 :max_trials
               ])

      assert is_map(schema)

      assert {:ok, schema, [:acquisition_function]} =
               SinterSchemas.path_to_schema([
                 :dspex,
                 :teleprompters,
                 :beacon,
                 :bayesian_optimization,
                 :acquisition_function
               ])

      assert is_map(schema)
    end

    test "returns error for unknown paths" do
      assert {:error, :unknown_path} = SinterSchemas.path_to_schema([:unknown, :path])
      assert {:error, :unknown_path} = SinterSchemas.path_to_schema([:dspex, :unknown, :field])
    end
  end

  describe "configuration value validation" do
    test "validates client configuration values" do
      # Valid timeout
      assert :ok = SinterSchemas.validate_config_value([:dspex, :client, :timeout], 5000)

      # Invalid timeout (too low)
      assert {:error, {:invalid_timeout, _}} =
               SinterSchemas.validate_config_value([:dspex, :client, :timeout], 500)

      # Invalid timeout (too high)
      assert {:error, {:invalid_timeout, _}} =
               SinterSchemas.validate_config_value([:dspex, :client, :timeout], 500_000)

      # Valid retry attempts
      assert :ok = SinterSchemas.validate_config_value([:dspex, :client, :retry_attempts], 3)

      # Invalid retry attempts (negative)
      assert {:error, {:invalid_retry_attempts, _}} =
               SinterSchemas.validate_config_value([:dspex, :client, :retry_attempts], -1)

      # Valid backoff factor
      assert :ok = SinterSchemas.validate_config_value([:dspex, :client, :backoff_factor], 2.0)

      # Invalid backoff factor (too low)
      assert {:error, {:invalid_backoff_factor, _}} =
               SinterSchemas.validate_config_value([:dspex, :client, :backoff_factor], 0.5)
    end

    test "validates provider configuration values" do
      # Valid API key (string)
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :api_key],
                 "sk-..."
               )

      # Valid API key (tuple)
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :api_key],
                 {:system, "OPENAI_API_KEY"}
               )

      # Valid base URL
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :base_url],
                 "https://api.openai.com"
               )

      # Invalid base URL (no protocol)
      assert {:error, {:invalid_base_url, _}} =
               SinterSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :base_url],
                 "api.openai.com"
               )

      # Valid model
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :default_model],
                 "gpt-4"
               )

      # Invalid model (empty)
      assert {:error, {:invalid_model, _}} =
               SinterSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :default_model],
                 ""
               )

      # Valid rate limit
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :rate_limit, :requests_per_minute],
                 100
               )

      # Invalid rate limit (too high)
      assert {:error, {:invalid_rate_limit, _}} =
               SinterSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :rate_limit, :requests_per_minute],
                 50_000
               )
    end

    test "validates prediction configuration values" do
      # Valid provider
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :prediction, :default_provider],
                 "openai"
               )

      # Invalid provider (not in choices)
      assert {:error, {:invalid_provider, _}} =
               SinterSchemas.validate_config_value(
                 [:dspex, :prediction, :default_provider],
                 "unknown"
               )

      # Valid temperature
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :prediction, :default_temperature],
                 0.7
               )

      # Invalid temperature (too high)
      assert {:error, {:invalid_temperature, _}} =
               SinterSchemas.validate_config_value(
                 [:dspex, :prediction, :default_temperature],
                 3.0
               )

      # Valid max tokens
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :prediction, :default_max_tokens],
                 1000
               )

      # Invalid max tokens (too high)
      assert {:error, {:invalid_max_tokens, _}} =
               SinterSchemas.validate_config_value(
                 [:dspex, :prediction, :default_max_tokens],
                 100_000
               )

      # Valid cache settings
      assert :ok =
               SinterSchemas.validate_config_value([:dspex, :prediction, :cache_enabled], true)

      assert :ok = SinterSchemas.validate_config_value([:dspex, :prediction, :cache_ttl], 3600)
    end

    test "validates evaluation configuration values" do
      # Valid batch size
      assert :ok = SinterSchemas.validate_config_value([:dspex, :evaluation, :batch_size], 50)

      # Invalid batch size (too large)
      assert {:error, {:invalid_batch_size, _}} =
               SinterSchemas.validate_config_value([:dspex, :evaluation, :batch_size], 2000)

      # Valid parallel limit
      assert :ok = SinterSchemas.validate_config_value([:dspex, :evaluation, :parallel_limit], 10)

      # Invalid parallel limit (too large)
      assert {:error, {:invalid_parallel_limit, _}} =
               SinterSchemas.validate_config_value([:dspex, :evaluation, :parallel_limit], 200)
    end

    test "validates teleprompter configuration values" do
      # Valid bootstrap examples
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :teleprompter, :bootstrap_examples],
                 20
               )

      # Invalid bootstrap examples (too many)
      assert {:error, {:invalid_bootstrap_examples, _}} =
               SinterSchemas.validate_config_value(
                 [:dspex, :teleprompter, :bootstrap_examples],
                 200
               )

      # Valid validation threshold
      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :teleprompter, :validation_threshold],
                 0.8
               )

      # Invalid validation threshold (too high)
      assert {:error, {:invalid_validation_threshold, _}} =
               SinterSchemas.validate_config_value(
                 [:dspex, :teleprompter, :validation_threshold],
                 1.5
               )
    end

    test "validates logging configuration values" do
      # Valid log level
      assert :ok = SinterSchemas.validate_config_value([:dspex, :logging, :level], "info")

      # Invalid log level
      assert {:error, {:invalid_log_level, _}} =
               SinterSchemas.validate_config_value([:dspex, :logging, :level], "trace")

      # Valid correlation setting
      assert :ok =
               SinterSchemas.validate_config_value([:dspex, :logging, :correlation_enabled], true)
    end

    test "validates telemetry configuration values" do
      # Valid telemetry settings
      assert :ok = SinterSchemas.validate_config_value([:dspex, :telemetry, :enabled], true)

      assert :ok =
               SinterSchemas.validate_config_value([:dspex, :telemetry, :detailed_logging], false)

      assert :ok =
               SinterSchemas.validate_config_value(
                 [:dspex, :telemetry, :performance_tracking],
                 true
               )
    end

    test "rejects nil values" do
      # All configuration values should reject nil
      assert {:error, {:invalid_timeout, "Value cannot be nil"}} =
               SinterSchemas.validate_config_value([:dspex, :client, :timeout], nil)

      assert {:error, {:invalid_provider, "Value cannot be nil"}} =
               SinterSchemas.validate_config_value([:dspex, :prediction, :default_provider], nil)
    end

    test "handles unknown paths" do
      assert {:error, {:unknown_path, [:unknown, :path]}} =
               SinterSchemas.validate_config_value([:unknown, :path], "value")
    end
  end

  describe "domain listing" do
    test "lists all available domains" do
      domains = SinterSchemas.list_domains()

      expected_domains = [
        :client,
        :provider,
        :prediction,
        :evaluation,
        :teleprompter,
        :beacon,
        :logging,
        :telemetry
      ]

      for domain <- expected_domains do
        assert domain in domains
      end
    end
  end

  describe "JSON schema export" do
    test "exports client schema as JSON" do
      {:ok, json_schema} = SinterSchemas.export_json_schema(:client)

      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "properties")

      properties = json_schema["properties"]
      assert Map.has_key?(properties, "timeout")
      assert Map.has_key?(properties, "retry_attempts")
      assert Map.has_key?(properties, "backoff_factor")
    end

    test "exports provider schema as JSON" do
      {:ok, json_schema} = SinterSchemas.export_json_schema(:provider)

      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "properties")

      properties = json_schema["properties"]
      assert Map.has_key?(properties, "api_key")
      assert Map.has_key?(properties, "base_url")
      assert Map.has_key?(properties, "rate_limit")
      assert Map.has_key?(properties, "circuit_breaker")
    end

    test "exports prediction schema as JSON" do
      {:ok, json_schema} = SinterSchemas.export_json_schema(:prediction)

      assert json_schema["type"] == "object"
      properties = json_schema["properties"]
      assert Map.has_key?(properties, "default_provider")
      assert Map.has_key?(properties, "default_temperature")
    end

    test "exports BEACON schema as JSON" do
      {:ok, json_schema} = SinterSchemas.export_json_schema(:beacon)

      assert json_schema["type"] == "object"
      properties = json_schema["properties"]
      assert Map.has_key?(properties, "optimization")
      assert Map.has_key?(properties, "bayesian_optimization")
    end

    test "handles unknown domains" do
      assert {:error, {:unknown_domain, :unknown}} = SinterSchemas.export_json_schema(:unknown)
    end
  end

  describe "schema validation accuracy" do
    test "validates complex nested structures" do
      # Test rate_limit nested validation
      path = [:dspex, :providers, :openai, :rate_limit, :requests_per_minute]

      assert :ok = SinterSchemas.validate_config_value(path, 100)
      assert {:error, {:invalid_rate_limit, _}} = SinterSchemas.validate_config_value(path, 0)

      assert {:error, {:invalid_rate_limit, _}} =
               SinterSchemas.validate_config_value(path, 50_000)
    end

    test "validates BEACON optimization settings" do
      # Test nested optimization structure
      path = [:dspex, :teleprompters, :beacon, :optimization, :max_trials]

      assert :ok = SinterSchemas.validate_config_value(path, 100)
      assert {:error, {_, _}} = SinterSchemas.validate_config_value(path, 0)
      assert {:error, {_, _}} = SinterSchemas.validate_config_value(path, 2000)
    end

    test "validates BEACON bayesian optimization settings" do
      # Test acquisition function choices
      path = [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function]

      assert :ok = SinterSchemas.validate_config_value(path, "ei")
      assert :ok = SinterSchemas.validate_config_value(path, "ucb")
      assert :ok = SinterSchemas.validate_config_value(path, "pi")
      assert {:error, {_, _}} = SinterSchemas.validate_config_value(path, "invalid")

      # Test surrogate model choices
      path = [:dspex, :teleprompters, :beacon, :bayesian_optimization, :surrogate_model]

      assert :ok = SinterSchemas.validate_config_value(path, "gp")
      assert :ok = SinterSchemas.validate_config_value(path, "rf")
      assert :ok = SinterSchemas.validate_config_value(path, "et")
      assert {:error, {_, _}} = SinterSchemas.validate_config_value(path, "invalid")
    end
  end

  describe "error formatting" do
    test "formats errors consistently" do
      {:error, {error_atom, message}} =
        SinterSchemas.validate_config_value([:dspex, :client, :timeout], 100)

      assert is_atom(error_atom)
      assert is_binary(message)
      assert error_atom == :invalid_timeout
    end

    test "maps field names to appropriate error atoms" do
      # Test various field mappings
      {:error, {:invalid_timeout, _}} =
        SinterSchemas.validate_config_value([:dspex, :client, :timeout], 100)

      {:error, {:invalid_provider, _}} =
        SinterSchemas.validate_config_value([:dspex, :prediction, :default_provider], "invalid")

      {:error, {:invalid_log_level, _}} =
        SinterSchemas.validate_config_value([:dspex, :logging, :level], "invalid")
    end
  end

  describe "performance characteristics" do
    test "validation is fast for repeated calls" do
      path = [:dspex, :client, :timeout]
      value = 5000

      start_time = System.monotonic_time()

      # Validate many times
      for _i <- 1..1000 do
        SinterSchemas.validate_config_value(path, value)
      end

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should be fast (under 1 second for 1000 validations)
      assert duration_ms < 1000
    end

    test "schema creation is efficient" do
      start_time = System.monotonic_time()

      # Create schemas multiple times
      for _i <- 1..100 do
        SinterSchemas.client_configuration_schema()
        SinterSchemas.provider_configuration_schema()
        SinterSchemas.prediction_configuration_schema()
      end

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Should be very fast (under 500ms for 300 schema creations)
      assert duration_ms < 500
    end
  end

  describe "edge cases and error handling" do
    test "handles malformed data gracefully" do
      # Test with wrong data types
      {:error, {_, _}} =
        SinterSchemas.validate_config_value([:dspex, :client, :timeout], "not_a_number")

      {:error, {_, _}} =
        SinterSchemas.validate_config_value(
          [:dspex, :logging, :correlation_enabled],
          "not_a_boolean"
        )
    end

    test "validates boundary conditions" do
      # Test exact boundaries
      # minimum
      assert :ok = SinterSchemas.validate_config_value([:dspex, :client, :timeout], 1000)
      # maximum
      assert :ok = SinterSchemas.validate_config_value([:dspex, :client, :timeout], 300_000)

      # Test boundary violations
      # below minimum
      {:error, {_, _}} = SinterSchemas.validate_config_value([:dspex, :client, :timeout], 999)
      # above maximum
      {:error, {_, _}} = SinterSchemas.validate_config_value([:dspex, :client, :timeout], 300_001)
    end

    test "handles complex data structures" do
      # This would test more complex nested validations when they're added
      # For now, just ensure the basic structure works
      {:ok, schema} = SinterSchemas.export_json_schema(:provider)
      assert Map.has_key?(schema["properties"], "rate_limit")
      assert Map.has_key?(schema["properties"], "circuit_breaker")
    end
  end
end
