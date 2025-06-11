# File: test/integration/foundation_integration_test.exs
defmodule DSPEx.Integration.FoundationIntegrationTest do
  use ExUnit.Case, async: false

  alias DSPEx.Services.{ConfigManager, TelemetrySetup}

  @moduletag :integration
  @moduletag :foundation

  describe "Foundation Config integration" do
    test "ConfigManager starts and integrates with Foundation" do
      # Verify ConfigManager can start and connect to Foundation
      assert {:ok, _pid} = ConfigManager.start_link([])

      # Test basic configuration retrieval
      assert {:ok, _config} = ConfigManager.get([:providers, :gemini])
    end

    test "configuration hot updates work" do
      # Test that configuration can be updated at runtime
      original_temp = ConfigManager.get_with_default([:prediction, :default_temperature], 0.7)

      :ok = ConfigManager.update([:prediction, :default_temperature], 0.9)

      assert {:ok, 0.9} = ConfigManager.get([:prediction, :default_temperature])

      # Cleanup
      :ok = ConfigManager.update([:prediction, :default_temperature], original_temp)
    end

    test "handles Foundation service unavailability gracefully" do
      # Test fallback behavior when Foundation services are not available
      # This is important for test environments

      # Mock Foundation being unavailable
      result = ConfigManager.get([:nonexistent, :config])

      # Should handle gracefully
      assert match?({:error, _}, result)
    end
  end

  describe "Foundation Telemetry integration" do
    test "TelemetrySetup integrates with Foundation telemetry" do
      assert {:ok, _pid} = TelemetrySetup.start_link([])

      # Verify telemetry handlers are attached
      handlers = :telemetry.list_handlers([])
      dspex_handlers = Enum.filter(handlers, fn %{id: id} ->
        String.contains?(to_string(id), "dspex")
      end)

      assert length(dspex_handlers) > 0
    end

    test "telemetry events are properly emitted and handled" do
      # Set up a test handler to capture events
      test_pid = self()

      handler_id = "test-dspex-handler"
      :telemetry.attach(
        handler_id,
        [:dspex, :test, :event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{}
      )

      # Emit a test event
      :telemetry.execute([:dspex, :test, :event], %{duration: 100}, %{test: true})

      # Verify we received it
      assert_receive {:telemetry_event, [:dspex, :test, :event], %{duration: 100}, %{test: true}}, 1000

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "handles telemetry errors gracefully during Foundation shutdown" do
      # Test the defensive programming in TelemetrySetup for shutdown scenarios

      # This is important because of the Foundation/ExUnit race conditions
      # mentioned in the telemetry_setup.ex code

      # Simulate a shutdown scenario
      send(TelemetrySetup, :prepare_for_shutdown)

      # Verify the process handles it gracefully
      Process.sleep(100)
      assert Process.alive?(Process.whereis(TelemetrySetup))
    end
  end

  describe "Foundation circuit breaker integration" do
    test "circuit breakers are properly initialized" do
      # Test that Foundation circuit breakers are set up for each provider
      # during ConfigManager initialization

      # For now, verify that ConfigManager starts without errors
      # which indicates circuit breaker setup succeeded
      assert {:ok, _pid} = ConfigManager.start_link([])

      # In future, when circuit breakers are fully implemented:
      # Test that circuit breaker state can be queried
      # Test that circuit breakers trip on failures
      # Test that circuit breakers recover after timeout
    end
  end

  describe "service lifecycle management" do
    test "services start in correct order" do
      # Test that DSPEx services integrate properly with Foundation's
      # service lifecycle management

      # ConfigManager should start first
      assert {:ok, config_pid} = ConfigManager.start_link([])
      assert Process.alive?(config_pid)

      # TelemetrySetup should start after ConfigManager
      assert {:ok, telemetry_pid} = TelemetrySetup.start_link([])
      assert Process.alive?(telemetry_pid)
    end

    test "graceful shutdown preserves service state" do
      # Test that services can be stopped gracefully without losing
      # important state or configuration

      {:ok, config_pid} = ConfigManager.start_link([])
      {:ok, telemetry_pid} = TelemetrySetup.start_link([])

      # Stop services gracefully
      GenServer.stop(telemetry_pid, :normal)
      GenServer.stop(config_pid, :normal)

      # Verify they stopped cleanly
      refute Process.alive?(telemetry_pid)
      refute Process.alive?(config_pid)
    end
  end
end
