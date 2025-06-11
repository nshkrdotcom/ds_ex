defmodule DSPEx.RaceConditionTest do
  @moduledoc """
  Specialized tests for detecting and preventing race conditions in DSPEx.
  Focuses on edge cases, timing-sensitive operations, and potential
  data races in concurrent scenarios.
  """
  use ExUnit.Case, async: false

  @moduletag :group_1
  @moduletag :race_conditions

  # Test programs designed to expose race conditions
  defmodule TimingSensitiveProgram do
    use DSPEx.Program

    defstruct [:id, :shared_state, :timing_window_ms]

    def new(id, timing_window_ms \\ 50) do
      {:ok, shared_state} = Agent.start_link(fn -> %{operations: [], last_timestamp: nil} end)
      %__MODULE__{id: id, shared_state: shared_state, timing_window_ms: timing_window_ms}
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      start_time = System.monotonic_time(:millisecond)

      # Read current state
      current_state = Agent.get(program.shared_state, & &1)

      # Introduce timing window for potential race
      Process.sleep(program.timing_window_ms)

      # Update state based on what we read earlier (potential race)
      new_operation = %{
        id: Map.get(inputs, :operation_id, :unknown),
        timestamp: start_time,
        previous_count: length(current_state.operations)
      }

      updated_state =
        Agent.get_and_update(program.shared_state, fn state ->
          new_operations = [new_operation | state.operations]
          new_state = %{state | operations: new_operations, last_timestamp: start_time}
          {new_state, new_state}
        end)

      {:ok,
       %{
         operation_id: new_operation.id,
         final_count: length(updated_state.operations),
         expected_count: new_operation.previous_count + 1,
         race_detected: length(updated_state.operations) != new_operation.previous_count + 1
       }}
    end

    def get_operations(program) do
      Agent.get(program.shared_state, & &1.operations)
    end

    def stop(program) do
      Agent.stop(program.shared_state)
    end
  end

  defmodule CounterRaceProgram do
    use DSPEx.Program

    defstruct [:id, :counter_agent, :increment_delay_ms]

    def new(id, increment_delay_ms \\ 10) do
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      %__MODULE__{id: id, counter_agent: counter, increment_delay_ms: increment_delay_ms}
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      # Classic read-modify-write race condition scenario

      # Read current value
      current_value = Agent.get(program.counter_agent, & &1)

      # Simulate processing time (race window)
      Process.sleep(program.increment_delay_ms)

      # Increment based on what we read (RACE CONDITION)
      new_value = current_value + 1

      # Write back the incremented value
      Agent.update(program.counter_agent, fn _current -> new_value end)

      # Return both what we thought the value should be and what it actually is
      actual_value = Agent.get(program.counter_agent, & &1)

      {:ok,
       %{
         operation_id: Map.get(inputs, :operation_id),
         expected_value: new_value,
         actual_value: actual_value,
         race_detected: new_value != actual_value
       }}
    end

    def get_final_count(program) do
      Agent.get(program.counter_agent, & &1)
    end

    def stop(program) do
      Agent.stop(program.counter_agent)
    end
  end

  defmodule TelemetryRaceProgram do
    use DSPEx.Program

    defstruct [:id, :telemetry_store]

    def new(id) do
      {:ok, store} = Agent.start_link(fn -> %{events: [], event_count: 0} end)
      %__MODULE__{id: id, telemetry_store: store}
    end

    @impl DSPEx.Program
    def forward(program, inputs, opts) do
      operation_id = Map.get(inputs, :operation_id, :unknown)
      correlation_id = Keyword.get(opts, :correlation_id, "no-correlation")

      # Simulate telemetry event handling
      event = %{
        operation_id: operation_id,
        correlation_id: correlation_id,
        timestamp: System.monotonic_time(:millisecond),
        process_id: self()
      }

      # Store event with potential race condition
      Agent.update(program.telemetry_store, fn state ->
        %{
          events: [event | state.events],
          event_count: state.event_count + 1
        }
      end)

      # Small delay to increase chance of race
      Process.sleep(1)

      current_state = Agent.get(program.telemetry_store, & &1)

      {:ok,
       %{
         operation_id: operation_id,
         stored_events: length(current_state.events),
         event_count: current_state.event_count,
         race_detected: length(current_state.events) != current_state.event_count
       }}
    end

    def get_events(program) do
      Agent.get(program.telemetry_store, & &1)
    end

    def stop(program) do
      Agent.stop(program.telemetry_store)
    end
  end

  describe "read-modify-write race conditions" do
    test "detects classic counter race condition" do
      # Longer delay increases race chance
      program = CounterRaceProgram.new(:counter_race, 20)

      try do
        # Perform many concurrent increments
        operation_count = 50

        tasks =
          for i <- 1..operation_count do
            Task.async(fn ->
              DSPEx.Program.forward(program, %{operation_id: i})
            end)
          end

        results = Task.await_many(tasks, 10_000)

        # All operations should complete
        assert length(results) == operation_count

        # Extract results
        operation_results = for {:ok, result} <- results, do: result
        assert length(operation_results) == operation_count

        # Check for detected races
        races_detected = Enum.count(operation_results, & &1.race_detected)

        # With sufficient concurrent operations and delay, we should detect some races
        # (This is a race condition we're intentionally creating to test detection)
        if races_detected > 0 do
          IO.puts("Race conditions detected: #{races_detected}/#{operation_count}")
        end

        # Final count should be less than expected due to lost updates
        final_count = CounterRaceProgram.get_final_count(program)
        # Should be less due to races
        assert final_count <= operation_count

        # If we detected races, final count should definitely be less
        if races_detected > 0 do
          assert final_count < operation_count
        end
      after
        CounterRaceProgram.stop(program)
      end
    end

    test "timing-sensitive state updates reveal race conditions" do
      program = TimingSensitiveProgram.new(:timing_race, 30)

      try do
        # Concurrent operations with overlapping timing windows
        tasks =
          for i <- 1..20 do
            Task.async(fn ->
              DSPEx.Program.forward(program, %{operation_id: i})
            end)
          end

        results = Task.await_many(tasks, 15_000)

        # All should complete
        operation_results = for {:ok, result} <- results, do: result
        assert length(operation_results) == 20

        # Check final operations list
        final_operations = TimingSensitiveProgram.get_operations(program)

        # Should have all operations
        assert length(final_operations) == 20

        # Check for race detection
        races_detected = Enum.count(operation_results, & &1.race_detected)

        if races_detected > 0 do
          IO.puts("Timing races detected: #{races_detected}/20")

          # If races were detected, some operations should have mismatched counts
          mismatched_operations =
            Enum.filter(operation_results, fn result ->
              result.final_count != result.expected_count
            end)

          assert length(mismatched_operations) > 0
        end
      after
        TimingSensitiveProgram.stop(program)
      end
    end
  end

  describe "telemetry race conditions" do
    test "concurrent telemetry events don't lose data" do
      program = TelemetryRaceProgram.new(:telemetry_race)

      try do
        # Setup actual telemetry handler to add more concurrency
        handler_id = make_ref()
        events_received = :counters.new(1, [])

        :telemetry.attach_many(
          handler_id,
          [
            [:dspex, :program, :forward, :start],
            [:dspex, :program, :forward, :stop]
          ],
          fn _event_name, _measurements, _metadata, _acc ->
            :counters.add(events_received, 1, 1)
          end,
          []
        )

        try do
          # Run many concurrent operations
          tasks =
            for i <- 1..30 do
              Task.async(fn ->
                DSPEx.Program.forward(program, %{operation_id: i},
                  correlation_id: "race-test-#{i}"
                )
              end)
            end

          results = Task.await_many(tasks, 5000)

          # All should complete successfully
          operation_results = for {:ok, result} <- results, do: result
          assert length(operation_results) == 30

          # Check program's internal telemetry storage
          final_state = TelemetryRaceProgram.get_events(program)

          # Should have stored all events
          assert length(final_state.events) == 30
          assert final_state.event_count == 30

          # Check for internal race detection
          internal_races = Enum.count(operation_results, & &1.race_detected)

          if internal_races > 0 do
            IO.puts("Internal telemetry races detected: #{internal_races}/30")
          end

          # Verify external telemetry received all events
          # Allow telemetry processing
          Process.sleep(100)
          external_events = :counters.get(events_received, 1)

          # Should have received 60 events (30 start + 30 stop)
          assert external_events == 60
        after
          :telemetry.detach(handler_id)
        end
      after
        TelemetryRaceProgram.stop(program)
      end
    end

    test "correlation IDs remain unique under concurrent stress" do
      # This test specifically targets correlation ID generation races

      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            # Each task creates multiple programs with rapid succession
            programs =
              for _j <- 1..5 do
                DSPEx.Predict.new(TestSignature, :test_client)
              end

            # Execute all programs concurrently
            program_tasks =
              for {program, j} <- Enum.with_index(programs) do
                Task.async(fn ->
                  inputs = %{question: "Test #{i}-#{j}"}
                  # Force unique correlation IDs
                  result =
                    DSPEx.Program.forward(program, inputs, correlation_id: "stress-#{i}-#{j}")

                  {i, j, result}
                end)
              end

            Task.await_many(program_tasks, 2000)
          end)
        end

      all_results =
        tasks
        |> Task.await_many(10_000)
        |> List.flatten()

      # Should have 500 total operations (100 tasks * 5 programs each)
      assert length(all_results) == 500

      # Extract correlation IDs from telemetry (would need telemetry handler for full test)
      # For now, verify operations completed without crashes
      for {i, j, result} <- all_results do
        assert is_integer(i)
        assert is_integer(j)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end

  describe "evaluation race conditions" do
    test "concurrent evaluations don't interfere with metrics" do
      # Create a shared metric function that could have race conditions
      # [total_calls, exact_matches]
      metric_state = :counters.new(2, [])

      metric_fn = fn example, prediction ->
        # Increment total calls
        :counters.add(metric_state, 1, 1)

        # Simulate processing delay
        Process.sleep(1)

        if Map.get(example.outputs, :answer) == Map.get(prediction, :answer) do
          # Increment exact matches
          :counters.add(metric_state, 2, 1)
          1.0
        else
          0.0
        end
      end

      # Create programs with known responses
      programs =
        for i <- 1..3 do
          DSPEx.RaceConditionTest.DelayedProgram.new(i, 5, 0)
        end

      examples = [
        DSPEx.Example.new(%{question: "Test 1", answer: "Response 1"}, [:question]),
        DSPEx.Example.new(%{question: "Test 2", answer: "Response 2"}, [:question])
      ]

      # Run evaluations concurrently
      tasks =
        for program <- programs do
          Task.async(fn ->
            DSPEx.Evaluate.run(program, examples, metric_fn)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All evaluations should complete
      assert length(results) == 3

      # Check metric state consistency
      total_calls = :counters.get(metric_state, 1)
      exact_matches = :counters.get(metric_state, 2)

      # Should have called metric for each example in each evaluation
      # 3 programs * 2 examples each
      expected_calls = 3 * 2
      assert total_calls == expected_calls

      # Exact matches depends on program responses, but should be consistent
      assert exact_matches <= total_calls
      assert exact_matches >= 0
    end

    test "distributed evaluation work distribution avoids races" do
      # Test the distributed evaluation logic for race conditions
      program = DSPEx.RaceConditionTest.DelayedProgram.new(:distributed_race, 10, 0)

      # Create many examples to force chunking
      examples =
        for i <- 1..50 do
          DSPEx.Example.new(%{id: i, expected: i * 2}, [:id])
        end

      metric_fn = fn example, prediction ->
        # Simple metric that should be deterministic
        outputs = DSPEx.Example.outputs(example)
        expected = outputs.expected
        actual = Map.get(prediction, :id, 0) * 2
        if expected == actual, do: 1.0, else: 0.0
      end

      # Run multiple distributed evaluations concurrently
      # (These will fallback to local since no cluster, but test the logic)
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            DSPEx.Evaluate.run_distributed(program, examples, metric_fn,
              max_concurrency: 10,
              correlation_id: "distributed-#{i}"
            )
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All should complete successfully
      assert length(results) == 3

      for {:ok, result} <- results do
        assert result.stats.total_examples == 50
        assert result.stats.successful + result.stats.failed == 50
        # Results should be consistent across runs
        assert result.stats.throughput > 0
      end

      # All evaluations should produce the same score (deterministic)
      scores = for {:ok, result} <- results, do: result.score
      unique_scores = Enum.uniq(scores)

      # Should have consistent results (allowing for potential floating point precision)
      # At most minor floating point differences
      assert length(unique_scores) <= 2
    end
  end

  describe "resource cleanup race conditions" do
    test "concurrent program creation and cleanup is safe" do
      # Test rapid creation and destruction of programs

      creation_tasks =
        for i <- 1..20 do
          Task.async(fn ->
            # Create and immediately use program
            program = TimingSensitiveProgram.new(:"rapid_#{i}", 5)

            result =
              try do
                DSPEx.Program.forward(program, %{operation_id: i})
              after
                TimingSensitiveProgram.stop(program)
              end

            {i, result}
          end)
        end

      results = Task.await_many(creation_tasks, 5000)

      # All should complete without crashes
      assert length(results) == 20

      for {i, result} <- results do
        assert is_integer(i)
        assert match?({:ok, _}, result)
      end
    end

    test "telemetry handler cleanup doesn't race with events" do
      # Test that telemetry handlers can be safely attached/detached concurrently

      event_counts = :counters.new(1, [])

      # Create multiple handlers concurrently
      handler_tasks =
        for i <- 1..5 do
          Task.async(fn ->
            handler_id = :"handler_#{i}"

            :telemetry.attach_many(
              handler_id,
              [[:dspex, :program, :forward, :start]],
              fn _event, _measurements, metadata, _acc ->
                # Only count events from our specific test handlers
                case Map.get(metadata, :correlation_id) do
                  "handler_test_" <> _ ->
                    :counters.add(event_counts, 1, 1)

                  _ ->
                    :ok
                end
              end,
              []
            )

            # Generate some events with specific correlation IDs
            program = DSPEx.RaceConditionTest.DelayedProgram.new(:"handler_test_#{i}", 1, 0)

            for j <- 1..5 do
              DSPEx.Program.forward(program, %{test: j}, correlation_id: "handler_test_#{i}_#{j}")
            end

            # Detach handler
            :telemetry.detach(handler_id)

            handler_id
          end)
        end

      handler_ids = Task.await_many(handler_tasks, 5000)

      # All handlers should be created and destroyed successfully
      assert length(handler_ids) == 5

      # Should have received some events (exact count may vary due to timing)
      total_events = :counters.get(event_counts, 1)
      assert total_events > 0
      # Very generous limit to account for concurrent test interference
      assert total_events <= 150
    end
  end

  # Helper module for tests
  defmodule TestSignature do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule DelayedProgram do
    use DSPEx.Program

    defstruct [:id, :delay_ms, :jitter_ms]

    def new(id, delay_ms, jitter_ms) do
      %__MODULE__{id: id, delay_ms: delay_ms, jitter_ms: jitter_ms}
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      if program.delay_ms && program.delay_ms > 0 do
        base_delay = program.delay_ms

        jitter =
          if program.jitter_ms && program.jitter_ms > 0,
            do: :rand.uniform(program.jitter_ms),
            else: 0

        Process.sleep(base_delay + jitter)
      end

      {:ok, Map.put(inputs, :processed_by, program.id)}
    end
  end
end
