# MT-504 to MT-601 validation bug ledger

Updated: 29 July 2026

This ledger records issues found during Windows Computer Use and rendered-PDF
validation. While the active model is Terra Light, these items are documentation
only. They must be diagnosed and fixed under Sol Medium before the combined user
test unless explicitly marked non-blocking.

## VT-001 - Compact export leaves an under-filled final page

- **State:** Candidate fix implemented; automated pagination regression passes.
  Recheck real rendered output in the next Computer Use round.
- **Severity:** Medium usability issue.
- **Fixture:** Local `Michael Jackson - Rock With You.pdf`.
- **Output:** Local validation file
  `C:\Users\Gerri\OneDrive\Documents\Music Tabbler\output\pdf\rock-with-you-beadg-validation.pdf`.
- **Observed:** The transformed chart exports as three A4 pages. Page 3 contains
  only the final four tab systems and leaves most of the page blank. The same
  under-filling is visible in Performance preview for existing visual charts,
  including a page containing only the tail of Thank You for the Venom.
- **Expected:** Pack complete systems onto the preceding page whenever the
  selected density profile's readability floor permits. Start a new page for a
  new song, not merely for a new source PDF page or source-strip group.
- **Safety constraint:** Do not solve this by shrinking rows below the selected
  density floor or by clipping notes, lyrics, techniques, or measure labels.
- **Likely inspection points:** A4 page planning, transform-output strip
  grouping, source-page boundaries, and per-strip minimum-height accounting.
- **Acceptance:** The same fixture uses the fewest pages permitted by the
  selected density floor, page order is unchanged, and all existing pagination
  tests still pass.

## VT-002 - Measure labels are partially clipped at transformed row boundaries

- **State:** Candidate fix implemented by adding a bounded vertical guard around
  transformed systems. Recheck real rendered output.
- **Severity:** Medium visual correctness issue.
- **Fixture/output:** Same Rock With You validation PDF as VT-001.
- **Observed:** Several measure numbers at the upper or lower edge of exported
  systems are visibly sliced. Notes, string lines, rests, ties, and bar lines
  remain readable.
- **Expected:** Measure labels remain complete when they belong to a selected
  tab system. Numbers classified as measure labels must remain excluded from
  fret replacement while still contributing to safe crop bounds.
- **Likely inspection points:** System crop rectangles, vertical guard padding,
  transform-output crop generation, and export whitespace trimming.
- **Acceptance:** Every measure label in a representative source/render pair is
  intact, no fret token is changed because it resembles a measure number, and
  row density does not regress materially.

## VT-003 - Common Unicode punctuation renders as a missing PDF-header glyph

- **State:** Common punctuation fallback implemented and tested. General
  Japanese/Unicode font support remains separate technical debt.
- **Severity:** Low for this fixture, higher for non-Latin metadata.
- **Fixture/output:** Rock With You validation PDF.
- **Observed:** The artist text
  `Track: Bass Guitar — Electric Bass (finger)` renders the em dash as a square.
  Poppler also reports missing `Symbol` and `ArialUnicode` display fonts while
  rendering the generated PDF.
- **Expected:** Common metadata punctuation renders legibly. Japanese/general
  Unicode remains subject to the separate font and licensing decision already
  recorded in `docs/TECHNICAL_DEBT.md`.
- **Medium decision:** Either safely normalize a small documented set of common
  punctuation for the built-in font, or complete the license-compatible bundled
  Unicode-font work. Do not download or embed an unreviewed font.
- **Acceptance:** The em dash case renders without a replacement box, existing
  Latin headers are unchanged, and font licensing is documented for any bundled
  asset.

## VT-004 - Ctrl+Z deskew undo was not confirmed from the tested focus

- **State:** Candidate focus fix implemented after deskew dialog closure.
  Physical-keyboard confirmation remains required.
- **Severity:** Low because toolbar Undo worked.
- **Observed:** After applying a `+1.0 degree` deskew, injected Ctrl+Z did not
  visibly undo from the current Computer Use focus. The explicit toolbar Undo
  restored the exact pre-deskew chart, and automated undo coverage passes.
- **Expected:** Ctrl+Z invokes the same one-step undo while the normal chart
  editor has focus.
- **Likely inspection points:** Focus ownership after closing the deskew dialog,
  shortcut scope, and Computer Use key injection.
- **Acceptance:** Reproduce with a physical keyboard in the normal editor. If it
  fails, fix shortcut focus handling; if it passes, record this as an automation
  limitation and close the item without code changes.

## VT-005 - Setlist placeholder begins on the preceding song's page

- **State:** Fixed in shared setlist layout with automated PDF/deck coverage;
  recheck Preview and Gig mode visually.
- **Severity:** High workflow correctness issue.
- **Fixture:** Existing four-item `RITN` setlist containing Thank You for the
  Venom, 9mm, the `Youtopia` placeholder, and a duplicate Thank You for the
  Venom entry.
- **Observed:** Jumping to the `Youtopia` placeholder opens preview page 5 of 8.
  The bottom of 9mm remains above the light-red placeholder banner on that same
  page.
- **Expected:** Every song occurrence and every named setlist placeholder starts
  on a clean new page in PDF export, Performance preview, and Gig mode.
- **Likely inspection points:** Performance-deck item-boundary page breaks,
  placeholder composition, and setlist PDF planner reuse.
- **Acceptance:** The same setlist gives each occurrence and placeholder its own
  first page, duplicates remain in order, and no blank page is inserted between
  items.

## VT-006 - Performance sidebar highlights the wrong item on a placeholder page

- **State:** Candidate-fixed by giving placeholders their own page ownership;
  recheck direct jumps, duplicates, and previous/next navigation.
- **Severity:** Medium navigation issue.
- **Fixture:** Same `RITN` setlist as VT-005.
- **Observed:** After jumping to the `Youtopia` placeholder, reopening the
  sidebar still highlights item 2 (`9mm`) in blue instead of item 3.
- **Expected:** The sidebar selection follows the current setlist entry,
  including placeholders and duplicate song occurrences.
- **Likely inspection points:** Page-to-entry identity mapping and placeholder
  page ownership in the shared performance deck.
- **Acceptance:** Direct jumps and previous/next navigation select the correct
  entry for every page of songs, duplicates, and placeholders.

## VT-007 - Preview and Gig mode use a PDF-specific density-dialog title

- **State:** Fixed with separate PDF, Performance preview, and Gig display
  dialog titles; widget regression passes.
- **Severity:** Low.
- **Observed:** Opening Performance preview or Gig mode displays a chooser titled
  `Setlist PDF density`.
- **Expected:** Use context-neutral wording such as `Display density`, or a
  context-specific Preview/Gig title. PDF export may retain PDF wording.
- **Acceptance:** All three entry points describe the operation the user
  selected while continuing to share the same density profiles.

## VT-008 - Windows Gig mode lacks the documented sidebar and annotation tools

- **State:** The current source exposes the complete Gig toolbar and sidebar.
  The prior Computer Use executable was stale; rebuild through `dev.bat` and
  recheck the current development build.
- **Severity:** High feature-parity issue.
- **Observed:** Gig mode shows only Exit and previous/next controls. The setlist
  sidebar, pen/highlighter, eraser, undo, hide/show, and clear controls available
  in Performance preview are absent.
- **Expected:** Gig mode exposes the editable setlist sidebar plus the persistent
  performance-annotation and secondary-highlighter workflow described in the
  product status and user-test checklist. Controls may auto-hide, but must be
  discoverable and usable.
- **Safety constraint:** Clearing performance notes/highlights must not alter
  chart-editor backing-vocal highlights.
- **Acceptance:** On Windows, the sidebar can jump/reorder/edit placeholders,
  annotations persist and erase promptly, the secondary highlighter is
  independently clearable, and the minimal stage surface remains available.
  Android lifecycle and swipe behavior still require physical-device testing.

## VT-009 - New / Import presents stale semantic-recognition copy

- **State:** Fixed. New / Import now explains the saved visual-source workflow
  and provides a button that opens it; widget regression passes.
- **Severity:** Medium discoverability issue.
- **Observed:** The Semantic recognition card says `OCR and note conversion will
  build on saved source assets later` and provides no action, although semantic
  recognition and review are described as implemented elsewhere in the app.
- **Expected:** Either provide the intended recognition entry point from New /
  Import or accurately direct the user to the required saved-chart workflow.
- **Acceptance:** A non-programmer can discover how to start recognition from
  this screen without documentation, and legally gated source search remains
  disabled/separate.

## VT-010 - Recognized semantic fret proposals render concatenated and unaligned

- **State:** Medium candidate fix implemented on 29 July 2026; repeat the
  saved-chart and fresh-recognition checks under Terra before closing. Fresh
  proposals now retain source-X spacing and conservatively exclude the
  reproduced sequential `31`--`35` measure-label run. Older saved proposed
  notes are normalized in memory when listed/opened: source geometry restores
  their horizontal positions and the same narrow false-positive run is
  removed. Verified user notes are never changed.
- **Automated evidence:** Focused recognition/review tests pass 14/14,
  including ordinary consecutive frets `12`--`14`, legacy proposal repair,
  and verified-note preservation. The full suite passes 199/199, `flutter
  analyze` reports no issues, and `git diff --check` passes.
- **Severity:** Critical for semantic transposition and re-tabbing.
- **Observed:** Tab-only view displays groups such as `11121314`, `15161718`,
  and `19202122` as concatenated text near measure starts rather than distinct
  notes aligned to their strings and beat positions. Other digits appear above
  the string grid rather than on a string.
- **Expected:** Each proposal renders as an individually selectable fret or dead
  note on its proposed string and beat. Ambiguous recognition remains visibly
  unverified and must not be treated as a playable chart.
- **Safety constraint:** Do not enable full-chart transpose/re-tab for an
  unreviewed chart whose event geometry is not trustworthy.
- **Likely inspection points:** OCR token-to-event beat mapping, proposal
  construction, semantic layout spacing, and fret-background clearing.
- **Acceptance:** A short real 9mm sample and synthetic fixture render distinct
  proposals at the correct string/beat positions; correction, verification,
  save/reopen, transpose, and PDF comparison all pass. Repeat the saved real
  `(Bass)` chart check that exposed the `3132333435` cluster before closing this
  issue.

## VT-011 - Recognition review is not visibly reachable as side-by-side review

- **State:** UI path revalidated by Computer Use on 29 July 2026. Selecting a
  proposal from the saved `(Bass)` 59-measure chart exposed its source-row
  preview plus explicit Accept selected and Reject selected controls. Persisted
  acceptance/rejection remains deliberately untested in this read-only pass.
- **Severity:** High if no alternate per-event entry point exists.
- **Observed:** The semantic screen reports `Recognition review: 91 proposal(s)`
  with `Verify all`, but clicking the review banner does nothing. The large
  right-side panel visible beside the chart is blank in the tested state.
- **Expected:** The documented side-by-side source/correction workflow is
  discoverable, shows the source region, and supports accept/edit/reject for one
  proposal at a time. Bulk verification must not be the only obvious path.
- **Acceptance:** From an unverified semantic chart, a user can open a source
  preview, select a proposal, correct or reject it, and see status update without
  verifying unrelated proposals.

## VT-012 - Upward mouse-wheel scrolling can jiggle or stall after rows load

- **State:** Fixed in source on 29 July 2026. The visual editor explicitly owns
  desktop wheel deltas and applies them monotonically to its stable-height
  primary scroll controller. Automated and Computer Use regressions pass;
  physical-wheel confirmation remains a user acceptance check.
- **Severity:** High usability issue when reproduced.
- **Fixture:** Existing 43-row Thank You for the Venom visual chart.
- **User-observed:** Scrolling down progressively loads the later rows. Scrolling
  upward afterwards can become stuck at a boundary and jiggle up and down, while
  dragging the scrollbar thumb continues to work.
- **Computer Use result:** After the fix, injected wheel gestures reached Row
  43 and returned directly to Rows 1â€“3 without stalling or oscillating. The
  chart highlighter also reached rows
  42–43 and returned to rows 1–2. Far highlighter rows briefly showed a blank
  viewport while loading, then rendered after about two seconds.
- **Expected:** Mouse-wheel scrolling moves monotonically in the requested
  direction regardless of image-cache or lazy-row state. Loading a row must not
  rewrite the scroll extent in a way that cancels or reverses the user's input.
- **Likely inspection points:** Lazy image decoding, row-height placeholders,
  scroll-position correction when images resolve, nested scrollables, and wheel
  event ownership.
- **Acceptance:** Reproduce with the user's physical wheel, then scroll from row
  1 to row 43 and back repeatedly without a stall, reversal, or large blank
  viewport. Scrollbar dragging and highlighter scrolling must remain correct.

## VT-013 - Importing an identical `.mtsong` silently skips the duplicate

- **State:** Fixed in source with stable duplicate identities. Bundle tests
  confirm repeated identical and divergent imports are retained independently;
  recheck the current development build.
- **Severity:** Medium data-workflow issue.
- **Fixture:** Local `Thank You for the Venom.mtsong`, imported while the same
  chart was already present.
- **Observed:** The file picker closed and Song Pool still contained only one
  Thank You for the Venom entry. No persistent conflict choice was offered.
- **Expected:** Importing a valid identical bundle creates a separate chart
  copy, or presents an explicit choice whose duplicate option is available. The
  user may delete the extra copy later.
- **Safety constraint:** A duplicate import must receive a new stable identity
  and must not overwrite the existing chart, its setlist references, or shared
  content-addressed assets.
- **Acceptance:** Import the same bundle twice and receive two independently
  deletable Song Pool entries with distinct identities. Existing setlist
  references continue to point to the original entry.

## VT-014 - Stage-readable Gig mode has a slow first-page render

- **State:** Fixed in source and revalidated by Computer Use on 29 July 2026.
  Gig mode now presents its title, progress state, and safe Exit immediately,
  while a validated three-entry LRU cache reuses unchanged performance decks
  across Preview, Gig, and setlist PDF generation.
- **Severity:** Medium stage-readiness/performance issue.
- **Fixture:** Existing four-item `RITN` setlist, Stage readable density.
- **Observed:** After choosing `Stage readable`, the surface remained black with
  a loading indicator for about 8 seconds before the first rendered page and
  controls appeared. Performance Preview also showed a short blank loading
  surface before rendering, but completed noticeably sooner.
- **Expected:** Gig mode should acknowledge loading promptly and render the
  first usable page fast enough for a practical stage transition. It must not
  show a misleading error or leave navigation unavailable while the deck is
  loading.
- **Likely inspection points:** Performance-deck image preparation, decode
  concurrency, first-page prioritisation, and any synchronous work on the UI
  isolate.
- **Acceptance:** First page and Exit/navigation controls appear within a
  defined, repeatable performance budget on the target Windows hardware;
  background page preparation must not block interaction.
- **Computer Use result:** The loading/Exit shell was visible at the first
  settled observation. The cold Stage-readable page was present at the next
  1.5-second check, and reopening the unchanged set reached page 1 in 246 ms
  from the density click.

## Windows Computer Use queue

### Completed in this pass

- [x] Song Pool and Gigs desktop layouts render without overflow.
- [x] Existing four-item setlist shows a duplicate song and light-red
  `Not playing` placeholder in the correct editor order.
- [x] Original, Balanced, and Stage-readable Performance preview all load
  without the former minimum-row-height error.
- [x] Preview next/previous and explicit Exit controls work.
- [x] Sidebar direct jumps work for normal and duplicate song entries.
- [x] Original-density Windows Gig mode opens and explicit Exit works.
- [x] Local URL intake clearly states that the app does not fetch the link.
- [x] Library transfer/recovery dialog exposes export, merge, replace, and
  restore actions without performing a destructive operation.
- [x] Semantic tab/notation toggles respond.
- [x] Motion Sickness and Rock With You visual transforms, deskew/undo, save,
  and Rock With You PDF export were exercised in the earlier focused pass.
- [x] The 43-row visual editor and chart highlighter reached the final rows and
  returned to the first rows without a Computer Use crash; physical-wheel
  behavior remains queued under VT-012.
- [x] Identical `.mtsong` import was exercised in the isolated library and
  reproduced the silent-skip behavior recorded as VT-013.
- [x] VT-010 saved `(Bass)` semantic chart recheck: the prior `3132333435`
  cluster is absent, 75 proposals remain individually selectable, and source
  comparison opens for a selected proposal. Fresh recognition remains deferred
  to a disposable visual copy.
- [x] Balanced Performance Preview: all four `RITN` entries retain order; 9mm
  starts on page 3 and the red `Youtopia` placeholder starts alone on page 6.
- [x] Stage-readable Gig mode exposes its sidebar, page navigation, Exit,
  annotation/highlighter controls, and a direct jump to 9mm. Slow first paint
  is recorded as VT-014.
- [x] Current Thank You for the Venom visual editor reached Row 43 and returned
  to Row 1 using injected scroll gestures; the highlighter dialog opens with
  existing editable boxes intact. Physical-wheel reproduction remains VT-012.
- [x] New / Import accurately states the local-only provenance boundary and
  routes semantic recognition through `Start visual source`; no link was
  fetched or submitted during this pass.

### Continue with Computer Use after Medium fixes

- [ ] Recheck compact pagination and item page boundaries in PDF, Preview, and
  Gig mode using the `RITN` setlist.
- [ ] Recheck placeholder and duplicate selection in the performance sidebar.
- [ ] Exercise performance annotations, eraser latency, clear-all, secondary
  highlighter, persistence, and PDF inclusion after Gig mode exposes them.
- [x] Re-run the longest-chart wheel-scroll regression with injected Windows
  wheel input after the VT-012 fix.
- [ ] Confirm the same regression with the user's physical mouse wheel.
- [ ] Export Balanced and Stage-readable setlist PDFs and render every page.
- [ ] Recheck identical import after VT-013 is fixed, then exercise a deliberately
  divergent bundle and verify the conflict summary.
- [ ] Exercise non-destructive `.mtstate` export plus cancel/corrupt-import
  paths only against the disposable library.
- [ ] Exercise semantic note/rest edits, MusicXML, short recognition correction,
  transpose, re-tab, and ranked variants after VT-010/VT-011 are resolved.
- [ ] Repeat visual analysis and transforms with a screenshot-only fixture.

Use `docs/COMPUTER_USE_FULL_APP_ROUND.md` for the complete next pass. Terra
Light must record new failures here and must not patch them.

### Physical user or hardware gate

- [ ] Confirm Ctrl+Z deskew undo with a physical keyboard.
- [ ] Confirm stage readability at the user's normal tablet/music-stand
  distance.
- [ ] Android import/export, fullscreen, swipe, Back behavior, lifecycle
  cleanup, and keep-awake.
- [ ] S Pen pressure, palm rejection, inverted eraser, rotation, persistence,
  and annotation alignment.
- [ ] macOS build/workflow and iOS Simulator feasibility on the MacBook Air.
- [ ] External-browser URL copy/open behavior, because this pass intentionally
  did not contact remote sites.
- [ ] Whole-library replace/restore recovery drill only after the user chooses a
  disposable target copy.

## Non-bugs observed during the same pass

- Rock With You's positioned-PDF text was too sparse for safe fret analysis, so
  the app offered Raster/OCR and completed the workflow through that fallback.
  This is intended conservative behavior.
- Original-layout export is not offered for a pitch-changing visual transform
  containing standard notation, because the notation would be musically stale.
  Compact tab-only output is the intended safe result.
- The Rock With You preset correctly produced target strings `G D A E B`
  top-to-bottom, an unused high G, target capo 2, global pitch change -2, and
  unchanged fret numbers.
