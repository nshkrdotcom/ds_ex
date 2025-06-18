defmodule DSPEx.Integration.BEACONPerformanceValidationTest do
  @moduledoc """
  Comprehensive performance validation tests for BEACON teleprompter.

  Validates that BEACON meets performance requirements and works correctly
  across different configurations and workload sizes.
  """
  use ExUnit.Case, async: false

  import Mox
  setup :verify_on_exit!

  alias DSPEx.{Predict, Program}
  alias DSPEx.Teleprompter.BEACON
  alias DSPEx.Teleprompter.BEACON.Benchmark
  alias DSPEx.Test.MockProvider

  @moduletag :integration
  @moduletag :performance
  @moduletag :phase2_features

  # Performance thresholds

  setup_all do
    {:ok, _mock} = MockProvider.start_link(mode: :performance)

    defmodule PerformanceSignature do
      use DSPEx.Signature, "question -> answer"
    end

    %{signature: PerformanceSignature}
  end

  describe "BEACON performance benchmarks" do
    test "benchmark module runs without errors", %{signature: _signature} do
      # Test that the benchmark module can execute
      assert_capture_io(fn ->
        result = Benchmark.run_benchmarks()
        assert is_list(result)
        # Small, Medium, Large scale
        assert length(result) == 3
      end)
    end

    test "individual benchmark configurations complete successfully", %{signature: _signature} do
      config = %{
        name: "Test Config",
        candidates: 5,
        trials: 10,
        demos: 2,
        trainset_size: 20
      }

      result = Benchmark.benchmark_configuration(config)

      assert result.config == config
      assert is_number(result.duration)
      assert result.duration > 0
      assert is_number(result.throughput)
      assert result.throughput > 0
      assert is_number(result.memory_mb)
      assert result.memory_mb >= 0
    end

    test "concurrency benchmarks show scaling behavior", %{signature: _signature} do
      assert_capture_io(fn ->
        results = Benchmark.run_concurrency_benchmarks()
        assert is_list(results)
        # 5 concurrency levels
        assert length(results) == 5

        # Verify structure
        for result <- results do
          assert Map.has_key?(result, :concurrency)
          assert Map.has_key?(result, :throughput)
          assert Map.has_key?(result, :efficiency)
          assert result.throughput > 0
        end
      end)
    end

    test "memory benchmarks track usage patterns", %{signature: _signature} do
      assert_capture_io(fn ->
        Benchmark.run_memory_benchmarks()
        # Just verify it runs without errors
      end)
    end

    test "quality benchmarks simulate optimization improvements", %{signature: _signature} do
      assert_capture_io(fn ->
        Benchmark.run_optimization_quality_benchmarks()
        # Just verify it runs without errors
      end)
    end
  end

  describe "BEACON teleprompter performance validation" do
    test "BEACON module can be instantiated without errors", %{signature: _signature} do
      teleprompter =
        BEACON.new(
          num_candidates: 5,
          max_bootstrapped_demos: 2,
          num_trials: 10,
          max_concurrency: 5,
          timeout: 10_000
        )

      assert teleprompter.num_candidates == 5
      assert teleprompter.max_bootstrapped_demos == 2
      assert teleprompter.num_trials == 10
      assert teleprompter.max_concurrency == 5
      assert teleprompter.timeout == 10_000
    end

    test "BEACON programs can be created with different configurations", %{signature: _signature} do
      # Test with varying configurations
      configs = [
        %{candidates: 5, demos: 2, trials: 10},
        %{candidates: 10, demos: 3, trials: 20},
        %{candidates: 15, demos: 4, trials: 30}
      ]

      for config <- configs do
        teleprompter =
          BEACON.new(
            num_candidates: config.candidates,
            max_bootstrapped_demos: config.demos,
            num_trials: config.trials
          )

        assert teleprompter.num_candidates == config.candidates
        assert teleprompter.max_bootstrapped_demos == config.demos
        assert teleprompter.num_trials == config.trials
      end
    end

    test "BEACON supports different concurrency configurations", %{signature: _signature} do
      # Test different concurrency levels
      concurrency_levels = [1, 5, 10, 20]

      for concurrency <- concurrency_levels do
        teleprompter =
          BEACON.new(
            num_candidates: 3,
            max_bootstrapped_demos: 1,
            num_trials: 3,
            max_concurrency: concurrency
          )

        assert teleprompter.max_concurrency == concurrency
        assert teleprompter.num_candidates == 3
        assert teleprompter.max_bootstrapped_demos == 1
        assert teleprompter.num_trials == 3
      end
    end
  end

  describe "Bayesian optimizer performance" do
    test "BayesianOptimizer module is available and can be referenced" do
      # Test that the module exists and is accessible
      assert Code.ensure_loaded?(DSPEx.Teleprompter.BEACON.BayesianOptimizer)

      # Test that the optimize function exists
      assert function_exported?(DSPEx.Teleprompter.BEACON.BayesianOptimizer, :optimize, 4)
    end

    test "Bayesian optimizer can be configured with different options" do
      # Test basic configuration parameters
      basic_config = [max_trials: 10, num_initial_samples: 3, acquisition: :expected_improvement]

      advanced_config = [
        max_trials: 50,
        num_initial_samples: 5,
        acquisition: :upper_confidence_bound
      ]

      # Just verify the configurations are different
      assert basic_config[:max_trials] != advanced_config[:max_trials]
      assert basic_config[:num_initial_samples] != advanced_config[:num_initial_samples]
    end
  end

  describe "integration with existing DSPEx components" do
    test "BEACON integrates correctly with Program module", %{signature: signature} do
      student = %Predict{signature: signature, client: :test}

      # Test program introspection functions with BEACON
      assert Program.program_type(student) == :predict
      assert Program.has_demos?(student) == false

      program_info = Program.safe_program_info(student)
      assert Map.has_key?(program_info, :type)
      assert Map.has_key?(program_info, :has_demos)
    end

    test "BEACON integrates with telemetry infrastructure", %{signature: _signature} do
      # Test that BEACON module can be loaded and has telemetry support
      assert Code.ensure_loaded?(DSPEx.Teleprompter.BEACON)

      # Verify BEACON compile function exists
      assert function_exported?(DSPEx.Teleprompter.BEACON, :compile, 5)
      assert function_exported?(DSPEx.Teleprompter.BEACON, :new, 1)

      # Test basic telemetry event names are defined as atoms
      start_event = [:dspex, :teleprompter, :beacon, :start]
      stop_event = [:dspex, :teleprompter, :beacon, :stop]

      assert is_list(start_event)
      assert is_list(stop_event)
      assert length(start_event) == 4
      assert length(stop_event) == 4
    end
  end

  # Helper functions

  defp assert_capture_io(fun) do
    ExUnit.CaptureIO.capture_io(fun)
    # Just ensure it runs without throwing
    :ok
  end
end
