#!/usr/bin/env python3
"""Benchmark script for layout detection model - generates confusion matrix and accuracy report."""
import json
import argparse
import subprocess
import sys
from collections import defaultdict

CLASSES = ['ru', 'en', 'he', 'ru_from_en', 'he_from_en', 'en_from_ru', 'en_from_he', 'he_from_ru', 'ru_from_he']

def run_swift_prediction(test_cases_path):
    """Run Swift test binary to get predictions (placeholder - requires Swift integration)."""
    # This would invoke a Swift CLI tool that loads the model and predicts
    # For now, return None to indicate manual testing needed
    return None

def calculate_metrics(predictions, test_cases):
    """Calculate confusion matrix and per-class accuracy."""
    confusion = defaultdict(lambda: defaultdict(int))
    correct = defaultdict(int)
    total = defaultdict(int)
    
    for tc, pred in zip(test_cases, predictions):
        expected = tc['expected_class']
        confusion[expected][pred] += 1
        total[expected] += 1
        if expected == pred:
            correct[expected] += 1
    
    return confusion, correct, total

def print_confusion_matrix(confusion, classes):
    """Print formatted confusion matrix."""
    print("\n=== CONFUSION MATRIX ===")
    print(f"{'Actual/Pred':<15}", end='')
    for cls in classes:
        print(f"{cls[:8]:<10}", end='')
    print()
    
    for actual in classes:
        print(f"{actual:<15}", end='')
        for pred in classes:
            count = confusion[actual][pred]
            print(f"{count:<10}", end='')
        print()

def print_accuracy_report(correct, total, classes):
    """Print per-class accuracy report."""
    print("\n=== ACCURACY PER CLASS ===")
    overall_correct = 0
    overall_total = 0
    
    for cls in classes:
        t = total[cls]
        c = correct[cls]
        acc = (c / t * 100) if t > 0 else 0
        overall_correct += c
        overall_total += t
        status = "✓" if acc >= 80 else "✗"
        print(f"{cls:<15}: {c:>3}/{t:<3} ({acc:>5.1f}%) {status}")
    
    overall_acc = (overall_correct / overall_total * 100) if overall_total > 0 else 0
    print(f"\n{'OVERALL':<15}: {overall_correct:>3}/{overall_total:<3} ({overall_acc:>5.1f}%)")
    return overall_acc

def main():
    parser = argparse.ArgumentParser(description='Benchmark layout detection model')
    parser.add_argument('--test_cases', default='test_cases.json', help='Path to test cases JSON')
    parser.add_argument('--predictions', default=None, help='Path to predictions JSON (optional)')
    parser.add_argument('--threshold', type=float, default=80.0, help='Minimum accuracy threshold')
    args = parser.parse_args()
    
    with open(args.test_cases, 'r', encoding='utf-8') as f:
        data = json.load(f)
    test_cases = data['test_cases']
    
    if args.predictions:
        with open(args.predictions, 'r', encoding='utf-8') as f:
            predictions = json.load(f)['predictions']
    else:
        # Try to run Swift prediction
        predictions = run_swift_prediction(args.test_cases)
        if predictions is None:
            print("No predictions available. Run Swift tests to generate predictions.")
            print(f"\nTest cases summary ({len(test_cases)} total):")
            for cls in CLASSES:
                count = sum(1 for tc in test_cases if tc['expected_class'] == cls)
                print(f"  {cls}: {count}")
            return 0
    
    confusion, correct, total = calculate_metrics(predictions, test_cases)
    print_confusion_matrix(confusion, CLASSES)
    overall_acc = print_accuracy_report(correct, total, CLASSES)
    
    if overall_acc < args.threshold:
        print(f"\n❌ FAIL: Overall accuracy {overall_acc:.1f}% < {args.threshold}% threshold")
        return 1
    else:
        print(f"\n✓ PASS: Overall accuracy {overall_acc:.1f}% >= {args.threshold}% threshold")
        return 0

if __name__ == "__main__":
    sys.exit(main())
