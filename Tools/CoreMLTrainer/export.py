import torch
import coremltools as ct
from train import LayoutClassifier, INPUT_LENGTH, CLASSES
import argparse

def export(args):
    # Load PyTorch model
    model = LayoutClassifier()
    model.load_state_dict(torch.load(args.model_in))
    model.eval()
    
    # Trace the model
    example_input = torch.randint(0, 100, (1, INPUT_LENGTH)).long()
    traced_model = torch.jit.trace(model, example_input)
    
    # Convert to CoreML
    # Note: We need to define input types carefully. 
    # CoreML expects multi-array inputs for basic conversions unless using specific text models.
    # Since we do custom tokenization in Swift, we will accept MultiArray input of shape (12).
    
    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.TensorType(name="input_ids", shape=(1, INPUT_LENGTH), dtype=int)],
        outputs=[ct.TensorType(name="classLogits")],
        convert_to="neuralnetwork"
    )
    
    # Add metadata
    mlmodel.author = "OMFK Agent"
    mlmodel.short_description = "Layout Classifier (Fast Path)"
    mlmodel.user_defined_metadata["classes"] = ",".join(CLASSES)
    
    # Save
    mlmodel.save(args.output)
    print(f"CoreML model saved to {args.output}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--model_in', default='model.pth')
    parser.add_argument('--output', default='LayoutClassifier.mlmodel')
    args = parser.parse_args()
    export(args)
