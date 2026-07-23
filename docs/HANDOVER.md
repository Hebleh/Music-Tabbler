# Music Tabbler handover

Updated: 22 July 2026

This is the fastest restart document for a new Codex task. Read this file, then `AGENTS.md`, `docs/CURRENT_STATUS.md`, `docs/SPEC.md`, and `ARCHITECTURE.md`. Do not discard or reset user work; inspect the current branch and working tree before starting a contract.

## Immediate state

- Repository: `C:\vibes\Music Tabbler`
- Stable integration branch: `master`
- Current sprint integration branch: `codex/sprint-gig-ready`
- Immutable MVP archive branch: `mvp/v0.1.0`
- Release checkpoint: Windows MVP `v0.1.0`
- Git remote: private `Hebleh/Music-Tabbler`
- License: intentionally undecided pending source terms and content-rights review; the private repository grants no public license
- Latest completed feature contract: MT-106 Ordered setlist repository; the next planned contract is MT-107 Setlist editor UI
- Near-term product target: dependable, stage-readable charts for the user's 16 August 2026 gig

Before making changes, run:

```powershell
git status --short
git diff --check
flutter analyze
flutter test
```

For normal app iteration, launch with `dev.bat`. It wraps `dev.ps1`, defaults to Windows `flutter run`, supports hot reload, and deliberately does not produce a release package. Use `dev.bat -Device <flutter-device-id>` for another connected Flutter target.

Do not use `git reset --hard`, `git checkout --`, or otherwise discard user work.

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
5. Use **Split into rows**. Reopening it from any sibling row restores the whole source page and all current boxes. **Detect rows** proposes editable boxes; use the sticky blue master side bars to align/crop common left and right edges, then fine-tune individual boxes. Even division and manual add/duplicate/delete remain available; Backspace/Delete removes the selected box.
6. Move/resize crop and row boxes directly using edges/corners. Reorder, duplicate, or delete chart rows.
7. Apply Original, Grayscale, Invert, or High contrast per row, or change the whole chart at once.
8. Open the chart-wide highlighter to work through all current split and unsplit rows in order. Select detected lyric words or draw freeform regions; freeform boxes remain editable. Optionally extend a recognized lyric selection downward to the corresponding tab column.
9. Edits autosave locally after a short debounce. Ctrl+Z or the toolbar undo restores prior draft snapshots. The Save button remains as an explicit retry/checkpoint. Saved visual drafts can be deleted after confirmation without deleting shared content-addressed assets.
10. Export A4. Title/artist appears only on page one when enabled; provenance is omitted.
11. Choose **Original**, **Balanced**, or **Stage-readable** export density. Original preserves the MVP portrait layout, while Stage-readable uses landscape A4 and larger minimum rows for at-a-glance use.

## Windows MVP checkpoint

The `v0.1.0` checkpoint contains the following completed work:

- Explorer `CF_HDROP` multi-file clipboard reading with bitmap fallback.
- Global `Ctrl+V` handling in the visual editor.
- Deterministic preview heights and native list-owned wheel scrolling, preventing asynchronous row preview loads from shifting the scroll extent during upward navigation through long charts.
- Shared `HorizontalRowDetector` used by **Detect rows** and export compaction.
- Conservative staff/tab-system grouping, background-aware activity detection, wide blank-band cuts, and guard padding for faint lyrics and rhythm notation.
- Up to 32 proposed split rows, all editable after detection.
- Artificial PDF inter-row gap removed; source crop padding is the only remaining spacing.
- Title/artist rendered on the first PDF page only.
- Improved local title/artist OCR preprocessing and Songsterr-label filtering. Windows OCR now retains Unicode and selects among installed English, Japanese, and profile engines; metadata recognition always uses the original full page so deleting a title row does not discard the source.
- Windows OCR now performs blocking C++/WinRT bitmap and recognition waits on a dedicated MTA worker instead of Flutter's STA platform thread, preventing the debug assertion encountered when opening the highlighter.
- Chart-wide detected-text and manual lyric/backing-vocal highlighting across all current rows, with crop-aware coordinate mapping, flattened yellow compositing, editable/deletable freeform boxes, and Backspace/Delete support replacing the separate lyric-area workflow.
- Crop-local OCR preprocessing with stronger upscaling for small and faint lyric fragments.
- Whole-source row re-splitting with current sibling boxes restored, dark-theme row detection, sticky master side cropping, and absolute fast-drag tracking.
- Debounced serialized autosave plus a bounded 50-snapshot undo history.
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

The latest slice has the following verification evidence:

- Live Windows UI check: two images selected together in Explorer, copied, and pasted into a freshly rebuilt app became `Row 1` and `Row 2`.
- Live `dev.bat` debug check on 21 July 2026: opened the saved 43-row chart, clicked **Open highlighter**, waited for OCR, and reached the recognized-text/freeform UI without a Visual C++ assertion window.
- Focused source tests on 21 July 2026: 14/14 passed, including a 43-row mouse-wheel regression that scrolls down to Row 43 and back up to Row 1.
- `flutter test --no-pub` on 21 July 2026: 40/40 passed after the fixed master-crop, background export, minimal-margin, metadata, and treatment changes.
- `flutter analyze` on 21 July 2026: no issues.
- `flutter build windows --release --no-pub`: passed for `v0.1.0+1`.
- The Windows release was packaged as both a user-level installer EXE and a portable ZIP; both checksum sidecars were independently re-read and matched.
- The portable ZIP was extracted into a temporary directory and its packaged executable remained running through a five-second startup smoke test.
- No APK was produced for this MVP checkpoint.
- `git diff --check`: passed; only Git's existing LF-to-CRLF warnings were printed.
- A real Songsterr screenshot was compacted and visually inspected. Detected rows retained lyrics/rhythm notation and used thin 2-point gaps.
- MT-101 real-chart QA on 22 July 2026 generated Original, Balanced, and Stage-readable PDFs from the reference Songsterr screenshot. The approved Stage-readable profile produced one landscape page with larger content and no clipped notation, lyrics, or invented trailing page.
- MT-104 adds transactional SQLite schema migrations, stable song/visual-variant identities, and a separate repository boundary without changing current visual-editor callers. A copied real MVP library migrated, edited, reopened, and retained identical asset hashes; the installed library was never modified.
- MT-106 adds schema-v3 ordered setlists, duplicate chart references with distinct stable entry IDs, metadata persistence, transactional reorder/save, and typed reference blockers. A copied real library created, reopened, and deleted a duplicate-entry setlist without changing its chart or asset hashes.
- `flutter test --no-pub` after MT-106: 58/58 passed; the combined focused persistence suite passed 14/14; `flutter analyze --no-pub` reported no issues.

Release artifacts:

- `build\release\Music-Tabbler-v0.1.0-Windows-x64.exe`
- `build\release\Music-Tabbler-v0.1.0-Windows-x64.exe.sha256`
- `build\release\Music-Tabbler-v0.1.0-Windows-x64-portable.zip`
- `build\release\Music-Tabbler-v0.1.0-Windows-x64-portable.zip.sha256`

The APK currently builds with a future Kotlin migration warning from `desktop_drop`, `file_picker`, and the vendored `flutter_ocr_native`. This is recorded debt, not a current build failure.

## Known limitations and cautions

- The automatic row detector is deliberately conservative. It may retain a header or footer rather than risk cutting notation or lyrics; proposals are intended for manual fine tuning.
- The user identified the scroll failure more precisely: after lower rows loaded, upward wheel input could stick and jiggle while scrollbar-thumb dragging remained reliable. Preview heights are now stable before/after asynchronous loading, custom wheel rerouting has been removed, and a 43-row down/up regression passes. Real-chart confirmation through `dev.bat` is still required.
- Title/artist OCR and detected lyric words are assistive, user-correctable proposals. They are not guaranteed complete.
- Japanese OCR depends on the optional Japanese Windows OCR language capability. The app tries `ja-JP`, English, and profile recognizers and falls back safely when a language engine is unavailable.
- Japanese title/artist detection remains unreliable on real score headings and is accepted technical debt for the MVP.
- Master side-crop control positions do not persist reliably through every split-dialog action or reopening; saved row crops remain intact. This convenience-state limitation is accepted MVP debt.
- Extending a lyric highlight to the tab below is geometric same-column mapping, not semantic note/lyric alignment.
- Imported visual charts do not yet have semantic note or lyric editing.
- A combined full-chart performance/gig preview remains deferred by request. The chart-wide highlighter composes the current rows for editing only.
- Direct URL intake is still a UI/workflow placeholder; Songsterr/Ultimate Guitar/YouTube adapters are not implemented.
- Setlist UI/export, safe portable state bundles, Android gig mode, S Pen annotations, full semantic OMR, transposition, and re-tabbing remain future work.
- Theme preference and semantic sample-song data are not persisted yet; visual drafts are persisted.
- The current notation painter is a semantic prototype, not production engraving.
- Android parity has only been build-verified, not exercised end to end on the user's physical tablet.

## Recommended next work

Keep the reliable visual fallback ahead of semantic research until the gig workflow is dependable.

1. Add the setlist editor for creating, naming, deleting, populating, duplicating, and reordering entries.
2. Add combined setlist PDF export.
3. Exercise the current import, split, highlighter, save/reopen, delete, and export flow on the physical Samsung tablet. Record Android-specific failures before expanding scope.
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

Pi's GitHub access was reported working again on 21 July 2026. Future routine release packaging/GitHub chores may be delegated when a release is explicitly requested, but ordinary development must not package releases and Codex must verify the final scope and artifacts. The user explicitly requested no new builds or packages during the current home-development phase; use `dev.bat` only for interactive app launches.

The local Qwen endpoint was subsequently restored on 21 July 2026. Its read-only review of `dev.ps1` identified a PowerShell 7 native-error preference edge case; Codex reviewed and applied the narrow exit-code hardening.

During this handover task, Qwen was asked for a read-only inventory. The first request failed on malformed UTF-8; the sanitized retry completed but returned an empty final response. No Qwen result was accepted into this document.
