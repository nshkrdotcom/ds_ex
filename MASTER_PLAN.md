# DSPEx Development Master Plan
*Created: June 14, 2025*

## Executive Summary

DSPEx is a comprehensive Elixir port of DSPy with a solid foundation (794 passing tests) but facing critical algorithmic issues in SIMBA, missing core reasoning modules, and significant gaps toward DSPy feature parity. This master plan provides a prioritized roadmap to transform DSPEx from a working foundation into a production-ready, feature-complete AI framework.

**Current Status**: ✅ Strong Foundation (11% DSPy parity) | 🚨 SIMBA Broken | ⚠️ Missing Core Modules

---

## 📚 Document Reference Guide

### **🎯 PRIORITY 1: Critical Action Items**
| File | Purpose | Action Required |
|------|---------|----------------|
| `CLAUDE.md` | Current project status & commands | ✅ **Foundation Complete** - Ready for SIMBA fixes |
| `DSPEX_MISSING_COMPONENTS_MASTER_LIST.md` | Complete gap analysis | 🚨 **Fix SIMBA algorithmic failures** |
| `DSPEX_CORE_GAPS.md` | Core component analysis | 🚨 **Implement Chain of Thought** |
| `SIMBA_USAGE_GUIDE.md` | SIMBA implementation guide | ⚠️ **Algorithm currently broken** |

### **🏗️ PRIORITY 2: Architecture & Integration**
| File | Purpose | Integration Status |
|------|---------|-------------------|
| `ELIXACT_LATEST_GAP_ANALYSIS_202506131704.md` | Elixact integration analysis | ✅ **Ready for integration** |
| `140_using_elixact.md` | Detailed Elixact integration plan | ✅ **Recommended approach** |
| `155_implementation_roadmap.md` | Step-by-step implementation guide | 📋 **Detailed roadmap available** |
| `150_elixact_integration_overview.md` | Elixact overview | 📋 **Background context** |

### **🔍 PRIORITY 3: Analysis & Planning Documents**
| File | Purpose | Status |
|------|---------|--------|
| `CRITICAL_ASSESSMENT.md` | Comprehensive codebase review | ✅ **Excellent foundation confirmed** |
| `DSPEX_GAP_ANALYSIS_*.md` (20+ files) | Detailed component analysis | 📚 **Reference material** |
| `*_plan.md` files | Various strategic plans | 📚 **Historical analysis** |

### **📊 PRIORITY 4: Supplementary Information**
| File Category | Purpose | Usage |
|---------------|---------|-------|
| `*_INTEG.md`, `*_typeadapter.md` | Technical integration details | 📋 **Implementation reference** |
| `RETRIEVE_PLANNING_*.md` | Retrieval system planning | 🔮 **Future implementation** |
| `DIFF*.md` | Change analysis | 📚 **Historical context** |
| `README.md` | Project overview | 📚 **Public documentation** |

---

## 🎯 Master Development Strategy

### **Phase 1: Emergency Fixes (Week 1) - BLOCKING ISSUES**

#### **🚨 CRITICAL: Fix SIMBA Algorithm (Day 1-2)**
**Problem**: SIMBA uses fixed scores (0.5) instead of real performance metrics
**Files**: `lib/dspex/teleprompter/simba.ex`
**Priority**: BLOCKING - All optimization is broken

**Required Changes**:
```elixir
# BROKEN CODE (current):
defp softmax_sample(program_indices, _all_programs, temperature) do
  scores = Enum.map(program_indices, fn _idx -> 0.5 end)  # ❌ FIXED SCORES!

# FIXED CODE (required):
defp softmax_sample(program_indices, program_scores, temperature) do
  scores = Enum.map(program_indices, fn idx -> 
    calculate_average_score(program_scores, idx)  # ✅ REAL SCORES
  end)
```

**Impact**: Without this fix, SIMBA optimization is completely non-functional

#### **⚠️ HIGH: Implement Chain of Thought (Day 3-5)**
**Problem**: Most widely used DSPy pattern is completely missing
**Location**: `lib/dspex/predict/chain_of_thought.ex` (new file)
**Dependencies**: Requires dynamic signature extension capability

**Implementation Plan**:
```elixir
defmodule DSPEx.Predict.ChainOfThought do
  use DSPEx.Program
  
  def new(signature, opts \\ []) do
    # Extend signature with rationale field
    enhanced_signature = DSPEx.Signature.extend(signature, %{
      rationale: %{type: :string, desc: "Let's think step by step."}
    })
    # Implementation details...
  end
end
```

### **Phase 2: Foundation Enhancement (Week 2-3)**

#### **🏗️ Dynamic Signature System**
**Current Limitation**: Only compile-time signature definition
**Required**: Runtime signature creation for optimization
**Implementation**: Use `Code.eval_string/3` for dynamic module creation

#### **🔧 Structured Output Parsing**
**Current Issue**: Basic string splitting only
**Required**: Field markers, JSON parsing, type-aware extraction
**Impact**: Better reliability for complex multi-field outputs

#### **📊 Advanced Demo Management**
**Current Issue**: Basic demo storage only
**Required**: Intelligent selection, validation, quality assessment
**Impact**: Improved few-shot learning performance

### **Phase 3: Elixact Integration (Week 3-5)**

#### **🎯 Strategic Decision: Adopt Elixact**
**Rationale**: Perfect fit for DSPy's Pydantic usage patterns
**Benefits**: 
- Type safety and validation
- JSON schema generation
- Structured error handling
- Better developer experience

**Migration Plan**:
1. **Week 3**: Create compatibility layer
2. **Week 4**: Migrate core signatures
3. **Week 5**: Enhanced adapters with automatic schema generation

**Example Transformation**:
```elixir
# OLD: String-based signatures
defmodule QASignature do
  use DSPEx.Signature, "question -> answer"
end

# NEW: Elixact-based schemas
defmodule QASignature do
  use Elixact
  schema do
    field :question, :string, description: "The question to answer"
    field :answer, :string, description: "The answer to the question"
  end
end
```

### **Phase 4: Advanced Reasoning (Week 5-8)**

#### **🧠 Missing Core Modules Implementation**
1. **ReAct (Reason + Act)** - Tool-enabled reasoning loops
2. **Multi-Chain Comparison** - Multiple reasoning path evaluation  
3. **Program Composition** - High-level program building patterns

#### **🔍 Retrieval System Foundation**
**Status**: Completely missing (0/25 components)
**Priority**: Medium-High (critical for RAG applications)
**Approach**: Start with basic embeddings and ChromaDB integration

### **Phase 5: Ecosystem Expansion (Week 8-12)**

#### **🌐 Provider Ecosystem**
**Current**: Basic OpenAI/Gemini
**Target**: Anthropic Claude, local models, Hugging Face
**Strategy**: LiteLLM-style integration approach

#### **📊 Advanced Evaluation**
**Current**: Basic exact match
**Target**: Semantic similarity, BLEU/ROUGE, confidence scoring
**Strategy**: Build comprehensive metrics framework

#### **🛡️ Production Features**
**Current**: Basic error handling
**Target**: Circuit breakers, advanced caching, monitoring
**Strategy**: Enterprise-ready resilience patterns

---

## 🎯 Success Metrics & Validation

### **Phase 1 Success Criteria**
- [ ] SIMBA optimization shows measurable performance improvement
- [ ] Chain of Thought produces step-by-step reasoning
- [ ] All existing tests continue to pass
- [ ] Performance regression < 10%

### **Phase 2 Success Criteria**  
- [ ] Dynamic signatures enable runtime optimization
- [ ] Structured parsing handles complex outputs reliably
- [ ] Demo management improves few-shot performance
- [ ] Test coverage maintains > 90%

### **Phase 3 Success Criteria**
- [ ] Elixact integration maintains backward compatibility
- [ ] JSON schema generation works automatically
- [ ] Type validation catches errors early
- [ ] Developer experience improves measurably

### **Long-term Success Criteria**
- [ ] 80%+ DSPy component parity achieved
- [ ] Production deployments running successfully
- [ ] Community adoption and contributions
- [ ] Performance matches or exceeds DSPy

---

## 🚨 Risk Assessment & Mitigation

### **Technical Risks**
1. **SIMBA Algorithm Complexity**: Detailed understanding required
   - *Mitigation*: Reference original DSPy implementation closely
2. **Elixact Integration Scope**: Large codebase changes
   - *Mitigation*: Incremental rollout with compatibility layer
3. **Dynamic Code Generation**: `Code.eval_string` security concerns
   - *Mitigation*: Sandboxed evaluation, input validation

### **Timeline Risks**
1. **Underestimating Complexity**: Features may take longer
   - *Mitigation*: Focus on core functionality first
2. **Dependency Conflicts**: Elixact integration issues
   - *Mitigation*: Thorough testing, version pinning

### **Quality Risks**
1. **Breaking Changes**: Existing functionality disruption
   - *Mitigation*: Comprehensive regression testing
2. **Performance Degradation**: Type checking overhead
   - *Mitigation*: Continuous benchmarking, optimization

---

## 🎯 Recommended Immediate Actions

### **This Week (Days 1-7)**
1. **Day 1**: Fix SIMBA program selection algorithm
2. **Day 2**: Implement `calc_average_score()` and `top_k_plus_baseline()`
3. **Day 3-4**: Create Chain of Thought module
4. **Day 5**: Test SIMBA + CoT integration
5. **Day 6-7**: Validate performance improvements

### **Next Week (Days 8-14)**
1. **Day 8-10**: Begin dynamic signature system
2. **Day 11-12**: Enhance structured output parsing
3. **Day 13-14**: Start Elixact integration planning

### **Month 1 Goals**
- ✅ SIMBA optimization working correctly
- ✅ Chain of Thought implemented and tested
- ✅ Elixact integration foundation ready
- ✅ All critical bugs resolved

---

## 📋 Development Commands Reference

### **Current Working Commands**
```bash
# Foundation tests (all passing)
mix test --include group_1 --include group_2

# Quality assurance (required)
mix dialyzer               # Zero warnings required
mix format                 # Code formatting  
mix credo --strict         # Code quality

# Performance validation
mix test test/performance/ --max-failures 1
```

### **Development Workflow**
```bash
# 1. Fix SIMBA algorithm
mix test test/integration/teleprompter_workflow_advanced_test.exs

# 2. Implement Chain of Thought
mix test test/unit/predict_chain_of_thought_test.exs  # (new file)

# 3. Validate integration
mix test --include integration_test --max-failures 1
```

---

## 🎉 Conclusion

DSPEx has a remarkable foundation with excellent Elixir/OTP patterns, comprehensive testing infrastructure, and solid architectural decisions. The path forward is clear:

1. **Fix critical SIMBA bugs** to unlock optimization capabilities
2. **Implement core reasoning modules** to match DSPy functionality  
3. **Integrate Elixact** for type safety and developer experience
4. **Expand ecosystem** for production readiness

With focused execution on this plan, DSPEx can become not just a DSPy port, but a superior AI framework that leverages Elixir's unique strengths for concurrent, fault-tolerant, and scalable AI applications.

**Next Step**: Begin SIMBA algorithm fixes immediately - this is the critical path blocker for all optimization functionality.