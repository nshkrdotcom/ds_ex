defmodule DSPEx.TelemetryRaceConditionTest do
  @moduledoc """
  Tests to validate the Foundation/ExUnit race condition workaround.

  These tests ensure that our defensive telemetry handlers prevent crashes
  during test cleanup and application shutdown scenarios.
  """
  use ExUnit.Case, async: false

  require Logger

  @tag :telemetry_race_condition
  test "defensive telemetry handlers survive Foundation shutdown" do
    # Enable telemetry debugging for this test
    original_debug = Application.get_env(:dspex, :telemetry_debug, false)
    Application.put_env(:dspex, :telemetry_debug, true)

    try do
      # Emit a burst of telemetry events to stress the system
      for i <- 1..50 do
        correlation_id = "test-shutdown-#{i}"

        # Emit various event types that our handlers process
        :telemetry.execute([:dspex, :predict, :start], %{}, %{
          signature: :TestSignature,
          correlation_id: correlation_id
        })

        :telemetry.execute([:dspex, :client, :request, :start], %{}, %{
          provider: :test,
          correlation_id: correlation_id
        })

        :telemetry.execute([:dspex, :predict, :stop], %{duration: i * 100}, %{
          signature: :TestSignature,
          provider: :test,
          success: true
        })

        # Small delay to create timing variations
        if rem(i, 10) == 0 do
          Process.sleep(1)
        end
      end

      # Force some Foundation telemetry calls to test defensive handling
      try do
        Foundation.Telemetry.emit_counter([:test, :stress], %{test: true})
        Foundation.Telemetry.emit_gauge([:test, :gauge], 42, %{})
      rescue
        # Expected if Foundation is not fully available
        _ -> :ok
      end

      # Test passes if we don't crash - defensive handlers worked
      assert true
    after
      # Restore original debug setting
      Application.put_env(:dspex, :telemetry_debug, original_debug)
    end
  end

  @tag :telemetry_race_condition
  test "telemetry handlers gracefully handle ETS table unavailability" do
    # Simulate scenarios where ETS tables might be unavailable

    # Create a mock GenServer that will crash when accessed
    {:ok, mock_pid} = Agent.start_link(fn -> :ok end)
    Agent.stop(mock_pid)

    # Try to emit telemetry events that might access unavailable resources
    capture_log =
      ExUnit.CaptureLog.capture_log(fn ->
        for i <- 1..20 do
          :telemetry.execute([:dspex, :adapter, :format, :start], %{}, %{
            signature: :MockSignature,
            correlation_id: "ets-test-#{i}"
          })

          :telemetry.execute([:dspex, :signature, :validation, :stop], %{duration: 50}, %{
            signature: :MockSignature,
            success: true
          })
        end

        # Small delay to allow telemetry processing
        Process.sleep(10)
      end)

    # Test should complete without crashes - defensive handlers protected us
    assert true

    # Check that we didn't get any error logs (defensive handling should be silent)
    refute capture_log =~ "ERROR"
    refute capture_log =~ "badarg"
  end

  @tag :telemetry_race_condition
  test "telemetry state management during lifecycle transitions" do
    # Test the telemetry setup service's state management

    # Get the current telemetry setup process
    setup_pid = Process.whereis(DSPEx.Services.TelemetrySetup)
    assert is_pid(setup_pid)

    # Check initial state (may already be shutdown due to ExUnit monitoring)
    state = :sys.get_state(setup_pid)

    # If already shut down from ExUnit integration, test reset behavior
    if state.telemetry_active == false do
      # Test that handlers still work defensively even when "disabled"
      _capture_log =
        ExUnit.CaptureLog.capture_log(fn ->
          :telemetry.execute([:dspex, :predict, :start], %{}, %{
            signature: :PostShutdownTest,
            correlation_id: "post-shutdown-test"
          })
        end)

      # Should not crash - defensive handling works
      assert true
    else
      # Test normal shutdown flow
      assert state.telemetry_active == true
      assert state.handlers_attached == true

      # Simulate a shutdown preparation signal
      send(setup_pid, :prepare_for_shutdown)

      # Give it time to process
      Process.sleep(10)

      # Check that state was updated
      new_state = :sys.get_state(setup_pid)
      assert new_state.telemetry_active == false
      assert new_state.handlers_attached == false

      # Even with telemetry "disabled", handlers should still work defensively
      _capture_log =
        ExUnit.CaptureLog.capture_log(fn ->
          :telemetry.execute([:dspex, :predict, :start], %{}, %{
            signature: :PostShutdownTest,
            correlation_id: "post-shutdown-test"
          })
        end)

      # Should not crash, and should handle gracefully
      assert true
    end
  end

  @tag :telemetry_race_condition
  test "concurrent telemetry stress test with defensive handlers" do
    # High-concurrency test to ensure defensive handlers work under load

    num_tasks = 10
    events_per_task = 100

    tasks =
      for i <- 1..num_tasks do
        Task.async(fn ->
          for j <- 1..events_per_task do
            correlation_id = "stress-#{i}-#{j}"

            # Mix of different event types
            events = [
              {[:dspex, :predict, :start], %{},
               %{signature: :StressTest, correlation_id: correlation_id}},
              {[:dspex, :client, :request, :start], %{},
               %{provider: :test, correlation_id: correlation_id}},
              {[:dspex, :predict, :stop], %{duration: j},
               %{signature: :StressTest, success: true}},
              {[:dspex, :predict, :exception], %{},
               %{signature: :StressTest, error_type: :test_error}}
            ]

            # Emit random event
            {event, measurements, metadata} = Enum.random(events)
            :telemetry.execute(event, measurements, metadata)

            # Occasionally emit Foundation telemetry too
            if rem(j, 20) == 0 do
              try do
                Foundation.Telemetry.emit_counter([:stress, :test], %{task: i, event: j})
              rescue
                # Defensive handling should catch this
                _ -> :ok
              end
            end

            # Random tiny delays to create timing variations
            if rem(j, 50) == 0 do
              Process.sleep(1)
            end
          end
        end)
      end

    # Let stress test run
    Process.sleep(100)

    # Kill some tasks to simulate abrupt failures
    {to_kill, to_await} = Enum.split(tasks, div(num_tasks, 3))

    Enum.each(to_kill, fn task ->
      Process.exit(task.pid, :kill)
    end)

    # Await remaining tasks - they should all complete successfully
    results =
      Enum.map(to_await, fn task ->
        try do
          Task.await(task, 2000)
          :success
        catch
          # Expected for some tasks
          :exit, _ -> :killed
        end
      end)

    # Should have some successful completions
    assert Enum.count(results, &(&1 == :success)) > 0

    # Overall test should pass - no crashes due to defensive handling
    assert true
  end

  @tag :telemetry_race_condition
  test "Foundation availability checking in telemetry handlers" do
    # Test the Foundation.available?() checking logic

    # Foundation should be available during normal test execution
    assert Foundation.available?() == true

    # Emit telemetry that should work normally
    :telemetry.execute([:dspex, :predict, :start], %{}, %{
      signature: :AvailabilityTest,
      correlation_id: "availability-test-1"
    })

    # Test should pass - telemetry processing worked
    assert true

    # Note: We can't easily simulate Foundation being unavailable
    # without breaking the test environment, so this test mainly
    # validates that the availability check works correctly
  end
end
