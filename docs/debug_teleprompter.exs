# Debug script to test teleprompter bootstrap process

# Load the application
System.put_env("MIX_ENV", "test")
Application.put_env(:dspex, :test_mode, :mock)

# Define a simple signature for testing
defmodule TestSignature do
  use DSPEx.Signature, "question -> reasoning, answer"
end

defmodule SimpleSignature do
  use DSPEx.Signature, "question -> answer"
end

# Set up mock responses
teacher_responses = [
  "Starting with 15 apples. After selling 7: 15 - 7 = 8 apples. After getting 8 more: 8 + 8 = 16 apples.\n16",
  "25% means 25/100 or 0.25. To find 25% of 80: 80 × 0.25 = 20.\n20",
  "Let me think step by step about this problem.\nThis is the answer"
]

DSPEx.MockClientManager.set_mock_responses(:gemini, teacher_responses ++ teacher_responses)

# Create programs
teacher = DSPEx.Predict.new(TestSignature, :gemini)
student = DSPEx.Predict.new(TestSignature, :gemini)

# Create training examples
training_examples = [
  DSPEx.Example.new(%{
    question: "If a store has 15 apples and sells 7, then gets 8 more, how many apples does it have?",
    reasoning: "Starting with 15 apples. After selling 7: 15 - 7 = 8 apples. After getting 8 more: 8 + 8 = 16 apples.",
    answer: "16"
  }),
  DSPEx.Example.new(%{
    question: "What is 25% of 80?",
    reasoning: "25% means 25/100 or 0.25. To find 25% of 80: 80 × 0.25 = 20.",
    answer: "20"
  })
]

IO.puts("🔍 Debug: Starting teleprompter debug test")

# Test mock client setup first
IO.puts("\n=== Testing Mock Client ===")
{:ok, mock_client} = DSPEx.MockClientManager.start_link(:gemini, %{responses: teacher_responses})
IO.puts("Mock client started: #{inspect(mock_client)}")

test_request = DSPEx.MockClientManager.request(mock_client, [%{role: "user", content: "Test question about apples"}])
IO.puts("Test request result: #{inspect(test_request)}")

# Test teacher execution directly
IO.puts("\n=== Testing Teacher Execution ===")
for {example, i} <- Enum.with_index(training_examples) do
  inputs = DSPEx.Example.inputs(example)
  IO.puts("Example #{i+1} inputs: #{inspect(inputs)}")
  
  case DSPEx.Program.forward(teacher, inputs) do
    {:ok, result} ->
      IO.puts("Teacher result: #{inspect(result)}")
    {:error, reason} ->
      IO.puts("Teacher failed: #{inspect(reason)}")
  end
end

# Test metric function
IO.puts("\n=== Testing Metric Function ===")
metric_fn = fn example, prediction ->
  # For mock testing with bootstrap, be very lenient
  answer_score =
    if (Map.has_key?(prediction, :answer) and is_binary(Map.get(prediction, :answer))) or
       (Map.has_key?(prediction, "answer") and is_binary(Map.get(prediction, "answer"))) do
      0.7
    else
      0.0
    end

  reasoning_score =
    cond do
      Map.has_key?(prediction, :reasoning) and is_binary(Map.get(prediction, :reasoning)) and 
      String.length(Map.get(prediction, :reasoning)) > 5 -> 0.3
      Map.has_key?(prediction, "reasoning") and is_binary(Map.get(prediction, "reasoning")) and 
      String.length(Map.get(prediction, "reasoning")) > 5 -> 0.3
      is_map(prediction) and map_size(prediction) > 0 -> 0.3
      true -> 0.0
    end

  total_score = answer_score + reasoning_score
  IO.puts("Score debug: answer=#{answer_score}, reasoning=#{reasoning_score}, total=#{total_score}")
  total_score
end

# Test metric with sample data
sample_prediction = %{reasoning: "Test reasoning", answer: "Test answer"}
score = metric_fn.(hd(training_examples), sample_prediction)
IO.puts("Sample metric score: #{score}")

# Try bootstrap
IO.puts("\n=== Testing Bootstrap ===")
result = DSPEx.Teleprompter.BootstrapFewShot.compile(
  student, teacher, training_examples, metric_fn,
  quality_threshold: 0.0
)

case result do
  {:ok, optimized} ->
    IO.puts("✅ Bootstrap succeeded!")
    IO.puts("Demos count: #{length(optimized.demos)}")
  {:error, reason} ->
    IO.puts("❌ Bootstrap failed: #{inspect(reason)}")
end

IO.puts("\n🔍 Debug: Teleprompter debug test complete")