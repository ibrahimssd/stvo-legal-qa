#!/bin/bash
# Generate the synthetic legal Q&A corpus.
#
# These are the generation runs that actually produced the released files under
# data/stvo/variants/ — each scenario below corresponds to one variant, and the
# settings match the manifests in data/stvo/metadata/. Uncomment the scenario
# you want; running all of them takes days on a single GPU.
#
# After generation, combine the runs and draw the split:
#     bash scripts/combine_and_split.sh
#
# Requires a GPU. Gated generators (Llama, Mistral) need HF_TOKEN.
# Run from the repository root:  bash scripts/generate_dataset.sh
#
# A SLURM version of this script is in scripts/slurm/generate_dataset.sm.

set -e

HF_TOKEN="${HF_TOKEN:?Set HF_TOKEN in your environment before running}"

GEN="python generation/legal_qa_generation.py"
SRC_EN="data/source/stvo_main_content_en_m2m100_418M.json"
SRC_DE="data/source/stvo_main_content_de.json"
OUT="${OUT:-data/stvo/variants}"

mkdir -p "$OUT"


# ============================================================================
# SCENARIO 1: High-quality generation with Llama  ->  qa_llama_highquality
# ============================================================================
# Expected quality scores 0.70-0.85. Slower but reliable.

echo "=== SCENARIO 1: High-quality Llama generation ==="

$GEN \
    --model_name "meta-llama/Llama-2-7b-chat-hf" \
    --num_samples 5000 \
    --pairs_per_sentence 4 \
    --domain_type "traffic_law" \
    --language "en" \
    --min_quality_score 0.65 \
    --max_retries 3 \
    --shuffle_sentences \
    --hf_token "$HF_TOKEN" \
    --input_file "$SRC_EN" \
    --output_file "$OUT/qa_llama_highquality.jsonl"


# ============================================================================
# SCENARIO 2: Fast generation with Mistral  ->  qa_mistral_fast
# ============================================================================
# Expected quality scores 0.60-0.72. Faster inference, good for prototyping.

# echo "=== SCENARIO 2: Fast Mistral generation ==="
#
# $GEN \
#     --model_name "mistralai/Mistral-7B-Instruct-v0.2" \
#     --num_samples 5000 \
#     --pairs_per_sentence 4 \
#     --domain_type "traffic_law" \
#     --language "en" \
#     --min_quality_score 0.60 \
#     --max_retries 4 \
#     --shuffle_sentences \
#     --hf_token "$HF_TOKEN" \
#     --input_file "$SRC_EN" \
#     --output_file "$OUT/qa_mistral_fast.jsonl"


# ============================================================================
# SCENARIO 3: Balanced generation with Chocolatine  ->  qa_chocolatine_balanced
# ============================================================================

# echo "=== SCENARIO 3: Balanced Chocolatine generation ==="
#
# $GEN \
#     --model_name "jpacifico/Chocolatine-14B-Instruct-DPO-v1.2" \
#     --num_samples 5000 \
#     --pairs_per_sentence 4 \
#     --domain_type "traffic_law" \
#     --language "en" \
#     --min_quality_score 0.65 \
#     --max_retries 4 \
#     --shuffle_sentences \
#     --hf_token "$HF_TOKEN" \
#     --input_file "$SRC_EN" \
#     --output_file "$OUT/qa_chocolatine_balanced.jsonl"


# ============================================================================
# SCENARIO 4: Quality threshold sweep  ->  qa_threshold_0.55 … 0.70_mistral
# ============================================================================
# Four corpora differing only in the quality gate, for studying the
# quality/quantity tradeoff of the filter itself. Note: no --shuffle_sentences,
# so all four traverse the statute in the same order.

# echo "=== SCENARIO 4: Quality threshold comparison ==="
#
# for threshold in 0.55 0.60 0.65 0.70; do
#     echo "Generating with quality threshold: $threshold"
#     $GEN \
#         --model_name "mistralai/Mistral-7B-Instruct-v0.2" \
#         --num_samples 1000 \
#         --pairs_per_sentence 4 \
#         --domain_type "traffic_law" \
#         --language "en" \
#         --min_quality_score $threshold \
#         --max_retries 4 \
#         --hf_token "$HF_TOKEN" \
#         --input_file "$SRC_EN" \
#         --output_file "$OUT/qa_threshold_${threshold}_mistral.jsonl"
# done


# ============================================================================
# SCENARIO 5: Domain-specific multi-run  ->  qa_domain_{traffic_law,regulatory,contract}
# ============================================================================
# The same statute framed through three different prompt templates.

# echo "=== SCENARIO 5: Multi-domain generation ==="
#
# for domain in "traffic_law" "regulatory" "contract"; do
#     echo "Generating for domain: $domain"
#     $GEN \
#         --model_name "meta-llama/Llama-2-7b-chat-hf" \
#         --num_samples 3000 \
#         --pairs_per_sentence 4 \
#         --domain_type "$domain" \
#         --language "en" \
#         --min_quality_score 0.65 \
#         --max_retries 4 \
#         --hf_token "$HF_TOKEN" \
#         --input_file "$SRC_EN" \
#         --output_file "$OUT/qa_domain_${domain}.jsonl"
# done


# ============================================================================
# SCENARIO 6: Incremental batches  ->  qa_llama_incremental_total
# ============================================================================
# The largest variant (8,717 pairs). Generated in ten resumable batches so a
# crash costs one batch, not the whole run. Per-batch manifests survive in
# data/stvo/metadata/qa_batch_*_info.json.

# echo "=== SCENARIO 6: Incremental batch generation ==="
#
# total_samples=10000
# batch_size=1000
# num_batches=$((total_samples / batch_size))
#
# for ((i=0; i<num_batches; i++)); do
#     echo "Batch $((i+1))/$num_batches - generating $batch_size samples"
#     $GEN \
#         --model_name "meta-llama/Llama-2-7b-chat-hf" \
#         --num_samples $batch_size \
#         --pairs_per_sentence 4 \
#         --domain_type "traffic_law" \
#         --language "en" \
#         --min_quality_score 0.65 \
#         --max_retries 4 \
#         --shuffle_sentences \
#         --hf_token "$HF_TOKEN" \
#         --input_file "$SRC_EN" \
#         --output_file "$OUT/qa_batch_${i}.jsonl"
#     echo "Batch $((i+1)) complete. Sleeping 60 seconds..."
#     sleep 60
# done
#
# cat "$OUT"/qa_batch_*.jsonl > "$OUT/qa_llama_incremental_total.jsonl"
# rm "$OUT"/qa_batch_*.jsonl


# ============================================================================
# SCENARIO 7: German generation (KNOWN TO YIELD NOTHING)
# ============================================================================
# Both German runs completed and produced ZERO surviving pairs — the
# language-consistency check in validate_qa_pair() rejects any pair containing
# common English function words, and the generators code-switch heavily on
# German legal text. The manifests are kept as a record:
#   data/stvo/metadata/qa_mistral_fast_de_info.json      (0 samples)
#   data/stvo/metadata/qa_llama_highquality_de_info.json (0 samples)
# Fixing this means loosening that check, not just rerunning the scenario.

# for model in "mistralai/Mistral-7B-Instruct-v0.2" "meta-llama/Llama-2-7b-chat-hf"; do
#     $GEN \
#         --model_name "$model" \
#         --num_samples 5000 \
#         --pairs_per_sentence 4 \
#         --domain_type "traffic_law" \
#         --language "de" \
#         --min_quality_score 0.60 \
#         --max_retries 4 \
#         --shuffle_sentences \
#         --hf_token "$HF_TOKEN" \
#         --input_file "$SRC_DE" \
#         --output_file "$OUT/qa_$(basename "$model")_de.jsonl"
# done


# ============================================================================
# Validate whatever was just generated
# ============================================================================

for f in "$OUT"/*.jsonl; do
    [ -s "$f" ] || continue
    python generation/validate_qa_dataset.py "$f"
done

echo "Done. Variants in $OUT/ — next: bash scripts/combine_and_split.sh"
