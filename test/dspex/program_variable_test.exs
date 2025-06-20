defmodule DSPEx.Program.VariableTest do
  use ExUnit.Case, async: true
  
  alias DSPEx.Program
  alias ElixirML.Variable

  # Test program with variables
  defmodule TestProgram do
    use DSPEx.Program

    # Declare test variables
    variable :temperature, :float, range: {0.0, 2.0}, default: 0.7
    variable :provider, :choice, choices: [:openai, :anthropic], default: :openai
    variable :max_tokens, :integer, range: {50, 1000}, default: 100

    defstruct [:signature, :client, :variable_space]

    @impl DSPEx.Program
    def forward(program, inputs, opts) do
      # Resolve variables for testing
      resolved = Program.resolve_variables(program, opts)
      {:ok, %{resolved_variables: resolved, inputs: inputs}}
    end
  end

  # Test program without variables
  defmodule SimpleProgram do
    use DSPEx.Program

    defstruct [:signature, :client]

    @impl DSPEx.Program
    def forward(_program, inputs, _opts) do
      {:ok, %{simple: true, inputs: inputs}}
    end
  end

  describe "variable declaration" do
    test "programs can declare variables" do
      variables = TestProgram.__variables__()
      
      assert %{
        temperature: %Variable{name: :temperature, type: :float},
        provider: %Variable{name: :provider, type: :choice},
        max_tokens: %Variable{name: :max_tokens, type: :integer}
      } = variables
    end

    test "programs without variables have empty variable map" do
      variables = SimpleProgram.__variables__()
      assert variables == %{}
    end
  end

  describe "variable space creation" do
    test "creates variable space from declared variables" do
      space = Program.create_variable_space(TestProgram)
      
      assert %ElixirML.Variable.Space{} = space
      assert Map.has_key?(space.variables, :temperature)
      assert Map.has_key?(space.variables, :provider)
      assert Map.has_key?(space.variables, :max_tokens)
    end

    test "creates standard ML config for programs without variables" do
      space = Program.create_variable_space(SimpleProgram)
      
      assert %ElixirML.Variable.Space{} = space
      # Should have standard ML variables
      assert Map.has_key?(space.variables, :provider)
      assert Map.has_key?(space.variables, :temperature)
    end
  end

  describe "variable resolution" do
    test "resolves variables from options" do
      program = %TestProgram{
        signature: TestSignature,
        client: :test,
        variable_space: Program.create_variable_space(TestProgram)
      }
      
      opts = [variables: %{temperature: 0.9, provider: :anthropic}]
      resolved = Program.resolve_variables(program, opts)
      
      assert resolved.temperature == 0.9
      assert resolved.provider == :anthropic
      # Should use default for unspecified variables
      assert resolved.max_tokens == 100
    end

    test "handles invalid variable values gracefully" do
      program = %TestProgram{
        signature: TestSignature,
        client: :test,
        variable_space: Program.create_variable_space(TestProgram)
      }
      
      # Invalid temperature (out of range)
      opts = [variables: %{temperature: 5.0, provider: :invalid}]
      resolved = Program.resolve_variables(program, opts)
      
      # Should fall back to defaults for invalid values
      assert is_map(resolved)
    end

    test "returns empty config for program without variable space" do
      program = %SimpleProgram{signature: TestSignature, client: :test}
      opts = [variables: %{temperature: 0.9}]
      
      resolved = Program.resolve_variables(program, opts)
      assert resolved == %{}
    end
  end

  describe "program execution with variables" do
    test "forwards resolved variables to program implementation" do
      program = %TestProgram{
        signature: TestSignature,
        client: :test,
        variable_space: Program.create_variable_space(TestProgram)
      }
      
      inputs = %{question: "test"}
      opts = [variables: %{temperature: 0.8, provider: :anthropic}]
      
      {:ok, result} = Program.forward(program, inputs, opts)
      
      assert %{resolved_variables: resolved, inputs: ^inputs} = result
      assert resolved.temperature == 0.8
      assert resolved.provider == :anthropic
    end

    test "works with programs that don't use variables" do
      program = %SimpleProgram{signature: TestSignature, client: :test}
      inputs = %{question: "test"}
      
      {:ok, result} = Program.forward(program, inputs, [])
      
      assert %{simple: true, inputs: ^inputs} = result
    end
  end

  describe "telemetry integration" do
    test "includes variable information in telemetry" do
      program = %TestProgram{
        signature: TestSignature,
        client: :test,
        variable_space: Program.create_variable_space(TestProgram)
      }
      
      # Capture telemetry events
      test_pid = self()
      :telemetry.attach_many(
        "test-variables",
        [[:dspex, :program, :forward, :start]],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      inputs = %{question: "test"}
      opts = [variables: %{temperature: 0.8}]
      
      Program.forward(program, inputs, opts)
      
      # Should receive telemetry with variable information
      assert_receive {:telemetry, [:dspex, :program, :forward, :start], _measurements, metadata}
      assert metadata.has_variables == true
      assert metadata.variable_count > 0

      :telemetry.detach("test-variables")
    end
  end

  # Mock signature for testing
  defmodule TestSignature do
    def input_fields, do: [:question]
    def output_fields, do: [:answer]
  end
end