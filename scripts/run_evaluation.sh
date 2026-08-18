#!/bin/bash
# Benchmark encoder models on the synthetic StVO Q&A test set.
#
#   Step 1  corpus analysis — statistics, linguistic diversity, report
#   Step 2  zero-shot binary classification for each model in MODELS
#
# Step 1 is CPU-only. Step 2 needs a GPU and downloads models from the Hub;
# gated checkpoints require HF_TOKEN.
# Run from the repository root:  bash scripts/run_evaluation.sh

set -e

HF_TOKEN="${HF_TOKEN:?Set HF_TOKEN in your environment before running}"

DATASET_FILE="${DATASET_FILE:-data/stvo/qa_test.jsonl}"
EVAL_DIR="${EVAL_DIR:-outputs/evaluation_$(date +%Y%m%d_%H%M%S)}"
CACHE_DIR="${CACHE_DIR:-}"          # empty = the standard Hugging Face cache
ARGS_OUT="${ARGS_OUT:-outputs/training_args}"

# Local directory of fine-tuned checkpoints to evaluate alongside the base
# models. Each subdirectory holding a config.json is picked up automatically.
# Leave unset to benchmark the base models only.
FINE_TUNED_DIR="${FINE_TUNED_DIR:-}"

# Base encoders to benchmark. These are the legal-domain models reported in the
# paper; add or remove freely.
BASE_MODELS=(
    nlpaueb/bert-base-uncased-echr
    nlpaueb/bert-base-uncased-eurlex
    nlpaueb/bert-base-uncased-contracts
    casehold/custom-legalbert
    dlicari/Italian-Legal-BERT
    google-bert/bert-base-uncased
    nlpaueb/legal-bert-base-uncased
    nlpaueb/legal-bert-small-uncased
    avichr/Legal-heBERT
)

mkdir -p "$EVAL_DIR/figures" "$ARGS_OUT"

# --- Build the model list: each base model, followed by any fine-tuned
# checkpoint whose directory name starts with that base model's name. ---
MODELS=()
USED_TUNED_MODELS=()

DISCOVERED=()
if [ -n "$FINE_TUNED_DIR" ]; then
    echo "Discovering fine-tuned checkpoints in: $FINE_TUNED_DIR"
    shopt -s nullglob
    for MODEL_DIR in "$FINE_TUNED_DIR"/*; do
        if [ -d "$MODEL_DIR" ] && [ -f "$MODEL_DIR/config.json" ]; then
            DISCOVERED+=("$(basename "$MODEL_DIR")")
        fi
    done
    shopt -u nullglob
fi

for BASE_MODEL in "${BASE_MODELS[@]}"; do
    BASE_MODEL_NAME=$(basename "$BASE_MODEL")
    MODELS+=("$BASE_MODEL")

    for TUNED_MODEL in "${DISCOVERED[@]}"; do
        # Prefix match, not substring: stops 'bert-base' from claiming
        # checkpoints that belong to 'legal-bert-base'.
        if [[ "$TUNED_MODEL" == "${BASE_MODEL_NAME}"_* ]]; then
            if [[ ! " ${USED_TUNED_MODELS[*]} " =~ " ${TUNED_MODEL} " ]]; then
                MODELS+=("$TUNED_MODEL")
                USED_TUNED_MODELS+=("$TUNED_MODEL")
                echo "Mapped: $BASE_MODEL_NAME -> $TUNED_MODEL"
            fi
        fi
    done
done

echo "Models to evaluate (${#MODELS[@]}):"
printf ' - %s\n' "${MODELS[@]}"

echo "=========================================="
echo "Step 1: dataset analysis"
echo "=========================================="
python evaluation/evaluation_suite.py \
    --dataset_path "$DATASET_FILE" \
    --output_dir "$EVAL_DIR" \
    --run_analysis

echo "=========================================="
echo "Step 2: zero-shot evaluation"
echo "=========================================="
for MODEL_NAME in "${MODELS[@]}"; do
    echo "--- $MODEL_NAME"
    python evaluation/evaluation_suite.py \
        --dataset_path "$DATASET_FILE" \
        --base_model "$MODEL_NAME" \
        --output_dir "$EVAL_DIR" \
        --training_args_out "$ARGS_OUT" \
        ${FINE_TUNED_DIR:+--fine_tuned_dir "$FINE_TUNED_DIR"} \
        ${CACHE_DIR:+--cache_dir "$CACHE_DIR"} \
        --access_token "$HF_TOKEN" \
        --run_fine_tuning \
        --binary_classification \
        --zero_shot_eval
done

# To fine-tune instead of evaluating zero-shot, drop --zero_shot_eval and add
# the split proportions, e.g.:
#   --epochs 5 --train_size 0.6 --val_size 0.1 --test_size 0.3

echo "Done. Results written to $EVAL_DIR/"
