# DSPEx.Teleprompter.BEACON.BayesianOptimizer - Advanced Bayesian Optimization

defmodule DSPEx.Teleprompter.BEACON.BayesianOptimizer do
  @moduledoc """
  Bayesian optimization engine for BEACON teleprompter.

  This module implements a simplified but effective Bayesian optimization algorithm
  specifically designed for optimizing instruction and demonstration combinations
  in language model programs.

  ## Features

  - Gaussian Process surrogate modeling
  - Expected Improvement acquisition function
  - Adaptive sampling strategies
  - Early stopping based on convergence
  - Multi-objective optimization support

  ## Algorithm

  1. **Initialization**: Sample initial configurations randomly
  2. **Surrogate Model**: Fit Gaussian Process to observed data
  3. **Acquisition**: Use Expected Improvement to select next configuration
  4. **Evaluation**: Test selected configuration on validation set
  5. **Update**: Add result to training data and repeat

  ## Example Usage

      optimizer = DSPEx.Teleprompter.BEACON.BayesianOptimizer.new(
        num_initial_samples: 10,
        acquisition_function: :expected_improvement,
        convergence_patience: 5
      )
      
      {:ok, result} = BayesianOptimizer.optimize(
        optimizer,
        search_space,
        objective_function,
        max_iterations: 50
      )
  """

  alias DSPEx.Teleprompter.BEACON

  defstruct num_initial_samples: 10,
            acquisition_function: :expected_improvement,
            convergence_patience: 5,
            convergence_threshold: 0.01,
            exploration_weight: 2.0,
            kernel_length_scale: 1.0,
            kernel_variance: 1.0,
            noise_variance: 0.1

  @type t :: %__MODULE__{
          num_initial_samples: pos_integer(),
          acquisition_function: :expected_improvement | :upper_confidence_bound | :probability_improvement,
          convergence_patience: pos_integer(),
          convergence_threshold: float(),
          exploration_weight: float(),
          kernel_length_scale: float(),
          kernel_variance: float(),
          noise_variance: float()
        }

  @type configuration :: %{
          instruction_id: String.t(),
          demo_ids: [String.t()],
          features: [float()]
        }

  @type observation :: %{
          configuration: configuration(),
          score: float(),
          timestamp: DateTime.t()
        }

  @type optimization_result :: %{
          best_configuration: configuration(),
          best_score: float(),
          observations: [observation()],
          convergence_iteration: non_neg_integer(),
          stats: map()
        }

  @doc """
  Create a new Bayesian optimizer with specified configuration.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @doc """
  Run Bayesian optimization to find the best instruction/demo combination.

  ## Parameters

  - `optimizer` - BayesianOptimizer configuration
  - `search_space` - Available instructions and demonstrations
  - `objective_function` - Function to evaluate configurations
  - `opts` - Optimization options

  ## Returns

  - `{:ok, optimization_result()}` - Successful optimization
  - `{:error, reason}` - Optimization failed
  """
  @spec optimize(t(), map(), function(), keyword()) :: {:ok, optimization_result()} | {:error, term()}
  def optimize(optimizer, search_space, objective_function, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 50)
    correlation_id = Keyword.get(opts, :correlation_id, generate_correlation_id())

    start_time = System.monotonic_time()

    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: correlation_id,
        max_iterations: max_iterations,
        search_space_size: map_size(search_space)
      }
    )

    result = with {:ok, initial_observations} <- 
                    initialize_observations(optimizer, search_space, objective_function, correlation_id),
                  {:ok, optimization_result} <- 
                    run_optimization_loop(
                      optimizer,
                      search_space,
                      objective_function,
                      initial_observations,
                      max_iterations,
                      correlation_id
                    ) do
                {:ok, optimization_result}
              else
                {:error, reason} -> {:error, reason}
              end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :stop],
      %{duration: duration, success: success},
      %{correlation_id: correlation_id}
    )

    result
  end

  # Private implementation

  defp initialize_observations(optimizer, search_space, objective_function, correlation_id) do
    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :initialization, :start],
      %{system_time: System.system_time()},
      %{correlation_id: correlation_id, num_samples: optimizer.num_initial_samples}
    )

    # Generate initial random samples
    initial_configs = generate_random_configurations(search_space, optimizer.num_initial_samples)

    # Evaluate initial configurations
    observations =
      initial_configs
      |> Task.async_stream(
        fn config ->
          score = objective_function.(config)
          
          %{
            configuration: config,
            score: score,
            timestamp: DateTime.utc_now()
          }
        end,
        max_concurrency: 5,
        timeout: 60_000
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, obs} -> obs end)
      |> Enum.to_list()

    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :initialization, :stop],
      %{duration: System.monotonic_time()},
      %{
        correlation_id: correlation_id,
        observations_collected: length(observations)
      }
    )

    if Enum.empty?(observations) do
      {:error, :no_initial_observations}
    else
      {:ok, observations}
    end
  end

  defp run_optimization_loop(
         optimizer,
         search_space,
         objective_function,
         initial_observations,
         max_iterations,
         correlation_id
       ) do
    state = %{
      observations: initial_observations,
      best_score: Enum.max_by(initial_observations, & &1.score).score,
      convergence_counter: 0,
      iteration: 0
    }

    final_state = 
      Enum.reduce_while(1..max_iterations, state, fn iteration, acc_state ->
        case run_single_iteration(
               optimizer,
               search_space,
               objective_function,
               acc_state,
               iteration,
               correlation_id
             ) do
          {:ok, new_state} ->
            if converged?(optimizer, new_state) do
              {:halt, new_state}
            else
              {:cont, new_state}
            end

          {:error, _reason} ->
            # Continue with current state on iteration failure
            {:cont, acc_state}
        end
      end)

    best_observation = Enum.max_by(final_state.observations, & &1.score)

    optimization_result = %{
      best_configuration: best_observation.configuration,
      best_score: best_observation.score,
      observations: final_state.observations,
      convergence_iteration: final_state.iteration,
      stats: %{
        total_iterations: final_state.iteration,
        convergence_achieved: final_state.convergence_counter >= optimizer.convergence_patience,
        improvement_over_random: calculate_improvement(final_state.observations),
        exploration_efficiency: calculate_exploration_efficiency(final_state.observations)
      }
    }

    {:ok, optimization_result}
  end

  defp run_single_iteration(
         optimizer,
         search_space,
         objective_function,
         state,
         iteration,
         correlation_id
       ) do
    # Fit surrogate model (simplified Gaussian Process)
    gp_model = fit_gaussian_process(state.observations, optimizer)

    # Select next configuration using acquisition function
    next_config = select_next_configuration(
      optimizer,
      search_space,
      gp_model,
      state.observations
    )

    # Evaluate the selected configuration
    score = objective_function.(next_config)

    new_observation = %{
      configuration: next_config,
      score: score,
      timestamp: DateTime.utc_now()
    }

    # Update state
    new_observations = [new_observation | state.observations]
    new_best_score = max(state.best_score, score)
    
    improvement = score - state.best_score
    new_convergence_counter = 
      if improvement > optimizer.convergence_threshold do
        0  # Reset counter on significant improvement
      else
        state.convergence_counter + 1
      end

    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :iteration],
      %{iteration: iteration, score: score, improvement: improvement},
      %{
        correlation_id: correlation_id,
        convergence_counter: new_convergence_counter
      }
    )

    new_state = %{
      observations: new_observations,
      best_score: new_best_score,
      convergence_counter: new_convergence_counter,
      iteration: iteration
    }

    {:ok, new_state}
  end

  defp generate_random_configurations(search_space, num_samples) do
    instruction_candidates = Map.get(search_space, :instruction_candidates, [])
    demo_candidates = Map.get(search_space, :demo_candidates, [])

    1..num_samples
    |> Enum.map(fn _i ->
      # Randomly select instruction
      instruction = Enum.random(instruction_candidates)
      
      # Randomly select subset of demos
      num_demos = min(4, length(demo_candidates))
      selected_demos = 
        demo_candidates
        |> Enum.shuffle()
        |> Enum.take(:rand.uniform(num_demos))

      %{
        instruction_id: instruction.id,
        demo_ids: Enum.map(selected_demos, & &1.id),
        features: encode_configuration_features(instruction, selected_demos)
      }
    end)
  end

  defp encode_configuration_features(instruction, demos) do
    # Create feature vector for Bayesian optimization
    # This is a simplified encoding - in practice, you might use embeddings
    
    instruction_features = [
      String.length(instruction.instruction) / 100.0,  # Normalized instruction length
      count_words(instruction.instruction) / 50.0,     # Normalized word count
      complexity_score(instruction.instruction)        # Instruction complexity
    ]

    demo_features = [
      length(demos) / 10.0,  # Normalized number of demos
      average_demo_quality(demos),
      demo_diversity_score(demos)
    ]

    instruction_features ++ demo_features
  end

  defp fit_gaussian_process(observations, optimizer) do
    # Simplified GP implementation
    # In practice, you might use a more sophisticated library
    
    X = Enum.map(observations, &(&1.configuration.features))
    y = Enum.map(observations, &(&1.score))

    %{
      X: X,
      y: y,
      kernel_params: %{
        length_scale: optimizer.kernel_length_scale,
        variance: optimizer.kernel_variance,
        noise_variance: optimizer.noise_variance
      },
      mean: Enum.sum(y) / length(y),
      std: calculate_std(y)
    }
  end

  defp select_next_configuration(optimizer, search_space, gp_model, observations) do
    instruction_candidates = Map.get(search_space, :instruction_candidates, [])
    demo_candidates = Map.get(search_space, :demo_candidates, [])

    # Generate candidate configurations
    candidate_configs = generate_candidate_configurations(
      instruction_candidates,
      demo_candidates,
      20  # Number of candidates to evaluate
    )

    # Filter out already evaluated configurations
    evaluated_configs = MapSet.new(observations, fn obs ->
      {obs.configuration.instruction_id, obs.configuration.demo_ids}
    end)

    new_candidates = Enum.filter(candidate_configs, fn config ->
      not MapSet.member?(evaluated_configs, {config.instruction_id, config.demo_ids})
    end)

    # Select best candidate using acquisition function
    case new_candidates do
      [] ->
        # Fallback to random if no new candidates
        Enum.random(candidate_configs)

      candidates ->
        Enum.max_by(candidates, fn config ->
          acquisition_value(optimizer, config, gp_model)
        end)
    end
  end

  defp generate_candidate_configurations(instruction_candidates, demo_candidates, num_candidates) do
    1..num_candidates
    |> Enum.map(fn _i ->
      instruction = Enum.random(instruction_candidates)
      
      # Use smarter demo selection (e.g., based on quality scores)
      sorted_demos = Enum.sort_by(demo_candidates, &(&1.quality_score || 0.0), :desc)
      num_demos = :rand.uniform(min(4, length(demo_candidates)))
      
      selected_demos = 
        sorted_demos
        |> Enum.take(num_demos * 2)  # Take from top candidates
        |> Enum.shuffle()
        |> Enum.take(num_demos)

      %{
        instruction_id: instruction.id,
        demo_ids: Enum.map(selected_demos, & &1.id),
        features: encode_configuration_features(instruction, selected_demos)
      }
    end)
  end

  defp acquisition_value(optimizer, config, gp_model) do
    case optimizer.acquisition_function do
      :expected_improvement ->
        expected_improvement(config.features, gp_model, optimizer)
      
      :upper_confidence_bound ->
        upper_confidence_bound(config.features, gp_model, optimizer)
      
      :probability_improvement ->
        probability_improvement(config.features, gp_model, optimizer)
    end
  end

  defp expected_improvement(features, gp_model, optimizer) do
    {mean, variance} = gp_predict(features, gp_model)
    
    best_y = Enum.max(gp_model.y)
    improvement = mean - best_y
    std = :math.sqrt(variance)

    if std > 0 do
      z = improvement / std
      ei = improvement * normal_cdf(z) + std * normal_pdf(z)
      ei
    else
      0.0
    end
  end

  defp upper_confidence_bound(features, gp_model, optimizer) do
    {mean, variance} = gp_predict(features, gp_model)
    std = :math.sqrt(variance)
    
    mean + optimizer.exploration_weight * std
  end

  defp probability_improvement(features, gp_model, _optimizer) do
    {mean, variance} = gp_predict(features, gp_model)
    
    best_y = Enum.max(gp_model.y)
    std = :math.sqrt(variance)

    if std > 0 do
      z = (mean - best_y) / std
      normal_cdf(z)
    else
      0.0
    end
  end

  defp gp_predict(features, gp_model) do
    # Simplified GP prediction
    # Calculate similarity to training points using RBF kernel
    
    similarities = 
      Enum.map(gp_model.X, fn x_train ->
        rbf_kernel(features, x_train, gp_model.kernel_params.length_scale)
      end)

    # Weighted prediction based on similarities
    weights = normalize_weights(similarities)
    
    mean = 
      gp_model.y
      |> Enum.zip(weights)
      |> Enum.reduce(0.0, fn {y_i, w_i}, acc -> acc + y_i * w_i end)

    # Simple variance estimate
    variance = gp_model.kernel_params.variance * (1.0 - Enum.max(similarities))
    
    {mean, variance}
  end

  # Helper functions

  defp converged?(optimizer, state) do
    state.convergence_counter >= optimizer.convergence_patience
  end

  defp calculate_improvement(observations) do
    sorted_scores = Enum.sort(Enum.map(observations, & &1.score))
    
    if length(sorted_scores) >= 2 do
      best_score = List.last(sorted_scores)
      initial_best = Enum.at(sorted_scores, div(length(sorted_scores), 5))  # Top 20% baseline
      
      (best_score - initial_best) / max(abs(initial_best), 0.1)
    else
      0.0
    end
  end

  defp calculate_exploration_efficiency(observations) do
    # Measure how well we explored the space
    scores = Enum.map(observations, & &1.score)
    score_variance = calculate_variance(scores)
    
    # Higher variance suggests better exploration
    min(score_variance * 10.0, 1.0)
  end

  defp count_words(text) do
    text
    |> String.split()
    |> length()
  end

  defp complexity_score(instruction) do
    # Simple complexity heuristic
    word_count = count_words(instruction)
    sentence_count = length(String.split(instruction, ~r/[.!?]/))
    
    case sentence_count do
      0 -> 0.5
      _ -> min(word_count / sentence_count / 10.0, 1.0)
    end
  end

  defp average_demo_quality(demos) do
    quality_scores = Enum.map(demos, &(&1.quality_score || 0.5))
    
    if Enum.empty?(quality_scores) do
      0.5
    else
      Enum.sum(quality_scores) / length(quality_scores)
    end
  end

  defp demo_diversity_score(demos) do
    # Simple diversity measure based on demo content
    if length(demos) <= 1 do
      0.0
    else
      # Calculate pairwise diversity and average
      pairs = for d1 <- demos, d2 <- demos, d1 != d2, do: {d1, d2}
      
      diversities = 
        Enum.map(pairs, fn {d1, d2} ->
          content_similarity(d1.demo.data, d2.demo.data)
        end)

      1.0 - (Enum.sum(diversities) / length(diversities))
    end
  end

  defp content_similarity(data1, data2) do
    # Simple similarity based on shared keys and values
    keys1 = MapSet.new(Map.keys(data1))
    keys2 = MapSet.new(Map.keys(data2))
    
    intersection_size = MapSet.size(MapSet.intersection(keys1, keys2))
    union_size = MapSet.size(MapSet.union(keys1, keys2))
    
    if union_size == 0, do: 1.0, else: intersection_size / union_size
  end

  defp calculate_std(values) do
    if Enum.empty?(values) do
      1.0
    else
      mean = Enum.sum(values) / length(values)
      variance = Enum.sum(Enum.map(values, &:math.pow(&1 - mean, 2))) / length(values)
      :math.sqrt(variance)
    end
  end

  defp calculate_variance(values) do
    if length(values) < 2 do
      0.0
    else
      mean = Enum.sum(values) / length(values)
      Enum.sum(Enum.map(values, &:math.pow(&1 - mean, 2))) / (length(values) - 1)
    end
  end

  defp rbf_kernel(x1, x2, length_scale) do
    distance_sq = 
      Enum.zip(x1, x2)
      |> Enum.reduce(0.0, fn {a, b}, acc -> acc + :math.pow(a - b, 2) end)
    
    :math.exp(-distance_sq / (2 * :math.pow(length_scale, 2)))
  end

  defp normalize_weights(weights) do
    total = Enum.sum(weights)
    
    if total > 0 do
      Enum.map(weights, &(&1 / total))
    else
      List.duplicate(1.0 / length(weights), length(weights))
    end
  end

  defp normal_cdf(z) do
    # Approximation of normal CDF
    0.5 * (1 + erf(z / :math.sqrt(2)))
  end

  defp normal_pdf(z) do
    # Normal probability density function
    (1 / :math.sqrt(2 * :math.pi())) * :math.exp(-0.5 * z * z)
  end

  defp erf(x) do
    # Approximation of error function
    # Using Abramowitz and Stegun approximation
    a1 = 0.254829592
    a2 = -0.284496736
    a3 = 1.421413741
    a4 = -1.453152027
    a5 = 1.061405429
    p = 0.3275911

    sign = if x < 0, do: -1, else: 1
    x = abs(x)

    t = 1.0 / (1.0 + p * x)
    y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * :math.exp(-x * x)

    sign * y
  end

  defp generate_correlation_id do
    "bo-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
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
end
