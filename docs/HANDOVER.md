# Music Tabbler handover

Updated: 20 July 2026

This is the fastest restart document for a new Codex task. Read this file, then `AGENTS.md`, `docs/CURRENT_STATUS.md`, `docs/SPEC.md`, and `ARCHITECTURE.md`. Do not discard or reset the current working tree: the latest verified work is intentionally uncommitted.

## Immediate state

- Repository: `C:\vibes\Music Tabbler`
- Branch: `main`
- Latest commit: `fd1e6d7 feat: streamline visual chart intake and editing`
- Git remote: none
- License/repository visibility: undecided pending source terms and content-rights review
- Current tree: dirty, with the clipboard, row-detection, OCR/highlighter, scrolling, deletion, persistence, and PDF-density work described below
- Near-term product target: dependable, stage-readable charts for the user's 16 August 2026 gig

Before making changes, run:

```powershell
git status --short
git diff --check
flutter analyze
flutter test
```

Do not use `git reset --hard`, `git checkout --`, or otherwise remove the current changes. No commit was requested or created for the latest slice.

## Product intent and fixed decisions

Music Tabbler is a fully local Flutter application that turns mixed music sources into compact, stage-readable bass tabs/charts. The primary workflow is initially the user's own five-string bass workflow, normally tuned BEADG, including backing vocals.

- Windows is the current authoring target.
- Android is intended to reach full feature parity, with gig mode particularly designed for the user's Samsung tablet and S Pen.
- A4 PDF remains the reliable gig fallback and must match what the app displays.
- Song Pool stores processed songs; Gigs/Setlists orders references to those songs; New/Import accepts source material.
- The reliable baseline is nondestructive PDF/PNG/JPEG/screenshot import, rearrangement, highlighting, and export.
- Whole-chart semantic OCR/OMR is the long-term goal. Recognition must remain an editable proposal, never silently verified truth.
- Tablature and standard notation must have independent toggles. Title/artist display is optional and source provenance never appears in PDFs.
- Transposing pitch and re-tabbing the same pitches for another tuning/string count are separate operations.
- Android/Windows state transfer must be manual, local, staged, checksummed, transactional, and non-destructive on failure.
- Direct chosen URLs are the preferred future online intake. Search/scouring is secondary. No source adapter may bypass authentication, paid access, CAPTCHAs, rate limits, or technical restrictions.

## Current user workflow

1. Open **New / Import** and create a visual chart.
2. Import PNG/JPEG files, a PDF, a screenshot folder, or drag files/folders onto the editor.
3. On Windows, press `Ctrl+V` or use **Paste image**. It now accepts either bitmap pixels or one or more files copied in Explorer.
4. The first page proposes title/artist through local OCR. The fields remain editable and **Detect title / artist** can retry.
5. Use **Split into rows**. **Detect rows** proposes editable row boxes; even division and manual add/duplicate/delete remain available.
6. Move/resize crop and row boxes directly using edges/corners. Reorder, duplicate, or delete chart rows.
7. Apply Original, Grayscale, Invert, or High contrast per row, or change the whole chart at once.
8. Use the unified highlighter for detected lyric words or freeform regions. Optionally extend a lyric selection downward to the corresponding tab column.
9. Save the draft to Song Pool. Saved visual drafts can be deleted after confirmation without deleting shared content-addressed assets.
10. Export A4. Title/artist appears only on page one when enabled; provenance is omitted.

## Latest verified uncommitted slice

The working tree after `fd1e6d7` contains the following completed work:

- Explorer `CF_HDROP` multi-file clipboard reading with bitmap fallback.
- Global `Ctrl+V` handling in the visual editor.
- Explicit wheel-event routing so scrolling does not become trapped over large unsplit previews or the split workspace.
- Shared `HorizontalRowDetector` used by **Detect rows** and export compaction.
- Conservative staff/tab-system grouping, background-aware activity detection, wide blank-band cuts, and guard padding for faint lyrics and rhythm notation.
- Up to 32 proposed split rows, all editable after detection.
- Minimum PDF inter-row gap reduced to 2 points.
- Title/artist rendered on the first PDF page only.
- Improved local title/artist OCR preprocessing and Songsterr-label filtering.
- Unified detected-text and manual lyric/backing-vocal highlighting.
- Song Pool draft deletion with confirmation while retaining shared assets.
- Regression coverage for copied-file import boundaries, mouse-wheel scrolling, staff-system detection, faint lyrics, narrow notation gaps, deletion, PDF layout, and related helpers.
- Updated `AGENTS.md` delegation hierarchy: Codex primary, text-only GLM 5.2 for limited higher-level review, local Qwen for routine work.

Important modified/new files include:

- `lib/application/horizontal_row_detector.dart`
- `lib/application/windows_clipboard_reader.dart`
- `lib/application/visual_import_service.dart`
- `lib/application/visual_image_processor.dart`
- `lib/application/pdf_export_service.dart`
- `lib/application/text_recognition_service.dart`
- `lib/features/import/visual_import_screen.dart`
- `lib/features/import/multi_row_split_dialog.dart`
- `lib/features/import/text_highlighter_dialog.dart`
- `lib/features/home/home_screen.dart`
- `lib/infrastructure/local_library.dart`
- `test/visual_image_processor_test.dart`
- `test/widget_test.dart`
- `test/songsterr_visual_qa_test.dart`

Use `git status --short` for the complete list.

## Verification evidence

The latest slice was verified on 20 July 2026:

- Live Windows UI check: two images selected together in Explorer, copied, and pasted into a freshly rebuilt app became `Row 1` and `Row 2`.
- `flutter test --reporter expanded`: 25/25 passed.
- `flutter analyze`: no issues.
- `flutter build windows --release`: passed.
- `flutter build apk --debug`: passed.
- `git diff --check`: passed; only Git's existing LF-to-CRLF warnings were printed.
- A real Songsterr screenshot was compacted and visually inspected. Detected rows retained lyrics/rhythm notation and used thin 2-point gaps.

Build/QA artifacts:

- `build\windows\x64\runner\Release\music_tabbler.exe`
- `build\app\outputs\flutter-apk\app-debug.apk`
- `build\qa\songsterr-safe-compact.pdf`
- `build\qa\songsterr_safe\page-1.png`

The APK currently builds with a future Kotlin migration warning from `desktop_drop`, `file_picker`, and the vendored `flutter_ocr_native`. This is recorded debt, not a current build failure.

## Known limitations and cautions

- The automatic row detector is deliberately conservative. It may retain a header or footer rather than risk cutting notation or lyrics; proposals are intended for manual fine tuning.
- Title/artist OCR and detected lyric words are assistive, user-correctable proposals. They are not guaranteed complete.
- Extending a lyric highlight to the tab below is geometric same-column mapping, not semantic note/lyric alignment.
- Imported visual charts do not yet have semantic note or lyric editing.
- Direct URL intake is still a UI/workflow placeholder; Songsterr/Ultimate Guitar/YouTube adapters are not implemented.
- Setlist persistence/export, safe portable state bundles, Android gig mode, S Pen annotations, full semantic OMR, transposition, and re-tabbing remain future work.
- Theme preference and semantic sample-song data are not persisted yet; visual drafts are persisted.
- The current notation painter is a semantic prototype, not production engraving.
- Android parity has only been build-verified, not exercised end to end on the user's physical tablet.

## Recommended next work

Keep the reliable visual fallback ahead of semantic research until the gig workflow is dependable.

1. Have the user test **Detect rows** and A4 export on a complete set of actual Songsterr screenshots. Iterate on stage-readable density and any remaining unsafe/over-conservative cuts.
2. Exercise the current import, split, highlighter, save/reopen, delete, and export flow on the physical Samsung tablet. Record Android-specific failures before expanding scope.
3. Add ordered setlist storage and combined setlist PDF export using references to Song Pool charts.
4. Add safe `.mtstate`/`.mtsong` export/import with checksum validation, staging, last-known-good preservation, and failure recovery.
5. Persist theme/gig-display preference, then implement Android gig navigation, keep-awake behavior, and nondestructive S Pen vector overlays.
6. Start Songsterr semantic recognition only with an annotated fixture set, explicit metrics, confidence states, and side-by-side correction.
7. Review source terms/content rights and dependency licenses before implementing or distributing any online adapter or making the repository public.

## External reference material

These files are user-owned references outside the repository and should not be committed without explicit permission:

- `C:\Users\Gerri\OneDrive - Nanyang Technological University\Guitar shiet\9mm.pdf`
- `C:\Users\Gerri\OneDrive - Nanyang Technological University\Guitar shiet\9mm (squeezed).pdf`
- `C:\Users\Gerri\OneDrive - Nanyang Technological University\Guitar shiet\Nothing's gonna change my love for you - George benson.pdf`
- Songsterr target screenshot: `C:\Users\Gerri\AppData\Local\Temp\codex-clipboard-15ec96be-1fb5-44f5-af19-efbe5dc86e87.png`

Temporary clipboard screenshots under `C:\Users\Gerri\AppData\Local\Temp` may disappear. The rendered QA PDF and PNG under `build\qa` are the durable local evidence for this working tree, although `build` artifacts are normally untracked.

## Local-model delegation

Follow `AGENTS.md` exactly. Query `http://127.0.0.1:8080/v1/models` before Qwen delegation and use the returned identifier. GLM 5.2 is text-only and uses limited NanoGPT quota. Keep architecture, visual judgment, security/legal work, destructive actions, and final verification with Codex.

During this handover task, Qwen was asked for a read-only inventory. The first request failed on malformed UTF-8; the sanitized retry completed but returned an empty final response. No Qwen result was accepted into this document.
