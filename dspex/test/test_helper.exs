ExUnit.start()

# Start Mox for mocking dependencies in tests
Mox.defmock(DSPEx.Test.ReqMock, for: DSPEx.Test.ReqBehaviour)
Mox.defmock(DSPEx.Test.ClientMock, for: DSPEx.Client)
Mox.defmock(DSPEx.Test.AdapterMock, for: DSPEx.Adapter)

# Set global mode for Mox - allows any process to use mocks
Mox.set_mox_global()

# Configure test environment
Application.put_env(:dspex, :environment, :test)

# Ensure required applications are started
Application.ensure_all_started(:cachex)
Application.ensure_all_started(:fuse)

# Test configuration
ExUnit.configure(
  exclude: [:integration, :end_to_end, :performance],
  timeout: 30_000,
  max_failures: 10
)
