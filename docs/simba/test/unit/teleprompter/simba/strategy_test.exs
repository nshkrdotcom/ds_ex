defmodule DSPEx.Teleprompter.SIMBA.StrategyTest do
  @moduledoc """
  Unit tests for DSPEx.Teleprompter.SIMBA.Strategy behavior module.
  Tests the strategy behavior contract and utility functions.
  """
  use ExUnit.Case, async: true

  @moduletag :group_1

  alias DSPEx.Teleprompter.SIMBA.{Strategy, Bucket, Trajectory}
  alias DSPEx.{Example, Program}

  # Test strategy implementation for testing
  defmodule TestStrategy do
    @behaviour DSPEx.Teleprompter.SIMBA.Strategy

    @impl true
    def apply(bucket, source_program, opts) do
      case Bucket.best_trajectory(bucket) do
        nil -> {:skip, "No trajectories found"}
        trajectory when trajectory.score > 0.5 -> {:ok, source_program}
        _ -> {:skip, "Score too low"}
      end
    end

    @impl true
    def applicable?(bucket, _opts) do
      case Bucket.best_trajectory(bucket) do
        nil -> false
        trajectory -> trajectory.score > 0.3
      end
    end
  end

  # Strategy without optional callback
  defmodule MinimalStrategy do
    @behaviour DSPEx.Teleprompter.SIMBA.Strategy

    @impl true
    def apply(_bucket, source_program, _opts) do
      {:ok, source_program}
    end
  end

  # Non-strategy module for testing
  defmodule NotAStrategy do
  end

  describe "implements_strategy?/1" do
    test "returns true for proper strategy implementation" do
      assert Strategy.implements_strategy?(TestStrategy)
    end

    test "returns true for minimal strategy implementation" do
      assert Strategy.implements_strategy?(MinimalStrategy)
    end

    test "returns false for non-strategy module" do
      refute Strategy.implements_strategy?(NotAStrategy)
    end

    test "returns false for non-existent module" do
      refute Strategy.implements_strategy?(NonExistentModule)
    end

    test "returns false for invalid input" do
      refute Strategy.implements_strategy?("not_a_module")
      refute Strategy.implements_strategy?(123)
      refute Strategy.implements_strategy?(nil)
    end
  end

  describe "strategy behavior contract" do
    test "apply/3 callback is required" do
      # TestStrategy should have apply/3
      assert function_exported?(TestStrategy, :apply, 3)
      assert function_exported?(MinimalStrategy, :apply, 3)
    end

    test "applicable?/2 callback is optional" do
      # TestStrategy implements it
      assert function_exported?(TestStrategy, :applicable?, 2)

      # MinimalStrategy doesn't implement it
      refute function_exported?(MinimalStrategy, :applicable?, 2)
    end

    test "apply/3 returns proper format" do
      bucket = create_test_bucket([0.8])
      program = create_test_program()

      # Should return {:ok, program} or {:skip, reason}
      result = TestStrategy.apply(bucket, program, %{})
      assert {:ok, ^program} = result
    end

    test "apply/3 can skip with reason" do
      bucket = create_test_bucket([0.2])  # Low score
      program = create_test_program()

      result = TestStrategy.apply(bucket, program, %{})
      assert {:skip, reason} = result
      assert is_binary(reason)
    end

    test "applicable?/2 returns boolean" do
      bucket = create_test_bucket([0.8])
      result = TestStrategy.applicable?(bucket, %{})
      assert is_boolean(result)
    end
  end

  describe "strategy application patterns" do
    test "strategy can analyze bucket quality" do
      high_quality_bucket = create_test_bucket([0.9, 0.8, 0.7])
      low_quality_bucket = create_test_bucket([0.2, 0.1])

      assert TestStrategy.applicable?(high_quality_bucket, %{})
      refute TestStrategy.applicable?(low_quality_bucket, %{})
    end

    test "strategy can handle empty bucket" do
      empty_bucket = create_test_bucket([])
      program = create_test_program()

      result = TestStrategy.apply(empty_bucket, program, %{})
      assert {:skip, _reason} = result

      refute TestStrategy.applicable?(empty_bucket, %{})
    end

    test "strategy receives options parameter" do
      bucket = create_test_bucket([0.8])
      program = create_test_program()
      opts = %{custom_option: "test_value"}

      # Should not crash with custom options
      result = TestStrategy.apply(bucket, program, opts)
      assert {:ok, ^program} = result
    end
  end

  describe "behavior validation" do
    test "validates behavior implementation at compile time" do
      # This test ensures our test strategies actually implement the behavior
      behaviors = TestStrategy.__info__(:attributes)[:behaviour] || []
      assert DSPEx.Teleprompter.SIMBA.Strategy in behaviors

      behaviors = MinimalStrategy.__info__(:attributes)[:behaviour] || []
      assert DSPEx.Teleprompter.SIMBA.Strategy in behaviors
    end

    test "behavior defines required callbacks" do
      # Check that the behavior module defines the expected callbacks
      callbacks = Strategy.behaviour_info(:callbacks)

      # Required callback
      assert {:apply, 3} in callbacks

      # Optional callback
      optional_callbacks = Strategy.behaviour_info(:optional_callbacks)
      assert {:applicable?, 2} in optional_callbacks
    end
  end

  describe "strategy error handling" do
    test "strategy can handle malformed bucket" do
      # Create a bucket-like structure that might cause issues
      fake_bucket = %{trajectories: nil}
      program = create_test_program()

      # Strategy should handle gracefully or raise clear error
      assert_raise(exception when exception in [FunctionClauseError, MatchError, KeyError], fn ->
        TestStrategy.apply(fake_bucket, program, %{})
      end)
    end

    test "strategy can handle nil program" do
      bucket = create_test_bucket([0.8])

      # Strategy should handle gracefully
      result = TestStrategy.apply(bucket, nil, %{})
      assert {:ok, nil} = result
    end
  end

  # Helper functions

  defp create_test_bucket(scores) do
    trajectories = Enum.map(scores, &create_test_trajectory/1)
    Bucket.new(trajectories)
  end

  defp create_test_trajectory(score) do
    program = create_test_program()
    example = Example.new(%{question: "test", answer: "test"})
    inputs = %{question: "test"}
    outputs = %{answer: "test"}

    Trajectory.new(program, example, inputs, outputs, score)
  end

  defp create_test_program do
    %Program{
      signature: %{inputs: [:question], outputs: [:answer]},
      predictors: []
    }
  end
end
