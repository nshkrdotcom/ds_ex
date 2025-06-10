defmodule DSPEx.OptimizedProgramTest do
  use ExUnit.Case, async: true

  alias DSPEx.{OptimizedProgram, Example}

  # Mock program for testing
  defmodule MockProgram do
    use DSPEx.Program

    # No demos field - should use options
    defstruct [:name]

    @impl true
    def forward(%__MODULE__{name: name}, inputs, opts) do
      demos = Keyword.get(opts, :demos, [])

      result = %{
        program_name: name,
        input_keys: Map.keys(inputs),
        demo_count: length(demos)
      }

      {:ok, result}
    end
  end

  defmodule MockProgramWithDemos do
    use DSPEx.Program

    defstruct [:name, :demos]

    @impl true
    def forward(%__MODULE__{name: name, demos: demos}, inputs, _opts) do
      result = %{
        program_name: name,
        input_keys: Map.keys(inputs),
        demo_count: length(demos || [])
      }

      {:ok, result}
    end
  end

  setup do
    program = %MockProgram{name: "test_program"}
    program_with_demos = %MockProgramWithDemos{name: "demo_program", demos: []}

    demos = [
      Example.new(%{question: "What is 2+2?", answer: "4", __id: 1})
      |> Example.with_inputs([:question]),
      Example.new(%{question: "What is 3+3?", answer: "6", __id: 2})
      |> Example.with_inputs([:question])
    ]

    %{
      program: program,
      program_with_demos: program_with_demos,
      demos: demos
    }
  end

  describe "new/3" do
    test "creates optimized program with required fields", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      assert %OptimizedProgram{} = optimized
      assert optimized.program == program
      assert optimized.demos == demos
      assert Map.has_key?(optimized.metadata, :optimized_at)
      assert optimized.metadata.demo_count == 2
    end

    test "creates optimized program with custom metadata", %{program: program, demos: demos} do
      custom_metadata = %{optimizer: "BootstrapFewShot", version: "1.0"}
      optimized = OptimizedProgram.new(program, demos, custom_metadata)

      assert optimized.metadata.optimizer == "BootstrapFewShot"
      assert optimized.metadata.version == "1.0"
      assert Map.has_key?(optimized.metadata, :optimized_at)
      assert optimized.metadata.demo_count == 2
    end
  end

  describe "forward/3" do
    test "forwards to program without native demo support", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)
      inputs = %{question: "What is 5+5?"}

      {:ok, result} = OptimizedProgram.forward(optimized, inputs, [])

      assert result.program_name == "test_program"
      # Demos passed through options
      assert result.demo_count == 2
    end

    test "forwards to program with native demo support", %{
      program_with_demos: program,
      demos: demos
    } do
      optimized = OptimizedProgram.new(program, demos)
      inputs = %{question: "What is 5+5?"}

      {:ok, result} = OptimizedProgram.forward(optimized, inputs)

      assert result.program_name == "demo_program"
      # Demos set directly on program
      assert result.demo_count == 2
    end

    test "passes through additional options", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)
      inputs = %{question: "What is 5+5?"}

      {:ok, result} = OptimizedProgram.forward(optimized, inputs, timeout: 30_000)

      # Should still work with additional options
      assert result.program_name == "test_program"
    end
  end

  describe "get_demos/1" do
    test "returns demonstration examples", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      assert OptimizedProgram.get_demos(optimized) == demos
    end
  end

  describe "get_program/1" do
    test "returns original program", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      assert OptimizedProgram.get_program(optimized) == program
    end
  end

  describe "get_metadata/1" do
    test "returns optimization metadata", %{program: program, demos: demos} do
      custom_metadata = %{optimizer: "test"}
      optimized = OptimizedProgram.new(program, demos, custom_metadata)

      metadata = OptimizedProgram.get_metadata(optimized)

      assert metadata.optimizer == "test"
      assert Map.has_key?(metadata, :optimized_at)
      assert metadata.demo_count == 2
    end
  end

  describe "add_demos/2" do
    test "adds new demonstrations to existing ones", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, [List.first(demos)])

      new_demo =
        Example.new(%{question: "What is 4+4?", answer: "8"})
        |> Example.with_inputs([:question])

      updated = OptimizedProgram.add_demos(optimized, [new_demo])

      assert length(OptimizedProgram.get_demos(updated)) == 2
      assert OptimizedProgram.get_metadata(updated).demo_count == 2
    end
  end

  describe "replace_demos/2" do
    test "replaces all demonstrations with new ones", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      new_demo =
        Example.new(%{question: "What is 4+4?", answer: "8"})
        |> Example.with_inputs([:question])

      updated = OptimizedProgram.replace_demos(optimized, [new_demo])

      assert length(OptimizedProgram.get_demos(updated)) == 1
      assert OptimizedProgram.get_metadata(updated).demo_count == 1
      assert List.first(OptimizedProgram.get_demos(updated)) == new_demo
    end
  end

  describe "DSPEx.Program behavior" do
    test "implements Program behavior correctly", %{program: program, demos: demos} do
      optimized = OptimizedProgram.new(program, demos)

      # Should be able to use DSPEx.Program.forward/3
      {:ok, result} = DSPEx.Program.forward(optimized, %{test: "input"})

      assert is_map(result)
    end
  end
end
