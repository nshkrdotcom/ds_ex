defmodule ElixirML.Variable.MLTypesEnhancedTest do
  use ExUnit.Case

  alias ElixirML.Variable.MLTypes
  alias ElixirML.Variable

  describe "enhanced ML types from Elixact patterns" do
    test "embedding/2 creates embedding variable with dimensions" do
      embedding_var = MLTypes.embedding(:embedding, dimensions: 1536)

      assert embedding_var.type == :composite
      assert embedding_var.metadata.dimensions == 1536
      assert embedding_var.description =~ "Embedding"
    end

    test "probability/2 creates probability variable with proper range" do
      prob_var = MLTypes.probability(:confidence)

      assert prob_var.type == :float
      assert prob_var.constraints.range == {0.0, 1.0}
      assert prob_var.default == 0.5
    end

    test "confidence_score/2 creates confidence variable" do
      conf_var = MLTypes.confidence_score(:confidence)

      assert conf_var.type == :float
      assert conf_var.constraints.range == {0.0, 1.0}
      assert conf_var.metadata.ml_type == :confidence
    end

    test "token_count/2 creates token count variable" do
      token_var = MLTypes.token_count(:tokens, max: 4096)

      assert token_var.type == :integer
      assert token_var.constraints.range == {1, 4096}
      assert token_var.description =~ "Token"
    end

    test "cost_estimate/2 creates cost estimation variable" do
      cost_var = MLTypes.cost_estimate(:cost, currency: :usd)

      assert cost_var.type == :float
      assert cost_var.metadata.currency == :usd
      assert cost_var.metadata.ml_type == :cost
    end

    test "latency_estimate/2 creates latency variable" do
      latency_var = MLTypes.latency_estimate(:latency)

      assert latency_var.type == :float
      assert latency_var.metadata.ml_type == :latency
      assert latency_var.metadata.measurement_unit == :seconds
    end

    test "quality_score/2 creates quality assessment variable" do
      quality_var = MLTypes.quality_score(:quality)

      assert quality_var.type == :float
      assert quality_var.constraints.range == {0.0, 10.0}
      assert quality_var.metadata.ml_type == :quality
    end

    test "reasoning_complexity/2 creates reasoning complexity variable" do
      complexity_var = MLTypes.reasoning_complexity(:complexity)

      assert complexity_var.type == :integer
      assert complexity_var.constraints.range == {1, 10}
      assert complexity_var.metadata.ml_type == :complexity
    end

    test "context_window/2 creates context window variable" do
      context_var = MLTypes.context_window(:context, model: "gpt-4")

      assert context_var.type == :integer
      assert context_var.metadata.model == "gpt-4"
      assert context_var.metadata.max_context == 8192
    end

    test "batch_size/2 creates batch processing variable" do
      batch_var = MLTypes.batch_size(:batch_size)

      assert batch_var.type == :integer
      assert batch_var.description =~ "Batch"
      assert batch_var.metadata.ml_type == :batch_size
    end
  end

  describe "enhanced variable spaces" do
    test "llm_optimization_space/1 creates comprehensive LLM optimization space" do
      space = MLTypes.llm_optimization_space()

      assert space.name == "LLM Optimization Space"
      assert Map.has_key?(space.variables, :temperature)
      assert Map.has_key?(space.variables, :top_p)
      assert Map.has_key?(space.variables, :max_tokens)
    end

    test "teleprompter_optimization_space/1 creates teleprompter-specific space" do
      space = MLTypes.teleprompter_optimization_space()

      assert space.name == "Teleprompter Optimization Space"
      assert Map.has_key?(space.variables, :temperature)
      assert Map.has_key?(space.variables, :batch_size)
      assert Map.has_key?(space.variables, :min_confidence)
    end

    test "multi_objective_space/1 creates multi-objective optimization space" do
      space = MLTypes.multi_objective_space()

      assert space.name == "Multi-Objective Optimization Space"
      assert Map.has_key?(space.variables, :accuracy)
      assert Map.has_key?(space.variables, :inference_time)
      assert space.metadata.space_type == :multi_objective
    end
  end

  describe "constraint validation" do
    test "validates embedding dimensions" do
      embedding_var = MLTypes.embedding(:test_embedding, dimensions: 512)

      # Composite variables have different validation
      assert embedding_var.type == :composite
      assert embedding_var.metadata.dimensions == 512
    end

    test "validates probability ranges" do
      prob_var = MLTypes.probability(:test_prob)

      assert {:ok, _} = Variable.validate(prob_var)
      assert prob_var.constraints.range == {0.0, 1.0}
    end

    test "validates token counts" do
      token_var = MLTypes.token_count(:test_tokens, max: 1000)

      assert {:ok, _} = Variable.validate(token_var)
      assert token_var.constraints.range == {1, 1000}
    end
  end

  describe "ML-specific metadata" do
    test "embedding variables include dimension metadata" do
      embedding_var = MLTypes.embedding(:test, dimensions: 1536)

      assert embedding_var.metadata.dimensions == 1536
      assert embedding_var.metadata.ml_type == :embedding
      assert embedding_var.metadata.normalization == :l2
    end

    test "cost variables include currency and scaling metadata" do
      cost_var = MLTypes.cost_estimate(:cost, currency: :usd, scaling: :linear)

      assert cost_var.metadata.currency == :usd
      assert cost_var.metadata.scaling == :linear
      assert cost_var.metadata.cost_model == :token_based
    end

    test "latency variables include timeout metadata" do
      latency_var = MLTypes.latency_estimate(:latency, timeout: 30.0)

      assert latency_var.metadata.timeout == 30.0
      assert latency_var.metadata.measurement_unit == :seconds
    end
  end

  describe "provider-specific optimizations" do
    test "creates provider-optimized variable spaces" do
      openai_space = MLTypes.provider_optimized_space(:openai)
      anthropic_space = MLTypes.provider_optimized_space(:anthropic)

      # Both should have temperature variables
      openai_temp = openai_space.variables[:temperature]
      anthropic_temp = anthropic_space.variables[:temperature]

      assert openai_temp.type == :float
      assert anthropic_temp.type == :float

      # They should have the same default since they use the same temperature function
      assert openai_temp.default == anthropic_temp.default

      # But different provider metadata
      assert openai_space.metadata.provider == :openai
      assert anthropic_space.metadata.provider == :anthropic
    end
  end
end
