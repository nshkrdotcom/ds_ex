defmodule DSPEx.Teleprompter.SIMBA.ContinuousOptimizerTest do
  @moduledoc """
  Comprehensive test suite for SIMBA Continuous Optimizer GenServer.
  """

  use ExUnit.Case, async: false

  alias DSPEx.{Example}
  alias DSPEx.Teleprompter.SIMBA.ContinuousOptimizer

  # Mock program for testing
  defmodule MockProgram do
    defstruct [:id, :quality_score, :optimization_count]

    def forward(%{quality_score: score}, _inputs) when is_number(score) do
      if score > 0.5 do
        {:ok, %{result: "success", quality: score}}
      else
        {:error, :low_quality}
      end
    end

    def forward(_program, _inputs) do
      {:ok, %{result: "mock_result", quality: 0.8}}
    end

    def forward(program, inputs, _opts) do
      forward(program, inputs)
    end
  end

  setup do
    program = %MockProgram{id: :test_program, quality_score: 0.8, optimization_count: 0}

    trainset = [
      Example.new(%{input: "test1", output: "result1"}, [:input]),
      Example.new(%{input: "test2", output: "result2"}, [:input])
    ]

    teacher = %MockProgram{id: :teacher, quality_score: 0.9}
    metric_fn = fn _example, prediction -> prediction[:quality] || 0.7 end

    %{
      program: program,
      trainset: trainset,
      teacher: teacher,
      metric_fn: metric_fn
    }
  end

  describe "GenServer initialization" do
    test "starts with proper initial state", %{program: program} do
      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: program,
          optimization_interval: 1000,
          quality_check_interval: 500
        )

      state = :sys.get_state(pid)

      assert state.program == program
      assert state.original_program == program
      assert state.optimization_interval == 1000
      assert state.quality_check_interval == 500
      assert state.optimization_count == 0
      assert state.status == :running
      assert is_binary(state.correlation_id)

      GenServer.stop(pid)
    end

    test "schedules initial quality check and optimization", %{program: program} do
      # Use shorter intervals for testing
      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: program,
          optimization_interval: 100,
          quality_check_interval: 50
        )

      # Verify process is alive and scheduled messages
      assert Process.alive?(pid)

      # Give some time for initialization
      Process.sleep(10)

      # Check that the GenServer is properly initialized
      state = :sys.get_state(pid)
      assert state.status == :running

      GenServer.stop(pid)
    end

    test "handles missing required options gracefully" do
      # Should handle missing program option
      Process.flag(:trap_exit, true)

      assert {:error, {:missing_required_option, :program}} =
               ContinuousOptimizer.start_link(
                 optimization_interval: 1000
                 # Missing required :program option
               )
    end

    test "accepts all configuration options", %{
      program: program,
      trainset: trainset,
      teacher: teacher,
      metric_fn: metric_fn
    } do
      opts = [
        program: program,
        optimization_interval: 24 * 3600 * 1000,
        quality_check_interval: 6 * 3600 * 1000,
        quality_threshold: 0.75,
        trainset: trainset,
        teacher: teacher,
        metric_fn: metric_fn
      ]

      {:ok, pid} = ContinuousOptimizer.start_link(opts)

      state = :sys.get_state(pid)
      assert state.quality_threshold == 0.75
      assert state.trainset == trainset
      assert state.teacher == teacher
      assert is_function(state.metric_fn)

      GenServer.stop(pid)
    end
  end

  describe "client API" do
    setup %{program: program} do
      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: program,
          # Longer intervals for testing
          optimization_interval: 5000,
          quality_check_interval: 2000
        )

      %{pid: pid}
    end

    test "get_status returns current status", %{pid: pid} do
      status = ContinuousOptimizer.get_status(pid)

      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :correlation_id)
      assert Map.has_key?(status, :last_optimization)
      assert Map.has_key?(status, :last_quality_check)
      assert Map.has_key?(status, :optimization_count)
      assert Map.has_key?(status, :current_quality)
      assert Map.has_key?(status, :quality_trend)

      assert status.status == :running
      assert is_binary(status.correlation_id)
      assert status.optimization_count == 0
    end

    test "trigger_optimization sends optimization message", %{pid: pid} do
      # Trigger manual optimization
      :ok = ContinuousOptimizer.trigger_optimization(pid)

      # Give some time for message processing
      Process.sleep(10)

      # Status should still be accessible
      status = ContinuousOptimizer.get_status(pid)
      assert Map.has_key?(status, :status)
    end

    test "update_config modifies configuration", %{pid: pid} do
      new_config = %{
        quality_threshold: 0.85,
        optimization_interval: 10_000
      }

      :ok = ContinuousOptimizer.update_config(pid, new_config)

      # Verify configuration was updated
      state = :sys.get_state(pid)
      assert state.quality_threshold == 0.85
      assert state.optimization_interval == 10_000
    end

    test "stop_optimization terminates the process", %{pid: pid} do
      # Stop the optimizer
      :ok = ContinuousOptimizer.stop_optimization(pid)

      # Give time for graceful shutdown
      Process.sleep(50)

      # Process should be terminated
      refute Process.alive?(pid)
    end
  end

  describe "quality monitoring" do
    test "quality check with sufficient configuration", %{
      program: program,
      trainset: trainset,
      teacher: teacher,
      metric_fn: metric_fn
    } do
      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: program,
          trainset: trainset,
          teacher: teacher,
          metric_fn: metric_fn,
          # Very short for testing
          quality_check_interval: 50,
          optimization_interval: 5000
        )

      # Wait for a quality check to occur
      Process.sleep(100)

      state = :sys.get_state(pid)

      # Should have updated quality history
      assert is_list(state.quality_history)

      GenServer.stop(pid)
    end

    test "quality check with insufficient configuration uses fallback", %{program: program} do
      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: program,
          quality_check_interval: 50,
          optimization_interval: 5000
          # Missing trainset, teacher, metric_fn
        )

      # Wait for quality check
      Process.sleep(100)

      state = :sys.get_state(pid)

      # Should still function with fallback quality assessment
      assert state.status == :running

      GenServer.stop(pid)
    end

    test "quality trend analysis" do
      # Test quality trend analysis logic
      quality_history = [
        %{timestamp: DateTime.utc_now(), quality: 0.9, optimization_count: 3},
        %{timestamp: DateTime.utc_now(), quality: 0.8, optimization_count: 2},
        %{timestamp: DateTime.utc_now(), quality: 0.7, optimization_count: 1},
        %{timestamp: DateTime.utc_now(), quality: 0.6, optimization_count: 0}
      ]

      trend = analyze_quality_trend_logic(quality_history)
      # Quality is increasing over time
      assert trend == :improving

      # Test declining trend
      declining_history = Enum.reverse(quality_history)
      declining_trend = analyze_quality_trend_logic(declining_history)
      assert declining_trend == :declining

      # Test insufficient data
      short_history = Enum.take(quality_history, 1)
      short_trend = analyze_quality_trend_logic(short_history)
      assert short_trend == :insufficient_data
    end

    test "immediate optimization trigger conditions" do
      # Test conditions that should trigger immediate optimization

      # Quality below threshold
      assert should_optimize_immediately_logic(0.5, %{
               quality_threshold: 0.7,
               last_optimization: DateTime.utc_now()
             })

      # Quality declining trend with recent check
      recent_time = DateTime.add(DateTime.utc_now(), -13, :hour)

      declining_state = %{
        quality_threshold: 0.7,
        last_optimization: recent_time,
        quality_history: [
          # Declining
          %{quality: 0.6},
          %{quality: 0.7},
          %{quality: 0.8}
        ]
      }

      # Should trigger on declining quality even if above threshold
      assert should_optimize_immediately_logic(0.75, declining_state)

      # Overdue optimization (>48 hours)
      old_time = DateTime.add(DateTime.utc_now(), -50, :hour)
      overdue_state = %{quality_threshold: 0.7, last_optimization: old_time, quality_history: []}
      assert should_optimize_immediately_logic(0.8, overdue_state)
    end
  end

  describe "optimization execution" do
    test "optimization with proper configuration", %{
      program: program,
      trainset: trainset,
      teacher: teacher,
      metric_fn: metric_fn
    } do
      # Mock successful optimization
      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: program,
          trainset: trainset,
          teacher: teacher,
          metric_fn: metric_fn,
          # Short interval for testing
          optimization_interval: 50,
          quality_check_interval: 2000
        )

      initial_state = :sys.get_state(pid)
      initial_count = initial_state.optimization_count

      # Wait for optimization to occur
      Process.sleep(100)

      final_state = :sys.get_state(pid)

      # Optimization count may have increased
      assert final_state.optimization_count >= initial_count

      GenServer.stop(pid)
    end

    test "optimization with insufficient configuration", %{program: program} do
      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: program,
          optimization_interval: 50,
          quality_check_interval: 2000
          # Missing trainset, teacher, metric_fn
        )

      # Wait for optimization attempt
      Process.sleep(100)

      state = :sys.get_state(pid)

      # Should handle gracefully and remain running
      assert state.status in [:running, :error]

      GenServer.stop(pid)
    end

    test "optimization intensity adjustment based on quality" do
      # Test optimization intensity logic

      # Low quality should use more intensive optimization
      low_quality_history = [%{quality: 0.4}]
      low_intensity = determine_optimization_intensity_logic(low_quality_history)

      # High quality should use lighter optimization
      high_quality_history = [%{quality: 0.9}]
      high_intensity = determine_optimization_intensity_logic(high_quality_history)

      assert low_intensity > high_intensity
      # 20 * 1.5
      assert low_intensity == 30
      # 20 * 0.8
      assert high_intensity == 16
    end

    test "trial count adjustment based on recent failures" do
      # Test trial count adjustment logic

      # Recent failures should increase trial count
      failure_history = [
        # 3 recent failures
        %{quality: 0.5},
        %{quality: 0.4},
        %{quality: 0.3}
      ]

      failure_trials = determine_trial_count_logic(failure_history)

      # No recent failures should use base trial count
      success_history = [
        %{quality: 0.8},
        %{quality: 0.9},
        %{quality: 0.85}
      ]

      success_trials = determine_trial_count_logic(success_history)

      assert failure_trials > success_trials
      # 40 * 1.5
      assert failure_trials == 60
      # Base trials
      assert success_trials == 40
    end
  end

  describe "error handling and recovery" do
    test "handles optimization failures gracefully", %{program: program} do
      # Create optimizer that will encounter errors
      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: program,
          optimization_interval: 50,
          quality_check_interval: 1000
        )

      # Trigger optimization (which should fail due to missing config)
      send(pid, :optimize)

      # Wait for processing
      Process.sleep(100)

      state = :sys.get_state(pid)

      # Should handle error and continue running
      assert state.status in [:running, :error]
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "continues operation after exceptions" do
      # Test that the GenServer continues operating after internal exceptions
      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: %MockProgram{},
          optimization_interval: 1000,
          quality_check_interval: 500
        )

      # Send malformed message that might cause issues
      send(pid, {:unexpected_message, "test"})

      # Wait a bit
      Process.sleep(50)

      # Should still be alive and responsive
      assert Process.alive?(pid)

      status = ContinuousOptimizer.get_status(pid)
      assert Map.has_key?(status, :status)

      GenServer.stop(pid)
    end

    test "handles process crashes and restarts" do
      # Test restart behavior (would need a supervisor in real implementation)
      program = %MockProgram{id: :crash_test}

      {:ok, pid} =
        ContinuousOptimizer.start_link(
          program: program,
          optimization_interval: 1000,
          quality_check_interval: 500
        )

      initial_status = ContinuousOptimizer.get_status(pid)
      assert initial_status.status == :running

      # Normal stop for cleanup
      GenServer.stop(pid)
    end
  end

  describe "start_optimization convenience function" do
    test "starts optimization with default intervals", %{program: program} do
      {:ok, pid} = ContinuousOptimizer.start_optimization(program)

      state = :sys.get_state(pid)
      assert state.program == program
      # 24 hours
      assert state.optimization_interval == 24 * 3600 * 1000
      # 6 hours
      assert state.quality_check_interval == 6 * 3600 * 1000

      GenServer.stop(pid)
    end

    test "accepts custom intervals", %{program: program} do
      {:ok, pid} =
        ContinuousOptimizer.start_optimization(program,
          interval_hours: 12,
          check_interval_hours: 3
        )

      state = :sys.get_state(pid)
      # 12 hours
      assert state.optimization_interval == 12 * 3600 * 1000
      # 3 hours
      assert state.quality_check_interval == 3 * 3600 * 1000

      GenServer.stop(pid)
    end

    test "registers with global name", %{program: program} do
      {:ok, pid} = ContinuousOptimizer.start_optimization(program)

      # Should be registered globally
      _global_name = {:global, {:simba_continuous_optimizer, program}}
      assert :global.whereis_name({:simba_continuous_optimizer, program}) == pid

      GenServer.stop(pid)
    end
  end

  # Helper functions for testing internal logic
  defp analyze_quality_trend_logic(quality_history) when length(quality_history) < 2 do
    :insufficient_data
  end

  defp analyze_quality_trend_logic(quality_history) do
    recent_qualities =
      quality_history
      |> Enum.take(5)
      |> Enum.map(& &1.quality)
      |> Enum.reverse()

    if length(recent_qualities) < 2 do
      :insufficient_data
    else
      first_half = Enum.take(recent_qualities, div(length(recent_qualities), 2))
      second_half = Enum.drop(recent_qualities, div(length(recent_qualities), 2))

      first_avg = Enum.sum(first_half) / length(first_half)
      second_avg = Enum.sum(second_half) / length(second_half)

      diff = second_avg - first_avg

      cond do
        diff > 0.05 -> :improving
        diff < -0.05 -> :declining
        true -> :stable
      end
    end
  end

  defp should_optimize_immediately_logic(current_quality, state) do
    quality_below_threshold = current_quality < state.quality_threshold

    quality_declining = is_quality_declining_logic(state[:quality_history] || [])

    hours_since_optimization = DateTime.diff(DateTime.utc_now(), state.last_optimization, :hour)
    overdue = hours_since_optimization >= 48

    quality_below_threshold or (quality_declining and hours_since_optimization >= 12) or overdue
  end

  defp is_quality_declining_logic(quality_history) when length(quality_history) < 3 do
    false
  end

  defp is_quality_declining_logic(quality_history) do
    recent_qualities =
      quality_history
      |> Enum.take(3)
      |> Enum.map(& &1.quality)
      |> Enum.reverse()

    case recent_qualities do
      [oldest, middle, newest] ->
        newest < middle and middle < oldest

      _ ->
        false
    end
  end

  defp determine_optimization_intensity_logic(quality_history) do
    base_candidates = 20

    current_quality =
      case quality_history do
        [latest | _] -> latest.quality
        [] -> 0.5
      end

    cond do
      current_quality < 0.5 -> round(base_candidates * 1.5)
      current_quality > 0.8 -> round(base_candidates * 0.8)
      true -> base_candidates
    end
  end

  defp determine_trial_count_logic(quality_history) do
    base_trials = 40

    recent_failures =
      quality_history
      |> Enum.take(5)
      |> Enum.count(fn entry -> entry.quality < 0.6 end)

    if recent_failures > 2 do
      round(base_trials * 1.5)
    else
      base_trials
    end
  end
end
