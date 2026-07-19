# Current status

Updated: 19 July 2026

## Repository state

- Product and architecture decisions are documented.
- A shared Flutter project targets Windows and Android from one codebase.
- A local Git repository exists on `main`; no remote or license has been created.
- The first product shell replaces the generated counter application.
- Repository visibility remains undecided pending legal/source-adapter review.

## Verified foundation

- Flutter 3.44.6 stable and Dart 3.12.2 are installed.
- `flutter doctor -v` reports no issues for Windows or Android.
- Windows uses Visual Studio Build Tools 2022 17.14.25 and Windows SDK 10.0.26100.0.
- Android uses API 36, Build Tools 36.0.0, Platform Tools 37.0.0, Emulator 36.6.11, NDK 28.2.13676358, CMake 3.22.1, and JDK 21.0.10.
- `flutter analyze` passes with no issues.
- `flutter analyze` passes and five model/widget tests pass.
- `flutter build windows --release` produces `music_tabbler.exe`.
- `flutter build apk --debug` produces a 146,210,932-byte debug APK.

## Confirmed product decisions

- Windows first; Android next with full feature parity and tablet-optimized gig mode.
- Fully local operation and manual portable state transfer.
- A4 PDF for individual songs and ordered setlists.
- Song pool, chart variants, setlists/gigs, and new/import areas.
- Direct chosen URL is the primary online intake; search/scouring is secondary.
- PDF/image/screenshot crop-and-arrange is the reliable baseline.
- Whole-chart semantic conversion is the durable goal.
- Independent tab/standard-notation toggles; title/artist overlay toggle; provenance never rendered.
- Default bass profile BEADG, custom per-string tunings, separate transpose and re-tab operations, ranked fingering alternatives.
- Editable syllable-aligned lyrics and backing-vocal emphasis mode.
- Persistent per-device light/dark preference; gig mode first-install default is light content on black.
- State import must be staged, checksummed, backed up, transactional, and non-destructive on failure.

## Implemented first product slice

- Responsive Song Pool, Gigs, and New / Import navigation for desktop and tablet-sized layouts.
- An immutable semantic bass-chart model with BEADG tuning, measures, notes, durations, sections, and syllable-aligned lyrics.
- A custom stage-oriented renderer with string lines cleared behind fret numbers, rhythm stems, measure labels, lyrics, and a simple standard-notation view.
- Independent tablature, standard-notation, and title/artist visibility controls.
- Direct note editing for string, fret, and duration, plus backing-vocal assignment and main-vocal contrast.
- A direct URL intake field in the New / Import area as a clearly labelled workflow preview.
- Dark and light app themes selectable for the current run.

## Current limitations

- Song data and theme preferences are not persisted yet.
- File, image, clipboard, PDF, and URL imports are not connected yet.
- The notation painter is an early semantic rendering spike, not full engraving.
- PDF export, setlist storage, OCR/OMR, safe state transfer, Android gig mode, and source adapters remain future slices.

## Reference examples (external, not committed)

- `9mm.pdf`: four A4 pages with standard notation and bass tab.
- `9mm (squeezed).pdf`: one-page tab-only manual compression; demonstrates useful density and unreadable line/number collisions.
- `Nothing's gonna change my love for you - George benson.pdf`: one-page collage from scrolling-tab video screenshots.
- `Thank You for the Venom Bass Tab` Songsterr screenshot: target structure for rhythm stems, sections, measure numbers, and syllable-aligned lyrics.

## Implementation sequence

### Slice 1 - foundation and visual fallback

- **In progress:** Flutter, Windows/Android targets, local Git, product navigation, an initial semantic domain model, renderer, editor, and both platform builds are verified.
- Establish the SQLite repository boundary, asset storage, migrations, and deterministic A4 layout primitives.
- Implement song pool, song creation, PDF/PNG/JPEG/clipboard import, cropping/arrangement, simple annotations, and A4 single-song export.
- Add title/artist and notation visibility controls without committing to OCR.

### Slice 2 - semantic editor

- Implement measures, rhythms, notes/rests, strings/frets, tuning presets, repeats, sections, lyrics, semantic rendering, and direct note editing.
- Import/export MusicXML fixtures where supported.
- Add backing-vocal edit/preview mode and combined setlist PDF export.

### Slice 3 - Songsterr screenshot recognition

- Build fixture annotations and accuracy metrics.
- Recognize line/measure geometry, fret digits, rhythm, sections, and lyrics into a reviewable proposal.
- Add side-by-side correction and explicit gig-ready verification.

### Slice 4 - transformations and safe transfer

- Add pitch transposition, re-tabbing, ranked fingering candidates, original/adapted variants, `.mtsong`/`.mtstate`, backups, conflicts, and restore.

### Slice 5 - Android parity and gig hardening

- Exercise the full workflow on Android.
- Add swipe navigation, keep-awake behavior, tablet layouts, S Pen vector annotations, and on-device PDF/state import/export verification.

## Near-term acceptance target

For the 16 August 2026 gig, prioritize dependable Windows-created PDFs from user-supplied Songsterr screenshots, with readable compression and editable/highlighted backing-vocal lyrics. Semantic recognition and Android parity should advance behind that fallback but must not endanger it.

## Open decisions and research gates

- Confirm whether macOS becomes a supported full platform after Android.
- Establish measured stage-readable density through iterative user review.
- Define the annotated fixture corpus and acceptance thresholds for each recognition source.
- Select Flutter packages only after license, Windows/Android support, and deterministic rendering spikes.
- Review source terms/content rights before distributing online adapters or deciding repository visibility/license.
- Evaluate Crawl4AI/ordinary browser automation for direct known URLs; use SearXNG only for discovery; keep stealth-browser experiments isolated and unbundled unless separately approved and license-compatible.
