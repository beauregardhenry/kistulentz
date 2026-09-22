# Kistulentz 0.23.10 — Craft Examples, a Writing Activity Heatmap, and Two New De-stink Checks

Version 0.23.10 adds two new ways to see your own progress as a writer, two new De-stink checks,
and a reliability fix for Ollama.

## Added

- **Show a Strong Example.** On a flagged craft-judgment issue -- an adverb, passive voice, a
  stock phrase, and similar -- ask Kistulentz to find a short excerpt from your own Reference
  Library that handles the same craft element well, with a one-line note on why it works. It's
  grounded by having the AI select an excerpt by id from ones Kistulentz already holds verbatim,
  rather than generating or reproducing quote text itself, so a hallucinated or misattributed
  quote is structurally impossible -- the excerpt shown is always byte-identical to what's in your
  library.
- **A calendar heatmap, streak, and daily word goal**, in Your Writing Growth. A GitHub-style grid
  shows which days you wrote, a counter tracks consecutive days, and today's word count is shown
  against a goal you set in Settings. Whether a day shows up on the heatmap at all (did you write)
  and what color it gets (how clean the writing was, ranked against your own history) are
  deliberately kept as two separate signals, so nothing here rewards raw word volume over writing
  quality.
- **Two new De-stink checks: anaphora and epistrophe.** De-stink Review now flags 3 or more
  consecutive sentences that all open the same way (anaphora) or all end the same way
  (epistrophe) -- a rhetorical device when it's deliberate, a tic when it isn't.

## Fixed

- **Ollama requests no longer inherit `URLSession`'s 60-second default timeout.** Local CPU
  inference on a larger model can legitimately take several minutes for a longer request; one that
  ran past 60 seconds was previously misreported as "Kistulentz could not reach Ollama on this
  Mac," even when Ollama was reached and actively computing the whole time. Ollama requests now
  get a 300-second timeout, and a genuine timeout is now reported distinctly from an unreachable
  Ollama, so the message points at the right fix.
- **A discourse-analysis bug that silently dropped a paragraph's first sentence.** When a
  paragraph immediately followed a heading (or another non-punctuated line), its first sentence
  was dropped from every discourse-tier De-stink rule, not only the two new ones above. Found
  while building anaphora and epistrophe detection; fixed for all affected rules.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.
