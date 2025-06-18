defmodule DSPEx.Teleprompter.SimbaProgramSelectionTest do
  use ExUnit.Case, async: true
  alias DSPEx.Teleprompter.SIMBA

  @moduletag :group_1

  describe "softmax_sample/3" do
    test "uses real program scores instead of fixed 0.5 values" do
      program_indices = [0, 1, 2]

      program_scores = %{
        # avg: 0.2
        0 => [0.2, 0.3, 0.1],
        # avg: 0.8
        1 => [0.8, 0.9, 0.7],
        # avg: 0.5
        2 => [0.5, 0.6, 0.4]
      }

      # Need to expose the private function for testing
      # This will fail initially as we need to fix the implementation

      # With high temperature, should still respect score distribution
      results =
        for _ <- 1..100 do
          # We'll need to expose this function or create a test helper
          SIMBA.test_softmax_sample(program_indices, program_scores, 0.5)
        end

      # Program 1 (highest score) should be selected most often
      program_1_selections = Enum.count(results, &(&1 == 1))
      program_0_selections = Enum.count(results, &(&1 == 0))

      assert program_1_selections > program_0_selections,
             "Higher scoring program should be selected more frequently"
    end

    test "handles temperature = 0 (greedy selection)" do
      program_indices = [0, 1, 2]
      program_scores = %{0 => [0.2], 1 => [0.9], 2 => [0.5]}

      # Should always select best program (index 1)
      for _ <- 1..10 do
        result = SIMBA.test_softmax_sample(program_indices, program_scores, 0)
        assert result == 1, "Temperature=0 should always select best program"
      end
    end

    test "handles empty program scores gracefully" do
      program_indices = [0, 1]
      program_scores = %{0 => [], 1 => []}

      result = SIMBA.test_softmax_sample(program_indices, program_scores, 1.0)
      assert result in [0, 1], "Should handle empty scores without crashing"
    end
  end

  describe "program pool management" do
    test "select_top_programs_with_baseline/3 includes top-k programs by average score" do
      programs = [:prog_a, :prog_b, :prog_c, :prog_d]

      program_scores = %{
        # baseline: avg 0.25
        0 => [0.2, 0.3],
        # best: avg 0.85
        1 => [0.9, 0.8],
        # worst: avg 0.15
        2 => [0.1, 0.2],
        # good: avg 0.65
        3 => [0.6, 0.7]
      }

      top_indices =
        SIMBA.test_select_top_programs_with_baseline(
          programs,
          program_scores,
          3
        )

      # Should include programs 1, 3, and 0 (baseline)
      assert length(top_indices) == 3
      assert 1 in top_indices, "Best program should be included"
      assert 3 in top_indices, "Second best should be included"
      assert 0 in top_indices, "Baseline should always be included"
    end

    test "always includes baseline even if it's not top-k" do
      programs = [:baseline, :excellent, :great, :good]

      program_scores = %{
        # baseline: worst
        0 => [0.1],
        # excellent
        1 => [0.9],
        # great
        2 => [0.8],
        # good
        3 => [0.7]
      }

      top_indices =
        SIMBA.test_select_top_programs_with_baseline(
          programs,
          program_scores,
          2
        )

      assert 0 in top_indices, "Baseline must always be included"
      assert 1 in top_indices, "Best program should be included"
      assert length(top_indices) == 2
    end
  end
end
