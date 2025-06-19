# DSPy Evaluation System Integration Guide for DSPEx

## Overview

This document provides a comprehensive guide for integrating DSPy's evaluation system into DSPEx. The evaluation system is a critical component for measuring program performance, optimizing parameters, and validating results across different metrics and configurations.

## Current DSPy Evaluation Architecture

### Core Components

#### 1. Main Evaluation Framework (`dspy/evaluate/evaluate.py`)

**Purpose**: Orchestrates evaluation execution with parallel processing, progress tracking, and result aggregation.

**Key Features**:
- Parallel execution using ThreadPoolExecutor
- Progress tracking with tqdm
- Result table display (console/Jupyter)
- Error handling and timeout management
- Straggler detection and resubmission
- Callback system integration

**Core Class**: `Evaluate`
```python
class Evaluate:
    def __init__(self, *, devset, metric=None, num_threads=None, 
                 display_progress=False, display_table=False, 
                 max_errors=None, return_all_scores=False, 
                 return_outputs=False, provide_traceback=None, 
                 failure_score=0.0)
```

#### 2. Basic Metrics (`dspy/evaluate/metrics.py`)

**Current Metrics**:
- `answer_exact_match`: Exact string matching with normalization
- `answer_passage_match`: Passage-level answer detection
- Internal functions: `_answer_match`, `_passage_match`

**Dependencies**: 
- `dspy.dsp.utils.EM` (Exact Match)
- `dspy.dsp.utils.F1` (F1 Score)
- `dspy.dsp.utils.DPR_normalize` (Text normalization)
- `dspy.dsp.utils.has_answer` (Answer detection in passages)

#### 3. Auto-Evaluation (`dspy/evaluate/auto_evaluation.py`)

**LLM-Based Evaluators**:
- `SemanticF1`: Semantic recall/precision using LLM
- `CompleteAndGrounded`: Combines completeness and groundedness
- `DecompositionalSemanticRecallPrecision`: Detailed semantic analysis
- `AnswerCompleteness`: Coverage evaluation
- `AnswerGroundedness`: Context support evaluation

#### 4. Parallel Execution (`dspy/utils/parallelizer.py`)

**Features**:
- Thread pool management
- Timeout and straggler handling
- Error tracking and cancellation
- Thread-local settings isolation
- Signal handling (Ctrl-C)

#### 5. Core Metrics Utilities (`dspy/dsp/utils/metrics.py`)

**Advanced Metrics**:
- `EM()`: Exact Match with multiple answers
- `F1()`: Token-level F1 score
- `HotPotF1()`: HotPot QA specific F1
- `normalize_text()`: Text preprocessing
- `em_score()`, `f1_score()`, `hotpot_f1_score()`: Core implementations

#### 6. Text Processing (`dspy/dsp/utils/dpr.py`)

**DPR Integration**:
- `has_answer()`: Answer detection in text
- `DPR_normalize()`: DPR-style text normalization
- `DPR_tokenize()`: Tokenization
- `locate_answers()`: Answer position detection
- Advanced tokenizer classes

## Missing Advanced Components (To Be Implemented)

### 1. Advanced Metrics (Priority: High)

#### Semantic Similarity Metrics
```elixir
# lib/dspex/evaluation/metrics/semantic.ex
defmodule DSPEx.Evaluation.Metrics.Semantic do
  @moduledoc """
  Advanced semantic similarity metrics for evaluation
  """
  
  def bleu_score(prediction, references, n_gram \\ 4)
  def rouge_score(prediction, reference, rouge_type \\ :rouge_l)
  def bert_score(prediction, reference, model \\ "bert-base-uncased")
  def semantic_f1(prediction, reference, threshold \\ 0.66)
end
```

#### Implementation Requirements:
- **BLEU Score**: N-gram precision with brevity penalty
- **ROUGE Score**: Recall-oriented metrics (ROUGE-1, ROUGE-2, ROUGE-L)
- **BERTScore**: Contextual embeddings similarity
- **Semantic F1**: LLM-based semantic overlap

#### Dependencies:
- Elixir NLP libraries or Python interop
- Pre-trained models (BERT, sentence transformers)
- N-gram processing utilities

### 2. Evaluation Framework Enhancements

#### Multi-threaded Evaluation
```elixir
# lib/dspex/evaluation/parallel_evaluator.ex
defmodule DSPEx.Evaluation.ParallelEvaluator do
  use GenServer
  
  def start_link(opts \\ [])
  def evaluate_async(evaluator, program, devset, metric, opts \\ [])
  def get_progress(evaluator)
  def cancel_evaluation(evaluator)
  
  # Internal process management
  defp spawn_workers(num_workers, work_queue)
  defp handle_timeouts(workers, timeout_ms)
  defp aggregate_results(results)
end
```

#### Progress and Display
```elixir
# lib/dspex/evaluation/display.ex
defmodule DSPEx.Evaluation.Display do
  def progress_bar(current, total, metrics \\ %{})
  def result_table(results, metric_name, opts \\ [])
  def statistical_summary(scores)
  def error_breakdown(errors)
  def export_results(results, format \\ :csv)
end
```

### 3. Auto-Evaluation System

#### LLM-Based Evaluation Signatures
```elixir
# lib/dspex/evaluation/auto/signatures.ex
defmodule DSPEx.Evaluation.Auto.Signatures do
  use DSPEx.Signature
  
  @semantic_precision """
  Compare a system's response to ground truth for recall and precision.
  """
  signature "question: str, ground_truth: str, system_response: str -> recall: float, precision: float"
  
  @completeness """
  Evaluate response completeness against ground truth.
  """
  signature "question: str, ground_truth: str, system_response: str -> completeness: float"
  
  @groundedness """
  Assess response groundedness in retrieved context.
  """
  signature "question: str, context: str, response: str -> groundedness: float"
end
```

#### Auto-Evaluator Modules
```elixir
# lib/dspex/evaluation/auto/evaluators.ex
defmodule DSPEx.Evaluation.Auto.Evaluators do
  def semantic_f1(example, prediction, opts \\ [])
  def complete_and_grounded(example, prediction, opts \\ [])
  def faithfulness(example, prediction, opts \\ [])
  def relevance(example, prediction, opts \\ [])
  def hallucination_detection(example, prediction, opts \\ [])
end
```

### 4. Specialized Evaluators

#### Domain-Specific Metrics
```elixir
# lib/dspex/evaluation/specialized/
├── qa_evaluators.ex          # Question-answering specific
├── summarization.ex          # Summarization metrics
├── classification.ex         # Classification accuracy
├── generation.ex            # Text generation quality
└── retrieval.ex            # Retrieval evaluation
```

## Integration Strategy for DSPEx

### Phase 1: Core Framework (Weeks 1-2)

#### 1.1 Basic Evaluation Infrastructure
```elixir
# lib/dspex/evaluation.ex
defmodule DSPEx.Evaluation do
  @moduledoc """
  Main evaluation interface for DSPEx programs
  """
  
  defstruct [
    :devset,
    :metric,
    :num_workers,
    :display_progress,
    :display_table,
    :max_errors,
    :return_all_scores,
    :return_outputs,
    :provide_traceback,
    :failure_score
  ]
  
  def new(devset, metric, opts \\ [])
  def evaluate(evaluator, program, opts \\ [])
  def evaluate_async(evaluator, program, opts \\ [])
end
```

#### 1.2 Core Metrics Implementation
```elixir
# lib/dspex/evaluation/metrics/core.ex
defmodule DSPEx.Evaluation.Metrics.Core do
  def exact_match(prediction, answers) when is_list(answers)
  def exact_match(prediction, answer) when is_binary(answer)
  
  def f1_score(prediction, ground_truth)
  def token_f1(prediction, ground_truth)
  def normalize_text(text)
  
  def passage_match(passages, answers)
  def has_answer?(text, answers)
end
```

#### 1.3 Text Processing Utilities
```elixir
# lib/dspex/evaluation/text_processing.ex
defmodule DSPEx.Evaluation.TextProcessing do
  def normalize_text(text)
  def tokenize(text, opts \\ [])
  def remove_articles(text)
  def remove_punctuation(text)
  def strip_accents(text)
  def ngrams(tokens, n)
end
```

### Phase 2: Parallel Processing (Weeks 3-4)

#### 2.1 Parallel Evaluator
```elixir
# lib/dspex/evaluation/parallel.ex
defmodule DSPEx.Evaluation.Parallel do
  use GenServer
  
  def start_link(opts \\ [])
  def evaluate_parallel(pid, program, devset, metric, opts \\ [])
  
  # Worker process management
  defp start_workers(num_workers)
  defp distribute_work(work_items, workers)
  defp collect_results(workers, timeout)
  defp handle_worker_timeout(worker, work_item)
end
```

#### 2.2 Progress Tracking
```elixir
# lib/dspex/evaluation/progress.ex
defmodule DSPEx.Evaluation.Progress do
  use GenServer
  
  def start_link(total_items, opts \\ [])
  def update_progress(pid, completed, metrics \\ %{})
  def display_progress(pid)
  def get_stats(pid)
end
```

### Phase 3: Advanced Metrics (Weeks 5-7)

#### 3.1 Semantic Metrics
- Implement BLEU, ROUGE, BERTScore
- Use Python interop via Pythonx/Nx for ML models
- Create embedding similarity functions

#### 3.2 LLM-Based Evaluation
- Port auto-evaluation signatures
- Implement semantic F1, completeness, groundedness
- Add reference-free evaluation methods

### Phase 4: Display and Reporting (Week 8)

#### 4.1 Result Display
```elixir
# lib/dspex/evaluation/display/table.ex
defmodule DSPEx.Evaluation.Display.Table do
  def format_results(results, metric_name, opts \\ [])
  def export_csv(results, filename)
  def export_json(results, filename)
  def console_table(results, opts \\ [])
end
```

#### 4.2 Statistical Analysis
```elixir
# lib/dspex/evaluation/stats.ex
defmodule DSPEx.Evaluation.Stats do
  def compute_statistics(scores)
  def confidence_intervals(scores, confidence \\ 0.95)
  def significance_test(scores1, scores2)
  def error_analysis(results)
end
```

## Dependencies and Requirements

### Elixir Dependencies
```elixir
# mix.exs dependencies
{:jason, "~> 1.4"},           # JSON handling
{:csv, "~> 3.0"},             # CSV export
{:table_rex, "~> 3.1.1"},     # Console tables
{:nx, "~> 0.6"},              # Numerical computing and vector operations
{:explorer, "~> 0.7"},        # Data analysis
{:req, "~> 0.4"},             # HTTP requests for external APIs
{:poolboy, "~> 1.5"},         # Worker pool management
```

### Python Interop (for ML models)
```elixir
# For advanced NLP metrics
{:pythonx, "~> 0.1"},         # Python interoperability
{:exla, "~> 0.6"},            # XLA backend for Nx
{:bumblebee, "~> 0.4"},       # Transformer models
```

### External Model Dependencies
- **BERT/RoBERTa**: For semantic similarity
- **Sentence Transformers**: For embeddings
- **NLTK/spaCy**: For text processing
- **SacreBLEU**: For BLEU implementation

## File Structure

```
lib/dspex/evaluation/
├── evaluation.ex                    # Main interface
├── metrics/
│   ├── core.ex                     # Basic metrics (EM, F1)
│   ├── semantic.ex                 # Semantic similarity
│   ├── auto.ex                     # LLM-based evaluation
│   └── specialized.ex              # Domain-specific
├── parallel/
│   ├── evaluator.ex               # Parallel execution
│   ├── worker.ex                  # Worker processes
│   └── progress.ex                # Progress tracking
├── display/
│   ├── table.ex                   # Result tables
│   ├── progress_bar.ex            # Progress display
│   └── export.ex                  # Data export
├── text_processing/
│   ├── normalization.ex           # Text normalization
│   ├── tokenization.ex            # Tokenization
│   └── similarity.ex              # Text similarity
└── auto/
    ├── signatures.ex              # LLM evaluation signatures
    ├── evaluators.ex              # Auto-evaluators
    └── prompt_templates.ex        # Evaluation prompts
```

## Testing Strategy

### Unit Tests
```elixir
# test/dspex/evaluation/
├── metrics/
│   ├── core_test.exs             # Basic metrics tests
│   ├── semantic_test.exs         # Semantic metrics tests
│   └── auto_test.exs             # Auto-evaluation tests
├── parallel_test.exs             # Parallel execution tests
├── display_test.exs              # Display functionality tests
└── integration_test.exs          # End-to-end tests
```

### Property-Based Tests
```elixir
# test/property/evaluation_property_test.exs
defmodule DSPEx.Evaluation.PropertyTest do
  use ExUnitProperties
  
  property "exact match is symmetric"
  property "f1 score is between 0 and 1"
  property "normalized text is idempotent"
end
```

## Migration Path from DSPy

### 1. API Compatibility Layer
```elixir
# lib/dspex/evaluation/compat/dspy.ex
defmodule DSPEx.Evaluation.Compat.DSPy do
  @moduledoc """
  DSPy-compatible evaluation interface for easier migration
  """
  
  def evaluate(program, devset, metric, opts \\ [])
  def answer_exact_match(example, pred, trace \\ nil)
  def answer_passage_match(example, pred, trace \\ nil)
end
```

### 2. Data Format Converters
```elixir
# lib/dspex/evaluation/converters.ex
defmodule DSPEx.Evaluation.Converters do
  def from_dspy_example(dspy_example)
  def to_dspy_format(dspex_result)
  def convert_metric_function(dspy_metric)
end
```

## Performance Considerations

### 1. Concurrency Strategy
- Use `Task.async_stream/3` for CPU-bound metric computation
- GenServer pools for stateful evaluators
- Backpressure handling for large datasets
- Memory-efficient streaming for huge evaluations

### 2. Caching
```elixir
# lib/dspex/evaluation/cache.ex
defmodule DSPEx.Evaluation.Cache do
  def cache_embeddings(texts, model)
  def cache_metric_results(program_hash, devset_hash, metric)
  def invalidate_cache(program)
end
```

### 3. Resource Management
- Memory monitoring for large datasets
- CPU usage balancing
- Timeout management for slow evaluations
- Graceful degradation under resource constraints

## Integration Points with Existing DSPEx

### 1. Program Interface
```elixir
# Extend existing DSPEx.Program
defmodule DSPEx.Program do
  def evaluate(program, devset, metric, opts \\ [])
  def benchmark(program, benchmarks, opts \\ [])
  def compare_programs(programs, devset, metric)
end
```

### 2. Teleprompter Integration
```elixir
# Integration with optimization
defmodule DSPEx.Teleprompter.BootstrapFewShot do
  def evaluate_candidates(candidates, devset, metric)
  def select_best_program(candidates, evaluation_results)
end
```

### 3. Configuration Integration
```elixir
# lib/dspex/config/evaluation.ex
defmodule DSPEx.Config.Evaluation do
  defstruct [
    default_num_workers: 4,
    default_timeout: 30_000,
    cache_embeddings: true,
    progress_refresh_rate: 100
  ]
end
```

## Advanced Features

### 1. Distributed Evaluation
```elixir
# lib/dspex/evaluation/distributed.ex
defmodule DSPEx.Evaluation.Distributed do
  def evaluate_across_nodes(program, devset, metric, nodes)
  def aggregate_distributed_results(results)
end
```

### 2. Real-time Evaluation
```elixir
# lib/dspex/evaluation/streaming.ex
defmodule DSPEx.Evaluation.Streaming do
  def evaluate_stream(program, example_stream, metric)
  def real_time_metrics(evaluation_stream)
end
```

### 3. Evaluation Pipelines
```elixir
# lib/dspex/evaluation/pipeline.ex
defmodule DSPEx.Evaluation.Pipeline do
  def create_pipeline(stages)
  def add_stage(pipeline, stage)
  def run_pipeline(pipeline, program, devset)
end
```

## Conclusion

This integration will provide DSPEx with a comprehensive evaluation system that matches and exceeds DSPy's capabilities. The modular design allows for incremental implementation while maintaining compatibility with existing DSPEx patterns and Elixir/OTP best practices.

Key benefits:
1. **Parallel Processing**: Leverages Elixir's actor model for efficient evaluation
2. **Advanced Metrics**: Includes semantic and LLM-based evaluation methods
3. **Extensibility**: Modular design for easy addition of new metrics
4. **Integration**: Seamless integration with existing DSPEx components
5. **Performance**: Optimized for large-scale evaluation workloads

The implementation should follow Elixir conventions and leverage OTP for robust, fault-tolerant evaluation processes. 

## Dependencies and Requirements

### Elixir Dependencies
```elixir
# mix.exs dependencies
{:jason, "~> 1.4"},           # JSON handling
{:csv, "~> 3.0"},             # CSV export
{:table_rex, "~> 3.1.1"},     # Console tables
{:nx, "~> 0.6"},              # Numerical computing and vector operations
{:explorer, "~> 0.7"},        # Data analysis
{:req, "~> 0.4"},             # HTTP requests for external APIs
{:poolboy, "~> 1.5"},         # Worker pool management
```

### Nx Integration for Advanced Metrics

#### Vector-Based Similarity Metrics
```elixir
# lib/dspex/evaluation/metrics/nx_enhanced.ex
defmodule DSPEx.Evaluation.Metrics.NxEnhanced do
  @moduledoc """
  Nx-powered evaluation metrics for advanced similarity and numerical analysis.
  
  Leverages Nx for high-performance vector operations, embeddings similarity,
  and statistical computations across large evaluation datasets.
  """
  
  import Nx.Defn
  
  @doc """
  Cosine similarity between text embeddings using Nx tensors.
  
  ## Examples
      
      iex> pred_emb = Nx.tensor([0.5, 0.8, 0.2])
      iex> ref_emb = Nx.tensor([0.4, 0.9, 0.1])
      iex> DSPEx.Evaluation.Metrics.NxEnhanced.cosine_similarity(pred_emb, ref_emb)
      0.9746318461970762
  """
  def cosine_similarity(tensor_a, tensor_b) do
    cosine_similarity_impl(tensor_a, tensor_b)
  end
  
  defn cosine_similarity_impl(a, b) do
    dot_product = Nx.dot(a, b)
    norm_a = Nx.LinAlg.norm(a)
    norm_b = Nx.LinAlg.norm(b)
    dot_product / (norm_a * norm_b)
  end
  
  @doc """
  Euclidean distance between embeddings.
  """
  def euclidean_distance(tensor_a, tensor_b) do
    euclidean_distance_impl(tensor_a, tensor_b)
  end
  
  defn euclidean_distance_impl(a, b) do
    diff = Nx.subtract(a, b)
    Nx.LinAlg.norm(diff)
  end
  
  @doc """
  Semantic similarity using embedding vectors.
  Computes cosine similarity and applies configurable thresholding.
  """
  def semantic_similarity(prediction_embedding, reference_embedding, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.7)
    similarity = cosine_similarity(prediction_embedding, reference_embedding)
    
    score = Nx.to_number(similarity)
    passed = score >= threshold
    
    %{
      similarity_score: score,
      threshold: threshold,
      passed: passed,
      similarity_level: classify_similarity_level(score)
    }
  end
  
  @doc """
  Batch similarity computation for efficient evaluation across many examples.
  """
  def batch_similarity(prediction_embeddings, reference_embeddings) do
    # Ensure tensors have compatible shapes
    pred_tensor = normalize_batch_tensor(prediction_embeddings)
    ref_tensor = normalize_batch_tensor(reference_embeddings)
    
    batch_cosine_similarity(pred_tensor, ref_tensor)
  end
  
  defn batch_cosine_similarity(pred_batch, ref_batch) do
    # Compute pairwise cosine similarities
    dot_products = Nx.dot(pred_batch, [0, 1], ref_batch, [1, 0])
    pred_norms = Nx.LinAlg.norm(pred_batch, axes: [1], keep_axes: true)
    ref_norms = Nx.LinAlg.norm(ref_batch, axes: [1], keep_axes: true)
    
    norms_product = Nx.dot(pred_norms, [0, 1], ref_norms, [1, 0])
    dot_products / norms_product
  end
  
  @doc """
  Statistical analysis of evaluation scores using Nx.
  """
  def compute_statistics(scores) when is_list(scores) do
    scores_tensor = Nx.tensor(scores)
    compute_statistics_impl(scores_tensor)
  end
  
  defn compute_statistics_impl(scores) do
    mean = Nx.mean(scores)
    std = Nx.standard_deviation(scores)
    min_val = Nx.reduce_min(scores)
    max_val = Nx.reduce_max(scores)
    median = compute_median(scores)
    
    %{
      mean: mean,
      std: std,
      min: min_val,
      max: max_val,
      median: median,
      count: Nx.size(scores)
    }
  end
  
  defn compute_median(sorted_scores) do
    sorted = Nx.sort(sorted_scores, direction: :asc)
    n = Nx.size(sorted)
    
    # Handle even/odd array sizes
    cond do
      Nx.remainder(n, 2) == 0 ->
        mid1 = Nx.divide(n, 2) - 1
        mid2 = Nx.divide(n, 2)
        (Nx.take(sorted, mid1) + Nx.take(sorted, mid2)) / 2
      
      true ->
        mid = Nx.divide(n, 2)
        Nx.take(sorted, mid)
    end
  end
  
  @doc """
  F1 score computation using Nx for precision/recall calculations.
  """
  def nx_f1_score(predictions, references, opts \\ []) do
    pred_tokens = tokenize_for_nx(predictions, opts)
    ref_tokens = tokenize_for_nx(references, opts)
    
    compute_f1_impl(pred_tokens, ref_tokens)
  end
  
  defn compute_f1_impl(pred_tokens, ref_tokens) do
    # Convert to binary vectors for overlap computation
    intersection = Nx.logical_and(pred_tokens, ref_tokens)
    intersection_count = Nx.sum(intersection)
    
    pred_count = Nx.sum(pred_tokens)
    ref_count = Nx.sum(ref_tokens)
    
    precision = intersection_count / pred_count
    recall = intersection_count / ref_count
    
    f1 = 2 * (precision * recall) / (precision + recall)
    
    %{
      precision: precision,
      recall: recall,
      f1: f1,
      intersection_count: intersection_count,
      pred_count: pred_count,
      ref_count: ref_count
    }
  end
  
  # Helper functions for Nx integration
  
  defp normalize_batch_tensor(embeddings) when is_list(embeddings) do
    embeddings
    |> Enum.map(&ensure_tensor/1)
    |> Nx.stack()
  end
  
  defp ensure_tensor(data) when is_list(data), do: Nx.tensor(data)
  defp ensure_tensor(%Nx.Tensor{} = tensor), do: tensor
  defp ensure_tensor(data), do: Nx.tensor(data)
  
  defp classify_similarity_level(score) when score >= 0.9, do: :very_high
  defp classify_similarity_level(score) when score >= 0.8, do: :high
  defp classify_similarity_level(score) when score >= 0.6, do: :medium
  defp classify_similarity_level(score) when score >= 0.4, do: :low
  defp classify_similarity_level(_), do: :very_low
  
  defp tokenize_for_nx(text, opts) do
    # Simplified tokenization for Nx compatibility
    # In practice, you'd use more sophisticated tokenization
    tokens = String.split(text)
    vocab_size = Keyword.get(opts, :vocab_size, 10000)
    
    # Convert to binary presence vector
    token_ids = Enum.map(tokens, &hash_token_to_id(&1, vocab_size))
    binary_vector = create_binary_vector(token_ids, vocab_size)
    Nx.tensor(binary_vector)
  end
  
  defp hash_token_to_id(token, vocab_size) do
    :erlang.phash2(token, vocab_size)
  end
  
  defp create_binary_vector(token_ids, vocab_size) do
    vector = List.duplicate(0, vocab_size)
    
    Enum.reduce(token_ids, vector, fn id, acc ->
      List.replace_at(acc, id, 1)
    end)
  end
end
```

#### Nx-Powered Parallel Evaluation Engine
```elixir
# lib/dspex/evaluation/nx_parallel_evaluator.ex
defmodule DSPEx.Evaluation.NxParallelEvaluator do
  @moduledoc """
  High-performance parallel evaluation using Nx for batch processing.
  
  Leverages Nx's efficient tensor operations to evaluate multiple
  examples simultaneously with vectorized metric computation.
  """
  
  use GenServer
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def evaluate_batch(examples, metric_fn, opts \\ []) do
    GenServer.call(__MODULE__, {:evaluate_batch, examples, metric_fn, opts}, 60_000)
  end
  
  def init(opts) do
    # Configure Nx backend based on available hardware
    backend = configure_nx_backend(opts)
    
    state = %{
      backend: backend,
      batch_size: Keyword.get(opts, :batch_size, 32),
      parallel_workers: Keyword.get(opts, :parallel_workers, System.schedulers_online())
    }
    
    {:ok, state}
  end
  
  def handle_call({:evaluate_batch, examples, metric_fn, opts}, _from, state) do
    # Process examples in batches for optimal Nx performance
    results = 
      examples
      |> Enum.chunk_every(state.batch_size)
      |> Task.async_stream(
        fn batch -> evaluate_batch_with_nx(batch, metric_fn, state.backend) end,
        max_concurrency: state.parallel_workers,
        timeout: 30_000
      )
      |> Enum.flat_map(fn
        {:ok, batch_results} -> batch_results
        {:exit, reason} -> 
          Logger.error("Batch evaluation failed: #{inspect(reason)}")
          []
      end)
    
    {:reply, {:ok, results}, state}
  end
  
  defp configure_nx_backend(opts) do
    case Keyword.get(opts, :backend, :auto) do
      :auto ->
        # Auto-detect best available backend
        cond do
          nx_backend_available?(:exla) -> {Nx.BinaryBackend, []}
          nx_backend_available?(:torchx) -> {Nx.BinaryBackend, []}
          true -> {Nx.BinaryBackend, []}
        end
      
      backend -> backend
    end
  end
  
  defp nx_backend_available?(backend_name) do
    case Application.spec(backend_name) do
      nil -> false
      _ -> true
    end
  end
  
  defp evaluate_batch_with_nx(examples, metric_fn, backend) do
    # Set Nx backend for this process
    Nx.default_backend(backend)
    
    try do
      # Extract predictions and references
      {predictions, references} = extract_prediction_reference_pairs(examples)
      
      # Convert to Nx tensors if dealing with numerical data
      case detect_data_type(predictions) do
        :numerical -> evaluate_numerical_batch(predictions, references, metric_fn)
        :textual -> evaluate_textual_batch(predictions, references, metric_fn)
        :embeddings -> evaluate_embedding_batch(predictions, references, metric_fn)
      end
    rescue
      error ->
        Logger.error("Nx batch evaluation error: #{inspect(error)}")
        # Fallback to individual evaluation
        Enum.map(examples, fn example ->
          apply(metric_fn, [example.prediction, example.reference])
        end)
    end
  end
  
  defp evaluate_numerical_batch(predictions, references, metric_fn) do
    # Convert to Nx tensors
    pred_tensor = Nx.tensor(predictions)
    ref_tensor = Nx.tensor(references)
    
    # Apply vectorized metric computation
    case Function.info(metric_fn)[:arity] do
      2 -> 
        # Assume metric function can handle tensors
        result = apply(metric_fn, [pred_tensor, ref_tensor])
        Nx.to_flat_list(result)
      
      _ ->
        # Fall back to individual computation
        Enum.zip(predictions, references)
        |> Enum.map(fn {pred, ref} -> apply(metric_fn, [pred, ref]) end)
    end
  end
  
  defp evaluate_embedding_batch(predictions, references, _metric_fn) do
    # Use Nx-powered similarity metrics
    pred_embeddings = Nx.tensor(predictions)
    ref_embeddings = Nx.tensor(references)
    
    similarity_matrix = DSPEx.Evaluation.Metrics.NxEnhanced.batch_similarity(
      pred_embeddings, 
      ref_embeddings
    )
    
    # Extract diagonal (pairwise similarities)
    Nx.to_flat_list(Nx.take_diagonal(similarity_matrix))
  end
  
  defp detect_data_type(data) do
    sample = List.first(data)
    
    cond do
      is_number(sample) or (is_list(sample) and Enum.all?(sample, &is_number/1)) ->
        :numerical
      
      is_list(sample) and length(sample) > 50 and Enum.all?(sample, &is_float/1) ->
        :embeddings
      
      true ->
        :textual
    end
  end
end
```

### Integration with ExLLM for Embeddings

#### Embedding-Enhanced Evaluation
```elixir
# lib/dspex/evaluation/embedding_evaluator.ex
defmodule DSPEx.Evaluation.EmbeddingEvaluator do
  @moduledoc """
  Evaluation using text embeddings with ExLLM and Nx integration.
  
  Combines ExLLM's embedding capabilities with Nx's tensor operations
  for sophisticated semantic similarity evaluation.
  """
  
  @doc """
  Generate embeddings using ExLLM providers that support embeddings.
  """
  def generate_embeddings(texts, opts \\ []) when is_list(texts) do
    provider = Keyword.get(opts, :embedding_provider, :openai)
    model = Keyword.get(opts, :embedding_model, "text-embedding-ada-002")
    
    case ExLLM.configured?(provider) do
      true ->
        # Batch embedding generation
        embeddings = 
          texts
          |> Enum.chunk_every(100)  # API rate limiting
          |> Enum.flat_map(fn chunk ->
            case ExLLM.embeddings(provider, chunk, model: model) do
              {:ok, response} -> response.embeddings
              {:error, _} -> List.duplicate([], length(chunk))
            end
          end)
        
        {:ok, embeddings}
      
      false ->
        {:error, {:provider_not_configured, provider}}
    end
  end
  
  @doc """
  Evaluate using semantic similarity with embeddings.
  """
  def evaluate_with_embeddings(examples, opts \\ []) do
    # Extract texts
    predictions = Enum.map(examples, & &1.prediction)
    references = Enum.map(examples, & &1.reference)
    
    with {:ok, pred_embeddings} <- generate_embeddings(predictions, opts),
         {:ok, ref_embeddings} <- generate_embeddings(references, opts) do
      
      # Convert to Nx tensors
      pred_tensor = Nx.tensor(pred_embeddings)
      ref_tensor = Nx.tensor(ref_embeddings)
      
      # Compute pairwise similarities
      similarities = 
        pred_tensor
        |> Nx.zip_with(ref_tensor, fn pred_emb, ref_emb ->
          DSPEx.Evaluation.Metrics.NxEnhanced.cosine_similarity(pred_emb, ref_emb)
        end)
      
      # Compute aggregate statistics
      stats = DSPEx.Evaluation.Metrics.NxEnhanced.compute_statistics(
        Nx.to_flat_list(similarities)
      )
      
      {:ok, %{
        individual_similarities: Nx.to_flat_list(similarities),
        statistics: stats,
        threshold_analysis: analyze_threshold_performance(similarities, opts)
      }}
    end
  end
  
  defp analyze_threshold_performance(similarities, opts) do
    thresholds = Keyword.get(opts, :thresholds, [0.5, 0.6, 0.7, 0.8, 0.9])
    
    Enum.map(thresholds, fn threshold ->
      passed_count = 
        similarities
        |> Nx.greater_equal(threshold)
        |> Nx.sum()
        |> Nx.to_number()
      
      total_count = Nx.size(similarities)
      pass_rate = passed_count / total_count
      
      %{
        threshold: threshold,
        passed_count: passed_count,
        total_count: total_count,
        pass_rate: pass_rate
      }
    end)
  end
end
```

### Nx Best Practices for DSPEx Evaluation

#### Development Guidelines
```elixir
# config/config.exs - Nx Configuration
config :nx,
  # Use BinaryBackend for development (CPU-only, no compilation)
  default_backend: {Nx.BinaryBackend, []},
  # Optional: Configure for specific use cases
  default_options: [
    type: {:f, 32},  # Use 32-bit floats for memory efficiency
    names: [:batch, :sequence, :features]  # Named dimensions for clarity
  ]

# config/prod.exs - Production optimization
config :nx,
  # Consider EXLA for production performance (when available)
  default_backend: {Nx.BinaryBackend, []},  # Keep simple for now
  default_options: [type: {:f, 32}]

# config/test.exs - Testing configuration  
config :nx,
  default_backend: {Nx.BinaryBackend, []},  # Deterministic for testing
  default_options: [type: {:f, 64}]  # Higher precision for test accuracy
```

#### Performance Optimization Patterns
```elixir
# lib/dspex/evaluation/nx_optimizations.ex
defmodule DSPEx.Evaluation.NxOptimizations do
  @moduledoc """
  Performance optimization patterns for Nx-based evaluation.
  
  Best practices for memory management, tensor operations,
  and efficient numerical computation in evaluation pipelines.
  """
  
  @doc """
  Memory-efficient batch processing with chunking.
  """
  def memory_efficient_evaluation(large_dataset, metric_fn, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 1000)
    
    large_dataset
    |> Stream.chunk_every(chunk_size)
    |> Stream.map(fn chunk ->
      # Process chunk and immediately release memory
      result = process_chunk_with_nx(chunk, metric_fn)
      
      # Force garbage collection after large tensor operations
      :erlang.garbage_collect()
      
      result
    end)
    |> Enum.to_list()
    |> List.flatten()
  end
  
  @doc """
  Tensor shape validation for consistent operations.
  """
  def validate_tensor_shapes(tensors, expected_shape) do
    Enum.all?(tensors, fn tensor ->
      Nx.shape(tensor) == expected_shape
    end)
  end
  
  @doc """
  Efficient similarity matrix computation with memory management.
  """
  def compute_similarity_matrix(embeddings_a, embeddings_b, opts \\ []) do
    # Ensure tensors are properly shaped
    a_tensor = normalize_embedding_tensor(embeddings_a)
    b_tensor = normalize_embedding_tensor(embeddings_b)
    
    # Use chunked computation for large matrices to avoid memory issues
    chunk_size = Keyword.get(opts, :chunk_size, 100)
    
    if Nx.axis_size(a_tensor, 0) > chunk_size do
      compute_chunked_similarity_matrix(a_tensor, b_tensor, chunk_size)
    else
      DSPEx.Evaluation.Metrics.NxEnhanced.batch_similarity(a_tensor, b_tensor)
    end
  end
  
  defp compute_chunked_similarity_matrix(a_tensor, b_tensor, chunk_size) do
    a_chunks = chunk_tensor(a_tensor, chunk_size)
    
    a_chunks
    |> Enum.map(fn chunk ->
      DSPEx.Evaluation.Metrics.NxEnhanced.batch_similarity(chunk, b_tensor)
    end)
    |> Nx.concatenate(axis: 0)
  end
  
  defp chunk_tensor(tensor, chunk_size) do
    total_size = Nx.axis_size(tensor, 0)
    
    0..(total_size - 1)
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(fn indices ->
      Nx.take(tensor, Nx.tensor(indices), axis: 0)
    end)
  end
  
  defp normalize_embedding_tensor(embeddings) when is_list(embeddings) do
    embeddings
    |> Enum.map(&Nx.tensor/1)
    |> Nx.stack()
  end
  
  defp normalize_embedding_tensor(%Nx.Tensor{} = tensor), do: tensor
end
``` 