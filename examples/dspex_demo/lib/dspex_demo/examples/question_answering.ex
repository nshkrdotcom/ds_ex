defmodule DspexDemo.Examples.QuestionAnswering do
  @moduledoc """
  Demonstrates DSPEx + BEACON for question answering optimization.
  """
  
  alias DSPEx.{Example, Predict, Program}
  alias DSPEx.Teleprompter.BEACON
  alias DspexDemo.Signatures.QASignature
  
  def run_demo do
    # Pre-load signature module to ensure function_exported? works correctly
    QASignature.input_fields()
    
    IO.puts """
    
    🎯 DSPEx + BEACON Question Answering Demo
    ==========================================
    
    This demo shows how BEACON optimizes a question-answering program
    by finding the best instruction and demonstration combinations.
    
    """
    
    # Create student and teacher programs
    student = Predict.new(QASignature, :gemini)
    teacher = Predict.new(QASignature, :gemini)
    
    IO.puts "📚 Creating training dataset..."
    
    # Create training examples
    trainset = [
      Example.new(%{
        question: "What is the capital of France?",
        answer: "Paris",
        reasoning: "Paris is the capital and largest city of France, located in the north-central part of the country.",
        confidence: "high"
      }, [:question]),
      
      Example.new(%{
        question: "What is 25% of 80?",
        answer: "20",
        reasoning: "25% means 25/100 or 0.25. To calculate: 80 × 0.25 = 20.",
        confidence: "high"
      }, [:question]),
      
      Example.new(%{
        question: "Who invented the telephone?",
        answer: "Alexander Graham Bell",
        reasoning: "Alexander Graham Bell is credited with inventing the first practical telephone in 1876.",
        confidence: "high"
      }, [:question]),
      
      Example.new(%{
        question: "What is the largest planet in our solar system?",
        answer: "Jupiter",
        reasoning: "Jupiter is the largest planet in our solar system, with a mass greater than all other planets combined.",
        confidence: "high"
      }, [:question]),
      
      Example.new(%{
        question: "In which year did World War II end?",
        answer: "1945",
        reasoning: "World War II ended in 1945 with the surrender of Japan in September following the atomic bombings.",
        confidence: "high"
      }, [:question])
    ]
    
    IO.puts "✅ Created #{length(trainset)} training examples"
    
    # Define evaluation metric
    metric_fn = fn example, prediction ->
      # Multi-factor scoring
      answer_score = if example.data.answer == Map.get(prediction, :answer), do: 0.6, else: 0.0
      reasoning_score = if String.length(Map.get(prediction, :reasoning, "") || "") > 10, do: 0.3, else: 0.0
      confidence_score = if Map.get(prediction, :confidence) in ["high", "medium", "low"], do: 0.1, else: 0.0
      
      answer_score + reasoning_score + confidence_score
    end
    
    IO.puts """
    
    🧠 Testing baseline student performance...
    """
    
    # Test baseline performance
    test_question = %{question: "What is the chemical symbol for gold?"}
    
    case Program.forward(student, test_question) do
      {:ok, baseline_result} ->
        IO.puts "Baseline Answer: #{Map.get(baseline_result, :answer, "N/A")}"
        IO.puts "Baseline Reasoning: #{Map.get(baseline_result, :reasoning, "N/A")}"
        IO.puts "Baseline Confidence: #{Map.get(baseline_result, :confidence, "N/A")}"
        
        IO.puts """
        
        🚀 Starting BEACON optimization...
    This will:
    1. Generate instruction candidates using the teacher model
    2. Bootstrap demonstration examples
    3. Use Bayesian optimization to find the best combination
    4. Return an optimized student program
    
    """
    
    # Create BEACON teleprompter
    teleprompter = BEACON.new(
      num_candidates: 8,           # Generate 8 instruction candidates
      max_bootstrapped_demos: 3,   # Use up to 3 demonstrations
      num_trials: 20,              # Run 20 optimization trials
      quality_threshold: 0.7,      # Require 70% quality for demos
      max_concurrency: 5,          # Use 5 concurrent workers
      timeout: 90_000              # 90 second timeout
    )
    
    # Add progress callback
    progress_callback = fn progress ->
      case progress.phase do
        :bootstrap_generation ->
          IO.write("📝 Generating demos: #{progress.completed}/#{progress.total}\r")
        :demonstration_evaluation ->
          IO.write("🔍 Evaluating demos: #{progress.completed}/#{progress.total}\r")
        :demonstration_selection ->
          IO.puts("\n✅ Selected #{progress.selected_count} quality demonstrations")
        _ ->
          :ok
      end
    end
    
    teleprompter_with_progress = %{teleprompter | progress_callback: progress_callback}
    
    # Run BEACON optimization
    case BEACON.compile(teleprompter_with_progress, student, teacher, trainset, metric_fn, []) do
      {:ok, optimized_student} ->
        IO.puts """
        
        ✨ BEACON optimization completed successfully!
        
        🧪 Testing optimized student performance...
        """
        
        # Test optimized performance
        case Program.forward(optimized_student, test_question) do
          {:ok, optimized_result} ->
            IO.puts """
            
            📊 RESULTS COMPARISON
            =====================
            
            BASELINE STUDENT:
            Answer: #{Map.get(baseline_result, :answer, "N/A")}
            Reasoning: #{Map.get(baseline_result, :reasoning, "N/A")}
            Confidence: #{Map.get(baseline_result, :confidence, "N/A")}
            
            OPTIMIZED STUDENT:
            Answer: #{Map.get(optimized_result, :answer, "N/A")}
            Reasoning: #{Map.get(optimized_result, :reasoning, "N/A")}
            Confidence: #{Map.get(optimized_result, :confidence, "N/A")}
            
            🎉 Optimization complete! The BEACON-optimized program should show
            improved reasoning quality and more structured responses.
            """
            
            {:ok, %{
              baseline: baseline_result,
              optimized: optimized_result,
              program: optimized_student
            }}
            
          {:error, reason} ->
            IO.puts "❌ Optimized test failed: #{inspect(reason)}"
            {:error, :optimized_test_failed}
        end
        
      {:error, reason} ->
        IO.puts """
        
        📊 QUESTION ANSWERING RESULTS (Baseline Only)
        ===============================================
        
        Question: "#{test_question.question}"
        
        BASELINE:
        Answer: #{Map.get(baseline_result, :answer, "N/A")}
        Reasoning: #{Map.get(baseline_result, :reasoning, "N/A")}
        Confidence: #{Map.get(baseline_result, :confidence, "N/A")}
        
        ❌ BEACON optimization failed: #{inspect(reason)}
        Note: Set GEMINI_API_KEY and OPENAI_API_KEY for full functionality.
        
        """
        {:ok, %{baseline: baseline_result}}
    end
        
      {:error, reason} ->
        IO.puts "❌ Baseline test failed: #{inspect(reason)}"
        {:error, :baseline_failed}
    end
  end
  
  def run_interactive_demo do
    IO.puts """
    
    🎮 Interactive DSPEx + BEACON Demo
    =================================
    
    Ask questions and see both baseline and optimized responses!
    Type 'quit' to exit.
    
    """
    
    case run_demo() do
      {:ok, %{program: optimized_program}} ->
        baseline_program = Predict.new(QASignature, :gemini)
        interactive_loop(baseline_program, optimized_program)
        
      {:error, reason} ->
        IO.puts "❌ Demo setup failed: #{inspect(reason)}"
    end
  end
  
  defp interactive_loop(baseline, optimized) do
    question = IO.gets("🤔 Ask a question: ") |> String.trim()
    
    case question do
      "quit" ->
        IO.puts "👋 Thanks for trying DSPEx + BEACON!"
        
      "" ->
        interactive_loop(baseline, optimized)
        
      _ ->
        IO.puts "\n🧠 Thinking..."
        
        input = %{question: question}
        
        # Get baseline response
        baseline_response = case Program.forward(baseline, input) do
          {:ok, result} -> result
          {:error, _} -> %{answer: "Error", reasoning: "Failed", confidence: "low"}
        end
        
        # Get optimized response
        optimized_response = case Program.forward(optimized, input) do
          {:ok, result} -> result
          {:error, _} -> %{answer: "Error", reasoning: "Failed", confidence: "low"}
        end
        
        IO.puts """
        
        📊 BASELINE vs OPTIMIZED
        ========================
        
        BASELINE:
        Answer: #{baseline_response.answer}
        Reasoning: #{baseline_response.reasoning}
        Confidence: #{baseline_response.confidence}
        
        OPTIMIZED (BEACON):
        Answer: #{optimized_response.answer}
        Reasoning: #{optimized_response.reasoning}
        Confidence: #{optimized_response.confidence}
        
        """
        
        interactive_loop(baseline, optimized)
    end
  end
end