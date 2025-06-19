ExUnit.start()

# Load test support files
Code.require_file("support/mock_helpers.exs", __DIR__)
Code.require_file("support/test_helpers.exs", __DIR__)
Code.require_file("support/beacon_test_mocks.exs", __DIR__)
Code.require_file("support/mock_provider.ex", __DIR__)

# Start Mox for mocking dependencies in tests
# Note: Only mocking modules that exist in Stage 1

# Configure test environment
Application.put_env(:dspex, :environment, :test)

# Ensure required applications are started (only the ones we actually need for Stage 1)
Application.ensure_all_started(:propcheck)

# Test configuration
ExUnit.configure(
  exclude: [
    :slow,
    :group_1,
    :group_2,
    :live_api,
    :integration,
    :end_to_end,
    :performance,
    :external_api,
    :phase2_features,
    :reproduction_test,
    :todo_optimize,
    :phase5a,
    :stress_test,
    :integration_test
  ],
  timeout: 30_000,
  max_failures: 10
)
