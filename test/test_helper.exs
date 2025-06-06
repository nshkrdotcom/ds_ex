ExUnit.start()

# Start Mox for mocking dependencies in tests
# Note: Only mocking modules that exist in Stage 1

# Configure test environment
Application.put_env(:dspex, :environment, :test)

# Ensure required applications are started (only the ones we actually need for Stage 1)
Application.ensure_all_started(:propcheck)

# Test configuration
ExUnit.configure(
  exclude: [
    :integration,
    :end_to_end,
    :performance,
    :external_api,
    :phase2_features,
    :reproduction_test
  ],
  timeout: 30_000,
  max_failures: 10
)
