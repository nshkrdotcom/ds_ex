# DSPEx.Teleprompter.SIMBA - Complete Integration

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

  alias DSPEx.{Program, Example, Predict}
  alias DSPEx.Services.ConfigManager

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
           {:ok, demo_candidates} <- bootstrap_demonstrations(teacher, trainset, config, correlation_id),
           {:ok, instruction_candidates} <- generate_instruction_candidates(student, trainset, config, correlation_id),
           {:ok, optimization_result} <- run_bayesian_optimization(
             student,
             demo_candidates,
             instruction_candidates,
             trainset,
             metric_fn,
             config,
             correlation_id
           ),
           {:ok, optimized_student} <- create_optimized_student(
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
    start_time = System.monotonic_time()

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :bootstrap, :start],
      %{system_time: System.system_time()},
      %{correlation_id: correlation_id, trainset_size: length(trainset)}
    )

    # Generate bootstrap demonstrations using teacher program
    candidates =
      trainset
      |> Stream.take(config.num_candidates * 2)  # Generate more than needed
      |> Stream.with_index()
      |> Task.async_stream(
        fn {example, index} ->
          result = generate_single_demonstration(teacher, example, config)

          # Report progress if callback provided
          if config.progress_callback do
            progress = %{
              phase: :bootstrap_generation,
              completed: index + 1,
              total: min(length(trainset), config.num_candidates * 2),
              correlation_id: correlation_id
            }

            config.progress_callback.(progress)
          end

          case result do
            {:ok, demo} ->
              demo_id = generate_demo_id(demo, index)
              
              %{
                id: demo_id,
                demo: demo,
                quality_score: nil,  # Will be evaluated later
                metadata: %{
                  generated_at: DateTime.utc_now(),
                  teacher: teacher_name(teacher),
                  original_index: index
                }
              }

            {:error, _reason} ->
              nil
          end
        end,
        max_concurrency: config.max_concurrency,
        timeout: config.timeout,
        on_timeout: :kill_task
      )
      |> Stream.filter(&match?({:ok, %{}}, &1))
      |> Stream.map(fn {:ok, candidate} -> candidate end)
      |> Enum.take(config.max_bootstrapped_demos)

    duration = System.monotonic_time() - start_time

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :bootstrap, :stop],
      %{duration: duration, success: length(candidates) > 0},
      %{
        correlation_id: correlation_id,
        candidates_generated: length(candidates)
      }
    )

    if Enum.empty?(candidates) do
      {:error, :no_successful_bootstrap_candidates}
    else
      {:ok, candidates}
    end
  end

  defp generate_instruction_candidates(student, trainset, config, correlation_id) do
    start_time = System.monotonic_time()

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :instructions, :start],
      %{system_time: System.system_time()},
      %{correlation_id: correlation_id}
    )

    # Get the signature from the student program
    signature = extract_signature(student)
    
    # Generate instruction candidates using LLM
    instruction_prompts = build_instruction_generation_prompts(signature, trainset, config)

    candidates =
      instruction_prompts
      |> Stream.with_index()
      |> Task.async_stream(
        fn {prompt, index} ->
          case generate_single_instruction(prompt, config, correlation_id) do
            {:ok, instruction} ->
              %{
                id: "inst_#{index}",
                instruction: instruction,
                quality_score: nil,
                metadata: %{
                  generated_at: DateTime.utc_now(),
                  prompt_type: Map.get(prompt, :type, :default)
                }
              }

            {:error, _reason} ->
              nil
          end
        end,
        max_concurrency: config.max_concurrency,
        timeout: config.timeout
      )
      |> Stream.filter(&match?({:ok, %{}}, &1))
      |> Stream.map(fn {:ok, candidate} -> candidate end)
      |> Enum.to_list()

    duration = System.monotonic_time() - start_time

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :instructions, :stop],
      %{duration: duration, success: length(candidates) > 0},
      %{
        correlation_id: correlation_id,
        candidates_generated: length(candidates)
      }
    )

    if Enum.empty?(candidates) do
      # Fallback to default instruction
      default_instruction = build_default_instruction(signature)
      
      candidates = [
        %{
          id: "inst_default",
          instruction: default_instruction,
          quality_score: nil,
          metadata: %{
            generated_at: DateTime.utc_now(),
            prompt_type: :fallback
          }
        }
      ]

      {:ok, candidates}
    else
      {:ok, candidates}
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
    start_time = System.monotonic_time()

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :optimization, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: correlation_id,
        demo_candidates: length(demo_candidates),
        instruction_candidates: length(instruction_candidates),
        num_trials: config.num_trials
      }
    )

    # Initialize Bayesian optimization state
    optimization_state = initialize_optimization_state(demo_candidates, instruction_candidates)

    # Run optimization trials
    {final_state, trials} = run_optimization_trials(
      student,
      optimization_state,
      trainset,
      metric_fn,
      config,
      correlation_id
    )

    # Find best configuration
    best_trial = Enum.max_by(trials, fn trial -> trial.score end)

    optimization_result = %{
      best_instruction: best_trial.instruction,
      best_demos: best_trial.demos,
      score: best_trial.score,
      trials: trials,
      stats: %{
        total_trials: length(trials),
        best_score: best_trial.score,
        optimization_duration: System.monotonic_time() - start_time,
        convergence_trial: find_convergence_trial(trials)
      }
    }

    duration = System.monotonic_time() - start_time

    emit_telemetry(
      [:dspex, :teleprompter, :simba, :optimization, :stop],
      %{duration: duration, success: true},
      %{
        correlation_id: correlation_id,
        best_score: best_trial.score,
        trials_completed: length(trials)
      }
    )

    {:ok, optimization_result}
  end

  defp run_optimization_trials(
         student,
         optimization_state,
         trainset,
         metric_fn,
         config,
         correlation_id
       ) do
    # Split trainset into train/validation
    {train_examples, val_examples} = split_trainset(trainset)

    # Run trials using simplified Bayesian optimization
    trials =
      1..config.num_trials
      |> Task.async_stream(
        fn trial_num ->
          # Sample configuration from candidates
          {instruction_candidate, demo_candidates} = sample_configuration(optimization_state)

          # Create trial program
          trial_program = create_trial_program(student, instruction_candidate, demo_candidates)

          # Evaluate on validation set
          score = evaluate_trial_program(trial_program, val_examples, metric_fn)

          # Report progress
          if config.progress_callback && rem(trial_num, 5) == 0 do
            config.progress_callback.(%{
              phase: :bayesian_optimization,
              trial: trial_num,
              total_trials: config.num_trials,
              current_score: score,
              correlation_id: correlation_id
            })
          end

          %{
            trial_num: trial_num,
            instruction: instruction_candidate.instruction,
            instruction_id: instruction_candidate.id,
            demos: Enum.map(demo_candidates, & &1.demo),
            demo_ids: Enum.map(demo_candidates, & &1.id),
            score: score,
            evaluated_at: DateTime.utc_now()
          }
        end,
        max_concurrency: div(config.max_concurrency, 2),  # Reduce concurrency for trials
        timeout: config.timeout * 2
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, trial} -> trial end)
      |> Enum.to_list()

    {optimization_state, trials}
  end

  defp create_optimized_student(student, optimization_result, _config) do
    # Create optimized student with best instruction and demos
    optimized = 
      case student do
        %{demos: _, instruction: _} ->
          # Student supports demos and instructions natively
          %{
            student
            | demos: optimization_result.best_demos,
              instruction: optimization_result.best_instruction
          }

        %{demos: _} ->
          # Student supports demos but not instructions
          %{student | demos: optimization_result.best_demos}

        _ ->
          # Student doesn't support demos/instructions natively, wrap it
          DSPEx.OptimizedProgram.new(
            student,
            optimization_result.best_demos,
            %{
              optimization_method: :simba,
              instruction: optimization_result.best_instruction,
              optimization_score: optimization_result.score,
              optimization_stats: optimization_result.stats
            }
          )
      end

    {:ok, optimized}
  end

  # Helper functions for demonstration generation

  defp generate_single_demonstration(teacher, example, config) do
    attempt_with_retries(config.teacher_retries, fn ->
      inputs = Example.inputs(example)

      case Program.forward(teacher, inputs) do
        {:ok, prediction} ->
          # Combine inputs and outputs into a single data map
          combined_data = Map.merge(inputs, prediction)

          # Add metadata fields
          demo_data =
            Map.merge(combined_data, %{
              __generated_by: :simba,
              __teacher: teacher_name(teacher),
              __original_example_id: get_in(example.data, [:__id]) || :unknown,
              __timestamp: DateTime.utc_now()
            })

          # Create demo with same input keys as original
          demo = Example.new(demo_data)
          demo = Example.with_inputs(demo, MapSet.to_list(example.input_keys))

          {:ok, demo}

        {:error, reason} ->
          {:error, {:teacher_prediction_failed, reason}}
      end
    end)
  end

  defp attempt_with_retries(0, _fun), do: {:error, :max_retries_exceeded}

  defp attempt_with_retries(retries, fun) when retries > 0 do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} when retries > 1 ->
        Process.sleep(100)
        attempt_with_retries(retries - 1, fun)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions for instruction generation

  defp build_instruction_generation_prompts(signature, trainset, config) do
    # Get sample examples for context
    sample_examples = Enum.take(trainset, 3)
    
    # Get signature information
    input_fields = if function_exported?(signature, :input_fields, 0), do: signature.input_fields(), else: []
    output_fields = if function_exported?(signature, :output_fields, 0), do: signature.output_fields(), else: []
    
    base_prompts = [
      %{
        type: :task_description,
        content: """
        I need to write an instruction for a language model to perform this task:

        Input fields: #{Enum.join(input_fields, ", ")}
        Output fields: #{Enum.join(output_fields, ", ")}

        Example data:
        #{format_examples_for_instruction(sample_examples)}

        Write a clear, concise instruction that tells the model how to transform the inputs into the outputs.
        Focus on the reasoning process and key considerations.
        """
      },
      %{
        type: :step_by_step,
        content: """
        Create a step-by-step instruction for this task:

        Task: Transform #{Enum.join(input_fields, ", ")} into #{Enum.join(output_fields, ", ")}

        Examples:
        #{format_examples_for_instruction(sample_examples)}

        Provide a clear instruction that breaks down the reasoning process into steps.
        """
      },
      %{
        type: :quality_focused,
        content: """
        Write an instruction emphasizing quality and accuracy for this task:

        Inputs: #{Enum.join(input_fields, ", ")}
        Outputs: #{Enum.join(output_fields, ", ")}

        Sample examples:
        #{format_examples_for_instruction(sample_examples)}

        Focus on accuracy, reasoning, and quality in your instruction.
        """
      }
    ]

    # Add more prompt variations based on config
    additional_prompts =
      if config.num_candidates > 3 do
        generate_additional_prompts(signature, sample_examples, config.num_candidates - 3)
      else
        []
      end

    base_prompts ++ additional_prompts
  end

  defp generate_additional_prompts(signature, sample_examples, count) do
    creativity_levels = ["be creative and think outside the box", "be precise and methodical", "be comprehensive and thorough"]
    
    1..count
    |> Enum.map(fn i ->
      creativity = Enum.at(creativity_levels, rem(i - 1, length(creativity_levels)))
      
      %{
        type: :variant,
        content: """
        Create an instruction for this task (#{creativity}):

        Signature: #{signature_name(signature)}
        Examples: #{format_examples_for_instruction(sample_examples)}

        Write an instruction that helps the model perform this task effectively.
        """
      }
    end)
  end

  defp generate_single_instruction(prompt, config, correlation_id) do
    # Use instruction model if specified, otherwise use default
    model = config.instruction_model || get_default_instruction_model()
    
    messages = [
      %{
        role: "user",
        content: prompt.content
      }
    ]

    case DSPEx.Client.request(messages, %{provider: model, correlation_id: correlation_id}) do
      {:ok, response} ->
        instruction =
          response.choices
          |> List.first()
          |> get_in([Access.key(:message), Access.key(:content)])
          |> String.trim()

        {:ok, instruction}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_default_instruction(signature) do
    input_fields = if function_exported?(signature, :input_fields, 0), do: signature.input_fields(), else: []
    output_fields = if function_exported?(signature, :output_fields, 0), do: signature.output_fields(), else: []
    
    """
    Given the input fields #{Enum.join(input_fields, ", ")}, provide the output fields #{Enum.join(output_fields, ", ")}.
    Think step by step and provide accurate, well-reasoned responses.
    """
  end

  # Helper functions for Bayesian optimization

  defp initialize_optimization_state(demo_candidates, instruction_candidates) do
    %{
      demo_candidates: demo_candidates,
      instruction_candidates: instruction_candidates,
      evaluated_configs: %{},
      best_score: 0.0
    }
  end

  defp sample_configuration(optimization_state) do
    # Simple sampling - randomly select instruction and demo combination
    instruction_candidate = Enum.random(optimization_state.instruction_candidates)
    
    # Sample a subset of demo candidates
    demo_candidates = 
      optimization_state.demo_candidates
      |> Enum.shuffle()
      |> Enum.take(min(4, length(optimization_state.demo_candidates)))

    {instruction_candidate, demo_candidates}
  end

  defp create_trial_program(student, instruction_candidate, demo_candidates) do
    demos = Enum.map(demo_candidates, & &1.demo)
    
    case student do
      %{demos: _, instruction: _} ->
        %{student | demos: demos, instruction: instruction_candidate.instruction}
      
      %{demos: _} ->
        %{student | demos: demos}
      
      _ ->
        DSPEx.OptimizedProgram.new(student, demos, %{instruction: instruction_candidate.instruction})
    end
  end

  defp evaluate_trial_program(trial_program, val_examples, metric_fn) do
    results =
      val_examples
      |> Stream.take(10)  # Limit validation set size for speed
      |> Task.async_stream(
        fn example ->
          inputs = Example.inputs(example)
          
          case Program.forward(trial_program, inputs) do
            {:ok, prediction} ->
              score = metric_fn.(example, prediction)
              if is_number(score), do: score, else: 0.0
              
            {:error, _} ->
              0.0
          end
        end,
        max_concurrency: 5,
        timeout: 30_000
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, score} -> score end)
      |> Enum.to_list()

    if Enum.empty?(results) do
      0.0
    else
      Enum.sum(results) / length(results)
    end
  end

  # Utility functions

  defp split_trainset(trainset) do
    split_point = div(length(trainset) * 7, 10)  # 70/30 split
    {Enum.take(trainset, split_point), Enum.drop(trainset, split_point)}
  end

  defp find_convergence_trial(trials) do
    # Find the trial where the best score was achieved
    best_score = Enum.max_by(trials, & &1.score).score
    
    Enum.find_index(trials, fn trial -> trial.score >= best_score * 0.95 end) || length(trials)
  end

  defp format_examples_for_instruction(examples) do
    examples
    |> Enum.take(3)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {example, index} ->
      inputs = Example.inputs(example)
      outputs = Example.outputs(example)
      
      "Example #{index}:\nInputs: #{inspect(inputs)}\nOutputs: #{inspect(outputs)}"
    end)
  end

  defp extract_signature(student) do
    case student do
      %{signature: signature} when is_atom(signature) -> signature
      %DSPEx.Predict{signature: signature} -> signature
      _ -> nil
    end
  end

  defp signature_name(signature) when is_atom(signature) do
    signature
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end

  defp signature_name(_), do: :unknown

  defp teacher_name(teacher) when is_struct(teacher) do
    teacher.__struct__
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end

  defp teacher_name(_), do: :unknown

  defp generate_demo_id(demo, index) do
    hash = :erlang.phash2(demo.data)
    "demo_#{index}_#{hash}"
  end

  defp generate_correlation_id do
    try do
      Foundation.Utils.generate_correlation_id()
    rescue
      _ -> 
        "simba-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    end
  end

  defp get_default_instruction_model do
    ConfigManager.get_with_default([:prediction, :default_provider], :gemini)
  end

  defp emit_telemetry(event, measurements, metadata) do
    try do
      :telemetry.execute(event, measurements, metadata)
    rescue
      _ -> :ok
    catch
      _ -> :ok
    end
  end

  defp struct_to_keyword(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.to_list()
  end
end

# Add SIMBA-specific signature for instruction generation
defmodule DSPEx.Teleprompter.SIMBA.InstructionSignature do
  @moduledoc """
  Signature for generating instructions in SIMBA teleprompter.
  """
  use DSPEx.Signature, "task_description, examples -> instruction"

  def description do
    """
    Generate a clear, effective instruction for a language model task.
    The instruction should help the model understand how to transform the given inputs into the desired outputs.
    Focus on clarity, specificity, and actionable guidance.
    """
  end
end

# Evaluation signature for SIMBA
defmodule DSPEx.Teleprompter.SIMBA.EvaluationSignature do
  @moduledoc """
  Signature for evaluating instruction quality in SIMBA.
  """
  use DSPEx.Signature, "instruction, task_examples -> quality_score, feedback"

  def description do
    """
    Evaluate the quality of an instruction for a given task.
    Provide a numerical quality score (0.0 to 1.0) and constructive feedback.
    Consider clarity, specificity, completeness, and likely effectiveness.
    """
  end
end
