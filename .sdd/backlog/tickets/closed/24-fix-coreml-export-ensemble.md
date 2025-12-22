# Ticket 24: Fix CoreML Export for EnsembleModel

## Priority: CRITICAL (Blocker)

## Status: Open

## Summary
EnsembleModel (CNN + Transformer) achieves 98.42% validation accuracy but cannot be exported to CoreML due to `torch.jit.trace` incompatibility with dynamic tensor operations. Training succeeds but the model is unusable in the macOS app.

## Problem Description

### Training Results (Successful)
- **Model**: EnsembleModel (CNN + Transformer)
- **Parameters**: 3,462,292
- **Training samples**: 5,000,000
- **Best validation accuracy**: 98.42% (epoch 10)
- **Early stopping**: epoch 25
- **Output file**: `model_production.pth`

### Export Failure
```
torch.jit._trace.TracingCheckError: Tracing failed sanity checks!
ERROR: Graphs differed across invocations!
```

### Root Causes

#### 1. Dynamic tensor size operations in LayoutClassifierV2 (CNN)
File: `/Users/sasha/IdeaProjects/personal_projects/omfk/Tools/CoreMLTrainer/train.py`
Lines 221-227:
```python
# Line 221 - Multi-scale convolution concatenation
min_len = min(c2.size(2), c3.size(2), c4.size(2), c5.size(2))
x = torch.cat([c2[:,:,:min_len], c3[:,:,:min_len], c4[:,:,:min_len], c5[:,:,:min_len]], dim=1)

# Line 227 - Second concatenation
min_len = min(x_a.size(2), x_b.size(2))
x = torch.cat([x_a[:,:,:min_len], x_b[:,:,:min_len]], dim=1)
```

TracerWarning:
```
Converting a tensor to a Python boolean might cause the trace to be incorrect. 
We can't record the data flow of Python values, so this value will be treated as a constant.
```

#### 2. TransformerEncoder with variable-length attention
- `PositionalEncoding` uses dynamic slicing: `self.pe[:, :x.size(1), :]`
- `TransformerEncoderLayer` has data-dependent control flow
- Attention mask computation varies with input

#### 3. Graph diff shows inconsistent node numbering
The trace produces different graphs on different invocations because:
- Tensor sizes are computed at runtime
- Conditional branches depend on tensor values
- Transformer attention patterns vary

## Affected Files

| File | Purpose | Issue |
|------|---------|-------|
| `/Users/sasha/IdeaProjects/personal_projects/omfk/Tools/CoreMLTrainer/train.py` | Model definitions | Dynamic `min()` operations, Transformer architecture |
| `/Users/sasha/IdeaProjects/personal_projects/omfk/Tools/CoreMLTrainer/export.py` | CoreML export | Uses `torch.jit.trace` which fails |
| `/Users/sasha/IdeaProjects/personal_projects/omfk/train_master.sh` | Training script | Calls export with `--ensemble` flag |

## Technical Context

### Current Architecture (train.py)

```python
class LayoutClassifierV2(nn.Module):
    """Enhanced multi-scale CNN - PROBLEMATIC"""
    def forward(self, x):
        # Multi-scale convolutions with different kernel sizes
        c2 = self.gelu(self.conv2(x))  # kernel=2, padding=1
        c3 = self.gelu(self.conv3(x))  # kernel=3, padding=1
        c4 = self.gelu(self.conv4(x))  # kernel=4, padding=2
        c5 = self.gelu(self.conv5(x))  # kernel=5, padding=2
        
        # PROBLEM: Dynamic min() creates trace inconsistency
        min_len = min(c2.size(2), c3.size(2), c4.size(2), c5.size(2))
        x = torch.cat([c2[:,:,:min_len], ...], dim=1)

class LayoutTransformer(nn.Module):
    """Transformer - PROBLEMATIC"""
    def forward(self, x):
        x = self.embedding(x)
        x = self.pos_encoder(x)  # Dynamic slicing
        x = self.transformer(x)  # Variable attention
        
class EnsembleModel(nn.Module):
    """Combines both - inherits all problems"""
    def forward(self, x):
        out_cnn = self.cnn(x)           # LayoutClassifierV2
        out_transformer = self.transformer(x)  # LayoutTransformer
        return weighted_average(out_cnn, out_transformer)
```

### Export Code (export.py)
```python
def export(args):
    model = EnsembleModel()
    model.load_state_dict(torch.load(args.model_in))
    model.eval()
    
    example_input = torch.randint(0, 100, (1, INPUT_LENGTH)).long()
    traced_model = torch.jit.trace(model, example_input)  # FAILS HERE
    
    mlmodel = ct.convert(traced_model, ...)
```

## Solution Options

### Option A: Make Architecture Trace-Compatible (Recommended)
**Effort**: Medium (1-2 days)
**Risk**: Low
**Accuracy impact**: Minimal

Changes required:
1. **Fix CNN padding** to ensure all convolutions output same length:
   ```python
   # Calculate padding to ensure output_len = input_len for all kernels
   # kernel=2: padding=1 (asymmetric) or use kernel=3
   # kernel=3: padding=1 ✓
   # kernel=4: padding=2 (asymmetric) or use kernel=5
   # kernel=5: padding=2 ✓
   
   # Solution: Use same-padding or fixed output size
   self.conv2 = nn.Conv1d(embedding_dim, hidden_dim//4, kernel_size=3, padding=1)
   self.conv3 = nn.Conv1d(embedding_dim, hidden_dim//4, kernel_size=3, padding=1)
   self.conv4 = nn.Conv1d(embedding_dim, hidden_dim//4, kernel_size=5, padding=2)
   self.conv5 = nn.Conv1d(embedding_dim, hidden_dim//4, kernel_size=5, padding=2)
   ```

2. **Remove dynamic min()** - use fixed slicing or ensure equal sizes:
   ```python
   # All convs now output same length, no min() needed
   x = torch.cat([c2, c3, c4, c5], dim=1)
   ```

3. **Fix PositionalEncoding** - use fixed max_len:
   ```python
   def forward(self, x):
       # Use constant INPUT_LENGTH instead of x.size(1)
       return x + self.pe[:, :INPUT_LENGTH, :]
   ```

4. **Replace TransformerEncoder** with trace-friendly version:
   ```python
   # Option 1: Use fixed-length attention (no mask)
   # Option 2: Use simpler self-attention without encoder layer
   # Option 3: Use torch.jit.script instead of trace (see Option B)
   ```

### Option B: Use torch.jit.script Instead of trace
**Effort**: Medium-High (2-3 days)
**Risk**: Medium (script has different limitations)
**Accuracy impact**: None

```python
# In export.py
scripted_model = torch.jit.script(model)  # Handles control flow
mlmodel = ct.convert(scripted_model, ...)
```

Requires:
- Type annotations on all methods
- No Python-only operations (list comprehensions, etc.)
- May need model refactoring for script compatibility

### Option C: Export CNN-only Model (Fallback)
**Effort**: Low (hours)
**Risk**: Low
**Accuracy impact**: ~1-2% lower (CNN alone vs ensemble)

```python
# Train and export LayoutClassifierV2 only (with fixes from Option A)
# Skip Transformer entirely
```

Pros:
- Simpler architecture
- Faster inference
- Easier to debug

Cons:
- Loses Transformer's sequence modeling benefits
- May need retraining

### Option D: Use ONNX as Intermediate Format
**Effort**: High (3-4 days)
**Risk**: High (compatibility issues)
**Accuracy impact**: None

```python
torch.onnx.export(model, example_input, "model.onnx")
# Then convert ONNX to CoreML
```

Not recommended due to:
- Additional conversion step
- Potential precision loss
- Less mature tooling for CoreML

## Recommended Approach

**Phase 1 (Immediate)**: Option A - Fix architecture
1. Modify `LayoutClassifierV2` to use consistent padding
2. Remove dynamic `min()` operations
3. Fix `PositionalEncoding` to use constant length
4. Test trace compatibility

**Phase 2 (If Phase 1 fails)**: Option B - Try torch.jit.script
1. Add type annotations
2. Refactor for script compatibility
3. Test export

**Phase 3 (Fallback)**: Option C - CNN-only
1. Export fixed LayoutClassifierV2 alone
2. Accept slight accuracy reduction
3. Document for future improvement

## Definition of Done

- [ ] `torch.jit.trace` succeeds without warnings
- [ ] CoreML export completes: `LayoutClassifier.mlmodel` generated
- [ ] Model loads in Swift: `MLModel(contentsOf: url)` succeeds
- [ ] Inference works: predictions match PyTorch outputs (±0.01)
- [ ] Accuracy preserved: validation accuracy ≥98% (or documented trade-off)
- [ ] No regression in existing tests

## Test Plan

1. **Trace test**:
   ```python
   traced = torch.jit.trace(model, example_input)
   # Should complete without TracingCheckError
   ```

2. **Export test**:
   ```bash
   python export.py --ensemble --model_in model_production.pth --output LayoutClassifier.mlmodel
   # Should complete without errors
   ```

3. **Swift integration test**:
   ```swift
   let model = try MLModel(contentsOf: modelURL)
   let input = try MLMultiArray(shape: [1, 20], dataType: .int32)
   let prediction = try model.prediction(from: input)
   // Should return valid class probabilities
   ```

4. **Accuracy validation**:
   ```python
   # Compare PyTorch vs CoreML predictions on test set
   # Difference should be < 0.01 for all samples
   ```

## Dependencies

- Ticket 23 (Hebrew sofits fine-tuning) - can proceed in parallel
- No blocking dependencies

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Architecture changes reduce accuracy | Low | Medium | Validate on test set before committing |
| torch.jit.script also fails | Medium | High | Fall back to Option C (CNN-only) |
| CoreML version incompatibility | Low | Medium | Test on target macOS versions |
| Retraining required | Medium | Medium | Use existing weights if architecture compatible |

## References

- PyTorch JIT documentation: https://pytorch.org/docs/stable/jit.html
- CoreML Tools: https://coremltools.readme.io/docs
- TracerWarning explanation: https://pytorch.org/docs/stable/generated/torch.jit.trace.html
- Project best practices: `/Users/sasha/IdeaProjects/personal_projects/omfk/.sdd/best_practices.md`
- Architecture spec: `/Users/sasha/IdeaProjects/personal_projects/omfk/.sdd/architect.md`
- Agent instructions: `/Users/sasha/IdeaProjects/personal_projects/omfk/.sdd/agent.md`

## Error Log (Full)

```
Exporting to CoreML...
scikit-learn version 1.8.0 is not supported. Minimum required version: 0.17. Maximum required version: 1.5.1. Disabling scikit-learn conversion API.
Torch version 2.9.1 has not been tested with coremltools. You may run into unexpected errors. Torch 2.7.0 is the most recent version that has been tested.
Loading EnsembleModel (CNN + Transformer)
Total parameters: 3,462,292

TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  min_len = min(c2.size(2), c3.size(2), c4.size(2), c5.size(2))

TracerWarning: Converting a tensor to a Python boolean might cause the trace to be incorrect. We can't record the data flow of Python values, so this value will be treated as a constant in the future. This means that the trace might not generalize to other inputs!
  min_len = min(x_a.size(2), x_b.size(2))

torch.jit._trace.TracingCheckError: Tracing failed sanity checks!
ERROR: Graphs differed across invocations!
```

## Estimated Effort

- Option A (recommended): 4-8 hours
- Option B (script): 8-16 hours  
- Option C (fallback): 2-4 hours
- Testing & validation: 2-4 hours

**Total**: 1-2 days for recommended path
