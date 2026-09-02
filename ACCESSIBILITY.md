# Kistulentz accessibility verification

Complete this review on macOS Sequoia with the release-candidate app, not only a development build. Record defects before release rather than checking a box without testing it.

## Keyboard-only use

- Complete first-launch onboarding without a pointer
- Create, open, and import a document; cancel every chooser and modal with Escape
- Reach the project sidebar, readability list, editor, suggestions, and toolbar controls in a predictable order
- Open and close Research Library, Reference Library, Project Organization, Systemic Revision, Publish & Export, Settings, System Check, and Draft Recovery
- Accept, decline, and undo a concrete suggestion
- Review, reorder, retry, cancel, and finish a Project Import Assistant batch
- Save a recovered copy, cancel replacement, and discard a test recovery journal

## VoiceOver

- Confirm every icon-only button announces its action and the affected item
- Confirm selected and unselected reference choices announce their state
- Confirm progress controls announce completed and total work
- Confirm the readability score announces grade, target, and interpretation without relying on ring fill or color
- Confirm recovery panes are announced as saved text and recovered text
- Confirm focus returns to a sensible control after dismissing a sheet or alert
- Confirm headings, groups, lists, and destructive confirmations are announced in context

## Visual access

- Test increased system text size without clipped buttons or inaccessible actions
- Test Increase Contrast, Differentiate Without Color, Reduce Transparency, and Reduce Motion
- Verify selection, warning, error, success, and disabled states remain understandable without color alone
- Verify light and dark appearances at the minimum supported window size
- Verify keyboard focus indicators remain visible throughout the editor and every modal flow

## Content and publication

- Confirm generated EPUB navigation and structural metadata with the release preflight
- Manually review meaningful image alternative text; do not treat filename-derived text as sufficient
- Confirm exported diagnostics contain no manuscript prose, excerpts, paths, filenames, API keys, or account data
