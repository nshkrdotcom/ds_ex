#!/usr/bin/env elixir
Mix.install([{:foundation, "~> 0.1.3"}])

Application.ensure_all_started(:foundation)

IO.puts("🚨 Foundation Events API Bug Reproduction")
IO.puts("This WILL crash with function clause error...")

# This WILL crash - 100% reproducible
Foundation.Events.new_event(:test, %{data: "test"}, correlation_id: "test-123")
|> Foundation.Events.store()

IO.puts("✅ If you see this message, the bug is FIXED!")
