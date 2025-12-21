# Ticket: 14 Integrate detection pipeline with Confidence Router

Spec version: v1.0 / strategies.md#strategy-1-2

## Context

Currently we have multiple detection components:
- **N-gram detector** — fast, statistical, 96-98% accuracy on 4+ chars
- **LanguageEnsemble** — combines NLLanguageRecognizer + n-gram + heuristics
- **UserLanguageProfile** — adaptive thresholds based on user history
- **CoreML classifier** (future, ticket 17) — ML-based, 98-99% accuracy

This ticket introduces a **Confidence Router** that intelligently routes detection requests through these components based on confidence levels and token characteristics.

## Architecture: Confidence Router

```
┌─────────────────────────────────────────────────────────────┐
│                    ConfidenceRouter                         │
│  Routes detection based on confidence thresholds            │
└─────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Fast Path      │  │  Standard Path  │  │  Deep Path      │
│  (N-gram only)  │  │  (Ensemble)     │  │  (CoreML)       │
│  conf > 0.95    │  │  conf > 0.7     │  │  ambiguous      │
│  latency: <1ms  │  │  latency: 2-5ms │  │  latency: 5-10ms│
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Routing Logic

```swift
func route(token: String, context: DetectorContext) -> LayoutDecision {
    // 1. Fast path: N-gram only for high-confidence cases
    let ngramResult = ngramDetector.score(token)
    if ngramResult.confidence > 0.95 && token.count >= 4 {
        return ngramResult.toDecision()
    }
    
    // 2. Standard path: Ensemble for medium confidence
    let ensembleResult = ensemble.classify(token, context)
    if ensembleResult.confidence > 0.7 {
        return ensembleResult
    }
    
    // 3. Deep path: CoreML for ambiguous cases (when available)
    if let coreml = coremlClassifier {
        return coreml.classify(token)
    }
    
    // 4. Fallback: Use ensemble result with lower confidence
    return ensembleResult
}
```

## Objective & Definition of Done

### Definition of Done

- [ ] **ConfidenceRouter implementation**:
  - [ ] Create `ConfidenceRouter.swift` actor
  - [ ] Implement routing logic with configurable thresholds
  - [ ] Support optional CoreML classifier (nil if not loaded)
  - [ ] Log routing decisions at debug level

- [ ] **Threshold configuration**:
  - [ ] `fastPathThreshold: Double = 0.95`
  - [ ] `standardPathThreshold: Double = 0.7`
  - [ ] `minTokenLengthForFastPath: Int = 4`
  - [ ] Configurable via SettingsStore (advanced settings)

- [ ] **Integration with UserLanguageProfile**:
  - [ ] Apply adaptive threshold adjustments from profile
  - [ ] Record outcomes for learning

- [ ] **EventMonitor integration**:
  - [ ] Replace direct LanguageEnsemble calls with ConfidenceRouter
  - [ ] Maintain <50ms latency budget

- [ ] **Metrics & Logging**:
  - [ ] Track which path was used (for debugging)
  - [ ] Log confidence scores and routing decisions

## Steps

1. **Create ConfidenceRouter** (1 day)
   - Define routing logic
   - Integrate existing components

2. **Update EventMonitor** (0.5 day)
   - Use ConfidenceRouter instead of direct calls

3. **Add threshold settings** (0.5 day)
   - Advanced settings in SettingsStore

4. **Write tests** (1 day)
   - Test routing logic
   - Test threshold behavior
   - Performance tests

## Affected Files/Modules

- `OMFK/Sources/Core/ConfidenceRouter.swift` — new file
- `OMFK/Sources/Engine/EventMonitor.swift` — use router
- `OMFK/Sources/Settings/SettingsStore.swift` — add thresholds
- `OMFK/Tests/ConfidenceRouterTests.swift` — new tests

## Reference Documentation

- **Strategies**: `.sdd/strategies.md` (detection strategies)
- **Architecture**: `.sdd/architect.md`

## Dependencies

- **Upstream**: Ticket 13 (multi-layout support)
- **Downstream**: Tickets 15, 16, 17

## Priority

**P1 — HIGH** — Core detection pipeline integration.
