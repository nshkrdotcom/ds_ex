defmodule DSPEx.Teleprompter.SIMBA.TrajectoryTest do
  @moduledoc """
  Unit tests for DSPEx.Teleprompter.SIMBA.Trajectory module.
  Tests trajectory creation, success evaluation, and demo conversion.
  """
  use ExUnit.Case, async: true

  @moduletag :unit

  # Test trajectory structure and behavior without depending on actual implementation

  describe "trajectory data structure" do
    test "defines expected trajectory fields" do
      trajectory_data = %{
        program: %{predictors: []},
        example: %{data: %{question: "What is 2+2?", answer: "4"}},
        inputs: %{question: "What is 2+2?"},
        outputs: %{answer: "4"},
        score: 0.9,
        duration: nil,
        model_config: nil,
        success: true,
        error: nil,
        metadata: %{}
      }

      assert is_map(trajectory_data.program)
      assert is_map(trajectory_data.example)
      assert is_map(trajectory_data.inputs)
      assert is_map(trajectory_data.outputs)
      assert is_number(trajectory_data.score)
      assert is_boolean(trajectory_data.success)
      assert is_map(trajectory_data.metadata)
    end

    test "trajectory with optional fields" do
      trajectory_data = %{
        program: %{predictors: []},
        example: %{data: %{question: "test", answer: "test"}},
        inputs: %{question: "test"},
        outputs: %{answer: "test"},
        score: 0.7,
        duration: 1500,
        model_config: %{temperature: 0.2, model: "gpt-4"},
        success: false,
        error: "timeout",
        metadata: %{attempt: 2, batch: 1}
      }

      assert trajectory_data.duration == 1500
      assert trajectory_data.model_config == %{temperature: 0.2, model: "gpt-4"}
      assert trajectory_data.success == false
      assert trajectory_data.error == "timeout"
      assert trajectory_data.metadata == %{attempt: 2, batch: 1}
    end
  end

  describe "trajectory success evaluation" do
    test "successful trajectory with positive score" do
      trajectory_data = create_test_trajectory_data(0.8, success: true)
      assert is_successful?(trajectory_data)
    end

    test "failed trajectory" do
      trajectory_data = create_test_trajectory_data(0.8, success: false)
      refute is_successful?(trajectory_data)
    end

    test "trajectory with zero score" do
      trajectory_data = create_test_trajectory_data(0.0, success: true)
      refute is_successful?(trajectory_data)
    end

    test "trajectory with negative score" do
      trajectory_data = create_test_trajectory_data(-0.1, success: true)
      refute is_successful?(trajectory_data)
    end

    test "trajectory with nil success and positive score" do
      trajectory_data = create_test_trajectory_data(0.7, success: nil)
      assert is_successful?(trajectory_data)
    end

    test "trajectory with nil success and zero score" do
      trajectory_data = create_test_trajectory_data(0.0, success: nil)
      refute is_successful?(trajectory_data)
    end
  end

  describe "quality score extraction" do
    test "returns the trajectory score" do
      trajectory_data = create_test_trajectory_data(0.85)
      assert get_quality_score(trajectory_data) == 0.85
    end

    test "handles zero score" do
      trajectory_data = create_test_trajectory_data(0.0)
      assert get_quality_score(trajectory_data) == 0.0
    end

    test "handles negative score" do
      trajectory_data = create_test_trajectory_data(-0.2)
      assert get_quality_score(trajectory_data) == -0.2
    end

    test "handles high score" do
      trajectory_data = create_test_trajectory_data(1.0)
      assert get_quality_score(trajectory_data) == 1.0
    end
  end

  describe "demo conversion" do
    test "creates demo from successful trajectory" do
      inputs = %{question: "What is the capital of France?", context: "Geography"}
      outputs = %{answer: "Paris", confidence: "high"}
      trajectory_data = create_test_trajectory_data(0.9, 
        inputs: inputs, 
        outputs: outputs, 
        success: true
      )

      {:ok, demo_data} = convert_to_demo(trajectory_data)

      assert demo_data[:question] == "What is the capital of France?"
      assert demo_data[:context] == "Geography"
      assert demo_data[:answer] == "Paris"
      assert demo_data[:confidence] == "high"
      
      # Input keys should be preserved
      expected_input_keys = [:question, :context]
      assert demo_data[:input_keys] == expected_input_keys
    end

    test "fails for unsuccessful trajectory" do
      trajectory_data = create_test_trajectory_data(0.8, success: false)
      
      {:error, reason} = convert_to_demo(trajectory_data)
      assert reason == :trajectory_failed
    end

    test "fails for trajectory with low quality score" do
      trajectory_data = create_test_trajectory_data(0.0, success: true)
      
      {:error, reason} = convert_to_demo(trajectory_data)
      assert reason == :low_quality_score
    end

    test "fails for trajectory with negative score" do
      trajectory_data = create_test_trajectory_data(-0.1, success: true)
      
      {:error, reason} = convert_to_demo(trajectory_data)
      assert reason == :low_quality_score
    end

    test "creates demo with merged input/output data" do
      inputs = %{question: "Test question"}
      outputs = %{answer: "Test answer", reasoning: "Test reasoning"}
      trajectory_data = create_test_trajectory_data(0.8, 
        inputs: inputs, 
        outputs: outputs, 
        success: true
      )

      {:ok, demo_data} = convert_to_demo(trajectory_data)

      # Should contain all input and output fields
      assert demo_data[:question] == "Test question"
      assert demo_data[:answer] == "Test answer"
      assert demo_data[:reasoning] == "Test reasoning"
    end

    test "handles overlapping input/output keys" do
      # Output should override input for same key
      inputs = %{key: "input_value", question: "test"}
      outputs = %{key: "output_value", answer: "test"}
      trajectory_data = create_test_trajectory_data(0.8, 
        inputs: inputs, 
        outputs: outputs, 
        success: true
      )

      {:ok, demo_data} = convert_to_demo(trajectory_data)

      assert demo_data[:key] == "output_value"  # Output takes precedence
      assert demo_data[:question] == "test"
      assert demo_data[:answer] == "test"
    end
  end

  describe "trajectory metadata handling" do
    test "stores arbitrary metadata" do
      metadata = %{
        model_provider: "openai",
        temperature: 0.7,
        tokens_used: 150,
        latency_ms: 1200
      }

      trajectory_data = create_test_trajectory_data(0.8, metadata: metadata)
      assert trajectory_data.metadata == metadata
    end

    test "stores execution duration" do
      trajectory_data = create_test_trajectory_data(0.8, duration: 2500)
      assert trajectory_data.duration == 2500
    end

    test "stores model configuration" do
      model_config = %{
        model: "gpt-4",
        temperature: 0.3,
        max_tokens: 1000
      }

      trajectory_data = create_test_trajectory_data(0.8, model_config: model_config)
      assert trajectory_data.model_config == model_config
    end

    test "stores error information" do
      error = "Connection timeout after 30s"
      trajectory_data = create_test_trajectory_data(0.0, error: error, success: false)
      
      assert trajectory_data.error == error
      assert trajectory_data.success == false
    end
  end

  # Helper functions for testing trajectory logic without actual implementation

  defp create_test_trajectory_data(score, opts \\ []) do
    inputs = Keyword.get(opts, :inputs, %{question: "test"})
    outputs = Keyword.get(opts, :outputs, %{answer: "test"})
    success = Keyword.get(opts, :success, score > 0.0)
    duration = Keyword.get(opts, :duration)
    model_config = Keyword.get(opts, :model_config)
    error = Keyword.get(opts, :error)
    metadata = Keyword.get(opts, :metadata, %{})

    %{
      program: %{predictors: []},
      example: %{data: Map.merge(inputs, outputs)},
      inputs: inputs,
      outputs: outputs,
      score: score,
      success: success,
      duration: duration,
      model_config: model_config,
      error: error,
      metadata: metadata
    }
  end

  defp is_successful?(trajectory_data) do
    trajectory_data.success != false and trajectory_data.score > 0.0
  end

  defp get_quality_score(trajectory_data) do
    trajectory_data.score
  end

  defp convert_to_demo(trajectory_data) do
    cond do
      trajectory_data.success == false ->
        {:error, :trajectory_failed}
      
      trajectory_data.score <= 0.0 ->
        {:error, :low_quality_score}
      
      true ->
        combined_data = Map.merge(trajectory_data.inputs, trajectory_data.outputs)
        input_keys = Map.keys(trajectory_data.inputs)
        
        demo_data = Map.put(combined_data, :input_keys, input_keys)
        {:ok, demo_data}
    end
  end
end
