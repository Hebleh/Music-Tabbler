# Terra Light full-app Computer Use round

This is the post-Medium Windows validation pass for the complete public,
pre-legal Music Tabbler application. Terra Light is the tester and recorder:
do not edit source code, patch defects, migrate the user's main library, build
an installer, package a release, or enter `LG-001` through `LG-006`.

## Start safely

1. Read, in order:
   - `docs/HANDOVER.md`
   - `AGENTS.md`
   - `docs/CURRENT_STATUS.md`
   - `docs/SPEC.md`
   - `ARCHITECTURE.md`
   - `docs/BUGS_MT504_VALIDATION.md`
   - `docs/COMBINED_USER_TEST_MT203.md`
   - `docs/COMBINED_USER_TEST_SPRINT6.md`
   - this document
2. Use the primary checkout at `C:\vibes\Music Tabbler`.
3. Launch the current source with `dev.bat`; do not use an older packaged or
   Profile executable.
4. Use the isolated/disposable Computer Use library where destructive transfer
   tests are involved. Never replace the user's only library.
5. Observe the screen immediately before every Computer Use action.
6. Add every failure to `docs/BUGS_MT504_VALIDATION.md` with a new stable
   `VT-###` ID, reproduction steps, expected/actual result, severity, fixture,
   and screenshot path. Do not patch it.

## Priority rerun after the 29 July Medium patch

Complete these checks before resuming the broader matrix:

1. Fully close the prior development process and relaunch current source with
   `dev.bat`.
2. Reopen the existing saved `(Bass)` 59-measure semantic chart that previously
   displayed `3132333435` near measures 17--20.
3. Confirm the sequential measure-label cluster is absent and remaining
   proposals are individually positioned. Select several remaining proposals
   and confirm the source-row comparison still appears.
4. Create a fresh recognition proposal from a short disposable visual copy
   containing visible measure labels and frets. Do not overwrite the user's
   only useful visual or semantic chart.
5. Confirm measure labels are not admitted as frets, ordinary consecutive frets
   remain visible, and accept/reject/edit one proposal still affects only that
   proposal.
6. Record the result under VT-010. If the saved chart or fresh proposal is still
   wrong, stop semantic transpose/re-tab checks and continue the non-semantic
   sections of this document.

## 1. Shell, navigation, and persistence

- [ ] Song Pool, Gigs, and New / Import render at wide and narrow Windows
  sizes without overflow.
- [ ] App theme, Gig theme, notation/tab visibility, and title visibility
  survive a full close and `dev.bat` relaunch.
- [ ] Existing visual charts, semantic charts, setlists, placeholders,
  provenance, highlights, and annotations remain present.
- [ ] Song Pool title fallback and Last edited metadata remain correct.

## 2. Manual visual screenshot/PDF workflow

- [ ] Import PNG/JPEG by picker, Ctrl+V, drag/drop, and a folder of ordered
  screenshots.
- [ ] Import a multi-page PDF, auto-detect rows, adjust master sides, split,
  resize, duplicate, delete with Backspace, crop, deskew, Ctrl+Z, and autosave.
- [ ] Scroll a 40+ row chart to the last row and back to Row 1 at least three
  times using a physical mouse wheel. Record any stall, reversal, jiggle,
  blank viewport, or delayed row height.
- [ ] Open the chart highlighter at the first and final rows. Add, resize,
  move, and delete freeform highlights; confirm text selection and
  corresponding-tab extension remain usable.
- [ ] Confirm editor highlights appear in the chart and song PDF, and that
  clearing performance notes never clears these editor highlights.
- [ ] Check title/artist detection on Latin material; record Japanese OCR only
  as existing technical debt unless behavior regresses.

## 3. Visual transform and deskew

- [ ] `9mm.pdf`: analyze/review and apply all-string `+1`; check ordinary
  frets, `X`, measure numbers, undo, edit/remove, save/reopen, and compact PDF.
- [ ] Motion Sickness: DADG to BEADG, pitch change 0, capo 0, unused E,
  low-D to B at `+3`.
- [ ] Rock With You: D#G#C#F# to BEADG, pitch change `-2`, target capo 2,
  unused high G, unchanged fret numbers.
- [ ] Repeat one transform from a screenshot-only source.
- [ ] Inspect every exported page for complete measure labels, intact
  techniques/lyrics, five correctly spaced strings, correct tuning labels,
  minimum whitespace, and no stale standard notation.
- [ ] Confirm common punctuation such as an em dash renders as a readable
  fallback rather than a missing-glyph square.

## 4. Setlists, PDF, Preview, and Gig mode

- [ ] Create/edit/delete a setlist with three songs, a duplicate occurrence,
  and a light-red `Not playing` placeholder.
- [ ] Reorder from the editor and Gig sidebar; restart and confirm persistence.
- [ ] Delete a referenced chart using the explicit policy and verify it does
  not return after deleting the setlist or restarting.
- [ ] Confirm chooser titles are `Setlist PDF density`,
  `Performance preview density`, and `Gig display density`.
- [ ] Export Original, Balanced, and Stage-readable PDFs. Render every page.
- [ ] Each song occurrence and placeholder starts on a fresh page, with no
  blank separator page. Within each song, rows use the fewest pages allowed by
  the density floor.
- [ ] Preview and Gig order exactly match the setlist PDF. Sidebar selection
  follows songs, duplicates, and placeholders on every page.
- [ ] Preview and Gig previous/next and Back/Exit work on normal, loading, and
  error surfaces.
- [ ] In Gig mode, open the sidebar; jump, reorder, add/edit/remove a
  placeholder; then test pen, secondary highlighter, eraser latency, undo,
  hide/show, PDF inclusion, and Clear all performance notes.
- [ ] Close/reopen Gig mode and confirm performance marks persist. Confirm
  Clear all does not alter chart-editor backing-vocal highlights.
- [ ] Resize the window narrowly and confirm the Gig toolbar scrolls without
  yellow/black overflow stripes.

## 5. Local sources and portable data

- [ ] Paste a Songsterr URL. Confirm it creates provenance only and does not
  fetch, scrape, or populate a chart.
- [ ] Edit/copy/open source details, save/reopen, and confirm provenance never
  appears in PDFs.
- [ ] Export one `.mtsong`, then import the exact file twice. Confirm each
  import creates a distinct, independently deletable Song Pool entry and does
  not redirect existing setlist references.
- [ ] Import a deliberately divergent bundle and confirm both variants remain.
- [ ] Export a non-empty `.mtstate`.
- [ ] Against only a disposable library: cancel import, attempt a corrupt
  import, merge a valid state, replace a valid state, and restore the automatic
  backup. Verify cancellation/corruption leave live state unchanged.

## 6. Semantic recognition, review, editing, and transforms

- [ ] From New / Import, use `Start visual source`, import/crop a short source,
  then use the `Recognize semantic proposal` toolbar action.
- [ ] Confirm proposed frets are separate, centered on their strings, and
  horizontally follow the source rather than appearing as concatenated text.
- [ ] Select a proposal. The source-comparison pane must show its source row.
  Accept one, reject one, edit one, save/reopen, and verify unrelated proposals
  remain proposed.
- [ ] `Verify all` remains explicit; Gig-ready stays disabled until required
  proposals and validation errors are resolved.
- [ ] Add/edit/delete a note and rest; edit beat/duration, tuning, capo,
  section, repeat/ending, technique, lyric alignment, and backing-vocal state;
  undo and save/reopen.
- [ ] Toggle tab and notation independently. Compare screen and semantic PDF.
- [ ] Export/import MusicXML and record all explicit loss diagnostics.
- [ ] On a short fully reviewed sample, transpose `+1`; verify exact sounding
  pitch delta and unchanged rhythm/lyrics.
- [ ] Re-tab a four-string sample to BEADG; compare ranked fingerings and save
  two independently editable variants.
- [ ] Route selected strings/capo using the Motion Sickness and Rock With You
  configurations; verify all final sounding MIDI pitches.

## 7. Final regression and report

- [ ] Reopen one screenshot chart, one positioned-PDF chart, one transformed
  chart, one semantic chart, and one setlist after a full app restart.
- [ ] Re-export their PDFs and inspect every rendered page.
- [ ] Confirm the manual screenshot/PDF workflow remains usable even if
  semantic recognition is inaccurate or cancelled.
- [ ] Run no Android, macOS, iOS, online-provider, scraping, installer, or
  release-package work in this Windows pass.

Report:

- completed checklist items;
- every new or still-reproduced `VT-###`;
- screenshots/rendered PDF paths;
- flows blocked by missing physical input or external hardware;
- a clear statement that no source patches were made.
