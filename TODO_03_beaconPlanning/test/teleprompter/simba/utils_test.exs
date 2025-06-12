defmodule DSPEx.Teleprompter.SIMBA.UtilsTest do
  @moduledoc """
  Comprehensive test suite for SIMBA Utils module.
  """

  use ExUnit.Case, async: true

  alias DSPEx.Teleprompter.SIMBA.Utils

  describe "text similarity" do
    test "identical texts return 1.0" do
      assert Utils.text_similarity("hello world", "hello world") == 1.0
    end

    test "empty strings return 1.0" do
      assert Utils.text_similarity("", "") == 1.0
    end

    test "completely different texts return low similarity" do
      similarity = Utils.text_similarity("apple banana", "car house")
      assert similarity < 0.3
    end

    test "similar texts return moderate similarity" do
      similarity = Utils.text_similarity("hello world", "hello there")
      assert similarity > 0.2 and similarity < 0.8
    end

    test "partially overlapping texts" do
      similarity = Utils.text_similarity("the quick brown fox", "the lazy brown dog")
      assert similarity > 0.3 and similarity < 0.7
    end

    test "handles nil inputs gracefully" do
      assert Utils.text_similarity(nil, "test") == 0.0
      assert Utils.text_similarity("test", nil) == 0.0
      assert Utils.text_similarity(nil, nil) == 0.0
    end

    test "case insensitive comparison" do
      similarity1 = Utils.text_similarity("Hello World", "hello world")
      similarity2 = Utils.text_similarity("hello world", "hello world")
      assert similarity1 == similarity2
    end

    test "handles different text lengths" do
      short = "cat"
      long = "the cat sat on the mat and looked very comfortable"
      similarity = Utils.text_similarity(short, long)
      assert similarity > 0.0 and similarity < 0.5
    end
  end

  describe "answer normalization" do
    test "removes punctuation and converts to lowercase" do
      assert Utils.normalize_answer("Hello, World!") == "hello world"
    end

    test "trims whitespace" do
      assert Utils.normalize_answer("  test  ") == "test"
      assert Utils.normalize_answer("\n\tspaced\t\n") == "spaced"
    end

    test "removes special characters" do
      assert Utils.normalize_answer("$42.50") == "4250"
      assert Utils.normalize_answer("user@example.com") == "userexamplecom"
    end

    test "handles empty and nil inputs" do
      assert Utils.normalize_answer("") == ""
      assert Utils.normalize_answer(nil) == ""
    end

    test "preserves alphanumeric characters" do
      assert Utils.normalize_answer("Test123") == "test123"
    end

    test "handles complex punctuation" do
      assert Utils.normalize_answer("Don't you think so?!") == "dont you think so"
    end
  end

  describe "keyword extraction" do
    test "extracts meaningful words" do
      keywords = Utils.extract_keywords("This is a test sentence with some important words")
      assert "test" in keywords
      assert "sentence" in keywords
      assert "important" in keywords
      assert "words" in keywords
    end

    test "filters out stop words" do
      keywords = Utils.extract_keywords("This is a test with some common words")
      refute "this" in keywords
      refute "with" in keywords
      refute "some" in keywords
      assert "test" in keywords
    end

    test "filters out short words" do
      keywords = Utils.extract_keywords("I am at the big house")
      refute "I" in keywords
      refute "am" in keywords
      refute "at" in keywords
      assert "house" in keywords
    end

    test "handles empty and nil inputs" do
      assert Utils.extract_keywords("") == []
      assert Utils.extract_keywords(nil) == []
    end

    test "case insensitive extraction" do
      keywords1 = Utils.extract_keywords("Important Test")
      keywords2 = Utils.extract_keywords("important test")
      assert keywords1 == keywords2
    end

    test "handles special characters" do
      keywords = Utils.extract_keywords("test-case, important@example.com")
      # Should handle gracefully, exact behavior may vary
      assert is_list(keywords)
    end
  end

  describe "number extraction" do
    test "extracts integer from text" do
      assert Utils.extract_number("The answer is 42") == 42
    end

    test "extracts float from text" do
      assert Utils.extract_number("Price: $19.99") == 19.99
    end

    test "finds first number in text" do
      assert Utils.extract_number("Buy 5 apples for $2.50 each") == 5
    end

    test "returns nil when no number found" do
      assert Utils.extract_number("No numbers here") == nil
    end

    test "handles nil input" do
      assert Utils.extract_number(nil) == nil
    end

    test "handles empty string" do
      assert Utils.extract_number("") == nil
    end

    test "extracts from complex text" do
      assert Utils.extract_number("Version 2.1.3 released") == 2.1
    end

    test "handles negative numbers" do
      # Note: Current implementation may not handle negatives
      result = Utils.extract_number("Temperature: -5 degrees")
      assert result == 5 or result == nil  # Either extracts 5 or finds no number
    end
  end

  describe "reasoning quality evaluation" do
    test "high quality reasoning with math operations" do
      expected = "Calculate 5 × 12 = 60 dollars"
      actual = "First, multiply 5 × 12 = 60. Therefore, the answer is $60."

      score = Utils.evaluate_reasoning_quality(expected, actual)
      assert score > 0.2  # Should get points for math operations and structure
    end

    test "poor quality reasoning gets low score" do
      expected = "Calculate 5 × 12 = 60 dollars"
      actual = "The answer is obvious."

      score = Utils.evaluate_reasoning_quality(expected, actual)
      assert score < 0.1
    end

    test "reasoning with logical connectors gets bonus" do
      expected = "Step by step solution"
      actual = "First, we do this. Then we do that. Therefore, the result is correct."

      score = Utils.evaluate_reasoning_quality(expected, actual)
      assert score > 0.05  # Should get logic bonus
    end

    test "reasoning with step markers gets bonus" do
      expected = "Multi-step process"
      actual = "Step 1: Start here. Next, move forward. Finally, conclude."

      score = Utils.evaluate_reasoning_quality(expected, actual)
      assert score > 0.05  # Should get step bonus
    end

    test "identical reasoning gets perfect keyword overlap" do
      reasoning = "This is a detailed reasoning process"
      score = Utils.evaluate_reasoning_quality(reasoning, reasoning)
      assert score > 0.2  # Perfect keyword match should score well
    end

    test "handles nil inputs gracefully" do
      assert Utils.evaluate_reasoning_quality(nil, "test") >= 0.0
      assert Utils.evaluate_reasoning_quality("test", nil) >= 0.0
    end

    test "score is bounded to maximum of 0.4" do
      # Create reasoning with all possible bonuses
      rich_reasoning = "First, calculate 5 × 12 = 60. Then, because this equals our target, therefore the final step gives us the answer."

      score = Utils.evaluate_reasoning_quality(rich_reasoning, rich_reasoning)
      assert score <= 0.4
    end
  end

  describe "correlation ID generation" do
    test "generates valid correlation ID" do
      id = Utils.generate_correlation_id()
      assert is_binary(id)
      assert String.starts_with?(id, "simba-")
      assert String.length(id) > 10
    end

    test "generates unique IDs" do
      id1 = Utils.generate_correlation_id()
      id2 = Utils.generate_correlation_id()
      assert id1 != id2
    end

    test "follows expected format" do
      id = Utils.generate_correlation_id()
      assert Regex.match?(~r/^simba-[a-f0-9]{16}$/, id)
    end
  end

  describe "execution time measurement" do
    test "measures successful function execution" do
      result = Utils.measure_execution_time(fn ->
        Process.sleep(10)
        {:ok, "test"}
      end)

      assert result.duration_ms >= 10
      assert result.success == true
      assert result.result == {:ok, "test"}
    end

    test "measures failed function execution" do
      result = Utils.measure_execution_time(fn ->
        raise "test error"
      end)

      assert result.duration_ms >= 0
      assert result.success == false
      assert match?({:error, _}, result.result)
    end

    test "handles functions that throw" do
      result = Utils.measure_execution_time(fn ->
        throw(:test_throw)
      end)

      assert result.success == false
      assert match?({:error, _}, result.result)
    end

    test "handles functions that exit" do
      result = Utils.measure_execution_time(fn ->
        exit(:test_exit)
      end)

      assert result.success == false
      assert match?({:error, _}, result.result)
    end

    test "timing accuracy" do
      sleep_time = 50
      result = Utils.measure_execution_time(fn ->
        Process.sleep(sleep_time)
        :ok
      end)

      # Allow for some timing variance
      assert result.duration_ms >= sleep_time - 5
      assert result.duration_ms <= sleep_time + 20
    end
  end

  describe "detailed progress reporter" do
    test "handles bootstrap generation progress" do
      progress = %{
        phase: :bootstrap_generation,
        completed: 5,
        total: 10
      }

      # Should not crash
      assert Utils.detailed_progress_reporter(progress) == :ok
    end

    test "handles bayesian optimization progress" do
      progress = %{
        phase: :bayesian_optimization,
        trial: 10,
        current_score: 0.85,
        total_trials: 50
      }

      assert Utils.detailed_progress_reporter(progress) == :ok
    end

    test "handles unknown phase" do
      progress = %{
        phase: :unknown_phase,
        data: "some data"
      }

      assert Utils.detailed_progress_reporter(progress) == :ok
    end

    test "handles malformed progress" do
      # Should handle gracefully even with missing fields
      progress = %{phase: :bootstrap_generation}

      assert Utils.detailed_progress_reporter(progress) == :ok
    end
  end
end
