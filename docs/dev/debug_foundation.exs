#!/usr/bin/env elixir

# Debug script to understand Foundation.Infrastructure.execute_protected behavior

Mix.install([
  {:foundation, "~> 0.1.2"}
])

# Start Foundation application
Application.ensure_all_started(:foundation)

# Initialize a test circuit breaker
Foundation.Infrastructure.initialize_circuit_breaker(:test_breaker, %{
  failure_threshold: 5,
  recovery_time: 30_000
})

# Test function that returns {:ok, data}
test_function = fn ->
  {:ok, %{test: "data"}}
end

# Test Foundation's execute_protected
result = Foundation.Infrastructure.execute_protected(
  {:test_client, :test_provider},
  [circuit_breaker: :test_breaker],
  test_function
)

IO.puts("Function returns: #{inspect({:ok, %{test: "data"}})}")
IO.puts("Foundation execute_protected returns: #{inspect(result)}")

# Test with error
error_function = fn ->
  {:error, :test_error}
end

error_result = Foundation.Infrastructure.execute_protected(
  {:test_client, :test_provider},
  [circuit_breaker: :test_breaker],
  error_function
)

IO.puts("Error function returns: #{inspect({:error, :test_error})}")
IO.puts("Foundation execute_protected error returns: #{inspect(error_result)}")
