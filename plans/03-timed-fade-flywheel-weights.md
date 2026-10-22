# 03 — Timed fade, flywheel scroll, lighter function words

## 1. Time-based fade (replaces 02's distance fade)
- When a word is said, its opacity drops immediately to 0.8, then eases
  out to 0.4 over 333 ms. A word counts as said when it's heard, or when
  its sentence passes 70% (from that moment).
- Missed words fade half as much (to 0.9, then 0.7), on the same curve,
  starting when their paragraph is completed.
- Text ahead of the cursor stays white.
- The tracker records `heardAt[word]`, `sentenceSaidAt[sentence]` and
  `paragraphDoneAt[paragraph]`.
- Only sentences with a fade in progress re-render: a
  `TimelineView(.explicit(dates))` at 60 fps until the newest fade ends,
  then nothing. No per-frame work when idle.

## 2. Flywheel scrolling
The old smooth mode set velocity = pace + k·error every frame, so a pace
update or a line change jumped the velocity. Replace it with a physical
model: velocity is state, and only acceleration changes.

Per frame:
- `pace` = speaking speed in pt/s: words/sec × average points per word
  across the document (not per sentence, which jumps on short
  sentences). It's averaged over about 4 s.
- While speaking (an advance within the last 1.2 s): spin up toward
  pace, `a += (pace − v) / 0.8 s`.
- When the speaker stops: friction only, `a −= 0.9 · v`, so it coasts to
  a stop.
- A weak spring toward centering the focus line: `a += 0.5 · error`. It
  corrects drift slowly, never as a step. After a pause it pulls the
  next line (usually the next paragraph's first line) to the center, so
  a coast tends to end there.
- If the view is ahead of the speaker, brake: `a −= 1.5 · v`.
- Clamp |a| ≤ 300 pt/s² and v ≥ 0 (never scroll backward).

This becomes the default (Smooth Scroll on). Snap mode stays as the
alternative.

Verify offline: replay the recorded speech stream through the tracker
and a synthetic layout, then compare the old and new controllers on
acceleration, jerk, and whether they come to rest near the paragraph
start during the ad-lib pause.

## 3. Lighter function words (setting, default on)
Rule: in speech, stress falls on content words (nouns, main verbs,
adjectives, adverbs); function words are unstressed. Set function words
in a lighter weight, so the shape of the line follows how it's spoken.

- Light: determiners/articles, prepositions, conjunctions, pronouns,
  particles (NaturalLanguage `.lexicalClass`), plus auxiliary and modal
  verbs (be/have/do forms, will, would, can, could, shall, should, may,
  might, must).
- Always regular: negations (not, no, never, n't contractions), numbers,
  and interjections. Negation carries meaning, so it keeps full weight.
- Weights: content words medium, function words light, both 32 pt.
- Setting name: "Lighter Small Words", with a footer giving examples.
