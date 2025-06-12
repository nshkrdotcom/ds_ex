# dspex/teleprompter/simba/strategies/append_demo.ex
defmodule DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo do
  @moduledoc """
  Strategy that creates demos from successful trajectories.

  This is the core SIMBA strategy that takes successful execution traces
  and adds their input/output pairs as demonstrations to the program.
  """

  @behaviour DSPEx.Teleprompter.SIMBA.Strategy

  alias DSPEx.{Example, OptimizedProgram}
  alias DSPEx.Teleprompter.SIMBA.{Bucket, Trajectory}

  @impl DSPEx.Teleprompter.SIMBA.Strategy
  def apply(bucket, source_program, opts \\ %{}) do
    max_demos = Map.get(opts, :max_demos, 4)
    quality_threshold = Map.get(opts, :quality_threshold, 0.7)
    predictor2name = Map.get(opts, :predictor2name, %{})
    name2predictor = Map.get(opts, :name2predictor, %{})

    # DSPy algorithm: Get the best trajectory and create demo
    case get_best_trajectory(bucket, quality_threshold) do
      {:ok, trajectory} ->
        case create_demo_from_trajectory(trajectory, opts) do
          {:ok, demo} ->
            # Apply DSPy-style demo dropping and addition
            drop_demos_and_add_new(source_program, demo, max_demos, predictor2name, name2predictor)

          {:error, reason} ->
            {:skip, "Failed to create demo: #{reason}"}
        end

      {:error, reason} ->
        {:skip, reason}
    end
  end

  @impl DSPEx.Teleprompter.SIMBA.Strategy
  def applicable?(bucket, opts \\ %{}) do
    quality_threshold = Map.get(opts, :quality_threshold, 0.7)

    case Bucket.best_trajectory(bucket) do
      nil -> false
      trajectory -> Trajectory.quality_score(trajectory) >= quality_threshold
    end
  end

  # Private helper functions

  # DSPy-style demo dropping before adding new ones
  defp drop_demos_and_add_new(source_program, new_demo, max_demos, predictor2name, name2predictor) do
    # First, drop some existing demos (DSPy behavior)
    program_with_dropped_demos = drop_random_demos(source_program, predictor2name, name2predictor, max_demos)

    # Then add the new demo
    add_demo_to_program(program_with_dropped_demos, new_demo, max_demos)
  end

  defp drop_random_demos(program, predictor2name, name2predictor, max_demos) do
    case program do
      %{demos: existing_demos} when is_list(existing_demos) and length(existing_demos) > 0 ->
        # Calculate how many demos to drop (DSPy uses Poisson distribution)
        num_demos = length(existing_demos)
        max_demos_tmp = if max_demos > 0, do: max_demos, else: 3

        # DSPy algorithm: drop based on Poisson distribution
        lambda = num_demos / max_demos_tmp
        num_demos_to_drop = max(poisson_sample(lambda), if(num_demos >= max_demos_tmp, do: 1, else: 0))
        num_demos_to_drop = min(num_demos_to_drop, num_demos)

        if num_demos_to_drop > 0 do
          # Drop random demos
          demos_to_drop_indices =
            0..(num_demos - 1)
            |> Enum.to_list()
            |> Enum.take_random(num_demos_to_drop)
            |> MapSet.new()

          remaining_demos =
            existing_demos
            |> Enum.with_index()
            |> Enum.reject(fn {_demo, idx} -> MapSet.member?(demos_to_drop_indices, idx) end)
            |> Enum.map(fn {demo, _idx} -> demo end)

          %{program | demos: remaining_demos}
        else
          program
        end

      _ ->
        program
    end
  end

  defp poisson_sample(lambda) do
    # Simple Poisson approximation using exponential distribution
    l = :math.exp(-lambda)
    k = 0
    p = 1.0

    poisson_loop(l, k, p, lambda)
  end

  defp poisson_loop(l, k, p, lambda) when p > l do
    k = k + 1
    u = :rand.uniform()
    p = p * u
    poisson_loop(l, k, p, lambda)
  end

  defp poisson_loop(_l, k, _p, _lambda), do: k - 1

  defp get_best_trajectory(bucket, quality_threshold) do
    case Bucket.best_trajectory(bucket) do
      nil ->
        {:error, "No trajectories in bucket"}

      trajectory ->
        if Trajectory.quality_score(trajectory) >= quality_threshold do
          {:ok, trajectory}
        else
          {:error, "Best trajectory score #{Trajectory.quality_score(trajectory)} below threshold #{quality_threshold}"}
        end
    end
  end

  defp create_demo_from_trajectory(trajectory, opts) do
    max_length = Map.get(opts, :demo_input_field_maxlen, 100_000)

    # Truncate input fields if they're too long
    truncated_inputs =
      trajectory.inputs
      |> Enum.map(fn {key, value} ->
        truncated_value =
          if is_binary(value) and String.length(value) > max_length do
            String.slice(value, 0, max_length)
          else
            value
          end
        {key, truncated_value}
      end)
      |> Enum.into(%{})

    # Combine inputs and outputs
    combined_data = Map.merge(truncated_inputs, trajectory.outputs)
    input_keys = Map.keys(trajectory.inputs)

    # Create demonstration example
    demo = Example.new(combined_data, input_keys)

    # Add metadata about the demo's origin
    demo_with_metadata = %{demo |
      data: Map.put(demo.data, :__simba_demo_metadata, %{
        original_score: trajectory.score,
        created_at: DateTime.utc_now(),
        strategy: :append_demo
      })
    }

    {:ok, demo_with_metadata}
  end

  defp add_demo_to_program(program, demo, max_demos) do
    case program do
      # Program has native demo support
      %{demos: existing_demos} when is_list(existing_demos) ->
        # Add new demo and limit total demos
        new_demos = [demo | existing_demos] |> Enum.take(max_demos)
        updated_program = %{program | demos: new_demos}
        {:ok, updated_program}

      # Program is already an OptimizedProgram
      %OptimizedProgram{demos: existing_demos} ->
        new_demos = [demo | existing_demos] |> Enum.take(max_demos)
        updated_program = OptimizedProgram.replace_demos(program, new_demos)
        {:ok, updated_program}

      # Program needs to be wrapped with OptimizedProgram
      _ ->
        optimized = OptimizedProgram.new(program, [demo], %{
          strategy: :append_demo,
          created_at: DateTime.utc_now()
        })
        {:ok, optimized}
    end
  end
end
