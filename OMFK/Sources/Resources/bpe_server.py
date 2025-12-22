#!/usr/bin/env python3
"""BPE validation server for OMFK - runs as subprocess"""
import sys
import sentencepiece as spm

# Load model
sp = spm.SentencePieceProcessor()
sp.Load(sys.argv[1] if len(sys.argv) > 1 else 'sentencepiece.bpe.model')

# Simple protocol: read line, output token count
for line in sys.stdin:
    text = line.strip()
    if not text:
        print(0, flush=True)
        continue
    tokens = sp.EncodeAsPieces(text)
    # Score: fewer tokens per char = better
    # Normalize by length to handle different word lengths
    score = len(tokens) / max(len(text), 1)
    print(f"{len(tokens)}|{score:.3f}", flush=True)
