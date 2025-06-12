defmodule DSPEx.Teleprompter.SIMBA.BayesianOptimizerTest do
  use ExUnit.Case, async: true

  alias DSPEx.Teleprompter.SIMBA.BayesianOptimizer

  describe "new/1" do
    test "creates optimizer with default values" do
      optimizer = BayesianOptimizer.new()

      assert optimizer.num_initial_samples == 10
      assert optimizer.acquisition_function == :expected_improvement
      assert optimizer.convergence_patience == 5
      assert optimizer.exploration_weight == 2.0
    end

    test "creates optimizer with custom options" do
      opts = [
        num_initial_samples: 5,
        acquisition_function: :upper_confidence_bound,
        convergence_patience: 3,
        exploration_weight: 1.5
      ]

      optimizer = BayesianOptimizer.new(opts)

      assert optimizer.num_initial_samples == 5
      assert optimizer.acquisition_function == :upper_confidence_bound
      assert optimizer.convergence_patience == 3
      assert optimizer.exploration_weight == 1.5
    end
  end

  describe "optimize/4" do
    test "runs optimization with simple search space" do
      optimizer =
        BayesianOptimizer.new(
          num_initial_samples: 3,
          convergence_patience: 2
        )

      search_space = %{
        instructions: [
          %{id: "inst1", instruction: "Test instruction 1"},
          %{id: "inst2", instruction: "Test instruction 2"}
        ],
        demos: [
          %{id: "demo1"},
          %{id: "demo2"}
        ]
      }

      # Simple objective function that prefers specific configurations
      objective_function = fn config ->
        score =
          cond do
            config.instruction_id == "inst1" && length(config.demo_ids) == 2 -> 0.9
            config.instruction_id == "inst2" -> 0.7
            true -> 0.5
          end

        # Add some noise to make optimization interesting
        score + (:rand.uniform() - 0.5) * 0.1
      end

      {:ok, result} =
        BayesianOptimizer.optimize(
          optimizer,
          search_space,
          objective_function,
          max_iterations: 10
        )

      assert result.best_configuration.instruction_id in ["inst1", "inst2"]
      assert is_list(result.best_configuration.demo_ids)
      assert result.best_score > 0.0
      # At least initial samples
      assert length(result.observations) >= 3
      assert is_integer(result.convergence_iteration)
      assert is_map(result.stats)
    end

    test "handles empty search space gracefully" do
      optimizer = BayesianOptimizer.new(num_initial_samples: 1)

      search_space = %{instructions: [], demos: []}
      objective_function = fn _ -> 0.5 end

      assert {:error, :no_initial_observations} =
               BayesianOptimizer.optimize(
                 optimizer,
                 search_space,
                 objective_function
               )
    end

    test "handles failing objective function" do
      optimizer =
        BayesianOptimizer.new(
          num_initial_samples: 2,
          convergence_patience: 1
        )

      search_space = %{
        instructions: [%{id: "inst1", instruction: "Test"}],
        demos: [%{id: "demo1"}]
      }

      # Objective function that always raises
      objective_function = fn _ ->
        raise "Evaluation failed"
      end

      assert {:error, :no_initial_observations} =
               BayesianOptimizer.optimize(
                 optimizer,
                 search_space,
                 objective_function,
                 max_iterations: 5
               )
    end

    test "supports different acquisition functions" do
      search_space = %{
        instructions: [%{id: "inst1", instruction: "Test"}],
        demos: [%{id: "demo1"}]
      }

      objective_function = fn _ -> 0.8 end

      for acquisition_fn <- [
            :expected_improvement,
            :upper_confidence_bound,
            :probability_improvement
          ] do
        optimizer =
          BayesianOptimizer.new(
            acquisition_function: acquisition_fn,
            num_initial_samples: 2,
            convergence_patience: 1
          )

        {:ok, result} =
          BayesianOptimizer.optimize(
            optimizer,
            search_space,
            objective_function,
            max_iterations: 3
          )

        assert result.best_score >= 0.0
      end
    end

    test "converges early when no improvement" do
      optimizer =
        BayesianOptimizer.new(
          num_initial_samples: 2,
          convergence_patience: 2
        )

      search_space = %{
        instructions: [%{id: "inst1", instruction: "Test"}],
        demos: [%{id: "demo1"}]
      }

      # Objective function that always returns the same score
      objective_function = fn _ -> 0.5 end

      {:ok, result} =
        BayesianOptimizer.optimize(
          optimizer,
          search_space,
          objective_function,
          max_iterations: 20
        )

      # Should converge much earlier than max_iterations
      assert result.convergence_iteration < 10
      assert result.best_score == 0.5
    end
  end

  describe "telemetry" do
    setup do
      # Capture telemetry events
      test_pid = self()

      handler_id = :test_bayesian_optimizer_telemetry

      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :simba, :bayesian_optimizer, :start],
          [:dspex, :simba, :bayesian_optimizer, :stop],
          [:dspex, :simba, :bayesian_optimizer, :initialization, :start],
          [:dspex, :simba, :bayesian_optimizer, :iteration, :start]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits telemetry events during optimization" do
      optimizer =
        BayesianOptimizer.new(
          num_initial_samples: 2,
          convergence_patience: 1
        )

      search_space = %{
        instructions: [%{id: "inst1", instruction: "Test"}],
        demos: [%{id: "demo1"}]
      }

      objective_function = fn _ -> 0.7 end

      {:ok, _result} =
        BayesianOptimizer.optimize(
          optimizer,
          search_space,
          objective_function,
          max_iterations: 3,
          correlation_id: "test-correlation-id"
        )

      # Should receive start and stop events
      assert_receive {:telemetry, [:dspex, :simba, :bayesian_optimizer, :start], _, metadata}
      assert metadata.correlation_id == "test-correlation-id"

      assert_receive {:telemetry, [:dspex, :simba, :bayesian_optimizer, :initialization, :start],
                      _, _}

      assert_receive {:telemetry, [:dspex, :simba, :bayesian_optimizer, :stop], measurements, _}
      assert is_integer(measurements.duration)
      assert measurements.success == true
    end
  end
end
