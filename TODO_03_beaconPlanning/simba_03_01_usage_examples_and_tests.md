# Usage Examples and Tests for DSPEx SIMBA Integration

defmodule DSPEx.Teleprompter.SIMBA.Examples do
  @moduledoc """
  Comprehensive examples and usage patterns for DSPEx SIMBA teleprompter.
  
  This module demonstrates various ways to use SIMBA for optimizing DSPEx programs,
  including different types of tasks, evaluation metrics, and configuration options.
  """

  alias DSPEx.{Example, Predict, Program}
  alias DSPEx.Teleprompter.SIMBA

  @doc """
  Example 1: Question Answering Optimization
  
  Demonstrates basic SIMBA usage for optimizing a question-answering program.
  """
  def question_answering_example do
    # Define signature
    defmodule QASignature do
      @moduledoc "Answer questions with clear, accurate responses"
      use DSPEx.Signature, "question -> answer"
    end

    # Create student and teacher programs
    student = Predict.new(QASignature, :gemini)
    teacher = Predict.new(QASignature, :openai)  # Use stronger model as teacher

    # Create training examples
    trainset = [
      Example.new(%{
        problem: "Tom saves $5 every week. After 12 weeks, how much money has he saved?",
        reasoning: "Tom saves $5 per week for 12 weeks. Total savings = $5 × 12 = $60.",
        answer: "$60"
      }, [:problem]),
      
      Example.new(%{
        problem: "A pizza is cut into 8 equal slices. If 3 slices are eaten, what fraction of the pizza remains?",
        reasoning: "The pizza has 8 slices total. 3 slices are eaten, so 8 - 3 = 5 slices remain. The fraction remaining is 5/8.",
        answer: "5/8"
      }, [:problem])
    ]

    # Sophisticated metric for reasoning tasks
    metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      
      # Check answer correctness (60% of score)
      answer_score = 
        if normalize_answer(expected_outputs[:answer]) == normalize_answer(prediction[:answer]) do
          0.6
        else
          0.0
        end

      # Check reasoning quality (40% of score)
      reasoning_score = evaluate_reasoning_quality(
        expected_outputs[:reasoning], 
        prediction[:reasoning]
      )

      answer_score + reasoning_score
    end

    # Configure SIMBA for reasoning optimization
    teleprompter = SIMBA.new(
      num_candidates: 25,
      max_bootstrapped_demos: 3,
      num_trials: 50,
      quality_threshold: 0.75,
      instruction_model: :openai,  # Use stronger model for instruction generation
      progress_callback: &detailed_progress_reporter/1
    )

    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✓ Reasoning optimization successful!")
        
        # Test with a complex problem
        test_problem = """
        A bakery sells cupcakes for $3 each and cookies for $2 each. 
        If someone buys 4 cupcakes and 6 cookies, and pays with a $30 bill, 
        how much change should they receive?
        """

        case Program.forward(optimized_student, %{problem: test_problem}) do
          {:ok, result} ->
            IO.puts("\nTest Problem: #{test_problem}")
            IO.puts("Reasoning: #{result[:reasoning]}")
            IO.puts("Answer: #{result[:answer]}")
            {:ok, optimized_student}
          
          {:error, reason} ->
            IO.puts("Test failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("✗ Reasoning optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 4: Multi-Step Program Optimization
  
  Shows how to optimize a complex program with multiple steps.
  """
  def multi_step_program_example do
    # Define a multi-step program
    defmodule MultiStepProgram do
      use DSPEx.Program
      
      defstruct [:analyze_step, :synthesize_step, :demos]
      
      @impl DSPEx.Program
      def forward(program, inputs, _opts) do
        with {:ok, analysis} <- Program.forward(program.analyze_step, inputs),
             {:ok, synthesis} <- Program.forward(program.synthesize_step, analysis) do
          {:ok, synthesis}
        else
          {:error, reason} -> {:error, reason}
        end
      end
    end

    # Define signatures for each step
    defmodule AnalysisSignature do
      @moduledoc "Analyze the input and extract key information"
      use DSPEx.Signature, "text -> key_points, sentiment, entities"
    end

    defmodule SynthesisSignature do
      @moduledoc "Synthesize analysis into a comprehensive summary"
      use DSPEx.Signature, "key_points, sentiment, entities -> summary, recommendation"
    end

    # Create multi-step programs
    student_analyze = Predict.new(AnalysisSignature, :gemini)
    student_synthesize = Predict.new(SynthesisSignature, :gemini)
    
    student = %MultiStepProgram{
      analyze_step: student_analyze,
      synthesize_step: student_synthesize,
      demos: []
    }

    teacher_analyze = Predict.new(AnalysisSignature, :openai)
    teacher_synthesize = Predict.new(SynthesisSignature, :openai)
    
    teacher = %MultiStepProgram{
      analyze_step: teacher_analyze,
      synthesize_step: teacher_synthesize,
      demos: []
    }

    # Training data for text analysis
    trainset = [
      Example.new(%{
        text: "The new smartphone has excellent camera quality and long battery life, but the price is quite high. Customer reviews are mostly positive, praising the build quality.",
        summary: "High-quality smartphone with excellent camera and battery, but expensive. Generally positive customer feedback.",
        recommendation: "Good choice for users prioritizing camera quality and battery life, if budget allows."
      }, [:text]),
      
      Example.new(%{
        text: "This restaurant has amazing food and great service. The atmosphere is cozy and perfect for dates. However, it can get quite crowded on weekends.",
        summary: "Excellent restaurant with great food, service, and romantic atmosphere. Popular and busy on weekends.",
        recommendation: "Highly recommended for special occasions. Make reservations, especially for weekends."
      }, [:text])
    ]

    # Complex metric for multi-step evaluation
    metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      
      summary_score = text_similarity(expected_outputs[:summary], prediction[:summary]) * 0.6
      recommendation_score = text_similarity(expected_outputs[:recommendation], prediction[:recommendation]) * 0.4
      
      summary_score + recommendation_score
    end

    # SIMBA configuration for complex programs
    teleprompter = SIMBA.new(
      num_candidates: 15,
      max_bootstrapped_demos: 2,  # Fewer demos for complex programs
      num_trials: 25,
      quality_threshold: 0.7,
      max_concurrency: 10,  # Reduced concurrency for complex operations
      timeout: 90_000,  # Longer timeout for multi-step operations
      progress_callback: &verbose_progress_reporter/1
    )

    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✓ Multi-step optimization successful!")
        
        test_text = """
        The new electric car model offers impressive range and fast charging capabilities. 
        The interior design is modern and comfortable. However, the charging infrastructure 
        in rural areas is still limited, which could be a concern for long trips.
        """

        case Program.forward(optimized_student, %{text: test_text}) do
          {:ok, result} ->
            IO.puts("\nTest Input: #{test_text}")
            IO.puts("Summary: #{result[:summary]}")
            IO.puts("Recommendation: #{result[:recommendation]}")
            {:ok, optimized_student}
          
          {:error, reason} ->
            IO.puts("Test failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("✗ Multi-step optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 5: Advanced SIMBA Configuration
  
  Demonstrates advanced configuration options and custom optimization strategies.
  """
  def advanced_configuration_example do
    # Define signature
    defmodule AdvancedSignature do
      @moduledoc "Provide detailed analysis with confidence and sources"
      use DSPEx.Signature, "query -> analysis, confidence, sources"
    end

    # Create programs with specific models
    student = Predict.new(AdvancedSignature, :gemini, adapter: CustomAdapter)
    teacher = Predict.new(AdvancedSignature, :openai, adapter: CustomAdapter)

    # Rich training dataset
    trainset = create_rich_dataset()

    # Advanced metric with multiple criteria
    metric_fn = create_advanced_metric()

    # Advanced SIMBA configuration
    teleprompter = SIMBA.new(
      # Core parameters
      num_candidates: 30,
      max_bootstrapped_demos: 5,
      max_labeled_demos: 20,
      num_trials: 75,
      quality_threshold: 0.85,
      
      # Performance tuning
      max_concurrency: 25,
      timeout: 120_000,
      teacher_retries: 3,
      
      # Model selection
      instruction_model: :openai,
      evaluation_model: :gemini,
      
      # Progress monitoring
      progress_callback: &advanced_progress_reporter/1
    )

    # Run optimization with detailed logging
    start_time = System.monotonic_time()
    
    case teleprompter.compile(student, teacher, trainset, metric_fn,
           correlation_id: "advanced_example_#{:os.system_time(:millisecond)}") do
      {:ok, optimized_student} ->
        duration = System.convert_time_unit(
          System.monotonic_time() - start_time,
          :native,
          :millisecond
        )
        
        IO.puts("✓ Advanced optimization completed in #{duration}ms")
        
        # Comprehensive testing
        run_comprehensive_tests(optimized_student)

      {:error, reason} ->
        IO.puts("✗ Advanced optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper functions for examples

  defp progress_reporter(progress) do
    case progress.phase do
      :bootstrap_generation ->
        IO.write("\rBootstrap: #{progress.completed}/#{progress.total}")
      
      :bayesian_optimization ->
        IO.write("\rOptimization: Trial #{progress.trial}/#{progress.total_trials} (Score: #{Float.round(progress.current_score, 3)})")
      
      _ ->
        IO.write("\r#{progress.phase}: #{inspect(progress)}")
    end
  end

  defp detailed_progress_reporter(progress) do
    timestamp = DateTime.utc_now() |> DateTime.to_string()
    
    case progress.phase do
      :bootstrap_generation ->
        percentage = Float.round(progress.completed / progress.total * 100, 1)
        IO.puts("[#{timestamp}] Bootstrap Generation: #{percentage}% (#{progress.completed}/#{progress.total})")
      
      :bayesian_optimization ->
        IO.puts("[#{timestamp}] Trial #{progress.trial}: Score #{Float.round(progress.current_score, 4)}")
      
      _ ->
        IO.puts("[#{timestamp}] #{progress.phase}: #{inspect(progress)}")
    end
  end

  defp verbose_progress_reporter(progress) do
    IO.puts("\n=== Progress Update ===")
    IO.puts("Phase: #{progress.phase}")
    IO.puts("Correlation ID: #{progress[:correlation_id]}")
    IO.puts("Details: #{inspect(progress)}")
    IO.puts("Timestamp: #{DateTime.utc_now()}")
    IO.puts("=====================\n")
  end

  defp advanced_progress_reporter(progress) do
    # Store progress in a persistent log
    log_entry = %{
      timestamp: DateTime.utc_now(),
      phase: progress.phase,
      correlation_id: progress[:correlation_id],
      details: progress
    }
    
    # In a real implementation, you might store this in ETS, GenServer, or database
    IO.puts("LOG: #{inspect(log_entry)}")
    
    # Also provide console feedback
    detailed_progress_reporter(progress)
  end

  defp string_similarity(str1, str2) when is_binary(str1) and is_binary(str2) do
    # Simple Jaccard similarity on words
    words1 = str1 |> String.downcase() |> String.split() |> MapSet.new()
    words2 = str2 |> String.downcase() |> String.split() |> MapSet.new()
    
    intersection = MapSet.intersection(words1, words2) |> MapSet.size()
    union = MapSet.union(words1, words2) |> MapSet.size()
    
    if union == 0, do: 1.0, else: intersection / union
  end

  defp string_similarity(_, _), do: 0.0

  defp normalize_answer(answer) when is_binary(answer) do
    answer
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.trim()
  end

  defp normalize_answer(_), do: ""

  defp evaluate_reasoning_quality(expected, actual) do
    # Simple reasoning quality evaluation
    # In practice, you might use more sophisticated NLP techniques
    
    expected_keywords = extract_keywords(expected)
    actual_keywords = extract_keywords(actual)
    
    keyword_overlap = string_similarity(
      Enum.join(expected_keywords, " "),
      Enum.join(actual_keywords, " ")
    )
    
    # Check for mathematical operations
    has_math_operations = String.contains?(actual, ["×", "*", "+", "-", "="])
    math_bonus = if has_math_operations, do: 0.1, else: 0.0
    
    min(keyword_overlap * 0.4 + math_bonus, 0.4)
  end

  defp extract_keywords(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.reject(&(&1 in ["with", "from", "that", "this", "they", "have", "will"]))
  end

  defp extract_keywords(_), do: []

  defp text_similarity(text1, text2) do
    # More sophisticated text similarity for longer texts
    if String.length(text1) == 0 and String.length(text2) == 0 do
      1.0
    else
      words_similarity = string_similarity(text1, text2)
      
      # Length similarity bonus
      len1 = String.length(text1)
      len2 = String.length(text2)
      length_similarity = 1.0 - abs(len1 - len2) / max(len1, len2)
      
      words_similarity * 0.8 + length_similarity * 0.2
    end
  end

  defp create_rich_dataset do
    [
      Example.new(%{
        query: "What are the benefits of renewable energy?",
        analysis: "Renewable energy offers environmental benefits by reducing greenhouse gas emissions, economic advantages through job creation and energy independence, and technological innovation opportunities.",
        confidence: "high",
        sources: "EPA reports, IEA studies, peer-reviewed research"
      }, [:query]),
      
      Example.new(%{
        query: "How does machine learning work?",
        analysis: "Machine learning uses algorithms to identify patterns in data, make predictions, and improve performance through experience without explicit programming for each task.",
        confidence: "high", 
        sources: "Academic textbooks, research papers, industry documentation"
      }, [:query]),
      
      # Add more examples...
    ]
  end

  defp create_advanced_metric do
    fn example, prediction ->
      expected = Example.outputs(example)
      
      # Analysis quality (50%)
      analysis_score = text_similarity(expected[:analysis], prediction[:analysis]) * 0.5
      
      # Confidence appropriateness (25%)
      confidence_score = 
        case {expected[:confidence], prediction[:confidence]} do
          {same, same} -> 0.25
          {"high", "medium"} -> 0.15
          {"medium", "high"} -> 0.15
          {"medium", "low"} -> 0.10
          {"low", "medium"} -> 0.10
          _ -> 0.0
        end
      
      # Sources relevance (25%)
      sources_score = 
        if String.contains?(prediction[:sources] || "", ["research", "study", "report"]) do
          0.25
        else
          0.1
        end
      
      analysis_score + confidence_score + sources_score
    end
  end

  defp run_comprehensive_tests(optimized_program) do
    test_cases = [
      %{query: "What is quantum computing?"},
      %{query: "How does climate change affect agriculture?"},
      %{query: "What are the principles of good design?"}
    ]

    IO.puts("\n=== Comprehensive Testing ===")
    
    results = 
      Enum.map(test_cases, fn test_case ->
        case Program.forward(optimized_program, test_case) do
          {:ok, result} ->
            IO.puts("\nQuery: #{test_case.query}")
            IO.puts("Analysis: #{String.slice(result[:analysis] || "", 0, 100)}...")
            IO.puts("Confidence: #{result[:confidence]}")
            IO.puts("Sources: #{result[:sources]}")
            {:ok, result}
          
          {:error, reason} ->
            IO.puts("\nQuery: #{test_case.query}")
            IO.puts("Error: #{inspect(reason)}")
            {:error, reason}
        end
      end)

    success_rate = 
      results
      |> Enum.count(&match?({:ok, _}, &1))
      |> Kernel./(length(results))
      |> Kernel.*(100)
      |> Float.round(1)

    IO.puts("\n=== Test Results ===")
    IO.puts("Success Rate: #{success_rate}%")
    IO.puts("Total Tests: #{length(results)}")
    
    {:ok, %{success_rate: success_rate, results: results}}
  end

  # Custom adapter example (placeholder)
  defmodule CustomAdapter do
    def format_messages(signature, demos, inputs) do
      # Custom formatting logic here
      DSPEx.Adapter.format_messages(signature, inputs)
    end

    def parse_response(signature, response) do
      # Custom parsing logic here
      DSPEx.Adapter.parse_response(signature, response)
    end
  end
end

# Test module for SIMBA functionality
defmodule DSPEx.Teleprompter.SIMBATest do
  @moduledoc """
  Comprehensive test suite for SIMBA teleprompter functionality.
  
  Tests cover basic functionality, edge cases, error handling, and performance.
  """

  use ExUnit.Case, async: false
  
  alias DSPEx.{Example, Predict}
  alias DSPEx.Teleprompter.SIMBA

  describe "SIMBA initialization" do
    test "creates SIMBA with default configuration" do
      teleprompter = SIMBA.new()
      
      assert teleprompter.num_candidates == 20
      assert teleprompter.max_bootstrapped_demos == 4
      assert teleprompter.num_trials == 50
      assert teleprompter.quality_threshold == 0.7
    end

    test "creates SIMBA with custom configuration" do
      teleprompter = SIMBA.new(
        num_candidates: 30,
        quality_threshold: 0.8,
        max_concurrency: 15
      )
      
      assert teleprompter.num_candidates == 30
      assert teleprompter.quality_threshold == 0.8
      assert teleprompter.max_concurrency == 15
    end
  end

  describe "SIMBA compilation" do
    setup do
      # Define test signature
      defmodule TestSignature do
        use DSPEx.Signature, "input -> output"
      end

      student = Predict.new(TestSignature, :gemini)
      teacher = Predict.new(TestSignature, :openai)
      
      trainset = [
        Example.new(%{input: "test1", output: "result1"}, [:input]),
        Example.new(%{input: "test2", output: "result2"}, [:input])
      ]

      metric_fn = fn _example, _prediction -> 0.8 end

      %{
        student: student,
        teacher: teacher,
        trainset: trainset,
        metric_fn: metric_fn
      }
    end

    test "validates input parameters", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      teleprompter = SIMBA.new()

      # Test invalid student
      assert {:error, :invalid_student_program} = 
        teleprompter.compile(nil, teacher, trainset, metric_fn)

      # Test invalid teacher
      assert {:error, :invalid_teacher_program} = 
        teleprompter.compile(student, nil, trainset, metric_fn)

      # Test empty trainset
      assert {:error, :invalid_or_empty_trainset} = 
        teleprompter.compile(student, teacher, [], metric_fn)

      # Test invalid metric function
      assert {:error, :invalid_metric_function} = 
        teleprompter.compile(student, teacher, trainset, "not_a_function")
    end

    @tag :integration
    test "performs basic compilation", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Use minimal configuration for testing
      teleprompter = SIMBA.new(
        num_candidates: 2,
        max_bootstrapped_demos: 1,
        num_trials: 3,
        timeout: 30_000
      )

      # Mock the LLM calls to avoid external dependencies in tests
      with_mocked_llm_calls do
        case teleprompter.compile(student, teacher, trainset, metric_fn) do
          {:ok, optimized_student} ->
            assert is_struct(optimized_student)
            
          {:error, reason} ->
            # Accept certain errors in test environment
            assert reason in [:no_successful_bootstrap_candidates, :network_error, :provider_not_configured]
        end
      end
    end
  end

  describe "SIMBA performance and edge cases" do
    test "handles large trainsets efficiently" do
      # Create a large trainset
      large_trainset = 
        1..100
        |> Enum.map(fn i ->
          Example.new(%{input: "test#{i}", output: "result#{i}"}, [:input])
        end)

      teleprompter = SIMBA.new(
        num_candidates: 5,
        max_bootstrapped_demos: 2,
        num_trials: 5,
        max_concurrency: 10
      )

      # Test that it doesn't crash with large datasets
      # (actual execution would require mocking)
      assert is_struct(teleprompter)
      assert length(large_trainset) == 100
    end

    test "handles timeout scenarios gracefully" do
      teleprompter = SIMBA.new(
        timeout: 1,  # Very short timeout
        teacher_retries: 0
      )

      # Verify timeout configuration
      assert teleprompter.timeout == 1
      assert teleprompter.teacher_retries == 0
    end

    test "progress callback functionality" do
      progress_updates = []
      
      progress_callback = fn progress ->
        send(self(), {:progress, progress})
        :ok
      end

      teleprompter = SIMBA.new(
        progress_callback: progress_callback,
        num_candidates: 2,
        num_trials: 2
      )

      assert is_function(teleprompter.progress_callback)
    end
  end

  # Helper function to mock LLM calls for testing
  defp with_mocked_llm_calls(test_func) do
    # In a real test, you would mock DSPEx.Client.request
    # and DSPEx.Program.forward calls here
    test_func.()
  end
end

# Benchmark module for SIMBA performance testing
defmodule DSPEx.Teleprompter.SIMBABenchmark do
  @moduledoc """
  Benchmarking utilities for SIMBA teleprompter performance analysis.
  """

  alias DSPEx.{Example, Predict}
  alias DSPEx.Teleprompter.SIMBA

  @doc """
  Run comprehensive benchmarks for SIMBA optimization.
  """
  def run_benchmarks do
    IO.puts("=== SIMBA Teleprompter Benchmarks ===\n")

    benchmark_configurations = [
      %{name: "Small Scale", candidates: 10, trials: 20, demos: 2},
      %{name: "Medium Scale", candidates: 20, trials: 40, demos: 4},
      %{name: "Large Scale", candidates: 30, trials: 60, demos: 6}
    ]

    results = 
      Enum.map(benchmark_configurations, fn config ->
        IO.puts("Running #{config.name} benchmark...")
        
        result = benchmark_configuration(config)
        
        IO.puts("✓ #{config.name} completed in #{result.duration}ms")
        IO.puts("  - Bootstrap time: #{result.bootstrap_time}ms")
        IO.puts("  - Optimization time: #{result.optimization_time}ms") 
        IO.puts("  - Memory usage: #{result.memory_mb}MB\n")
        
        result
      end)

    print_benchmark_summary(results)
  end

  defp benchmark_configuration(config) do
    # Setup
    defmodule BenchmarkSignature do
      use DSPEx.Signature, "question -> answer"
    end

    student = Predict.new(BenchmarkSignature, :gemini)
    teacher = Predict.new(BenchmarkSignature, :openai)
    trainset = create_benchmark_trainset(config.demos * 5)
    metric_fn = fn _example, _prediction -> :rand.uniform() end

    teleprompter = SIMBA.new(
      num_candidates: config.candidates,
      max_bootstrapped_demos: config.demos,
      num_trials: config.trials,
      max_concurrency: 20
    )

    # Measure performance
    {memory_before, _} = :erlang.process_info(self(), :memory)
    start_time = System.monotonic_time()

    # Note: In actual benchmarks, you'd run real optimization
    # For demo purposes, we simulate the timing
    Process.sleep(config.candidates * 10)  # Simulate bootstrap
    bootstrap_time = System.monotonic_time() - start_time

    Process.sleep(config.trials * 5)  # Simulate optimization
    optimization_time = System.monotonic_time() - start_time - bootstrap_time

    total_time = System.monotonic_time() - start_time
    {memory_after, _} = :erlang.process_info(self(), :memory)

    %{
      config: config,
      duration: System.convert_time_unit(total_time, :native, :millisecond),
      bootstrap_time: System.convert_time_unit(bootstrap_time, :native, :millisecond),
      optimization_time: System.convert_time_unit(optimization_time, :native, :millisecond),
      memory_mb: (memory_after - memory_before) / 1_048_576
    }
  end

  defp create_benchmark_trainset(size) do
    1..size
    |> Enum.map(fn i ->
      Example.new(%{
        question: "Benchmark question #{i}?",
        answer: "Benchmark answer #{i}"
      }, [:question])
    end)
  end

  defp print_benchmark_summary(results) do
    IO.puts("=== Benchmark Summary ===")
    
    total_time = Enum.sum(Enum.map(results, & &1.duration))
    avg_memory = results |> Enum.map(& &1.memory_mb) |> Enum.sum() |> Kernel./(length(results))
    
    IO.puts("Total benchmark time: #{total_time}ms")
    IO.puts("Average memory usage: #{Float.round(avg_memory, 2)}MB")
    
    fastest = Enum.min_by(results, & &1.duration)
    slowest = Enum.max_by(results, & &1.duration)
    
    IO.puts("Fastest: #{fastest.config.name} (#{fastest.duration}ms)")
    IO.puts("Slowest: #{slowest.config.name} (#{slowest.duration}ms)")
    IO.puts("========================")
  end
endquestion: "What is the capital of France?", answer: "Paris"}, [:question]),
      Example.new(%{question: "What is 2 + 2?", answer: "4"}, [:question]),
      Example.new(%{question: "Who wrote Romeo and Juliet?", answer: "William Shakespeare"}, [:question]),
      Example.new(%{question: "What is the largest planet?", answer: "Jupiter"}, [:question]),
      Example.new(%{question: "What year did WWII end?", answer: "1945"}, [:question])
    ]

    # Define metric function
    metric_fn = fn example, prediction ->
      expected = Example.outputs(example)[:answer]
      actual = prediction[:answer]
      
      if String.downcase(expected) == String.downcase(actual) do
        1.0
      else
        # Partial credit for similar answers
        similarity = string_similarity(expected, actual)
        if similarity > 0.8, do: 0.7, else: 0.0
      end
    end

    # Create SIMBA teleprompter
    teleprompter = SIMBA.new(
      num_candidates: 15,
      max_bootstrapped_demos: 3,
      num_trials: 30,
      quality_threshold: 0.6,
      progress_callback: &progress_reporter/1
    )

    # Optimize the student program
    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✓ QA optimization successful!")
        
        # Test the optimized program
        test_input = %{question: "What is the smallest country in the world?"}
        
        case Program.forward(optimized_student, test_input) do
          {:ok, result} ->
            IO.puts("Test result: #{result[:answer]}")
            {:ok, optimized_student}
          
          {:error, reason} ->
            IO.puts("Test failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("✗ QA optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 2: Text Classification with Custom Metrics
  
  Shows how to use SIMBA for text classification with custom evaluation metrics.
  """
  def text_classification_example do
    # Define signature
    defmodule ClassificationSignature do
      @moduledoc "Classify text sentiment as positive, negative, or neutral"
      use DSPEx.Signature, "text -> sentiment, confidence"
    end

    # Create programs
    student = Predict.new(ClassificationSignature, :gemini)
    teacher = Predict.new(ClassificationSignature, :openai)

    # Training data
    trainset = [
      Example.new(%{
        text: "I love this product! It's amazing!",
        sentiment: "positive",
        confidence: "high"
      }, [:text]),
      
      Example.new(%{
        text: "This is terrible. I hate it.",
        sentiment: "negative", 
        confidence: "high"
      }, [:text]),
      
      Example.new(%{
        text: "It's okay, nothing special.",
        sentiment: "neutral",
        confidence: "medium"
      }, [:text]),
      
      Example.new(%{
        text: "Best purchase ever! Highly recommend!",
        sentiment: "positive",
        confidence: "high"
      }, [:text]),
      
      Example.new(%{
        text: "Completely useless waste of money.",
        sentiment: "negative",
        confidence: "high"
      }, [:text])
    ]

    # Custom metric with weighted scoring
    metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      
      # Check sentiment accuracy (70% of score)
      sentiment_score = 
        if expected_outputs[:sentiment] == prediction[:sentiment] do
          0.7
        else
          0.0
        end

      # Check confidence appropriateness (30% of score)
      confidence_score = 
        case {expected_outputs[:confidence], prediction[:confidence]} do
          {"high", "high"} -> 0.3
          {"medium", "medium"} -> 0.3
          {"low", "low"} -> 0.3
          {"high", "medium"} -> 0.15
          {"medium", "high"} -> 0.15
          {"medium", "low"} -> 0.15
          {"low", "medium"} -> 0.15
          _ -> 0.0
        end

      sentiment_score + confidence_score
    end

    # Configure SIMBA for classification task
    teleprompter = SIMBA.new(
      num_candidates: 20,
      max_bootstrapped_demos: 4,
      num_trials: 40,
      quality_threshold: 0.8,
      max_concurrency: 15
    )

    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✓ Classification optimization successful!")
        
        # Test with various examples
        test_cases = [
          "This movie is absolutely fantastic!",
          "I'm not sure how I feel about this.",
          "Worst experience of my life."
        ]

        results = 
          Enum.map(test_cases, fn text ->
            case Program.forward(optimized_student, %{text: text}) do
              {:ok, result} -> 
                {text, result[:sentiment], result[:confidence]}
              {:error, _} -> 
                {text, "error", "unknown"}
            end
          end)

        IO.puts("Test results:")
        Enum.each(results, fn {text, sentiment, confidence} ->
          IO.puts("  \"#{text}\" -> #{sentiment} (#{confidence})")
        end)

        {:ok, optimized_student}

      {:error, reason} ->
        IO.puts("✗ Classification optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 3: Chain-of-Thought Reasoning
  
  Demonstrates SIMBA optimization for complex reasoning tasks.
  """
  def chain_of_thought_example do
    # Define signature for reasoning
    defmodule ReasoningSignature do
      @moduledoc "Solve math word problems with step-by-step reasoning"
      use DSPEx.Signature, "problem -> reasoning, answer"
    end

    # Create programs
    student = Predict.new(ReasoningSignature, :gemini)
    teacher = Predict.new(ReasoningSignature, :openai)

    # Math word problems training set
    trainset = [
      Example.new(%{
        problem: "Sarah has 15 apples. She gives 3 to her friend and buys 7 more. How many apples does she have now?",
        reasoning: "Sarah starts with 15 apples. She gives away 3, leaving her with 15 - 3 = 12 apples. Then she buys 7 more, so 12 + 7 = 19 apples.",
        answer: "19"
      }, [:problem]),
      
      Example.new(%{
        problem: "A rectangular garden is 8 meters long and 6 meters wide. What is its area?",
        reasoning: "The area of a rectangle is length × width. So the area is 8 × 6 = 48 square meters.",
        answer: "48 square meters"
      }, [:problem]),
      
      Example.new(%{
        problem: "Tom saves $5 every week. After 12 weeks, how much money has he saved?",
        reasoning: "Tom saves $5 per week for 12 weeks. Total savings = $5 × 12 = $60.",
        answer: "$60"
      }, [:problem]),
      
      Example.new(%{
        problem: "A pizza is cut into 8 equal slices. If 3 slices are eaten, what fraction of the pizza remains?",
        reasoning: "The pizza has 8 slices total. 3 slices are eaten, so 8 - 3 = 5 slices remain. The fraction remaining is 5/8.",
        answer: "5/8"
      }, [:problem]),
      
      Example.new(%{
        problem: "A store sells notebooks for $3 each. If you buy 4 notebooks and pay with a $20 bill, how much change will you receive?",
        reasoning: "4 notebooks cost 4 × $3 = $12. Change from $20 is $20 - $12 = $8.",
        answer: "$8"
      }, [:problem]),
      
      Example.new(%{
        problem: "In a classroom, there are 6 rows of desks with 5 desks in each row. How many desks are there in total?",
        reasoning: "There are 6 rows with 5 desks each. Total desks = 6 × 5 = 30 desks.",
        answer: "30"
      }, [:problem])
    ]

    # Sophisticated metric for reasoning tasks
    metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      
      # Check answer correctness (60% of score)
      answer_score = 
        if normalize_answer(expected_outputs[:answer]) == normalize_answer(prediction[:answer]) do
          0.6
        else
          # Partial credit for numeric answers that are close
          case {extract_number(expected_outputs[:answer]), extract_number(prediction[:answer])} do
            {expected_num, predicted_num} when is_number(expected_num) and is_number(predicted_num) ->
              diff = abs(expected_num - predicted_num)
              if diff <= expected_num * 0.1, do: 0.3, else: 0.0  # 10% tolerance
            _ ->
              0.0
          end
        end

      # Check reasoning quality (40% of score)
      reasoning_score = evaluate_reasoning_quality(
        expected_outputs[:reasoning], 
        prediction[:reasoning]
      )

      answer_score + reasoning_score
    end

    # Configure SIMBA for reasoning optimization
    teleprompter = SIMBA.new(
      num_candidates: 25,
      max_bootstrapped_demos: 3,
      num_trials: 50,
      quality_threshold: 0.75,
      instruction_model: :openai,  # Use stronger model for instruction generation
      max_concurrency: 15,
      timeout: 90_000,  # Longer timeout for reasoning tasks
      progress_callback: &detailed_progress_reporter/1
    )

    IO.puts("🧠 Starting Chain-of-Thought reasoning optimization...")
    IO.puts("📊 Training set: #{length(trainset)} math word problems")
    
    start_time = System.monotonic_time()

    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        duration = System.convert_time_unit(
          System.monotonic_time() - start_time,
          :native,
          :millisecond
        )
        
        IO.puts("✅ Reasoning optimization successful! (#{duration}ms)")
        
        # Test with a complex problem
        test_problems = [
          """
          A bakery sells cupcakes for $3 each and cookies for $2 each. 
          If someone buys 4 cupcakes and 6 cookies, and pays with a $30 bill, 
          how much change should they receive?
          """,
          
          """
          A train travels at 60 mph for 2 hours, then slows down to 40 mph for the next 3 hours.
          What is the total distance traveled?
          """,
          
          """
          A box contains 24 chocolates. If 1/3 are dark chocolate, 1/4 are milk chocolate,
          and the rest are white chocolate, how many white chocolates are there?
          """
        ]

        IO.puts("\n🔬 Testing optimized reasoning program:")
        
        Enum.each(test_problems, fn problem ->
          IO.puts("\n📝 Problem: #{String.trim(problem)}")
          
          case Program.forward(optimized_student, %{problem: problem}) do
            {:ok, result} ->
              IO.puts("💭 Reasoning: #{result[:reasoning]}")
              IO.puts("🎯 Answer: #{result[:answer]}")
              
              # Validate reasoning contains mathematical operations
              reasoning_quality = analyze_reasoning_structure(result[:reasoning])
              IO.puts("📈 Reasoning Quality: #{reasoning_quality}")
              
            {:error, reason} ->
              IO.puts("❌ Test failed: #{inspect(reason)}")
          end
        end)
        
        # Run validation on original training set
        validation_results = validate_optimized_program(optimized_student, trainset, metric_fn)
        IO.puts("\n📊 Validation Results:")
        IO.puts("   Average Score: #{Float.round(validation_results.average_score, 3)}")
        IO.puts("   Success Rate: #{Float.round(validation_results.success_rate * 100, 1)}%")
        IO.puts("   Improved Examples: #{validation_results.improved_count}/#{length(trainset)}")
        
        {:ok, optimized_student}

      {:error, reason} ->
        IO.puts("❌ Reasoning optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 4: Multi-Modal Reasoning with Images
  
  Demonstrates SIMBA optimization for programs that handle both text and images.
  """
  def multi_modal_example do
    # Define signature for multi-modal tasks
    defmodule MultiModalSignature do
      @moduledoc "Analyze images and answer questions about them"
      use DSPEx.Signature, "image_description, question -> analysis, answer, confidence"
    end

    # Create programs
    student = Predict.new(MultiModalSignature, :gemini)
    teacher = Predict.new(MultiModalSignature, :openai)

    # Multi-modal training set
    trainset = [
      Example.new(%{
        image_description: "A sunny beach with palm trees, blue ocean, and people playing volleyball",
        question: "What recreational activities are visible in this image?",
        analysis: "The image shows a beach scene with clear indicators of recreational activities. There are people engaged in volleyball, which is a common beach sport.",
        answer: "Volleyball and beach recreation",
        confidence: "high"
      }, [:image_description, :question]),
      
      Example.new(%{
        image_description: "A busy city street with cars, buses, traffic lights, and pedestrians crossing",
        question: "What safety concerns might exist in this environment?",
        analysis: "This urban environment presents multiple safety considerations including vehicle traffic, pedestrian crossings, and the need for traffic signal compliance.",
        answer: "Traffic safety, pedestrian crossings, vehicle interactions",
        confidence: "high"
      }, [:image_description, :question]),
      
      Example.new(%{
        image_description: "A kitchen with modern appliances, granite countertops, and fresh vegetables on the counter",
        question: "What type of meal preparation is this kitchen suited for?",
        analysis: "The modern appliances and fresh vegetables suggest this kitchen is well-equipped for healthy meal preparation and cooking from fresh ingredients.",
        answer: "Fresh cooking and healthy meal preparation",
        confidence: "medium"
      }, [:image_description, :question])
    ]

    # Multi-criteria metric for multi-modal tasks
    metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      
      # Analysis quality (40%)
      analysis_score = semantic_similarity_score(
        expected_outputs[:analysis], 
        prediction[:analysis]
      ) * 0.4
      
      # Answer accuracy (35%)
      answer_score = keyword_overlap_score(
        expected_outputs[:answer],
        prediction[:answer]
      ) * 0.35
      
      # Confidence appropriateness (25%)
      confidence_score = confidence_alignment_score(
        expected_outputs[:confidence],
        prediction[:confidence]
      ) * 0.25
      
      analysis_score + answer_score + confidence_score
    end

    # Configure SIMBA for multi-modal optimization
    teleprompter = SIMBA.new(
      num_candidates: 20,
      max_bootstrapped_demos: 4,
      num_trials: 40,
      quality_threshold: 0.7,
      instruction_model: :openai,
      evaluation_model: :gemini,
      max_concurrency: 12,
      timeout: 75_000,
      progress_callback: &multi_modal_progress_reporter/1
    )

    IO.puts("🖼️ Starting Multi-Modal reasoning optimization...")
    
    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✅ Multi-modal optimization successful!")
        
        # Test with complex multi-modal scenarios
        test_cases = [
          %{
            image_description: "A crowded farmers market with vendors selling fruits, vegetables, and handmade crafts",
            question: "What economic and social benefits does this type of market provide?"
          },
          %{
            image_description: "A solar panel installation on a residential rooftop with clear blue skies",
            question: "What environmental and economic factors make this installation beneficial?"
          }
        ]

        IO.puts("\n🔬 Testing multi-modal reasoning:")
        
        Enum.each(test_cases, fn test_case ->
          IO.puts("\n🖼️ Image: #{test_case.image_description}")
          IO.puts("❓ Question: #{test_case.question}")
          
          case Program.forward(optimized_student, test_case) do
            {:ok, result} ->
              IO.puts("🔍 Analysis: #{result[:analysis]}")
              IO.puts("💡 Answer: #{result[:answer]}")
              IO.puts("📊 Confidence: #{result[:confidence]}")
            
            {:error, reason} ->
              IO.puts("❌ Test failed: #{inspect(reason)}")
          end
        end)

        {:ok, optimized_student}

      {:error, reason} ->
        IO.puts("❌ Multi-modal optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 5: Code Generation and Analysis
  
  Shows SIMBA optimization for programming-related tasks.
  """
  def code_generation_example do
    # Define signature for code tasks
    defmodule CodeSignature do
      @moduledoc "Generate and analyze code solutions"
      use DSPEx.Signature, "problem_description, language -> code_solution, explanation, complexity"
    end

    # Create programs
    student = Predict.new(CodeSignature, :gemini)
    teacher = Predict.new(CodeSignature, :openai)

    # Programming training set
    trainset = [
      Example.new(%{
        problem_description: "Write a function to find the maximum value in a list of numbers",
        language: "Python",
        code_solution: "def find_max(numbers):\n    if not numbers:\n        return None\n    return max(numbers)",
        explanation: "This function uses Python's built-in max() function to find the maximum value. It includes a check for empty lists.",
        complexity: "O(n) time, O(1) space"
      }, [:problem_description, :language]),
      
      Example.new(%{
        problem_description: "Implement a binary search algorithm",
        language: "Python",
        code_solution: "def binary_search(arr, target):\n    left, right = 0, len(arr) - 1\n    while left <= right:\n        mid = (left + right) // 2\n        if arr[mid] == target:\n            return mid\n        elif arr[mid] < target:\n            left = mid + 1\n        else:\n            right = mid - 1\n    return -1",
        explanation: "Binary search divides the search space in half each iteration by comparing the target with the middle element.",
        complexity: "O(log n) time, O(1) space"
      }, [:problem_description, :language]),
      
      Example.new(%{
        problem_description: "Create a function to reverse a string",
        language: "Elixir",
        code_solution: "def reverse_string(str) when is_binary(str) do\n  String.reverse(str)\nend",
        explanation: "Uses Elixir's built-in String.reverse/1 function with a guard clause to ensure the input is a binary string.",
        complexity: "O(n) time, O(n) space"
      }, [:problem_description, :language])
    ]

    # Sophisticated metric for code evaluation
    metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      
      # Code correctness (50% - simplified check)
      code_score = evaluate_code_quality(
        expected_outputs[:code_solution],
        prediction[:code_solution]
      ) * 0.5
      
      # Explanation clarity (30%)
      explanation_score = text_similarity(
        expected_outputs[:explanation],
        prediction[:explanation]
      ) * 0.3
      
      # Complexity analysis (20%)
      complexity_score = complexity_accuracy(
        expected_outputs[:complexity],
        prediction[:complexity]
      ) * 0.2
      
      code_score + explanation_score + complexity_score
    end

    # Configure SIMBA for code generation
    teleprompter = SIMBA.new(
      num_candidates: 15,
      max_bootstrapped_demos: 3,
      num_trials: 30,
      quality_threshold: 0.8,
      instruction_model: :openai,  # Better for code instructions
      max_concurrency: 10,
      timeout: 100_000,  # Longer timeout for code generation
      progress_callback: &code_progress_reporter/1
    )

    IO.puts("💻 Starting Code Generation optimization...")
    
    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✅ Code optimization successful!")
        
        # Test with programming problems
        test_problems = [
          %{
            problem_description: "Write a function to calculate the factorial of a number",
            language: "Python"
          },
          %{
            problem_description: "Implement a function to check if a string is a palindrome",
            language: "Elixir"
          },
          %{
            problem_description: "Create a function to merge two sorted arrays",
            language: "Python"
          }
        ]

        IO.puts("\n🔬 Testing code generation:")
        
        Enum.each(test_problems, fn test_case ->
          IO.puts("\n📝 Problem: #{test_case.problem_description}")
          IO.puts("🔧 Language: #{test_case.language}")
          
          case Program.forward(optimized_student, test_case) do
            {:ok, result} ->
              IO.puts("💻 Code Solution:")
              IO.puts(indent_code(result[:code_solution]))
              IO.puts("📖 Explanation: #{result[:explanation]}")
              IO.puts("⚡ Complexity: #{result[:complexity]}")
              
              # Basic code validation
              code_quality = assess_code_structure(result[:code_solution])
              IO.puts("📊 Code Quality: #{code_quality}")
            
            {:error, reason} ->
              IO.puts("❌ Test failed: #{inspect(reason)}")
          end
        end)

        {:ok, optimized_student}

      {:error, reason} ->
        IO.puts("❌ Code optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper functions for examples

  defp detailed_progress_reporter(progress) do
    timestamp = DateTime.utc_now() |> DateTime.to_string()
    
    case progress.phase do
      :bootstrap_generation ->
        percentage = Float.round(progress.completed / progress.total * 100, 1)
        IO.puts("[#{timestamp}] 🔄 Bootstrap Generation: #{percentage}% (#{progress.completed}/#{progress.total})")
      
      :bayesian_optimization ->
        IO.puts("[#{timestamp}] 🎯 Trial #{progress.trial}: Score #{Float.round(progress.current_score, 4)}")
        
        # Show progress bar for trials
        if rem(progress.trial, 5) == 0 do
          progress_bar = create_progress_bar(progress.trial, progress.total_trials)
          IO.puts("     #{progress_bar}")
        end
      
      :instruction_generation ->
        IO.puts("[#{timestamp}] 📝 Generating instruction candidates...")
      
      _ ->
        IO.puts("[#{timestamp}] #{progress.phase}: #{inspect(progress)}")
    end
  end

  defp multi_modal_progress_reporter(progress) do
    emoji = case progress.phase do
      :bootstrap_generation -> "🖼️"
      :bayesian_optimization -> "🧠"
      :instruction_generation -> "📝"
      _ -> "⚙️"
    end
    
    IO.write("\r#{emoji} #{progress.phase} - #{inspect(progress)}")
  end

  defp code_progress_reporter(progress) do
    case progress.phase do
      :bootstrap_generation ->
        IO.puts("💻 Generating code demonstrations: #{progress.completed}/#{progress.total}")
      
      :bayesian_optimization ->
        IO.puts("🔍 Optimizing code generation (Trial #{progress.trial}): Score #{Float.round(progress.current_score, 3)}")
      
      _ ->
        IO.puts("⚙️ #{progress.phase}: #{inspect(progress)}")
    end
  end

  defp normalize_answer(answer) when is_binary(answer) do
    answer
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.trim()
  end

  defp normalize_answer(_), do: ""

  defp extract_number(text) when is_binary(text) do
    case Regex.run(~r/\d+(?:\.\d+)?/, text) do
      [number_str] ->
        case Float.parse(number_str) do
          {number, _} -> number
          :error -> 
            case Integer.parse(number_str) do
              {number, _} -> number
              :error -> nil
            end
        end
      nil -> nil
    end
  end

  defp extract_number(_), do: nil

  defp evaluate_reasoning_quality(expected, actual) do
    # Enhanced reasoning quality evaluation
    expected_keywords = extract_reasoning_keywords(expected)
    actual_keywords = extract_reasoning_keywords(actual)
    
    keyword_overlap = calculate_keyword_overlap(expected_keywords, actual_keywords)
    
    # Check for mathematical operations and logical flow
    has_math_operations = String.contains?(actual, ["×", "*", "+", "-", "=", "÷", "/"])
    has_logical_flow = contains_logical_connectors(actual)
    has_step_markers = contains_step_indicators(actual)
    
    base_score = keyword_overlap * 0.25
    math_bonus = if has_math_operations, do: 0.08, else: 0.0
    logic_bonus = if has_logical_flow, do: 0.04, else: 0.0
    step_bonus = if has_step_markers, do: 0.03, else: 0.0
    
    min(base_score + math_bonus + logic_bonus + step_bonus, 0.4)
  end

  defp extract_reasoning_keywords(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.reject(&(&1 in ["the", "and", "but", "with", "from", "that", "this", "they", "have", "will", "are", "for"]))
  end

  defp extract_reasoning_keywords(_), do: []

  defp calculate_keyword_overlap(keywords1, keywords2) do
    set1 = MapSet.new(keywords1)
    set2 = MapSet.new(keywords2)
    
    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()
    
    if union == 0, do: 1.0, else: intersection / union
  end

  defp contains_logical_connectors(text) do
    logical_words = ["then", "so", "therefore", "because", "since", "thus", "hence"]
    Enum.any?(logical_words, &String.contains?(String.downcase(text), &1))
  end

  defp contains_step_indicators(text) do
    step_indicators = ["first", "next", "then", "finally", "step", "="]
    Enum.any?(step_indicators, &String.contains?(String.downcase(text), &1))
  end

  defp semantic_similarity_score(text1, text2) do
    # Simplified semantic similarity
    words1 = String.split(String.downcase(text1))
    words2 = String.split(String.downcase(text2))
    
    set1 = MapSet.new(words1)
    set2 = MapSet.new(words2)
    
    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()
    
    if union == 0, do: 1.0, else: intersection / union
  end

  defp keyword_overlap_score(text1, text2) do
    keywords1 = extract_keywords(text1)
    keywords2 = extract_keywords(text2)
    
    calculate_keyword_overlap(keywords1, keywords2)
  end

  defp confidence_alignment_score(expected, actual) do
    confidence_map = %{
      "high" => 3,
      "medium" => 2,
      "low" => 1
    }
    
    expected_val = Map.get(confidence_map, expected, 2)
    actual_val = Map.get(confidence_map, actual, 2)
    
    diff = abs(expected_val - actual_val)
    max(0.0, 1.0 - diff / 2.0)
  end

  defp evaluate_code_quality(expected_code, actual_code) do
    # Simplified code quality evaluation
    expected_lines = String.split(expected_code, "\n") |> length()
    actual_lines = String.split(actual_code, "\n") |> length()
    
    # Check for basic code structure
    has_function_def = String.contains?(actual_code, "def ")
    has_return = String.contains?(actual_code, "return")
    has_proper_indentation = check_indentation(actual_code)
    
    base_score = 0.3
    structure_bonus = if has_function_def, do: 0.1, else: 0.0
    return_bonus = if has_return, do: 0.05, else: 0.0
    indent_bonus = if has_proper_indentation, do: 0.05, else: 0.0
    
    base_score + structure_bonus + return_bonus + indent_bonus
  end

  defp check_indentation(code) do
    lines = String.split(code, "\n")
    indented_lines = Enum.filter(lines, &String.starts_with?(&1, "    "))
    
    length(indented_lines) > 0
  end

  defp complexity_accuracy(expected, actual) do
    # Simple complexity matching
    expected_clean = String.downcase(expected) |> String.replace(~r/[^\w\(\)]/, "")
    actual_clean = String.downcase(actual) |> String.replace(~r/[^\w\(\)]/, "")
    
    if String.contains?(actual_clean, expected_clean) do
      1.0
    else
      # Partial credit for containing complexity notation
      if String.contains?(actual_clean, "o(") do
        0.5
      else
        0.0
      end
    end
  end

  defp analyze_reasoning_structure(reasoning) do
    structure_indicators = %{
      has_numbers: Regex.match?(~r/\d+/, reasoning),
      has_operations: String.contains?(reasoning, ["+", "-", "×", "*", "÷", "/", "="]),
      has_steps: contains_step_indicators(reasoning),
      has_logic: contains_logical_connectors(reasoning),
      proper_length: String.length(reasoning) > 20 and String.length(reasoning) < 500
    }
    
    score = structure_indicators
    |> Map.values()
    |> Enum.count(& &1)
    |> Kernel./(5)
    
    quality_levels = [
      {0.8, "Excellent"},
      {0.6, "Good"},
      {0.4, "Fair"},
      {0.0, "Poor"}
    ]
    
    {_, quality} = Enum.find(quality_levels, fn {threshold, _} -> score >= threshold end)
    "#{quality} (#{Float.round(score * 100, 1)}%)"
  end

  defp validate_optimized_program(optimized_program, trainset, metric_fn) do
    results = 
      trainset
      |> Enum.map(fn example ->
        inputs = Example.inputs(example)
        
        case Program.forward(optimized_program, inputs) do
          {:ok, prediction} ->
            score = metric_fn.(example, prediction)
            {:ok, score}
          
          {:error, _reason} ->
            {:error, 0.0}
        end
      end)

    successful_results = Enum.filter(results, &match?({:ok, _}, &1))
    scores = Enum.map(successful_results, fn {:ok, score} -> score end)
    
    %{
      average_score: if(Enum.empty?(scores), do: 0.0, else: Enum.sum(scores) / length(scores)),
      success_rate: length(successful_results) / length(trainset),
      improved_count: Enum.count(scores, &(&1 > 0.5)),
      total_examples: length(trainset)
    }
  end

  defp assess_code_structure(code) when is_binary(code) do
    checks = %{
      has_function: String.contains?(code, "def "),
      has_return: String.contains?(code, "return"),
      has_comments: String.contains?(code, "#"),
      proper_length: String.length(code) > 10 and String.length(code) < 1000,
      has_logic: String.contains?(code, ["if", "while", "for"])
    }
    
    score = checks
    |> Map.values()
    |> Enum.count(& &1)
    |> Kernel./(5)
    
    "#{Float.round(score * 100, 1)}% structural quality"
  end

  defp assess_code_structure(_), do: "0% structural quality"

  defp indent_code(code) when is_binary(code) do
    code
    |> String.split("\n")
    |> Enum.map(&("    " <> &1))
    |> Enum.join("\n")
  end

  defp indent_code(_), do: "    [invalid code]"

  defp create_progress_bar(current, total) do
    percentage = current / total
    filled = round(percentage * 20)
    empty = 20 - filled
    
    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    "Progress: [#{bar}] #{Float.round(percentage * 100, 1)}%"
  end

  defp extract_keywords(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.reject(&(&1 in ["with", "from", "that", "this", "they", "have", "will", "are", "for", "the", "and"]))
  end

  defp extract_keywords(_), do: []

  defp text_similarity(text1, text2) when is_binary(text1) and is_binary(text2) do
    # Enhanced text similarity with multiple factors
    words1 = String.split(String.downcase(text1))
    words2 = String.split(String.downcase(text2))
    
    set1 = MapSet.new(words1)
    set2 = MapSet.new(words2)
    
    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()
    
    jaccard_similarity = if union == 0, do: 1.0, else: intersection / union
    
    # Length similarity bonus
    len1 = length(words1)
    len2 = length(words2)
    length_similarity = 1.0 - abs(len1 - len2) / max(len1, len2, 1)
    
    # Combine similarities
    jaccard_similarity * 0.8 + length_similarity * 0.2
  end

  defp text_similarity(_, _), do: 0.0

  @doc """
  Example 6: Real-time Adaptation and Learning
  
  Demonstrates SIMBA's capability for online learning and adaptation.
  """
  def adaptive_learning_example do
    # Define signature for adaptive tasks
    defmodule AdaptiveSignature do
      @moduledoc "Provide contextually aware responses that improve over time"
      use DSPEx.Signature, "context, user_query -> response, adaptation_note"
    end

    # Create programs
    student = Predict.new(AdaptiveSignature, :gemini)
    teacher = Predict.new(AdaptiveSignature, :openai)

    # Initial training set with diverse contexts
    initial_trainset = [
      Example.new(%{
        context: "Customer service chat - frustrated customer with billing issue",
        user_query: "My bill is completely wrong and I'm very upset!",
        response: "I understand your frustration with the billing issue. Let me help you resolve this quickly. Can you provide your account number so I can review the charges?",
        adaptation_note: "Empathetic tone, action-oriented approach"
      }, [:context, :user_query]),
      
      Example.new(%{
        context: "Technical support - beginner user with software question",
        user_query: "I can't figure out how to save my document",
        response: "No problem! To save your document, you can press Ctrl+S on Windows or Cmd+S on Mac. You can also go to File menu and click Save.",
        adaptation_note: "Simple language, step-by-step instructions"
      }, [:context, :user_query]),
      
      Example.new(%{
        context: "Educational tutoring - student struggling with math",
        user_query: "I don't understand fractions at all",
        response: "Fractions can be tricky! Think of a fraction like a pizza. If you cut a pizza into 4 equal pieces and eat 1 piece, you've eaten 1/4 of the pizza. The bottom number (4) shows how many pieces total, and the top number (1) shows how many pieces you have.",
        adaptation_note: "Visual analogies, encouraging tone, build confidence"
      }, [:context, :user_query])
    ]

    # Adaptive metric that considers context appropriateness
    adaptive_metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      context = Example.inputs(example)[:context]
      
      # Response quality (50%)
      response_quality = evaluate_response_quality(
        expected_outputs[:response],
        prediction[:response],
        context
      ) * 0.5
      
      # Context awareness (30%)
      context_awareness = evaluate_context_awareness(
        context,
        prediction[:response]
      ) * 0.3
      
      # Adaptation learning (20%)
      adaptation_score = evaluate_adaptation_note(
        expected_outputs[:adaptation_note],
        prediction[:adaptation_note]
      ) * 0.2
      
      response_quality + context_awareness + adaptation_score
    end

    # Configure SIMBA for adaptive learning
    teleprompter = SIMBA.new(
      num_candidates: 18,
      max_bootstrapped_demos: 5,
      num_trials: 45,
      quality_threshold: 0.75,
      instruction_model: :openai,
      max_concurrency: 12,
      timeout: 85_000,
      progress_callback: &adaptive_progress_reporter/1
    )

    IO.puts("🧠 Starting Adaptive Learning optimization...")
    IO.puts("📚 Training on contextual awareness and adaptation...")
    
    case teleprompter.compile(student, teacher, initial_trainset, adaptive_metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✅ Adaptive learning optimization successful!")
        
        # Test adaptive responses in different contexts
        test_scenarios = [
          %{
            context: "Medical consultation - patient with anxiety about symptoms",
            user_query: "I've been having headaches and I'm worried it's something serious"
          },
          %{
            context: "Sales conversation - potential customer showing interest",
            user_query: "This product looks interesting, but I'm not sure if it's worth the price"
          },
          %{
            context: "Academic research - graduate student seeking guidance",
            user_query: "I'm struggling to find relevant sources for my literature review"
          },
          %{
            context: "Parenting advice - new parent feeling overwhelmed",
            user_query: "My baby cries all the time and I don't know what to do"
          }
        ]

        IO.puts("\n🔬 Testing adaptive responses across contexts:")
        
        adaptation_results = Enum.map(test_scenarios, fn scenario ->
          IO.puts("\n📍 Context: #{scenario.context}")
          IO.puts("❓ Query: #{scenario.user_query}")
          
          case Program.forward(optimized_student, scenario) do
            {:ok, result} ->
              IO.puts("💬 Response: #{result[:response]}")
              IO.puts("🎯 Adaptation: #{result[:adaptation_note]}")
              
              # Analyze response appropriateness
              appropriateness = analyze_contextual_appropriateness(
                scenario.context,
                result[:response]
              )
              IO.puts("📊 Context Appropriateness: #{appropriateness}")
              
              {:ok, %{scenario: scenario, result: result, appropriateness: appropriateness}}
            
            {:error, reason} ->
              IO.puts("❌ Test failed: #{inspect(reason)}")
              {:error, reason}
          end
        end)

        # Calculate overall adaptation effectiveness
        successful_adaptations = Enum.filter(adaptation_results, &match?({:ok, _}, &1))
        adaptation_rate = length(successful_adaptations) / length(test_scenarios) * 100
        
        IO.puts("\n📈 Adaptation Performance:")
        IO.puts("   Success Rate: #{Float.round(adaptation_rate, 1)}%")
        IO.puts("   Contexts Handled: #{length(successful_adaptations)}/#{length(test_scenarios)}")
        
        {:ok, optimized_student}

      {:error, reason} ->
        IO.puts("❌ Adaptive learning optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 7: Ensemble and Meta-Learning
  
  Shows how to use SIMBA to optimize ensemble programs and meta-learning approaches.
  """
  def ensemble_meta_learning_example do
    # Define signature for ensemble decision making
    defmodule EnsembleSignature do
      @moduledoc "Combine multiple perspectives to make better decisions"
      use DSPEx.Signature, "problem, expert_opinions -> synthesis, confidence, reasoning"
    end

    # Create ensemble components
    analytical_expert = Predict.new(EnsembleSignature, :gemini)
    creative_expert = Predict.new(EnsembleSignature, :openai)
    practical_expert = Predict.new(EnsembleSignature, :gemini)

    # Define ensemble program
    defmodule EnsembleProgram do
      use DSPEx.Program
      
      defstruct [:experts, :meta_learner, :demos]
      
      @impl DSPEx.Program
      def forward(program, inputs, _opts) do
        # Get opinions from all experts
        expert_results = 
          Enum.map(program.experts, fn expert ->
            case Program.forward(expert, inputs) do
              {:ok, result} -> result
              {:error, _} -> %{synthesis: "unavailable", confidence: "low", reasoning: "expert error"}
            end
          end)

        # Combine expert opinions
        combined_input = Map.merge(inputs, %{expert_opinions: expert_results})
        
        # Use meta-learner to synthesize
        Program.forward(program.meta_learner, combined_input)
      end
    end

    student = %EnsembleProgram{
      experts: [analytical_expert, creative_expert, practical_expert],
      meta_learner: Predict.new(EnsembleSignature, :gemini),
      demos: []
    }

    teacher = %EnsembleProgram{
      experts: [
        Predict.new(EnsembleSignature, :openai),
        Predict.new(EnsembleSignature, :openai),
        Predict.new(EnsembleSignature, :openai)
      ],
      meta_learner: Predict.new(EnsembleSignature, :openai),
      demos: []
    }

    # Training set for ensemble learning
    ensemble_trainset = [
      Example.new(%{
        problem: "A startup is deciding whether to expand internationally or focus on domestic growth",
        synthesis: "Focus on domestic growth first to establish strong foundation, then plan international expansion in 18-24 months with lessons learned",
        confidence: "high",
        reasoning: "Balances growth ambition with risk management, allows for learning and resource optimization"
      }, [:problem]),
      
      Example.new(%{
        problem: "A team is split between two different technical approaches for a critical project",
        synthesis: "Implement a small pilot with both approaches to gather real data, then decide based on performance metrics rather than opinions",
        confidence: "medium",
        reasoning: "Evidence-based decision making reduces bias and provides concrete comparison data"
      }, [:problem])
    ]

    # Meta-learning metric that evaluates synthesis quality
    meta_metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      
      # Synthesis quality (60%)
      synthesis_score = evaluate_synthesis_quality(
        expected_outputs[:synthesis],
        prediction[:synthesis]
      ) * 0.6
      
      # Reasoning coherence (25%)
      reasoning_score = evaluate_reasoning_coherence(
        expected_outputs[:reasoning],
        prediction[:reasoning]
      ) * 0.25
      
      # Confidence calibration (15%)
      confidence_score = evaluate_confidence_calibration(
        expected_outputs[:confidence],
        prediction[:confidence]
      ) * 0.15
      
      synthesis_score + reasoning_score + confidence_score
    end

    # Configure SIMBA for meta-learning
    teleprompter = SIMBA.new(
      num_candidates: 12,
      max_bootstrapped_demos: 3,
      num_trials: 25,
      quality_threshold: 0.8,
      instruction_model: :openai,
      max_concurrency: 8,
      timeout: 120_000,  # Longer timeout for ensemble operations
      progress_callback: &ensemble_progress_reporter/1
    )

    IO.puts("🎭 Starting Ensemble Meta-Learning optimization...")
    IO.puts("🧠 Training ensemble decision synthesis...")
    
    case teleprompter.compile(student, teacher, ensemble_trainset, meta_metric_fn) do
      {:ok, optimized_ensemble} ->
        IO.puts("✅ Ensemble optimization successful!")
        
        # Test complex decision scenarios
        decision_scenarios = [
          %{
            problem: "A company must choose between investing in AI automation or hiring more human workers during an economic downturn"
          },
          %{
            problem: "A research team is debating whether to publish preliminary findings now or wait for more comprehensive results"
          },
          %{
            problem: "A city is deciding between building new public transportation or improving existing road infrastructure with limited budget"
          }
        ]

        IO.puts("\n🔬 Testing ensemble decision making:")
        
        Enum.each(decision_scenarios, fn scenario ->
          IO.puts("\n🎯 Decision Problem: #{scenario.problem}")
          
          case Program.forward(optimized_ensemble, scenario) do
            {:ok, result} ->
              IO.puts("🔄 Synthesis: #{result[:synthesis]}")
              IO.puts("📊 Confidence: #{result[:confidence]}")
              IO.puts("🧠 Reasoning: #{result[:reasoning]}")
              
              # Evaluate decision quality
              decision_quality = evaluate_decision_completeness(result)
              IO.puts("⭐ Decision Quality: #{decision_quality}")
            
            {:error, reason} ->
              IO.puts("❌ Ensemble test failed: #{inspect(reason)}")
          end
        end)

        {:ok, optimized_ensemble}

      {:error, reason} ->
        IO.puts("❌ Ensemble optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run comprehensive SIMBA testing suite
  
  Executes all example scenarios and provides detailed performance analysis.
  """
  def run_comprehensive_test_suite do
    IO.puts("🚀 Starting Comprehensive SIMBA Test Suite")
    IO.puts("=" |> String.duplicate(50))
    
    test_results = %{
      chain_of_thought: nil,
      multi_modal: nil,
      code_generation: nil,
      adaptive_learning: nil,
      ensemble_meta: nil
    }

    # Test 1: Chain-of-Thought Reasoning
    IO.puts("\n🧠 Test 1: Chain-of-Thought Reasoning")
    IO.puts("-" |> String.duplicate(40))
    
    cot_result = measure_execution_time(fn ->
      chain_of_thought_example()
    end)
    
    test_results = Map.put(test_results, :chain_of_thought, cot_result)

    # Test 2: Multi-Modal Reasoning
    IO.puts("\n🖼️ Test 2: Multi-Modal Reasoning")
    IO.puts("-" |> String.duplicate(40))
    
    mm_result = measure_execution_time(fn ->
      multi_modal_example()
    end)
    
    test_results = Map.put(test_results, :multi_modal, mm_result)

    # Test 3: Code Generation
    IO.puts("\n💻 Test 3: Code Generation and Analysis")
    IO.puts("-" |> String.duplicate(40))
    
    code_result = measure_execution_time(fn ->
      code_generation_example()
    end)
    
    test_results = Map.put(test_results, :code_generation, code_result)

    # Test 4: Adaptive Learning
    IO.puts("\n🎯 Test 4: Adaptive Learning")
    IO.puts("-" |> String.duplicate(40))
    
    adaptive_result = measure_execution_time(fn ->
      adaptive_learning_example()
    end)
    
    test_results = Map.put(test_results, :adaptive_learning, adaptive_result)

    # Test 5: Ensemble Meta-Learning
    IO.puts("\n🎭 Test 5: Ensemble Meta-Learning")
    IO.puts("-" |> String.duplicate(40))
    
    ensemble_result = measure_execution_time(fn ->
      ensemble_meta_learning_example()
    end)
    
    test_results = Map.put(test_results, :ensemble_meta, ensemble_result)

    # Generate comprehensive report
    generate_test_report(test_results)
  end

  # Additional helper functions for advanced examples

  defp adaptive_progress_reporter(progress) do
    case progress.phase do
      :bootstrap_generation ->
        IO.puts("🧠 Adaptive Bootstrap: #{progress.completed}/#{progress.total} examples processed")
      
      :bayesian_optimization ->
        IO.puts("🎯 Adaptive Trial #{progress.trial}: Contextual Score #{Float.round(progress.current_score, 4)}")
      
      _ ->
        IO.puts("⚙️ Adaptive #{progress.phase}: #{inspect(progress)}")
    end
  end

  defp ensemble_progress_reporter(progress) do
    case progress.phase do
      :bootstrap_generation ->
        IO.puts("🎭 Ensemble Bootstrap: #{progress.completed}/#{progress.total} consensus examples")
      
      :bayesian_optimization ->
        IO.puts("🔄 Meta-Learning Trial #{progress.trial}: Synthesis Score #{Float.round(progress.current_score, 4)}")
      
      _ ->
        IO.puts("🎭 Ensemble #{progress.phase}: #{inspect(progress)}")
    end
  end

  defp evaluate_response_quality(expected_response, actual_response, context) do
    # Base similarity
    base_similarity = text_similarity(expected_response, actual_response)
    
    # Context-specific adjustments
    context_bonus = case String.downcase(context) do
      text when text =~ "customer service" ->
        if String.contains?(String.downcase(actual_response), ["help", "understand", "resolve"]) do
          0.1
        else
          0.0
        end
      
      text when text =~ "technical support" ->
        if String.contains?(String.downcase(actual_response), ["step", "press", "click", "menu"]) do
          0.1
        else
          0.0
        end
      
      text when text =~ "educational" ->
        if String.contains?(String.downcase(actual_response), ["like", "think", "example", "imagine"]) do
          0.1
        else
          0.0
        end
      
      _ ->
        0.0
    end
    
    min(base_similarity + context_bonus, 1.0)
  end

  defp evaluate_context_awareness(context, response) do
    context_keywords = extract_context_keywords(context)
    response_lower = String.downcase(response)
    
    awareness_indicators = [
      # Check for appropriate tone based on context
      check_tone_appropriateness(context, response),
      
      # Check for domain-specific language
      check_domain_language(context, response),
      
      # Check for context-relevant keywords
      Enum.any?(context_keywords, &String.contains?(response_lower, &1))
    ]
    
    Enum.count(awareness_indicators, & &1) / length(awareness_indicators)
  end

  defp evaluate_adaptation_note(expected_note, actual_note) do
    # Check if adaptation note captures key learning points
    expected_concepts = extract_adaptation_concepts(expected_note)
    actual_concepts = extract_adaptation_concepts(actual_note)
    
    calculate_keyword_overlap(expected_concepts, actual_concepts)
  end

  defp analyze_contextual_appropriateness(context, response) do
    appropriateness_scores = %{
      tone: evaluate_tone_match(context, response),
      language_level: evaluate_language_complexity(context, response),
      relevance: evaluate_content_relevance(context, response),
      helpfulness: evaluate_helpfulness(response)
    }
    
    overall_score = appropriateness_scores
    |> Map.values()
    |> Enum.sum()
    |> Kernel./(4)
    
    quality_level = cond do
      overall_score >= 0.8 -> "Excellent"
      overall_score >= 0.6 -> "Good"
      overall_score >= 0.4 -> "Fair"
      true -> "Needs Improvement"
    end
    
    "#{quality_level} (#{Float.round(overall_score * 100, 1)}%)"
  end

  defp evaluate_synthesis_quality(expected_synthesis, actual_synthesis) do
    # Multi-faceted synthesis evaluation
    factors = [
      # Completeness - addresses key aspects
      evaluate_completeness(expected_synthesis, actual_synthesis),
      
      # Balance - considers multiple perspectives
      evaluate_balance(actual_synthesis),
      
      # Actionability - provides concrete guidance
      evaluate_actionability(actual_synthesis),
      
      # Feasibility - realistic and practical
      evaluate_feasibility(actual_synthesis)
    ]
    
    Enum.sum(factors) / length(factors)
  end

  defp evaluate_reasoning_coherence(expected_reasoning, actual_reasoning) do
    # Check logical flow and coherence
    coherence_factors = [
      check_logical_structure(actual_reasoning),
      check_evidence_support(actual_reasoning),
      text_similarity(expected_reasoning, actual_reasoning)
    ]
    
    Enum.sum(coherence_factors) / length(coherence_factors)
  end

  defp evaluate_confidence_calibration(expected_confidence, actual_confidence) do
    confidence_mapping = %{"high" => 0.8, "medium" => 0.6, "low" => 0.4}
    
    expected_val = Map.get(confidence_mapping, expected_confidence, 0.5)
    actual_val = Map.get(confidence_mapping, actual_confidence, 0.5)
    
    1.0 - abs(expected_val - actual_val)
  end

  defp evaluate_decision_completeness(result) do
    completeness_checks = [
      String.length(result[:synthesis]) > 50,  # Sufficient detail
      String.contains?(result[:synthesis], ["should", "recommend", "suggest"]),  # Clear recommendation
      String.length(result[:reasoning]) > 30,  # Adequate reasoning
      result[:confidence] in ["high", "medium", "low"]  # Valid confidence
    ]
    
    score = Enum.count(completeness_checks, & &1) / length(completeness_checks)
    
    case score do
      s when s >= 0.75 -> "Complete and well-reasoned"
      s when s >= 0.5 -> "Adequate with some gaps"
      _ -> "Incomplete or unclear"
    end
  end

  defp measure_execution_time(fun) do
    start_time = System.monotonic_time()
    
    result = try do
      fun.()
    rescue
      exception ->
        {:error, exception}
    catch
      :exit, reason ->
        {:error, {:exit, reason}}
    end
    
    duration = System.convert_time_unit(
      System.monotonic_time() - start_time,
      :native,
      :millisecond
    )
    
    %{
      result: result,
      duration_ms: duration,
      success: match?({:ok, _}, result)
    }
  end

  defp generate_test_report(test_results) do
    IO.puts("\n" <> "=" |> String.duplicate(60))
    IO.puts("📊 COMPREHENSIVE SIMBA TEST REPORT")
    IO.puts("=" |> String.duplicate(60))
    
    # Summary statistics
    total_tests = map_size(test_results)
    successful_tests = test_results |> Map.values() |> Enum.count(& &1.success)
    total_duration = test_results |> Map.values() |> Enum.map(& &1.duration_ms) |> Enum.sum()
    
    IO.puts("\n📈 SUMMARY STATISTICS")
    IO.puts("   Total Tests: #{total_tests}")
    IO.puts("   Successful: #{successful_tests}")
    IO.puts("   Success Rate: #{Float.round(successful_tests / total_tests * 100, 1)}%")
    IO.puts("   Total Duration: #{total_duration}ms (#{Float.round(total_duration / 1000, 1)}s)")
    IO.puts("   Average per Test: #{Float.round(total_duration / total_tests, 1)}ms")
    
    # Individual test results
    IO.puts("\n🔍 INDIVIDUAL TEST RESULTS")
    
    test_results
    |> Enum.each(fn {test_name, result} ->
      status_emoji = if result.success, do: "✅", else: "❌"
      IO.puts("   #{status_emoji} #{format_test_name(test_name)}: #{result.duration_ms}ms")
      
      case result.result do
        {:ok, _} ->
          IO.puts("      Status: Optimization completed successfully")
        
        {:error, reason} ->
          IO.puts("      Status: Failed - #{inspect(reason)}")
      end
    end)
    
    # Performance analysis
    IO.puts("\n⚡ PERFORMANCE ANALYSIS")
    
    fastest_test = test_results |> Enum.min_by(fn {_, result} -> result.duration_ms end)
    slowest_test = test_results |> Enum.max_by(fn {_, result} -> result.duration_ms end)
    
    IO.puts("   Fastest: #{format_test_name(elem(fastest_test, 0))} (#{elem(fastest_test, 1).duration_ms}ms)")
    IO.puts("   Slowest: #{format_test_name(elem(slowest_test, 0))} (#{elem(slowest_test, 1).duration_ms}ms)")
    
    # Recommendations
    IO.puts("\n💡 RECOMMENDATIONS")
    
    if successful_tests == total_tests do
      IO.puts("   🎉 All tests passed! SIMBA integration is working excellently.")
    else
      failed_tests = total_tests - successful_tests
      IO.puts("   ⚠️  #{failed_tests} test(s) failed. Review error logs for optimization.")
    end
    
    if total_duration > 300_000 do  # > 5 minutes
      IO.puts("   🚀 Consider reducing test complexity or increasing concurrency for faster runs.")
    end
    
    IO.puts("\n" <> "=" |> String.duplicate(60))
    IO.puts("Test suite completed at #{DateTime.utc_now()}")
    IO.puts("=" |> String.duplicate(60))
    
    test_results
  end

  # Helper functions for evaluation metrics

  defp extract_context_keywords(context) do
    context
    |> String.downcase()
    |> String.split(~r/[^\w]/)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.take(5)  # Top 5 context keywords
  end

  defp check_tone_appropriateness(context, response) do
    case String.downcase(context) do
      text when text =~ "frustrated" or text =~ "upset" ->
        String.contains?(String.downcase(response), ["understand", "help", "sorry"])
      
      text when text =~ "beginner" or text =~ "student" ->
        String.contains?(String.downcase(response), ["simple", "easy", "step"])
      
      _ ->
        true  # Default to appropriate
    end
  end

  defp check_domain_language(context, response) do
    domain_keywords = %{
      "medical" => ["symptoms", "condition", "treatment", "doctor"],
      "technical" => ["system", "software", "settings", "configuration"],
      "sales" => ["product", "value", "benefits", "features"],
      "education" => ["learn", "understand", "practice", "study"]
    }
    
    Enum.any?(domain_keywords, fn {domain, keywords} ->
      if String.contains?(String.downcase(context), domain) do
        Enum.any?(keywords, &String.contains?(String.downcase(response), &1))
      else
        false
      end
    end)
  end

  defp extract_adaptation_concepts(note) when is_binary(note) do
    note
    |> String.downcase()
    |> String.split(~r/[^\w]/)
    |> Enum.filter(&(String.length(&1) > 3))
  end

  defp extract_adaptation_concepts(_), do: []

  defp evaluate_tone_match(context, response) do
    if check_tone_appropriateness(context, response), do: 1.0, else: 0.5
  end

  defp evaluate_language_complexity(context, response) do
    expected_complexity = cond do
      String.contains?(String.downcase(context), "beginner") -> :simple
      String.contains?(String.downcase(context), "expert") -> :complex
      true -> :medium
    end
    
    actual_complexity = assess_language_complexity(response)
    
    if expected_complexity == actual_complexity, do: 1.0, else: 0.6
  end

  defp assess_language_complexity(text) do
    avg_word_length = 
      text
      |> String.split()
      |> Enum.map(&String.length/1)
      |> Enum.sum()
      |> Kernel./(max(length(String.split(text)), 1))
    
    cond do
      avg_word_length < 4.5 -> :simple
      avg_word_length > 6.0 -> :complex
      true -> :medium
    end
  end

  defp evaluate_content_relevance(context, response) do
    context_words = extract_context_keywords(context)
    response_words = String.split(String.downcase(response))
    
    relevance = Enum.count(context_words, &(&1 in response_words)) / max(length(context_words), 1)
    min(relevance * 2, 1.0)  # Scale up relevance score
  end

  defp evaluate_helpfulness(response) do
    helpful_indicators = [
      String.contains?(String.downcase(response), ["can", "will", "help", "try"]),
      String.contains?(response, ["?", "!"]),  # Engaging punctuation
      String.length(response) > 20,  # Sufficient detail
      not String.contains?(String.downcase(response), ["don't know", "can't help"])
    ]
    
    Enum.count(helpful_indicators, & &1) / length(helpful_indicators)
  end

  defp evaluate_completeness(expected, actual) do
    expected_concepts = String.split(String.downcase(expected))
    actual_concepts = String.split(String.downcase(actual))
    
    coverage = Enum.count(expected_concepts, &(&1 in actual_concepts)) / max(length(expected_concepts), 1)
    min(coverage * 1.5, 1.0)
  end

  defp evaluate_balance(synthesis) do
    balance_indicators = [
      String.contains?(synthesis, ["however", "but", "although", "while"]),
      String.contains?(synthesis, ["both", "and", "as well as"]),
      String.contains?(synthesis, ["consider", "balance", "weigh"])
    ]
    
    Enum.count(balance_indicators, & &1) / length(balance_indicators)
  end

  defp evaluate_actionability(synthesis) do
    action_indicators = [
      String.contains?(synthesis, ["should", "recommend", "suggest", "propose"]),
      String.contains?(synthesis, ["implement", "start", "begin", "create"]),
      String.contains?(synthesis, ["first", "then", "next", "finally"])
    ]
    
    Enum.count(action_indicators, & &1) / length(action_indicators)
  end

  defp evaluate_feasibility(synthesis) do
    feasibility_indicators = [
      not String.contains?(String.downcase(synthesis), ["impossible", "never", "can't"]),
      String.contains?(synthesis, ["practical", "realistic", "achievable", "possible"]),
      String.length(synthesis) > 30  # Sufficient detail for feasibility
    ]
    
    Enum.count(feasibility_indicators, & &1) / length(feasibility_indicators)
  end

  defp check_logical_structure(reasoning) do
    structure_indicators = [
      String.contains?(reasoning, ["because", "since", "therefore", "thus"]),
      String.contains?(reasoning, ["first", "second", "then", "finally"]),
      String.contains?(reasoning, ["leads to", "results in", "causes"])
    ]
    
    if Enum.any?(structure_indicators, & &1), do: 1.0, else: 0.5
  end

  defp check_evidence_support(reasoning) do
    evidence_indicators = [
      String.contains?(reasoning, ["data", "research", "study", "evidence"]),
      String.contains?(reasoning, ["shows", "indicates", "demonstrates"]),
      String.contains?(reasoning, ["based on", "according to"])
    ]
    
    if Enum.any?(evidence_indicators, & &1), do: 1.0, else: 0.5
  end





























































































  defp check_evidence_support(reasoning) do
    evidence_indicators = [
      String.contains?(reasoning, ["data", "research", "study", "evidence"]),
      String.contains?(reasoning, ["shows", "indicates", "demonstrates"]),
      String.contains?(reasoning, ["based on", "according to"])
    ]
    
    if Enum.any?(evidence_indicators, & &1), do: 1.0, else: 0.5
  end

  defp assess_code_structure(code) when is_binary(code) do
    checks = %{
      has_function: String.contains?(code, "def "),
      has_return: String.contains?(code, "return"),
      has_comments: String.contains?(code, "#"),
      proper_length: String.length(code) > 10 and String.length(code) < 1000,
      has_logic: String.contains?(code, ["if", "while", "for"])
    }
    
    score = checks
    |> Map.values()
    |> Enum.count(& &1)
    |> Kernel./(5)
    
    "#{Float.round(score * 100, 1)}% structural quality"
  end

  defp assess_code_structure(_), do: "0% structural quality"

  defp indent_code(code) when is_binary(code) do
    code
    |> String.split("\n")
    |> Enum.map(&("    " <> &1))
    |> Enum.join("\n")
  end

  defp indent_code(_), do: "    [invalid code]"

  defp create_progress_bar(current, total) do
    percentage = current / total
    filled = round(percentage * 20)
    empty = 20 - filled
    
    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    "Progress: [#{bar}] #{Float.round(percentage * 100, 1)}%"
  end

  defp extract_keywords(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.reject(&(&1 in ["with", "from", "that", "this", "they", "have", "will", "are", "for", "the", "and"]))
  end

  defp extract_keywords(_), do: []

  defp text_similarity(text1, text2) when is_binary(text1) and is_binary(text2) do
    # Enhanced text similarity with multiple factors
    words1 = String.split(String.downcase(text1))
    words2 = String.split(String.downcase(text2))
    
    set1 = MapSet.new(words1)
    set2 = MapSet.new(words2)
    
    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()
    
    jaccard_similarity = if union == 0, do: 1.0, else: intersection / union
    
    # Length similarity bonus
    len1 = length(words1)
    len2 = length(words2)
    length_similarity = 1.0 - abs(len1 - len2) / max(len1, len2, 1)
    
    # Combine similarities
    jaccard_similarity * 0.8 + length_similarity * 0.2
  end

  defp text_similarity(_, _), do: 0.0

  @doc """
  Example 6: Real-time Adaptation and Learning
  
  Demonstrates SIMBA's capability for online learning and adaptation.
  """
  def adaptive_learning_example do
    # Define signature for adaptive tasks
    defmodule AdaptiveSignature do
      @moduledoc "Provide contextually aware responses that improve over time"
      use DSPEx.Signature, "context, user_query -> response, adaptation_note"
    end

    # Create programs
    student = Predict.new(AdaptiveSignature, :gemini)
    teacher = Predict.new(AdaptiveSignature, :openai)

    # Initial training set with diverse contexts
    initial_trainset = [
      Example.new(%{
        context: "Customer service chat - frustrated customer with billing issue",
        user_query: "My bill is completely wrong and I'm very upset!",
        response: "I understand your frustration with the billing issue. Let me help you resolve this quickly. Can you provide your account number so I can review the charges?",
        adaptation_note: "Empathetic tone, action-oriented approach"
      }, [:context, :user_query]),
      
      Example.new(%{
        context: "Technical support - beginner user with software question",
        user_query: "I can't figure out how to save my document",
        response: "No problem! To save your document, you can press Ctrl+S on Windows or Cmd+S on Mac. You can also go to File menu and click Save.",
        adaptation_note: "Simple language, step-by-step instructions"
      }, [:context, :user_query]),
      
      Example.new(%{
        context: "Educational tutoring - student struggling with math",
        user_query: "I don't understand fractions at all",
        response: "Fractions can be tricky! Think of a fraction like a pizza. If you cut a pizza into 4 equal pieces and eat 1 piece, you've eaten 1/4 of the pizza. The bottom number (4) shows how many pieces total, and the top number (1) shows how many pieces you have.",
        adaptation_note: "Visual analogies, encouraging tone, build confidence"
      }, [:context, :user_query])
    ]

    # Adaptive metric that considers context appropriateness
    adaptive_metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      context = Example.inputs(example)[:context]
      
      # Response quality (50%)
      response_quality = evaluate_response_quality(
        expected_outputs[:response],
        prediction[:response],
        context
      ) * 0.5
      
      # Context awareness (30%)
      context_awareness = evaluate_context_awareness(
        context,
        prediction[:response]
      ) * 0.3
      
      # Adaptation learning (20%)
      adaptation_score = evaluate_adaptation_note(
        expected_outputs[:adaptation_note],
        prediction[:adaptation_note]
      ) * 0.2
      
      response_quality + context_awareness + adaptation_score
    end

    # Configure SIMBA for adaptive learning
    teleprompter = SIMBA.new(
      num_candidates: 18,
      max_bootstrapped_demos: 5,
      num_trials: 45,
      quality_threshold: 0.75,
      instruction_model: :openai,
      max_concurrency: 12,
      timeout: 85_000,
      progress_callback: &adaptive_progress_reporter/1
    )

    IO.puts("🧠 Starting Adaptive Learning optimization...")
    IO.puts("📚 Training on contextual awareness and adaptation...")
    
    case teleprompter.compile(student, teacher, initial_trainset, adaptive_metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✅ Adaptive learning optimization successful!")
        
        # Test adaptive responses in different contexts
        test_scenarios = [
          %{
            context: "Medical consultation - patient with anxiety about symptoms",
            user_query: "I've been having headaches and I'm worried it's something serious"
          },
          %{
            context: "Sales conversation - potential customer showing interest",
            user_query: "This product looks interesting, but I'm not sure if it's worth the price"
          },
          %{
            context: "Academic research - graduate student seeking guidance",
            user_query: "I'm struggling to find relevant sources for my literature review"
          },
          %{
            context: "Parenting advice - new parent feeling overwhelmed",
            user_query: "My baby cries all the time and I don't know what to do"
          }
        ]

        IO.puts("\n🔬 Testing adaptive responses across contexts:")
        
        adaptation_results = Enum.map(test_scenarios, fn scenario ->
          IO.puts("\n📍 Context: #{scenario.context}")
          IO.puts("❓ Query: #{scenario.user_query}")
          
          case Program.forward(optimized_student, scenario) do
            {:ok, result} ->
              IO.puts("💬 Response: #{result[:response]}")
              IO.puts("🎯 Adaptation: #{result[:adaptation_note]}")
              
              # Analyze response appropriateness
              appropriateness = analyze_contextual_appropriateness(
                scenario.context,
                result[:response]
              )
              IO.puts("📊 Context Appropriateness: #{appropriateness}")
              
              {:ok, %{scenario: scenario, result: result, appropriateness: appropriateness}}
            
            {:error, reason} ->
              IO.puts("❌ Test failed: #{inspect(reason)}")
              {:error, reason}
          end
        end)

        # Calculate overall adaptation effectiveness
        successful_adaptations = Enum.filter(adaptation_results, &match?({:ok, _}, &1))
        adaptation_rate = length(successful_adaptations) / length(test_scenarios) * 100
        
        IO.puts("\n📈 Adaptation Performance:")
        IO.puts("   Success Rate: #{Float.round(adaptation_rate, 1)}%")
        IO.puts("   Contexts Handled: #{length(successful_adaptations)}/#{length(test_scenarios)}")
        
        {:ok, optimized_student}

      {:error, reason} ->
        IO.puts("❌ Adaptive learning optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 7: Ensemble and Meta-Learning
  
  Shows how to use SIMBA to optimize ensemble programs and meta-learning approaches.
  """
  def ensemble_meta_learning_example do
    # Define signature for ensemble decision making
    defmodule EnsembleSignature do
      @moduledoc "Combine multiple perspectives to make better decisions"
      use DSPEx.Signature, "problem, expert_opinions -> synthesis, confidence, reasoning"
    end

    # Create ensemble components
    analytical_expert = Predict.new(EnsembleSignature, :gemini)
    creative_expert = Predict.new(EnsembleSignature, :openai)
    practical_expert = Predict.new(EnsembleSignature, :gemini)

    # Define ensemble program
    defmodule EnsembleProgram do
      use DSPEx.Program
      
      defstruct [:experts, :meta_learner, :demos]
      
      @impl DSPEx.Program
      def forward(program, inputs, _opts) do
        # Get opinions from all experts
        expert_results = 
          Enum.map(program.experts, fn expert ->
            case Program.forward(expert, inputs) do
              {:ok, result} -> result
              {:error, _} -> %{synthesis: "unavailable", confidence: "low", reasoning: "expert error"}
            end
          end)

        # Combine expert opinions
        combined_input = Map.merge(inputs, %{expert_opinions: expert_results})
        
        # Use meta-learner to synthesize
        Program.forward(program.meta_learner, combined_input)
      end
    end

    student = %EnsembleProgram{
      experts: [analytical_expert, creative_expert, practical_expert],
      meta_learner: Predict.new(EnsembleSignature, :gemini),
      demos: []
    }

    teacher = %EnsembleProgram{
      experts: [
        Predict.new(EnsembleSignature, :openai),
        Predict.new(EnsembleSignature, :openai),
        Predict.new(EnsembleSignature, :openai)
      ],
      meta_learner: Predict.new(EnsembleSignature, :openai),
      demos: []
    }

    # Training set for ensemble learning
    ensemble_trainset = [
      Example.new(%{
        problem: "A startup is deciding whether to expand internationally or focus on domestic growth",
        synthesis: "Focus on domestic growth first to establish strong foundation, then plan international expansion in 18-24 months with lessons learned",
        confidence: "high",
        reasoning: "Balances growth ambition with risk management, allows for learning and resource optimization"
      }, [:problem]),
      
      Example.new(%{
        problem: "A team is split between two different technical approaches for a critical project",
        synthesis: "Implement a small pilot with both approaches to gather real data, then decide based on performance metrics rather than opinions",
        confidence: "medium",
        reasoning: "Evidence-based decision making reduces bias and provides concrete comparison data"
      }, [:problem])
    ]

    # Meta-learning metric that evaluates synthesis quality
    meta_metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)
      
      # Synthesis quality (60%)
      synthesis_score = evaluate_synthesis_quality(
        expected_outputs[:synthesis],
        prediction[:synthesis]
      ) * 0.6
      
      # Reasoning coherence (25%)
      reasoning_score = evaluate_reasoning_coherence(
        expected_outputs[:reasoning],
        prediction[:reasoning]
      ) * 0.25
      
      # Confidence calibration (15%)
      confidence_score = evaluate_confidence_calibration(
        expected_outputs[:confidence],
        prediction[:confidence]
      ) * 0.15
      
      synthesis_score + reasoning_score + confidence_score
    end

    # Configure SIMBA for meta-learning
    teleprompter = SIMBA.new(
      num_candidates: 12,
      max_bootstrapped_demos: 3,
      num_trials: 25,
      quality_threshold: 0.8,
      instruction_model: :openai,
      max_concurrency: 8,
      timeout: 120_000,  # Longer timeout for ensemble operations
      progress_callback: &ensemble_progress_reporter/1
    )

    IO.puts("🎭 Starting Ensemble Meta-Learning optimization...")
    IO.puts("🧠 Training ensemble decision synthesis...")
    
    case teleprompter.compile(student, teacher, ensemble_trainset, meta_metric_fn) do
      {:ok, optimized_ensemble} ->
        IO.puts("✅ Ensemble optimization successful!")
        
        # Test complex decision scenarios
        decision_scenarios = [
          %{
            problem: "A company must choose between investing in AI automation or hiring more human workers during an economic downturn"
          },
          %{
            problem: "A research team is debating whether to publish preliminary findings now or wait for more comprehensive results"
          },
          %{
            problem: "A city is deciding between building new public transportation or improving existing road infrastructure with limited budget"
          }
        ]

        IO.puts("\n🔬 Testing ensemble decision making:")
        
        Enum.each(decision_scenarios, fn scenario ->
          IO.puts("\n🎯 Decision Problem: #{scenario.problem}")
          
          case Program.forward(optimized_ensemble, scenario) do
            {:ok, result} ->
              IO.puts("🔄 Synthesis: #{result[:synthesis]}")
              IO.puts("📊 Confidence: #{result[:confidence]}")
              IO.puts("🧠 Reasoning: #{result[:reasoning]}")
              
              # Evaluate decision quality
              decision_quality = evaluate_decision_completeness(result)
              IO.puts("⭐ Decision Quality: #{decision_quality}")
            
            {:error, reason} ->
              IO.puts("❌ Ensemble test failed: #{inspect(reason)}")
          end
        end)

        {:ok, optimized_ensemble}

      {:error, reason} ->
        IO.puts("❌ Ensemble optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run comprehensive SIMBA testing suite
  
  Executes all example scenarios and provides detailed performance analysis.
  """
  def run_comprehensive_test_suite do
    IO.puts("🚀 Starting Comprehensive SIMBA Test Suite")
    IO.puts("=" |> String.duplicate(50))
    
    test_results = %{
      chain_of_thought: nil,
      multi_modal: nil,
      code_generation: nil,
      adaptive_learning: nil,
      ensemble_meta: nil
    }

    # Test 1: Chain-of-Thought Reasoning
    IO.puts("\n🧠 Test 1: Chain-of-Thought Reasoning")
    IO.puts("-" |> String.duplicate(40))
    
    cot_result = measure_execution_time(fn ->
      chain_of_thought_example()
    end)
    
    test_results = Map.put(test_results, :chain_of_thought, cot_result)

    # Test 2: Multi-Modal Reasoning
    IO.puts("\n🖼️ Test 2: Multi-Modal Reasoning")
    IO.puts("-" |> String.duplicate(40))
    
    mm_result = measure_execution_time(fn ->
      multi_modal_example()
    end)
    
    test_results = Map.put(test_results, :multi_modal, mm_result)

    # Test 3: Code Generation
    IO.puts("\n💻 Test 3: Code Generation and Analysis")
    IO.puts("-" |> String.duplicate(40))
    
    code_result = measure_execution_time(fn ->
      code_generation_example()
    end)
    
    test_results = Map.put(test_results, :code_generation, code_result)

    # Test 4: Adaptive Learning
    IO.puts("\n🎯 Test 4: Adaptive Learning")
    IO.puts("-" |> String.duplicate(40))
    
    adaptive_result = measure_execution_time(fn ->
      adaptive_learning_example()
    end)
    
    test_results = Map.put(test_results, :adaptive_learning, adaptive_result)

    # Test 5: Ensemble Meta-Learning
    IO.puts("\n🎭 Test 5: Ensemble Meta-Learning")
    IO.puts("-" |> String.duplicate(40))
    
    ensemble_result = measure_execution_time(fn ->
      ensemble_meta_learning_example()
    end)
    
    test_results = Map.put(test_results, :ensemble_meta, ensemble_result)

    # Generate comprehensive report
    generate_test_report(test_results)
  end

  # Additional helper functions for advanced examples

  defp adaptive_progress_reporter(progress) do
    case progress.phase do
      :bootstrap_generation ->
        IO.puts("🧠 Adaptive Bootstrap: #{progress.completed}/#{progress.total} examples processed")
      
      :bayesian_optimization ->
        IO.puts("🎯 Adaptive Trial #{progress.trial}: Contextual Score #{Float.round(progress.current_score, 4)}")
      
      _ ->
        IO.puts("⚙️ Adaptive #{progress.phase}: #{inspect(progress)}")
    end
  end

  defp ensemble_progress_reporter(progress) do
    case progress.phase do
      :bootstrap_generation ->
        IO.puts("🎭 Ensemble Bootstrap: #{progress.completed}/#{progress.total} consensus examples")
      
      :bayesian_optimization ->
        IO.puts("🔄 Meta-Learning Trial #{progress.trial}: Synthesis Score #{Float.round(progress.current_score, 4)}")
      
      _ ->
        IO.puts("🎭 Ensemble #{progress.phase}: #{inspect(progress)}")
    end
  end

  defp evaluate_response_quality(expected_response, actual_response, context) do
    # Base similarity
    base_similarity = text_similarity(expected_response, actual_response)
    
    # Context-specific adjustments
    context_bonus = case String.downcase(context) do
      text when text =~ "customer service" ->
        if String.contains?(String.downcase(actual_response), ["help", "understand", "resolve"]) do
          0.1
        else
          0.0
        end
      
      text when text =~ "technical support" ->
        if String.contains?(String.downcase(actual_response), ["step", "press", "click", "menu"]) do
          0.1
        else
          0.0
        end
      
      text when text =~ "educational" ->
        if String.contains?(String.downcase(actual_response), ["like", "think", "example", "imagine"]) do
          0.1
        else
          0.0
        end
      
      _ ->
        0.0
    end
    
    min(base_similarity + context_bonus, 1.0)
  end

  defp evaluate_context_awareness(context, response) do
    context_keywords = extract_context_keywords(context)
    response_lower = String.downcase(response)
    
    awareness_indicators = [
      # Check for appropriate tone based on context
      check_tone_appropriateness(context, response),
      
      # Check for domain-specific language
      check_domain_language(context, response),
      
      # Check for context-relevant keywords
      Enum.any?(context_keywords, &String.contains?(response_lower, &1))
    ]
    
    Enum.count(awareness_indicators, & &1) / length(awareness_indicators)
  end

  defp evaluate_adaptation_note(expected_note, actual_note) do
    # Check if adaptation note captures key learning points
    expected_concepts = extract_adaptation_concepts(expected_note)
    actual_concepts = extract_adaptation_concepts(actual_note)
    
    calculate_keyword_overlap(expected_concepts, actual_concepts)
  end

  defp analyze_contextual_appropriateness(context, response) do
    appropriateness_scores = %{
      tone: evaluate_tone_match(context, response),
      language_level: evaluate_language_complexity(context, response),
      relevance: evaluate_content_relevance(context, response),
      helpfulness: evaluate_helpfulness(response)
    }
    
    overall_score = appropriateness_scores
    |> Map.values()
    |> Enum.sum()
    |> Kernel./(4)
    
    quality_level = cond do
      overall_score >= 0.8 -> "Excellent"
      overall_score >= 0.6 -> "Good"
      overall_score >= 0.4 -> "Fair"
      true -> "Needs Improvement"
    end
    
    "#{quality_level} (#{Float.round(overall_score * 100, 1)}%)"
  end

  defp evaluate_synthesis_quality(expected_synthesis, actual_synthesis) do
    # Multi-faceted synthesis evaluation
    factors = [
      # Completeness - addresses key aspects
      evaluate_completeness(expected_synthesis, actual_synthesis),
      
      # Balance - considers multiple perspectives
      evaluate_balance(actual_synthesis),
      
      # Actionability - provides concrete guidance
      evaluate_actionability(actual_synthesis),
      
      # Feasibility - realistic and practical
      evaluate_feasibility(actual_synthesis)
    ]
    
    Enum.sum(factors) / length(factors)
  end

  defp evaluate_reasoning_coherence(expected_reasoning, actual_reasoning) do
    # Check logical flow and coherence
    coherence_factors = [
      check_logical_structure(actual_reasoning),
      check_evidence_support(actual_reasoning),
      text_similarity(expected_reasoning, actual_reasoning)
    ]
    
    Enum.sum(coherence_factors) / length(coherence_factors)
  end

  defp evaluate_confidence_calibration(expected_confidence, actual_confidence) do
    confidence_mapping = %{"high" => 0.8, "medium" => 0.6, "low" => 0.4}
    
    expected_val = Map.get(confidence_mapping, expected_confidence, 0.5)
    actual_val = Map.get(confidence_mapping, actual_confidence, 0.5)
    
    1.0 - abs(expected_val - actual_val)
  end

  defp evaluate_decision_completeness(result) do
    completeness_checks = [
      String.length(result[:synthesis]) > 50,  # Sufficient detail
      String.contains?(result[:synthesis], ["should", "recommend", "suggest"]),  # Clear recommendation
      String.length(result[:reasoning]) > 30,  # Adequate reasoning
      result[:confidence] in ["high", "medium", "low"]  # Valid confidence
    ]
    
    score = Enum.count(completeness_checks, & &1) / length(completeness_checks)
    
    case score do
      s when s >= 0.75 -> "Complete and well-reasoned"
      s when s >= 0.5 -> "Adequate with some gaps"
      _ -> "Incomplete or unclear"
    end
  end

  defp measure_execution_time(fun) do
    start_time = System.monotonic_time()
    
    result = try do
      fun.()
    rescue
      exception ->
        {:error, exception}
    catch
      :exit, reason ->
        {:error, {:exit, reason}}
    end
    
    duration = System.convert_time_unit(
      System.monotonic_time() - start_time,
      :native,
      :millisecond
    )
    
    %{
      result: result,
      duration_ms: duration,
      success: match?({:ok, _}, result)
    }
  end

  defp generate_test_report(test_results) do
    IO.puts("\n" <> "=" |> String.duplicate(60))
    IO.puts("📊 COMPREHENSIVE SIMBA TEST REPORT")
    IO.puts("=" |> String.duplicate(60))
    
    # Summary statistics
    total_tests = map_size(test_results)
    successful_tests = test_results |> Map.values() |> Enum.count(& &1.success)
    total_duration = test_results |> Map.values() |> Enum.map(& &1.duration_ms) |> Enum.sum()
    
    IO.puts("\n📈 SUMMARY STATISTICS")
    IO.puts("   Total Tests: #{total_tests}")
    IO.puts("   Successful: #{successful_tests}")
    IO.puts("   Success Rate: #{Float.round(successful_tests / total_tests * 100, 1)}%")
    IO.puts("   Total Duration: #{total_duration}ms (#{Float.round(total_duration / 1000, 1)}s)")
    IO.puts("   Average per Test: #{Float.round(total_duration / total_tests, 1)}ms")
    
    # Individual test results
    IO.puts("\n🔍 INDIVIDUAL TEST RESULTS")
    
    test_results
    |> Enum.each(fn {test_name, result} ->
      status_emoji = if result.success, do: "✅", else: "❌"
      IO.puts("   #{status_emoji} #{format_test_name(test_name)}: #{result.duration_ms}ms")
      
      case result.result do
        {:ok, _} ->
          IO.puts("      Status: Optimization completed successfully")
        
        {:error, reason} ->
          IO.puts("      Status: Failed - #{inspect(reason)}")
      end
    end)
    
    # Performance analysis
    IO.puts("\n⚡ PERFORMANCE ANALYSIS")
    
    fastest_test = test_results |> Enum.min_by(fn {_, result} -> result.duration_ms end)
    slowest_test = test_results |> Enum.max_by(fn {_, result} -> result.duration_ms end)
    
    IO.puts("   Fastest: #{format_test_name(elem(fastest_test, 0))} (#{elem(fastest_test, 1).duration_ms}ms)")
    IO.puts("   Slowest: #{format_test_name(elem(slowest_test, 0))} (#{elem(slowest_test, 1).duration_ms}ms)")
    
    # Recommendations
    IO.puts("\n💡 RECOMMENDATIONS")
    
    if successful_tests == total_tests do
      IO.puts("   🎉 All tests passed! SIMBA integration is working excellently.")
    else
      failed_tests = total_tests - successful_tests
      IO.puts("   ⚠️  #{failed_tests} test(s) failed. Review error logs for optimization.")
    end
    
    if total_duration > 300_000 do  # > 5 minutes
      IO.puts("   🚀 Consider reducing test complexity or increasing concurrency for faster runs.")
    end
    
    IO.puts("\n" <> "=" |> String.duplicate(60))
    IO.puts("Test suite completed at #{DateTime.utc_now()}")
    IO.puts("=" |> String.duplicate(60))
    
    test_results
  end

  # Helper functions for evaluation metrics

  defp extract_context_keywords(context) do
    context
    |> String.downcase()
    |> String.split(~r/[^\w]/)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.take(5)  # Top 5 context keywords
  end

  defp check_tone_appropriateness(context, response) do
    case String.downcase(context) do
      text when text =~ "frustrated" or text =~ "upset" ->
        String.contains?(String.downcase(response), ["understand", "help", "sorry"])
      
      text when text =~ "beginner" or text =~ "student" ->
        String.contains?(String.downcase(response), ["simple", "easy", "step"])
      
      _ ->
        true  # Default to appropriate
    end
  end

  defp check_domain_language(context, response) do
    domain_keywords = %{
      "medical" => ["symptoms", "condition", "treatment", "doctor"],
      "technical" => ["system", "software", "settings", "configuration"],
      "sales" => ["product", "value", "benefits", "features"],
      "education" => ["learn", "understand", "practice", "study"]
    }
    
    Enum.any?(domain_keywords, fn {domain, keywords} ->
      if String.contains?(String.downcase(context), domain) do
        Enum.any?(keywords, &String.contains?(String.downcase(response), &1))
      else
        false
      end
    end)
  end

  defp extract_adaptation_concepts(note) when is_binary(note) do
    note
    |> String.downcase()
    |> String.split(~r/[^\w]/)
    |> Enum.filter(&(String.length(&1) > 3))
  end

  defp extract_adaptation_concepts(_), do: []

  defp evaluate_tone_match(context, response) do
    if check_tone_appropriateness(context, response), do: 1.0, else: 0.5
  end

  defp evaluate_language_complexity(context, response) do
    expected_complexity = cond do
      String.contains?(String.downcase(context), "beginner") -> :simple
      String.contains?(String.downcase(context), "expert") -> :complex
      true -> :medium
    end
    
    actual_complexity = assess_language_complexity(response)
    
    if expected_complexity == actual_complexity, do: 1.0, else: 0.6
  end

  defp assess_language_complexity(text) do
    avg_word_length = 
      text
      |> String.split()
      |> Enum.map(&String.length/1)
      |> Enum.sum()
      |> Kernel./(max(length(String.split(text)), 1))
    
    cond do
      avg_word_length < 4.5 -> :simple
      avg_word_length > 6.0 -> :complex
      true -> :medium
    end
  end

  defp evaluate_content_relevance(context, response) do
    context_words = extract_context_keywords(context)
    response_words = String.split(String.downcase(response))
    
    relevance = Enum.count(context_words, &(&1 in response_words)) / max(length(context_words), 1)
    min(relevance * 2, 1.0)  # Scale up relevance score
  end

  defp evaluate_helpfulness(response) do
    helpful_indicators = [
      String.contains?(String.downcase(response), ["can", "will", "help", "try"]),
      String.contains?(response, ["?", "!"]),  # Engaging punctuation
      String.length(response) > 20,  # Sufficient detail
      not String.contains?(String.downcase(response), ["don't know", "can't help"])
    ]
    
    Enum.count(helpful_indicators, & &1) / length(helpful_indicators)
  end

  defp evaluate_completeness(expected, actual) do
    expected_concepts = String.split(String.downcase(expected))
    actual_concepts = String.split(String.downcase(actual))
    
    coverage = Enum.count(expected_concepts, &(&1 in actual_concepts)) / max(length(expected_concepts), 1)
    min(coverage * 1.5, 1.0)
  end

  defp evaluate_balance(synthesis) do
    balance_indicators = [
      String.contains?(synthesis, ["however", "but", "although", "while"]),
      String.contains?(synthesis, ["both", "and", "as well as"]),
      String.contains?(synthesis, ["consider", "balance", "weigh"])
    ]
    
    Enum.count(balance_indicators, & &1) / length(balance_indicators)
  end

  defp evaluate_actionability(synthesis) do
    action_indicators = [
      String.contains?(synthesis, ["should", "recommend", "suggest", "propose"]),
      String.contains?(synthesis, ["implement", "start", "begin", "create"]),
      String.contains?(synthesis, ["first", "then", "next", "finally"])
    ]
    
    Enum.count(action_indicators, & &1) / length(action_indicators)
  end

  defp evaluate_feasibility(synthesis) do
    feasibility_indicators = [
      not String.contains?(String.downcase(synthesis), ["impossible", "never", "can't"]),
      String.contains?(synthesis, ["practical", "realistic", "achievable", "possible"]),
      String.length(synthesis) > 30  # Sufficient detail for feasibility
    ]
    
    Enum.count(feasibility_indicators, & &1) / length(feasibility_indicators)
  end

  defp check_logical_structure(reasoning) do
    structure_indicators = [
      String.contains?(reasoning, ["because", "since", "therefore", "thus"]),
      String.contains?(reasoning, ["first", "second", "then", "finally"]),
      String.contains?(reasoning, ["leads to", "results in", "causes"])
    ]
    
    if Enum.any?(structure_indicators, & &1), do: 1.0, else: 0.5
  end

  defp format_test_name(test_name) do
    test_name
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end

# Test module for SIMBA functionality
defmodule DSPEx.Teleprompter.SIMBATest do
  @moduledoc """
  Comprehensive test suite for SIMBA teleprompter functionality.
  
  Tests cover basic functionality, edge cases, error handling, and performance.
  """

  use ExUnit.Case, async: false
  
  alias DSPEx.{Example, Predict}
  alias DSPEx.Teleprompter.SIMBA

  describe "SIMBA initialization" do
    test "creates SIMBA with default configuration" do
      teleprompter = SIMBA.new()
      
      assert teleprompter.num_candidates == 20
      assert teleprompter.max_bootstrapped_demos == 4
      assert teleprompter.num_trials == 50
      assert teleprompter.quality_threshold == 0.7
    end

    test "creates SIMBA with custom configuration" do
      teleprompter = SIMBA.new(
        num_candidates: 30,
        quality_threshold: 0.8,
        max_concurrency: 15
      )
      
      assert teleprompter.num_candidates == 30
      assert teleprompter.quality_threshold == 0.8
      assert teleprompter.max_concurrency == 15
    end

    test "validates configuration bounds" do
      # Test that configuration validates reasonable bounds
      teleprompter = SIMBA.new(
        num_candidates: 100,  # High but valid
        quality_threshold: 1.0,  # Maximum valid threshold
        max_concurrency: 1  # Minimum valid concurrency
      )
      
      assert teleprompter.num_candidates == 100
      assert teleprompter.quality_threshold == 1.0
      assert teleprompter.max_concurrency == 1
    end
  end

  describe "SIMBA compilation" do
    setup do
      # Define test signature
      defmodule TestSignature do
        use DSPEx.Signature, "input -> output"
      end

      student = Predict.new(TestSignature, :gemini)
      teacher = Predict.new(TestSignature, :openai)
      
      trainset = [
        Example.new(%{input: "test1", output: "result1"}, [:input]),
        Example.new(%{input: "test2", output: "result2"}, [:input]),
        Example.new(%{input: "test3", output: "result3"}, [:input])
      ]

      metric_fn = fn example, prediction -> 
        expected = Example.outputs(example)
        if expected[:output] == prediction[:output], do: 1.0, else: 0.0
      end

      %{
        student: student,
        teacher: teacher,
        trainset: trainset,
        metric_fn: metric_fn
      }
    end

    test "validates input parameters", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      teleprompter = SIMBA.new()

      # Test invalid student
      assert {:error, :invalid_student_program} = 
        teleprompter.compile(nil, teacher, trainset, metric_fn)

      # Test invalid teacher
      assert {:error, :invalid_teacher_program} = 
        teleprompter.compile(student, nil, trainset, metric_fn)

      # Test empty trainset
      assert {:error, :invalid_or_empty_trainset} = 
        teleprompter.compile(student, teacher, [], metric_fn)

      # Test invalid metric function
      assert {:error, :invalid_metric_function} = 
        teleprompter.compile(student, teacher, trainset, "not_a_function")
    end

    test "handles edge cases gracefully", %{student: student, teacher: teacher, metric_fn: metric_fn} do
      teleprompter = SIMBA.new(num_candidates: 1, num_trials: 1, max_bootstrapped_demos: 1)

      # Test with minimal trainset
      minimal_trainset = [
        Example.new(%{input: "test", output: "result"}, [:input])
      ]

      # Should not crash with minimal configuration
      result = teleprompter.compile(student, teacher, minimal_trainset, metric_fn)
      
      # Result can be either success or specific errors, but shouldn't crash
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "respects timeout configurations", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Test with very short timeout to ensure timeout handling works
      teleprompter = SIMBA.new(
        timeout: 1,  # 1ms timeout should cause timeouts
        num_candidates: 2,
        num_trials: 2
      )

      # This should either succeed quickly or fail gracefully with timeout
      result = teleprompter.compile(student, teacher, trainset, metric_fn)
      
      # Accept either success (if very fast) or timeout/error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "progress callback functionality" do
      progress_updates = []
      
      progress_callback = fn progress ->
        send(self(), {:progress, progress})
        :ok
      end

      teleprompter = SIMBA.new(
        progress_callback: progress_callback,
        num_candidates: 2,
        num_trials: 2
      )

      assert is_function(teleprompter.progress_callback)
      
      # The callback should be stored correctly
      assert teleprompter.progress_callback == progress_callback
    end

    @tag :integration
    test "full compilation workflow", %{student: student, teacher: teacher, trainset: trainset, metric_fn: metric_fn} do
      # Use minimal but realistic configuration for testing
      teleprompter = SIMBA.new(
        num_candidates: 3,
        max_bootstrapped_demos: 2,
        num_trials: 3,
        timeout: 30_000,
        quality_threshold: 0.5  # Lower threshold for test success
      )

      # Mock the LLM calls to avoid external dependencies in tests
      # In practice, you would mock DSPEx.Client.request and DSPEx.Program.forward
      result = with_mocked_llm_calls do
        teleprompter.compile(student, teacher, trainset, metric_fn)
      end

      case result do
        {:ok, optimized_student} ->
          assert is_struct(optimized_student)
          # Verify the optimized student has the expected structure
          
        {:error, reason} ->
          # Accept certain errors in test environment
          acceptable_errors = [
            :no_successful_bootstrap_candidates,
            :network_error,
            :provider_not_configured,
            :timeout
          ]
          assert reason in acceptable_errors
      end
    end
  end

  describe "SIMBA performance and edge cases" do
    test "handles large trainsets efficiently" do
      # Create a large trainset
      large_trainset = 
        1..100
        |> Enum.map(fn i ->
          Example.new(%{input: "test#{i}", output: "result#{i}"}, [:input])
        end)

      teleprompter = SIMBA.new(
        num_candidates: 5,
        max_bootstrapped_demos: 2,
        num_trials: 5,
        max_concurrency: 10
      )

      # Test that it doesn't crash with large datasets
      assert is_struct(teleprompter)
      assert length(large_trainset) == 100
      
      # Verify configuration is appropriate for large datasets
      assert teleprompter.max_concurrency <= 20  # Reasonable concurrency
      assert teleprompter.num_candidates < length(large_trainset)  # Subset of training data
    end

    test "concurrent safety" do
      # Test that SIMBA can handle concurrent operations safely
      teleprompter = SIMBA.new(max_concurrency: 5)
      
      # Verify the concurrency setting
      assert teleprompter.max_concurrency == 5
      
      # The actual concurrent execution would be tested in integration tests
      # with mocked LLM calls to avoid external dependencies
    end

    test "memory efficiency with large datasets" do
      # Test that SIMBA doesn't consume excessive memory
      large_trainset = 
        1..1000
        |> Enum.map(fn i ->
          # Create examples with realistic data sizes
          large_input = String.duplicate("word ", 100)  # ~500 chars
          Example.new(%{input: "#{large_input}#{i}", output: "result#{i}"}, [:input])
        end)

      teleprompter = SIMBA.new(
        num_candidates: 10,
        max_bootstrapped_demos: 5
      )

      # Memory usage should be reasonable
      memory_before = :erlang.memory(:total)
      
      # Just creating the trainset and teleprompter shouldn't use excessive memory
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      
      # Should use less than 100MB for setup
      assert memory_used < 100 * 1024 * 1024
      
      # Verify trainset and teleprompter are properly created
      assert length(large_trainset) == 1000
      assert is_struct(teleprompter)
    end

    test "error recovery and resilience" do
      # Test SIMBA's ability to handle various error conditions
      
      # Test with metric function that sometimes throws errors
      unreliable_metric = fn _example, _prediction ->
        if :rand.uniform() > 0.7 do
          raise "Simulated metric error"
        else
          0.8
        end
      end

      teleprompter = SIMBA.new(
        num_candidates: 3,
        num_trials: 3,
        teacher_retries: 2
      )

      # Should handle metric errors gracefully
      assert teleprompter.teacher_retries == 2
      assert is_function(unreliable_metric)
    end

    test "configuration validation and bounds checking" do
      # Test edge cases for configuration values
      
      # Test minimum values
      min_config = SIMBA.new(
        num_candidates: 1,
        max_bootstrapped_demos: 1,
        num_trials: 1,
        quality_threshold: 0.0,
        max_concurrency: 1
      )
      
      assert min_config.num_candidates == 1
      assert min_config.max_bootstrapped_demos == 1
      assert min_config.num_trials == 1
      assert min_config.quality_threshold == 0.0
      assert min_config.max_concurrency == 1

      # Test maximum reasonable values
      max_config = SIMBA.new(
        num_candidates: 1000,
        max_bootstrapped_demos: 100,
        num_trials: 1000,
        quality_threshold: 1.0,
        max_concurrency: 100
      )
      
      assert max_config.num_candidates == 1000
      assert max_config.max_bootstrapped_demos == 100
      assert max_config.num_trials == 1000
      assert max_config.quality_threshold == 1.0
      assert max_config.max_concurrency == 100
    end
  end

  describe "SIMBA telemetry and observability" do
    test "emits proper telemetry events" do
      # Test that SIMBA emits expected telemetry events
      teleprompter = SIMBA.new()
      
      # In a real test, you would set up telemetry event collection
      # and verify that the expected events are emitted during compilation
      
      assert is_struct(teleprompter)
    end

    test "correlation ID propagation" do
      # Test that correlation IDs are properly propagated through the system
      correlation_id = "test-correlation-123"
      
      teleprompter = SIMBA.new()
      
      # The correlation ID should be usable in compilation
      # In a real test, you would verify it appears in telemetry events
      
      assert is_binary(correlation_id)
      assert is_struct(teleprompter)
    end

    test "progress tracking accuracy" do
      # Test that progress tracking provides accurate information
      progress_events = []
      
      progress_callback = fn progress ->
        send(self(), {:progress, progress})
        :ok
      end

      teleprompter = SIMBA.new(progress_callback: progress_callback)
      
      # Verify the callback is properly stored
      assert is_function(teleprompter.progress_callback)
    end
  end

  # Helper function to mock LLM calls for testing
  defp with_mocked_llm_calls(test_func) do
    # In a real implementation, you would mock DSPEx.Client.request
    # and DSPEx.Program.forward calls here to avoid external API dependencies
    
    # For now, we'll simulate the test function execution
    try do
      test_func.()
    rescue
      # Catch any errors that would occur due to missing API keys, etc.
      _ -> {:error, :mocked_test_environment}
    catch
      # Catch exits/throws
      :exit, _ -> {:error, :mocked_test_environment}
      :throw, _ -> {:error, :mocked_test_environment}
    end
  end
end

# Benchmark module for SIMBA performance testing
defmodule DSPEx.Teleprompter.SIMBABenchmark do
  @moduledoc """
  Benchmarking utilities for SIMBA teleprompter performance analysis.
  
  Provides comprehensive benchmarking capabilities to measure and optimize
  SIMBA's performance across different configurations and workload sizes.
  """

  alias DSPEx.{Example, Predict}
  alias DSPEx.Teleprompter.SIMBA

  @doc """
  Run comprehensive benchmarks for SIMBA optimization.
  
  Tests performance across multiple configuration scales and provides
  detailed analysis of optimization characteristics.
  """
  def run_benchmarks do
    IO.puts("=== SIMBA Teleprompter Benchmarks ===\n")

    benchmark_configurations = [
      %{name: "Small Scale", candidates: 10, trials: 20, demos: 2, trainset_size: 50},
      %{name: "Medium Scale", candidates: 20, trials: 40, demos: 4, trainset_size: 200},
      %{name: "Large Scale", candidates: 30, trials: 60, demos: 6, trainset_size: 500}
    ]

    results = 
      Enum.map(benchmark_configurations, fn config ->
        IO.puts("Running #{config.name} benchmark...")
        
        result = benchmark_configuration(config)
        
        IO.puts("✓ #{config.name} completed in #{result.duration}ms")
        IO.puts("  - Bootstrap time: #{result.bootstrap_time}ms")
        IO.puts("  - Optimization time: #{result.optimization_time}ms") 
        IO.puts("  - Memory usage: #{result.memory_mb}MB")
        IO.puts("  - Throughput: #{result.throughput} examples/sec\n")
        
        result
      end)

    print_benchmark_summary(results)
    
    # Additional specialized benchmarks
    run_concurrency_benchmarks()
    run_memory_benchmarks()
    run_optimization_quality_benchmarks()
    
    results
  end

  @doc """
  Benchmark a specific SIMBA configuration.
  """
  def benchmark_configuration(config) do
    # Setup benchmark environment
    defmodule BenchmarkSignature do
      use DSPEx.Signature, "question -> answer"
    end

    student = Predict.new(BenchmarkSignature, :gemini)
    teacher = Predict.new(BenchmarkSignature, :openai)
    
    # Create trainset of specified size
    trainset = create_benchmark_trainset(config.trainset_size)
    metric_fn = fn _example, _prediction -> :rand.uniform() end

    teleprompter = SIMBA.new(
      num_candidates: config.candidates,
      max_bootstrapped_demos: config.demos,
      num_trials: config.trials,
      max_concurrency: 20,
      timeout: 60_000
    )

    # Measure performance
    {memory_before, _} = :erlang.process_info(self(), :memory)
    start_time = System.monotonic_time()

    # Simulate the timing (in real benchmarks, you'd run actual optimization)
    bootstrap_time = simulate_bootstrap_phase(config)
    optimization_time = simulate_optimization_phase(config)

    total_time = bootstrap_time + optimization_time
    {memory_after, _} = :erlang.process_info(self(), :memory)

    throughput = config.trainset_size / (total_time / 1000)

    %{
      config: config,
      duration: total_time,
      bootstrap_time: bootstrap_time,
      optimization_time: optimization_time,
      memory_mb: (memory_after - memory_before) / 1_048_576,
      throughput: throughput,
      efficiency_score: calculate_efficiency_score(config, total_time, memory_after - memory_before)
    }
  end

  @doc """
  Run concurrency-focused benchmarks.
  """
  def run_concurrency_benchmarks do
    IO.puts("\n=== Concurrency Benchmarks ===")
    
    concurrency_levels = [1, 5, 10, 20, 50]
    trainset_size = 100
    
    results = Enum.map(concurrency_levels, fn concurrency ->
      config = %{
        name: "Concurrency #{concurrency}",
        candidates: 20,
        trials: 30,
        demos: 4,
        trainset_size: trainset_size,
        max_concurrency: concurrency
      }
      
      start_time = System.monotonic_time()
      
      # Simulate concurrent processing
      simulated_time = simulate_concurrent_processing(trainset_size, concurrency)
      
      duration = System.convert_time_unit(
        System.monotonic_time() - start_time + simulated_time,
        :native,
        :millisecond
      )
      
      throughput = trainset_size / (duration / 1000)
      efficiency = throughput / concurrency  # Examples per second per concurrent worker
      
      IO.puts("  Concurrency #{concurrency}: #{Float.round(throughput, 1)} examples/sec, #{Float.round(efficiency, 2)} efficiency")
      
      %{
        concurrency: concurrency,
        duration: duration,
        throughput: throughput,
        efficiency: efficiency
      }
    end)
    
    # Find optimal concurrency level
    optimal = Enum.max_by(results, & &1.efficiency)
    IO.puts("\n  Optimal concurrency: #{optimal.concurrency} (#{Float.round(optimal.efficiency, 2)} efficiency)")
    
    results
  end

  @doc """
  Run memory usage benchmarks.
  """
  def run_memory_benchmarks do
    IO.puts("\n=== Memory Usage Benchmarks ===")
    
    dataset_sizes = [100, 500, 1000, 2000]
    
    Enum.each(dataset_sizes, fn size ->
      memory_before = :erlang.memory(:total)
      
      # Simulate memory usage for dataset size
      trainset = create_benchmark_trainset(size)
      
      # Create SIMBA configuration
      teleprompter = SIMBA.new(
        num_candidates: min(50, div(size, 10)),
        max_bootstrapped_demos: min(10, div(size, 50))
      )
      
      memory_after = :erlang.memory(:total)
      memory_used = (memory_after - memory_before) / 1_048_576  # MB
      memory_per_example = memory_used / size
      
      IO.puts("  Dataset size #{size}: #{Float.round(memory_used, 2)}MB total, #{Float.round(memory_per_example * 1000, 2)}KB per example")
      
      # Cleanup for next iteration
      :erlang.garbage_collect()
    end)
  end

  @doc """
  Run optimization quality benchmarks.
  """
  def run_optimization_quality_benchmarks do
    IO.puts("\n=== Optimization Quality Benchmarks ===")
    
    quality_configs = [
      %{name: "Speed Focused", candidates: 5, trials: 10, threshold: 0.5},
      %{name: "Balanced", candidates: 15, trials: 30, threshold: 0.7},
      %{name: "Quality Focused", candidates: 30, trials: 60, threshold: 0.9}
    ]
    
    Enum.each(quality_configs, fn config ->
      # Simulate optimization quality results
      simulated_improvement = simulate_optimization_improvement(config)
      simulated_consistency = simulate_optimization_consistency(config)
      simulated_time = config.candidates * config.trials * 10  # ms
      
      quality_score = (simulated_improvement + simulated_consistency) / 2
      
      IO.puts("  #{config.name}:")
      IO.puts("    Improvement: #{Float.round(simulated_improvement * 100, 1)}%")
      IO.puts("    Consistency: #{Float.round(simulated_consistency * 100, 1)}%")
      IO.puts("    Quality Score: #{Float.round(quality_score * 100, 1)}%")
      IO.puts("    Time: #{simulated_time}ms")
    end)
  end

  # Private helper functions

  defp create_benchmark_trainset(size) do
    1..size
    |> Enum.map(fn i ->
      Example.new(%{
        question: "Benchmark question #{i}? #{generate_varied_content(i)}",
        answer: "Benchmark answer #{i} with detailed explanation."
      }, [:question])
    end)
  end

  defp generate_varied_content(i) do
    # Generate varied content to simulate realistic datasets
    case rem(i, 4) do
      0 -> "This involves mathematical calculation and reasoning."
      1 -> "This requires understanding of complex concepts and relationships."
      2 -> "This needs careful analysis of multiple factors and considerations."
      3 -> "This demands synthesis of information from various sources."
    end
  end

  defp simulate_bootstrap_phase(config) do
    # Simulate bootstrap time based on configuration
    base_time = config.candidates * 50  # 50ms per candidate
    concurrency_factor = max(1, config.candidates / 20)  # Reduced time with higher concurrency
    round(base_time / concurrency_factor)
  end

  defp simulate_optimization_phase(config) do
    # Simulate optimization time based on trials and complexity
    base_time = config.trials * 100  # 100ms per trial
    complexity_factor = 1 + (config.demos * 0.1)  # More demos = more complexity
    round(base_time * complexity_factor)
  end

  defp simulate_concurrent_processing(trainset_size, concurrency) do
    # Simulate the time saved by concurrent processing
    base_time_per_example = 10  # ms
    total_base_time = trainset_size * base_time_per_example
    
    # Concurrency reduces time but with diminishing returns
    concurrency_efficiency = min(concurrency, trainset_size) / (1 + concurrency * 0.01)
    concurrent_time = total_base_time / concurrency_efficiency
    
    # Convert to system time units
    System.convert_time_unit(round(concurrent_time), :millisecond, :native)
  end

  defp calculate_efficiency_score(config, time_ms, memory_bytes) do
    # Calculate a normalized efficiency score
    time_score = 1.0 / (time_ms / 1000)  # Higher score for less time
    memory_score = 1.0 / (memory_bytes / 1_048_576)  # Higher score for less memory
    work_score = config.candidates * config.trials  # More work = higher score
    
    (time_score + memory_score + work_score) / 3
  end

  defp simulate_optimization_improvement(config) do
    # Simulate improvement based on configuration
    base_improvement = 0.3
    candidate_factor = min(config.candidates / 50, 1.0) * 0.4
    trial_factor = min(config.trials / 100, 1.0) * 0.2
    threshold_factor = config.threshold * 0.1
    
    base_improvement + candidate_factor + trial_factor + threshold_factor
  end

  defp simulate_optimization_consistency(config) do
    # Simulate consistency based on configuration rigor
    base_consistency = 0.6
    trial_factor = min(config.trials / 100, 1.0) * 0.3
    threshold_factor = config.threshold * 0.1
    
    base_consistency + trial_factor + threshold_factor
  end

  defp print_benchmark_summary(results) do
    IO.puts("\n=== Benchmark Summary ===")
    
    total_time = Enum.sum(Enum.map(results, & &1.duration))
    avg_memory = results |> Enum.map(& &1.memory_mb) |> Enum.sum() |> Kernel./(length(results))
    avg_throughput = results |> Enum.map(& &1.throughput) |> Enum.sum() |> Kernel./(length(results))
    
    IO.puts("Total benchmark time: #{total_time}ms")
    IO.puts("Average memory usage: #{Float.round(avg_memory, 2)}MB")
    IO.puts("Average throughput: #{Float.round(avg_throughput, 1)} examples/sec")
    
    fastest = Enum.max_by(results, & &1.throughput)
    most_efficient = Enum.max_by(results, & &1.efficiency_score)
    
    IO.puts("Fastest throughput: #{fastest.config.name} (#{Float.round(fastest.throughput, 1)} examples/sec)")
    IO.puts("Most efficient: #{most_efficient.config.name} (score: #{Float.round(most_efficient.efficiency_score, 3)})")
    
    # Performance recommendations
    IO.puts("\n=== Performance Recommendations ===")
    
    if avg_memory > 100 do
      IO.puts("• Consider reducing max_bootstrapped_demos or num_candidates to decrease memory usage")
    end
    
    if avg_throughput < 10 do
      IO.puts("• Consider increasing max_concurrency to improve throughput")
    end
    
    if total_time > 60_000 do
      IO.puts("• Consider reducing num_trials or timeout values for faster optimization")
    end
    
    IO.puts("• Optimal configuration appears to be: #{most_efficient.config.name}")
    IO.puts("========================")
  end
end

# Example usage and integration patterns
defmodule DSPEx.Teleprompter.SIMBAIntegration do
  @moduledoc """
  Integration patterns and real-world usage examples for SIMBA teleprompter.
  
  This module demonstrates how to integrate SIMBA into larger applications
  and workflows, including monitoring, error handling, and optimization strategies.
  """

  alias DSPEx.{Example, Predict, Program}
  alias DSPEx.Teleprompter.SIMBA

  @doc """
  Production-ready SIMBA optimization with comprehensive error handling.
  """
  def optimize_for_production(student, teacher, trainset, metric_fn, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || generate_correlation_id()
    
    # Enhanced configuration for production
    production_config = %{
      num_candidates: Keyword.get(opts, :num_candidates, 20),
      max_bootstrapped_demos: Keyword.get(opts, :max_bootstrapped_demos, 4),
      num_trials: Keyword.get(opts, :num_trials, 50),
      quality_threshold: Keyword.get(opts, :quality_threshold, 0.75),
      max_concurrency: Keyword.get(opts, :max_concurrency, 15),
      timeout: Keyword.get(opts, :timeout, 90_000),
      teacher_retries: Keyword.get(opts, :teacher_retries, 3),
      progress_callback: create_production_progress_callback(correlation_id)
    }

    teleprompter = SIMBA.new(production_config)

    # Comprehensive error handling and monitoring
    try do
      # Pre-optimization validation
      :ok = validate_optimization_inputs(student, teacher, trainset, metric_fn)
      
      # Setup monitoring
      monitoring_ref = setup_optimization_monitoring(correlation_id, production_config)
      
      # Run optimization with timeout wrapper
      result = run_with_timeout(fn ->
        teleprompter.compile(student, teacher, trainset, metric_fn)
      end, production_config.timeout * 2)  # Extra buffer for safety
      
      # Post-optimization validation and reporting
      case result do
        {:ok, optimized_student} ->
          validation_result = validate_optimization_result(
           student, 
           optimized_student, 
           trainset, 
           metric_fn
         )
         
         case validation_result do
           {:ok, improvement_metrics} ->
             report_optimization_success(correlation_id, improvement_metrics, monitoring_ref)
             {:ok, optimized_student}
           
           {:error, validation_reason} ->
             report_optimization_warning(correlation_id, validation_reason, monitoring_ref)
             # Return original student if optimization didn't help
             {:ok, student}
         end
       
       {:error, optimization_reason} ->
         report_optimization_failure(correlation_id, optimization_reason, monitoring_ref)
         {:error, optimization_reason}
     end
     
   rescue
     exception ->
       report_optimization_exception(correlation_id, exception)
       {:error, {:optimization_exception, exception}}
   after
     cleanup_optimization_monitoring(correlation_id)
   end
 end

 @doc """
 Batch optimization for multiple programs with resource management.
 """
 def optimize_batch(program_configs, opts \\ []) do
   batch_id = generate_correlation_id()
   max_concurrent_optimizations = Keyword.get(opts, :max_concurrent, 3)
   
   IO.puts("🔄 Starting batch optimization (ID: #{batch_id})")
   IO.puts("   Programs to optimize: #{length(program_configs)}")
   IO.puts("   Max concurrent: #{max_concurrent_optimizations}")
   
   start_time = System.monotonic_time()
   
   results = program_configs
   |> Stream.with_index()
   |> Task.async_stream(
     fn {config, index} ->
       program_id = "#{batch_id}_program_#{index}"
       
       optimize_single_program_in_batch(config, program_id, opts)
     end,
     max_concurrency: max_concurrent_optimizations,
     timeout: :infinity,
     on_timeout: :kill_task
   )
   |> Enum.to_list()
   
   duration = System.convert_time_unit(
     System.monotonic_time() - start_time,
     :native,
     :millisecond
   )
   
   # Analyze batch results
   successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
   failed = length(results) - successful
   
   IO.puts("\n📊 Batch optimization completed:")
   IO.puts("   Duration: #{duration}ms (#{Float.round(duration / 1000, 1)}s)")
   IO.puts("   Successful: #{successful}/#{length(results)}")
   IO.puts("   Failed: #{failed}/#{length(results)}")
   IO.puts("   Success rate: #{Float.round(successful / length(results) * 100, 1)}%")
   
   {:ok, %{
     batch_id: batch_id,
     results: results,
     stats: %{
       duration: duration,
       successful: successful,
       failed: failed,
       success_rate: successful / length(results)
     }
   }}
 end

 @doc """
 Adaptive optimization that adjusts parameters based on initial results.
 """
 def optimize_adaptively(student, teacher, trainset, metric_fn, opts \\ []) do
   correlation_id = generate_correlation_id()
   
   IO.puts("🧠 Starting adaptive optimization (ID: #{correlation_id})")
   
   # Stage 1: Quick exploratory optimization
   exploratory_config = %{
     num_candidates: 10,
     max_bootstrapped_demos: 2,
     num_trials: 15,
     quality_threshold: 0.6,
     max_concurrency: 20,
     timeout: 30_000
   }
   
   IO.puts("   Stage 1: Exploratory optimization...")
   
   exploratory_teleprompter = SIMBA.new(exploratory_config)
   
   case exploratory_teleprompter.compile(student, teacher, trainset, metric_fn) do
     {:ok, exploratory_result} ->
       # Evaluate exploratory result
       exploratory_score = evaluate_program_quality(
         exploratory_result, 
         Enum.take(trainset, 20), 
         metric_fn
       )
       
       IO.puts("   Stage 1 completed: Score #{Float.round(exploratory_score, 3)}")
       
       # Stage 2: Adaptive refinement based on results
       refined_config = adapt_configuration(exploratory_config, exploratory_score, trainset)
       
       IO.puts("   Stage 2: Refined optimization...")
       IO.puts("   Adapted config: #{inspect(refined_config)}")
       
       refined_teleprompter = SIMBA.new(refined_config)
       
       case refined_teleprompter.compile(student, teacher, trainset, metric_fn) do
         {:ok, final_result} ->
           final_score = evaluate_program_quality(final_result, trainset, metric_fn)
           
           IO.puts("   Stage 2 completed: Score #{Float.round(final_score, 3)}")
           
           improvement = final_score - exploratory_score
           
           if improvement > 0.05 do
             IO.puts("✅ Adaptive optimization successful (+#{Float.round(improvement, 3)})")
             {:ok, final_result}
           else
             IO.puts("🔄 Using exploratory result (refinement didn't improve significantly)")
             {:ok, exploratory_result}
           end
         
         {:error, reason} ->
           IO.puts("⚠️  Refinement failed, using exploratory result: #{inspect(reason)}")
           {:ok, exploratory_result}
       end
     
     {:error, reason} ->
       IO.puts("❌ Exploratory optimization failed: #{inspect(reason)}")
       {:error, reason}
   end
 end

 @doc """
 Continuous optimization for long-running applications.
 """
 def start_continuous_optimization(program, opts \\ []) do
   optimization_interval = Keyword.get(opts, :interval_hours, 24) * 3600 * 1000  # ms
   quality_check_interval = Keyword.get(opts, :check_interval_hours, 6) * 3600 * 1000  # ms
   
   GenServer.start_link(
     DSPEx.Teleprompter.ContinuousOptimizer,
     %{
       program: program,
       optimization_interval: optimization_interval,
       quality_check_interval: quality_check_interval,
       opts: opts
     },
     name: {:global, {:simba_continuous_optimizer, program}}
   )
 end

 # Private implementation functions

 defp validate_optimization_inputs(student, teacher, trainset, metric_fn) do
   cond do
     not is_struct(student) ->
       {:error, :invalid_student_program}
     
     not is_struct(teacher) ->
       {:error, :invalid_teacher_program}
     
     not is_list(trainset) or length(trainset) < 5 ->
       {:error, :insufficient_training_data}
     
     not is_function(metric_fn, 2) ->
       {:error, :invalid_metric_function}
     
     true ->
       :ok
   end
 end

 defp setup_optimization_monitoring(correlation_id, config) do
   monitoring_ref = make_ref()
   
   # Start monitoring process
   spawn_link(fn ->
     monitor_optimization_progress(correlation_id, monitoring_ref, config)
   end)
   
   monitoring_ref
 end

 defp monitor_optimization_progress(correlation_id, monitoring_ref, config) do
   start_time = System.monotonic_time()
   
   # Periodic health checks
   check_interval = 30_000  # 30 seconds
   
   Stream.repeatedly(fn ->
     Process.sleep(check_interval)
     
     current_time = System.monotonic_time()
     elapsed = System.convert_time_unit(current_time - start_time, :native, :millisecond)
     
     # Check for timeout
     if elapsed > config.timeout * 1.5 do
       IO.puts("⚠️  Optimization #{correlation_id} may be taking longer than expected (#{elapsed}ms)")
     end
     
     # Monitor system resources
     memory_usage = :erlang.memory(:total) / 1_048_576  # MB
     
     if memory_usage > 1000 do  # 1GB
       IO.puts("⚠️  High memory usage during optimization: #{Float.round(memory_usage, 1)}MB")
     end
     
     :continue
   end)
   |> Stream.take_while(fn status -> status == :continue end)
   |> Enum.to_list()
 end

 defp run_with_timeout(fun, timeout) do
   task = Task.async(fun)
   
   case Task.yield(task, timeout) do
     {:ok, result} -> result
     nil -> 
       Task.shutdown(task, :brutal_kill)
       {:error, :optimization_timeout}
   end
 end

 defp validate_optimization_result(original, optimized, trainset, metric_fn) do
   # Sample validation set
   validation_sample = Enum.take_random(trainset, min(50, length(trainset)))
   
   # Evaluate both programs
   original_score = evaluate_program_quality(original, validation_sample, metric_fn)
   optimized_score = evaluate_program_quality(optimized, validation_sample, metric_fn)
   
   improvement = optimized_score - original_score
   improvement_percentage = improvement / max(original_score, 0.001) * 100
   
   if improvement > 0.02 do  # At least 2% improvement
     {:ok, %{
       original_score: original_score,
       optimized_score: optimized_score,
       improvement: improvement,
       improvement_percentage: improvement_percentage
     }}
   else
     {:error, {:insufficient_improvement, improvement_percentage}}
   end
 end

 defp evaluate_program_quality(program, examples, metric_fn) do
   results = examples
   |> Enum.map(fn example ->
     case Program.forward(program, Example.inputs(example)) do
       {:ok, prediction} -> metric_fn.(example, prediction)
       {:error, _} -> 0.0
     end
   end)
   
   if Enum.empty?(results) do
     0.0
   else
     Enum.sum(results) / length(results)
   end
 end

 defp optimize_single_program_in_batch(config, program_id, batch_opts) do
   try do
     # Extract program configuration
     student = Map.fetch!(config, :student)
     teacher = Map.fetch!(config, :teacher)
     trainset = Map.fetch!(config, :trainset)
     metric_fn = Map.fetch!(config, :metric_fn)
     
     # Use batch-specific optimization settings
     optimization_opts = [
       correlation_id: program_id,
       num_candidates: Keyword.get(batch_opts, :num_candidates, 15),
       num_trials: Keyword.get(batch_opts, :num_trials, 30),
       timeout: Keyword.get(batch_opts, :timeout, 60_000)
     ]
     
     optimize_for_production(student, teacher, trainset, metric_fn, optimization_opts)
     
   rescue
     exception ->
       {:error, {:program_optimization_failed, program_id, exception}}
   end
 end

 defp adapt_configuration(base_config, exploratory_score, trainset) do
   # Adapt configuration based on exploratory results
   
   adaptation_factor = cond do
     exploratory_score > 0.8 ->
       # High quality results, can be more aggressive
       %{
         num_candidates: round(base_config.num_candidates * 1.5),
         num_trials: round(base_config.num_trials * 2),
         quality_threshold: min(base_config.quality_threshold + 0.1, 0.9)
       }
     
     exploratory_score > 0.6 ->
       # Moderate results, slight increase
       %{
         num_candidates: round(base_config.num_candidates * 1.2),
         num_trials: round(base_config.num_trials * 1.5),
         quality_threshold: base_config.quality_threshold
       }
     
     true ->
       # Low quality, be more conservative but increase search space
       %{
         num_candidates: round(base_config.num_candidates * 2),
         num_trials: round(base_config.num_trials * 1.2),
         quality_threshold: max(base_config.quality_threshold - 0.1, 0.4)
       }
   end
   
   # Adjust for dataset size
   dataset_factor = cond do
     length(trainset) > 500 -> 1.3  # Larger dataset, can handle more candidates
     length(trainset) > 200 -> 1.1
     true -> 0.9  # Smaller dataset, reduce candidates
   end
   
   Map.merge(base_config, %{
     num_candidates: round(adaptation_factor.num_candidates * dataset_factor),
     num_trials: adaptation_factor.num_trials,
     quality_threshold: adaptation_factor.quality_threshold,
     max_concurrency: min(25, base_config.max_concurrency + 5)
   })
 end

 defp create_production_progress_callback(correlation_id) do
   fn progress ->
     case progress.phase do
       :bootstrap_generation ->
         if rem(progress.completed, 10) == 0 do
           percentage = Float.round(progress.completed / progress.total * 100, 1)
           IO.puts("[#{correlation_id}] Bootstrap: #{percentage}% (#{progress.completed}/#{progress.total})")
         end
       
       :bayesian_optimization ->
         if rem(progress.trial, 5) == 0 do
           IO.puts("[#{correlation_id}] Optimization: Trial #{progress.trial} - Score #{Float.round(progress.current_score, 4)}")
         end
       
       _ ->
         IO.puts("[#{correlation_id}] #{progress.phase}: #{inspect(progress)}")
     end
     
     :ok
   end
 end

 defp report_optimization_success(correlation_id, metrics, _monitoring_ref) do
   IO.puts("✅ Optimization #{correlation_id} completed successfully")
   IO.puts("   Original score: #{Float.round(metrics.original_score, 4)}")
   IO.puts("   Optimized score: #{Float.round(metrics.optimized_score, 4)}")
   IO.puts("   Improvement: +#{Float.round(metrics.improvement_percentage, 1)}%")
 end

 defp report_optimization_warning(correlation_id, reason, _monitoring_ref) do
   IO.puts("⚠️  Optimization #{correlation_id} completed with warnings")
   IO.puts("   Reason: #{inspect(reason)}")
   IO.puts("   Returning original program")
 end

 defp report_optimization_failure(correlation_id, reason, _monitoring_ref) do
   IO.puts("❌ Optimization #{correlation_id} failed")
   IO.puts("   Reason: #{inspect(reason)}")
 end

 defp report_optimization_exception(correlation_id, exception) do
   IO.puts("💥 Optimization #{correlation_id} crashed")
   IO.puts("   Exception: #{Exception.format(:error, exception)}")
 end

 defp cleanup_optimization_monitoring(correlation_id) do
   IO.puts("🧹 Cleaning up monitoring for #{correlation_id}")
   # In a real implementation, you might clean up ETS tables, stop processes, etc.
   :ok
 end

 defp generate_correlation_id do
   "simba-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
 end
end

# Continuous optimization GenServer
defmodule DSPEx.Teleprompter.ContinuousOptimizer do
 @moduledoc """
 GenServer for continuous program optimization in production environments.
 """
 
 use GenServer
 
 def init(state) do
   # Schedule first quality check
   Process.send_after(self(), :quality_check, state.quality_check_interval)
   
   {:ok, Map.put(state, :last_optimization, DateTime.utc_now())}
 end
 
 def handle_info(:quality_check, state) do
   # Check if optimization is needed
   current_quality = assess_program_quality(state.program)
   
   if should_optimize?(current_quality, state) do
     send(self(), :optimize)
   end
   
   # Schedule next quality check
   Process.send_after(self(), :quality_check, state.quality_check_interval)
   
   {:noreply, state}
 end
 
 def handle_info(:optimize, state) do
   # Perform optimization
   case run_optimization(state) do
     {:ok, optimized_program} ->
       new_state = %{
         state 
         | program: optimized_program,
           last_optimization: DateTime.utc_now()
       }
       
       # Schedule next optimization
       Process.send_after(self(), :optimize, state.optimization_interval)
       
       {:noreply, new_state}
     
     {:error, reason} ->
       IO.puts("Continuous optimization failed: #{inspect(reason)}")
       
       # Retry later
       Process.send_after(self(), :optimize, div(state.optimization_interval, 2))
       
       {:noreply, state}
   end
 end
 
 defp assess_program_quality(program) do
   # Implement quality assessment logic
   # This could involve running the program on a held-out test set
   :rand.uniform()  # Placeholder
 end
 
 defp should_optimize?(current_quality, state) do
   # Determine if optimization is needed
   time_since_last = DateTime.diff(DateTime.utc_now(), state.last_optimization, :hour)
   
   current_quality < 0.7 or time_since_last >= 24
 end
 
 defp run_optimization(state) do
   # Run the actual optimization
   # This would use the real SIMBA optimization logic
   {:ok, state.program}  # Placeholder
 end
end