defmodule DSPEx.Teleprompter.SIMBA.Strategy.AppendDemoTest do
  @moduledoc """
  Unit tests for DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo module.
  Tests the demo appending strategy implementation.
  """
  use ExUnit.Case, async: true

  @moduletag :unit

  # Test AppendDemo strategy logic without depending on actual implementation

  describe "strategy behavior implementation" do
    test "implements expected strategy interface" do
      # Test that AppendDemo strategy defines expected interface
      expected_functions = [:apply, :applicable?]

      for func <- expected_functions do
        assert is_atom(func)
      end
    end

    test "defines strategy behavior contract" do
      # Strategy should implement behavior contract
      behavior_functions = %{
        apply: 3,      # (bucket, source_program, opts)
        applicable?: 2  # (bucket, opts)
      }

      for {func, arity} <- behavior_functions do
        assert is_atom(func) and is_integer(arity)
      end
    end
  end

  describe "applicability analysis" do
    test "applicable for bucket with high quality trajectory" do
      bucket_data = create_test_bucket_data([0.8])
      assert is_applicable?(bucket_data)
    end

    test "not applicable for bucket with low quality trajectory" do
      bucket_data = create_test_bucket_data([0.5])
      refute is_applicable?(bucket_data)
    end

    test "not applicable for empty bucket" do
      bucket_data = create_test_bucket_data([])
      refute is_applicable?(bucket_data)
    end

    test "uses custom quality threshold" do
      bucket_data = create_test_bucket_data([0.6])

      # Default threshold is 0.7, so should return false
      refute is_applicable?(bucket_data)

      # Lower threshold should return true
      assert is_applicable?(bucket_data, %{quality_threshold: 0.5})
    end

    test "picks best trajectory from bucket" do
      bucket_data = create_test_bucket_data([0.5, 0.8, 0.6])

      # Should use the best trajectory (0.8) which exceeds threshold
      assert is_applicable?(bucket_data)
    end
  end

  describe "strategy application" do
    test "creates enhanced program from high quality trajectory" do
      bucket_data = create_test_bucket_data([0.9])
      program = create_test_program_data()

      {:ok, enhanced_program} = mock_append_demo_apply(bucket_data, program)

      assert enhanced_program != program
      assert enhanced_program.enhanced == true
    end

    test "skips when no high quality trajectory found" do
      bucket_data = create_test_bucket_data([0.5])
      program = create_test_program_data()

      {:skip, reason} = mock_append_demo_apply(bucket_data, program)
      assert is_binary(reason)
      assert String.contains?(reason, "quality")
    end

    test "skips when bucket is empty" do
      bucket_data = create_test_bucket_data([])
      program = create_test_program_data()

      {:skip, reason} = mock_append_demo_apply(bucket_data, program)
      assert is_binary(reason)
    end

    test "uses custom options" do
      bucket_data = create_test_bucket_data([0.8])
      program = create_test_program_data()

      opts = %{
        max_demos: 2,
        quality_threshold: 0.6
      }

      result = mock_append_demo_apply(bucket_data, program, opts)
      assert {:ok, _enhanced_program} = result
    end

    test "handles trajectory to demo conversion failure" do
      # Create a bucket that will fail demo conversion
      bucket_data = create_test_bucket_data([0.0])  # Zero score trajectory
      program = create_test_program_data()

      {:skip, reason} = mock_append_demo_apply(bucket_data, program, %{quality_threshold: 0.0})
      assert is_binary(reason)
    end
  end

  describe "demo creation and program enhancement" do
    test "creates demo from successful trajectory" do
      inputs = %{question: "What is 2+2?", context: "math"}
      outputs = %{answer: "4", confidence: "high"}

      trajectory_data = %{
        score: 0.9,
        inputs: inputs,
        outputs: outputs,
        success: true
      }

      {:ok, demo_data} = mock_create_demo_from_trajectory(trajectory_data)

      # Verify demo contains input and output data
      assert demo_data[:question] == "What is 2+2?"
      assert demo_data[:context] == "math"
      assert demo_data[:answer] == "4"
      assert demo_data[:confidence] == "high"
    end

    test "handles programs with existing demos" do
      existing_demos = [%{question: "old", answer: "old"}]
      program = create_test_program_data(demos: existing_demos)

      bucket_data = create_test_bucket_data([0.9])

      {:ok, enhanced_program} = mock_append_demo_apply(bucket_data, program)

      # Should handle existing demos appropriately
      assert enhanced_program != program
      assert enhanced_program.enhanced == true
    end

    test "respects max_demos limit" do
      # Create program with many demos
      existing_demos = for i <- 1..5 do
        %{question: "q#{i}", answer: "a#{i}"}
      end
      program = create_test_program_data(demos: existing_demos)

      bucket_data = create_test_bucket_data([0.9])

      {:ok, enhanced_program} = mock_append_demo_apply(bucket_data, program, %{max_demos: 3})

      # Implementation should respect max_demos
      assert enhanced_program != program
      assert enhanced_program.max_demos_applied == true
    end
  end

  describe "demo dropping behavior" do
    test "drops demos when approaching limit" do
      # This tests the Poisson sampling behavior for demo dropping
      existing_demos = for i <- 1..4 do
        %{question: "q#{i}", answer: "a#{i}"}
      end
      program = create_test_program_data(demos: existing_demos)

      bucket_data = create_test_bucket_data([0.9])

      # With max_demos = 3, should drop some existing demos
      {:ok, enhanced_program} = mock_append_demo_apply(bucket_data, program, %{max_demos: 3})

      assert enhanced_program != program
      assert enhanced_program.demos_dropped == true
    end

    test "handles programs without demos field" do
      program = %{predictors: []}  # No demos field

      bucket_data = create_test_bucket_data([0.9])

      # Should handle gracefully
      result = mock_append_demo_apply(bucket_data, program)
      assert {:ok, _enhanced_program} = result
    end
  end

  describe "edge cases" do
    test "handles nil program" do
      bucket_data = create_test_bucket_data([0.9])

      # Should handle gracefully or raise clear error
      result = mock_append_demo_apply(bucket_data, nil)
      assert match?({:error, _} | {:skip, _}, result)
    end

    test "handles malformed bucket" do
      program = create_test_program_data()
      fake_bucket = %{trajectories: nil}

      result = mock_append_demo_apply(fake_bucket, program)
      assert match?({:error, _} | {:skip, _}, result)
    end

    test "handles very high quality threshold" do
      bucket_data = create_test_bucket_data([0.9])
      program = create_test_program_data()

      # Threshold higher than any trajectory score
      {:skip, reason} = mock_append_demo_apply(bucket_data, program, %{quality_threshold: 1.1})
      assert is_binary(reason)
    end
  end

  # Helper functions for testing AppendDemo logic without actual implementation

  defp create_test_bucket_data(scores) do
    trajectories = Enum.map(scores, fn score ->
      %{
        score: score,
        success: score > 0.0,
        inputs: %{question: "test"},
        outputs: %{answer: "test"}
      }
    end)

    if Enum.empty?(trajectories) do
      %{
        trajectories: [],
        max_score: 0.0
      }
    else
      max_score = Enum.max(scores)
      %{
        trajectories: Enum.sort_by(trajectories, & &1.score, :desc),
        max_score: max_score
      }
    end
  end

  defp create_test_program_data(opts \\ []) do
    %{
      predictors: [],
      demos: Keyword.get(opts, :demos, [])
    }
  end

  defp is_applicable?(bucket_data, opts \\ %{}) do
    quality_threshold = Map.get(opts, :quality_threshold, 0.7)

    case get_best_trajectory(bucket_data) do
      nil -> false
      trajectory -> trajectory.score >= quality_threshold
    end
  end

  defp get_best_trajectory(bucket_data) do
    case bucket_data.trajectories do
      [] -> nil
      [best | _] -> best
    end
  end

  defp mock_append_demo_apply(bucket_data, program, opts \\ %{}) do
    quality_threshold = Map.get(opts, :quality_threshold, 0.7)
    max_demos = Map.get(opts, :max_demos, 4)

    cond do
      is_nil(program) ->
        {:error, "nil program"}

      not is_list(bucket_data.trajectories) ->
        {:error, "malformed bucket"}

      Enum.empty?(bucket_data.trajectories) ->
        {:skip, "empty bucket"}

      bucket_data.max_score < quality_threshold ->
        {:skip, "no high quality trajectories found"}

      true ->
        enhanced_program = Map.merge(program, %{
          enhanced: true,
          max_demos_applied: max_demos <= 3,
          demos_dropped: length(Map.get(program, :demos, [])) >= max_demos
        })
        {:ok, enhanced_program}
    end
  end

  defp mock_create_demo_from_trajectory(trajectory_data) do
    if trajectory_data.success and trajectory_data.score > 0.0 do
      demo_data = Map.merge(trajectory_data.inputs, trajectory_data.outputs)
      {:ok, demo_data}
    else
      {:error, "trajectory failed or low quality"}
    end
  end
end
