# DSPEx Adaptive Optimization System - Examples & Testing

## Practical Usage Examples

### Example 1: Question Answering Optimization

```elixir
defmodule QAOptimizationExample do
  @moduledoc """
  Example of optimizing a question-answering system across different
  adapters, modules, and parameters.
  """
  
  alias DSPEx.Variables.{Variable, VariableSpace}
  alias DSPEx.Optimization.{UniversalOptimizer, MultiObjectiveEvaluator}
  
  def run_qa_optimization() do
    # Define the problem-specific variable space
    variable_space = create_qa_variable_space()
    
    # Create multi-objective evaluator
    evaluator = create_qa_evaluator()
    
    # Create optimizer
    optimizer = UniversalOptimizer.new(variable_space,
      budget: 30,
      strategy: :multi_objective,
      evaluation_metric: evaluator
    )
    
    # Define base program
    program = %DSPEx.Predict{
      signature: create_qa_signature(),
      adapter: DSPEx.Adapters.JSONAdapter,
      client: create_client()
    }
    
    # Create training dataset
    trainset = create_qa_trainset()
    
    # Run optimization
    {:ok, optimized_program} = UniversalOptimizer.optimize(
      optimizer,
      program,
      trainset,
      &evaluate_qa_program/2
    )
    
    IO.puts("Optimization completed!")
    IO.inspect(optimized_program, label: "Optimized Program")
    
    optimized_program
  end
  
  defp create_qa_variable_space() do
    VariableSpace.new()
    |> VariableSpace.add_variable(Variable.discrete(:adapter, [
      DSPEx.Adapters.JSONAdapter,
      DSPEx.Adapters.ChatAdapter,
      DSPEx.Adapters.MarkdownAdapter
    ], description: "Response format adapter"))
    
    |> VariableSpace.add_variable(Variable.discrete(:module_type, [
      DSPEx.Predict,
      DSPEx.ChainOfThought,
      DSPEx.ReAct
    ], description: "Reasoning module"))
    
    |> VariableSpace.add_variable(Variable.discrete(:provider, [
      :openai, :anthropic, :groq
    ], description: "LLM provider", cost_weight: 1.5))
    
    |> VariableSpace.add_variable(Variable.continuous(:temperature, {0.0, 1.5}, 
      default: 0.7, description: "Model temperature"))
    
    |> VariableSpace.add_variable(Variable.continuous(:top_p, {0.1, 1.0}, 
      default: 0.9, description: "Nucleus sampling"))
    
    |> VariableSpace.add_variable(Variable.discrete(:model, [
      "gpt-4", "gpt-3.5-turbo", "claude-3-sonnet", "llama-2-70b"
    ], description: "Model selection"))
  end
  
  defp create_qa_signature() do
    %DSPEx.Signature{
      inputs: %{
        context: %{type: :string, description: "Background context"},
        question: %{type: :string, description: "Question to answer"}
      },
      outputs: %{
        answer: %{type: :string, description: "Answer to the question"},
        confidence: %{type: :float, description: "Confidence score 0-1"}
      },
      instructions: """
      Given the context and question, provide a clear, accurate answer.
      Include a confidence score indicating how certain you are about the answer.
      """
    }
  end
  
  defp create_qa_evaluator() do
    objectives = [
      %{
        name: :accuracy,
        function: &evaluate_qa_accuracy/2,
        weight: 0.5,
        direction: :maximize
      },
      %{
        name: :cost,
        function: &evaluate_qa_cost/2,
        weight: 0.2,
        direction: :minimize
      },
      %{
        name: :latency,
        function: &evaluate_qa_latency/2,
        weight: 0.2,
        direction: :minimize
      },
      %{
        name: :confidence_calibration,
        function: &evaluate_confidence_calibration/2,
        weight: 0.1,
        direction: :maximize
      }
    ]
    
    MultiObjectiveEvaluator.new(objectives)
  end
  
  defp create_qa_trainset() do
    [
      %{
        inputs: %{
          context: "The Eiffel Tower is located in Paris, France. It was built in 1889.",
          question: "When was the Eiffel Tower built?"
        },
        outputs: %{
          answer: "1889",
          confidence: 0.95
        }
      },
      %{
        inputs: %{
          context: "Python is a programming language created by Guido van Rossum in 1991.",
          question: "Who created Python?"
        },
        outputs: %{
          answer: "Guido van Rossum",
          confidence: 0.98
        }
      },
      %{
        inputs: %{
          context: "Machine learning is a subset of artificial intelligence.",
          question: "What is the relationship between ML and AI?"
        },
        outputs: %{
          answer: "Machine learning is a subset of artificial intelligence",
          confidence: 0.90
        }
      }
    ]
  end
  
  defp evaluate_qa_program(program, trainset) do
    # Run the program on all examples and calculate metrics
    results = 
      trainset
      |> Task.async_stream(fn example ->
        case DSPEx.Program.forward(program, example.inputs) do
          {:ok, outputs} -> 
            %{
              expected: example.outputs,
              actual: outputs,
              success: true
            }
          {:error, reason} -> 
            %{
              expected: example.outputs,
              actual: nil,
              success: false,
              error: reason
            }
        end
      end, max_concurrency: 4)
      |> Enum.map(fn {:ok, result} -> result end)
    
    # Calculate overall score
    successful_results = Enum.filter(results, & &1.success)
    success_rate = length(successful_results) / length(results)
    
    if success_rate > 0 do
      accuracy_scores = Enum.map(successful_results, &calculate_answer_accuracy/1)
      avg_accuracy = Enum.sum(accuracy_scores) / length(accuracy_scores)
      
      # Combine success rate and accuracy
      success_rate * 0.3 + avg_accuracy * 0.7
    else
      0.0
    end
  end
  
  defp calculate_answer_accuracy(%{expected: expected, actual: actual}) do
    expected_answer = Map.get(expected, :answer, "")
    actual_answer = Map.get(actual, :answer, "")
    
    # Simple string similarity (can be enhanced with more sophisticated metrics)
    String.jaro_distance(expected_answer, actual_answer)
  end
  
  defp evaluate_qa_accuracy(_configuration, {program, trainset}) do
    # Detailed accuracy evaluation
    results = evaluate_program_on_trainset(program, trainset)
    
    accuracy_scores = 
      results
      |> Enum.filter(& &1.success)
      |> Enum.map(&calculate_detailed_accuracy/1)
    
    case accuracy_scores do
      [] -> 0.0
      scores -> Enum.sum(scores) / length(scores)
    end
  end
  
  defp evaluate_qa_cost(configuration, {_program, trainset}) do
    # Estimate cost based on provider and model
    provider = Map.get(configuration, :provider, :openai)
    model = Map.get(configuration, :model, "gpt-4")
    
    base_cost = get_provider_base_cost(provider)
    model_multiplier = get_model_cost_multiplier(model)
    
    # Estimate tokens per example
    avg_tokens_per_example = 150  # Rough estimate for QA
    total_tokens = avg_tokens_per_example * length(trainset)
    
    estimated_cost = base_cost * model_multiplier * total_tokens / 1000
    
    # Normalize to 0-1 scale (assuming max cost of $5)
    min(estimated_cost / 5.0, 1.0)
  end
  
  defp evaluate_qa_latency(_configuration, {program, trainset}) do
    # Measure actual latency on a sample
    sample_size = min(3, length(trainset))
    sample_examples = Enum.take_random(trainset, sample_size)
    
    latencies = 
      sample_examples
      |> Enum.map(fn example ->
        start_time = System.monotonic_time(:millisecond)
        DSPEx.Program.forward(program, example.inputs)
        end_time = System.monotonic_time(:millisecond)
        end_time - start_time
      end)
    
    avg_latency = Enum.sum(latencies) / length(latencies)
    
    # Normalize to 0-1 scale (assuming max acceptable latency of 5 seconds)
    min(avg_latency / 5000.0, 1.0)
  end
  
  defp evaluate_confidence_calibration(_configuration, {program, trainset}) do
    # Evaluate how well confidence scores match actual accuracy
    results = evaluate_program_on_trainset(program, trainset)
    
    successful_results = Enum.filter(results, & &1.success)
    
    if length(successful_results) < 2 do
      0.5  # Default score for insufficient data
    else
      calibration_scores = 
        successful_results
        |> Enum.map(fn result ->
          predicted_confidence = get_in(result.actual, [:confidence]) || 0.5
          actual_accuracy = calculate_answer_accuracy(result)
          
          # Calculate calibration error (lower is better)
          abs(predicted_confidence - actual_accuracy)
        end)
      
      avg_calibration_error = Enum.sum(calibration_scores) / length(calibration_scores)
      
      # Convert to 0-1 scale where 1 is perfectly calibrated
      max(0.0, 1.0 - avg_calibration_error)
    end
  end
  
  # Helper functions
  
  defp create_client() do
    %DSPEx.Client{
      provider: :openai,
      model: "gpt-4",
      api_key: System.get_env("OPENAI_API_KEY") || "test-key"
    }
  end
  
  defp evaluate_program_on_trainset(program, trainset) do
    trainset
    |> Enum.map(fn example ->
      case DSPEx.Program.forward(program, example.inputs) do
        {:ok, outputs} -> 
          %{expected: example.outputs, actual: outputs, success: true}
        {:error, reason} -> 
          %{expected: example.outputs, actual: nil, success: false, error: reason}
      end
    end)
  end
  
  defp calculate_detailed_accuracy(%{expected: expected, actual: actual}) do
    answer_similarity = String.jaro_distance(
      Map.get(expected, :answer, ""),
      Map.get(actual, :answer, "")
    )
    
    # Also consider confidence score accuracy if available
    confidence_accuracy = case {Map.get(expected, :confidence), Map.get(actual, :confidence)} do
      {nil, _} -> 1.0  # No expected confidence
      {_, nil} -> 0.5  # Missing confidence in output
      {exp_conf, act_conf} -> 1.0 - abs(exp_conf - act_conf)
    end
    
    # Weighted combination
    0.8 * answer_similarity + 0.2 * confidence_accuracy
  end
  
  defp get_provider_base_cost(:openai), do: 0.03
  defp get_provider_base_cost(:anthropic), do: 0.025
  defp get_provider_base_cost(:groq), do: 0.005
  defp get_provider_base_cost(_), do: 0.02
  
  defp get_model_cost_multiplier("gpt-4"), do: 3.0
  defp get_model_cost_multiplier("gpt-3.5-turbo"), do: 1.0
  defp get_model_cost_multiplier("claude-3-sonnet"), do: 2.5
  defp get_model_cost_multiplier("llama-2-70b"), do: 0.5
  defp get_model_cost_multiplier(_), do: 1.5
end
```

### Example 2: Code Generation Optimization

```elixir
defmodule CodeGenOptimizationExample do
  @moduledoc """
  Example of optimizing a code generation system with different
  reasoning approaches and parameter settings.
  """
  
  def run_codegen_optimization() do
    variable_space = create_codegen_variable_space()
    
    optimizer = UniversalOptimizer.new(variable_space,
      budget: 25,
      strategy: :genetic_algorithm  # Good for discrete-heavy spaces
    )
    
    program = %DSPEx.ProgramOfThought{
      signature: create_codegen_signature(),
      adapter: DSPEx.Adapters.MarkdownAdapter,
      client: create_client(),
      code_executor: DSPEx.CodeExecutor.Python
    }
    
    trainset = create_codegen_trainset()
    
    {:ok, optimized_program} = UniversalOptimizer.optimize(
      optimizer,
      program,
      trainset,
      &evaluate_codegen_program/2
    )
    
    optimized_program
  end
  
  defp create_codegen_variable_space() do
    VariableSpace.new()
    |> VariableSpace.add_variable(Variable.discrete(:module_type, [
      DSPEx.ProgramOfThought,
      DSPEx.ChainOfThought,
      DSPEx.ReAct
    ], description: "Reasoning approach"))
    
    |> VariableSpace.add_variable(Variable.discrete(:adapter, [
      DSPEx.Adapters.MarkdownAdapter,
      DSPEx.Adapters.JSONAdapter
    ], description: "Output format"))
    
    |> VariableSpace.add_variable(Variable.continuous(:temperature, {0.1, 1.2}, 
      default: 0.3, description: "Creativity level"))
    
    |> VariableSpace.add_variable(Variable.discrete(:code_style, [
      :pythonic, :verbose, :minimal, :functional
    ], description: "Code generation style"))
    
    |> VariableSpace.add_variable(Variable.continuous(:max_tokens, {500, 2000}, 
      default: 1000, description: "Maximum response tokens"))
  end
  
  defp create_codegen_signature() do
    %DSPEx.Signature{
      inputs: %{
        problem: %{type: :string, description: "Programming problem description"},
        language: %{type: :string, description: "Target programming language"},
        constraints: %{type: :string, description: "Additional constraints"}
      },
      outputs: %{
        code: %{type: :string, description: "Generated code solution"},
        explanation: %{type: :string, description: "Code explanation"},
        test_cases: %{type: :list, description: "Example test cases"}
      },
      instructions: """
      Generate clean, efficient code that solves the given problem.
      Include clear explanations and relevant test cases.
      Follow best practices for the target language.
      """
    }
  end
  
  defp create_codegen_trainset() do
    [
      %{
        inputs: %{
          problem: "Write a function to find the factorial of a number",
          language: "Python",
          constraints: "Use recursion"
        },
        outputs: %{
          code: """
          def factorial(n):
              if n <= 1:
                  return 1
              return n * factorial(n - 1)
          """,
          explanation: "Recursive implementation of factorial",
          test_cases: ["factorial(5) == 120", "factorial(0) == 1"]
        }
      },
      %{
        inputs: %{
          problem: "Implement binary search",
          language: "Python", 
          constraints: "Handle edge cases"
        },
        outputs: %{
          code: """
          def binary_search(arr, target):
              left, right = 0, len(arr) - 1
              while left <= right:
                  mid = (left + right) // 2
                  if arr[mid] == target:
                      return mid
                  elif arr[mid] < target:
                      left = mid + 1
                  else:
                      right = mid - 1
              return -1
          """,
          explanation: "Iterative binary search with proper bounds",
          test_cases: ["binary_search([1,2,3,4,5], 3) == 2"]
        }
      }
    ]
  end
  
  defp evaluate_codegen_program(program, trainset) do
    results = 
      trainset
      |> Enum.map(fn example ->
        case DSPEx.Program.forward(program, example.inputs) do
          {:ok, outputs} -> 
            %{
              expected: example.outputs,
              actual: outputs,
              success: true,
              code_quality: evaluate_code_quality(outputs),
              correctness: evaluate_code_correctness(outputs, example.outputs)
            }
          {:error, _} -> 
            %{success: false, code_quality: 0.0, correctness: 0.0}
        end
      end)
    
    successful_results = Enum.filter(results, & &1.success)
    
    if length(successful_results) > 0 do
      avg_quality = successful_results |> Enum.map(& &1.code_quality) |> Enum.sum() |> Kernel./(length(successful_results))
      avg_correctness = successful_results |> Enum.map(& &1.correctness) |> Enum.sum() |> Kernel./(length(successful_results))
      
      success_rate = length(successful_results) / length(results)
      
      # Weighted combination
      success_rate * 0.3 + avg_correctness * 0.4 + avg_quality * 0.3
    else
      0.0
    end
  end
  
  defp evaluate_code_quality(outputs) do
    code = Map.get(outputs, :code, "")
    
    # Simple heuristics for code quality
    quality_score = 0.0
    
    # Check for proper indentation
    quality_score = if String.contains?(code, "    ") or String.contains?(code, "\t") do
      quality_score + 0.2
    else
      quality_score
    end
    
    # Check for comments or docstrings
    quality_score = if String.contains?(code, "#") or String.contains?(code, '"""') do
      quality_score + 0.2
    else
      quality_score
    end
    
    # Check for reasonable variable names (not single letters except for loops)
    quality_score = if Regex.match?(~r/def \w{2,}/, code) do
      quality_score + 0.2
    else
      quality_score
    end
    
    # Check for error handling
    quality_score = if String.contains?(code, "try") or String.contains?(code, "if") do
      quality_score + 0.2
    else
      quality_score
    end
    
    # Base quality for syntactically valid code
    quality_score + 0.2
  end
  
  defp evaluate_code_correctness(actual_outputs, expected_outputs) do
    actual_code = Map.get(actual_outputs, :code, "")
    expected_code = Map.get(expected_outputs, :code, "")
    
    # Simple similarity measure (can be enhanced with AST comparison)
    code_similarity = String.jaro_distance(actual_code, expected_code)
    
    # Check if explanation is provided
    explanation_quality = case Map.get(actual_outputs, :explanation) do
      nil -> 0.0
      "" -> 0.0
      explanation when is_binary(explanation) -> 
        if String.length(explanation) > 10, do: 0.8, else: 0.4
      _ -> 0.0
    end
    
    # Weighted combination
    0.7 * code_similarity + 0.3 * explanation_quality
  end
end
```

## Testing Framework

### Unit Tests

```elixir
defmodule DSPEx.Optimization.AdaptiveOptimizationTest do
  use ExUnit.Case, async: true
  
  alias DSPEx.Variables.{Variable, VariableSpace}
  alias DSPEx.Optimization.{UniversalOptimizer, MultiObjectiveEvaluator}
  
  describe "Variable system" do
    test "creates discrete variables correctly" do
      variable = Variable.discrete(:adapter, [:json, :chat, :markdown])
      
      assert variable.id == :adapter
      assert variable.type == :discrete
      assert variable.choices == [:json, :chat, :markdown]
      assert variable.default == :json
    end
    
    test "creates continuous variables correctly" do
      variable = Variable.continuous(:temperature, {0.0, 2.0}, default: 0.7)
      
      assert variable.id == :temperature
      assert variable.type == :continuous
      assert variable.range == {0.0, 2.0}
      assert variable.default == 0.7
    end
    
    test "validates discrete variable values" do
      variable = Variable.discrete(:adapter, [:json, :chat])
      
      assert {:ok, :json} = Variable.validate(variable, :json)
      assert {:error, _} = Variable.validate(variable, :invalid)
    end
    
    test "validates continuous variable values" do
      variable = Variable.continuous(:temperature, {0.0, 2.0})
      
      assert {:ok, 1.0} = Variable.validate(variable, 1.0)
      assert {:error, _} = Variable.validate(variable, 3.0)
      assert {:error, _} = Variable.validate(variable, "invalid")
    end
  end
  
  describe "VariableSpace" do
    test "creates standard DSPEx variable space" do
      space = VariableSpace.dspex_standard_space()
      
      assert Map.has_key?(space.variables, :adapter)
      assert Map.has_key?(space.variables, :module_type)
      assert Map.has_key?(space.variables, :temperature)
      assert Map.has_key?(space.variables, :provider)
    end
    
    test "samples configurations from variable space" do
      space = VariableSpace.new()
        |> VariableSpace.add_variable(Variable.discrete(:adapter, [:json, :chat]))
        |> VariableSpace.add_variable(Variable.continuous(:temperature, {0.0, 1.0}))
      
      config = VariableSpace.sample(space)
      
      assert Map.has_key?(config, :adapter)
      assert Map.has_key?(config, :temperature)
      assert config.adapter in [:json, :chat]
      assert config.temperature >= 0.0 and config.temperature <= 1.0
    end
    
    test "validates configurations against variable space" do
      space = VariableSpace.new()
        |> VariableSpace.add_variable(Variable.discrete(:adapter, [:json, :chat]))
      
      valid_config = %{adapter: :json}
      invalid_config = %{adapter: :invalid}
      
      assert {:ok, _} = VariableSpace.validate_configuration(space, valid_config)
      assert {:error, _} = VariableSpace.validate_configuration(space, invalid_config)
    end
  end
  
  describe "UniversalOptimizer" do
    test "selects appropriate strategy for variable space" do
      # Small discrete space should use grid search
      discrete_space = VariableSpace.new()
        |> VariableSpace.add_variable(Variable.discrete(:adapter, [:json, :chat]))
        |> VariableSpace.add_variable(Variable.discrete(:provider, [:openai, :anthropic]))
      
      optimizer = UniversalOptimizer.new(discrete_space, budget: 10)
      assert optimizer.strategy == :grid_search
      
      # Continuous space should use Bayesian optimization
      continuous_space = VariableSpace.new()
        |> VariableSpace.add_variable(Variable.continuous(:temperature, {0.0, 2.0}))
        |> VariableSpace.add_variable(Variable.continuous(:top_p, {0.1, 1.0}))
      
      optimizer = UniversalOptimizer.new(continuous_space, budget: 100)
      assert optimizer.strategy == :bayesian_optimization
    end
    
    test "runs optimization with mock evaluation function" do
      space = VariableSpace.new()
        |> VariableSpace.add_variable(Variable.continuous(:temperature, {0.0, 2.0}))
      
      optimizer = UniversalOptimizer.new(space, budget: 5)
      
      program = %{signature: :test}
      trainset = [%{inputs: %{}, outputs: %{}}]
      
      # Mock evaluation function that prefers lower temperature
      evaluation_fn = fn configured_program, _trainset ->
        temp = get_in(configured_program, [:client_config, :temperature]) || 1.0
        1.0 - (temp / 2.0)  # Higher score for lower temperature
      end
      
      {:ok, optimized_program} = UniversalOptimizer.optimize(
        optimizer,
        program,
        trainset,
        evaluation_fn
      )
      
      assert optimized_program != nil
      # Should have lower temperature than default
      optimized_temp = get_in(optimized_program, [:client_config, :temperature])
      assert optimized_temp != nil
      assert optimized_temp < 1.0
    end
  end
  
  describe "MultiObjectiveEvaluator" do
    test "creates standard evaluator with correct objectives" do
      evaluator = MultiObjectiveEvaluator.dspex_standard_evaluator()
      
      objective_names = Enum.map(evaluator.objectives, & &1.name)
      assert :accuracy in objective_names
      assert :cost in objective_names
      assert :latency in objective_names
      assert :reliability in objective_names
    end
    
    test "evaluates configuration across multiple objectives" do
      objectives = [
        %{name: :metric1, function: fn _, _ -> 0.8 end, weight: 0.6, direction: :maximize},
        %{name: :metric2, function: fn _, _ -> 0.3 end, weight: 0.4, direction: :minimize}
      ]
      
      evaluator = MultiObjectiveEvaluator.new(objectives)
      
      configuration = %{temperature: 0.5}
      program = %{signature: :test}
      trainset = []
      
      {result, _updated_evaluator} = MultiObjectiveEvaluator.evaluate(
        evaluator,
        configuration,
        program,
        trainset
      )
      
      assert result.configuration == configuration
      assert length(result.objective_scores) == 2
      assert result.weighted_score > 0
    end
  end
end
```

### Integration Tests

```elixir
defmodule DSPEx.Optimization.IntegrationTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.Variables.VariableSpace
  alias DSPEx.Optimization.{UniversalOptimizer, MultiObjectiveEvaluator}
  
  @moduletag :integration
  @moduletag timeout: 60_000
  
  test "end-to-end optimization finds better configurations" do
    # Create a realistic optimization scenario
    variable_space = create_test_variable_space()
    
    evaluator = create_test_evaluator()
    
    optimizer = UniversalOptimizer.new(variable_space,
      budget: 15,
      strategy: :multi_objective,
      evaluation_metric: evaluator
    )
    
    # Base program with suboptimal settings
    program = %DSPEx.Predict{
      signature: create_test_signature(),
      adapter: DSPEx.Adapters.JSONAdapter,
      client: create_test_client(),
      client_config: %{temperature: 1.5, top_p: 0.5}  # Suboptimal settings
    }
    
    trainset = create_test_trainset()
    
    # Evaluate base program
    base_score = evaluate_test_program(program, trainset)
    
    # Run optimization
    {:ok, optimized_program} = UniversalOptimizer.optimize(
      optimizer,
      program,
      trainset,
      &evaluate_test_program/2
    )
    
    # Evaluate optimized program
    optimized_score = evaluate_test_program(optimized_program, trainset)
    
    # Optimization should improve the score
    assert optimized_score > base_score
    
    # Optimized program should have different configuration
    assert optimized_program != program
    
    IO.puts("Base score: #{base_score}")
    IO.puts("Optimized score: #{optimized_score}")
    IO.puts("Improvement: #{(optimized_score - base_score) * 100}%")
  end
  
  test "optimization respects budget constraints" do
    variable_space = create_test_variable_space()
    
    # Set a very small budget
    optimizer = UniversalOptimizer.new(variable_space, budget: 3)
    
    program = %DSPEx.Predict{
      signature: create_test_signature(),
      adapter: DSPEx.Adapters.JSONAdapter,
      client: create_test_client()
    }
    
    trainset = create_test_trainset()
    
    start_time = System.monotonic_time(:millisecond)
    
    {:ok, _optimized_program} = UniversalOptimizer.optimize(
      optimizer,
      program,
      trainset,
      &evaluate_test_program/2
    )
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    # With budget of 3, optimization should complete quickly
    assert duration < 10_000  # Less than 10 seconds
  end
  
  test "optimization handles evaluation failures gracefully" do
    variable_space = create_test_variable_space()
    
    optimizer = UniversalOptimizer.new(variable_space, budget: 5)
    
    program = %DSPEx.Predict{
      signature: create_test_signature(),
      adapter: DSPEx.Adapters.JSONAdapter,
      client: create_test_client()
    }
    
    trainset = create_test_trainset()
    
    # Evaluation function that sometimes fails
    failing_evaluation_fn = fn _program, _trainset ->
      if :rand.uniform() < 0.3 do
        # Simulate failure
        raise "Evaluation failed"
      else
        :rand.uniform()
      end
    end
    
    # Should handle failures and still return a result
    assert {:ok, _optimized_program} = UniversalOptimizer.optimize(
      optimizer,
      program,
      trainset,
      failing_evaluation_fn
    )
  end
  
  # Helper functions
  
  defp create_test_variable_space() do
    VariableSpace.new()
    |> VariableSpace.add_variable(Variable.discrete(:adapter, [
      DSPEx.Adapters.JSONAdapter,
      DSPEx.Adapters.ChatAdapter
    ]))
    |> VariableSpace.add_variable(Variable.continuous(:temperature, {0.1, 1.0}))
    |> VariableSpace.add_variable(Variable.continuous(:top_p, {0.5, 1.0}))
    |> VariableSpace.add_variable(Variable.discrete(:provider, [:openai, :groq]))
  end
  
  defp create_test_evaluator() do
    objectives = [
      %{name: :quality, function: &evaluate_quality/2, weight: 0.7, direction: :maximize},
      %{name: :cost, function: &evaluate_cost/2, weight: 0.3, direction: :minimize}
    ]
    
    MultiObjectiveEvaluator.new(objectives)
  end
  
  defp create_test_signature() do
    %DSPEx.Signature{
      inputs: %{text: %{type: :string}},
      outputs: %{result: %{type: :string}},
      instructions: "Process the input text"
    }
  end
  
  defp create_test_client() do
    %DSPEx.Client{
      provider: :openai,
      model: "gpt-3.5-turbo",
      api_key: "test-key"
    }
  end
  
  defp create_test_trainset() do
    [
      %{inputs: %{text: "Hello world"}, outputs: %{result: "Processed: Hello world"}},
      %{inputs: %{text: "Test input"}, outputs: %{result: "Processed: Test input"}}
    ]
  end
  
  defp evaluate_test_program(program, trainset) do
    # Simulate program evaluation with preference for certain configurations
    temp = get_in(program, [:client_config, :temperature]) || 0.7
    top_p = get_in(program, [:client_config, :top_p]) || 0.9
    
    # Prefer moderate temperature and high top_p
    temp_score = 1.0 - abs(temp - 0.5) * 2  # Prefer temp around 0.5
    top_p_score = top_p  # Prefer higher top_p
    
    # Simulate some randomness
    base_score = (temp_score + top_p_score) / 2
    noise = (:rand.uniform() - 0.5) * 0.1  # Small random component
    
    max(0.0, min(1.0, base_score + noise))
  end
  
  defp evaluate_quality(_configuration, {program, trainset}) do
    # Mock quality evaluation
    evaluate_test_program(program, trainset)
  end
  
  defp evaluate_cost(configuration, {_program, _trainset}) do
    # Mock cost evaluation - prefer groq over openai
    case Map.get(configuration, :provider, :openai) do
      :groq -> 0.2
      :openai -> 0.8
      _ -> 0.5
    end
  end
end
```

## Configuration Examples

### Development Configuration

```elixir
# config/dev.exs
config :dspex, :adaptive_optimization,
  default_budget: 20,
  parallel_evaluations: 2,
  evaluation_timeout: 30_000,
  debug_mode: true
```

### Production Configuration

```elixir
# config/prod.exs
config :dspex, :adaptive_optimization,
  default_budget: 100,
  parallel_evaluations: System.schedulers_online() * 2,
  evaluation_timeout: 120_000,
  cache_evaluations: true,
  optimization_strategies: [:bayesian_optimization, :genetic_algorithm]
```

## Benefits Demonstrated

1. **Automated Discovery**: Examples show how the system automatically finds optimal configurations
2. **Multi-Objective Optimization**: Balances accuracy, cost, latency, and reliability
3. **Robust Testing**: Comprehensive test suite ensures reliability
4. **Real-World Applications**: Practical examples for QA and code generation tasks
5. **Fault Tolerance**: Graceful handling of evaluation failures

This comprehensive framework addresses the DSPy community's needs while leveraging Elixir's strengths for building reliable, concurrent optimization systems. 