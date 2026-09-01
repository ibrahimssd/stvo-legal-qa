<div align="center">

# StVO-Legal-QA

### A synthetic question-answering corpus over German road traffic law — and the pipeline that built it

[![Data](https://img.shields.io/badge/QA%20pairs-12%2C554-blue)]()
[![Split](https://img.shields.io/badge/split-paragraph--disjoint-success)]()
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Code](https://img.shields.io/badge/code-MIT-green)](LICENSE)
[![Data license](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey)](LICENSE)

</div>

---

Legal QA benchmarks are scarce because annotating them requires lawyers. This
repository releases **12,554 question–answer pairs grounded sentence-by-sentence
in the German *Straßenverkehrs-Ordnung* (StVO)**, together with the full pipeline
that produced them: prompting, a six-stage validator, deduplication, a
paragraph-disjoint split, and an evaluation suite for benchmarking encoders on
the result.

The pipeline is not StVO-specific. Point it at any statute parsed into the same
structured JSON — paragraphs containing numbered sentences — and it will generate,
filter, and split a corpus the same way.

**The task.** Each record pairs a question with an answer that either *follows
from* the source sentence (`correct`) or is *plausible but contradicts it*
(`incorrect`). A model must decide which — not retrieve the answer, but judge
whether it is legally supported.

---

## Quickstart

```bash
git clone https://github.com/ibrahimssd/stvo-legal-qa.git
cd stvo-legal-qa
pip install -r requirements.txt
```

The data is plain JSONL — no loading script, no dependencies:

```python
import json

train = [json.loads(l) for l in open("data/stvo/qa_train.jsonl", encoding="utf-8")]
test  = [json.loads(l) for l in open("data/stvo/qa_test.jsonl",  encoding="utf-8")]

print(len(train), len(test))          # 10245 2309
print(train[0]["question"], train[0]["label"])
```

Verify what you got, and confirm the split guarantee:

```bash
python generation/validate_qa_dataset.py data/stvo/qa.jsonl
python generation/preprocess_data.py
```

---

## Dataset card

### Files

| Path | Records | What it is |
|:--|--:|:--|
| [`data/stvo/qa.jsonl`](data/stvo/qa.jsonl) | 12,554 | The full corpus — all variants combined, deduplicated, quality-gated |
| [`data/stvo/qa_train.jsonl`](data/stvo/qa_train.jsonl) | 10,245 | Train split — 49 paragraphs |
| [`data/stvo/qa_test.jsonl`](data/stvo/qa_test.jsonl) | 2,309 | Test split — 10 paragraphs, **disjoint from train** |
| [`data/stvo/variants/`](data/stvo/variants/) | 17,870 | The 11 individual generation runs, before combining |
| [`data/stvo/metadata/`](data/stvo/metadata/) | 22 files | One manifest per run: model, settings, yield, quality metrics |
| [`data/bgb/`](data/bgb/) | 18,550 | Bürgerliches Gesetzbuch QA — **raw, earlier convention** (see below) |
| [`data/source/`](data/source/) | 3 files | The parsed statute the pairs were generated from (DE + two translations) |

### Record schema

```json
{
  "question": "Which conditions necessitate the usage of vehicle lighting devices as per the given provision?",
  "answer": "The use of vehicle lighting devices is mandatory during the darkness, in the darkness, or when sight conditions otherwise demand it.",
  "label": "correct",
  "quality_score": 0.8,
  "paragraph_id": "§ 17",
  "paragraph": "§ 17Lighting",
  "sentence": "(1) During the darkness, in the darkness or where the sight conditions otherwise require it, the required lighting devices shall be used.",
  "is_yes_no_question": true,
  "language": "en",
  "generation_attempt": 1,
  "sentence_length": 136
}
```

| Field | Type | Meaning |
|:--|:--|:--|
| `question`, `answer` | str | The pair |
| `label` | str | `correct` — the answer follows from `sentence`; `incorrect` — plausible but contradicts it |
| `quality_score` | float | Composite score from the validator, 0–1. Everything released scores **≥ 0.65** |
| `paragraph_id` | str | The § the pair is grounded in — **the unit the split is drawn on** |
| `paragraph` | str | Paragraph heading (id concatenated with title, as parsed) |
| `sentence` | str | The exact source sentence. Every pair is traceable to it |
| `is_yes_no_question` | bool | Whether the question is *phrased* as a yes/no question |
| `language` | str | `en` throughout the released corpus |
| `generation_attempt` | int | Which retry produced this pair (1–4); the generator retries on validation failure |
| `sentence_length` | int | Characters in `sentence` |

> **On labels.** `label` is about legal support, **not answer polarity**. A
> `correct` answer may well begin with "No" — see
> [`docs/example_records.md`](docs/example_records.md). Raw generator output uses
> `yes`/`no` for the same distinction; `generation/preprocess_data.py` renames
> them to `correct`/`incorrect`. Files under `data/stvo/variants/` still carry the
> raw `yes`/`no`.

### Statistics — `qa.jsonl`

| | |
|:--|:--|
| Records | 12,554 |
| Label balance | 6,277 `correct` / 6,277 `incorrect` — exactly balanced by construction |
| Paragraphs covered | 59 §§ |
| Language | English (machine-translated statute) |
| Question length | 14.9 words mean, range 3–35 |
| Answer length | 25.4 words mean, range 3–82 |
| Quality score | 0.8 for 11,716 records; 0.7 for 602; 0.65 for 231; 1.0 for 5 |
| Phrased as yes/no | 10,013 of 12,554 (80 %) |

### The split

Train and test share **no paragraph**. 10 of 59 §§ (17 %) are held out
entirely — `§ 2, § 12, § 18, § 20, § 31, § 33, § 36a, § 38, § 44a, § 47`. A model
cannot score by memorising paragraph text it saw in training, because it has
never seen those paragraphs at all.

```
train  10,245 pairs  49 §§   5,137 correct / 5,108 incorrect
test    2,309 pairs  10 §§   1,140 correct / 1,169 incorrect
```

`generation/preprocess_data.py` asserts the disjointness on every run.

---

## How the corpus was built

### 1 — Generation

[`generation/legal_qa_generation.py`](generation/legal_qa_generation.py) walks the
statute sentence by sentence. For each sentence it prompts an instruction-tuned
LLM for *n* pairs — half supported by the sentence, half plausible-but-contradicting —
supplying the surrounding paragraph as context. Failures are retried up to
`--max_retries` times.

Three prompt variants (`--domain_type`) frame the same statute differently:
`traffic_law`, `regulatory`, `contract`. Every released run used
`--pairs_per_sentence 4` over the m2m100 translation:

| Variant | Generator | Gate | Records |
|:--|:--|--:|--:|
| `qa_llama_incremental_total` | Llama-2-7b-chat-hf | 0.65 | 8,717 |
| `qa_mistral_fast` | Mistral-7B-Instruct-v0.2 | 0.60 | 1,016 |
| `qa_threshold_0.55` … `0.70` | Mistral-7B-Instruct-v0.2 | 0.55–0.70 | 1,000 each |
| `qa_domain_regulatory` | Llama-2-7b-chat-hf | 0.65 | 956 |
| `qa_domain_traffic_law` | Llama-2-7b-chat-hf | 0.65 | 881 |
| `qa_llama_highquality` | Llama-2-7b-chat-hf | 0.65 | 829 |
| `qa_domain_contract` | Llama-2-7b-chat-hf | 0.65 | 770 |
| `qa_chocolatine_balanced` | Chocolatine-14B-Instruct-DPO-v1.2 | 0.65 | 701 |

The `threshold_*` runs sweep the quality gate from 0.55 to 0.70 — they exist so
the effect of the filter itself can be studied, and they are the one set
generated *without* `--shuffle_sentences`, so all four traverse the statute in
the same order. `qa_llama_incremental_total` was produced as ten resumable
batches of 1,000 and concatenated; the per-batch manifests survive as
`qa_batch_0..9_info.json`.

Exact settings for every run are in that run's manifest under
[`data/stvo/metadata/`](data/stvo/metadata/), and the runs themselves are
reproduced scenario-by-scenario in
[`scripts/generate_dataset.sh`](scripts/generate_dataset.sh).

### 2 — Six-stage validation

Every generated pair passes through `validate_qa_pair()` before it is kept.
A failure at any stage discards the pair and triggers a retry:

1. **Structure** — required fields present; German/English field aliases
   normalised; label in the valid set; question ≠ answer.
2. **Language consistency** — a German run containing common English function
   words is rejected outright.
3. **Length bounds** — question 15–200 chars, answer 20–500 chars.
4. **Non-reasoning rejection** — a yes/no-phrased question answered with a bare
   "yes"/"no"/"true"/"false" carries no reasoning, and is dropped.
5. **Placeholder and paraphrase detection** — `xxx`, `example`, `[...]` and
   friends; plus question/answer Jaccard overlap > 0.7, which catches answers
   that merely restate the question.
6. **Legal terminology** — the pair must contain at least one term from a
   curated domain lexicon (*Vorfahrt*, right of way, Halteverbot, …), which
   filters generic small talk about the text.

Surviving pairs are scored on a composite metric — length, generic-question
patterns, source overlap (too little suggests hallucination, too much suggests
copying), degenerate answers, repetition — and anything below
`--min_quality_score` (default **0.6**) is dropped.

### 3 — Combining and splitting

[`generation/combine_and_clean.py`](generation/combine_and_clean.py) merges the
runs, hashes out exact duplicates, then does near-duplicate removal *within each
`paragraph_id` group* — a cheap way to avoid the O(N²) all-pairs comparison,
since duplicates almost always share a source paragraph.
[`generation/preprocess_data.py`](generation/preprocess_data.py) then normalises
the labels and draws the paragraph-disjoint split.

Reproduce the whole thing:

```bash
export HF_TOKEN=...                      # gated generators (Llama, Mistral) need this
bash scripts/generate_dataset.sh         # GPU — one scenario per released variant
bash scripts/combine_and_split.sh        # CPU — merge, deduplicate, split
```

`generate_dataset.sh` ships with one scenario active and the rest commented out;
running all of them takes days on a single GPU. For a cluster, submit
[`scripts/slurm/generate_dataset.sm`](scripts/slurm/generate_dataset.sm).
`combine_and_split.sh` carries the exact 11-file input list behind the released
`qa.jsonl`.

---

## Evaluation suite

[`evaluation/evaluation_suite.py`](evaluation/evaluation_suite.py) does two jobs.

**Corpus analysis** — statistics, label and length distributions, type-token
ratios, n-gram diversity, and a markdown report. CPU only:

```bash
python evaluation/evaluation_suite.py \
    --dataset_path data/stvo/qa_test.jsonl \
    --output_dir outputs/analysis \
    --run_analysis
```

The committed [`evaluation/analysis/`](evaluation/analysis/) holds the output of
exactly this command on the test split, so you can diff against it.

**Model benchmarking** — treats the corpus as binary classification over
(question, answer) pairs, zero-shot or fine-tuned, across a list of encoders,
and writes per-model reports plus a comparison CSV:

```bash
export HF_TOKEN=...
bash scripts/run_evaluation.sh
```

Set `FINE_TUNED_DIR=/path/to/checkpoints` to fold local checkpoints into the
sweep — each subdirectory containing a `config.json` is discovered and matched to
its base model by name prefix. `evaluation/tables.py`,
`evaluation/visualize_data.py`, and `evaluation/paper_visualize.py` turn the
resulting reports into the tables and figures used in the paper.

---

## Repository layout

```
├── data/
│   ├── stvo/            qa.jsonl + train/test splits, variants/, metadata/
│   ├── bgb/             Bürgerliches Gesetzbuch QA (raw, older convention)
│   └── source/          parsed statute — the input to generation
├── generation/
│   ├── legal_qa_generation.py   prompting + six-stage validation
│   ├── combine_and_clean.py     merge, deduplicate, quality gate
│   ├── preprocess_data.py       label normalisation + paragraph-disjoint split
│   └── validate_qa_dataset.py   standalone corpus validator
├── evaluation/
│   ├── evaluation_suite.py      corpus analysis + model benchmarking
│   ├── llm_evaluator.py         baseline encoder evaluator
│   ├── report.py                experiment tracking and reports
│   ├── tables.py, visualize_data.py, paper_visualize.py
│   └── analysis/                committed analysis of the test split
├── scripts/
│   ├── generate_dataset.sh      one scenario per released variant
│   ├── combine_and_split.sh     merge, deduplicate, label, split
│   ├── run_evaluation.sh        analysis + zero-shot benchmark sweep
│   └── slurm/                   the SLURM envelope the corpus was generated in
└── docs/example_records.md      annotated records, including a noisy one
```

Scripts are written to run **from the repository root**.

---

## Related repositories

| | |
|:--|:--|
| [**stvo-legal-knowledge-graph-parser**](https://github.com/ibrahimssd/stvo-legal-knowledge-graph-parser) | The parser that turns raw StVO into the structured JSON in `data/source/`, and builds the legal knowledge graph |
| [**stvo-llm-driver**](https://github.com/ibrahimssd/stvo-llm-driver) | The research project this corpus was built for — KG-guided multi-task pre-training, and the results reported on this data |

---

## Licence

**Code** — MIT. **Data** — [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
See [LICENSE](LICENSE) for both texts and the reasoning below.

The underlying StVO and BGB are official works under § 5 UrhG and are not subject
to copyright in Germany. The English text is machine translation produced by this
project; the QA pairs are model-generated. If you redistribute or build products
on the pairs, check the terms of the generating models
(Mistral-7B-Instruct-v0.2, Llama-2) for your own use case — those terms attach to
model outputs independently of this repository's licence.

---

## Citation

```bibtex
@inproceedings{siddig2026stvo,
  title     = {Enhancing Legal Reasoning in Pre-trained Language Models via
               Knowledge Graph-Guided Multi-Task Pre-training},
  author    = {Siddig, Ibrahim and Georges, Munir},
  year      = {2026},
  note      = {Under review}
}
```

The parser that produced the structured statute is published separately:

```bibtex
@inproceedings{siddig2025parsing,
  title     = {Pattern-based Parsing of German Traffic Regulations (StVO)
               for Legal Knowledge Graph Construction (KGC)},
  author    = {Siddig, Ibrahim and Tugeev, Sviatoslav and Georges, Munir},
  booktitle = {ESSV},
  year      = {2025}
}
```
