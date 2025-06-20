# DSPEx Unified Schema & Variable System Architecture

## Executive Decision: Build ElixirML.Schema

Create a single, unified library specifically designed for DSPEx's Variable system and ML optimization needs.

## Library Structure

```
lib/elixir_ml/
├── schema/                 # Core schema functionality (Sinter-inspired simplicity)
│   ├── core.ex            # Basic validation engine
│   ├── types.ex           # ML-specific types
│   └── runtime.ex         # Dynamic schema generation
├── variable/              # Advanced Variable system (new innovation)
│   ├── core.ex            # Variable abstraction
│   ├── space.ex           # Variable space management  
│   ├── resolver.ex        # Configuration resolution
│   └── ml_types.ex        # ML-specific variables
├── optimization/          # Multi-objective optimization
│   ├── evaluator.ex       # Multi-objective evaluation
│   ├── constraints.ex     # Advanced constraints
│   └── pareto.ex          # Pareto optimization
└── integration/           # DSPEx integration
    ├── program.ex         # Program enhancement
    └── teleprompter.ex    # Optimizer integration
```

## Core Design Principles

### 1. Variable-First Architecture
Everything is designed around the Variable abstraction as the primary concern:

```elixir
defmodule ElixirML.Variable do
  @moduledoc """
  Universal variable abstraction enabling any optimizer to tune any parameter.
  Core innovation for DSPEx's competitive advantage.
  """
  
  defstruct [
    :id,                    # Unique identifier
    :type,                  # :discrete | :continuous | :hybrid | :conditional | :composite
    :choices,               # For discrete variables
    :range,                 # For continuous variables
    :default,               # Default value
    :constraints,           # Validation constraints
    :dependencies,          # Variable dependencies
    :metadata,              # Additional metadata
    :description,           # Human description
    :cost_weight,           # Cost optimization weight
    :performance_weight,    # Performance optimization weight
    :validation_schema,     # Schema for validation
    :transform_fn,          # Value transformation function
    :condition_fn          # Conditional activation function
  ]
end
```

### 2. Dual API Design
Provide both simple and advanced APIs:

```elixir
# Simple API (Sinter-style simplicity)
defmodule SimpleExample do
  use ElixirML.Schema
  
  field :name, :string, required: true
  field :age, :integer, optional: true
end

# Advanced API (Variable-aware)
defmodule AdvancedExample do
  use ElixirML.Schema
  
  # Traditional fields
  field :question, :string, required: true
  field :answer, :string, required: true
  
  # Variable definitions for optimization
  variable :adapter, :discrete, 
    choices: [JSONAdapter, MarkdownAdapter, ChatAdapter],
    description: "Response format adapter"
    
  variable :reasoning_module, :discrete,
    choices: [Predict, ChainOfThought, ProgramOfThought],
    description: "Reasoning strategy"
    
  variable :temperature, :continuous,
    range: {0.0, 2.0},
    default: 0.7,
    description: "Model temperature"
end
```

### 3. ML-Optimized Types
Built-in types specifically for ML/LLM applications:

```elixir
defmodule ElixirML.Schema.MLTypes do
  # Standard types (Sinter compatibility)
  @basic_types [:string, :integer, :float, :boolean, :atom, :map, :list]
  
  # ML-specific types
  @ml_types [
    :embedding,           # Vector embeddings
    :probability,         # 0.0 to 1.0 values
    :model_response,      # LLM response structure
    :token_list,          # Tokenized text
    :confidence_score,    # Model confidence
    :provider_config,     # LLM provider configuration
    :adapter_module,      # Response format adapter
    :reasoning_strategy   # Reasoning module selection
  ]
end
```

### 4. Runtime Schema Generation
Dynamic schema creation for optimization:

```elixir
defmodule ElixirML.Schema.Runtime do
  def create_program_signature(input_fields, output_fields, variables \\ []) do
    all_fields = input_fields ++ output_fields
    
    schema = ElixirML.Schema.define(all_fields, 
      title: "DSPy Program Signature",
      variables: variables
    )
    
    # Add optimization space
    variable_space = ElixirML.Variable.Space.from_schema(schema)
    
    {schema, variable_space}
  end
end
```

## Integration Strategy

### Phase 1: Core Implementation (Weeks 1-2)
- Build unified schema engine (Sinter simplicity + Elixact features)
- Implement Variable abstraction system
- Create ML-specific types and constraints
- Add runtime schema generation

### Phase 2: Variable System (Weeks 3-4)  
- Implement Variable Space management
- Add constraint and dependency systems
- Create configuration resolution pipeline
- Build validation and transformation

### Phase 3: DSPEx Integration (Weeks 5-6)
- Enhance DSPEx.Program with Variable support
- Integrate with teleprompters (SIMBA, BEACON)
- Add automatic module selection
- Create optimization evaluation framework

### Phase 4: Advanced Features (Weeks 7-8)
- Multi-objective optimization
- Pareto frontier analysis
- Advanced constraint solving
- Performance optimization

## Migration Strategy

### Immediate Actions
1. **Start Fresh**: Create `ElixirML.Schema` as new unified library
2. **Cherry-Pick**: Take the best concepts from both Sinter and Elixact
3. **Focus**: Design specifically for Variable system requirements
4. **Integrate**: Build DSPEx integration from day one

### Code Reuse Plan
- **From Sinter**: Core validation engine, simple API design, performance focus
- **From Elixact**: Advanced features, ML types, JSON schema generation
- **New Innovation**: Variable system, optimization integration, ML-specific constraints

### Dependencies
```elixir
# mix.exs
defp deps do
  [
    # Core dependencies
    {:jason, "~> 1.4"},                    # JSON handling
    {:nx, "~> 0.7"},                       # Numerical computing for optimization
    
    # Optional integrations  
    {:ash, "~> 3.0", optional: true},      # Resource framework (if needed)
    {:stream_data, "~> 0.6", only: :test}, # Property-based testing
    
    # Development
    {:ex_doc, "~> 0.31", only: :dev},
    {:credo, "~> 1.7", only: [:dev, :test]},
    {:dialyzer, "~> 1.4", only: [:dev, :test]}
  ]
end
```

## Competitive Advantages

### 1. Variable Abstraction Pioneer
- First implementation of Omar's Variable vision
- Positions DSPEx as the definitive ML optimization platform
- Creates community momentum around DSPEx

### 2. ML-Native Design
- Types and constraints designed for LLM applications
- Built-in support for provider optimization
- Advanced multi-objective evaluation

### 3. Performance Excellence
- Designed for optimization workloads
- Concurrent evaluation capabilities
- Intelligent caching and memoization

### 4. Developer Experience
- Simple API for basic use cases
- Advanced API for sophisticated optimization
- Comprehensive documentation and examples

## Technical Specifications

### Schema Definition API
```elixir
# Simple usage
schema = ElixirML.Schema.define([
  {:name, :string, [required: true]},
  {:age, :integer, [optional: true]}
])

# Variable-enhanced usage
schema = ElixirML.Schema.define([
  {:question, :string, [required: true]},
  {:answer, :string, [required: true]}
], variables: [
  ElixirML.Variable.discrete(:adapter, [JSONAdapter, MarkdownAdapter]),
  ElixirML.Variable.continuous(:temperature, {0.0, 2.0}, default: 0.7)
])
```

### Variable Space API
```elixir
# Create optimization space
variable_space = ElixirML.Variable.Space.new()
  |> ElixirML.Variable.Space.add_variable(
    ElixirML.Variable.discrete(:adapter, [JSONAdapter, MarkdownAdapter])
  )
  |> ElixirML.Variable.Space.add_variable(
    ElixirML.Variable.continuous(:temperature, {0.0, 2.0})
  )

# Sample configurations for optimization
configurations = ElixirML.Variable.Space.sample(variable_space, count: 10)

# Validate configuration
{:ok, config} = ElixirML.Variable.Space.validate(variable_space, %{
  adapter: JSONAdapter,
  temperature: 0.7
})
```

### DSPEx Integration API
```elixir
# Enhanced DSPEx.Program with Variables
defmodule MyProgram do
  use DSPEx.Program
  use ElixirML.Schema.Integration
  
  # Define program signature with variables
  signature :question_answering do
    input :question, :string, required: true
    output :answer, :string, required: true
    output :confidence, :probability, required: true
    
    # Variables for optimization
    variable :adapter, :discrete,
      choices: [JSONAdapter, MarkdownAdapter]
    variable :temperature, :continuous,
      range: {0.0, 2.0}, default: 0.7
  end
end

# Automatic optimization
{:ok, optimized_program} = DSPEx.Teleprompter.SIMBA.compile(
  MyProgram, 
  training_data, 
  metric_fn,
  optimize_variables: true
)
```

## Quality Assurance

### Testing Strategy
- **Unit Tests**: >95% coverage for all core functions
- **Integration Tests**: Complete DSPEx integration validation
- **Property Tests**: Variable generation and constraint validation
- **Performance Tests**: Benchmarking against Sinter and Elixact

### Documentation Requirements
- **API Reference**: Complete function documentation
- **User Guide**: Progressive tutorials from simple to advanced
- **Examples**: Real-world DSPEx optimization examples
- **Migration Guide**: Clear path from Sinter/Elixact

### Performance Targets
- **Validation Speed**: Match or exceed Sinter performance
- **Memory Usage**: <20% overhead for Variable system
- **Optimization Time**: Linear scaling with variable count
- **Concurrent Safety**: Thread-safe operations throughout

## Conclusion

Building `ElixirML.Schema` as a unified library specifically designed for the Variable system will:

1. **Position DSPEx as the leader** in implementing Omar's Variable vision
2. **Provide clean architecture** without legacy constraints
3. **Enable sophisticated ML optimization** with built-in Variable support
4. **Maintain simplicity** for basic use cases while supporting advanced features
5. **Create competitive advantage** in the ML/LLM framework space

This approach avoids the complexity of refactoring Elixact or extending Sinter beyond their design limits, instead creating the ideal foundation for DSPEx's Variable-driven optimization future.
