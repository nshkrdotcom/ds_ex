defmodule DSPEx.Teleprompter do
  @moduledoc """
  Behavior for DSPEx teleprompters (optimizers).
  
  Teleprompters are responsible for improving programs by learning from examples
  and optimizing demonstration selection. They take a student program, a teacher
  program, and training examples, then return an optimized version of the student.
  
  This module focuses on single-node optimization with excellent local performance.
  Distributed features can be added later as enhancements.
  
  ## Example
  
      defmodule MyTeleprompter do
        @behaviour DSPEx.Teleprompter
        
        @impl true
        def compile(student, teacher, trainset, metric_fn, opts) do
          # Optimization logic here
          {:ok, optimized_student}
        end
      end
  """
  
  alias DSPEx.Example
  
  @type program :: struct()
  @type trainset :: [Example.t()]
  @type metric_fn :: (Example.t(), map() -> number())
  @type opts :: keyword()
  @type compilation_result :: {:ok, program()} | {:error, term()}
  
  @doc """
  Compile (optimize) a student program using a teacher program and training data.
  
  ## Parameters
  
  - `student`: The program to be optimized
  - `teacher`: A stronger program used to generate demonstrations
  - `trainset`: Training examples for optimization
  - `metric_fn`: Function to evaluate prediction quality (example, prediction) -> score
  - `opts`: Options for compilation (varies by teleprompter)
  
  ## Returns
  
  - `{:ok, optimized_program}` on successful optimization
  - `{:error, reason}` if optimization fails
  """
  @callback compile(
    student :: program(),
    teacher :: program(), 
    trainset :: trainset(),
    metric_fn :: metric_fn(),
    opts :: opts()
  ) :: compilation_result()
  
  @doc """
  Helper function to create a basic metric function for exact match comparison.
  """
  @spec exact_match(atom()) :: metric_fn()
  def exact_match(field) when is_atom(field) do
    fn example, prediction ->
      outputs = Example.outputs(example)
      expected = Map.get(outputs, field)
      actual = Map.get(prediction, field)
      
      if expected == actual do
        1.0
      else
        0.0
      end
    end
  end
  
  @doc """
  Helper function to create a metric function that checks if prediction contains expected value.
  """
  @spec contains_match(atom()) :: metric_fn()
  def contains_match(field) when is_atom(field) do
    fn example, prediction ->
      outputs = Example.outputs(example)
      expected = Map.get(outputs, field)
      actual = Map.get(prediction, field)
      
      if is_binary(expected) and is_binary(actual) do
        if String.contains?(String.downcase(actual), String.downcase(expected)) do
          1.0
        else
          0.0
        end
      else
        if expected == actual do
          1.0
        else
          0.0
        end
      end
    end
  end
  
  @doc """
  Helper function to validate that a module implements the teleprompter behavior.
  """
  @spec implements_behavior?(module()) :: boolean()
  def implements_behavior?(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        behaviours = module.module_info(:attributes)
                    |> Keyword.get(:behaviour, [])
        
        __MODULE__ in behaviours
        
      _ ->
        false
    end
  end
end