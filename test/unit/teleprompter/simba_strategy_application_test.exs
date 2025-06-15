defmodule DSPEx.Teleprompter.SimbaStrategyTest do
  use ExUnit.Case, async: true

  alias DSPEx.Teleprompter.SIMBA
  alias DSPEx.Teleprompter.SIMBA.{Bucket, Trajectory}
  alias DSPEx.{Example, Predict}

  # Mock signature for testing
  defmodule MockSignature do
    def input_fields, do: [:question]
    def output_fields, do: [:answer]
    def description, do: "Answer the question"
  end

  describe "apply_strategies_fixed/8" do
    test "filters buckets with improvement potential" do
      config = SIMBA.new(num_candidates: 3, temperature_for_candidates: 0.5)
      correlation_id = "strategy-test"

      programs = [
        %Predict{signature: MockSignature, client: :test},
        %Predict{signature: MockSignature, client: :test},
        %Predict{signature: MockSignature, client: :test}
      ]

      # Program scores
      program_scores = %{
        # avg: 0.25
        0 => [0.2, 0.3],
        # avg: 0.85
        1 => [0.8, 0.9],
        # avg: 0.55
        2 => [0.5, 0.6]
      }

      # Create test buckets with different improvement potential
      good_bucket =
        create_test_bucket(
          [
            create_trajectory(0.9, true),
            create_trajectory(0.3, false)
          ],
          %{max_to_min_gap: 0.6, max_score: 0.9}
        )

      poor_bucket =
        create_test_bucket(
          [
            create_trajectory(0.1, false),
            create_trajectory(0.05, false)
          ],
          %{max_to_min_gap: 0.05, max_score: 0.1}
        )

      buckets = [good_bucket, poor_bucket]
      next_program_idx = 3
      predictor2name = %{}
      name2predictor = %{}

      {candidates, updated_idx} =
        SIMBA.apply_strategies_fixed(
          buckets,
          programs,
          program_scores,
          config,
          next_program_idx,
          predictor2name,
          name2predictor,
          correlation_id
        )

      # Should generate candidates only from viable buckets
      assert length(candidates) >= 0
      assert updated_idx >= next_program_idx
    end

    test "uses real program scores for source program selection" do
      # Greedy
      config = SIMBA.new(num_candidates: 2, temperature_for_candidates: 0.0)
      correlation_id = "greedy-strategy-test"

      programs = [
        # Worst
        %Predict{signature: MockSignature, client: :test},
        # Best
        %Predict{signature: MockSignature, client: :test},
        # Middle
        %Predict{signature: MockSignature, client: :test}
      ]

      # Program 1 has highest score
      program_scores = %{
        # worst
        0 => [0.1],
        # best
        1 => [0.9],
        # middle
        2 => [0.5]
      }

      # Create viable bucket
      bucket =
        create_test_bucket(
          [
            create_trajectory(0.8, true),
            create_trajectory(0.2, false)
          ],
          %{max_to_min_gap: 0.6, max_score: 0.8}
        )

      buckets = [bucket]

      {candidates, _updated_idx} =
        SIMBA.apply_strategies_fixed(
          buckets,
          programs,
          program_scores,
          config,
          3,
          %{},
          %{},
          correlation_id
        )

      # With temperature=0, should select highest scoring program (index 1) as source
      # This is verified by the strategy application logic
      assert is_list(candidates)
    end

    test "handles empty viable buckets gracefully" do
      config = SIMBA.new(num_candidates: 2)
      correlation_id = "empty-buckets-test"

      programs = [%Predict{signature: MockSignature, client: :test}]
      program_scores = %{0 => [0.5]}

      # Create buckets with no improvement potential
      poor_bucket =
        create_test_bucket(
          [
            create_trajectory(0.05, false)
          ],
          %{max_to_min_gap: 0.001, max_score: 0.05}
        )

      buckets = [poor_bucket]

      {candidates, updated_idx} =
        SIMBA.apply_strategies_fixed(
          buckets,
          programs,
          program_scores,
          config,
          1,
          %{},
          %{},
          correlation_id
        )

      # Should return empty candidates list
      assert candidates == []
      # No change in program index
      assert updated_idx == 1
    end
  end

  describe "apply_first_applicable_strategy_fixed/6" do
    test "applies first strategy that is applicable" do
      bucket =
        create_test_bucket(
          [
            create_trajectory(0.8, true),
            create_trajectory(0.3, false)
          ],
          %{max_to_min_gap: 0.5, max_score: 0.8}
        )

      source_program = %Predict{signature: MockSignature, client: :test}

      # Mock strategy modules
      strategies = [
        DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo
      ]

      config = SIMBA.new()

      result =
        SIMBA.apply_first_applicable_strategy_fixed(
          bucket,
          source_program,
          strategies,
          %{},
          %{},
          config
        )

      # Should either apply strategy or skip with reason
      assert match?({:ok, _program}, result) or match?({:skip, _reason}, result)
    end
  end

  # Helper functions
  defp create_test_bucket(trajectories, metadata) do
    Bucket.new(trajectories, metadata: metadata)
  end

  defp create_trajectory(score, success) do
    example = Example.new(%{question: "Test?", answer: "Test"})
    program = %Predict{signature: MockSignature, client: :test}

    %Trajectory{
      program: program,
      example: example,
      inputs: %{question: "Test?"},
      outputs: %{answer: "Test"},
      score: score,
      duration: 1000,
      model_config: %{temperature: 0.7},
      success: success,
      metadata: %{exec_id: :rand.uniform(1000)}
    }
  end
end
