# DSPEx Architecture Decision Records (ADRs)

## Overview

This document captures the key architectural decisions made during DSPEx development, providing rationale and context for future development and maintenance.

---

## ADR-001: Foundation 2.0 as Core Infrastructure Dependency

**Date**: 2025-06-09
**Status**: Accepted  
**Decision Makers**: Core DSPEx Team  

### Context

DSPEx requires robust infrastructure for distributed AI workloads, including circuit breakers, connection pooling, rate limiting, and cluster coordination. We evaluated several options:

1. **Build from scratch**: Custom implementation of all infrastructure
2. **Use existing libraries**: Combine multiple specialized libraries (Fuse, Poolboy, etc.)
3. **Foundation 2.0 integration**: Leverage comprehensive BEAM-native infrastructure

### Decision

We will integrate Foundation 2.0 as our core infrastructure dependency, providing:
- Unified circuit breakers, rate limiting, and connection pooling
- Partisan-based clustering for 1000+ node scale
- Distributed state management and consensus algorithms
- Built-in telemetry and observability

### Rationale

**Advantages**:
- **BEAM-native**: Designed specifically for BEAM applications
- **Production-ready**: Battle-tested patterns and implementations
- **Scalability**: Supports our vision of 1000+ node clusters
- **Unified API**: Single interface for all infrastructure concerns
- **Active development**: We can influence Foundation's roadmap for DSPEx needs

**Risks**:
- **Early-stage dependency**: Foundation 2.0 is still developing
- **Coupling**: Deep integration may limit flexibility
- **Learning curve**: Team needs to understand Foundation patterns

**Mitigation**:
- Maintain fallback implementations for critical features
- Regular coordination with Foundation development team
- Gradual migration path from Foundation 1.x

### Consequences

- All infrastructure code will use Foundation APIs
- DSPEx becomes showcase for Foundation 2.0 capabilities
- Performance and scalability tied to Foundation improvements
- Team expertise in Foundation becomes strategic advantage

---

## ADR-002: GenServer-Based Client Architecture

**Date**: 2025-06-09 
**Status**: Accepted  
**Decision Makers**: Core DSPEx Team  

### Context

The original DSPEx client was a simple HTTP wrapper module. For production use, we need:
- Connection pooling and lifecycle management
- Circuit breakers and fault tolerance
- Multi-provider support with unified interface
- Observability and metrics collection
- Graceful handling of configuration changes

### Decision

We will implement a GenServer-based client architecture with:
- `DSPEx.Client.Manager`: Central coordinator for all providers
- `DSPEx.Client.Provider`: Per-provider GenServer instances
- `DSPEx.Client.HttpWorker`: Pooled HTTP workers for actual requests
- Foundation integration for infrastructure concerns

### Rationale

**Advantages**:
- **OTP compliance**: Leverages supervision trees and fault tolerance
- **State management**: Maintains connection pools and configuration
- **Scalability**: Can handle thousands of concurrent requests
- **Observability**: Built-in metrics and telemetry integration
- **Flexibility**: Easy to add new providers or modify behavior

**Alternatives considered**:
- **Simple module**: Too limited for production requirements
- **Agent-based**: Less robust than GenServer for complex state
- **Task-based**: Doesn't provide persistent infrastructure

### Consequences

- All LLM requests go through supervised GenServer processes
- Client startup time increases but provides better reliability
- Memory usage increases for persistent state management
- Configuration changes can be applied without restarts

---

## ADR-003: Hybrid Local/Distributed Evaluation Strategy

**Date**: 2025-06-09  
**Status**: Accepted  
**Decision Makers**: Core DSPEx Team  

### Context

DSPEx evaluation needs to work efficiently in multiple environments:
- Single-node development and testing
- Small clusters (2-10 nodes)
- Large clusters (100+ nodes)
- Massive clusters (1000+ nodes)

Each environment has different optimal strategies for work distribution.

### Decision

We will implement a hybrid evaluation strategy that automatically selects the optimal approach:

```elixir
def run(program, examples, metric_fn, opts) do
  if should_distribute?(opts) and cluster_available?() do
    run_distributed(program, examples, metric_fn, opts)
  else
    run_local(program, examples, metric_fn, opts)
  end
end
```

**Local evaluation** uses:
- `Task.async_stream` for concurrency
- Process-per-example isolation
- Foundation telemetry for observability

**Distributed evaluation** uses:
- Foundation WorkDistribution for coordination
- Intelligent node selection based on capabilities
- Fault-tolerant aggregation with consensus

### Rationale

**Advantages**:
- **Automatic optimization**: Chooses best strategy for environment
- **Development simplicity**: Works great on single nodes
- **Production scalability**: Leverages cluster capabilities
- **Graceful degradation**: Falls back to local if distribution fails

**Alternatives considered**:
- **Always distributed**: Adds complexity for simple cases
- **Always local**: Doesn't leverage cluster capabilities
- **Manual selection**: Requires users to understand infrastructure

### Consequences

- Evaluation code is more complex but handles all environments
- Performance is optimal for each deployment scenario
- Testing must cover both local and distributed paths
- Users get optimal performance without configuration

---

## ADR-004: Consensus-Based Demo Selection in Teleprompters

**Date**: 2025-06-09
**Status**: Accepted  
**Decision Makers**: Core DSPEx Team  

### Context

In distributed optimization, multiple nodes generate demonstration examples independently. We need a strategy for selecting the best demonstrations across the cluster that:
- Ensures quality and diversity
- Handles network partitions gracefully
- Scales to large clusters
- Provides deterministic results

### Decision

We will use Foundation's consensus algorithms for demo selection:

1. **Distributed Bootstrap**: Each node generates demos independently
2. **Quality Scoring**: Demos are scored based on multiple criteria
3. **Consensus Voting**: Nodes vote on demo selection using Byzantine fault-tolerant consensus
4. **Fallback Strategy**: Local selection if consensus fails

### Rationale

**Advantages**:
- **Quality assurance**: Multiple nodes validate demo quality
- **Fault tolerance**: Survives node failures and network issues
- **Scalability**: Consensus algorithms scale to large clusters
- **Determinism**: Same input always produces same output

**Alternatives considered**:
- **Central coordination**: Single point of failure
- **Random selection**: Lower quality results
- **Majority voting**: Vulnerable to Byzantine failures
- **Local optimization**: Doesn't leverage cluster intelligence

### Consequences

- Optimization takes longer but produces higher quality results
- Network overhead for consensus communication
- Requires understanding of distributed systems concepts
- More complex testing and debugging

---

## ADR-005: Process Ecosystems for Complex Workflows

**Date**: 2025-06-09  
**Status**: Accepted  
**Decision Makers**: Core DSPEx Team  

### Context

Complex AI workflows require coordination between multiple concerns:
- Input validation and preprocessing
- Model inference and prediction
- Output processing and validation
- Performance monitoring and logging
- Caching and memoization

Traditional approaches either create monolithic functions or complex callback chains.

### Decision

We will use Foundation's ProcessEcosystem pattern for complex workflows:

```elixir
ProcessEcosystem.spawn_ecosystem(
  :inference_workflow,
  [
    {:coordinator, InferenceCoordinator, [program: program]},
    {:validator, InputValidator, [signature: signature]},
    {:processor, OutputProcessor, [transformations: transforms]},
    {:monitor, PerformanceMonitor, [metrics: [:latency, :cost]]},
    {:cache, CacheManager, [strategy: :lru]}
  ]
)
```

### Rationale

**Advantages**:
- **Separation of concerns**: Each process has single responsibility
- **Fault isolation**: Failure in one component doesn't crash others
- **Observability**: Each process can be monitored independently
- **Composability**: Ecosystems can be nested and combined
- **BEAM-native**: Leverages actor model strengths

**Alternatives considered**:
- **Monolithic functions**: Hard to test and modify
- **Callback chains**: Complex error handling and debugging
- **GenStage pipelines**: More complex than needed for this use case

### Consequences

- Higher memory usage for process overhead
- More complex debugging across multiple processes
- Excellent fault tolerance and isolation
- Easy to add new capabilities without changing existing code

---

## ADR-006: Signature Macro vs Runtime Definition

**Date**: 2025-06-09
**Status**: Accepted  
**Decision Makers**: Core DSPEx Team  

### Context

DSPy signatures can be defined in two ways:
1. **Compile-time macros**: `use DSPEx.Signature, "question -> answer"`
2. **Runtime definitions**: Dynamic signature creation and manipulation

We need to choose the primary approach while potentially supporting both.

### Decision

We will prioritize compile-time macro definitions with runtime support as secondary:

**Primary approach**:
```elixir
defmodule QASignature do
  use DSPEx.Signature, "question -> answer"
end
```

**Secondary support**:
```elixir
signature = DSPEx.Signature.create("question -> answer")
```

### Rationale

**Compile-time advantages**:
- **Type safety**: Dialyzer can validate field access
- **Performance**: No parsing overhead at runtime
- **Developer experience**: Clear, declarative syntax
- **Documentation**: Self-documenting code

**Runtime advantages**:
- **Flexibility**: Dynamic signature creation
- **Metaprogramming**: Generated signatures
- **Configuration**: Signatures from external sources

**Decision rationale**:
- Most use cases benefit from compile-time definition
- Runtime support provides escape hatch for advanced uses
- Compile-time aligns with Elixir best practices

### Consequences

- Primary API is simple and type-safe
- Runtime API requires more careful error handling
- Testing must cover both approaches
- Documentation emphasizes compile-time approach

---

## ADR-007: Multi-Channel Partisan Communication

**Date**: 2025-06-09
**Status**: Accepted  
**Decision Makers**: Core DSPEx Team  

### Context

Large-scale distributed AI workloads generate different types of traffic:
- **Inference requests**: High volume, latency-sensitive
- **Coordination messages**: Low volume, reliability-critical
- **Telemetry data**: High volume, loss-tolerant
- **Real-time updates**: Low latency, order-sensitive

Traditional Distributed Erlang uses single TCP connection per node pair, causing head-of-line blocking.

### Decision

We will use Foundation 2.0's Partisan multi-channel communication:

```elixir
channels = [
  :inference,      # High priority, low latency
  :coordination,   # Critical reliability
  :telemetry,      # Best effort, high volume
  :real_time       # Ultra-low latency
]
```

Each channel gets dedicated connection with appropriate configuration.

### Rationale

**Advantages**:
- **Eliminates head-of-line blocking**: Independent channels
- **Traffic prioritization**: Critical messages aren't delayed
- **Optimal configuration**: Each channel tuned for its traffic type
- **Scalability**: Better resource utilization

**Alternatives considered**:
- **Single channel**: Head-of-line blocking issues
- **External message queue**: Adds operational complexity
- **HTTP-based**: Higher latency and overhead

### Consequences

- Higher connection overhead (multiple TCP connections)
- More complex configuration and monitoring
- Better performance characteristics for mixed workloads
- Requires Partisan-enabled cluster

---

## ADR-008: Zero-Breaking-Changes Migration Strategy

**Date**: 2025-06-09
**Status**: Accepted  
**Decision Makers**: Core DSPEx Team  

### Context

DSPEx needs to evolve from basic implementation to distributed AI framework while maintaining compatibility with existing code. Users shouldn't be forced to rewrite applications.

### Decision

We will implement zero-breaking-changes migration strategy:

1. **API Compatibility**: All existing APIs continue to work
2. **Opt-in Features**: New capabilities available via options
3. **Sensible Defaults**: Optimal behavior without configuration
4. **Deprecation Path**: Gradual phase-out of obsolete features

**Example**:
```elixir
# Works in all versions
{:ok, result} = DSPEx.Predict.forward(program, inputs)

# New distributed features opt-in
{:ok, result} = DSPEx.Predict.forward(program, inputs, distributed: true)
```

### Rationale

**Advantages**:
- **User trust**: No fear of breaking changes
- **Adoption**: Easy upgrade path encourages adoption
- **Validation**: Existing tests continue to pass
- **Rollback**: Easy to revert if issues found

**Alternatives considered**:
- **Major version bump**: Discourages adoption
- **Parallel APIs**: Confusing for users
- **Flag day migration**: High risk for users

### Consequences

- More complex implementation supporting old and new patterns
- Technical debt from maintaining deprecated features
- Higher confidence in migrations
- Better adoption of new capabilities

---

## ADR-009: Self-Managing Infrastructure Philosophy

**Date**: 2025-06-09
**Status**: Accepted  
**Decision Makers**: Core DSPEx Team  

### Context

Traditional distributed systems require significant operational overhead:
- Manual scaling decisions
- Performance tuning
- Cost optimization
- Failure recovery

AI workloads have predictable patterns that can be learned and automated.

### Decision

We will implement self-managing infrastructure that:
- **Learns workload patterns** using machine learning
- **Predicts resource needs** and scales proactively
- **Optimizes costs** automatically across cloud providers
- **Recovers from failures** without human intervention
- **Adapts to changes** in real-time

### Rationale

**Advantages**:
- **Reduced ops burden**: Less manual intervention required
- **Better performance**: Proactive rather than reactive optimization
- **Cost efficiency**: Automated cost optimization
- **Reliability**: Faster failure recovery than human response

**BEAM advantages**:
- **Process model**: Natural fault isolation and recovery
- **Hot code upgrades**: Update optimization algorithms without downtime
- **Observability**: Rich telemetry for learning algorithms

### Consequences

- Complex implementation requiring ML capabilities
- Potential for optimization algorithms to make wrong decisions
- Requires extensive testing and validation
- Significant competitive advantage when working properly

---

## Decision Summary

| ADR | Decision | Impact | Risk Level |
|-----|----------|---------|------------|
| 001 | Foundation 2.0 dependency | High scalability gains | Medium |
| 002 | GenServer client architecture | Better reliability | Low |
| 003 | Hybrid evaluation strategy | Optimal performance | Low |
| 004 | Consensus-based demo selection | Higher quality results | Medium |
| 005 | Process ecosystems | Better fault tolerance | Medium |
| 006 | Signature macro priority | Developer experience | Low |
| 007 | Multi-channel communication | Eliminates bottlenecks | High |
| 008 | Zero-breaking-changes | User adoption | Low |
| 009 | Self-managing infrastructure | Revolutionary capability | High |

## Review and Evolution

These ADRs will be reviewed quarterly and updated as:
- Foundation 2.0 capabilities evolve
- Performance data validates or contradicts assumptions
- User feedback identifies issues or opportunities
- New distributed systems research emerges

Each ADR includes metrics for validation and criteria for potential revision.