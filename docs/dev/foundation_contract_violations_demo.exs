#!/usr/bin/env elixir

Mix.install([
  {:foundation, "~> 0.1.1"}
])

defmodule FoundationContractViolationDemo do
  @moduledoc """
  Demonstrates Foundation v0.1.1 contract violations discovered during DSPEx integration.

  Run with: elixir foundation_contract_violations_demo.exs
  """

  require Logger

  def run do
    IO.puts("=== Foundation Contract Violations Demo ===\n")

    # Foundation should already be started by Mix.install
    IO.puts("Checking Foundation availability...")
    case Foundation.available?() do
      true -> IO.puts("✓ Foundation is available")
      false -> IO.puts("✗ Foundation not available")
    end

    # Wait for Foundation to be ready
    :timer.sleep(1000)

    demonstrate_config_violations()
    demonstrate_infrastructure_violations()
    demonstrate_telemetry_violations()
    demonstrate_events_violations()

    IO.puts("\n=== Summary ===")
    IO.puts("All demonstrated issues prevent Foundation from being used as intended.")
    IO.puts("Workarounds required for basic application configuration and infrastructure.")
  end

  defp demonstrate_config_violations do
    IO.puts("\n--- Config System Violations ---")

    # Violation 1: Cannot set application config at runtime
    IO.puts("1. Testing runtime config updates for application namespace...")
    case Foundation.Config.update([:myapp], %{feature: "enabled"}) do
      :ok ->
        IO.puts("✓ Unexpected success - this should work")
      {:error, %Foundation.Types.Error{error_type: :config_update_forbidden} = error} ->
        IO.puts("✗ VIOLATION: #{error.message}")
        IO.puts("   Expected: Should allow application config updates")
        IO.puts("   Actual: Only allows pre-defined system paths")
    end

    # Violation 2: Setting nested paths doesn't create intermediate maps
    IO.puts("\n2. Testing nested path creation...")
    # First try to set individual nested values
    Foundation.Config.update([:myapp, :database, :host], "localhost")
    Foundation.Config.update([:myapp, :database, :port], 5432)

    # Then try to retrieve the intermediate map
    case Foundation.Config.get([:myapp, :database]) do
      {:ok, config} ->
        IO.puts("✓ Nested config retrieved: #{inspect(config)}")
      {:error, %Foundation.Types.Error{error_type: :config_path_not_found} = error} ->
        IO.puts("✗ VIOLATION: #{error.message}")
        IO.puts("   Expected: Setting nested paths should create intermediate maps")
        IO.puts("   Actual: Can set leaves but can't retrieve intermediate maps")
    end
  end

  defp demonstrate_infrastructure_violations do
    IO.puts("\n--- Infrastructure API Violations ---")

    # Violation 3: execute_protected circuit breaker not found
    IO.puts("1. Testing infrastructure protection...")
    try do
      result = Foundation.Infrastructure.execute_protected(
        {:demo_service, :test},
        [circuit_breaker: :demo_breaker, rate_limiter: {:demo, "user1"}],
        fn -> {:ok, "success"} end
      )
      IO.puts("Result: #{inspect(result)}")
    rescue
      error ->
        IO.puts("✗ VIOLATION: Infrastructure protection failed")
        IO.puts("   Error: #{inspect(error)}")
        IO.puts("   Expected: Should provide circuit breaker protection")
        IO.puts("   Actual: Circuit breakers not initialized/available")
    end

    # Violation 4: initialize_circuit_breaker undefined
    IO.puts("\n2. Testing circuit breaker initialization...")
    try do
      Foundation.Infrastructure.initialize_circuit_breaker(:demo_breaker, %{
        failure_threshold: 5,
        recovery_time: 30_000
      })
      IO.puts("✓ Circuit breaker initialized")
    rescue
      UndefinedFunctionError ->
        IO.puts("✗ VIOLATION: Foundation.Infrastructure.initialize_circuit_breaker/2 undefined")
        IO.puts("   Expected: Should provide circuit breaker initialization")
        IO.puts("   Actual: Function doesn't exist")
    end
  end

  defp demonstrate_telemetry_violations do
    IO.puts("\n--- Telemetry API Violations ---")

    # Violation 5: Telemetry helper methods undefined
    helpers = [
      {:emit_histogram, 3},
      {:emit_counter, 2},
      {:emit_gauge, 3}
    ]

    Enum.each(helpers, fn {func, arity} ->
      IO.puts("Testing Foundation.Telemetry.#{func}/#{arity}...")
      try do
        case func do
          :emit_histogram ->
            Foundation.Telemetry.emit_histogram([:demo, :duration], 100, %{})
          :emit_counter ->
            Foundation.Telemetry.emit_counter([:demo, :requests], %{})
          :emit_gauge ->
            Foundation.Telemetry.emit_gauge([:demo, :memory], 1024, %{})
        end
        IO.puts("✓ Function exists and works")
      rescue
        UndefinedFunctionError ->
          IO.puts("✗ VIOLATION: Foundation.Telemetry.#{func}/#{arity} undefined")
          IO.puts("   Expected: Should provide telemetry helper methods")
          IO.puts("   Actual: Must use standard :telemetry.execute/3 directly")
      end
    end)
  end

  defp demonstrate_events_violations do
    IO.puts("\n--- Events API Violations ---")

    # Violation 6: Event validation expects wrong format
    IO.puts("Testing event creation and storage...")
    correlation_id = Foundation.Utils.generate_correlation_id()

    try do
      event_result = Foundation.Events.new_event(:demo_event, %{
        action: "test",
        timestamp: DateTime.utc_now()
      }, correlation_id: correlation_id)

      IO.puts("Event creation result: #{inspect(event_result)}")

      case event_result do
        {:ok, event} ->
          # Try to store the event
          case Foundation.Events.store(event) do
            {:ok, event_id} ->
              IO.puts("✓ Event stored successfully: #{event_id}")
            {:error, reason} ->
              IO.puts("✗ VIOLATION: Event storage failed")
              IO.puts("   Error: #{inspect(reason)}")
              IO.puts("   Expected: Should store events successfully")
              IO.puts("   Actual: Event validation failures")
          end
        error ->
          IO.puts("✗ Event creation failed: #{inspect(error)}")
      end
    rescue
      error ->
        IO.puts("✗ VIOLATION: Events API failed")
        IO.puts("   Error: #{inspect(error)}")
        IO.puts("   Expected: Should provide reliable event storage")
        IO.puts("   Actual: GenServer crashes and validation issues")
    end
  end
end

# Run the demo
FoundationContractViolationDemo.run()
