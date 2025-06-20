defmodule DSPEx.Config.ElixirMLSchemasTest do
  use ExUnit.Case
  doctest DSPEx.Config.ElixirMLSchemas

  alias DSPEx.Config.ElixirMLSchemas

  describe "path_to_schema/1" do
    test "returns client configuration schema for client paths" do
      assert {:ok, schema, [:timeout]} =
               ElixirMLSchemas.path_to_schema([:dspex, :client, :timeout])

      assert Map.has_key?(schema, :fields)
      assert Map.has_key?(schema.fields, :timeout)
    end

    test "returns provider configuration schema for provider paths" do
      assert {:ok, schema, [:api_key]} =
               ElixirMLSchemas.path_to_schema([:dspex, :providers, :openai, :api_key])

      assert Map.has_key?(schema, :fields)
      assert Map.has_key?(schema.fields, :api_key)
    end

    test "returns prediction configuration schema for prediction paths" do
      assert {:ok, schema, [:default_temperature]} =
               ElixirMLSchemas.path_to_schema([:dspex, :prediction, :default_temperature])

      assert Map.has_key?(schema, :fields)
      assert Map.has_key?(schema.fields, :default_temperature)
    end

    test "returns error for unknown paths" do
      assert {:error, :unknown_path} = ElixirMLSchemas.path_to_schema([:invalid, :path])
    end

    test "handles nested configuration paths" do
      assert {:ok, schema, [:requests_per_minute]} =
               ElixirMLSchemas.path_to_schema([
                 :dspex,
                 :providers,
                 :openai,
                 :rate_limit,
                 :requests_per_minute
               ])

      assert Map.has_key?(schema, :fields)
    end
  end

  describe "validate_config_value/2" do
    test "validates client timeout with valid integer" do
      assert :ok = ElixirMLSchemas.validate_config_value([:dspex, :client, :timeout], 30_000)
    end

    test "rejects invalid client timeout" do
      assert {:error, _} =
               ElixirMLSchemas.validate_config_value([:dspex, :client, :timeout], "invalid")

      assert {:error, _} =
               ElixirMLSchemas.validate_config_value([:dspex, :client, :timeout], -1000)

      assert {:error, _} = ElixirMLSchemas.validate_config_value([:dspex, :client, :timeout], 0)
    end

    test "validates provider configuration" do
      assert :ok =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :api_key],
                 "sk-test"
               )

      assert :ok =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :api_key],
                 {:system, "OPENAI_API_KEY"}
               )

      assert :ok =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :providers, :openai, :base_url],
                 "https://api.openai.com/v1"
               )
    end

    test "validates prediction configuration with ML types" do
      # Temperature should use probability-like validation
      assert :ok =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :prediction, :default_temperature],
                 0.7
               )

      assert {:error, _} =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :prediction, :default_temperature],
                 3.0
               )

      # Provider should be atom choice
      assert :ok =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :prediction, :default_provider],
                 :openai
               )

      assert {:error, _} =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :prediction, :default_provider],
                 :invalid
               )
    end

    test "validates boolean configurations" do
      assert :ok =
               ElixirMLSchemas.validate_config_value([:dspex, :prediction, :cache_enabled], true)

      assert :ok =
               ElixirMLSchemas.validate_config_value([:dspex, :prediction, :cache_enabled], false)

      assert {:error, _} =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :prediction, :cache_enabled],
                 "true"
               )
    end

    test "validates logging configuration" do
      assert :ok = ElixirMLSchemas.validate_config_value([:dspex, :logging, :level], :info)
      assert :ok = ElixirMLSchemas.validate_config_value([:dspex, :logging, :level], :debug)

      assert {:error, _} =
               ElixirMLSchemas.validate_config_value([:dspex, :logging, :level], :invalid)
    end

    test "validates BEACON teleprompter configuration" do
      assert :ok =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :teleprompters, :beacon, :max_concurrent_operations],
                 10
               )

      assert {:error, _} =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :teleprompters, :beacon, :max_concurrent_operations],
                 0
               )

      # Bayesian optimization parameters
      assert :ok =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
                 :expected_improvement
               )

      assert {:error, _} =
               ElixirMLSchemas.validate_config_value(
                 [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
                 :invalid
               )
    end

    test "rejects nil values even for optional fields" do
      assert {:error, _} = ElixirMLSchemas.validate_config_value([:dspex, :client, :timeout], nil)
    end

    test "returns error for unknown paths" do
      assert {:error, {:unknown_path, _}} =
               ElixirMLSchemas.validate_config_value([:invalid, :path], "value")
    end
  end

  describe "list_domains/0" do
    test "returns all available configuration domains" do
      domains = ElixirMLSchemas.list_domains()

      assert :client in domains
      assert :provider in domains
      assert :prediction in domains
      assert :evaluation in domains
      assert :teleprompter in domains
      assert :beacon in domains
      assert :logging in domains
      assert :telemetry in domains
    end
  end

  describe "export_json_schema/1" do
    test "exports JSON schema for client domain" do
      assert {:ok, json_schema} = ElixirMLSchemas.export_json_schema(:client)

      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "properties")
      assert Map.has_key?(json_schema["properties"], "timeout")
    end

    test "exports JSON schema for prediction domain with ML optimizations" do
      assert {:ok, json_schema} = ElixirMLSchemas.export_json_schema(:prediction)

      assert json_schema["type"] == "object"
      assert Map.has_key?(json_schema, "properties")

      # Should have ML-optimized temperature field
      temp_prop = json_schema["properties"]["default_temperature"]
      assert temp_prop["type"] == "number"
      assert temp_prop["minimum"] == 0.0
      assert temp_prop["maximum"] == 2.0
    end

    test "returns error for unknown domain" do
      assert {:error, {:unknown_domain, :invalid}} = ElixirMLSchemas.export_json_schema(:invalid)
    end
  end

  describe "schema validation with ElixirML types" do
    test "client configuration schema uses proper ElixirML types" do
      {:ok, schema, _} = ElixirMLSchemas.path_to_schema([:dspex, :client, :timeout])

      # Should be able to validate using ElixirML
      assert {:ok, validated} =
               ElixirML.Runtime.validate(schema, %{
                 timeout: 30_000,
                 retry_attempts: 3,
                 backoff_factor: 2.0
               })

      assert validated.timeout == 30_000
      assert validated.retry_attempts == 3
      assert validated.backoff_factor == 2.0
    end

    test "prediction configuration uses ML-native types" do
      {:ok, schema, _} =
        ElixirMLSchemas.path_to_schema([:dspex, :prediction, :default_temperature])

      # Should handle temperature as ML-native type
      assert {:ok, validated} =
               ElixirML.Runtime.validate(schema, %{
                 default_provider: :openai,
                 default_temperature: 0.7,
                 default_max_tokens: 1000,
                 cache_enabled: true,
                 cache_ttl: 3600
               })

      assert validated.default_temperature == 0.7
      assert validated.default_provider == :openai
    end

    test "provider configuration handles complex validation" do
      {:ok, schema, _} = ElixirMLSchemas.path_to_schema([:dspex, :providers, :openai, :api_key])

      # Should handle union types for API key
      assert {:ok, validated} =
               ElixirML.Runtime.validate(schema, %{
                 api_key: "sk-test",
                 base_url: "https://api.openai.com/v1",
                 default_model: "gpt-4",
                 timeout: 30_000
               })

      assert validated.api_key == "sk-test"
    end
  end

  describe "error handling and compatibility" do
    test "maintains error format compatibility with SinterSchemas" do
      {:error, {error_atom, message}} =
        ElixirMLSchemas.validate_config_value([:dspex, :client, :timeout], "invalid")

      assert is_atom(error_atom)
      assert is_binary(message)
      assert error_atom == :invalid_timeout
    end

    test "provides detailed validation errors" do
      {:error, {error_atom, message}} =
        ElixirMLSchemas.validate_config_value([:dspex, :prediction, :default_temperature], 5.0)

      assert error_atom == :invalid_temperature
      assert String.contains?(message, "temperature") or String.contains?(message, "range")
    end
  end
end
