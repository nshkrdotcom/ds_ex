ExUnit.start()

# Load SIMBA-specific test support files
Code.require_file("support/simba_test_helper.exs", __DIR__)

# Configure test environment for SIMBA
Application.put_env(:dspex, :environment, :test)

# Test configuration for SIMBA tests
ExUnit.configure(
  exclude: [
    :integration,
    :performance,
    :external_api,
    :live_test
  ],
  timeout: 10_000,
  max_failures: 5
)
