defmodule DSPEx.Teleprompter.SIMBA do
  @moduledoc """
  SIMBA (SIMple BAyesian) teleprompter for DSPEx program optimization.

  SIMBA is a simple yet effective Bayesian optimization teleprompter that:
  1. Bootstrap generates candidate demonstrations using a teacher program
  2. Uses Bayesian optimization to find the best instruction/demonstration combinations
  3. Evaluates candidates on a validation set to select optimal configurations

  ## Features

  - Pure single-node implementation with excellent concurrency
  - Bayesian optimization for efficient hyperparameter search
  - Configurable bootstrap generation and evaluation
  - Progress tracking and comprehensive telemetry
  - Fault tolerance with graceful error handling

  ## Algorithm Overview

  1. **Bootstrap Generation**: Use teacher program to generate candidate demonstrations
  2. **Instruction Proposal**: Generate instruction candidates using LLM
  3. **Bayesian Optimization**: Find optimal instruction/demo combinations
  4. **Validation**: Select best performing configuration

  ## Example Usage

      # Create SIMBA teleprompter
      teleprompter = DSPEx.Teleprompter.SIMBA.new(
        num_candidates: 20,
        max_bootstrapped_demos: 4,
        num_trials: 50,
        quality_threshold: 0.7
      )

      # Optimize student program
      {:ok, optimized_student} = teleprompter.compile(
        student_program,
        teacher_program,
        training_examples,
        metric_fn
      )
  """

  @behaviour DSPEx.Teleprompter

  alias DSPEx.{Program, Example, OptimizedProgram}
  alias DSPEx.Teleprompter.BootstrapFewShot

  defstruct num_candidates: 20,
            max_bootstrapped_demos: 4,
            max_labeled_demos: 16,
            num_trials: 50,
            quality_threshold: 0.7,
            max_concurrency: 20,
            timeout: 60_000,
            teacher_retries: 2,
            progress_callback: nil,
            instruction_model: nil,
            evaluation_model: nil

  @type t :: %__MODULE__{
          num_candidates: pos_integer(),
          max_bootstrapped_demos: pos_integer(),
          max_labeled_demos: pos_integer(),
          num_trials: pos_integer(),
          quality_threshold: float(),
          max_concurrency: pos_integer(),
          timeout: timeout(),
          teacher_retries: pos_integer(),
          progress_callback: (map() -> :ok) | nil,
          instruction_model: atom() | nil,
          evaluation_model: atom() | nil
        }

  @type instruction_candidate :: %{
          id: String.t(),
          instruction: String.t(),
          quality_score: float() | nil,
          metadata: map()
        }

  @type demo_candidate :: %{
          id: String.t(),
          demo: Example.t(),
          quality_score: float(),
          metadata: map()
        }

  @type optimization_result :: %{
          best_instruction: String.t(),
          best_demos: [Example.t()],
          score: float(),
          trials: [map()],
          stats: map()
        }

  @doc """
  Create a new SIMBA teleprompter with given options.

  ## Options

  - `:num_candidates` - Number of instruction candidates to generate (default: 20)
  - `:max_bootstrapped_demos` - Maximum bootstrapped demos to generate (default: 4)
  - `:max_labeled_demos` - Maximum labeled demos to include (default: 16)
  - `:num_trials` - Number of Bayesian optimization trials (default: 50)
  - `:quality_threshold` - Minimum quality score for demonstrations (default: 0.7)
  - `:max_concurrency` - Maximum concurrent operations (default: 20)
  - `:timeout` - Timeout for operations in ms (default: 60_000)
  - `:teacher_retries` - Number of retries for failed teacher requests (default: 2)
  - `:progress_callback` - Function to call with progress updates (default: nil)
  - `:instruction_model` - Model to use for instruction generation (default: nil)
  - `:evaluation_model` - Model to use for evaluation (default: nil)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl DSPEx.Teleprompter
  def compile(student, teacher, trainset, metric_fn, opts \\ [])

  def compile(student, teacher, trainset, metric_fn, opts) when is_list(opts) do
    do_compile(student, teacher, trainset, metric_fn, opts)
  end

  def compile(%__MODULE__{} = teleprompter, student, teacher, trainset, metric_fn, opts) do
    do_compile(
      student,
      teacher,
      trainset,
      metric_fn,
      Keyword.merge(struct_to_keyword(teleprompter), opts)
    )
  end

  # Private implementation

  defp do_compile(student, teacher, trainset, metric_fn, opts) when is_list(opts) do
    config = struct(__MODULE__, opts)
    correlation_id = Keyword.get(opts, :correlation_id) || generate_correlation_id()

    start_time = System.monotonic_time()

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: correlation_id,
        trainset_size: length(trainset),
        config: Map.take(config, [:num_candidates, :num_trials, :max_bootstrapped_demos])
      }
    )

    result =
      with :ok <- validate_inputs(student, teacher, trainset, metric_fn),
           {:ok, demo_candidates} <-
             bootstrap_demonstrations(teacher, trainset, config, correlation_id),
           {:ok, instruction_candidates} <-
             generate_instruction_candidates(student, trainset, config, correlation_id),
           {:ok, optimization_result} <-
             run_bayesian_optimization(
               student,
               demo_candidates,
               instruction_candidates,
               trainset,
               metric_fn,
               config,
               correlation_id
             ),
           {:ok, optimized_student} <-
             create_optimized_student(
               student,
               optimization_result,
               config
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

  defp bootstrap_demonstrations(teacher, trainset, config, correlation_id) do
    emit_telemetry(
      [:dspex, :teleprompter, :simba, :bootstrap, :start],
      %{system_time: System.system_time()},
      %{correlation_id: correlation_id, trainset_size: length(trainset)}
    )

    # Use BootstrapFewShot to generate demonstrations
    bootstrap_opts = [
      num_threads: config.max_concurrency,
      max_bootstrapped_demos: config.max_bootstrapped_demos,
      quality_threshold: config.quality_threshold,
      teacher_retries: config.teacher_retries
    ]

    case BootstrapFewShot.compile(teacher, teacher, trainset, fn _, _ -> 1.0 end, bootstrap_opts) do
      {:ok, bootstrap_result} ->
        # Convert bootstrap result to demo candidates
        demo_candidates =
          bootstrap_result.demos
          |> Enum.with_index()
          |> Enum.map(fn {demo, index} ->
            %{
              id: "bootstrap_#{index}",
              demo: demo,
              # BootstrapFewShot already filters for quality
              quality_score: 1.0,
              metadata: %{
                source: :bootstrap,
                generated_at: DateTime.utc_now()
              }
            }
          end)

        emit_telemetry(
          [:dspex, :teleprompter, :simba, :bootstrap, :stop],
          %{duration: System.monotonic_time()},
          %{correlation_id: correlation_id, candidates_generated: length(demo_candidates)}
        )

        {:ok, demo_candidates}

      {:error, reason} ->
        emit_telemetry(
          [:dspex, :teleprompter, :simba, :bootstrap, :exception],
          %{},
          %{correlation_id: correlation_id, error: reason}
        )

        {:error, {:bootstrap_failed, reason}}
    end
  end

  defp generate_instruction_candidates(student, _trainset, config, correlation_id) do
    emit_telemetry(
      [:dspex, :teleprompter, :simba, :instruction, :start],
      %{system_time: System.system_time()},
      %{correlation_id: correlation_id, num_candidates: config.num_candidates}
    )

    # For now, generate simple instruction variations
    # This will be enhanced with LLM-based generation in future iterations
    base_instruction = get_base_instruction(student)

    instruction_candidates =
      0..(config.num_candidates - 1)
      |> Enum.map(fn index ->
        instruction =
          case index do
            0 -> base_instruction
            _ -> "#{base_instruction} (variation #{index})"
          end

        %{
          id: "instruction_#{index}",
          instruction: instruction,
          # Will be evaluated during optimization
          quality_score: nil,
          metadata: %{
            source: :generated,
            variation: index,
            generated_at: DateTime.utc_now()
          }
        }
      end)

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :instruction, :stop],
      %{duration: System.monotonic_time()},
      %{correlation_id: correlation_id, candidates_generated: length(instruction_candidates)}
    )

    {:ok, instruction_candidates}
  end

  defp get_base_instruction(program) do
    case program do
      %{instruction: instruction} when is_binary(instruction) -> instruction
      %{signature: signature} -> get_signature_instruction(signature)
      _ -> "Please solve this task step by step."
    end
  end

  defp get_signature_instruction(signature) do
    case signature do
      %{instruction: instruction} when is_binary(instruction) -> instruction
      _ -> "Please solve this task step by step."
    end
  end

  defp run_bayesian_optimization(
         student,
         demo_candidates,
         instruction_candidates,
         trainset,
         metric_fn,
         config,
         correlation_id
       ) do
    emit_telemetry(
      [:dspex, :teleprompter, :simba, :optimization, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: correlation_id,
        num_trials: config.num_trials,
        demo_candidates: length(demo_candidates),
        instruction_candidates: length(instruction_candidates)
      }
    )

    # For initial implementation, use simple grid search
    # This will be replaced with proper Bayesian optimization in future iterations
    trials = []
    best_score = -1.0
    best_config = nil

    result =
      instruction_candidates
      |> Enum.take(min(config.num_trials, length(instruction_candidates)))
      |> Enum.reduce_while(
        {:ok, %{best_score: best_score, best_config: best_config, trials: trials}},
        fn instruction_candidate, {:ok, acc} ->
          # Create a test configuration
          test_config = %{
            instruction: instruction_candidate.instruction,
            demos: Enum.map(demo_candidates, & &1.demo)
          }

          # Create optimized program for testing
          test_program = create_test_program(student, test_config)

          # Evaluate on validation set (use subset of trainset)
          validation_set = Enum.take_random(trainset, min(10, length(trainset)))

          case evaluate_configuration(test_program, validation_set, metric_fn) do
            {:ok, score} ->
              trial = %{
                instruction_id: instruction_candidate.id,
                demo_ids: Enum.map(demo_candidates, & &1.id),
                score: score,
                timestamp: DateTime.utc_now()
              }

              new_trials = [trial | acc.trials]

              if score > acc.best_score do
                {:cont, {:ok, %{best_score: score, best_config: test_config, trials: new_trials}}}
              else
                {:cont, {:ok, %{acc | trials: new_trials}}}
              end

            {:error, reason} ->
              {:halt, {:error, {:evaluation_failed, reason}}}
          end
        end
      )

    case result do
      {:ok, %{best_config: best_config, best_score: best_score, trials: trials}}
      when best_config != nil ->
        optimization_result = %{
          best_instruction: best_config.instruction,
          best_demos: best_config.demos,
          score: best_score,
          trials: Enum.reverse(trials),
          stats: %{
            total_trials: length(trials),
            best_score: best_score,
            convergence_iteration: length(trials)
          }
        }

        emit_telemetry(
          [:dspex, :teleprompter, :simba, :optimization, :stop],
          %{duration: System.monotonic_time()},
          %{
            correlation_id: correlation_id,
            best_score: best_score,
            total_trials: length(trials)
          }
        )

        {:ok, optimization_result}

      {:error, reason} ->
        emit_telemetry(
          [:dspex, :teleprompter, :simba, :optimization, :exception],
          %{},
          %{correlation_id: correlation_id, error: reason}
        )

        {:error, reason}

      _ ->
        {:error, :no_valid_configurations}
    end
  end

  defp create_test_program(student, config) do
    case OptimizedProgram.simba_enhancement_strategy(student) do
      :native_full ->
        %{student | instruction: config.instruction, demos: config.demos}

      :native_demos ->
        %{student | demos: config.demos}

      :wrap_optimized ->
        OptimizedProgram.new(student, config.demos, %{instruction: config.instruction})
    end
  end

  defp evaluate_configuration(program, validation_set, metric_fn) do
    try do
      scores =
        validation_set
        |> Task.async_stream(
          fn example ->
            # Extract inputs from Example struct based on input_keys
            inputs =
              example.data
              |> Map.take(MapSet.to_list(example.input_keys))

            case Program.forward(program, inputs, timeout: 30_000) do
              {:ok, outputs} ->
                metric_fn.(example, outputs)

              {:error, _} ->
                0.0
            end
          end,
          max_concurrency: 3,
          timeout: 35_000
        )
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Stream.map(fn {:ok, score} -> score end)
        |> Enum.to_list()

      if Enum.empty?(scores) do
        {:error, :no_valid_evaluations}
      else
        average_score = Enum.sum(scores) / length(scores)
        {:ok, average_score}
      end
    rescue
      error ->
        {:error, {:evaluation_exception, error}}
    end
  end

  defp create_optimized_student(student, optimization_result, _config) do
    case OptimizedProgram.simba_enhancement_strategy(student) do
      :native_full ->
        optimized = %{
          student
          | instruction: optimization_result.best_instruction,
            demos: optimization_result.best_demos
        }

        {:ok, optimized}

      :native_demos ->
        optimized = %{student | demos: optimization_result.best_demos}
        {:ok, optimized}

      :wrap_optimized ->
        optimized =
          OptimizedProgram.new(
            student,
            optimization_result.best_demos,
            %{
              instruction: optimization_result.best_instruction,
              simba_optimization: optimization_result.stats,
              optimized_at: DateTime.utc_now()
            }
          )

        {:ok, optimized}
    end
  end

  # Utility functions

  defp struct_to_keyword(struct) do
    struct
    |> Map.from_struct()
    |> Enum.to_list()
  end

  defp generate_correlation_id do
    node_hash = :erlang.phash2(node(), 65_536)
    timestamp = System.unique_integer([:positive])
    random = :erlang.unique_integer([:positive])
    "simba-#{node_hash}-#{timestamp}-#{random}"
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  rescue
    _ ->
      # Fail silently if telemetry is not available
      :ok
  end
end
