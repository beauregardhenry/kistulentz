# Kistulentz 0.23.10 friend preview guide

Thank you for testing Kistulentz. The most useful feedback is not whether every feature works
once, but whether the app feels safe and predictable while you work on real writing.

You do not need to complete every section. Choose the workflows closest to the way you write.

## Before you begin

- Use macOS Sequoia 15 or later on an Apple-silicon or Intel Mac.
- Download Kistulentz only from the
  [official 0.23.10 release](https://github.com/beauregardhenry/kistulentz/releases/tag/v0.23.10).
- Test with copies of important documents and project folders. Keep your normal backup.
- You do not need an OpenAI or Anthropic key. Local analysis and Local Polish work without one.
- If Kistulentz hangs, overwrites the wrong text, loses work, or leaves you trapped in a screen,
  stop and report it. Those are release-blocking defects.

## Install and first launch

1. Open the downloaded DMG and drag Kistulentz into Applications.
2. Try to open Kistulentz from Applications.
3. If macOS blocks it, dismiss the warning, open **System Settings → Privacy & Security**, and
   choose **Open Anyway** beside Kistulentz. Do not disable Gatekeeper or run Terminal commands.
4. Complete the Welcome screen. Confirm every choice either advances or cancels normally.
5. If offered the optional English structural-analysis pack, either install it or decline it.
   Both choices should leave the app usable.

Please report any missing button, clipped text, screen you cannot leave, or window that does not
fit your display.

## Everyday document editing

- Open a Markdown or plain-text document.
- Type normally, then paste a substantial passage. Typing and scrolling should remain responsive.
- Change the target reading grade and confirm the score and guidance update.
- Accept one suggestion and decline another. Only the accepted passage should change.
- Try **Apply All** after reviewing its confirmation. It should apply only concrete suggestions.
- Press Command-Z. It should undo the writing change, not erase the analysis or scan.
- Try Redo, save, close the document, reopen it, and confirm the saved text is intact.
- Confirm a declined suggestion stays hidden after reopening, then change its passage and see
  whether the relevant guidance can return.
- Resize the window and use the app in light and dark appearance. Important controls should remain
  visible and reachable.

## Import existing work

Open **Project Import Assistant…** from the Projects folder menu.

- Add several documents or a folder. Markdown, TXT, DOCX, RTF, RTFD, HTML, and ODT are supported.
- Reorder the documents and assign them as Parts, Chapters, Scenes, or Sections.
- Start a conversion, cancel it, and confirm no output was written.
- Convert again and review the Markdown preview and every formatting warning.
- Try a deliberately damaged disposable file and confirm Kistulentz reports the failure without
  creating a partial Markdown document or preventing the remaining imports from completing.
- Try an unusually compressed or malformed DOCX, ODT, or EPUB only if you have a disposable test
  file. Kistulentz should reject it with a useful safety message instead of hanging or expanding it.
- If tracked changes are present, accept or reject each one before finishing.
- Try a combined Markdown file and, separately, a new project with individual documents.
- Confirm the original documents were not modified.
- If one file fails, the remaining files should continue and the failed file should remain visible
  with a useful explanation and a Retry option.

Look closely at headings, emphasis, lists, links, images, tables, footnotes, comments, and tracked
changes. Report anything missing or misleading, even when Kistulentz displays a warning.

## Long-form projects and Project Polish

- Open a copied fiction or nonfiction project folder.
- Move among several documents, search the manuscript, and confirm the document scores and total
  word count remain responsive.
- Open Project Organization and verify Parts, Chapters, Scenes, or Sections appear in the expected
  order. Cancel any reorganization you do not intend to keep.
- Run **Polish Project…** and review each stage. Exclude a stage, include it again, and edit one
  proposed passage.
- Cancel from the final confirmation. No manuscript file should change.
- Run it again, apply reviewed passages, and press Command-Z once. The complete Project Polish
  operation should be undone in one step.
- If you change a passage after Kistulentz analyzes it, the old proposal should become stale rather
  than overwrite the newer writing.
- Check that your manual notes in `Kistulentz Bible.md`, `Kistulentz Manuscript Report.md`, and
  `Kistulentz Style.md` remain intact after automatic updates.

## Reference and Research Libraries

- Open **Reference Library…** and **Research Library…**.
- Try **Choose Folder**, create a new folder, and cancel the chooser on a separate attempt.
- Close each library screen using its normal control and Escape. You should never become trapped.
- Import an EPUB into the Reference Library and review its local style profile. Correct any
  incorrect title, author, or genre inside Kistulentz.
- Select more than one reference and confirm combined guidance identifies its sources.
- Add a test attachment to the Research Library as a managed copy or link. Confirm Kistulentz
  clearly identifies which choice you made.
- Cancel a large attachment index or EPUB import, close the library, reopen it, and confirm the
  completed records remain usable while the cancelled item is clearly incomplete.
- Start a second import or analysis before the first finishes. The newer request should win; an
  older result must never appear later and replace it.

Do not test with DRM-protected or image-only EPUBs unless you specifically want to check the error
message; those books do not expose readable text for analysis.

## Optional AI and Ollama checks

Only complete this section if you already use one of these providers.

- Open Kistulentz Settings, save an OpenAI or Anthropic key, choose a model, and select
  **Test Connection**. The connection test should not send manuscript text.
- If you use Ollama, open Ollama first. Kistulentz should detect it and list installed models. Any
  model download must ask permission, show progress, and offer Cancel.
- Start a Rewrite or Deepen w/ AI. Before anything is sent, confirm the request preview names
  the provider and model and shows the exact writing and optional context. (Polish always runs
  locally, even with a provider configured, so it never shows this preview.)
- Remove or redact optional material, then cancel. Nothing should be sent and no writing should
  change.
- On another test, approve the request and review the result before applying it. The proposed change
  should not violate the rule it claims to fix, and Command-Z should undo an applied passage.

## Optional recovery check

Use only a disposable copy of a document.

1. Save the document, make another edit, and force Kistulentz to quit before the edit is saved.
2. Reopen Kistulentz and review the recovered and saved versions.
3. Save a recovered copy instead of replacing the original.
4. Repeat the test after changing the original file in another app. Kistulentz should refuse to
   replace the newer file without an explicit confirmation.
5. Confirm Discard and Cancel do exactly what they say and leave you able to close the screen.

## Keyboard and VoiceOver

- Use Tab, Shift-Tab, arrow keys, Return, Space, and Escape through a normal editing task.
- Confirm focus remains visible and returns somewhere sensible after closing a sheet or alert.
- If you use VoiceOver, confirm icon-only buttons announce their action, selected references
  announce their state, and the readability meter announces the grade and target without relying
  on color or the ring.
- Increase text size or enable Increase Contrast, Differentiate Without Color, Reduce Transparency,
  or Reduce Motion. Report clipped or ambiguous controls.

## Report a problem

For every problem, please include:

- What you were trying to do.
- The shortest steps that reproduce it.
- What you expected and what happened instead.
- Whether it happens every time.
- The document format and approximate document or project size.
- A screenshot when it does not reveal private writing.

Then open the **Kistulentz** menu and choose **Kistulentz System Check…**. After it finishes, choose
**Export Diagnostic Report…** and attach the Markdown report. The report includes the Kistulentz
version and Mac environment, but excludes manuscript text, excerpts, filenames, paths, API keys,
and account data.

Send the report to Beau or
[open a GitHub issue](https://github.com/beauregardhenry/kistulentz/issues/new). Do not attach a
manuscript or private source material unless you deliberately choose to share it.

Please label these problems as urgent:

- Lost writing or an unexpected overwrite.
- A save, import, recovery, or Undo action affecting the wrong file or passage.
- A reproducible hang, crash, or operation that cannot be cancelled.
- A screen with no usable way to close or continue.
- Writing sent to a cloud provider without a clear preview and approval.

Confusing language, unclear icons, poor suggestions, and awkward workflows are also valuable
feedback. Please report them even when the app technically completes the task.
