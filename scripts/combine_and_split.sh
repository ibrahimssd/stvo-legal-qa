#!/bin/bash
# Combine the generation runs into the released corpus and draw the split.
#
#   1. merge the 11 variants, drop exact and near duplicates, apply the quality gate
#   2. normalise yes/no labels to correct/incorrect
#   3. split by paragraph_id so train and test share no paragraph
#
# CPU only. Run from the repository root:  bash scripts/combine_and_split.sh
#
# WARNING: with --resplit this overwrites the released qa_train.jsonl and
# qa_test.jsonl with a fresh split. Results then stop being comparable to the
# published numbers. Set OUT to somewhere else to keep the released files.

set -e

VARIANTS="${VARIANTS:-data/stvo/variants}"
OUT="${OUT:-outputs/corpus}"

mkdir -p "$OUT"

echo "=========================================="
echo "Combine, deduplicate, quality gate"
echo "=========================================="

# The exact input list behind the released data/stvo/qa.jsonl.
python generation/combine_and_clean.py \
    --input \
        "$VARIANTS/qa_chocolatine_balanced.jsonl" \
        "$VARIANTS/qa_mistral_fast.jsonl" \
        "$VARIANTS/qa_llama_highquality.jsonl" \
        "$VARIANTS/qa_domain_contract.jsonl" \
        "$VARIANTS/qa_domain_regulatory.jsonl" \
        "$VARIANTS/qa_domain_traffic_law.jsonl" \
        "$VARIANTS/qa_threshold_0.55_mistral.jsonl" \
        "$VARIANTS/qa_threshold_0.60_mistral.jsonl" \
        "$VARIANTS/qa_threshold_0.65_mistral.jsonl" \
        "$VARIANTS/qa_threshold_0.70_mistral.jsonl" \
        "$VARIANTS/qa_llama_incremental_total.jsonl" \
    --output "$OUT/qa.jsonl" \
    --stats "$OUT/qa_stats.json" \
    --min-quality 0.6 \
    --similarity-threshold 0.85

echo "=========================================="
echo "Normalise labels, split by paragraph"
echo "=========================================="

python generation/preprocess_data.py \
    --input "$OUT/qa.jsonl" \
    --train "$OUT/qa_train.jsonl" \
    --test "$OUT/qa_test.jsonl" \
    --normalize_labels \
    --resplit

echo "=========================================="
echo "Validate"
echo "=========================================="

python generation/validate_qa_dataset.py "$OUT/qa.jsonl"

echo "Done. Corpus in $OUT/"
