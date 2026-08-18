#!/usr/bin/env python3
"""
Preprocess the combined Q&A corpus into the released train/test splits.

Two steps:

1. Label normalisation — the generator emits ``yes``/``no`` (does the answer
   follow from the source sentence?). Downstream classification uses
   ``correct``/``incorrect``. This rewrites the labels in place.

2. Paragraph-disjoint split — train and test never share a paragraph_id, so a
   model cannot score by memorising paragraph content it has already seen.

By default this script only *verifies* the shipped splits. Pass ``--resplit``
to draw a fresh split; note that this replaces the released one, and results
will no longer be comparable to the numbers reported in the paper.

    python generation/preprocess_data.py                 # verify the shipped splits
    python generation/preprocess_data.py --resplit       # draw a new split
"""

import argparse
import json
import random
from pathlib import Path


def replace_data(input_file, output_file):
    """Rewrite yes/no labels as correct/incorrect."""
    with open(input_file, 'r', encoding='utf-8') as f:
        data = [json.loads(line) for line in f if line.strip()]

    for item in data:
        if item['label'] == 'yes':
            item['label'] = 'correct'
        elif item['label'] == 'no':
            item['label'] = 'incorrect'

    with open(output_file, 'w', encoding='utf-8') as f:
        for item in data:
            json.dump(item, f, ensure_ascii=False)
            f.write('\n')

    return data


def split_train_test_by_paragraph_id(input_file, train_file, test_file,
                                     test_size=0.16, seed=42):
    """Split by paragraph_id so no paragraph appears in both train and test."""
    with open(input_file, 'r', encoding='utf-8') as f:
        data = [json.loads(line) for line in f if line.strip()]

    # Group data by paragraph_id
    paragraph_groups = {}
    for item in data:
        paragraph_groups.setdefault(item['paragraph_id'], []).append(item)

    # Split paragraph groups into train and test
    paragraph_ids = list(paragraph_groups.keys())
    random.Random(seed).shuffle(paragraph_ids)
    split_index = int(len(paragraph_ids) * (1 - test_size))
    train_paragraphs = paragraph_ids[:split_index]
    test_paragraphs = paragraph_ids[split_index:]

    # Write train and test files
    with open(train_file, 'w', encoding='utf-8') as train_f, \
            open(test_file, 'w', encoding='utf-8') as test_f:
        for pid in train_paragraphs:
            for item in paragraph_groups[pid]:
                json.dump(item, train_f, ensure_ascii=False)
                train_f.write('\n')
        for pid in test_paragraphs:
            for item in paragraph_groups[pid]:
                json.dump(item, test_f, ensure_ascii=False)
                test_f.write('\n')


def load(path):
    with open(path, 'r', encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]


def report(train_data, test_data):
    """Print split statistics and assert the paragraph-disjointness guarantee."""
    print(f"Train data: {len(train_data)} samples")
    print(f"Test data: {len(test_data)} samples")

    train_paragraphs = set(item['paragraph_id'] for item in train_data)
    test_paragraphs = set(item['paragraph_id'] for item in test_data)
    assert not train_paragraphs & test_paragraphs, \
        "Paragraphs overlap between train and test!"
    print("No paragraph overlap between train and test data.")

    print(f"Unique paragraphs in train data: {len(train_paragraphs)}")
    print(f"Unique paragraphs in test data: {len(test_paragraphs)}")

    train_qa_pairs = set((item['question'], item['answer']) for item in train_data)
    test_qa_pairs = set((item['question'], item['answer']) for item in test_data)
    print(f"Unique question-answer pairs in train data: {len(train_qa_pairs)}")
    print(f"Unique question-answer pairs in test data: {len(test_qa_pairs)}")

    for name, data in (("Train", train_data), ("Test", test_data)):
        distribution = {'correct': 0, 'incorrect': 0}
        for item in data:
            distribution[item['label']] += 1
        correct_pct = distribution['correct'] / len(data) * 100
        incorrect_pct = distribution['incorrect'] / len(data) * 100
        print(f"{name} label distribution: {distribution} "
              f"({correct_pct:.2f}% correct / {incorrect_pct:.2f}% incorrect)")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--input', default='data/stvo/qa.jsonl',
                        help="Combined Q&A corpus")
    parser.add_argument('--train', default='data/stvo/qa_train.jsonl')
    parser.add_argument('--test', default='data/stvo/qa_test.jsonl')
    parser.add_argument('--normalize_labels', action='store_true',
                        help="Rewrite yes/no labels as correct/incorrect in --input "
                             "(the released qa.jsonl is already normalised)")
    parser.add_argument('--resplit', action='store_true',
                        help="Draw a new paragraph-disjoint split, replacing the released one")
    parser.add_argument('--test_size', type=float, default=0.16,
                        help="Fraction of paragraphs held out for test")
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()

    if args.normalize_labels:
        replace_data(args.input, args.input)
        print(f"Normalised labels in {args.input}")

    if args.resplit:
        split_train_test_by_paragraph_id(args.input, args.train, args.test,
                                         test_size=args.test_size, seed=args.seed)
        print(f"Wrote a fresh split to {args.train} and {args.test}")

    for path in (args.train, args.test):
        if not Path(path).exists():
            parser.error(f"{path} not found — run with --resplit to create it")

    report(load(args.train), load(args.test))


if __name__ == "__main__":
    main()
