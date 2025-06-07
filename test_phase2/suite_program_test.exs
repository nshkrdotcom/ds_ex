defmodule DSPEx.ProgramSuiteTest do
  use ExUnit.Case, async: false
  
  @moduletag :phase2_features

  defmodule QASignature do
    use DSPEx.Signature, "question -> answer"
  end

  defmodule ChainOfThoughtSignature do
    use DSPEx.Signature, "question -> reasoning, answer"
  end

  defmodule MockClient do
    def request(_client, request) do
      # Return different responses based on signature used
      cond do
        String.contains?(Jason.encode!(request), "reasoning") ->
          {:ok, %{
            choices: [%{message: %{content: "[[ ## reasoning ## ]]\nLet me think step by step.\n[[ ## answer ## ]]\n42"}}],
            usage: %{prompt_tokens: 15, completion_tokens: 8}
          }}

        true ->
          {:ok, %{
            choices: [%{message: %{content: "[[ ## answer ## ]]\n42"}}],
            usage: %{prompt_tokens: 10, completion_tokens: 3}
          }}
      end
    end
  end

  defmodule SimpleProgram do
    @behaviour DSPEx.Program

    defstruct [:predict, :name]

    def new(signature, client, name \\ "SimpleProgram") do
      predict = DSPEx.Predict.new(signature, client: client)
      %__MODULE__{predict: predict, name: name}
    end

    @impl DSPEx.Program
    def forward(%__MODULE__{predict: predict}, inputs) do
      DSPEx.Predict.forward(predict, inputs)
    end

    @impl DSPEx.Program
    def named_predictors(%__MODULE__{predict: predict, name: name}) do
      [{name, predict}]
    end

    @impl DSPEx.Program
    def update_predictor(%__MODULE__{} = program, name, new_predict) do
      if program.name == name do
        %{program | predict: new_predict}
      else
        program
      end
    end
  end

  defmodule ChainOfThoughtProgram do
    @behaviour DSPEx.Program

    defstruct [:cot_predict, :answer_predict]

    def new(client) do
      cot_predict = DSPEx.Predict.new(ChainOfThoughtSignature, client: client)
      answer_predict = DSPEx.Predict.new(QASignature, client: client)

      %__MODULE__{
        cot_predict: cot_predict,
        answer_predict: answer_predict
      }
    end

    @impl DSPEx.Program
    def forward(%__MODULE__{cot_predict: cot_predict}, inputs) do
      # Use chain of thought reasoning
      DSPEx.Predict.forward(cot_predict, inputs)
    end

    @impl DSPEx.Program
    def named_predictors(%__MODULE__{cot_predict: cot, answer_predict: ans}) do
      [
        {"cot_predict", cot},
        {"answer_predict", ans}
      ]
    end

    @impl DSPEx.Program
    def update_predictor(%__MODULE__{} = program, name, new_predict) do
      case name do
        "cot_predict" -> %{program | cot_predict: new_predict}
        "answer_predict" -> %{program | answer_predict: new_predict}
        _ -> program
      end
    end
  end

  setup do
    {:ok, client} = start_supervised({DSPEx.Client, %{
      api_key: "test",
      model: "test",
      adapter: MockClient
    }})

    %{client: client}
  end

  describe "program behavior implementation" do
    test "simple program implements required callbacks", %{client: client} do
      program = SimpleProgram.new(QASignature, client)

      # Test forward
      result = DSPEx.Program.forward(program, %{question: "What is life?"})
      assert {:ok, prediction} = result
      assert prediction.answer == "42"

      # Test named_predictors
      predictors = DSPEx.Program.named_predictors(program)
      assert length(predictors) == 1
      assert [{"SimpleProgram", _predict}] = predictors

      # Test update_predictor
      new_predict = DSPEx.Predict.new(QASignature, client: client)
      updated_program = DSPEx.Program.update_predictor(program, "SimpleProgram", new_predict)
      assert updated_program.predict == new_predict
    end

    test "chain of thought program works correctly", %{client: client} do
      program = ChainOfThoughtProgram.new(client)

      result = DSPEx.Program.forward(program, %{question: "What is 2+2?"})

      assert {:ok, prediction} = result
      assert prediction.reasoning == "Let me think step by step."
      assert prediction.answer == "42"
    end
  end

  describe "program composition" do
    defmodule ComposedProgram do
      @behaviour DSPEx.Program

      defstruct [:analyzer, :answerer]

      def new(client) do
        analyzer = SimpleProgram.new(QASignature, client, "analyzer")
        answerer = SimpleProgram.new(QASignature, client, "answerer")

        %__MODULE__{analyzer: analyzer, answerer: answerer}
      end

      @impl DSPEx.Program
      def forward(%__MODULE__{analyzer: analyzer, answerer: answerer}, inputs) do
        # First analyze the question
        case DSPEx.Program.forward(analyzer, inputs) do
          {:ok, analysis} ->
            # Then generate final answer based on analysis
            enhanced_inputs = Map.put(inputs, :context, analysis.answer)
            DSPEx.Program.forward(answerer, enhanced_inputs)

          error -> error
        end
      end

      @impl DSPEx.Program
      def named_predictors(%__MODULE__{analyzer: analyzer, answerer: answerer}) do
        DSPEx.Program.named_predictors(analyzer) ++
        DSPEx.Program.named_predictors(answerer)
      end

      @impl DSPEx.Program
      def update_predictor(%__MODULE__{} = program, name, new_predict) do
        cond do
          name in Enum.map(DSPEx.Program.named_predictors(program.analyzer), &elem(&1, 0)) ->
            updated_analyzer = DSPEx.Program.update_predictor(program.analyzer, name, new_predict)
            %{program | analyzer: updated_analyzer}

          name in Enum.map(DSPEx.Program.named_predictors(program.answerer), &elem(&1, 0)) ->
            updated_answerer = DSPEx.Program.update_predictor(program.answerer, name, new_predict)
            %{program | answerer: updated_answerer}

          true -> program
        end
      end
    end

    test "composed program chains sub-programs", %{client: client} do
      program = ComposedProgram.new(client)

      result = DSPEx.Program.forward(program, %{question: "Complex question"})

      assert {:ok, prediction} = result
      assert prediction.answer == "42"
    end

    test "composed program exposes all named predictors", %{client: client} do
      program = ComposedProgram.new(client)

      predictors = DSPEx.Program.named_predictors(program)

      assert length(predictors) == 2
      predictor_names = Enum.map(predictors, &elem(&1, 0))
      assert "analyzer" in predictor_names
      assert "answerer" in predictor_names
    end
  end

  describe "program state management" do
    test "programs can save and load state", %{client: client} do
      program = SimpleProgram.new(QASignature, client)
      demo = DSPEx.Example.new(%{question: "Test", answer: "Response"})

      # Add demo to program
      updated_predict = DSPEx.Predict.add_demo(program.predict, demo)
      program_with_demo = %{program | predict: updated_predict}

      # Save state
      state = DSPEx.Program.save_state(program_with_demo)

      # Load state into new program
      new_program = SimpleProgram.new(QASignature, client)
      loaded_program = DSPEx.Program.load_state(new_program, state)

      assert length(loaded_program.predict.demos) == 1
      assert hd(loaded_program.predict.demos).question == "Test"
    end

    test "programs can be reset to initial state", %{client: client} do
      program = SimpleProgram.new(QASignature, client)
      demo = DSPEx.Example.new(%{question: "Test", answer: "Response"})

      # Modify program
      updated_predict = DSPEx.Predict.add_demo(program.predict, demo)
      modified_program = %{program | predict: updated_predict}

      # Reset
      reset_program = DSPEx.Program.reset(modified_program)

      assert length(reset_program.predict.demos) == 0
    end
  end

  describe "program metrics and tracing" do
    test "programs track usage statistics", %{client: client} do
      program = SimpleProgram.new(QASignature, client)

      {:ok, prediction} = DSPEx.Program.forward(program, %{question: "Test"})

      assert prediction.usage.prompt_tokens > 0
      assert prediction.usage.completion_tokens > 0
    end

    test "programs support tracing execution" do
      # This would test execution tracing functionality
      # Implementation depends on tracing system design
    end
  end
end
