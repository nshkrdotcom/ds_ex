defmodule FoundationExUnitRaceTest do
  use ExUnit.Case, async: false
  
  test "Foundation telemetry during test lifecycle" do
    # Emit Foundation telemetry events
    for i <- 1..100 do
      Foundation.Telemetry.emit_counter([:test, :events], %{iteration: i})
      :telemetry.execute([:app, :test, :event], %{}, %{id: i})
    end
    
    # Spawn background telemetry during test cleanup
    spawn(fn ->
      Process.sleep(50)  # Hit cleanup window
      for j <- 1..10 do
        Foundation.Telemetry.emit_counter([:test, :cleanup], %{id: j})
        Process.sleep(5)
      end
    end)
    
    assert true  # Test will "pass" but crash during cleanup
  end
end
