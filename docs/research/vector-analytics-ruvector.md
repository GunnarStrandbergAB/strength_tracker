# Vector-Based Workout Analytics Research

**Date**: 2026-02-16
**Branch**: `ruvector`
**Research method**: 3-agent parallel swarm (RuVector capabilities, on-device iOS ML, vector analytics architecture)

---

## TL;DR

| Question | Answer |
|----------|--------|
| **Can I use RuVector on iOS?** | Not directly. It's Rust/Node.js with no Swift bindings. The *concepts* (HNSW, vector similarity) apply, but use iOS-native libraries instead. |
| **Local LLM on iPhone?** | YES. Apple NLContextualEmbedding (iOS 17+) gives 512-dim sentence vectors on-device for free. Foundation Models framework (iOS 26) adds full LLM. MLX/llama.cpp also work. |
| **Can I skip LLMs entirely?** | YES. For workout analytics, **feature-engineered numeric vectors + cosine similarity** is simpler, faster, and more appropriate than LLM embeddings. No ML model needed at all. |
| **Recommended approach?** | **Pure on-device**: hand-crafted workout vectors (16-24 dims) + Apple Accelerate vDSP for similarity search. Zero API costs, 100% offline, <10ms searches. |

---

## 1. RuVector: What It Is and Why It Doesn't Fit iOS

RuVector is a **distributed, self-learning vector database** written in Rust with Node.js bindings:

- **HNSW indexing** with <0.5ms search latency
- **52,000+ inserts/second**, ~50 bytes per vector
- **Self-learning** via Graph Neural Networks
- **Deployment options**: Full server, rvLite (2MB edge), WASM (5.5KB)
- **LLM-independent**: Can use local ONNX models (MiniLM-L6-v2) or pre-computed vectors

**Why it doesn't fit StrengthTracker:**
- No native Swift/iOS bindings
- Requires Node.js runtime (not typical iOS)
- Designed for server/distributed use cases
- Bridging Rust -> Node.js -> Swift adds unnecessary complexity

**What to take from it:** The HNSW algorithm and vector similarity concepts are exactly what we want - just implemented natively in Swift.

---

## 2. On-Device ML Options for iOS

### Tier 1: Apple Built-in (No Dependencies)

| Framework | iOS | What It Does | Cost |
|-----------|-----|-------------|------|
| **NLEmbedding** | 13+ | Word-level vectors, 7 languages | Free |
| **NLContextualEmbedding** | 17+ | 512-dim sentence vectors (BERT), 27 languages | Free |
| **Core ML** | 11+ | Run any exported ML model on-device (Neural Engine) | Free |
| **Foundation Models** | 26+ | Full on-device LLM (Apple Intelligence) | Free |

**NLContextualEmbedding is the sweet spot for iOS 17+** - production-ready, no dependencies, fully offline.

```swift
import NaturalLanguage

let embedding = NLEmbedding.sentenceEmbedding(for: .english)
let vector = embedding?.vector(for: "heavy squat day with accessories")
// Returns [Double] with 512 elements, entirely on-device
```

### Tier 2: Third-Party Local LLMs

| Library | What | Size | Devices |
|---------|------|------|---------|
| **Apple MLX** | Apple's ML framework, Swift bindings | Varies | iPhone 15 Pro+ (8GB) |
| **LLM.swift** | llama.cpp wrapper for Swift | ~3-7GB models | iPhone 15 Pro+ |
| **llama.cpp** | C++ inference, XCFramework for iOS | ~2-4GB (quantized) | iPhone 12+ (limited) |

### Tier 3: API-Based

| Provider | Model | Cost per 1M tokens |
|----------|-------|-------------------|
| OpenAI | text-embedding-3-small | $0.02 |
| OpenAI | text-embedding-3-large | $0.13 |
| Anthropic | Claude Sonnet | $3.00 input |

**Verdict: API is overkill and unnecessary for workout analytics.**

---

## 3. The Key Insight: You Don't Need an LLM

For workout analytics, the data is already **structured and numeric**. LLM embeddings convert text to vectors - but workout data (sets, reps, weight, muscle groups) is already numeric. Feature engineering beats LLM embeddings here:

| Approach | Latency | Cost | Accuracy for Workouts |
|----------|---------|------|-----------------------|
| **Feature-engineered vectors** | <1ms | $0 | Best (domain-specific) |
| NLContextualEmbedding | ~10ms | $0 | Good (semantic text) |
| OpenAI embeddings API | ~200ms | $0.02/1M | Good (general purpose) |

---

## 4. Recommended Architecture: Pure On-Device

### What Gets Vectorized

**Workout Session Vector (16-18 dimensions):**
```swift
[
    totalVolume / 10000.0,      // Normalized total kg
    duration / 120.0,           // Normalized minutes
    exerciseCount / 10.0,       // Number of exercises
    setCount / 40.0,            // Total sets
    avgIntensity,               // Weight / estimated 1RM
    chestRatio,                 // % volume per muscle group
    backRatio,                  //   (6 muscle group dimensions)
    legsRatio,
    shouldersRatio,
    armsRatio,
    coreRatio,
    compoundLiftRatio,          // % compound vs isolation
    avgRestTime / 300.0,        // Normalized rest periods
    rpeAverage / 10.0,          // RPE if tracked
    hourOfDay / 24.0,           // Time features
    dayOfWeek / 7.0
]
```

### Analytics Features This Enables

| Feature | How | User Sees |
|---------|-----|-----------|
| **Similar Workouts** | Cosine similarity on workout vectors | "Workouts like this one" with % match |
| **Plateau Detection** | Track strength trajectory vectors over time | "No PRs in 3 weeks - consider a deload" |
| **Muscle Balance** | Compare muscle group volume ratios | "Back:Chest ratio 1.8:1 (ideal ~1.5)" |
| **Exercise Recommendations** | Nearest neighbor on exercise vectors | "Try incline DB press (similar to bench)" |
| **Optimal Volume** | Regression on volume -> progress vectors | "Your sweet spot: 12-16 sets/week for chest" |
| **Recovery Patterns** | Time between muscle group hits | "You perform best hitting legs every 72h" |

### System Architecture

```
SwiftUI Views (WorkoutAnalyticsView)
        |
WorkoutAnalyticsViewModel (@Observable, @MainActor)
        |
WorkoutAnalyticsService
    |                   |
VectorSearchService     WorkoutRepository (SwiftData)
(Accelerate/vDSP)
```

### Core Implementation

**Cosine similarity with Apple Accelerate (hardware-accelerated):**
```swift
import Accelerate

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    var dotProduct: Float = 0
    var magA: Float = 0
    var magB: Float = 0

    vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

    var sqA = [Float](repeating: 0, count: a.count)
    var sqB = [Float](repeating: 0, count: b.count)
    vDSP_vsq(a, 1, &sqA, 1, vDSP_Length(a.count))
    vDSP_vsq(b, 1, &sqB, 1, vDSP_Length(b.count))
    vDSP_sve(sqA, 1, &magA, vDSP_Length(a.count))
    vDSP_sve(sqB, 1, &magB, vDSP_Length(b.count))

    guard magA > 0, magB > 0 else { return 0 }
    return dotProduct / (sqrt(magA) * sqrt(magB))
}
```

**SwiftData storage (extend WorkoutEntity):**
```swift
@Model
public final class WorkoutEntity {
    // ... existing properties ...
    @Attribute(.transformable)
    public var vectorEmbedding: Data?   // Stores [Float] as raw bytes
    public var lastVectorizedAt: Date?
}
```

### Performance Estimates

| Operation | Time | Notes |
|-----------|------|-------|
| Vectorize 1 workout | <1ms | vDSP acceleration |
| Vectorize 500 workouts (bulk) | ~500ms | One-time on first launch |
| Linear search (500 workouts) | ~5ms | Fine for typical user |
| HNSW search (10,000 workouts) | ~0.5ms | Only needed for power users |
| Storage per workout | 64 bytes | 16 floats x 4 bytes |
| 1000 workouts total | 64KB | Negligible |

---

## 5. iOS-Native Vector Search Libraries

If linear scan becomes too slow (>5,000 workouts), add HNSW indexing:

| Library | Type | Notes |
|---------|------|-------|
| **SimilaritySearchKit** | Pure Swift, MIT | Best documented, includes NL embeddings + HNSW. [GitHub](https://github.com/ZachNagengast/similarity-search-kit) |
| **swift-hnsw** | Pure Swift | Lightweight HNSW. [GitHub](https://github.com/JadenGeller/swift-hnsw) |
| **hnswlib.swift** | C++ bridge | Swift bindings for hnswlib. [GitHub](https://github.com/MegaPortal/hnswlib.swift) |
| **VecturaKit** | Pure Swift | MLTensor-based, zero deps. [GitHub](https://github.com/rryam/VecturaKit) |
| **ObjectBox** | Commercial | Native Swift DB with HNSW. [objectbox.io](https://objectbox.io) |

**Recommendation**: Start with linear scan (plenty fast for <2,000 workouts), add SimilaritySearchKit if/when needed.

---

## 6. Implementation Roadmap

### Phase 1: Foundation (Week 1)
- `WorkoutVectorizer` service (feature extraction from domain models)
- `VectorSearchService` with vDSP cosine similarity
- Extend `WorkoutEntity` with vector storage
- Background vectorization of existing workouts on app launch

### Phase 2: Basic Analytics UI (Week 2)
- "Similar Workouts" card in WorkoutDetailView
- Basic `WorkoutAnalyticsViewModel`
- Unit tests for vectorization and search

### Phase 3: Advanced Features (Weeks 3-4)
- Plateau detection algorithm
- Muscle balance radar chart
- Exercise recommendation engine
- Analytics tab or dashboard section

### Phase 4: Optimization (Week 5)
- HNSW indexing if needed (SimilaritySearchKit)
- Incremental vectorization (only new workouts)
- Watch app mini-insights
- Optional: NLContextualEmbedding for semantic exercise search ("find pulling exercises")

---

## 7. File Structure

```
Shared/
  Services/
    Analytics/
      WorkoutAnalyticsService.swift
      WorkoutVectorizer.swift
      VectorSearchService.swift
      PlateauDetector.swift
  ViewModels/
    WorkoutAnalyticsViewModel.swift

iOS/
  Features/
    Analytics/
      Views/
        WorkoutAnalyticsView.swift
        SimilarWorkoutsCard.swift
        MuscleBalanceChart.swift
        PlateauInsightCard.swift
```

---

## Sources

### RuVector
- [GitHub - ruvnet/ruvector](https://github.com/ruvnet/ruvector)
- [RuVector npm package](https://www.npmjs.com/package/ruvector)
- [GitHub - ruvnet/claude-flow](https://github.com/ruvnet/claude-flow)

### Apple On-Device ML
- [NLEmbedding - Apple Developer](https://developer.apple.com/documentation/naturallanguage/nlembedding)
- [NLContextualEmbedding - Apple Developer](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)
- [Foundation Models framework (iOS 26)](https://developer.apple.com/documentation/FoundationModels)
- [Core ML - Apple Developer](https://developer.apple.com/documentation/coreml)
- [Apple MLX Swift](https://github.com/ml-explore/mlx-swift)
- [Get started with MLX - WWDC25](https://developer.apple.com/videos/play/wwdc2025/315/)

### Local LLMs on iOS
- [LLM.swift](https://github.com/eastriverlee/LLM.swift)
- [llama.cpp](https://github.com/ggml-org/llama.cpp)
- [Phi-3 Technical Report](https://arxiv.org/html/2404.14219v4)

### Vector Search on iOS
- [SimilaritySearchKit](https://github.com/ZachNagengast/similarity-search-kit)
- [VecturaKit](https://github.com/rryam/VecturaKit)
- [swift-hnsw](https://github.com/JadenGeller/swift-hnsw)
- [ObjectBox on-device Vector Database](https://objectbox.io/swift-ios-on-device-vector-database-aka-semantic-index/)

### Fitness + Vector Search
- [Building a Personal Fitness Insights Engine with Vector Search](https://sneekes.app/posts/building-a-personal-fitness-assistant-with-vector-search/)
- [Physical Exercise Recommendation (arXiv)](https://arxiv.org/pdf/2010.00482)
- [Cosine Similarity with Accelerate in Swift](https://rudrank.com/exploring-ai-cosine-similarity-rag-accelerate-swift)
- [Apple Accelerate framework](https://developer.apple.com/accelerate/)

### Embeddings & APIs
- [OpenAI Embeddings Pricing](https://platform.openai.com/docs/pricing)
- [Vector Embeddings - Pinecone](https://www.pinecone.io/learn/vector-embeddings/)
- [ONNX Runtime iOS](https://onnxruntime.ai/docs/tutorials/on-device-training/ios-app.html)
