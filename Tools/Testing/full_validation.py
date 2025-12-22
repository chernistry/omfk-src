#!/usr/bin/env python3
"""
Full pipeline validation and benchmarking for OMFK.
Covers tickets 16 and 18.
"""
import json
import time
import random
import argparse
from collections import defaultdict
from pathlib import Path

CLASSES = ['ru', 'en', 'he', 'ru_from_en', 'he_from_en', 'en_from_ru', 'en_from_he', 'he_from_ru', 'ru_from_he']

def load_test_cases(path):
    with open(path) as f:
        return json.load(f)['test_cases']

def generate_edge_cases():
    """Generate edge cases for testing."""
    return [
        # Very short tokens (2 chars)
        {'input': 'hi', 'expected_class': 'en', 'category': 'short'},
        {'input': 'да', 'expected_class': 'ru', 'category': 'short'},
        {'input': 'לא', 'expected_class': 'he', 'category': 'short'},
        
        # Transliteration
        {'input': 'privet', 'expected_class': 'en', 'category': 'translit'},
        {'input': 'shalom', 'expected_class': 'en', 'category': 'translit'},
        {'input': 'spasibo', 'expected_class': 'en', 'category': 'translit'},
        
        # Slang/abbreviations
        {'input': 'lol', 'expected_class': 'en', 'category': 'slang'},
        {'input': 'хз', 'expected_class': 'ru', 'category': 'slang'},
        {'input': 'пж', 'expected_class': 'ru', 'category': 'slang'},
        
        # Numbers mixed
        {'input': 'test123', 'expected_class': 'en', 'category': 'mixed'},
        {'input': 'тест123', 'expected_class': 'ru', 'category': 'mixed'},
        
        # Punctuation
        {'input': 'hello!', 'expected_class': 'en', 'category': 'punct'},
        {'input': 'привет?', 'expected_class': 'ru', 'category': 'punct'},
        {'input': 'שלום!', 'expected_class': 'he', 'category': 'punct'},
    ]

def analyze_by_length(test_cases, predictions):
    """Analyze accuracy by token length."""
    length_buckets = {'2-3': [], '4-6': [], '7+': []}
    
    for tc, pred in zip(test_cases, predictions):
        length = len(tc['input'])
        correct = pred == tc['expected_class']
        
        if length <= 3:
            length_buckets['2-3'].append(correct)
        elif length <= 6:
            length_buckets['4-6'].append(correct)
        else:
            length_buckets['7+'].append(correct)
    
    results = {}
    for bucket, outcomes in length_buckets.items():
        if outcomes:
            results[bucket] = sum(outcomes) / len(outcomes) * 100
        else:
            results[bucket] = 0
    return results

def compute_confusion_matrix(test_cases, predictions):
    """Compute confusion matrix."""
    matrix = defaultdict(lambda: defaultdict(int))
    for tc, pred in zip(test_cases, predictions):
        matrix[tc['expected_class']][pred] += 1
    return matrix

def print_confusion_matrix(matrix):
    """Print formatted confusion matrix."""
    print("\n=== CONFUSION MATRIX ===")
    print(f"{'Actual\\Pred':<12}", end='')
    for cls in CLASSES:
        print(f"{cls[:8]:<10}", end='')
    print()
    
    for actual in CLASSES:
        print(f"{actual:<12}", end='')
        for pred in CLASSES:
            count = matrix[actual][pred]
            print(f"{count:<10}", end='')
        print()

def compute_metrics(test_cases, predictions):
    """Compute all metrics."""
    # Overall accuracy
    correct = sum(1 for tc, p in zip(test_cases, predictions) if tc['expected_class'] == p)
    total = len(test_cases)
    accuracy = correct / total * 100 if total > 0 else 0
    
    # Per-class accuracy
    per_class = defaultdict(lambda: {'correct': 0, 'total': 0})
    for tc, pred in zip(test_cases, predictions):
        per_class[tc['expected_class']]['total'] += 1
        if tc['expected_class'] == pred:
            per_class[tc['expected_class']]['correct'] += 1
    
    # False positive rate (corrections when shouldn't)
    pure_classes = ['ru', 'en', 'he']
    fp_count = 0
    fp_total = 0
    for tc, pred in zip(test_cases, predictions):
        if tc['expected_class'] in pure_classes:
            fp_total += 1
            if pred not in pure_classes:  # Predicted correction when text was correct
                fp_count += 1
    fp_rate = fp_count / fp_total * 100 if fp_total > 0 else 0
    
    return {
        'accuracy': accuracy,
        'per_class': dict(per_class),
        'false_positive_rate': fp_rate,
        'by_length': analyze_by_length(test_cases, predictions)
    }

def print_report(metrics, latency_stats=None):
    """Print validation report."""
    print("\n" + "=" * 60)
    print("OMFK VALIDATION REPORT")
    print("=" * 60)
    
    print(f"\n📊 OVERALL ACCURACY: {metrics['accuracy']:.1f}%")
    
    print("\n📈 ACCURACY BY CLASS:")
    for cls in CLASSES:
        stats = metrics['per_class'].get(cls, {'correct': 0, 'total': 0})
        acc = stats['correct'] / stats['total'] * 100 if stats['total'] > 0 else 0
        status = '✓' if acc >= 80 else '✗'
        print(f"  {status} {cls:<15}: {stats['correct']:>3}/{stats['total']:<3} ({acc:>5.1f}%)")
    
    print("\n📏 ACCURACY BY TOKEN LENGTH:")
    for bucket, acc in metrics['by_length'].items():
        target = 95 if bucket == '7+' else (90 if bucket == '4-6' else 85)
        status = '✓' if acc >= target else '✗'
        print(f"  {status} {bucket} chars: {acc:.1f}% (target: {target}%)")
    
    print(f"\n⚠️  FALSE POSITIVE RATE: {metrics['false_positive_rate']:.1f}% (target: <3%)")
    
    if latency_stats:
        print(f"\n⏱️  LATENCY:")
        print(f"  Average: {latency_stats['avg']:.2f}ms (target: <10ms)")
        print(f"  P95: {latency_stats['p95']:.2f}ms (target: <20ms)")
    
    # Summary
    print("\n" + "=" * 60)
    targets_met = (
        metrics['accuracy'] >= 95 and
        metrics['false_positive_rate'] < 3 and
        metrics['by_length'].get('7+', 0) >= 95
    )
    if targets_met:
        print("✅ ALL TARGETS MET - Ready for production")
    else:
        print("❌ SOME TARGETS NOT MET - Review needed")
    print("=" * 60)

def main():
    parser = argparse.ArgumentParser(description='OMFK Validation & Benchmarking')
    parser.add_argument('--test-cases', default='test_cases.json')
    parser.add_argument('--predictions', default=None, help='JSON file with predictions')
    parser.add_argument('--edge-cases', action='store_true', help='Include edge cases')
    parser.add_argument('--output', default='validation_report.json')
    args = parser.parse_args()
    
    # Load test cases
    test_cases = load_test_cases(args.test_cases)
    print(f"Loaded {len(test_cases)} test cases")
    
    if args.edge_cases:
        edge = generate_edge_cases()
        test_cases.extend(edge)
        print(f"Added {len(edge)} edge cases")
    
    if args.predictions:
        with open(args.predictions) as f:
            predictions = json.load(f)['predictions']
    else:
        print("\nNo predictions file provided.")
        print("Run Swift tests to generate predictions, or use --predictions flag.")
        print("\nTest case summary:")
        for cls in CLASSES:
            count = sum(1 for tc in test_cases if tc['expected_class'] == cls)
            print(f"  {cls}: {count}")
        return
    
    # Compute metrics
    metrics = compute_metrics(test_cases, predictions)
    matrix = compute_confusion_matrix(test_cases, predictions)
    
    # Print report
    print_confusion_matrix(matrix)
    print_report(metrics)
    
    # Save report
    with open(args.output, 'w') as f:
        json.dump({
            'metrics': metrics,
            'confusion_matrix': dict(matrix),
            'test_count': len(test_cases)
        }, f, indent=2)
    print(f"\nReport saved to {args.output}")

if __name__ == '__main__':
    main()
