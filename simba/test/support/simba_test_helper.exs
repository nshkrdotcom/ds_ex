defmodule SIMBA.TestHelper do
  @moduledoc """
  Test helper functions for SIMBA unit tests.
  Provides common utilities for creating test data and mocking dependencies.
  """

  alias DSPEx.Teleprompter.SIMBA.{Bucket, Trajectory}
  alias DSPEx.{Example, Program}

  @doc """
  Creates a test program with basic structure.
  """
  def create_test_program(opts \\ []) do
    inputs = Keyword.get(opts, :inputs, [:question])
    outputs = Keyword.get(opts, :outputs, [:answer])
    demos = Keyword.get(opts, :demos, [])
    predictors = Keyword.get(opts, :predictors, [])

    %Program{
      signature: %{inputs: inputs, outputs: outputs},
      predictors: predictors,
      demos: demos
    }
  end

  @doc """
  Creates a test example with given data.
  """
  def create_test_example(data \\ %{}) do
    default_data = %{question: "test question", answer: "test answer"}
    example_data = Map.merge(default_data, data)
    Example.new(example_data)
  end

  @doc """
  Creates a test trajectory with specified score and options.
  """
  def create_test_trajectory(score, opts \\ []) do
    program = Keyword.get(opts, :program, create_test_program())
    example = Keyword.get(opts, :example, create_test_example())
    inputs = Keyword.get(opts, :inputs, %{question: "test"})
    outputs = Keyword.get(opts, :outputs, %{answer: "test"})
    
    trajectory_opts = Keyword.drop(opts, [:program, :example, :inputs, :outputs])
    
    Trajectory.new(program, example, inputs, outputs, score, trajectory_opts)
  end

  @doc """
  Creates a test bucket with trajectories of specified scores.
  """
  def create_test_bucket(scores, opts \\ []) do
    trajectories = Enum.map(scores, fn score ->
      create_test_trajectory(score, opts)
    end)
    
    bucket_opts = Keyword.take(opts, [:metadata])
    Bucket.new(trajectories, bucket_opts)
  end

  @doc """
  Creates multiple test buckets with different score patterns.
  """
  def create_test_buckets(bucket_specs) do
    Enum.map(bucket_specs, fn
      scores when is_list(scores) ->
        create_test_bucket(scores)
      {scores, opts} ->
        create_test_bucket(scores, opts)
    end)
  end

  @doc """
  Generates a list of test examples for training/testing.
  """
  def generate_test_examples(count, opts \\ []) do
    base_question = Keyword.get(opts, :base_question, "What is")
    base_answer = Keyword.get(opts, :base_answer, "answer")
    
    for i <- 1..count do
      create_test_example(%{
        question: "#{base_question} #{i}?",
        answer: "#{base_answer} #{i}"
      })
    end
  end

  @doc """
  Creates a mock metric function for testing.
  """
  def create_mock_metric(behavior \\ :default) do
    case behavior do
      :default ->
        fn _example, _outputs -> 0.8 end
      
      :variable ->
        fn _example, outputs ->
          # Score based on answer length as a simple heuristic
          answer = Map.get(outputs, :answer, "")
          min(String.length(answer) / 10.0, 1.0)
        end
      
      :failing ->
        fn _example, _outputs -> 0.0 end
      
      :random ->
        fn _example, _outputs -> :rand.uniform() end
      
      custom_fn when is_function(custom_fn) ->
        custom_fn
    end
  end

  @doc """
  Asserts that a value is within a reasonable floating point range.
  """
  def assert_score_range(score, min \\ 0.0, max \\ 1.0) do
    assert score >= min, "Score #{score} below minimum #{min}"
    assert score <= max, "Score #{score} above maximum #{max}"
  end

  @doc """
  Asserts that statistics map contains expected keys with proper types.
  """
  def assert_valid_statistics(stats) do
    required_keys = [
      :trajectory_count, :successful_count, :max_score, 
      :min_score, :avg_score, :score_variance, :improvement_potential
    ]
    
    for key <- required_keys do
      assert Map.has_key?(stats, key), "Missing key: #{key}"
    end
    
    assert is_integer(stats.trajectory_count)
    assert is_integer(stats.successful_count)
    assert is_float(stats.max_score) or is_integer(stats.max_score)
    assert is_float(stats.min_score) or is_integer(stats.min_score)
    assert is_float(stats.avg_score) or is_integer(stats.avg_score)
    assert is_float(stats.score_variance) or is_integer(stats.score_variance)
    assert is_boolean(stats.improvement_potential)
  end

  @doc """
  Asserts that bucket has expected structure and values.
  """
  def assert_valid_bucket(bucket) do
    assert %Bucket{} = bucket
    assert is_list(bucket.trajectories)
    assert is_number(bucket.max_score)
    assert is_number(bucket.min_score)
    assert is_number(bucket.avg_score)
    assert is_number(bucket.max_to_min_gap)
    assert is_number(bucket.max_to_avg_gap)
    assert is_map(bucket.metadata)
  end

  @doc """
  Asserts that trajectory has expected structure and values.
  """
  def assert_valid_trajectory(trajectory) do
    assert %Trajectory{} = trajectory
    assert is_struct(trajectory.program)
    assert %Example{} = trajectory.example
    assert is_map(trajectory.inputs)
    assert is_map(trajectory.outputs)
    assert is_number(trajectory.score)
  end

  @doc """
  Simulates program execution for testing purposes.
  """
  def mock_program_forward(program, inputs, result \\ nil) do
    default_result = {:ok, %{answer: "mocked answer"}}
    result || default_result
  end

  @doc """
  Creates a progress callback for testing.
  """
  def create_test_progress_callback do
    parent = self()
    fn progress ->
      send(parent, {:progress_update, progress})
    end
  end

  @doc """
  Waits for and returns progress updates sent by callback.
  """
  def receive_progress_updates(timeout \\ 1000) do
    receive_progress_updates([], timeout)
  end

  defp receive_progress_updates(acc, timeout) do
    receive do
      {:progress_update, progress} ->
        receive_progress_updates([progress | acc], timeout)
    after
      timeout ->
        Enum.reverse(acc)
    end
  end
end
