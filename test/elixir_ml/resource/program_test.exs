defmodule ElixirML.Resource.ProgramTest do
  use ExUnit.Case, async: true
  alias ElixirML.Resources.Program

  describe "Program resource definition" do
    test "program has required attributes" do
      # Should have id, name, type, signature_config, program_config, status, performance_metrics
      attrs = Program.__resource_attributes__()
      attr_names = Enum.map(attrs, fn {name, _type, _opts} -> name end)

      assert :name in attr_names
      assert :type in attr_names
      assert :signature_config in attr_names
      assert :status in attr_names
    end

    test "program has relationships to variable space and optimization runs" do
      # Should belong_to variable_space, has_many optimization_runs and executions
      relationships = Program.__resource_relationships__()

      belongs_to_found =
        Enum.any?(relationships, fn
          {:belongs_to, :variable_space, ElixirML.Resources.VariableSpace, _} -> true
          _ -> false
        end)

      assert belongs_to_found

      has_many_found =
        Enum.any?(relationships, fn
          {:has_many, :optimization_runs, ElixirML.Resources.OptimizationRun, _} -> true
          _ -> false
        end)

      assert has_many_found
    end

    test "program supports schema-based attributes" do
      # Should use schema_attribute for complex configurations
      schema_attrs = Program.__resource_schema_attributes__()
      schema_attr_names = Enum.map(schema_attrs, fn {name, _module, _opts} -> name end)

      assert :signature_config in schema_attr_names
      assert :program_config in schema_attr_names
    end
  end

  describe "Program resource actions" do
    test "execute action is defined" do
      actions = Program.__resource_actions__()
      action_names = Enum.map(actions, fn {name, _opts, _block} -> name end)

      assert :execute in action_names
      assert :optimize in action_names
      assert :validate_inputs in action_names
    end

    test "program can be created with valid configuration" do
      {:ok, program} =
        Program.create(%{
          name: "Test Program",
          type: :predict,
          signature_config: %{
            input_fields: [%{"name" => "input", "type" => "string"}],
            output_fields: [%{"name" => "output", "type" => "string"}]
          }
        })

      assert program.name == "Test Program"
      assert program.type == :predict
      assert program.status == :draft
    end

    test "program validates type constraints" do
      {:error, reason} =
        Program.create(%{
          name: "Test Program",
          type: :invalid_type,
          signature_config: %{
            input_fields: [],
            output_fields: []
          }
        })

      assert match?({:validation_error, :type, _}, reason)
    end
  end

  describe "Program resource calculations" do
    test "current_performance_score calculation" do
      {:ok, program} = create_test_program()

      {:ok, score} = Program.calculate(program, :current_performance_score, %{})
      assert is_float(score) or is_integer(score)
    end

    test "optimization_count calculation" do
      {:ok, program} = create_test_program()

      {:ok, count} = Program.calculate(program, :optimization_count, %{})
      assert is_integer(count)
      assert count >= 0
    end

    test "calculations are defined" do
      calculations = Program.__resource_calculations__()
      calc_names = Enum.map(calculations, fn {name, _type, _module, _opts} -> name end)

      assert :current_performance_score in calc_names
      assert :optimization_count in calc_names
      assert :variable_importance_scores in calc_names
    end
  end

  describe "Program lifecycle" do
    test "program can be created with minimal configuration" do
      {:ok, program} =
        Program.create(%{
          name: "Minimal Program",
          type: :predict,
          signature_config: %{
            input_fields: [%{"name" => "input", "type" => "string"}],
            output_fields: [%{"name" => "output", "type" => "string"}]
          }
        })

      assert program.name == "Minimal Program"
      assert program.status == :draft
      assert program.version == 1
    end

    test "program can be updated" do
      {:ok, program} = create_test_program()

      {:ok, updated} = Program.update(program, %{status: :active})
      assert updated.status == :active
      # Other fields unchanged
      assert updated.name == program.name
    end

    test "program validates status transitions" do
      {:ok, program} = create_test_program()

      # Valid status transition
      {:ok, _updated} = Program.update(program, %{status: :active})

      # Invalid status
      {:error, reason} = Program.update(program, %{status: :invalid_status})
      assert match?({:validation_error, :status, _}, reason)
    end
  end

  # Helper function
  defp create_test_program do
    Program.create(%{
      name: "Test Program",
      type: :predict,
      signature_config: %{
        input_fields: [%{"name" => "question", "type" => "string"}],
        output_fields: [%{"name" => "answer", "type" => "string"}]
      },
      program_config: %{
        provider: :openai,
        model: "gpt-3.5-turbo",
        temperature: 0.7
      }
    })
  end
end
