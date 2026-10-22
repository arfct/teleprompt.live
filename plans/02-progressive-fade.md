# 02 — Progressive fade instead of highlight

Feedback on 01: fade said words to gray gradually rather than all at once
when a sentence ends, and drop the yellow highlight. Missed phrases should
fade only halfway, and only once their paragraph is done.

## Rule (per word, in `ScriptTextView`)
Let `c` = tracker cursor (last spoken word), `F` = 6 words (fade length),
`gray` = 0.35 opacity.

- Word ahead of the cursor (`w > c`): white. A confirmed re-read rewinds
  the cursor, so the text it covers un-fades.
- **Said word** (heard, or in a sentence that's ≥ 70% heard):
  opacity = `1 − (1 − gray) · min(1, (c − w + 1) / F)`.
  It dims over the next ~6 spoken words, so behind the speaker there's a
  short trail from white to gray.
- **Missed word** (not heard; its sentence wasn't said): white until the
  cursor passes the end of its paragraph. Then it fades over F words to
  half the said amount: `1 − (1 − gray) · 0.5 · min(1, (c − end) / F)`.

Distance in words, not time, means colors only change when the tracker
moves (a few times a second). No per-frame re-rendering, and the trail
pauses when the speaker pauses.

## Verify
In a simulator demo with a skipped sentence and a missed short sentence:
- a white-to-gray trail behind the reading position,
- no yellow,
- missed text stays white mid-paragraph, then goes half-gray once the
  paragraph is finished.
