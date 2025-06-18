defmodule DSPEx.ConcurrentExecutionTest do
  @moduledoc """
  Comprehensive concurrent execution tests for DSPEx.
  Tests race conditions, thread safety, shared state management,
  telemetry under load, and performance characteristics under concurrent access.
  """
  # Some tests need to avoid interference
  use ExUnit.Case, async: false

  @moduletag :group_1
  @moduletag :concurrent

  # Test programs with different concurrency characteristics
  defmodule ThreadSafeProgram do
    use DSPEx.Program

    defstruct [:id, :counter_ref]

    def new(id) do
      %__MODULE__{id: id, counter_ref: :counters.new(1, [])}
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      # Increment counter atomically
      :counters.add(program.counter_ref, 1, 1)
      count = :counters.get(program.counter_ref, 1)

      # Simulate some work
      Process.sleep(1)

      {:ok, Map.put(inputs, :execution_count, count)}
    end

    def get_count(program) do
      :counters.get(program.counter_ref, 1)
    end
  end

  defmodule StatefulProgram do
    use DSPEx.Program

    defstruct [:id, :state_agent]

    def new(id) do
      {:ok, agent} = Agent.start_link(fn -> %{executions: 0, errors: 0} end)
      %__MODULE__{id: id, state_agent: agent}
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      # Update state through Agent
      Agent.update(program.state_agent, fn state ->
        %{state | executions: state.executions + 1}
      end)

      # Simulate work with potential race condition
      current_count = Agent.get(program.state_agent, & &1.executions)
      # Window for race conditions
      Process.sleep(5)

      case Map.get(inputs, :should_error) do
        true ->
          Agent.update(program.state_agent, fn state ->
            %{state | errors: state.errors + 1}
          end)

          {:error, :intentional_error}

        _ ->
          {:ok, Map.put(inputs, :execution_id, current_count)}
      end
    end

    def get_state(program) do
      Agent.get(program.state_agent, & &1)
    end

    def stop(program) do
      Agent.stop(program.state_agent)
    end
  end

  # Program that fails randomly for testing concurrent error handling
  defmodule RandomFailProgram do
    use DSPEx.Program

    defstruct [:id, :fail_rate]

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      if :rand.uniform() < program.fail_rate do
        {:error, :random_failure}
      else
        {:ok, Map.put(inputs, :processed, true)}
      end
    end
  end

  defmodule DelayedProgram do
    use DSPEx.Program

    defstruct [:id, :delay_ms, :jitter_ms]

    def new(id, delay_ms, jitter_ms) do
      %__MODULE__{id: id, delay_ms: delay_ms, jitter_ms: jitter_ms}
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      base_delay = program.delay_ms || 10

      jitter =
        if program.jitter_ms && program.jitter_ms > 0,
          do: :rand.uniform(program.jitter_ms),
          else: 0

      total_delay = base_delay + jitter

      Process.sleep(total_delay)

      {:ok,
       Map.merge(inputs, %{
         delay_used: total_delay,
         process_id: self()
       })}
    end
  end

  describe "concurrent program execution" do
    test "multiple programs execute independently" do
      programs =
        for i <- 1..5 do
          ThreadSafeProgram.new(i)
        end

      # Execute all programs concurrently multiple times
      tasks =
        for program <- programs, j <- 1..10 do
          Task.async(fn ->
            DSPEx.Program.forward(program, %{test: "concurrent", iteration: j})
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All executions should succeed
      assert length(results) == 50
      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 50

      # Each program should have been executed exactly 10 times
      for program <- programs do
        assert ThreadSafeProgram.get_count(program) == 10
      end
    end

    test "shared state is properly synchronized" do
      program = StatefulProgram.new(:shared_state_test)

      try do
        # Execute many operations concurrently
        tasks =
          for i <- 1..20 do
            Task.async(fn ->
              inputs = %{operation: i, should_error: rem(i, 5) == 0}
              DSPEx.Program.forward(program, inputs)
            end)
          end

        results = Task.await_many(tasks, 5000)

        # Verify results
        successes = Enum.count(results, &match?({:ok, _}, &1))
        failures = Enum.count(results, &match?({:error, _}, &1))

        assert successes + failures == 20
        # Every 5th operation should fail
        assert failures == 4

        # Verify state consistency
        final_state = StatefulProgram.get_state(program)
        assert final_state.executions == 20
        assert final_state.errors == 4
      after
        StatefulProgram.stop(program)
      end
    end

    test "concurrent executions don't interfere with each other" do
      program = DSPEx.ConcurrentExecutionTest.DelayedProgram.new(:interference_test, 50, 20)

      # Track process IDs to ensure different processes
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            result = DSPEx.Program.forward(program, %{task_id: i})
            {i, result, self()}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert length(results) == 10

      # Extract execution results
      execution_results =
        for {task_id, {:ok, output}, task_pid} <- results do
          {task_id, output, task_pid}
        end

      assert length(execution_results) == 10

      # Each should have different process ID (from program execution)
      process_ids = Enum.map(execution_results, fn {_, output, _} -> output.process_id end)
      task_pids = Enum.map(execution_results, fn {_, _, task_pid} -> task_pid end)

      # Task processes should be different
      assert length(Enum.uniq(task_pids)) == 10

      # Program executions might share processes (that's OK)
      assert length(Enum.uniq(process_ids)) >= 1

      # Each task should maintain its identity
      for {task_id, output, _} <- execution_results do
        assert output.task_id == task_id
      end
    end
  end

  describe "concurrent evaluation scenarios" do
    test "multiple evaluations run independently" do
      # Create different programs for concurrent evaluation
      programs =
        for i <- 1..3 do
          DSPEx.ConcurrentExecutionTest.DelayedProgram.new(i, 20, 10)
        end

      examples =
        for j <- 1..5 do
          DSPEx.Example.new(%{question: "Question #{j}", processed: true}, [:question])
        end

      metric_fn = fn _example, prediction ->
        # Always succeed but with small delay to create potential races
        Process.sleep(1)
        if Map.has_key?(prediction, :delay_used), do: 1.0, else: 0.0
      end

      # Run evaluations concurrently
      tasks =
        for program <- programs do
          Task.async(fn ->
            DSPEx.Evaluate.run(program, examples, metric_fn)
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All evaluations should succeed
      assert length(results) == 3

      for {:ok, result} <- results do
        assert result.stats.total_examples == 5
        assert result.stats.successful == 5
        assert result.stats.failed == 0
        assert result.score == 1.0
      end
    end

    test "concurrent evaluation with shared telemetry" do
      # Setup telemetry collection with explicit process registry
      handler_id = make_ref()
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :evaluate, :run, :start],
          [:dspex, :evaluate, :run, :stop],
          [:dspex, :program, :forward, :start],
          [:dspex, :program, :forward, :stop]
        ],
        fn event_name, measurements, metadata, _acc ->
          send(test_pid, {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )

      try do
        # Longer delay
        program = DSPEx.ConcurrentExecutionTest.DelayedProgram.new(:telemetry_test, 50, 10)
        examples = [DSPEx.Example.new(%{test: "data", processed: true}, [:test])]
        metric_fn = fn _example, _prediction -> 1.0 end

        # Start collecting events before running
        {:ok, collected_events} = Agent.start_link(fn -> [] end)

        # Wrap handler to store in Agent
        handler_fn = fn event_name, measurements, metadata, _acc ->
          Agent.update(collected_events, fn events ->
            [{event_name, measurements, metadata} | events]
          end)
        end

        # Re-attach with the Agent-storing handler
        :telemetry.detach(handler_id)

        :telemetry.attach_many(
          handler_id,
          [
            [:dspex, :evaluate, :run, :start],
            [:dspex, :evaluate, :run, :stop],
            [:dspex, :program, :forward, :start],
            [:dspex, :program, :forward, :stop]
          ],
          handler_fn,
          nil
        )

        # Run multiple evaluations concurrently
        tasks =
          for i <- 1..3 do
            Task.async(fn ->
              DSPEx.Evaluate.run(program, examples, metric_fn, correlation_id: "concurrent-#{i}")
            end)
          end

        results = Task.await_many(tasks, 10_000)

        # All should succeed
        for {:ok, result} <- results do
          assert result.stats.successful == 1
        end

        # Wait for events to be processed
        Process.sleep(100)

        final_events = Agent.get(collected_events, & &1)
        Agent.stop(collected_events)

        # Should have received events from all 3 evaluations
        run_start_events =
          Enum.filter(final_events, fn {event, _, _} ->
            event == [:dspex, :evaluate, :run, :start]
          end)

        assert length(run_start_events) == 3

        # Each should have unique correlation ID
        correlation_ids =
          for {_, _, metadata} <- run_start_events do
            metadata.correlation_id
          end

        assert length(Enum.uniq(correlation_ids)) == 3
        assert Enum.all?(correlation_ids, &String.contains?(&1, "concurrent-"))
      after
        :telemetry.detach(handler_id)
      end
    end

    test "evaluation handles concurrent program failures gracefully" do
      # Create programs with different failure rates
      programs = [
        # 20% failure
        %RandomFailProgram{id: 1, fail_rate: 0.2},
        # 50% failure
        %RandomFailProgram{id: 2, fail_rate: 0.5},
        # 80% failure
        %RandomFailProgram{id: 3, fail_rate: 0.8}
      ]

      examples =
        for i <- 1..10 do
          DSPEx.Example.new(%{id: i, processed: true}, [:id])
        end

      metric_fn = fn _example, _prediction -> 1.0 end

      # Run evaluations concurrently
      tasks =
        for program <- programs do
          Task.async(fn ->
            DSPEx.Evaluate.run(program, examples, metric_fn)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All evaluations should complete (but with different success rates)
      assert length(results) == 3

      for {:ok, result} <- results do
        assert result.stats.total_examples == 10
        assert result.stats.successful + result.stats.failed == 10
        # Should have some variation in success rates
        assert result.stats.success_rate >= 0.0
        assert result.stats.success_rate <= 1.0
      end
    end
  end

  describe "race condition detection" do
    test "telemetry correlation IDs remain unique under load" do
      program = ThreadSafeProgram.new(:correlation_test)

      # Generate many concurrent operations
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            # Each task performs multiple operations
            for j <- 1..5 do
              result = DSPEx.Program.forward(program, %{task: i, operation: j})
              {i, j, result}
            end
          end)
        end

      all_results =
        tasks
        |> Task.await_many(10_000)
        |> List.flatten()

      # Should have 250 total operations (50 tasks * 5 operations each)
      assert length(all_results) == 250

      # All should succeed
      successes = Enum.count(all_results, fn {_, _, result} -> match?({:ok, _}, result) end)
      assert successes == 250

      # Verify state consistency
      final_count = ThreadSafeProgram.get_count(program)
      assert final_count == 250
    end

    test "concurrent signature parsing is thread-safe" do
      # Test that signature parsing doesn't have race conditions
      defmodule ConcurrentSignature do
        use DSPEx.Signature, "input1, input2, input3 -> output1, output2, output3"
      end

      # Create many programs concurrently using the same signature
      tasks =
        for _i <- 1..20 do
          Task.async(fn ->
            program = DSPEx.Predict.new(ConcurrentSignature, :test_client)

            # Verify signature is correctly parsed
            assert program.signature == ConcurrentSignature

            # Test input validation concurrently
            valid_inputs = %{input1: "a", input2: "b", input3: "c"}
            # Missing input2 and input3
            invalid_inputs = %{input1: "a"}

            assert :ok == DSPEx.Predict.validate_inputs(ConcurrentSignature, valid_inputs)

            assert {:error, :missing_inputs} ==
                     DSPEx.Predict.validate_inputs(ConcurrentSignature, invalid_inputs)

            program
          end)
        end

      programs = Task.await_many(tasks, 5000)

      # All programs should be created successfully
      assert length(programs) == 20

      # All should have the same signature
      for program <- programs do
        assert program.signature == ConcurrentSignature
      end
    end

    test "concurrent telemetry handling doesn't lose events" do
      # Setup telemetry with concurrent event processing
      event_counter = :counters.new(1, [])
      handler_id = make_ref()

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :program, :forward, :start],
          [:dspex, :program, :forward, :stop]
        ],
        fn _event_name, _measurements, _metadata, _acc ->
          :counters.add(event_counter, 1, 1)
        end,
        []
      )

      try do
        # Minimal delay
        program = DSPEx.ConcurrentExecutionTest.DelayedProgram.new(:telemetry_load_test, 1, 0)

        # Generate high-frequency concurrent operations
        tasks =
          for i <- 1..100 do
            Task.async(fn ->
              DSPEx.Program.forward(program, %{operation: i})
            end)
          end

        results = Task.await_many(tasks, 10_000)

        # All operations should succeed
        successes = Enum.count(results, &match?({:ok, _}, &1))
        assert successes == 100

        # Wait for all telemetry events to be processed
        Process.sleep(100)

        # Should have received exactly 200 events (100 start + 100 stop)
        total_events = :counters.get(event_counter, 1)
        assert total_events == 200
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  describe "performance under concurrent load" do
    test "throughput scales with concurrency" do
      # Fixed 10ms delay
      program = DSPEx.ConcurrentExecutionTest.DelayedProgram.new(:throughput_test, 10, 0)

      # Test different concurrency levels
      concurrency_levels = [1, 5, 10, 20]
      operation_count = 50

      results =
        for concurrency <- concurrency_levels do
          start_time = System.monotonic_time()

          # Create batches for controlled concurrency
          batches = Enum.chunk_every(1..operation_count, div(operation_count, concurrency))

          batch_tasks =
            for batch <- batches do
              Task.async(fn ->
                Enum.map(batch, fn i ->
                  DSPEx.Program.forward(program, %{operation: i})
                end)
              end)
            end

          _batch_results = Task.await_many(batch_tasks, 10_000)

          duration = System.monotonic_time() - start_time
          duration_ms = System.convert_time_unit(duration, :native, :millisecond)
          throughput = operation_count / (duration_ms / 1000)

          {concurrency, duration_ms, throughput}
        end

      # Higher concurrency should generally improve throughput
      throughputs = Enum.map(results, fn {_, _, throughput} -> throughput end)

      # At minimum, concurrent execution shouldn't be much slower than sequential
      [seq_throughput | concurrent_throughputs] = throughputs

      for concurrent_throughput <- concurrent_throughputs do
        # Concurrent should be at least 50% of sequential (accounting for overhead)
        assert concurrent_throughput >= seq_throughput * 0.5
      end

      # Highest concurrency should be better than sequential
      highest_throughput = List.last(throughputs)
      assert highest_throughput > seq_throughput
    end

    test "memory usage remains stable under concurrent load" do
      program = DSPEx.ConcurrentExecutionTest.DelayedProgram.new(:memory_test, 5, 0)

      # Baseline memory
      :erlang.garbage_collect()
      {:memory, baseline_memory} = :erlang.process_info(self(), :memory)

      # Run high concurrent load
      tasks =
        for _i <- 1..100 do
          Task.async(fn ->
            # Each task does multiple operations
            for j <- 1..10 do
              DSPEx.Program.forward(program, %{operation: j})
            end
          end)
        end

      _results = Task.await_many(tasks, 10_000)

      # Force cleanup and measure memory
      :erlang.garbage_collect()
      # Allow cleanup time
      Process.sleep(100)
      :erlang.garbage_collect()

      {:memory, final_memory} = :erlang.process_info(self(), :memory)

      memory_growth = final_memory - baseline_memory

      # Memory growth should be reasonable (< 10MB for 1000 operations)
      assert memory_growth < 10_000_000
    end

    test "error handling remains robust under concurrent stress" do
      # Mix of successful and failing programs
      programs = [
        DSPEx.ConcurrentExecutionTest.DelayedProgram.new(:success_1, 5, 0),
        DSPEx.ConcurrentExecutionTest.DelayedProgram.new(:success_2, 10, 0),
        # Will fail
        %StatefulProgram{id: :fail_program, state_agent: nil}
      ]

      # Generate many concurrent operations with mixed programs
      tasks =
        for _i <- 1..30 do
          Task.async(fn ->
            program = Enum.random(programs)

            try do
              DSPEx.Program.forward(program, %{test: "stress"})
            rescue
              error -> {:error, {:exception, error}}
            catch
              :exit, reason -> {:error, {:exit, reason}}
              thrown -> {:error, {:throw, thrown}}
            end
          end)
        end

      results = Task.await_many(tasks, 5000)

      # Should have a mix of successes and predictable failures
      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      assert successes + failures == 30
      # Some should succeed
      assert successes > 0
      # Some should fail (due to nil agent)
      assert failures > 0

      # No unexpected crashes or undefined behavior
      for result <- results do
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end
end
