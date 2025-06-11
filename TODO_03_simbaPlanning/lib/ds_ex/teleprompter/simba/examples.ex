defmodule DSPEx.Teleprompter.SIMBA.Examples do
  @moduledoc """
  Comprehensive examples demonstrating various SIMBA teleprompter use cases.

  This module provides educational examples showing how to use SIMBA for different
  types of optimization tasks, from basic question answering to complex reasoning.
  """

  alias DSPEx.{Example, Predict, Program}
  alias DSPEx.Teleprompter.SIMBA
  alias DSPEx.Teleprompter.SIMBA.Utils

  @doc """
  Example 1: Basic Question Answering Optimization

  Demonstrates fundamental SIMBA usage for optimizing a simple Q&A program.
  """
  def question_answering_example do
    defmodule QASignature do
      @moduledoc "Answer questions with clear, accurate responses"
      use DSPEx.Signature, "question -> answer"
    end

    student = Predict.new(QASignature, :gemini)
    teacher = Predict.new(QASignature, :openai)

    trainset = [
      Example.new(%{
        question: "What is the capital of France?",
        answer: "Paris"
      }, [:question]),
      Example.new(%{
        question: "What is 2 + 2?",
        answer: "4"
      }, [:question]),
      Example.new(%{
        question: "Who wrote Romeo and Juliet?",
        answer: "William Shakespeare"
      }, [:question]),
      Example.new(%{
        question: "What is the largest planet?",
        answer: "Jupiter"
      }, [:question]),
      Example.new(%{
        question: "What year did WWII end?",
        answer: "1945"
      }, [:question])
    ]

    metric_fn = fn example, prediction ->
      expected = Example.outputs(example)[:answer]
      actual = prediction[:answer]

      if String.downcase(expected) == String.downcase(actual) do
        1.0
      else
        similarity = Utils.text_similarity(expected, actual)
        if similarity > 0.8, do: 0.7, else: 0.0
      end
    end

    teleprompter = SIMBA.new(
      num_candidates: 15,
      max_bootstrapped_demos: 3,
      num_trials: 30,
      quality_threshold: 0.6,
      progress_callback: &Utils.detailed_progress_reporter/1
    )

    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✓ QA optimization successful!")
        test_optimized_program(optimized_student, %{question: "What is the smallest country in the world?"})

      {:error, reason} ->
        IO.puts("✗ QA optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 2: Mathematical Reasoning with Chain-of-Thought

  Shows SIMBA optimization for complex reasoning tasks requiring step-by-step thinking.
  """
  def chain_of_thought_example do
    defmodule ReasoningSignature do
      @moduledoc "Solve math word problems with step-by-step reasoning"
      use DSPEx.Signature, "problem -> reasoning, answer"
    end

    student = Predict.new(ReasoningSignature, :gemini)
    teacher = Predict.new(ReasoningSignature, :openai)

    trainset = [
      Example.new(%{
        problem: "Tom saves $5 every week. After 12 weeks, how much money has he saved?",
        reasoning: "Tom saves $5 per week for 12 weeks. Total savings = $5 × 12 = $60.",
        answer: "$60"
      }, [:problem]),

      Example.new(%{
        problem: "A pizza is cut into 8 equal slices. If 3 slices are eaten, what fraction remains?",
        reasoning: "The pizza has 8 slices total. 3 slices are eaten, so 8 - 3 = 5 slices remain. The fraction remaining is 5/8.",
        answer: "5/8"
      }, [:problem]),

      Example.new(%{
        problem: "A rectangular garden is 8 meters long and 6 meters wide. What is its area?",
        reasoning: "The area of a rectangle is length × width. So the area is 8 × 6 = 48 square meters.",
        answer: "48 square meters"
      }, [:problem])
    ]

    metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)

      # Answer correctness (60%)
      answer_score =
        if Utils.normalize_answer(expected_outputs[:answer]) == Utils.normalize_answer(prediction[:answer]) do
          0.6
        else
          case {Utils.extract_number(expected_outputs[:answer]), Utils.extract_number(prediction[:answer])} do
            {expected_num, predicted_num} when is_number(expected_num) and is_number(predicted_num) ->
              diff = abs(expected_num - predicted_num)
              if diff <= expected_num * 0.1, do: 0.3, else: 0.0
            _ ->
              0.0
          end
        end

      # Reasoning quality (40%)
      reasoning_score = Utils.evaluate_reasoning_quality(
        expected_outputs[:reasoning],
        prediction[:reasoning]
      )

      answer_score + reasoning_score
    end

    teleprompter = SIMBA.new(
      num_candidates: 25,
      max_bootstrapped_demos: 3,
      num_trials: 50,
      quality_threshold: 0.75,
      instruction_model: :openai,
      timeout: 90_000,
      progress_callback: &Utils.detailed_progress_reporter/1
    )

    IO.puts("🧠 Starting Chain-of-Thought reasoning optimization...")

    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✅ Reasoning optimization successful!")

        test_problem = """
        A bakery sells cupcakes for $3 each and cookies for $2 each.
        If someone buys 4 cupcakes and 6 cookies, and pays with a $30 bill,
        how much change should they receive?
        """

        test_optimized_program(optimized_student, %{problem: test_problem})

      {:error, reason} ->
        IO.puts("❌ Reasoning optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 3: Text Classification with Confidence Scoring

  Demonstrates SIMBA for classification tasks with confidence calibration.
  """
  def text_classification_example do
    defmodule ClassificationSignature do
      @moduledoc "Classify text sentiment with confidence"
      use DSPEx.Signature, "text -> sentiment, confidence"
    end

    student = Predict.new(ClassificationSignature, :gemini)
    teacher = Predict.new(ClassificationSignature, :openai)

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
      }, [:text])
    ]

    metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)

      # Sentiment accuracy (70%)
      sentiment_score =
        if expected_outputs[:sentiment] == prediction[:sentiment] do
          0.7
        else
          0.0
        end

      # Confidence appropriateness (30%)
      confidence_score =
        case {expected_outputs[:confidence], prediction[:confidence]} do
          {same, same} -> 0.3
          {"high", "medium"} -> 0.15
          {"medium", "high"} -> 0.15
          {"medium", "low"} -> 0.15
          {"low", "medium"} -> 0.15
          _ -> 0.0
        end

      sentiment_score + confidence_score
    end

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

        test_cases = [
          "This movie is absolutely fantastic!",
          "I'm not sure how I feel about this.",
          "Worst experience of my life."
        ]

        results = test_classification_program(optimized_student, test_cases)
        display_classification_results(results)

        {:ok, optimized_student}

      {:error, reason} ->
        IO.puts("✗ Classification optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 4: Multi-Step Program Optimization

  Shows optimization of complex programs with multiple processing steps.
  """
  def multi_step_program_example do
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

    defmodule AnalysisSignature do
      @moduledoc "Analyze input and extract key information"
      use DSPEx.Signature, "text -> key_points, sentiment, entities"
    end

    defmodule SynthesisSignature do
      @moduledoc "Synthesize analysis into comprehensive summary"
      use DSPEx.Signature, "key_points, sentiment, entities -> summary, recommendation"
    end

    student = create_multi_step_program(AnalysisSignature, SynthesisSignature, :gemini)
    teacher = create_multi_step_program(AnalysisSignature, SynthesisSignature, :openai)

    trainset = [
      Example.new(%{
        text: "The new smartphone has excellent camera quality and long battery life, but the price is quite high. Customer reviews are mostly positive.",
        summary: "High-quality smartphone with excellent camera and battery, but expensive. Generally positive feedback.",
        recommendation: "Good choice for users prioritizing camera quality and battery life, if budget allows."
      }, [:text])
    ]

    metric_fn = fn example, prediction ->
      expected_outputs = Example.outputs(example)

      summary_score = Utils.text_similarity(expected_outputs[:summary], prediction[:summary]) * 0.6
      recommendation_score = Utils.text_similarity(expected_outputs[:recommendation], prediction[:recommendation]) * 0.4

      summary_score + recommendation_score
    end

    teleprompter = SIMBA.new(
      num_candidates: 15,
      max_bootstrapped_demos: 2,
      num_trials: 25,
      quality_threshold: 0.7,
      max_concurrency: 10,
      timeout: 90_000
    )

    case teleprompter.compile(student, teacher, trainset, metric_fn) do
      {:ok, optimized_student} ->
        IO.puts("✓ Multi-step optimization successful!")

        test_text = """
        The new electric car model offers impressive range and fast charging capabilities.
        The interior design is modern and comfortable. However, the charging infrastructure
        in rural areas is still limited, which could be a concern for long trips.
        """

        test_optimized_program(optimized_student, %{text: test_text})

      {:error, reason} ->
        IO.puts("✗ Multi-step optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run all examples in sequence and generate a comprehensive report.
  """
  def run_all_examples do
    IO.puts("🚀 Running All SIMBA Examples")
    IO.puts("=" |> String.duplicate(40))

    examples = [
      {:question_answering, &question_answering_example/0},
      {:chain_of_thought, &chain_of_thought_example/0},
      {:text_classification, &text_classification_example/0},
      {:multi_step_program, &multi_step_program_example/0}
    ]

    results = examples
    |> Enum.map(fn {name, example_fn} ->
      IO.puts("\n🔬 Running #{format_example_name(name)}...")
      result = Utils.measure_execution_time(example_fn)

      status = if result.success, do: "✅", else: "❌"
      IO.puts("#{status} #{format_example_name(name)}: #{result.duration_ms}ms")

      {name, result}
    end)

    generate_examples_report(results)
  end

  # Private helper functions

  defp test_optimized_program(program, inputs) do
    case Program.forward(program, inputs) do
      {:ok, result} ->
        IO.puts("Test result: #{inspect(result)}")
        {:ok, result}

      {:error, reason} ->
        IO.puts("Test failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_multi_step_program(analysis_sig, synthesis_sig, model) do
    %MultiStepProgram{
      analyze_step: Predict.new(analysis_sig, model),
      synthesize_step: Predict.new(synthesis_sig, model),
      demos: []
    }
  end

  defp test_classification_program(program, test_cases) do
    Enum.map(test_cases, fn text ->
      case Program.forward(program, %{text: text}) do
        {:ok, result} ->
          {text, result[:sentiment], result[:confidence]}
        {:error, _} ->
          {text, "error", "unknown"}
      end
    end)
  end

  defp display_classification_results(results) do
    IO.puts("Test results:")
    Enum.each(results, fn {text, sentiment, confidence} ->
      IO.puts("  \"#{text}\" -> #{sentiment} (#{confidence})")
    end)
  end

  defp format_example_name(name) do
    name
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp generate_examples_report(results) do
    IO.puts("\n📊 EXAMPLES EXECUTION REPORT")
    IO.puts("=" |> String.duplicate(40))

    total_tests = length(results)
    successful = Enum.count(results, fn {_, result} -> result.success end)
    total_time = results |> Enum.map(fn {_, result} -> result.duration_ms end) |> Enum.sum()

    IO.puts("Total Examples: #{total_tests}")
    IO.puts("Successful: #{successful}")
    IO.puts("Success Rate: #{Float.round(successful / total_tests * 100, 1)}%")
    IO.puts("Total Time: #{total_time}ms")
    IO.puts("Average Time: #{Float.round(total_time / total_tests, 1)}ms")

    results
  end
end
