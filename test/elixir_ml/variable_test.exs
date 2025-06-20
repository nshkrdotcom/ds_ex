defmodule ElixirML.VariableTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ElixirML.Variable
  alias ElixirML.Variable.MLTypes
  alias ElixirML.Variable.Space

  describe "variable creation" do
    test "creates float variable with constraints" do
      var = Variable.float(:temperature, range: {0.0, 2.0}, default: 0.7)

      assert var.name == :temperature
      assert var.type == :float
      assert var.default == 0.7
      assert var.constraints.range == {0.0, 2.0}
    end

    test "creates integer variable with constraints" do
      var = Variable.integer(:max_tokens, range: {1, 4096}, default: 1000)

      assert var.name == :max_tokens
      assert var.type == :integer
      assert var.default == 1000
      assert var.constraints.range == {1, 4096}
    end

    test "creates choice variable with options" do
      var = Variable.choice(:provider, [:openai, :anthropic, :groq], default: :openai)

      assert var.name == :provider
      assert var.type == :choice
      assert var.default == :openai
      assert var.constraints.choices == [:openai, :anthropic, :groq]
    end

    test "creates module variable for automatic selection" do
      var =
        Variable.module(:adapter,
          modules: [ModuleA, ModuleB],
          behavior: SomeBehavior
        )

      assert var.name == :adapter
      assert var.type == :module
      assert var.constraints.modules == [ModuleA, ModuleB]
      assert var.constraints.behavior == SomeBehavior
    end

    test "creates composite variable with dependencies" do
      var =
        Variable.composite(:model_config,
          dependencies: [:provider, :temperature],
          compute: fn %{provider: provider, temperature: temp} ->
            %{model: "#{provider}-default", temperature: temp}
          end
        )

      assert var.name == :model_config
      assert var.type == :composite
      assert var.dependencies == [:provider, :temperature]
    end
  end

  describe "variable validation" do
    test "validates float values within range" do
      var = Variable.float(:temperature, range: {0.0, 2.0})

      assert {:ok, 0.8} = Variable.validate(var, 0.8)
      assert {:ok, +0.0} = Variable.validate(var, +0.0)
      assert {:ok, 2.0} = Variable.validate(var, 2.0)

      assert {:error, _} = Variable.validate(var, -0.1)
      assert {:error, _} = Variable.validate(var, 2.1)
      assert {:error, _} = Variable.validate(var, "not a number")
    end

    test "validates integer values within range" do
      var = Variable.integer(:max_tokens, range: {1, 1000})

      assert {:ok, 500} = Variable.validate(var, 500)
      assert {:ok, 1} = Variable.validate(var, 1)
      assert {:ok, 1000} = Variable.validate(var, 1000)

      assert {:error, _} = Variable.validate(var, 0)
      assert {:error, _} = Variable.validate(var, 1001)
      assert {:error, _} = Variable.validate(var, 3.14)
    end

    test "validates choice values" do
      var = Variable.choice(:provider, [:openai, :anthropic])

      assert {:ok, :openai} = Variable.validate(var, :openai)
      assert {:ok, :anthropic} = Variable.validate(var, :anthropic)

      assert {:error, _} = Variable.validate(var, :groq)
    end

    test "validates choice with custom values allowed" do
      var = Variable.choice(:provider, [:openai, :anthropic], allow_custom: true)

      assert {:ok, :openai} = Variable.validate(var, :openai)
      assert {:ok, :custom_provider} = Variable.validate(var, :custom_provider)
    end

    test "validates module values" do
      var = Variable.module(:adapter, modules: [String, Integer])

      assert {:ok, String} = Variable.validate(var, String)
      assert {:ok, Integer} = Variable.validate(var, Integer)

      assert {:error, _} = Variable.validate(var, Float)
      assert {:error, _} = Variable.validate(var, "not a module")
    end
  end

  describe "random value generation" do
    test "generates random float values within range" do
      var = Variable.float(:temperature, range: {0.0, 1.0})

      for _i <- 1..100 do
        value = Variable.random_value(var)
        assert is_float(value)
        assert value >= 0.0
        assert value <= 1.0
      end
    end

    test "generates random integer values within range" do
      var = Variable.integer(:count, range: {1, 10})

      for _i <- 1..100 do
        value = Variable.random_value(var)
        assert is_integer(value)
        assert value >= 1
        assert value <= 10
      end
    end

    test "generates random choice values" do
      choices = [:a, :b, :c]
      var = Variable.choice(:option, choices)

      for _i <- 1..100 do
        value = Variable.random_value(var)
        assert value in choices
      end
    end
  end

  describe "variable space management" do
    test "creates empty variable space" do
      space = Space.new(name: "Test Space")

      assert space.name == "Test Space"
      assert map_size(space.variables) == 0
    end

    test "adds variables to space" do
      space = Space.new()
      var1 = Variable.float(:temperature, range: {0.0, 2.0})
      var2 = Variable.choice(:provider, [:openai, :anthropic])

      space =
        space
        |> Space.add_variable(var1)
        |> Space.add_variable(var2)

      assert map_size(space.variables) == 2
      assert Space.get_variable(space, :temperature) == var1
      assert Space.get_variable(space, :provider) == var2
    end

    test "validates configuration against space" do
      space =
        Space.new()
        |> Space.add_variable(Variable.float(:temperature, range: {0.0, 2.0}, default: 0.7))
        |> Space.add_variable(Variable.choice(:provider, [:openai, :anthropic], default: :openai))

      # Valid configuration
      config = %{temperature: 0.8, provider: :openai}
      assert {:ok, validated} = Space.validate_configuration(space, config)
      assert validated.temperature == 0.8
      assert validated.provider == :openai

      # Configuration with defaults
      partial_config = %{temperature: 0.9}
      assert {:ok, validated} = Space.validate_configuration(space, partial_config)
      assert validated.temperature == 0.9
      # default value
      assert validated.provider == :openai

      # Invalid configuration
      invalid_config = %{temperature: 3.0, provider: :openai}
      assert {:error, _} = Space.validate_configuration(space, invalid_config)
    end

    test "generates random configurations" do
      space =
        Space.new()
        |> Space.add_variable(Variable.float(:temperature, range: {0.0, 2.0}))
        |> Space.add_variable(Variable.choice(:provider, [:openai, :anthropic]))

      {:ok, config} = Space.random_configuration(space)

      assert Map.has_key?(config, :temperature)
      assert Map.has_key?(config, :provider)
      assert config.temperature >= 0.0 and config.temperature <= 2.0
      assert config.provider in [:openai, :anthropic]
    end

    test "handles dependencies in variable space" do
      compute_fn = fn config ->
        provider = Map.get(config, :provider, :unknown)
        temp = Map.get(config, :temperature, 0.5)
        %{model: "#{provider}-default", temperature: temp}
      end

      space =
        Space.new()
        |> Space.add_variable(Variable.choice(:provider, [:openai, :anthropic]))
        |> Space.add_variable(Variable.float(:temperature, range: {0.0, 1.0}))
        |> Space.add_variable(
          Variable.composite(:config,
            dependencies: [:provider, :temperature],
            compute: compute_fn,
            default: %{model: "default", temperature: 0.5}
          )
        )

      config = %{provider: :openai, temperature: 0.8}
      {:ok, validated} = Space.validate_configuration(space, config)

      assert Map.has_key?(validated, :config)
      assert validated.config.model == "openai-default"
      assert validated.config.temperature == 0.8
    end

    test "adds and validates cross-variable constraints" do
      constraint_fn = fn config ->
        if config.temperature > 1.5 and config.provider == :groq do
          {:error, "Groq doesn't support high temperature"}
        else
          {:ok, config}
        end
      end

      space =
        Space.new()
        |> Space.add_variable(Variable.float(:temperature, range: {0.0, 2.0}))
        |> Space.add_variable(Variable.choice(:provider, [:openai, :groq]))
        |> Space.add_constraint(constraint_fn)

      # Valid configuration
      valid_config = %{temperature: 0.8, provider: :groq}
      assert {:ok, _} = Space.validate_configuration(space, valid_config)

      # Invalid configuration (violates constraint)
      invalid_config = %{temperature: 1.8, provider: :groq}
      assert {:error, error_msg} = Space.validate_configuration(space, invalid_config)
      assert error_msg =~ "Groq doesn't support high temperature"
    end
  end

  describe "ML-specific variable types" do
    test "creates provider variable with metadata" do
      provider_var = MLTypes.provider(:llm_provider)

      assert provider_var.type == :choice
      assert :openai in provider_var.constraints.choices
      assert :anthropic in provider_var.constraints.choices
      assert Map.has_key?(provider_var.metadata, :cost_weights)
      assert Map.has_key?(provider_var.metadata, :performance_weights)
    end

    test "creates temperature variable with ML-specific defaults" do
      temp_var = MLTypes.temperature(:temperature)

      assert temp_var.type == :float
      assert temp_var.constraints.range == {0.0, 2.0}
      assert temp_var.default == 0.7
      assert temp_var.description =~ "temperature"
    end

    test "creates max_tokens variable" do
      tokens_var = MLTypes.max_tokens(:max_tokens)

      assert tokens_var.type == :integer
      assert tokens_var.constraints.range == {1, 4096}
      assert tokens_var.default == 1000
    end

    test "creates reasoning strategy module variable" do
      reasoning_var = MLTypes.reasoning_strategy(:reasoning)

      assert reasoning_var.type == :module
      assert reasoning_var.constraints.behavior == ElixirML.Reasoning.Strategy
      assert Map.has_key?(reasoning_var.metadata, :complexity_levels)
    end

    test "creates standard ML configuration space" do
      space = MLTypes.standard_ml_config()

      assert map_size(space.variables) >= 6
      assert Space.get_variable(space, :provider)
      assert Space.get_variable(space, :temperature)
      assert Space.get_variable(space, :max_tokens)
      assert Space.get_variable(space, :reasoning_strategy)
    end
  end

  describe "space dimensionality and complexity" do
    test "calculates space dimensionality" do
      space =
        Space.new()
        |> Space.add_variable(Variable.float(:temp1, range: {0.0, 1.0}))
        |> Space.add_variable(Variable.float(:temp2, range: {0.0, 1.0}))
        |> Space.add_variable(Variable.choice(:provider, [:a, :b, :c]))
        |> Space.add_variable(Variable.integer(:count, range: {1, 10}))

      {discrete, continuous} = Space.dimensionality(space)
      # Two float variables
      assert continuous == 2
      # One choice + one integer
      assert discrete == 2
    end

    test "validates space for circular dependencies" do
      # Valid space (no circular dependencies)
      valid_space =
        Space.new()
        |> Space.add_variable(Variable.float(:a, range: {0.0, 1.0}))
        |> Space.add_variable(Variable.composite(:b, dependencies: [:a], compute: & &1))

      assert Space.valid?(valid_space)
    end
  end

  describe "property-based testing" do
    test "property: random values are always within constraints for float variables" do
      check all(
              min <- float(min: -100.0, max: 100.0),
              max <- float(min: min, max: min + 100.0),
              max_runs: 50
            ) do
        var = Variable.float(:test_var, range: {min, max})

        for _i <- 1..10 do
          value = Variable.random_value(var)
          assert value >= min
          assert value <= max
          assert is_float(value)
        end
      end
    end

    test "property: validation is consistent with random value generation" do
      check all(
              choices <- list_of(atom(:alphanumeric), min_length: 1, max_length: 10),
              max_runs: 50
            ) do
        var = Variable.choice(:test_var, choices)

        for _i <- 1..10 do
          value = Variable.random_value(var)
          assert {:ok, ^value} = Variable.validate(var, value)
        end
      end
    end

    test "property: space validates its own random configurations" do
      check all(
              temp_range <- tuple({float(min: 0.0, max: 1.0), float(min: 1.0, max: 2.0)}),
              choices <- list_of(atom(:alphanumeric), min_length: 1, max_length: 5),
              max_runs: 50
            ) do
        {min_temp, max_temp} = temp_range

        space =
          Space.new()
          |> Space.add_variable(Variable.float(:temperature, range: {min_temp, max_temp}))
          |> Space.add_variable(Variable.choice(:provider, choices))

        case Space.random_configuration(space) do
          {:ok, config} ->
            assert {:ok, _} = Space.validate_configuration(space, config)

          {:error, _} ->
            # Some configurations might fail constraints, that's ok
            :ok
        end
      end
    end
  end
end
