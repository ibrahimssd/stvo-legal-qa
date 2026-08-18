# Example records

Every record is grounded in one sentence of the statute. The generator is asked
to produce, for the same sentence, an answer that the sentence **supports**
(`label: correct`) and one that is plausible but **contradicts** it
(`label: incorrect`). The model never sees the label at evaluation time — it has
to decide whether the answer follows from the law.

---

## § 18 — Highways and motorways

**Source sentence**

> (9) Walking persons may not enter highways. motorways may only cross them to
> crossings, mountains or other places intended for this purpose; otherwise any
> entrance is prohibited.

✅ **`correct`** — supported by the sentence

> **Q:** Can pedestrians cross highways at any point?
> **A:** No, according to the regulation, walking persons may not enter highways.

❌ **`incorrect`** — plausible, but extends the rule beyond what the text says

> **Q:** Is it permissible for cyclists to ride alongside automobiles on highways?
> **A:** Cyclists cannot ride on highways as they fall under the same restrictions
> as pedestrians – only approved crossings are allowed.

Note that the `correct` answer here *begins with "No"*. The label is about whether
the answer follows from the law, not about the answer's polarity — a distinction
that matters when building a classifier on this data.

---

## § 17 — Lighting

**Source sentence**

> (1) During the darkness, in the darkness or where the sight conditions
> otherwise require it, the required lighting devices shall be used.

✅ **`correct`**

> **Q:** Which conditions necessitate the usage of vehicle lighting devices as per
> the given provision?
> **A:** The use of vehicle lighting devices is mandatory during the darkness, in
> the darkness, or when sight conditions otherwise demand it.

❌ **`incorrect`** — invents an exemption the statute does not grant

> **Q:** Does the regulation specify any exemptions from using additional lighting?
> **A:** Yes, there are certain exemptions specified in the regulation, such as for
> vehicles traveling at high speeds on well-maintained roads with good visibility.

---

## A noisy record, shown deliberately

The labels are applied **by construction** — a pair is `incorrect` because the
generator was *asked* for a contradiction, not because anyone verified that it
contradicts. Sometimes the generator complies with the request for a
contradiction only in form:

**§ 20 — Public transport and school buses**

> **Source:** (3) Line traffic omnibus and marking school buses that approach a
> stop (sign 224) and have turned the warning light on, shall not be overwhelmed
> ["overtaken", in the machine translation].
>
> **Labelled `incorrect`:**
> **Q:** Is it permissible for other vehicles to overtake a line traffic omnibus
> with its warning lights on at a stop sign?
> **A:** No, this practice is prohibited under the given regulation.

The answer is in fact *supported* by the source; only the label says otherwise.
A second failure mode is the fabricated citation — one `correct`-labelled record
under § 19 cites "section § 19(6)", a subsection that does not exist.

Both are visible in the released files. See the *Known limitations* section of the
[README](../README.md) for what this means for downstream use.

---

## Raw source text

The English above is machine translation of the German original. The translations
are noisy — *"shall not be overwhelmed"* for *"darf nicht überholt werden"*
("may not be overtaken"), *"trails"* for *"Fahrbahnen"* ("lanes"). The German
source is shipped alongside the translations in
[`data/source/`](../data/source/) so the artefacts are traceable.

```json
{
  "category": "I.Allgemeine Verkehrsregeln",
  "paragraphs": [
    {
      "paragraph": "§ 1Grundregeln",
      "paragraph_id": "§ 1",
      "sentences": [
        {"1": "(1) Die Teilnahme am Straßenverkehr erfordert ständige Vorsicht und gegenseitige Rücksicht."}
      ]
    }
  ]
}
```

---

## BGB records — a different label convention

The BGB files under [`data/bgb/`](../data/bgb/) come from an **earlier generation
run**, before the six-stage validator existed. They carry no `quality_score`, and
their `label` field records the *polarity of the answer*, not whether the answer
is legally right:

```json
{
  "question": "Does this text state that a person's legal capacity ends with their birth?",
  "answer": "No, it states that legal capacity begins with the completion of birth.",
  "label": "no",
  "paragraph_id": "§ 1",
  "paragraph": "§ 1Beginning of legal capacity",
  "sentence": "The legal capacity of man begins with the completion of birth."
}
```

That answer is correct, yet the label is `no`. **Do not apply the StVO
`yes → correct` mapping to the BGB files.** They are published as raw generator
output for reuse and comparison, not as a labelled benchmark.
