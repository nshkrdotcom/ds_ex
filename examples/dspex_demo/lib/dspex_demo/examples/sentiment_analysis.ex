defmodule DspexDemo.Examples.SentimentAnalysis do
  @moduledoc """
  Demonstrates DSPEx + BEACON for sentiment analysis optimization.
  """
  
  alias DSPEx.{Example, Predict, Program}
  alias DSPEx.Teleprompter.BEACON
  alias DspexDemo.Signatures.SentimentSignature
  
  def run_demo do
    # Pre-load signature module to ensure function_exported? works correctly
    SentimentSignature.input_fields()
    
    IO.puts """
    
    😊 DSPEx + BEACON Sentiment Analysis Demo
    ========================================
    
    This demo optimizes sentiment analysis with reasoning and confidence scoring.
    
    """
    
    student = Predict.new(SentimentSignature, :gemini)
    teacher = Predict.new(SentimentSignature, :gemini)
    
    # Create training examples
    trainset = [
      Example.new(%{
        text: "I absolutely love this product! It exceeded all my expectations.",
        sentiment: "positive",
        reasoning: "Strong positive language with 'absolutely love' and 'exceeded expectations'",
        confidence: "high"
      }, [:text]),
      
      Example.new(%{
        text: "This is the worst purchase I've ever made. Complete waste of money.",
        sentiment: "negative", 
        reasoning: "Extremely negative language with 'worst' and 'waste of money'",
        confidence: "high"
      }, [:text]),
      
      Example.new(%{
        text: "The product is okay, nothing special but does the job.",
        sentiment: "neutral",
        reasoning: "Balanced language with 'okay' and 'nothing special' indicating neutrality",
        confidence: "medium"
      }, [:text]),
      
      Example.new(%{
        text: "Amazing quality and fast delivery! Highly recommended.",
        sentiment: "positive",
        reasoning: "Positive descriptors 'amazing' and enthusiastic recommendation",
        confidence: "high"
      }, [:text])
    ]
    
    # Evaluation metric for sentiment analysis
    metric_fn = fn example, prediction ->
      sentiment_score = if example.data.sentiment == Map.get(prediction, :sentiment), do: 0.7, else: 0.0
      reasoning_score = if String.length(Map.get(prediction, :reasoning, "") || "") > 15, do: 0.2, else: 0.0
      confidence_score = if Map.get(prediction, :confidence) in ["high", "medium", "low"], do: 0.1, else: 0.0
      
      sentiment_score + reasoning_score + confidence_score
    end
    
    # Test input
    test_text = %{text: "The movie was pretty good but the ending was disappointing."}
    
    # Get baseline and run BEACON
    case Program.forward(student, test_text) do
      {:ok, baseline} ->
        # Create and run BEACON
        teleprompter = BEACON.new(
          num_candidates: 6,
          max_bootstrapped_demos: 2,
          num_trials: 15,
          quality_threshold: 0.6
        )
        
        case BEACON.compile(teleprompter, student, teacher, trainset, metric_fn, []) do
          {:ok, optimized} ->
            {:ok, optimized_result} = Program.forward(optimized, test_text)
            
            IO.puts """
            
            📊 SENTIMENT ANALYSIS RESULTS
            =============================
            
            Text: "#{test_text.text}"
            
            BASELINE:
            Sentiment: #{Map.get(baseline, :sentiment, "N/A")}
            Reasoning: #{Map.get(baseline, :reasoning, "N/A")}
            Confidence: #{Map.get(baseline, :confidence, "N/A")}
            
            OPTIMIZED:
            Sentiment: #{Map.get(optimized_result, :sentiment, "N/A")}
            Reasoning: #{Map.get(optimized_result, :reasoning, "N/A")}
            Confidence: #{Map.get(optimized_result, :confidence, "N/A")}
            
            """
            
            {:ok, %{baseline: baseline, optimized: optimized_result}}
            
          {:error, reason} ->
            IO.puts """
            
            📊 SENTIMENT ANALYSIS RESULTS (Baseline Only)
            ============================================
            
            Text: "#{test_text.text}"
            
            BASELINE:
            Sentiment: #{Map.get(baseline, :sentiment, "N/A")}
            Reasoning: #{Map.get(baseline, :reasoning, "N/A")}
            Confidence: #{Map.get(baseline, :confidence, "N/A")}
            
            ❌ BEACON optimization failed: #{inspect(reason)}
            Note: Set GEMINI_API_KEY and OPENAI_API_KEY for full functionality.
            
            """
            
            {:ok, %{baseline: baseline}}
        end
        
      {:error, reason} ->
        IO.puts "❌ Baseline test failed: #{inspect(reason)}"
        {:error, :baseline_failed}
    end
  end
end