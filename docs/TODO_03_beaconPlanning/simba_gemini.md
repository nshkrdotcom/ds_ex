Of course. Integrating a new optimizer like `dspy.BEACON` into your Elixir `DSPEx` codebase is an excellent way to enhance your program's performance. BEACON, as a prompt optimizer, focuses on finding the best instructions for your program to maximize its accuracy on a given task.

Here is a comprehensive plan and implementation for integrating `dspy.beacon` into your Elixir codebase. This integration will create a new teleprompter, `DSPEx.Teleprompter.BEACON`, and make the necessary adjustments to the core `DSPEx` modules to support instruction-based optimization.

### Integration Strategy Summary

1.  **Enhance `DSPEx.Predict` and `DSPEx.Adapter`**: We will modify these core modules to allow for runtime overriding of a program's instructions. This is a crucial prerequisite for any instruction-based optimizer like BEACON.
2.  **Create `DSPEx.Teleprompter.BEACON`**: We will implement a new teleprompter module that embodies the logic of BEACON. This module will:
    *   Use a powerful "meta-model" (like GPT-4 or Gemini) to generate several new instruction candidates for your program.
    *   Concurrently evaluate each candidate instruction by running the program against your training data.
    *   Select the best-performing instruction based on your specified metric.
    *   Return a new, optimized version of your program compiled with the winning instruction.
3.  **Provide Clear Documentation and Usage**: The new module will be fully documented, explaining its purpose, options, and how it fits into the `DSPEx` ecosystem.

---

### Step 1: Modify Existing Files

First, we need to update `dspex/predict.ex` and `dspex/adapter.ex` to support instruction overriding.

#### File to Modify: `dspex/predict.ex`

We'll add an `:instruction_override` field to the `DSPEx.Predict` struct and ensure it's used during the `forward` pass.

```diff
--- a/dspex/predict.ex
+++ b/dspex/predict.ex
@@ -16,13 +16,14 @@
 
   use DSPEx.Program
 
-  defstruct [:signature, :client, :adapter, demos: []]
+  defstruct [:signature, :client, :adapter, demos: [], instruction_override: nil]
 
   @type t :: %__MODULE__{
           signature: module(),
           client: atom() | map(),
           adapter: module() | nil,
-          demos: [map()]
+          demos: [map()],
+          instruction_override: String.t() | nil
         }
   @type signature :: module()
   @type inputs :: map()
@@ -43,12 +44,14 @@
   - `:adapter` - Adapter module (default: nil, uses DSPEx.Adapter fallback)
   - `:demos` - List of demonstration examples
 
-  """
+  """ 
   @spec new(signature(), atom() | map(), keyword() | map()) :: t()
   def new(signature, client, opts \\ []) do
     %__MODULE__{
       signature: signature,
       client: client,
       adapter: get_option(opts, :adapter, nil),
-      demos: get_option(opts, :demos, [])
+      demos: get_option(opts, :demos, []),
+      instruction_override: get_option(opts, :instruction_override, nil)
     }
   end
 
@@ -62,8 +65,11 @@
   def forward(program, inputs, opts) when is_struct(program, __MODULE__) do
     correlation_id =
       Keyword.get(opts, :correlation_id) || Foundation.Utils.generate_correlation_id()
-
-    with {:ok, messages} <- format_messages(program, inputs, correlation_id),
+ 
+    format_opts =
+      if program.instruction_override, do: [instruction_override: program.instruction_override], else: []
+
+    with {:ok, messages} <- format_messages(program, inputs, correlation_id, format_opts),
          {:ok, response} <- make_request(program, messages, opts, correlation_id),
          {:ok, outputs} <- parse_response(program, response, correlation_id) do
       {:ok, outputs}
@@ -82,7 +88,7 @@
 
   # Private helper functions for Program implementation
 
-  defp format_messages(program, inputs, correlation_id) do
+  defp format_messages(program, inputs, correlation_id, opts) do
     start_time = System.monotonic_time()
 
     :telemetry.execute(
@@ -94,11 +100,11 @@
       }
     )
 
-    # Use adapter to format messages with signature and demos
+    # Use adapter to format messages with signature, demos and options (for overrides)
     result =
-      if program.adapter && function_exported?(program.adapter, :format_messages, 3) do
-        program.adapter.format_messages(program.signature, program.demos, inputs)
+      if program.adapter && function_exported?(program.adapter, :format_messages, 4) do
+        program.adapter.format_messages(program.signature, program.demos, inputs, opts)
       else
         # Fallback to basic adapter
         DSPEx.Adapter.format_messages(program.signature, inputs)

```

#### File to Modify: `dspex/adapter.ex`

Here, we'll update the `Adapter` to accept and use the `instruction_override` option.

```diff
--- a/dspex/adapter.ex
+++ b/dspex/adapter.ex
@@ -21,11 +21,11 @@
   - `{:error, reason}` - Error with validation or formatting
 
   """
-  @spec format_messages(signature(), inputs()) :: {:ok, messages()} | {:error, atom()}
-  def format_messages(signature, inputs) do
+  @spec format_messages(signature(), inputs(), keyword()) :: {:ok, messages()} | {:error, atom()}
+  def format_messages(signature, inputs, opts \\ []) do
     with {:ok, input_fields} <- get_input_fields(signature),
          {:ok, validated_inputs} <- validate_inputs(input_fields, inputs),
-         {:ok, prompt} <- build_prompt(signature, validated_inputs) do
+         {:ok, prompt} <- build_prompt(signature, validated_inputs, opts) do
       messages = [%{role: "user", content: prompt}]
       {:ok, messages}
     else
@@ -91,15 +91,16 @@
     end
   end
 
-  @spec build_prompt(signature(), inputs()) ::
+  @spec build_prompt(signature(), inputs(), keyword()) ::
           {:ok, String.t()} | {:error, :prompt_generation_failed}
-  defp build_prompt(signature, inputs) do
+  defp build_prompt(signature, inputs, opts) do
     try do
-      # Try to get signature description for context
+      # Use instruction override if provided, otherwise fall back to signature description
       description =
-        if function_exported?(signature, :description, 0) do
-          signature.description()
-        else
-          "Please process the following input"
+        Keyword.get(opts, :instruction_override) ||
+          if function_exported?(signature, :description, 0) do
+            signature.description()
+          else
+            "Please process the following input"
         end
 
       # Build a simple prompt with the inputs

```

---

### Step 2: Create the BEACON Teleprompter

Now, create a new file for our optimizer. This module will contain the core logic for generating and testing new instructions.

#### New File: `dspex/teleprompter/beacon.ex`

```elixir
defmodule DSPEx.Teleprompter.BEACON do
  @moduledoc """
  A teleprompter for instruction optimization using a meta-learning approach.

  BEACON (Simple Instruction Meta-learning and Bootstrapping Algorithm) generates
  and evaluates multiple instruction candidates for a given program to find the
  one that performs best on a training dataset.

  It follows these steps:
  1. **Propose**: A powerful "meta-model" generates new instruction candidates based on the original instruction and examples from the training set.
  2. **Evaluate**: Each candidate instruction is used to create a temporary version of the student program. This program is then evaluated against the training set using the provided metric.
  3. **Select**: The instruction that results in the highest evaluation score is chosen.
  4. **Compile**: A new, optimized program is returned, configured with the best-performing instruction.

  ## Usage

  The `teacher` program argument in `compile/5` is ignored by this teleprompter,
  as it optimizes a single `student` program. The student program must have an
  `:instruction_override` field in its struct (like `DSPEx.Predict`).

  ## Options

  - `:num_candidates` (integer): The number of new instructions to generate. Default: `5`.
  - `:meta_client` (atom): The `DSPEx.Client` to use for the meta-model (e.g., `:openai` or `:gemini`). Default: `:gemini`.
  - `:meta_model_config` (map): Specific options for the meta-model, like `{model: "gpt-4-turbo"}`. Default: `%{}`.
  - `:max_concurrency` (integer): Max concurrency for evaluating candidates. Default: `10`.
  - `:progress_callback` (function): A function to call with progress updates.
  """
  @behaviour DSPEx.Teleprompter

  alias DSPEx.{Evaluate, Example, Predict, Program, Signature}
  require Logger

  defstruct num_candidates: 5,
            meta_client: :gemini,
            meta_model_config: %{},
            max_concurrency: 10,
            progress_callback: nil

  @type t :: %__MODULE__{
          num_candidates: pos_integer(),
          meta_client: atom(),
          meta_model_config: map(),
          max_concurrency: pos_integer(),
          progress_callback: (map() -> :ok) | nil
        }

  # The meta-signature for generating new instructions. We ask an LLM to act as an optimizer.
  defmodule MetaSignature do
    @moduledoc """
    You are an expert prompt engineer. Your task is to rewrite a given instruction to improve a language model's performance on a specific task.
    You will be given the original instruction and a few examples of the task.
    Generate a list of diverse, high-quality alternative instructions. The instructions should be clear, direct, and guide the model effectively.
    Format the output as a numbered list of instructions, separated by newlines.
    """

    use Signature, "original_instruction, examples -> new_instructions"
  end

  @doc "Creates a new BEACON teleprompter."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl DSPEx.Teleprompter
  def compile(student, _teacher, trainset, metric_fn, opts \\ []) do
    config = struct(__MODULE__, opts)

    with {:ok, _} <- validate_student(student),
         {:ok, original_instruction} <- get_original_instruction(student),
         {:ok, candidates} <- propose_instructions(original_instruction, trainset, config),
         {:ok, best_program} <-
           evaluate_candidates(student, candidates, trainset, metric_fn, config) do
      report_progress(config.progress_callback, %{
        phase: :done,
        message: "BEACON optimization complete.",
        best_instruction: best_program.instruction_override
      })

      {:ok, best_program}
    else
      {:error, reason} ->
        Logger.error("BEACON optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_student(%{__struct__: struct} = student) do
    if Map.has_key?(student, :instruction_override) and Program.implements_program?(struct) do
      :ok
    else
      {:error,
       "Student program must be a DSPEx.Program with an :instruction_override field (e.g., DSPEx.Predict)"}
    end
  end

  defp get_original_instruction(%{signature: signature}) do
    if function_exported?(signature, :instructions, 0) do
      {:ok, signature.instructions()}
    else
      {:error, "Student program's signature must provide instructions."}
    end
  end

  defp propose_instructions(original_instruction, trainset, config) do
    report_progress(config.progress_callback, %{
      phase: :propose,
      message: "Generating instruction candidates with meta-model..."
    })

    # Use a few examples from the trainset to guide the meta-model
    example_subset =
      trainset
      |> Enum.take(3)
      |> Enum.map(&Example.to_dict/1)
      |> inspect()

    meta_program =
      Predict.new(MetaSignature, config.meta_client,
        model: config.meta_model_config[:model],
        temperature: 0.7
      )

    inputs = %{
      original_instruction: original_instruction,
      examples: example_subset
    }

    case Program.forward(meta_program, inputs) do
      {:ok, %{new_instructions: new_instructions}} ->
        # Parse the numbered list of instructions
        candidates =
          new_instructions
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(not String.starts_with?(&1, "```")))
          |> Enum.map(&Regex.replace(~r/^\d+\.\s*/, &1, ""))
          |> Enum.filter(&(&1 != ""))

        # Include the original instruction as a baseline
        all_candidates = [original_instruction | candidates] |> Enum.uniq()

        report_progress(config.progress_callback, %{
          phase: :propose_done,
          message: "Generated #{length(all_candidates)} unique instruction candidates."
        })

        {:ok, all_candidates}

      {:error, reason} ->
        {:error, {:meta_program_failed, reason}}
    end
  end

  defp evaluate_candidates(student, candidates, trainset, metric_fn, config) do
    report_progress(config.progress_callback, %{
      phase: :evaluate,
      message: "Evaluating #{length(candidates)} candidates...",
      total: length(candidates)
    })

    results =
      candidates
      |> Enum.with_index()
      |> Task.async_stream(
        fn {instruction, index} ->
          # Create a temporary program with the new instruction
          candidate_program = %{student | instruction_override: instruction}

          # Evaluate its performance
          case Evaluate.run(candidate_program, trainset, metric_fn) do
            {:ok, %{score: score}} ->
              report_progress(config.progress_callback, %{
                phase: :evaluate_progress,
                completed: index + 1,
                total: length(candidates),
                score: score,
                instruction: instruction
              })

              {score, candidate_program}

            {:error, reason} ->
              Logger.warning(
                "Evaluation failed for an instruction candidate: #{inspect(reason)}"
              )

              # Assign a score of 0 for failed evaluations
              {0.0, candidate_program}
          end
        end,
        max_concurrency: config.max_concurrency,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    if Enum.empty?(results) do
      {:error, :all_candidate_evaluations_failed}
    else
      # Select the program with the highest score
      {_best_score, best_program} = Enum.max_by(results, fn {score, _program} -> score end)
      {:ok, best_program}
    end
  end

  defp report_progress(nil, _), do: :ok

  defp report_progress(callback, progress) when is_function(callback, 1) do
    callback.(progress)
  end
end
```

### Step 3: How to Use the New BEACON Optimizer

With these changes in place, you can now use `DSPEx.Teleprompter.BEACON` to optimize any program that has an `:instruction_override` field, such as `DSPEx.Predict`.

Here is a complete usage example:

```elixir
# 1. Define your signature and a program to optimize.
defmodule QASignature do
  @moduledoc "Answer the following question." # Initial, simple instruction
  use DSPEx.Signature, "question -> answer"
end

# The program we want to improve.
student_program = DSPEx.Predict.new(QASignature, :openai)

# 2. Prepare your training data and metric.
trainset = [
  DSPEx.Example.new(%{question: "What is the capital of France?", answer: "Paris"}),
  DSPEx.Example.new(%{question: "Who wrote Hamlet?", answer: "William Shakespeare"})
  # ... more examples
]

metric_fn = fn example, prediction ->
  if String.contains?(prediction.answer, example.data.answer), do: 1.0, else: 0.0
end

# 3. Initialize and run the BEACON optimizer.
beacon_teleprompter = DSPEx.Teleprompter.BEACON.new(
  num_candidates: 8,
  meta_client: :openai, # Use a powerful model for generating instructions
  meta_model_config: %{model: "gpt-4-turbo"},
  progress_callback: &IO.inspect/1
)

# The `teacher` argument is ignored by BEACON. We pass the student program again.
case beacon_teleprompter.compile(student_program, student_program, trainset, metric_fn) do
  {:ok, optimized_program} ->
    IO.puts("Optimization successful!")
    IO.puts("Original Instruction: #{QASignature.instructions()}")
    IO.puts("Optimized Instruction: #{optimized_program.instruction_override}")

    # 4. Use the optimized program for inference.
    inputs = %{question: "What is the largest planet in our solar system?"}
    {:ok, result} = DSPEx.Program.forward(optimized_program, inputs)
    IO.inspect(result) # The program will now use the new, better instruction.

  {:error, reason} ->
    IO.puts("Optimization failed: #{inspect(reason)}")
end
```

This comprehensive integration provides a powerful new capability to your `DSPEx` framework, allowing you to systematically improve the performance of your AI programs by finding better natural language instructions.
