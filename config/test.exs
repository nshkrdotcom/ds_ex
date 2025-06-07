import Config

# Configure DSPEx for test environment
config :dspex,
  # Enable telemetry debugging in test mode to monitor race condition workarounds
  # Set to true to debug telemetry issues
  telemetry_debug: false,

  # Test-specific telemetry settings
  telemetry: %{
    enabled: true,
    detailed_logging: false,
    performance_tracking: true,

    # Enhanced protection against Foundation/ExUnit race conditions
    defensive_mode: true,
    graceful_shutdown: true
  },

  # Configure providers for testing (use mock responses)
  providers: %{
    test: %{
      api_key: "test-key",
      base_url: "http://localhost:8080",
      default_model: "test-model",
      # Faster timeouts in tests
      timeout: 1000,
      circuit_breaker: %{
        failure_threshold: 2,
        recovery_time: 100
      },
      rate_limit: %{
        # Higher limits for tests
        requests_per_minute: 1000,
        tokens_per_minute: 100_000
      }
    }
  },

  # Test-specific prediction settings
  prediction: %{
    # Disable cache in tests for predictable behavior
    cache_enabled: false,
    cache_ttl: 100,
    default_provider: :test,
    # More deterministic in tests
    default_temperature: 0.1,
    default_max_tokens: 50
  }

# Configure logging for tests
config :logger,
  # Reduce log noise in tests
  level: :warning,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Configure ExUnit to exclude reproduction tests by default
config :ex_unit,
  exclude: [
    :integration,
    :end_to_end,
    :performance,
    :external_api,
    :phase2_features,
    :reproduction_test
  ]

# Foundation-specific test configuration
if Code.ensure_loaded?(Foundation) do
  config :foundation,
    # Test mode settings to prevent race conditions
    test_mode: true,
    graceful_shutdown: true,

    # Telemetry configuration for tests
    telemetry: %{
      enabled: true,
      test_isolation: true
    },

    # Events configuration (if using Foundation Events)
    events: %{
      enabled: true,
      test_mode: true
    }
end
