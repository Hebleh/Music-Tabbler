# Music Tabbler handover

Updated: 31 July 2026

This is the fastest restart document for a new Codex task. Read this file, then `AGENTS.md`, `docs/CURRENT_STATUS.md`, `docs/SPEC.md`, and `ARCHITECTURE.md`. Do not discard or reset user work; inspect the current branch and working tree before starting a contract.

Use `docs/ROADMAP.md` as the live checkbox tracker for contract status, sprint
order, the user-testing gate, and the reusable implementation cycle.

## Immediate state

- Windows repository: `C:\vibes\Music Tabbler`
- Mac repository: `/Users/guh/Vibes/Codex/Music Tabbler`
- Stable integration branch: `master`
- Apple validation branch: `codex/mt-602-apple-full-validation` at `81763a4`
- Current Windows regression branch: `codex/windows-post-apple-regression`
- Apple validation history is pulled into the Windows checkout. The current
  branch contains the follow-up real-9mm semantic segmentation and review
  repairs.
- Immutable MVP archive branch: `mvp/v0.1.0`
- Release checkpoint: Windows MVP `v0.1.0`
- Git remote: private `Hebleh/Music-Tabbler`
- License: intentionally undecided pending source terms and content-rights review; the private repository grants no public license
- Latest automated checkpoint: the complete suite passes 211/211 and
  `flutter analyze` is clean after MT-602 Apple validation plus Windows
  reviewed-visual semantic segmentation, measure-local proposal positioning,
  dead-note rendering, and source-crop repairs.
- Latest Windows Computer Use checkpoint: the disposable mixed setlist opens
  in Balanced (8 pages) and Stage-readable (15 pages) Gig mode without the old
  density-floor error. Song boundaries, duplicate entries, the red
  `Not playing` placeholder, sidebar jumps, annotation controls, Clear All,
  and explicit Exit were exercised without touching the user's main library.
- Near-term product target: dependable, stage-readable charts for the user's 16 August 2026 gig
- Current user-test sheet: `docs/COMBINED_USER_TEST_SPRINT6.md`

Before making changes, run:

```powershell
git status --short
git diff --check
flutter analyze
flutter test
```

For normal app iteration, launch with `dev.bat`. It wraps `dev.ps1`, defaults to Windows `flutter run`, supports hot reload, and deliberately does not produce a release package. Use `dev.bat -Device <flutter-device-id>` for another connected Flutter target.

Do not use `git reset --hard`, `git checkout --`, or otherwise discard user work.

## MT-602 Apple validation checkpoint

- Branch `codex/mt-602-apple-full-validation` was created from `7cb75c9` and
  pushed to the private origin. Focused commits add Apple runners, Apple PDFium
  deployment, semantic/all-row review repairs, responsive Song Pool cards, and
  validation documentation.
- Flutter 3.44.8 / Dart 3.12.2, Xcode 26.6, CocoaPods 1.17.0, and iOS 26.5
  Simulator were used. `flutter analyze` reports no issues and the complete
  suite passes 207/207.
- macOS debug and release builds succeed. The exact release app is a universal
  x86_64/arm64 bundle with bundle ID `com.gerri.musicTabbler`; `codesign
  --verify --deep --strict` passes with an ad-hoc signature. It is not
  Developer-ID signed or notarized.
- The current local portable ZIP is
  `tmp/apple-validation/release/Music-Tabbler-macOS-universal-mt602-vt024.zip`,
  29,457,337 bytes, SHA-256
  `39ecd4e000a5f0b7eea10dcb3c0d3653022c89c3aebd6b4d7b927a9a2a8a8ae9`.
  It was made from a clean release build after the VT-023/VT-024 repairs,
  extracted again, checked as universal x86_64/arm64, passed strict deep
  signature verification, and launched to the populated Song Pool. It is
  evidence only and is intentionally ignored/unpublished. The older
  `Music-Tabbler-macOS-universal-mt602.zip` is superseded.
- iPhone 17 and iPad Air 11-inch Simulator builds launch. Portrait and
  landscape Song Pool layouts are readable after the responsive repair.
  Physical iPhone signing/device behavior remains unverified.
- The Windows-exported `music-tabbler-library.mtstate` remains untracked and
  unchanged. Its SHA-256 and the isolated validation copy both equal
  `e8c6b9d5d7d112b0cd3688a6173bb810535a48b28c860dab49b9f41978332cc9`.
- The disposable macOS library imported 8 variants and 4 setlists. The real
  29-row `9mm` review retained 822 fret/dead-note tokens, including 88 on row
  27. Semantic recognition created 29 proposed measures containing 822
  source-aligned note proposals in 5-string BEADG. One note was accepted and
  persisted across quit/reopen; the chart was never bulk-verified or marked
  gig-ready.
- A real four-page PDF imported, rendered, saved, and reopened in the sandboxed
  macOS app. PDF tests that previously timed out now complete through
  `pdfium_flutter`.
- All 16 usable PDFs under the external `Guitar shiet` fixture folder were
  imported and exported through the deterministic A4 round-trip test: 42/42
  source pages passed. Poppler renders of all source pages were also inspected
  in five contact sheets. The set includes portrait, landscape, sparse,
  highlighted, dense single-page, and eight-page inputs. No source or rendered
  fixture was added to Git.
- The real-fixture run exposed VT-022: the macOS Flutter test bootstrap selected
  the x86_64 PDFium dylib by path ordering on an arm64 host. The bootstrap now
  selects `mac-arm64` or `mac-x64` from `Abi.current()`; the formerly hanging
  real two-page round trip passes in about three seconds including test startup.
- Restored Mac window ownership enabled a second exact-release UI pass. The
  Windows state merged through the native picker as 8 variants and 4 setlists;
  a corrupt `.mtstate` was rejected while database counts stayed unchanged, and
  picker cancellation was non-mutating. Stage-readable Gig mode rendered 12
  pages with sidebar jumps, duplicate entries, a dedicated placeholder page,
  next/previous navigation, explicit Exit, drawing, hide/show, Undo, PDF
  inclusion, and Clear All. Performance Preview used its own density title,
  rendered the same 12-page plan, navigated, and exited explicitly.
- That pass found and repaired VT-023, where multi-strip Gig controls targeted
  only the first strip, and VT-024, where a song containing a semantic variant
  could not export as `.mtsong`. The rebuilt release app passed both real 9mm
  retests. `.mtsong` schema 2 now preserves mixed visual/semantic variants while
  retaining schema-1 import compatibility.
- Do not merge, tag, bump the version, or publish `v0.2.0-beta.2` yet. Required
  remaining gates include the Windows/Android shared regression, physical
  iPhone/hardware checks, the deferred complete fixture/UI matrix items listed
  in `docs/BUGS_MT504_VALIDATION.md`, and the Unicode PDF-header font decision.
- Existing `master`, `v0.1.0`, `mvp/v0.1.0`, `v0.2.0-beta.1`, and its release
  remain unchanged.

## Windows post-Apple regression checkpoint

- The Apple branch was pulled at `81763a4` and continued on
  `codex/windows-post-apple-regression`.
- Reviewed visual analysis no longer creates one semantic measure per full
  strip. Bar-line geometry splits the real 9mm fixture into 129 proposed
  measures while retaining all 822 reviewed fret/dead-note proposals.
- Proposal positions remain local to their semantic measure after save/reopen;
  source comparison crops preserve aspect ratio and center the selected source
  token. Dead notes render as one `x`, without an adjacent synthetic `0`.
- The automated checkpoint is 211/211 tests, clean analysis, and clean
  `git diff --check` apart from the repository's existing Windows line-ending
  advisory.
- Balanced Gig mode renders the four-item `RITN` fixture in 8 pages and
  Stage-readable renders it in 15. Each song and placeholder starts on a fresh
  page; duplicate and placeholder sidebar entries remain available.
- The Android debug APK was rebuilt successfully at
  `build\app\outputs\flutter-apk\app-debug.apk` (242,720,986 bytes, SHA-256
  `8e341bdd0d165cea87baf51e4a3f88f83e1c53c69a55eff2fd66a8b45ff13416`).
  It is a development artifact, not a release package.
- Remaining meaningful gate: install and exercise the APK on the user's
  Samsung tablet, including import/export, Back, fullscreen, swipe navigation,
  keep-awake cleanup, S Pen behavior, annotations, and restart persistence.

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
12. In **Gigs**, create an ordered setlist, repeat songs, add light-red
    non-playing placeholders, reorder entries, export one combined PDF, or open
    the performance preview/gig view.
13. Use the home toolbar's **Library transfer and recovery** action to export,
    merge, replace, or restore `.mtstate`. Replacement validates first and
    creates a backup. Song-level `.mtsong` import/export is available from Song
    Pool actions.

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
- `flutter test --no-pub` after MT-203: 125/125 passed, including portable
  archive adversarial checks, `.mtsong` round trips, transactional `.mtstate`
  replacement/merge/restore, corrupt-existing-asset rejection, setlist/PDF,
  performance, annotation, Android widget, and legacy workflow regressions.
- `flutter analyze --no-pub` and `git diff --check` after MT-203 reported no
  issues.
- `flutter test` after MT-503 passes 163/163 tests. `flutter analyze --no-pub`
  and `git diff --check` pass.
- Combined-test debug builds on 24/25 July 2026 succeeded:
  `build\windows\x64\runner\Debug\music_tabbler.exe` and
  `build\app\outputs\flutter-apk\app-debug.apk`. The APK SHA-256 is
  `1D1842A646482712A8D31BB2892E7FC76AF989CFF15C25A82C4701AB027B274E`.

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
- Master side-crop control positions now persist explicitly through the saved
  visual-strip schema and JSON round trips. The full mixed-width interaction
  matrix still needs Windows UI confirmation.
- Extending a lyric highlight to the tab below is geometric same-column mapping, not semantic note/lyric alignment.
- Imported visual charts become editable semantic note/lyric proposals only
  through local recognition and explicit review.
- Direct URLs are stored only as local provenance and can be opened in the
  normal browser. Songsterr/Ultimate Guitar/YouTube adapters are not
  implemented.
- Recognition remains assistive rather than bulletproof: every proposal must be
  corrected and verified before gig-ready use or trusted transformation.
- Semantic variants persist. Pitch transposition, same-pitch re-tabbing, and
  ranked fingering variants are implemented pending Windows user verification.
- The current notation painter is a semantic prototype, not production engraving.
- Android parity has only been build-verified, not exercised end to end on the user's physical tablet.

## Recommended next work

Keep the reliable visual fallback ahead of semantic research until the gig workflow is dependable.

1. Fetch `codex/mt-602-apple-full-validation` in the Windows checkout and run
   the complete shared regression before merging.
2. Confirm the 9mm visual +1 fallback, transformed semantic proposal review,
   split master-crop reopen, long-chart scrolling, PDFs, setlists, Preview, and
   Gig mode on Windows.
3. Build and exercise Android after the Windows workflow is accepted.
4. Merge to `master` and prepare `v0.2.0-beta.2` only when those gates and the
   remaining manual/hardware checks are truthfully documented.
5. Review source terms/content rights and dependency licenses before
   implementing or distributing any online adapter or making the repository
   public.

## External reference material

These files are user-owned references outside the repository and should not be committed without explicit permission:

- `C:\Users\Gerri\OneDrive - Nanyang Technological University\Guitar shiet\9mm.pdf`
- `C:\Users\Gerri\OneDrive - Nanyang Technological University\Guitar shiet\9mm (squeezed).pdf`
- `C:\Users\Gerri\OneDrive\Desktop\10mm.pdf` (Music Tabbler export of 9mm,
  renamed only for comparison)
- `C:\Users\Gerri\OneDrive - Nanyang Technological University\Guitar shiet\Nothing's gonna change my love for you - George benson.pdf`
- Songsterr target screenshot: `C:\Users\Gerri\AppData\Local\Temp\codex-clipboard-15ec96be-1fb5-44f5-af19-efbe5dc86e87.png`

Temporary clipboard screenshots under `C:\Users\Gerri\AppData\Local\Temp` may disappear. The rendered QA PDF and PNG under `build\qa` are the durable local evidence for this working tree, although `build` artifacts are normally untracked.

## Local-model delegation

Follow `AGENTS.md` exactly. Query `http://127.0.0.1:8080/v1/models` before Qwen delegation and use the returned identifier. GLM 5.2 is text-only and uses limited NanoGPT quota. Keep architecture, visual judgment, security/legal work, destructive actions, and final verification with Codex.

Pi's GitHub access was reported working again on 21 July 2026. Future routine release packaging/GitHub chores may be delegated when a release is explicitly requested, but ordinary development must not package releases and Codex must verify the final scope and artifacts. Ordinary development uses `dev.bat` and does not package releases. The user explicitly requested Windows and Android debug builds for the combined MT-107-through-MT-203 test checkpoint; these are development artifacts, not a public release.

The local Qwen endpoint was subsequently restored on 21 July 2026. Its read-only review of `dev.ps1` identified a PowerShell 7 native-error preference edge case; Codex reviewed and applied the narrow exit-code hardening.

During this handover task, Qwen was asked for a read-only inventory. The first request failed on malformed UTF-8; the sanitized retry completed but returned an empty final response. No Qwen result was accepted into this document.
