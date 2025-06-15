defmodule DSPEx.Teleprompter.SimbaProgramPoolTest do
  use ExUnit.Case, async: true

  alias DSPEx.Teleprompter.SIMBA
  alias DSPEx.Predict

  # Mock signature for testing
  defmodule MockSignature do
    def input_fields, do: [:question]
    def output_fields, do: [:answer]
    def description, do: "Answer the question"
  end

  describe "update_program_pool_fixed/5" do
    test "adds new candidates to program list" do
      # Existing programs
      programs = [
        %Predict{signature: MockSignature, client: :test},
        %Predict{signature: MockSignature, client: :test}
      ]

      # Existing scores
      program_scores = %{
        # avg: 0.25
        0 => [0.2, 0.3],
        # avg: 0.85
        1 => [0.8, 0.9]
      }

      # New candidates
      new_candidates = [
        %Predict{signature: MockSignature, client: :test},
        %Predict{signature: MockSignature, client: :test}
      ]

      # Candidate scores (index in new_candidates -> score)
      candidate_scores = [{0, 0.7}, {1, 0.6}]
      next_idx = 2

      {updated_programs, updated_scores} =
        SIMBA.update_program_pool_fixed(
          programs,
          program_scores,
          new_candidates,
          candidate_scores,
          next_idx
        )

      # Should have 4 programs total
      assert length(updated_programs) == 4
      assert updated_programs == programs ++ new_candidates

      # Should have scores for all programs
      # First new candidate at index 2
      assert Map.has_key?(updated_scores, 2)
      # Second new candidate at index 3
      assert Map.has_key?(updated_scores, 3)
      assert hd(updated_scores[2]) == 0.7
      assert hd(updated_scores[3]) == 0.6
    end

    test "prunes program pool when it gets too large" do
      # Create 60 programs (exceeds threshold of 50)
      programs =
        for _i <- 0..59 do
          %Predict{signature: MockSignature, client: :test}
        end

      # Create scores with varying performance (baseline at 0 should be kept)
      program_scores =
        for i <- 0..59, into: %{} do
          # Baseline gets low score
          score = if i == 0, do: 0.1, else: i / 100.0
          {i, [score]}
        end

      new_candidates = []
      candidate_scores = []
      next_idx = 60

      {updated_programs, updated_scores} =
        SIMBA.update_program_pool_fixed(
          programs,
          program_scores,
          new_candidates,
          candidate_scores,
          next_idx
        )

      # Should be pruned to 30 programs
      assert length(updated_programs) <= 30

      # Baseline (original index 0) should always be kept
      baseline_present =
        Enum.any?(0..(length(updated_programs) - 1), fn idx ->
          Map.get(updated_scores, idx, []) |> hd() == 0.1
        end)

      assert baseline_present, "Baseline program should always be preserved"
    end

    test "handles empty candidates gracefully" do
      programs = [%Predict{signature: MockSignature, client: :test}]
      program_scores = %{0 => [0.5]}
      new_candidates = []
      candidate_scores = []
      next_idx = 1

      {updated_programs, updated_scores} =
        SIMBA.update_program_pool_fixed(
          programs,
          program_scores,
          new_candidates,
          candidate_scores,
          next_idx
        )

      # Should remain unchanged
      assert updated_programs == programs
      assert updated_scores == program_scores
    end
  end

  describe "prune_program_pool/3" do
    test "keeps baseline and top performers" do
      programs = [
        # Baseline
        %Predict{signature: MockSignature, client: :test},
        # Best
        %Predict{signature: MockSignature, client: :test},
        # Worst
        %Predict{signature: MockSignature, client: :test},
        # Middle
        %Predict{signature: MockSignature, client: :test}
      ]

      program_scores = %{
        # Baseline (worst performance)
        0 => [0.1],
        # Best
        1 => [0.9],
        # Worst
        2 => [0.2],
        # Middle
        3 => [0.6]
      }

      keep_count = 3

      {pruned_programs, pruned_scores} =
        SIMBA.prune_program_pool(
          programs,
          program_scores,
          keep_count
        )

      # Should keep exactly 3 programs
      assert length(pruned_programs) == 3

      # Should include baseline and top performers
      scores = Map.values(pruned_scores) |> Enum.map(&hd/1) |> Enum.sort()
      assert 0.1 in scores, "Baseline should be preserved"
      assert 0.9 in scores, "Best performer should be preserved"
      assert 0.6 in scores, "Second best should be preserved"
      refute 0.2 in scores, "Worst performer should be removed"
    end

    test "handles keep_count larger than program pool" do
      programs = [%Predict{signature: MockSignature, client: :test}]
      program_scores = %{0 => [0.5]}
      keep_count = 10

      {pruned_programs, pruned_scores} =
        SIMBA.prune_program_pool(
          programs,
          program_scores,
          keep_count
        )

      # Should keep all programs when keep_count exceeds pool size
      assert length(pruned_programs) == 1
      assert pruned_programs == programs
      assert pruned_scores == program_scores
    end
  end

  describe "update_winning_programs/5" do
    test "adds best candidate when score exceeds threshold" do
      current_winning = [%Predict{signature: MockSignature, client: :test}]

      new_candidates = [
        %Predict{signature: MockSignature, client: :test},
        %Predict{signature: MockSignature, client: :test}
      ]

      # First candidate is good
      candidate_scores = [{0, 0.8}, {1, 0.3}]
      all_programs = []
      program_scores = %{}

      updated_winning =
        SIMBA.update_winning_programs(
          current_winning,
          new_candidates,
          candidate_scores,
          all_programs,
          program_scores
        )

      # Should add the good candidate (score 0.8 > 0.5 threshold)
      assert length(updated_winning) == 2
      assert Enum.at(new_candidates, 0) in updated_winning
    end

    test "does not add candidates with low scores" do
      current_winning = [%Predict{signature: MockSignature, client: :test}]

      new_candidates = [%Predict{signature: MockSignature, client: :test}]
      # Below threshold
      candidate_scores = [{0, 0.3}]
      all_programs = []
      program_scores = %{}

      updated_winning =
        SIMBA.update_winning_programs(
          current_winning,
          new_candidates,
          candidate_scores,
          all_programs,
          program_scores
        )

      # Should not add the low-scoring candidate
      assert updated_winning == current_winning
    end

    test "limits winning programs list size" do
      # Create 20 existing winning programs (at limit)
      current_winning =
        for _ <- 1..20 do
          %Predict{signature: MockSignature, client: :test}
        end

      new_candidates = [%Predict{signature: MockSignature, client: :test}]
      # High score
      candidate_scores = [{0, 0.9}]
      all_programs = []
      program_scores = %{}

      updated_winning =
        SIMBA.update_winning_programs(
          current_winning,
          new_candidates,
          candidate_scores,
          all_programs,
          program_scores
        )

      # Should maintain limit of 20 programs
      assert length(updated_winning) == 20
      # New high-scoring candidate should be at the front
      assert hd(updated_winning) == hd(new_candidates)
    end

    test "handles empty candidate scores" do
      current_winning = [%Predict{signature: MockSignature, client: :test}]
      new_candidates = []
      candidate_scores = []
      all_programs = []
      program_scores = %{}

      updated_winning =
        SIMBA.update_winning_programs(
          current_winning,
          new_candidates,
          candidate_scores,
          all_programs,
          program_scores
        )

      # Should remain unchanged
      assert updated_winning == current_winning
    end
  end
end
