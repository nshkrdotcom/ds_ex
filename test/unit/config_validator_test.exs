defmodule DSPEx.Config.ValidatorTest do
  use ExUnit.Case, async: true

  alias DSPEx.Config.Validator
  alias DSPEx.Config.ElixactSchemas

  doctest DSPEx.Config.Validator

  describe "path validation" do
    test "validates known configuration paths" do
      assert :ok = Validator.validate_path([:dspex, :client, :timeout])
      assert :ok = Validator.validate_path([:dspex, :providers, :gemini, :api_key])
      assert :ok = Validator.validate_path([:dspex, :prediction, :default_provider])

      assert :ok =
               Validator.validate_path([
                 :dspex,
                 :teleprompters,
                 :beacon,
                 :optimization,
                 :max_trials
               ])
    end

    test "rejects invalid configuration paths" do
      assert {:error, :invalid_path} = Validator.validate_path([:invalid, :path])
      assert {:error, :invalid_path} = Validator.validate_path([:not_dspex, :client, :timeout])
      assert {:error, :invalid_path} = Validator.validate_path([])
    end

    test "validates extensible paths with dspex prefix" do
      # The validator should allow new paths under :dspex for extensibility
      assert :ok = Validator.validate_path([:dspex, :new_feature, :setting])
    end
  end

  describe "schema-based value validation" do
    test "validates client configuration values" do
      # Valid client timeout
      assert :ok = Validator.validate_value([:dspex, :client, :timeout], 30000)
      assert :ok = Validator.validate_value([:dspex, :client, :timeout], 1)

      # Invalid client timeout
      assert {:error, :invalid_timeout} = Validator.validate_value([:dspex, :client, :timeout], 0)

      assert {:error, :invalid_timeout} =
               Validator.validate_value([:dspex, :client, :timeout], -1000)

      assert {:error, :invalid_timeout} =
               Validator.validate_value([:dspex, :client, :timeout], "30000")

      # Valid retry attempts
      assert :ok = Validator.validate_value([:dspex, :client, :retry_attempts], 0)
      assert :ok = Validator.validate_value([:dspex, :client, :retry_attempts], 5)

      # Invalid retry attempts  
      assert {:error, :invalid_retry_attempts} =
               Validator.validate_value([:dspex, :client, :retry_attempts], -1)

      assert {:error, :invalid_retry_attempts} =
               Validator.validate_value([:dspex, :client, :retry_attempts], "3")

      # Valid backoff factor
      assert :ok = Validator.validate_value([:dspex, :client, :backoff_factor], 2.0)
      assert :ok = Validator.validate_value([:dspex, :client, :backoff_factor], 1.5)

      # Invalid backoff factor
      assert {:error, :invalid_backoff_factor} =
               Validator.validate_value([:dspex, :client, :backoff_factor], 0)

      assert {:error, :invalid_backoff_factor} =
               Validator.validate_value([:dspex, :client, :backoff_factor], -1.0)
    end

    test "validates provider configuration values" do
      # Valid API key
      assert :ok =
               Validator.validate_value([:dspex, :providers, :gemini, :api_key], "valid-api-key")

      assert :ok =
               Validator.validate_value(
                 [:dspex, :providers, :gemini, :api_key],
                 {:system, "GEMINI_API_KEY"}
               )

      # Invalid API key
      assert {:error, :invalid_api_key} =
               Validator.validate_value([:dspex, :providers, :gemini, :api_key], 12345)

      assert {:error, :invalid_api_key} =
               Validator.validate_value([:dspex, :providers, :gemini, :api_key], nil)

      # Valid base URL
      assert :ok =
               Validator.validate_value(
                 [:dspex, :providers, :openai, :base_url],
                 "https://api.openai.com"
               )

      # Invalid base URL  
      assert {:error, :invalid_base_url} =
               Validator.validate_value([:dspex, :providers, :openai, :base_url], 123)

      # Valid rate limit
      assert :ok =
               Validator.validate_value(
                 [:dspex, :providers, :gemini, :rate_limit, :requests_per_minute],
                 100
               )

      # Invalid rate limit
      assert {:error, :invalid_rate_limit} =
               Validator.validate_value(
                 [:dspex, :providers, :gemini, :rate_limit, :requests_per_minute],
                 0
               )

      assert {:error, :invalid_rate_limit} =
               Validator.validate_value(
                 [:dspex, :providers, :gemini, :rate_limit, :requests_per_minute],
                 "100"
               )
    end

    test "validates prediction configuration values" do
      # Valid provider
      assert :ok = Validator.validate_value([:dspex, :prediction, :default_provider], :gemini)
      assert :ok = Validator.validate_value([:dspex, :prediction, :default_provider], :openai)

      # Invalid provider
      assert {:error, :invalid_provider} =
               Validator.validate_value(
                 [:dspex, :prediction, :default_provider],
                 :invalid_provider
               )

      assert {:error, :invalid_provider} =
               Validator.validate_value([:dspex, :prediction, :default_provider], "gemini")

      # Valid temperature
      assert :ok = Validator.validate_value([:dspex, :prediction, :default_temperature], 0.0)
      assert :ok = Validator.validate_value([:dspex, :prediction, :default_temperature], 1.0)
      assert :ok = Validator.validate_value([:dspex, :prediction, :default_temperature], 2.0)

      # Invalid temperature
      assert {:error, :invalid_temperature} =
               Validator.validate_value([:dspex, :prediction, :default_temperature], -0.1)

      assert {:error, :invalid_temperature} =
               Validator.validate_value([:dspex, :prediction, :default_temperature], 2.1)

      assert {:error, :invalid_temperature} =
               Validator.validate_value([:dspex, :prediction, :default_temperature], "1.0")

      # Valid cache settings
      assert :ok = Validator.validate_value([:dspex, :prediction, :cache_enabled], true)
      assert :ok = Validator.validate_value([:dspex, :prediction, :cache_enabled], false)

      # Invalid cache settings
      assert {:error, :invalid_boolean} =
               Validator.validate_value([:dspex, :prediction, :cache_enabled], "true")

      assert {:error, :invalid_boolean} =
               Validator.validate_value([:dspex, :prediction, :cache_enabled], 1)
    end

    test "validates BEACON teleprompter configuration values" do
      # Valid optimization settings
      assert :ok =
               Validator.validate_value(
                 [:dspex, :teleprompters, :beacon, :optimization, :max_trials],
                 10
               )

      assert :ok =
               Validator.validate_value(
                 [:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold],
                 0.05
               )

      # Invalid optimization settings
      assert {:error, :invalid_max_trials} =
               Validator.validate_value(
                 [:dspex, :teleprompters, :beacon, :optimization, :max_trials],
                 0
               )

      assert {:error, :invalid_improvement_threshold} =
               Validator.validate_value(
                 [:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold],
                 1.5
               )

      # Valid Bayesian optimization settings
      assert :ok =
               Validator.validate_value(
                 [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
                 :expected_improvement
               )

      assert :ok =
               Validator.validate_value(
                 [:dspex, :teleprompters, :beacon, :bayesian_optimization, :surrogate_model],
                 :gaussian_process
               )

      # Invalid Bayesian optimization settings
      assert {:error, :invalid_acquisition_function} =
               Validator.validate_value(
                 [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
                 :invalid_function
               )

      assert {:error, :invalid_surrogate_model} =
               Validator.validate_value(
                 [:dspex, :teleprompters, :beacon, :bayesian_optimization, :surrogate_model],
                 :invalid_model
               )
    end

    test "validates logging and telemetry configuration values" do
      # Valid log level
      assert :ok = Validator.validate_value([:dspex, :logging, :level], :info)
      assert :ok = Validator.validate_value([:dspex, :logging, :level], :debug)
      assert :ok = Validator.validate_value([:dspex, :logging, :level], :error)

      # Invalid log level
      assert {:error, :invalid_log_level} =
               Validator.validate_value([:dspex, :logging, :level], :invalid_level)

      assert {:error, :invalid_log_level} =
               Validator.validate_value([:dspex, :logging, :level], "info")

      # Valid boolean settings
      assert :ok = Validator.validate_value([:dspex, :telemetry, :enabled], true)
      assert :ok = Validator.validate_value([:dspex, :logging, :correlation_enabled], false)

      # Invalid boolean settings
      assert {:error, :invalid_boolean} =
               Validator.validate_value([:dspex, :telemetry, :enabled], "true")

      assert {:error, :invalid_boolean} =
               Validator.validate_value([:dspex, :logging, :correlation_enabled], 1)
    end
  end

  describe "enhanced error reporting" do
    test "provides detailed validation error information" do
      {:error, error_details} =
        Validator.validate_value_detailed([:dspex, :client, :timeout], "invalid")

      assert is_map(error_details)
      assert error_details.field == :timeout
      assert error_details.provided == "invalid"
      assert error_details.error_code == :invalid_timeout
      assert is_binary(error_details.message)
      assert is_binary(error_details.suggestion)
      assert error_details.path == [:dspex, :client, :timeout]
    end

    test "provides helpful suggestions for common errors" do
      {:error, error_details} =
        Validator.validate_value_detailed([:dspex, :client, :timeout], "invalid")

      assert error_details.suggestion =~ "positive integer"
      assert error_details.suggestion =~ "30000"

      {:error, error_details} =
        Validator.validate_value_detailed([:dspex, :prediction, :default_temperature], 3.0)

      assert error_details.suggestion =~ "0.0 and 2.0"

      {:error, error_details} =
        Validator.validate_value_detailed([:dspex, :logging, :level], :invalid)

      assert error_details.suggestion =~ "valid log level"
    end

    test "returns :ok for valid values in detailed validation" do
      assert :ok = Validator.validate_value_detailed([:dspex, :client, :timeout], 30000)

      assert :ok =
               Validator.validate_value_detailed(
                 [:dspex, :prediction, :default_provider],
                 :gemini
               )
    end
  end

  describe "JSON schema export" do
    test "exports schemas for all configuration domains" do
      domains = Validator.list_domains()
      assert :client in domains
      assert :provider in domains
      assert :prediction in domains
      assert :beacon in domains

      Enum.each(domains, fn domain ->
        {:ok, schema} = Validator.export_schema(domain)
        assert is_map(schema)
        assert schema["type"] == "object"
        assert is_map(schema["properties"])
      end)
    end

    test "returns error for unknown domain" do
      assert {:error, {:unknown_domain, :unknown}} = Validator.export_schema(:unknown)
    end
  end

  describe "backward compatibility" do
    test "maintains same API as legacy validator" do
      # Ensure the main validate_value function signature is preserved
      assert :ok = Validator.validate_value([:dspex, :client, :timeout], 30000)

      assert {:error, :invalid_timeout} =
               Validator.validate_value([:dspex, :client, :timeout], "invalid")

      # Ensure error atoms match legacy behavior
      assert {:error, :invalid_timeout} = Validator.validate_value([:dspex, :client, :timeout], 0)

      assert {:error, :invalid_retry_attempts} =
               Validator.validate_value([:dspex, :client, :retry_attempts], -1)

      assert {:error, :invalid_provider} =
               Validator.validate_value([:dspex, :prediction, :default_provider], :invalid)

      assert {:error, :invalid_boolean} =
               Validator.validate_value([:dspex, :telemetry, :enabled], "true")
    end

    test "legacy validator functions still work" do
      # Ensure legacy functions are still accessible for debugging/comparison
      assert :ok = Validator.validate_value_legacy([:dspex, :client, :timeout], 30000)

      assert {:error, :invalid_timeout} =
               Validator.validate_value_legacy([:dspex, :client, :timeout], "invalid")
    end
  end

  describe "ElixactSchemas integration" do
    test "path to schema mapping works correctly" do
      # Client configuration
      assert {:ok, ClientConfiguration, [:timeout]} =
               ElixactSchemas.path_to_schema([:dspex, :client, :timeout])

      assert {:ok, ClientConfiguration, [:retry_attempts]} =
               ElixactSchemas.path_to_schema([:dspex, :client, :retry_attempts])

      # Provider configuration with wildcard
      assert {:ok, ProviderConfiguration, [:api_key]} =
               ElixactSchemas.path_to_schema([:dspex, :providers, :gemini, :api_key])

      assert {:ok, ProviderConfiguration, [:rate_limit, :requests_per_minute]} =
               ElixactSchemas.path_to_schema([
                 :dspex,
                 :providers,
                 :openai,
                 :rate_limit,
                 :requests_per_minute
               ])

      # BEACON configuration  
      assert {:ok, BEACONConfiguration, [:optimization, :max_trials]} =
               ElixactSchemas.path_to_schema([
                 :dspex,
                 :teleprompters,
                 :beacon,
                 :optimization,
                 :max_trials
               ])

      # Unknown path
      assert {:error, :unknown_path} = ElixactSchemas.path_to_schema([:invalid, :path])
    end

    test "schema validation provides consistent results" do
      # Direct schema validation should match validator results
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], 30000)

      assert {:error, _} =
               ElixactSchemas.validate_config_value([:dspex, :client, :timeout], "invalid")

      # Error format should be suitable for validator processing
      {:error, error} =
        ElixactSchemas.validate_config_value([:dspex, :client, :timeout], "invalid")

      assert is_tuple(error) or is_atom(error) or is_map(error)
    end

    test "all configuration domains have JSON schema export" do
      domains = ElixactSchemas.list_domains()

      Enum.each(domains, fn domain ->
        {:ok, json_schema} = ElixactSchemas.export_json_schema(domain)

        # Verify JSON schema structure
        assert is_map(json_schema)
        assert json_schema["type"] == "object"
        assert is_map(json_schema["properties"])

        # Verify schema contains field definitions
        assert map_size(json_schema["properties"]) > 0
      end)
    end
  end

  describe "error edge cases" do
    test "handles unknown paths gracefully" do
      assert {:error, {:unknown_path, [:unknown, :path]}} =
               Validator.validate_value([:unknown, :path], "value")
    end

    test "handles nil and edge values" do
      assert {:error, _} = Validator.validate_value([:dspex, :client, :timeout], nil)
      assert {:error, _} = Validator.validate_value([:dspex, :client, :timeout], %{})
      assert {:error, _} = Validator.validate_value([:dspex, :client, :timeout], [])
    end

    test "detailed validation handles edge cases" do
      {:error, error_details} = Validator.validate_value_detailed([:unknown, :path], "value")
      assert is_map(error_details) or error_details == {:unknown_path, [:unknown, :path]}
    end
  end

  describe "performance characteristics" do
    test "schema validation is reasonably fast" do
      # Ensure validation doesn't introduce significant overhead
      start_time = System.monotonic_time(:microsecond)

      # Run 1000 validations
      for _i <- 1..1000 do
        Validator.validate_value([:dspex, :client, :timeout], 30000)
      end

      end_time = System.monotonic_time(:microsecond)
      duration_ms = (end_time - start_time) / 1000

      # Should complete 1000 validations in under 100ms (reasonable for dev use)
      assert duration_ms < 100,
             "Schema validation took #{duration_ms}ms for 1000 calls - too slow"
    end

    test "path validation remains fast" do
      start_time = System.monotonic_time(:microsecond)

      # Run 1000 path validations  
      for _i <- 1..1000 do
        Validator.validate_path([:dspex, :client, :timeout])
      end

      end_time = System.monotonic_time(:microsecond)
      duration_ms = (end_time - start_time) / 1000

      # Path validation should be very fast
      assert duration_ms < 50, "Path validation took #{duration_ms}ms for 1000 calls - too slow"
    end
  end
end
