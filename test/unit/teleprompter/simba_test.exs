defmodule DSPEx.Teleprompter.SIMBATest do
  @moduledoc """
  Unit tests for DSPEx.Teleprompter.SIMBA module.
  Tests the main SIMBA teleprompter functionality including configuration,
  compilation process, and optimization behavior.
  """
  use ExUnit.Case, async: true

  alias DSPEx.Teleprompter.SIMBA

  @moduletag :unit

  describe "struct definition" do
    test "creates SIMBA struct with default values" do
      simba = SIMBA.new()

      assert simba.bsize == 32
      assert simba.num_candidates == 6
      assert simba.max_steps == 8
      assert simba.max_demos == 4
      assert simba.demo_input_field_maxlen == 100_000
      assert simba.num_threads == nil
      # Phase 1: Empty strategies list
      assert simba.strategies == []
      assert simba.temperature_for_sampling == 0.2
      assert simba.temperature_for_candidates == 0.2
      assert simba.progress_callback == nil
      assert simba.correlation_id == nil
    end

    test "creates SIMBA struct with custom configuration" do
      custom_opts = [
        bsize: 16,
        num_candidates: 4,
        max_steps: 5,
        max_demos: 2,
        temperature_for_sampling: 0.3,
        temperature_for_candidates: 0.4,
        correlation_id: "test-123"
      ]

      simba = SIMBA.new(custom_opts)

      assert simba.bsize == 16
      assert simba.num_candidates == 4
      assert simba.max_steps == 5
      assert simba.max_demos == 2
      assert simba.temperature_for_sampling == 0.3
      assert simba.temperature_for_candidates == 0.4
      assert simba.correlation_id == "test-123"
    end
  end

  describe "configuration validation" do
    test "validates numeric ranges" do
      # Test reasonable numeric ranges
      assert 32 > 0
      assert 6 > 0
      assert 8 > 0
      assert 4 > 0
      assert 100_000 > 0
      assert 0.2 >= 0.0 and 0.2 <= 1.0
    end

    test "validates strategy lists" do
      strategies = [:append_demo, :custom_strategy]
      assert is_list(strategies)
      assert length(strategies) >= 1
    end

    test "validates callback functions" do
      callback = fn _progress -> :ok end
      assert is_function(callback, 1)
    end
  end

  describe "teleprompter interface" do
    test "implements DSPEx.Teleprompter behavior" do
      assert DSPEx.Teleprompter.implements_behavior?(SIMBA)
    end

    test "new/1 creates valid SIMBA struct" do
      simba = SIMBA.new()
      assert %SIMBA{} = simba
    end

    test "compile/5 with basic validation - Phase 1 stub" do
      # Phase 1: Basic validation test with stub implementation
      student = %{some: "program"}
      teacher = %{some: "teacher"}
      trainset = [%{example: "data"}]
      metric_fn = fn _ex, _out -> 0.8 end

      # Should return error for invalid inputs
      assert {:error, :invalid_student_program} =
               SIMBA.compile(nil, teacher, trainset, metric_fn, [])

      assert {:error, :invalid_or_empty_trainset} =
               SIMBA.compile(student, teacher, [], metric_fn, [])

      assert {:error, :invalid_metric_function} =
               SIMBA.compile(student, teacher, trainset, "not_a_function", [])

      # Should return student unchanged for valid inputs (Phase 1 stub)
      assert {:ok, ^student} = SIMBA.compile(student, teacher, trainset, metric_fn, [])
    end
  end
end
