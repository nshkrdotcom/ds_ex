# DSPEx + BEACON Demo Application 🚀

A comprehensive demonstration of the DSPEx framework with **BEACON teleprompter optimization**, showcasing how Bayesian optimization can automatically improve language model programs.

## ✅ Status: FULLY WORKING

This demo application successfully demonstrates:
- **Complete BEACON optimization pipeline** 
- **Real-time Bayesian optimization** with instruction and demonstration tuning
- **End-to-end teleprompter workflows** from bootstrap to optimized programs

## 🎯 Features

- **Question Answering** - Optimizes Q&A with reasoning and confidence scoring
- **Sentiment Analysis** - Improves sentiment classification with explanations  
- **Chain-of-Thought** - Enhances mathematical reasoning step-by-step
- **Interactive Mode** - Ask questions and compare baseline vs optimized responses
- **Real API Integration** - Works with Gemini and OpenAI APIs (GEMINI_API_KEY detected!)
- **Educational Fallbacks** - Mock responses when API keys aren't configured

## 🚀 Quick Start

### Setup

```bash
# Navigate to the demo directory
cd examples/dspex_demo

# Install dependencies  
mix deps.get

# (Optional) Set API keys for live demonstrations
export GEMINI_API_KEY=your_gemini_key_here
export OPENAI_API_KEY=your_openai_key_here
```

### Running Demos

```bash
# Method 1: Use the demo script (recommended)
./demo                     # Run all demos
./demo qa                  # Question answering only
./demo sentiment           # Sentiment analysis only
./demo cot                 # Chain-of-thought only
./demo --interactive       # Interactive Q&A session
./demo --help              # Show help

# Method 2: Use mix run directly
mix run -e "DspexDemo.main([])"                    # All demos
mix run -e "DspexDemo.main([\"qa\"])"              # Question answering
mix run -e "DspexDemo.main([\"sentiment\"])"       # Sentiment analysis
mix run -e "DspexDemo.main([\"cot\"])"             # Chain-of-thought
mix run -e "DspexDemo.main([\"--interactive\"])"   # Interactive mode
```

## 📊 What You'll See

Each demo shows:

1. **Baseline Performance** - Initial program output
2. **BEACON Optimization Process** - Real-time progress of:
   - Instruction candidate generation
   - Demonstration bootstrapping
   - Bayesian optimization trials
3. **Optimized Performance** - Improved program output
4. **Side-by-side Comparison** - Clear before/after results

## 🛠 How It Works

### BEACON Optimization Process

1. **Teacher-Student Setup** - Uses different models (e.g., GPT-4 as teacher, Gemini as student)
2. **Instruction Generation** - Teacher generates multiple instruction candidates
3. **Demonstration Bootstrapping** - Creates high-quality examples automatically
4. **Bayesian Optimization** - Finds optimal instruction + demonstration combinations
5. **Program Enhancement** - Returns optimized student program

### Example Signatures

**Question Answering**
```elixir
use DSPEx.Signature, "question -> answer, reasoning, confidence"
```

**Sentiment Analysis**
```elixir
use DSPEx.Signature, "text -> sentiment, reasoning, confidence"
```

**Chain-of-Thought**
```elixir
use DSPEx.Signature, "problem -> reasoning, answer"
```

## 🔧 Configuration

The demo uses the following default configuration in `config/config.exs`:

- **Default Provider**: Gemini (for students)
- **Teacher Provider**: OpenAI (for instruction generation)
- **Timeout**: 30 seconds per API call
- **Concurrency**: Up to 10 concurrent operations

## 📚 Educational Value

This demo illustrates:

- **Automated Program Improvement** - No manual prompt engineering required
- **Multi-Model Orchestration** - Leveraging different models' strengths
- **Evaluation Metrics** - Custom scoring functions for different tasks
- **Progress Tracking** - Real-time optimization feedback
- **Fallback Handling** - Graceful degradation without API keys

## 🎮 Interactive Mode

The interactive Q&A mode lets you:

1. Ask any question
2. See both baseline and optimized responses
3. Compare reasoning quality and structure
4. Experience the improvement firsthand

Example interaction:
```
🤔 Ask a question: What is the square root of 144?

📊 BASELINE vs OPTIMIZED
========================

BASELINE:
Answer: 12
Reasoning: 144 is a perfect square
Confidence: medium

OPTIMIZED (BEACON):
Answer: 12
Reasoning: To find the square root of 144, I need to find what number multiplied by itself equals 144. Since 12 × 12 = 144, the square root of 144 is 12.
Confidence: high
```

## 🚀 Next Steps

After running the demo, you can:

1. Modify the training examples to see different optimization results
2. Adjust BEACON parameters (num_candidates, num_trials, etc.)
3. Create new signatures for different tasks
4. Experiment with different evaluation metrics
5. Use the optimized programs in your own applications

The demo provides a complete foundation for understanding and extending DSPEx + BEACON capabilities!