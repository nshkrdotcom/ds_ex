#!/usr/bin/env elixir
Mix.install([{:foundation, "~> 0.1.3"}])

Application.ensure_all_started(:foundation)

IO.puts("🔍 Foundation Events Debug - Testing Different Call Patterns")
IO.puts("=" <> String.duplicate("=", 60))

# Test 1: Pipeline operator (from working script)
IO.puts("\n1. Testing pipeline operator approach:")
try do
  result1 = Foundation.Events.new_event(:test, %{data: "test"}, correlation_id: "test-123")
            |> Foundation.Events.store()
  IO.puts("✅ Pipeline approach: #{inspect(result1)}")
rescue
  error -> IO.puts("❌ Pipeline approach failed: #{inspect(error)}")
end

# Test 2: Variable assignment (from crashing script)
IO.puts("\n2. Testing variable assignment approach:")
try do
  correlation_id = "test-#{System.unique_integer([:positive])}"
  event_result = Foundation.Events.new_event(:test_event, %{test: "data", timestamp: DateTime.utc_now()}, correlation_id: correlation_id)
  IO.puts("   Event result: #{inspect(event_result)}")

  store_result = Foundation.Events.store(event_result)
  IO.puts("✅ Variable approach: #{inspect(store_result)}")
rescue
  error -> IO.puts("❌ Variable approach failed: #{inspect(error)}")
end

# Test 3: Pipeline with complex data (like crashing script)
IO.puts("\n3. Testing pipeline with complex data:")
try do
  correlation_id = "test-#{System.unique_integer([:positive])}"
  result3 = Foundation.Events.new_event(:test_event, %{test: "data", timestamp: DateTime.utc_now()}, correlation_id: correlation_id)
            |> Foundation.Events.store()
  IO.puts("✅ Pipeline + complex data: #{inspect(result3)}")
rescue
  error -> IO.puts("❌ Pipeline + complex data failed: #{inspect(error)}")
end

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Debug completed.")
