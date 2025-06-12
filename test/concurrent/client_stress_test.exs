defmodule DSPEx.Concurrent.ClientStressTest do
  @moduledoc """
  Concurrent stress tests for DSPEx.Client behavior.
  Tests concurrent request patterns, resource management, and error handling
  under high concurrent load to validate BEACON readiness.
  """
  use ExUnit.Case, async: false

  @moduletag :group_2

  @concurrency_level 50
  @stress_operations 200

  # Mock program for testing client behavior
  defmodule MockClientProgram do
    use DSPEx.Program

    defstruct [:id, :delay_ms, :failure_rate]

    def new(id, opts \\ []) do
      %__MODULE__{
        id: id,
        delay_ms: Keyword.get(opts, :delay_ms, 10),
        failure_rate: Keyword.get(opts, :failure_rate, 0.0)
      }
    end

    @impl DSPEx.Program
    def forward(program, inputs, _opts) do
      # Simulate processing time
      Process.sleep(program.delay_ms)

      # Simulate random failures
      if :rand.uniform() < program.failure_rate do
        {:error, :program_failure}
      else
        {:ok, Map.put(inputs, :processed_by, program.id)}
      end
    end
  end

  describe "concurrent request patterns" do
    test "multiple programs execute concurrently without interference" do
      # Create multiple programs with different characteristics
      programs =
        for i <- 1..@concurrency_level do
          MockClientProgram.new("program_#{i}", delay_ms: 20 + rem(i, 10))
        end

      # Execute all programs concurrently
      tasks =
        for {program, i} <- Enum.with_index(programs, 1) do
          Task.async(fn ->
            inputs = %{request_id: i, test_data: "concurrent_test"}
            result = DSPEx.Program.forward(program, inputs)
            {i, program.id, result}
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All executions should succeed
      assert length(results) == @concurrency_level
      successes = Enum.count(results, fn {_, _, result} -> match?({:ok, _}, result) end)
      assert successes == @concurrency_level

      # Each result should be tagged with correct program ID
      for {i, program_id, {:ok, output}} <- results do
        expected_program_id = "program_#{i}"
        assert program_id == expected_program_id
        assert output.processed_by == expected_program_id
        assert output.request_id == i
      end
    end

    test "concurrent requests maintain quality under load" do
      program = MockClientProgram.new(:quality_test, delay_ms: 15)

      # Execute many concurrent requests
      tasks =
        for i <- 1..@stress_operations do
          Task.async(fn ->
            start_time = System.monotonic_time()
            inputs = %{request_id: i, test_type: "quality_under_load"}
            result = DSPEx.Program.forward(program, inputs)
            end_time = System.monotonic_time()

            duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
            {i, result, duration}
          end)
        end

      results = Task.await_many(tasks, 15_000)

      # All should succeed with consistent quality
      assert length(results) == @stress_operations
      successes = Enum.count(results, fn {_, result, _} -> match?({:ok, _}, result) end)
      assert successes == @stress_operations

      # Verify response quality and timing
      durations = Enum.map(results, fn {_, _, duration} -> duration end)
      avg_duration = Enum.sum(durations) / length(durations)

      # Should maintain reasonable response times
      # Average under 100ms including test overhead
      assert avg_duration < 100

      # Verify all responses have correct structure
      for {i, {:ok, output}, _duration} <- results do
        assert output.processed_by == :quality_test
        assert output.request_id == i
        assert output.test_type == "quality_under_load"
      end
    end

    test "system doesn't deadlock under high concurrency" do
      program = MockClientProgram.new(:deadlock_test, delay_ms: 30)

      # Use shared counter to create contention potential
      shared_counter = :counters.new(1, [])

      start_time = System.monotonic_time()

      # Create waves of concurrent requests
      wave_size = @concurrency_level

      wave_tasks =
        for wave <- 1..3 do
          Task.async(fn ->
            wave_results =
              for i <- 1..wave_size do
                Task.async(fn ->
                  # Simulate contention by accessing shared resource
                  :counters.add(shared_counter, 1, 1)
                  count = :counters.get(shared_counter, 1)

                  inputs = %{wave: wave, request: i, shared_count: count}
                  result = DSPEx.Program.forward(program, inputs)
                  {wave, i, result}
                end)
              end
              |> Task.await_many(8_000)

            {wave, wave_results}
          end)
        end

      wave_results = Task.await_many(wave_tasks, 12_000)
      end_time = System.monotonic_time()

      total_duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      # Should complete in reasonable time (not deadlocked)
      assert total_duration < 15_000

      # All waves should complete successfully
      assert length(wave_results) == 3

      total_requests =
        for {_wave, results} <- wave_results, reduce: 0 do
          acc ->
            assert length(results) == wave_size
            successes = Enum.count(results, fn {_, _, result} -> match?({:ok, _}, result) end)
            assert successes == wave_size
            acc + wave_size
        end

      # Verify shared counter integrity
      final_count = :counters.get(shared_counter, 1)
      assert final_count == total_requests
    end
  end

  describe "resource management" do
    test "concurrent execution doesn't exhaust system resources" do
      program = MockClientProgram.new(:resource_test, delay_ms: 25)

      # Monitor system resources
      initial_memory = :erlang.memory(:total)
      initial_processes = :erlang.system_info(:process_count)

      # Execute resource-intensive concurrent operations
      tasks =
        for i <- 1..@stress_operations do
          Task.async(fn ->
            # Each task does multiple operations
            results =
              for j <- 1..5 do
                inputs = %{batch: i, operation: j}
                DSPEx.Program.forward(program, inputs)
              end

            {i, results}
          end)
        end

      batch_results = Task.await_many(tasks, 20_000)

      # Allow cleanup
      :erlang.garbage_collect()
      Process.sleep(200)

      final_memory = :erlang.memory(:total)
      final_processes = :erlang.system_info(:process_count)

      # All batches should succeed
      assert length(batch_results) == @stress_operations

      for {_batch, results} <- batch_results do
        assert length(results) == 5
        successes = Enum.count(results, &match?({:ok, _}, &1))
        assert successes == 5
      end

      # Resource usage should be reasonable
      memory_growth = final_memory - initial_memory
      process_growth = final_processes - initial_processes

      # Memory growth should be bounded (< 50MB)
      assert memory_growth < 50_000_000

      # Process count should return to reasonable levels
      assert process_growth < 200
    end

    test "concurrent execution handles memory pressure gracefully" do
      program = MockClientProgram.new(:memory_test, delay_ms: 20)

      # Monitor memory during large payload processing
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)

      # Create memory pressure with large inputs
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            # Large input to create memory pressure
            large_data = String.duplicate("Memory pressure test data #{i} ", 1000)
            inputs = %{large_payload: large_data, test_id: i}

            result = DSPEx.Program.forward(program, inputs)

            # Verify result integrity despite memory pressure
            case result do
              {:ok, output} -> assert String.contains?(output.large_payload, "#{i}")
              _ -> flunk("Expected success but got #{inspect(result)}")
            end

            result
          end)
        end

      results = Task.await_many(tasks, 12_000)

      # Force cleanup
      :erlang.garbage_collect()
      Process.sleep(100)
      final_memory = :erlang.memory(:total)

      # All should succeed despite memory pressure
      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 100

      # Memory should be managed gracefully
      memory_growth = final_memory - initial_memory

      # Should handle large payloads without excessive memory growth (< 200MB)
      assert memory_growth < 200_000_000
    end

    test "error handling remains robust under concurrent stress" do
      # Mix of reliable and unreliable programs
      reliable_program = MockClientProgram.new(:reliable, delay_ms: 15)
      unreliable_program = MockClientProgram.new(:unreliable, delay_ms: 20, failure_rate: 0.5)

      # Execute mixed concurrent operations
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            # Alternate between reliable and unreliable programs
            program = if rem(i, 3) == 0, do: unreliable_program, else: reliable_program

            inputs = %{test_id: i, program_type: program.id}

            try do
              DSPEx.Program.forward(program, inputs)
            rescue
              error -> {:error, {:exception, error}}
            catch
              :exit, reason -> {:error, {:exit, reason}}
              thrown -> {:error, {:throw, thrown}}
            end
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All tasks should complete (either success or graceful failure)
      assert length(results) == 100

      # Count different outcome types
      successes = Enum.count(results, &match?({:ok, _}, &1))
      program_failures = Enum.count(results, &match?({:error, :program_failure}, &1))

      unexpected_errors =
        Enum.count(results, fn
          {:error, {:exception, _}} -> true
          {:error, {:exit, _}} -> true
          {:error, {:throw, _}} -> true
          _ -> false
        end)

      # Should have mix of successes and expected failures
      assert successes > 0
      assert program_failures > 0
      assert successes + program_failures + unexpected_errors == 100

      # Should not have excessive unexpected errors
      assert unexpected_errors < 10
    end
  end

  describe "fault tolerance" do
    test "individual failures don't affect other concurrent operations" do
      # Create mix of programs with different failure characteristics
      programs = [
        MockClientProgram.new(:always_succeed, failure_rate: 0.0),
        MockClientProgram.new(:sometimes_fail, failure_rate: 0.3),
        MockClientProgram.new(:often_fail, failure_rate: 0.7)
      ]

      # Track results by program type
      # succeed, sometimes_fail, often_fail
      result_tracker = :counters.new(3, [])

      tasks =
        for i <- 1..150 do
          Task.async(fn ->
            program = Enum.at(programs, rem(i, 3))

            inputs = %{test_id: i, isolation_test: true}
            result = DSPEx.Program.forward(program, inputs)

            # Track result by program type
            counter_index =
              case program.id do
                :always_succeed -> 1
                :sometimes_fail -> 2
                :often_fail -> 3
              end

            case result do
              {:ok, _} -> :counters.add(result_tracker, counter_index, 1)
              # Failures are expected for some programs
              {:error, _} -> :ok
            end

            {program.id, result}
          end)
        end

      results = Task.await_many(tasks, 8_000)

      # All should complete
      assert length(results) == 150

      # Group results by program type
      succeed_results = Enum.filter(results, fn {id, _} -> id == :always_succeed end)
      sometimes_results = Enum.filter(results, fn {id, _} -> id == :sometimes_fail end)
      often_results = Enum.filter(results, fn {id, _} -> id == :often_fail end)

      # Always succeed program should have 100% success rate
      succeed_successes =
        Enum.count(succeed_results, fn {_, result} -> match?({:ok, _}, result) end)

      # 150/3 = 50 calls per program
      assert succeed_successes == 50

      # Sometimes fail should have some successes
      sometimes_successes =
        Enum.count(sometimes_results, fn {_, result} -> match?({:ok, _}, result) end)

      # At least 40% success
      assert sometimes_successes > 20

      # Often fail should have some failures
      often_successes = Enum.count(often_results, fn {_, result} -> match?({:ok, _}, result) end)
      # Less than 60% success
      assert often_successes < 30

      # Verify counter integrity
      succeed_count = :counters.get(result_tracker, 1)
      sometimes_count = :counters.get(result_tracker, 2)
      often_count = :counters.get(result_tracker, 3)

      assert succeed_count == succeed_successes
      assert sometimes_count == sometimes_successes
      assert often_count == often_successes
    end

    test "timeout handling works correctly under concurrent load" do
      # Programs with different timing characteristics
      fast_program = MockClientProgram.new(:fast, delay_ms: 10)
      slow_program = MockClientProgram.new(:slow, delay_ms: 200)

      # completed, timed_out
      timeout_tracker = :counters.new(2, [])

      tasks =
        for i <- 1..60 do
          Task.async(fn ->
            # Mix fast and slow programs
            program = if rem(i, 3) == 0, do: slow_program, else: fast_program

            inputs = %{test_id: i, timing_test: true}

            # Use timeout for execution
            task_result =
              Task.async(fn ->
                DSPEx.Program.forward(program, inputs)
              end)

            # 100ms timeout
            case Task.yield(task_result, 100) do
              {:ok, result} ->
                # completed
                :counters.add(timeout_tracker, 1, 1)
                {program.id, :completed, result}

              nil ->
                Task.shutdown(task_result, :brutal_kill)
                # timed out
                :counters.add(timeout_tracker, 2, 1)
                {program.id, :timeout, nil}
            end
          end)
        end

      results = Task.await_many(tasks, 5_000)

      # All should complete (either success or timeout)
      assert length(results) == 60

      # Analyze results
      fast_completed =
        Enum.count(results, fn {id, status, _} ->
          id == :fast and status == :completed
        end)

      slow_timeouts =
        Enum.count(results, fn {id, status, _} ->
          id == :slow and status == :timeout
        end)

      # Fast programs should mostly complete
      # Most fast operations complete
      assert fast_completed > 30

      # Slow programs should mostly timeout
      # Most slow operations timeout
      assert slow_timeouts > 15

      # Verify timeout tracking
      completed_count = :counters.get(timeout_tracker, 1)
      timeout_count = :counters.get(timeout_tracker, 2)

      assert completed_count + timeout_count == 60
    end
  end

  describe "performance characteristics" do
    test "throughput scales reasonably with concurrency" do
      program = MockClientProgram.new(:throughput_test, delay_ms: 50)

      # Test different concurrency levels
      concurrency_levels = [1, 5, 10, 20]
      operation_count = 40

      results =
        for concurrency <- concurrency_levels do
          start_time = System.monotonic_time()

          # Create controlled concurrency batches
          batch_size = div(operation_count, concurrency)
          batches = Enum.chunk_every(1..operation_count, batch_size)

          batch_tasks =
            for batch <- batches do
              Task.async(fn ->
                Enum.map(batch, fn i ->
                  inputs = %{operation: i, concurrency_level: concurrency}
                  DSPEx.Program.forward(program, inputs)
                end)
              end)
            end

          _batch_results = Task.await_many(batch_tasks, 10_000)

          end_time = System.monotonic_time()
          duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
          throughput = operation_count / (duration_ms / 1000)

          {concurrency, duration_ms, throughput}
        end

      # Analyze scaling characteristics
      throughputs = Enum.map(results, fn {_, _, throughput} -> throughput end)

      # Higher concurrency should generally improve throughput
      [seq_throughput | concurrent_throughputs] = throughputs

      # At minimum, concurrent execution shouldn't be much slower
      for concurrent_throughput <- concurrent_throughputs do
        # Should be at least 60% of sequential (allowing for overhead)
        assert concurrent_throughput >= seq_throughput * 0.6
      end

      # Highest concurrency should outperform sequential
      highest_throughput = List.last(throughputs)
      assert highest_throughput > seq_throughput
    end

    test "memory usage remains stable under sustained concurrent load" do
      program = MockClientProgram.new(:memory_stability_test, delay_ms: 10)

      # Baseline memory
      :erlang.garbage_collect()
      {:memory, baseline_memory} = :erlang.process_info(self(), :memory)

      # Run sustained concurrent load
      for round <- 1..5 do
        tasks =
          for i <- 1..50 do
            Task.async(fn ->
              # Multiple operations per task
              for j <- 1..10 do
                inputs = %{round: round, task: i, operation: j}
                DSPEx.Program.forward(program, inputs)
              end
            end)
          end

        _results = Task.await_many(tasks, 8_000)

        # Periodic cleanup between rounds
        :erlang.garbage_collect()
        Process.sleep(50)
      end

      # Final cleanup and measurement
      :erlang.garbage_collect()
      Process.sleep(100)
      :erlang.garbage_collect()

      {:memory, final_memory} = :erlang.process_info(self(), :memory)

      memory_growth = final_memory - baseline_memory

      # Memory growth should be reasonable for 2500 operations (5 rounds * 50 tasks * 10 ops)
      # Less than 10MB growth
      assert memory_growth < 10_000_000
    end
  end
end
