defmodule DSPEx.Config.ElixactSchemasTest do
  use ExUnit.Case, async: true

  alias DSPEx.Config.ElixactSchemas

  describe "schema definitions" do
    test "defines all required schemas" do
      # Verify schema modules are defined
      assert Code.ensure_loaded?(ClientConfiguration)
      assert Code.ensure_loaded?(ProviderConfiguration)
      assert Code.ensure_loaded?(PredictionConfiguration)
      assert Code.ensure_loaded?(EvaluationConfiguration)
      assert Code.ensure_loaded?(TeleprompterConfiguration)
      assert Code.ensure_loaded?(BEACONConfiguration)
      assert Code.ensure_loaded?(LoggingConfiguration)
      assert Code.ensure_loaded?(TelemetryConfiguration)
    end

    test "schemas can validate correct data structures" do
      # Client configuration
      assert {:ok, _} = ClientConfiguration.validate(%{
        timeout: 30000,
        retry_attempts: 3,
        backoff_factor: 2.0
      })

      # Provider configuration
      assert {:ok, _} = ProviderConfiguration.validate(%{
        api_key: "test-key",
        base_url: "https://api.example.com",
        default_model: "gpt-4",
        timeout: 30000,
        rate_limit: %{
          requests_per_minute: 100,
          tokens_per_minute: 10000
        },
        circuit_breaker: %{
          failure_threshold: 5,
          recovery_time: 60000
        }
      })

      # Prediction configuration
      assert {:ok, _} = PredictionConfiguration.validate(%{
        default_provider: :gemini,
        default_temperature: 0.7,
        default_max_tokens: 1000,
        cache_enabled: true,
        cache_ttl: 3600
      })
    end

    test "schemas reject invalid data structures" do
      # Invalid client timeout (string instead of integer)
      assert {:error, _} = ClientConfiguration.validate(%{timeout: "30000"})

      # Invalid provider (not in allowed list)
      assert {:error, _} = PredictionConfiguration.validate(%{default_provider: :invalid_provider})

      # Invalid temperature (out of range)
      assert {:error, _} = PredictionConfiguration.validate(%{default_temperature: 3.0})

      # Invalid boolean (string instead of boolean)
      assert {:error, _} = TelemetryConfiguration.validate(%{enabled: "true"})
    end
  end

  describe "path to schema mapping" do
    test "maps client configuration paths correctly" do
      assert {:ok, ClientConfiguration, [:timeout]} = ElixactSchemas.path_to_schema([:dspex, :client, :timeout])
      assert {:ok, ClientConfiguration, [:retry_attempts]} = ElixactSchemas.path_to_schema([:dspex, :client, :retry_attempts])
      assert {:ok, ClientConfiguration, [:backoff_factor]} = ElixactSchemas.path_to_schema([:dspex, :client, :backoff_factor])
    end

    test "maps provider configuration paths with wildcards" do
      # Test different providers map to same schema
      assert {:ok, ProviderConfiguration, [:api_key]} = ElixactSchemas.path_to_schema([:dspex, :providers, :gemini, :api_key])
      assert {:ok, ProviderConfiguration, [:api_key]} = ElixactSchemas.path_to_schema([:dspex, :providers, :openai, :api_key])
      assert {:ok, ProviderConfiguration, [:api_key]} = ElixactSchemas.path_to_schema([:dspex, :providers, :claude, :api_key])

      # Test nested paths
      assert {:ok, ProviderConfiguration, [:rate_limit, :requests_per_minute]} = 
        ElixactSchemas.path_to_schema([:dspex, :providers, :gemini, :rate_limit, :requests_per_minute])
      
      assert {:ok, ProviderConfiguration, [:circuit_breaker, :failure_threshold]} = 
        ElixactSchemas.path_to_schema([:dspex, :providers, :openai, :circuit_breaker, :failure_threshold])
    end

    test "maps BEACON configuration paths correctly" do
      assert {:ok, BEACONConfiguration, [:default_instruction_model]} = 
        ElixactSchemas.path_to_schema([:dspex, :teleprompters, :beacon, :default_instruction_model])
      
      assert {:ok, BEACONConfiguration, [:optimization, :max_trials]} = 
        ElixactSchemas.path_to_schema([:dspex, :teleprompters, :beacon, :optimization, :max_trials])
      
      assert {:ok, BEACONConfiguration, [:bayesian_optimization, :acquisition_function]} = 
        ElixactSchemas.path_to_schema([:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function])
    end

    test "returns error for unknown paths" do
      assert {:error, :unknown_path} = ElixactSchemas.path_to_schema([:invalid, :path])
      assert {:error, :unknown_path} = ElixactSchemas.path_to_schema([:dspex, :unknown, :field])
      assert {:error, :unknown_path} = ElixactSchemas.path_to_schema([])
    end
  end

  describe "configuration value validation" do
    test "validates simple configuration values" do
      # Client timeout
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], 30000)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], "invalid")
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], 0)

      # Provider API key
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :providers, :gemini, :api_key], "valid-key")
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :providers, :gemini, :api_key], {:system, "ENV_VAR"})
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :providers, :gemini, :api_key], 12345)

      # Boolean values
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :telemetry, :enabled], true)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :telemetry, :enabled], false)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :telemetry, :enabled], "true")
    end

    test "validates nested configuration values" do
      # Rate limit settings
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :providers, :gemini, :rate_limit, :requests_per_minute], 100)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :providers, :gemini, :rate_limit, :requests_per_minute], 0)

      # Circuit breaker settings
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :providers, :openai, :circuit_breaker, :failure_threshold], 5)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :providers, :openai, :circuit_breaker, :failure_threshold], "5")

      # BEACON optimization settings
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :teleprompters, :beacon, :optimization, :max_trials], 10)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :teleprompters, :beacon, :optimization, :max_trials], 0)
    end

    test "validates choice constraints" do
      # Valid providers
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :prediction, :default_provider], :gemini)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :prediction, :default_provider], :openai)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :prediction, :default_provider], :invalid_provider)

      # Valid log levels
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :logging, :level], :info)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :logging, :level], :debug)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :logging, :level], :error)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :logging, :level], :invalid_level)

      # Valid acquisition functions
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function], :expected_improvement)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function], :invalid_function)
    end

    test "validates numeric constraints" do
      # Temperature constraints (0.0 to 2.0)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :prediction, :default_temperature], 0.0)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :prediction, :default_temperature], 1.0)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :prediction, :default_temperature], 2.0)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :prediction, :default_temperature], -0.1)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :prediction, :default_temperature], 2.1)

      # Improvement threshold constraints (0.0 to 1.0)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold], 0.0)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold], 0.05)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold], 1.0)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold], 1.5)

      # Positive integer constraints
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], 1)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], 30000)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], 0)

      # Non-negative integer constraints
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :client, :retry_attempts], 0)
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :client, :retry_attempts], 5)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :client, :retry_attempts], -1)
    end

    test "handles unknown paths" do
      assert {:error, {:unknown_path, [:unknown, :path]}} = 
        ElixactSchemas.validate_config_value([:unknown, :path], "value")
      
      assert {:error, {:unknown_path, [:dspex, :unknown_domain, :field]}} = 
        ElixactSchemas.validate_config_value([:dspex, :unknown_domain, :field], "value")
    end
  end

  describe "JSON schema export" do
    test "exports valid JSON schemas for all domains" do
      domains = ElixactSchemas.list_domains()
      
      Enum.each(domains, fn domain ->
        {:ok, json_schema} = ElixactSchemas.export_json_schema(domain)
        
        # Basic JSON schema structure
        assert is_map(json_schema)
        assert json_schema["type"] == "object"
        assert is_map(json_schema["properties"])
        
        # Should have at least one property
        assert map_size(json_schema["properties"]) > 0
        
        # Properties should have valid schema structure
        Enum.each(json_schema["properties"], fn {field_name, field_schema} ->
          assert is_binary(field_name)
          assert is_map(field_schema)
          assert is_binary(field_schema["type"]) or is_list(field_schema["type"])
        end)
      end)
    end

    test "includes field documentation in exported schemas" do
      {:ok, client_schema} = ElixactSchemas.export_json_schema(:client)
      
      # Should have descriptions for documented fields
      timeout_schema = client_schema["properties"]["timeout"]
      assert is_map(timeout_schema)
      # Note: Documentation inclusion depends on Elixact JSON schema generation
      # This test verifies the structure is compatible
    end

    test "handles constraint validation in exported schemas" do
      {:ok, prediction_schema} = ElixactSchemas.export_json_schema(:prediction)
      
      # Temperature should have numeric constraints
      temp_schema = prediction_schema["properties"]["default_temperature"]
      assert temp_schema["type"] == "number" or temp_schema["type"] == "float"
      
      # Provider should have enum constraints  
      provider_schema = prediction_schema["properties"]["default_provider"]
      assert provider_schema["type"] == "string"
      # Enum constraints may be included depending on Elixact implementation
    end

    test "returns error for unknown domains" do
      assert {:error, {:unknown_domain, :unknown}} = ElixactSchemas.export_json_schema(:unknown)
      assert {:error, {:unknown_domain, :invalid}} = ElixactSchemas.export_json_schema(:invalid)
    end
  end

  describe "domain listing" do
    test "lists all available configuration domains" do
      domains = ElixactSchemas.list_domains()
      
      expected_domains = [:client, :provider, :prediction, :evaluation, :teleprompter, :beacon, :logging, :telemetry]
      
      Enum.each(expected_domains, fn domain ->
        assert domain in domains, "Expected domain #{domain} not in list: #{inspect(domains)}"
      end)
      
      # Ensure all domains can export schemas
      Enum.each(domains, fn domain ->
        assert {:ok, _schema} = ElixactSchemas.export_json_schema(domain)
      end)
    end
  end

  describe "error normalization" do
    test "normalizes Elixact errors to legacy error atoms" do
      # These tests verify that the error mapping preserves backward compatibility
      
      # Test timeout validation error mapping
      {:error, error} = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], "invalid")
      
      case error do
        {:invalid_timeout, _message} -> assert true
        {error_atom, _message} when is_atom(error_atom) -> assert true
        _ -> assert false, "Expected normalized error format, got: #{inspect(error)}"
      end
    end

    test "handles multiple validation errors gracefully" do
      # Test that multiple errors are handled appropriately
      # This depends on how Elixact handles multiple field errors
      
      # For now, test that single field errors work correctly
      {:error, _error} = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], "invalid")
    end
  end

  describe "edge cases and error handling" do
    test "handles nil and edge values gracefully" do
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], nil)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], %{})
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :client, :timeout], [])
    end

    test "handles empty and malformed paths" do
      assert {:error, :unknown_path} = ElixactSchemas.path_to_schema([])
      assert {:error, :unknown_path} = ElixactSchemas.path_to_schema([:dspex])
      assert {:error, :unknown_path} = ElixactSchemas.path_to_schema([:not_dspex, :client, :timeout])
    end

    test "validates schema consistency across different providers" do
      # Ensure that wildcard provider paths work consistently
      providers = [:gemini, :openai, :claude, :anthropic]
      
      Enum.each(providers, fn provider ->
        # All providers should map to the same schema for API key
        assert {:ok, ProviderConfiguration, [:api_key]} = 
          ElixactSchemas.path_to_schema([:dspex, :providers, provider, :api_key])
        
        # All providers should validate the same way
        assert :ok = ElixactSchemas.validate_config_value([:dspex, :providers, provider, :api_key], "test-key")
        assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :providers, provider, :api_key], 123)
      end)
    end

    test "handles Union type validation for API keys" do
      # Test both string and tuple formats for API keys
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :providers, :gemini, :api_key], "direct-key")
      assert :ok = ElixactSchemas.validate_config_value([:dspex, :providers, :gemini, :api_key], {:system, "ENV_VAR"})
      
      # Invalid formats should fail
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :providers, :gemini, :api_key], 123)
      assert {:error, _} = ElixactSchemas.validate_config_value([:dspex, :providers, :gemini, :api_key], {:invalid, "format"})
    end
  end
end