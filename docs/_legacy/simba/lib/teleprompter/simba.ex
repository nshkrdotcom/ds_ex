# lib/teleprompter/simba.ex - Fixed Implementation
defmodule DSPEx.Teleprompter.SIMBA do
  @moduledoc """
  Faithful implementation of DSPy's SIMBA (Stochastic Introspective Mini-Batch Ascent).

  This is a direct port of the original DSPy SIMBA algorithm, which uses stochastic
  hill-climbing with trajectory analysis rather than Bayesian optimization.

  ## Algorithm Overview

  1. **Trajectory Sampling**: Execute programs on mini-batches with different configurations
  2. **Bucket Analysis**: Group execution traces by performance and identify patterns
  3. **Strategy Application**: Use simple heuristics to create new program candidates
  4. **Selection**: Keep best performing programs and iterate

  ## Key Features

  - Mini-batch based optimization for efficiency
  - Trajectory-based introspection of program execution
  - Simple strategy system for program improvement
  - Stochastic exploration with performance-guided selection
  """

  @behaviour DSPEx.Teleprompter

  alias DSPEx.{Example, Program, OptimizedProgram}
  alias DSPEx.Teleprompter.SIMBA.{Trajectory, Bucket}

  @enforce_keys []
  defstruct bsize: 32,
            num_candidates: 6,
            max_steps: 8,
            max_demos: 4,
            demo_input_field_maxlen: 100_000,
            num_threads: nil,
            strategies: [DSPEx.Teleprompter.SIMBA.Strategy.AppendDemo],
            temperature_for_sampling: 0.2,
            temperature_for_candidates: 0.2,
            progress_callback: nil,
            correlation_id: nil

  @type t :: %__MODULE__{
          bsize: pos_integer(),
          num_candidates: pos_integer(),
          max_steps: pos_integer(),
          max_demos: pos_integer(),
          demo_input_field_maxlen: pos_integer(),
          num_threads: pos_integer() | nil,
          strategies: [module()],
          temperature_for_sampling: float(),
          temperature_for_candidates: float(),
          progress_callback: (map() -> any()) | nil,
          correlation_id: String.t() | nil
        }

  @doc """
  Create a new SIMBA teleprompter.

  ## Options

  - `:bsize` - Mini-batch size (default: 32)
  - `:num_candidates` - Candidate programs per iteration (default: 6)
  - `:max_steps` - Maximum optimization steps (default: 8)
  - `:max_demos` - Maximum demos per predictor (default: 4)
  - `:strategies` - List of strategy modules (default: [AppendDemo])
  - `:temperature_for_sampling` - Temperature for trajectory sampling (default: 0.2)
  - `:temperature_for_candidates` - Temperature for candidate selection (default: 0.2)
  - `:progress_callback` - Function called with progress updates
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl DSPEx.Teleprompter
  def compile(student, teacher, trainset, metric_fn, opts \\ [])

  def compile(%__MODULE__{} = teleprompter, student, teacher, trainset, metric_fn, opts) do
    config_opts = struct_to_keyword(teleprompter)
    merged_opts = Keyword.merge(config_opts, opts)
    do_compile(student, teacher, trainset, metric_fn, merged_opts)
  end

  def compile(student, teacher, trainset, metric_fn, opts) when is_list(opts) do
    do_compile(student, teacher, trainset, metric_fn, opts)
  end

  # Main compilation implementation
  defp do_compile(student, teacher, trainset, metric_fn, opts) when is_list(opts) do
    config = struct(__MODULE__, opts)
    correlation_id = config.correlation_id || generate_correlation_id()

    start_time = System.monotonic_time()

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: correlation_id,
        trainset_size: length(trainset),
        config: Map.take(config, [:bsize, :num_candidates, :max_steps])
      }
    )

    result =
      with :ok <- validate_inputs(student, teacher, trainset, metric_fn),
           {:ok, optimized_student} <- run_simba_optimization(
             student,
             teacher,
             trainset,
             metric_fn,
             config,
             correlation_id
           ) do
        {:ok, optimized_student}
      else
        {:error, reason} -> {:error, reason}
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :stop],
      %{duration: duration, success: success},
      %{correlation_id: correlation_id}
    )

    result
  end

  defp run_simba_optimization(student, teacher, trainset, metric_fn, config, correlation_id) do
    try do
      # Initialize properly
      programs = [student]
      program_scores = %{0 => []}
      next_program_idx = 1
      winning_programs = [student]

      # Initialize RNG with better seed
      :rand.seed(:exsplus, {System.unique_integer(), System.system_time(), self() |> :erlang.phash2()})
      data_indices = 0..(length(trainset) - 1) |> Enum.to_list() |> Enum.shuffle()

      # Build predictor mappings
      {predictor2name, name2predictor} = build_predictor_mappings(student)

      # Main optimization loop
      final_state =
        Enum.reduce(0..(config.max_steps - 1),
          {programs, program_scores, winning_programs, next_program_idx},
          fn step, {current_programs, current_scores, current_winning, prog_idx} ->

            emit_telemetry(
              [:dspex, :teleprompter, :simba, :iteration, :start],
              %{step: step},
              %{correlation_id: correlation_id}
            )

            # STEP 1: Get next batch (fixed circular indexing)
            instance_idx = step * config.bsize
            batch_indices = get_circular_batch_indices(data_indices, instance_idx, config.bsize)
            batch = Enum.map(batch_indices, &Enum.at(trainset, &1))

            # STEP 2: Prepare models with temperature variations
            models = prepare_models_for_resampling(List.first(current_programs), config.num_candidates)
            top_programs = select_top_programs(current_programs, current_scores, config.num_candidates)

            # STEP 3: Sample trajectories
            trajectories = sample_trajectories(
              batch,
              top_programs,
              current_programs,
              models,
              metric_fn,
              config,
              correlation_id
            )

            # STEP 4: Create performance buckets
            buckets = create_performance_buckets(trajectories, config, correlation_id)

            # STEP 5: Apply strategies to create candidates
            {new_candidates, updated_prog_idx} = apply_strategies_to_buckets(
              buckets,
              current_programs,
              config,
              prog_idx,
              predictor2name,
              name2predictor,
              correlation_id
            )

            # STEP 6: Evaluate candidates and update state
            candidate_scores = evaluate_candidates_batch(new_candidates, batch, metric_fn)

            # STEP 7: Select winning programs
            best_candidate_program = select_best_from_candidates(new_candidates, candidate_scores)
            updated_winning = [best_candidate_program | current_winning]

            # STEP 8: Update program pool
            {updated_programs, updated_scores} = update_program_pool(
              current_programs,
              current_scores,
              new_candidates,
              candidate_scores,
              updated_prog_idx
            )

            emit_telemetry(
              [:dspex, :teleprompter, :simba, :iteration, :stop],
              %{step: step, candidates_generated: length(new_candidates)},
              %{correlation_id: correlation_id}
            )

            {updated_programs, updated_scores, updated_winning, updated_prog_idx}
          end)

      {_final_programs, _final_scores, final_winning, _final_idx} = final_state

      # Select final best program
      best_program = select_final_best_program(final_winning, trainset, metric_fn)

      {:ok, best_program}
    rescue
      error ->
        emit_telemetry(
          [:dspex, :teleprompter, :simba, :error],
          %{error_type: error.__struct__},
          %{correlation_id: correlation_id, error: inspect(error)}
        )
        {:error, {:optimization_failed, error}}
    catch
      :exit, reason ->
        {:error, {:optimization_exit, reason}}
    end
  end

  # Sample trajectories for the current mini-batch
  defp sample_trajectories(batch, top_programs, all_programs, models, metric_fn, config, correlation_id) do
    exec_pairs =
      for {example, example_idx} <- Enum.with_index(batch),
          {model_config, model_idx} <- Enum.with_index(models) do

        # Use softmax sampling like DSPy
        chosen_prog_idx = softmax_sample(
          top_programs,
          all_programs,
          config.temperature_for_sampling
        )

        candidate_system = Enum.at(all_programs, chosen_prog_idx)

        {candidate_system, model_config, example, example_idx * length(models) + model_idx}
      end

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :trajectory, :start],
      %{trajectory_count: length(exec_pairs)},
      %{correlation_id: correlation_id}
    )

    # Execute trajectories with proper error handling
    trajectories =
      exec_pairs
      |> Task.async_stream(
        fn {program, model_config, example, exec_id} ->
          execute_with_trajectory(program, example, model_config, metric_fn, exec_id)
        end,
        max_concurrency: config.num_threads || 20,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, trajectory} -> trajectory end)
      |> Enum.to_list()

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :trajectory, :sampled],
      %{trajectory_count: length(trajectories)},
      %{correlation_id: correlation_id}
    )

    trajectories
  end

  # Execute a program and capture the trajectory
  defp execute_with_trajectory(program, example, model_config, metric_fn, exec_id) do
    start_time = System.monotonic_time()

    inputs = Example.inputs(example)
    execution_opts = model_config_to_opts(model_config)

    case Program.forward(program, inputs, execution_opts) do
      {:ok, outputs} ->
        score =
          try do
            metric_fn.(example, outputs)
          rescue
            _ -> 0.0
          catch
            _ -> 0.0
          end

        %Trajectory{
          program: program,
          example: example,
          inputs: inputs,
          outputs: outputs,
          score: score,
          duration: System.monotonic_time() - start_time,
          model_config: model_config,
          success: true,
          metadata: %{exec_id: exec_id}
        }

      {:error, reason} ->
        %Trajectory{
          program: program,
          example: example,
          inputs: inputs,
          outputs: %{},
          score: 0.0,
          duration: System.monotonic_time() - start_time,
          model_config: model_config,
          success: false,
          error: reason,
          metadata: %{exec_id: exec_id}
        }
    end
  rescue
    error ->
      %Trajectory{
        program: program,
        example: example,
        inputs: inputs,
        outputs: %{},
        score: 0.0,
        duration: System.monotonic_time() - start_time,
        model_config: model_config,
        success: false,
        error: error,
        metadata: %{exec_id: exec_id}
      }
  end

  # Create performance buckets from trajectories
  defp create_performance_buckets(trajectories, config, correlation_id) do
    emit_telemetry(
      [:dspex, :teleprompter, :simba, :bucket, :start],
      %{trajectory_count: length(trajectories)},
      %{correlation_id: correlation_id}
    )

    # Group trajectories by example index
    trajectories_by_example =
      trajectories
      |> Enum.group_by(fn trajectory ->
        div(trajectory.metadata[:exec_id] || 0, config.num_candidates)
      end)

    # Create buckets with proper DSPy statistics
    buckets =
      trajectories_by_example
      |> Enum.map(fn {_example_idx, example_trajectories} ->
        sorted_trajectories = Enum.sort_by(example_trajectories, &(-&1.score))

        scores = Enum.map(sorted_trajectories, & &1.score)
        max_score = if Enum.empty?(scores), do: 0.0, else: Enum.max(scores)
        min_score = if Enum.empty?(scores), do: 0.0, else: Enum.min(scores)
        avg_score = if Enum.empty?(scores), do: 0.0, else: Enum.sum(scores) / length(scores)

        max_to_min_gap = max_score - min_score
        max_to_avg_gap = max_score - avg_score

        Bucket.new(sorted_trajectories,
          metadata: %{
            max_to_min_gap: max_to_min_gap,
            max_to_avg_gap: max_to_avg_gap,
            max_score: max_score,
            avg_score: avg_score
          }
        )
      end)
      |> Enum.sort_by(fn bucket ->
        {
          -bucket.metadata[:max_to_min_gap],
          -bucket.metadata[:max_score],
          -bucket.metadata[:max_to_avg_gap]
        }
      end)

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :bucket, :created],
      %{bucket_count: length(buckets)},
      %{correlation_id: correlation_id}
    )

    buckets
  end

  # Apply strategies to buckets to generate new candidate programs
  defp apply_strategies_to_buckets(buckets, programs, config, next_program_idx, predictor2name, name2predictor, correlation_id) do
    viable_buckets = Enum.filter(buckets, fn bucket ->
      bucket.metadata[:max_to_min_gap] > 0.01 and bucket.metadata[:max_score] > 0.1
    end)

    top_buckets = Enum.take(viable_buckets, config.num_candidates)

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :strategy, :start],
      %{viable_buckets: length(viable_buckets), selected_buckets: length(top_buckets)},
      %{correlation_id: correlation_id}
    )

    {candidates, updated_idx} =
      Enum.reduce(top_buckets, {[], next_program_idx}, fn bucket, {acc_candidates, current_idx} ->
        program_scores = Enum.map(programs, fn _p -> 0.5 end)
        source_program_idx = softmax_sample_simple(program_scores, config.temperature_for_candidates)
        source_program = Enum.at(programs, source_program_idx)

        case apply_first_applicable_strategy(bucket, source_program, config.strategies,
                                           predictor2name, name2predictor, config) do
          {:ok, new_program} ->
            {[new_program | acc_candidates], current_idx + 1}

          {:skip, _reason} ->
            {acc_candidates, current_idx}
        end
      end)

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :strategy, :applied],
      %{candidates_created: length(candidates)},
      %{correlation_id: correlation_id}
    )

    {Enum.reverse(candidates), updated_idx}
  end

  # Evaluate candidate programs on the batch
  defp evaluate_candidates_batch(candidates, batch, metric_fn) do
    candidates
    |> Enum.with_index()
    |> Task.async_stream(
      fn {candidate, idx} ->
        scores =
          batch
          |> Enum.map(fn example ->
            inputs = Example.inputs(example)

            case Program.forward(candidate, inputs) do
              {:ok, outputs} ->
                try do
                  metric_fn.(example, outputs)
                rescue
                  _ -> 0.0
                end

              {:error, _} -> 0.0
            end
          end)

        avg_score = if Enum.empty?(scores), do: 0.0, else: Enum.sum(scores) / length(scores)
        {idx, avg_score}
      end,
      max_concurrency: 10,
      timeout: 30_000
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, result} -> result end)
    |> Enum.to_list()
  end

  # Select best candidate from evaluation results
  defp select_best_from_candidates(candidates, candidate_scores) do
    if Enum.empty?(candidate_scores) do
      List.first(candidates) || %{}
    else
      {best_idx, _best_score} = Enum.max_by(candidate_scores, fn {_idx, score} -> score end)
      Enum.at(candidates, best_idx) || List.first(candidates) || %{}
    end
  end

  # Update program pool with new candidates and their scores
  defp update_program_pool(programs, program_scores, new_candidates, candidate_scores, _next_idx) do
    updated_programs = programs ++ new_candidates

    updated_scores =
      Enum.reduce(candidate_scores, program_scores, fn {candidate_idx, score}, acc ->
        program_idx = length(programs) + candidate_idx
        Map.update(acc, program_idx, [score], &[score | &1])
      end)

    {updated_programs, updated_scores}
  end

  # Select final best program from winning programs
  defp select_final_best_program(winning_programs, trainset, metric_fn) do
    program_scores =
      winning_programs
      |> Enum.with_index()
      |> Task.async_stream(
        fn {program, _idx} ->
          sample_size = min(50, length(trainset))
          sample = Enum.take_random(trainset, sample_size)

          scores =
            sample
            |> Enum.map(fn example ->
              inputs = Example.inputs(example)

              case Program.forward(program, inputs) do
                {:ok, outputs} ->
                  try do
                    metric_fn.(example, outputs)
                  rescue
                    _ -> 0.0
                  end

                {:error, _} -> 0.0
              end
            end)

          avg_score = if Enum.empty?(scores), do: 0.0, else: Enum.sum(scores) / length(scores)
          {program, avg_score}
        end,
        max_concurrency: 5,
        timeout: 60_000
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, result} -> result end)
      |> Enum.to_list()

    if Enum.empty?(program_scores) do
      List.first(winning_programs)
    else
      {best_program, _best_score} = Enum.max_by(program_scores, fn {_prog, score} -> score end)
      best_program
    end
  end

  # Helper functions

  defp validate_inputs(student, teacher, trainset, metric_fn) do
    cond do
      not is_struct(student) ->
        {:error, :invalid_student_program}

      not is_struct(teacher) ->
        {:error, :invalid_teacher_program}

      not is_list(trainset) or Enum.empty?(trainset) ->
        {:error, :invalid_or_empty_trainset}

      not is_function(metric_fn, 2) ->
        {:error, :invalid_metric_function}

      true ->
        :ok
    end
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  rescue
    _ -> :ok
  end

  defp struct_to_keyword(struct) do
    struct
    |> Map.from_struct()
    |> Enum.to_list()
  end

  defp get_circular_batch_indices(data_indices, start_idx, batch_size) do
    total_size = length(data_indices)

    0..(batch_size - 1)
    |> Enum.map(fn i ->
      idx = rem(start_idx + i, total_size)
      Enum.at(data_indices, idx)
    end)
  end

  defp prepare_models_for_resampling(base_program, num_candidates) do
    base_temp = 0.7

    temperatures = [base_temp] ++
      Enum.map(1..(num_candidates - 1), fn i ->
        0.5 + i * (0.5 / num_candidates)
      end)

    temperatures
    |> Enum.uniq()
    |> Enum.take(num_candidates)
    |> Enum.map(fn temp -> %{temperature: temp} end)
  end

  defp model_config_to_opts(model_config) do
    [temperature: Map.get(model_config, :temperature, 0.7)]
  end

  defp select_top_programs(programs, program_scores, num_candidates) do
    program_avg_scores =
      programs
      |> Enum.with_index()
      |> Enum.map(fn {_program, idx} ->
        scores = Map.get(program_scores, idx, [])
        avg_score = if Enum.empty?(scores), do: 0.5, else: Enum.sum(scores) / length(scores)
        {idx, avg_score}
      end)
      |> Enum.sort_by(fn {_idx, score} -> -score end)

    top_indices =
      program_avg_scores
      |> Enum.take(num_candidates)
      |> Enum.map(fn {idx, _score} -> idx end)

    if 0 in top_indices do
      top_indices
    else
      [0 | Enum.take(top_indices, num_candidates - 1)]
    end
  end

  defp softmax_sample(program_indices, _all_programs, temperature) do
    if is_list(program_indices) and length(program_indices) > 0 do
      scores = Enum.map(program_indices, fn _idx -> 0.5 end)
      weighted_index = softmax_sample_simple(scores, temperature)
      Enum.at(program_indices, weighted_index, List.first(program_indices))
    else
      0
    end
  end

  defp softmax_sample_simple(scores, temperature) do
    if temperature > 0 do
      exp_scores = Enum.map(scores, fn score -> :math.exp(score / temperature) end)
      sum_exp = Enum.sum(exp_scores)

      if sum_exp > 0 do
        probabilities = Enum.map(exp_scores, fn exp_score -> exp_score / sum_exp end)
        weighted_random_choice(probabilities)
      else
        0
      end
    else
      {_max_score, max_idx} = scores |> Enum.with_index() |> Enum.max_by(fn {score, _} -> score end)
      max_idx
    end
  end

  defp weighted_random_choice(probabilities) do
    random_val = :rand.uniform()

    probabilities
    |> Enum.with_index()
    |> Enum.reduce_while(0.0, fn {prob, idx}, acc ->
      new_acc = acc + prob
      if random_val <= new_acc do
        {:halt, idx}
      else
        {:cont, new_acc}
      end
    end)
  end

  defp build_predictor_mappings(program) do
    predictor2name = %{program => "main"}
    name2predictor = %{"main" => program}

    {predictor2name, name2predictor}
  end

  defp apply_first_applicable_strategy(bucket, source_program, strategies, predictor2name, name2predictor, config) do
    opts = %{
      max_demos: config.max_demos,
      demo_input_field_maxlen: config.demo_input_field_maxlen,
      predictor2name: predictor2name,
      name2predictor: name2predictor,
      quality_threshold: 0.7
    }

    strategies
    |> Enum.reduce_while({:skip, "No strategies provided"}, fn strategy_module, _acc ->
      if apply(strategy_module, :applicable?, [bucket, opts]) do
        case apply(strategy_module, :apply, [bucket, source_program, opts]) do
          {:ok, new_program} -> {:halt, {:ok, new_program}}
          {:skip, reason} -> {:cont, {:skip, reason}}
        end
      else
        {:cont, {:skip, "Strategy not applicable"}}
      end
    end)
  end
end
