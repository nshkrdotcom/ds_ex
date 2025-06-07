#!/usr/bin/env elixir

Mix.install([
  {:foundation, "~> 0.1.3"}
])

# Start Foundation application
Application.ensure_all_started(:foundation)

IO.puts("Testing Foundation Events API v0.1.3...")
IO.puts("=" <> String.duplicate("=", 50))

# Try to create and store a simple event
correlation_id = "test-#{System.unique_integer([:positive])}"

IO.puts("1. Creating event with correlation_id: #{correlation_id}")

try do
  event_result = Foundation.Events.new_event(:test_event, %{test: "data", timestamp: DateTime.utc_now()}, correlation_id: correlation_id)

  IO.puts("2. Event creation result: #{inspect(event_result)}")

  IO.puts("3. Attempting to store event...")

  store_result = Foundation.Events.store(event_result)

  IO.puts("✅ Event stored successfully: #{inspect(store_result)}")
rescue
  error ->
    IO.puts("❌ Event storage failed with error: #{inspect(error)}")
    IO.puts("\nError details:")
    IO.puts("- Type: #{error.__struct__}")
    IO.puts("- Message: #{Exception.message(error)}")

    if Map.has_key?(error, :stacktrace) do
      IO.puts("- Stacktrace: #{inspect(error.stacktrace)}")
    end
catch
  kind, reason ->
    IO.puts("❌ Event storage failed with #{kind}: #{inspect(reason)}")
end

IO.puts("\n" <> String.duplicate("=", 50))
IO.puts("Test completed.")
