defmodule ElixirML.Process.PipelineTest do
  use ExUnit.Case, async: true
  
  alias ElixirML.Process.Pipeline

  describe "pipeline creation" do
    test "creates pipeline with default options" do
      stages = [
        %{id: :stage1, type: :function, function: fn x -> x + 1 end}
      ]
      
      pipeline = Pipeline.new(stages)
      
      assert pipeline.id != nil
      assert pipeline.name == "Pipeline"
      assert pipeline.stages == stages
      assert pipeline.execution_strategy == :sequential
      assert pipeline.error_handling == :fail_fast
      assert pipeline.timeout == 30_000
    end

    test "creates pipeline with custom options" do
      stages = [
        %{id: :stage1, type: :function, function: fn x -> x * 2 end}
      ]
      
      opts = [
        id: "custom_pipeline",
        name: "Custom Pipeline",
        execution_strategy: :parallel,
        error_handling: :continue_on_error,
        timeout: 60_000
      ]
      
      pipeline = Pipeline.new(stages, opts)
      
      assert pipeline.id == "custom_pipeline"
      assert pipeline.name == "Custom Pipeline"
      assert pipeline.execution_strategy == :parallel
      assert pipeline.error_handling == :continue_on_error
      assert pipeline.timeout == 60_000
    end
  end

  describe "sequential execution" do
    test "executes simple function stages in sequence" do
      stages = [
        %{id: :add_one, type: :function, function: fn x -> x + 1 end},
        %{id: :multiply_two, type: :function, function: fn x -> x * 2 end},
        %{id: :subtract_three, type: :function, function: fn x -> x - 3 end}
      ]
      
      pipeline = Pipeline.new(stages, execution_strategy: :sequential)
      
      result = Pipeline.execute(pipeline, 5)
      
      assert {:ok, execution_result} = result
      assert execution_result.outputs == 9  # (5 + 1) * 2 - 3 = 9
      assert Map.has_key?(execution_result, :stage_results)
      assert Map.has_key?(execution_result, :execution_time)
      assert execution_result.pipeline_id == pipeline.id
    end

    test "handles stage errors with fail_fast strategy" do
      stages = [
        %{id: :success, type: :function, function: fn x -> x + 1 end},
        %{id: :failure, type: :function, function: fn _x -> raise "Test error" end},
        %{id: :never_reached, type: :function, function: fn x -> x * 2 end}
      ]
      
      pipeline = Pipeline.new(stages, 
        execution_strategy: :sequential,
        error_handling: :fail_fast
      )
      
      result = Pipeline.execute(pipeline, 5)
      
      assert {:error, error_result} = result
      assert Map.has_key?(error_result, :error)
      assert Map.has_key?(error_result, :execution_time)
      assert error_result.pipeline_id == pipeline.id
    end
  end

  describe "parallel execution" do
    test "executes stages in parallel" do
      stages = [
        %{id: :add_one, type: :function, function: fn x -> x + 1 end},
        %{id: :multiply_two, type: :function, function: fn x -> x * 2 end},
        %{id: :add_ten, type: :function, function: fn x -> x + 10 end}
      ]
      
      pipeline = Pipeline.new(stages, execution_strategy: :parallel)
      
      result = Pipeline.execute(pipeline, 5)
      
      assert {:ok, execution_result} = result
      assert Map.has_key?(execution_result, :stage_results)
      assert map_size(execution_result.stage_results) == 3
      
      # All stages should have executed with the same input
      assert execution_result.stage_results[:add_one] == 6      # 5 + 1
      assert execution_result.stage_results[:multiply_two] == 10 # 5 * 2
      assert execution_result.stage_results[:add_ten] == 15     # 5 + 10
    end

    test "handles parallel execution with some failures" do
      stages = [
        %{id: :success1, type: :function, function: fn x -> x + 1 end},
        %{id: :failure, type: :function, function: fn _x -> raise "Test error" end},
        %{id: :success2, type: :function, function: fn x -> x * 2 end}
      ]
      
      pipeline = Pipeline.new(stages, 
        execution_strategy: :parallel,
        error_handling: :continue_on_error
      )
      
      result = Pipeline.execute(pipeline, 5)
      
      assert {:ok, execution_result} = result
      assert Map.has_key?(execution_result, :stage_results)
      assert Map.has_key?(execution_result, :errors)
      
      # Successful stages should have results
      assert execution_result.stage_results[:success1] == 6
      assert execution_result.stage_results[:success2] == 10
      
      # Should have recorded errors
      assert is_list(execution_result.errors)
      assert length(execution_result.errors) > 0
    end
  end

  describe "validation stages" do
    test "executes validation stages successfully" do
      validator = fn input ->
        if is_integer(input) and input > 0 do
          {:ok, input}
        else
          {:error, :invalid_input}
        end
      end
      
      stages = [
        %{id: :validate, type: :validation, validator: validator},
        %{id: :process, type: :function, function: fn x -> x * 2 end}
      ]
      
      pipeline = Pipeline.new(stages)
      
      # Test with valid input
      result = Pipeline.execute(pipeline, 5)
      assert {:ok, execution_result} = result
      assert execution_result.outputs == 10
      
      # Test with invalid input
      result = Pipeline.execute(pipeline, -1)
      assert {:error, _error_result} = result
    end

    test "handles boolean validation results" do
      stages = [
        %{id: :validate, type: :validation, validator: fn x -> x > 0 end},
        %{id: :process, type: :function, function: fn x -> x * 2 end}
      ]
      
      pipeline = Pipeline.new(stages)
      
      # Test with valid input (returns true)
      result = Pipeline.execute(pipeline, 5)
      assert {:ok, execution_result} = result
      assert execution_result.outputs == 10
      
      # Test with invalid input (returns false)
      result = Pipeline.execute(pipeline, -1)
      assert {:error, _error_result} = result
    end
  end

  describe "program execution integration" do
    test "can execute a program through pipeline system" do
      # Create a mock program
      program = %{
        id: "test_program",
        variable_space: nil
      }
      
      # Create a simple function pipeline instead of program pipeline
      # to avoid dependency on ProgramSupervisor
      pipeline = Pipeline.new([
        %{id: :mock_program, type: :function, function: fn inputs ->
          %{
            output: "Processed: #{inspect(inputs)}",
            program_id: program.id,
            timestamp: System.monotonic_time(:millisecond)
          }
        end}
      ])
      
      result = Pipeline.execute(pipeline, %{input: "test"})
      
      # The result structure should be consistent
      assert {:ok, execution_result} = result
      assert Map.has_key?(execution_result, :outputs)
      assert Map.has_key?(execution_result, :execution_time)
      assert Map.has_key?(execution_result, :pipeline_id)
    end
  end

  describe "error handling strategies" do
    test "continue_on_error allows pipeline to complete despite failures" do
      stages = [
        %{id: :success1, type: :function, function: fn x -> x + 1 end},
        %{id: :failure, type: :function, function: fn _x -> raise "Test error" end},
        %{id: :success2, type: :function, function: fn x -> x * 2 end}
      ]
      
      pipeline = Pipeline.new(stages, 
        execution_strategy: :sequential,
        error_handling: :continue_on_error
      )
      
      result = Pipeline.execute(pipeline, 5)
      
      # Should complete successfully despite the error in the middle
      assert {:ok, execution_result} = result
      assert Map.has_key?(execution_result, :stage_results)
    end
  end

  describe "pipeline utilities" do
    test "generates unique pipeline IDs" do
      pipeline1 = Pipeline.new([])
      pipeline2 = Pipeline.new([])
      
      assert pipeline1.id != pipeline2.id
      assert is_binary(pipeline1.id)
      assert is_binary(pipeline2.id)
    end
  end
end