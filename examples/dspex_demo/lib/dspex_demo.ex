defmodule DspexDemo do
  @moduledoc """
  DSPEx + SIMBA Demo Application
  
  This application demonstrates the power of DSPEx with SIMBA optimization
  across different use cases: question answering, sentiment analysis, and
  chain-of-thought reasoning.
  """
  
  alias DspexDemo.Examples.{QuestionAnswering, SentimentAnalysis, ChainOfThought}
  
  def main(args \\ []) do
    case parse_args(args) do
      {:help} ->
        print_help()
        
      {:interactive} ->
        QuestionAnswering.run_interactive_demo()
        
      {:demo, type} ->
        run_demo(type)
        
      {:all} ->
        run_all_demos()
        
      {:error, reason} ->
        IO.puts "❌ Error: #{reason}"
        print_help()
    end
  end
  
  defp parse_args([]), do: {:all}
  defp parse_args(["--help"]), do: {:help}
  defp parse_args(["-h"]), do: {:help}
  defp parse_args(["--interactive"]), do: {:interactive}
  defp parse_args(["-i"]), do: {:interactive}
  defp parse_args(["qa"]), do: {:demo, :question_answering}
  defp parse_args(["sentiment"]), do: {:demo, :sentiment_analysis}
  defp parse_args(["cot"]), do: {:demo, :chain_of_thought}
  defp parse_args([unknown]), do: {:error, "Unknown option: #{unknown}"}
  
  defp print_help do
    IO.puts """
    
    🎯 DSPEx + SIMBA Demo Application
    =================================
    
    This demo showcases DSPEx with SIMBA teleprompter optimization.
    
    Usage:
      mix run                    # Run all demos
      mix run qa                 # Question answering demo
      mix run sentiment          # Sentiment analysis demo  
      mix run cot                # Chain-of-thought demo
      mix run --interactive      # Interactive Q&A session
      mix run --help             # Show this help
    
    Environment Variables (optional):
      GEMINI_API_KEY            # Google Gemini API key
      OPENAI_API_KEY            # OpenAI API key
    
    Note: Without API keys, the demo will use mock responses
    for educational purposes.
    
    """
  end
  
  defp run_demo(:question_answering) do
    QuestionAnswering.run_demo()
  end
  
  defp run_demo(:sentiment_analysis) do
    SentimentAnalysis.run_demo()
  end
  
  defp run_demo(:chain_of_thought) do
    ChainOfThought.run_demo()
  end
  
  defp run_all_demos do
    IO.puts """
    
    🚀 Running All DSPEx + SIMBA Demos
    ===================================
    
    This will demonstrate SIMBA optimization across three different
    program types: Question Answering, Sentiment Analysis, and
    Chain-of-Thought Reasoning.
    
    """
    
    demos = [
      {"Question Answering", &QuestionAnswering.run_demo/0},
      {"Sentiment Analysis", &SentimentAnalysis.run_demo/0},
      {"Chain-of-Thought Reasoning", &ChainOfThought.run_demo/0}
    ]
    
    results = Enum.map(demos, fn {name, demo_fn} ->
      IO.puts "\n" <> String.duplicate("=", 60)
      IO.puts "🎯 #{name} Demo"
      IO.puts String.duplicate("=", 60)
      
      case demo_fn.() do
        {:ok, result} ->
          IO.puts "✅ #{name} demo completed successfully!"
          {name, :success, result}
          
        {:error, reason} ->
          IO.puts "❌ #{name} demo failed: #{inspect(reason)}"
          {name, :error, reason}
      end
    end)
    
    # Summary
    IO.puts """
    
    📊 DEMO SUMMARY
    ===============
    """
    
    Enum.each(results, fn {name, status, _result} ->
      emoji = if status == :success, do: "✅", else: "❌"
      IO.puts "#{emoji} #{name}: #{status}"
    end)
    
    success_count = Enum.count(results, fn {_, status, _} -> status == :success end)
    
    IO.puts """
    
    🎉 Completed #{success_count}/#{length(results)} demos successfully!
    
    The DSPEx + SIMBA framework demonstrates how Bayesian optimization
    can automatically improve language model programs by finding optimal
    instruction and demonstration combinations.
    
    """
  end
end