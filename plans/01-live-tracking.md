# 01 — Live word tracking, centered reading, smooth scroll, settings

## Goals (from feedback)
1. Highlight words as they're said.
2. Gray out sentences already said; keep the current phrase centered.
3. Assume forward motion: no wild rewinds on mismatches. Hold and catch up.
4. A skipped sentence is not grayed out.
5. Forgive small mistakes: a sentence ≥ 70% matched counts as said.
6. Settings sheet (from the ⋯ menu) with the voice recognition picker.
7. "Smooth Scroll" toggle: scroll speed follows speaking speed, so lines
   arrive on screen as you reach them.
8. Typography: tighter wrapped lines, more space between sentences, an
   extra line between paragraphs.

## Model — `ScriptDocument`
- Paragraphs = non-empty lines of the source (Google Docs paragraphs end
  in `\n`; blank lines collapse).
- Sentences: split within a paragraph after `. ! ? …` (plus trailing
  quotes/brackets) followed by whitespace.
- Words: regex runs of letters/digits (with inner apostrophes), each with
  its character range in the sentence and a normalized form (lowercase,
  apostrophes dropped). Punctuation and dashes aren't words; they take
  the color of the word before them. So "youth—something" is two words,
  which matches how speech engines transcribe it.

## Tracking — `ScriptTracker` (pure Swift, testable outside the app)
State: `heard[word]`, `cursor` (the last word confirmed spoken),
recent (time, cursor) samples for speed, and a pending jump awaiting
confirmation.

On each transcript update (volatile or final):
1. Normalize it and take the last ≤ 12 words.
2. Local alignment (Smith–Waterman) against a script window
   [cursor − 40, cursor + 160]. Fuzzy word match: exact, small homophone
   table (to/too/two…), or edit-similarity ≥ 0.7 for words of 4+
   letters, plus a prefix match for the last (partial) transcript word.
3. Only alignments that end at the transcript's last or second-to-last
   word count. The script end position is the candidate cursor.
4. Forward bias:
   - 0…15 words ahead: needs 2 matched words.
   - ≤ 40 ahead: needs 3.
   - Further ahead: needs 4, plus the same target (±3) on two consecutive
     updates.
   - Backwards: needs 5 matched words plus two-update confirmation;
     otherwise hold.
   - Ties go to the nearest forward position.
5. On acceptance, mark every script word from the first to the last
   matched word as heard, which forgives misheard words in between, and
   advance the cursor.

Derived:
- A sentence is said when ≥ 70% of its words are heard.
- The current sentence is the one holding the next word (cursor + 1).
- A sentence before the current one with < 70% heard was skipped and
  renders as normal text.
- Speed: words/sec over the last ~6 s of cursor advances, as an EMA.
  It decays toward 0 after 2.5 s without progress.

## Rendering — `TelepromptView`
- Black background, white text, 32pt.
- Colors: said sentences gray; words heard in the current sentence in a
  yellow highlight; upcoming text white.
- Each sentence is one `Text`, built from an `AttributedString`.
- Spacing: `.lineHeight(.tight)` for wrapped lines (iOS 26), 16pt between
  sentences, one extra line between paragraphs.
- Half-viewport padding at the top and bottom, so the first and last
  lines can be centered.
- Sentence frames come from `onGeometryChange` in the content coordinate
  space. The focus line's y is estimated from the next word's character
  offset within its sentence, snapped to a line.
- Snap mode (default): when the focus line changes, animate
  `ScrollPosition` to center it.
- Smooth mode: run a display link with
  `v = wps × (points per word near the focus) + k × (centered target − y)`,
  clamped to ≥ 0. Wait (v = 0) when far ahead of the speaker.
- Manual drags pause auto-follow for 2 s.

## Settings
- ⋯ menu → "Settings…" opens a sheet: a Form with a Voice Recognition
  picker and a Smooth Scroll toggle, each with a footer.
- The picker moves out of the menu. `@AppStorage("smoothScroll")`
  defaults to off.

## Verification
- Tracker harness: run real SpeechAnalyzer output from `say` audio of
  Twain (one sentence skipped, words swapped) through
  `ScriptDocument` + `ScriptTracker` with `swiftc`. Check the cursor never
  rewinds, the skipped sentence isn't marked said, and misread sentences
  still are.
- DEBUG `-UIDemoTranscript` feeds a synthetic reading into the view (with
  a substituted word and a skipped sentence) for simulator screenshots of
  highlighting, graying, and centering in both modes.
