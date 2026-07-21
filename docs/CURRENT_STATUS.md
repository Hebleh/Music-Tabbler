# Current status

Updated: 20 July 2026

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
- `flutter analyze` passes with no issues, and 25 model, persistence, bulk-import, image-processing, PDF, OCR-helper, and widget tests pass.
- `flutter build windows --release` produces `music_tabbler.exe`.
- `flutter build apk --debug` produces an installable debug APK.

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

## Implemented product slices

- Responsive Song Pool, Gigs, and New / Import navigation for desktop and tablet-sized layouts.
- An immutable semantic bass-chart model with BEADG tuning, measures, notes, durations, sections, and syllable-aligned lyrics.
- A custom stage-oriented renderer with string lines cleared behind fret numbers, rhythm stems, measure labels, lyrics, and a simple standard-notation view.
- Independent tablature, standard-notation, and title/artist visibility controls.
- Direct note editing for string, fret, and duration, plus backing-vocal assignment and main-vocal contrast.
- A direct URL intake field in the New / Import area as a clearly labelled workflow preview.
- Dark and light app themes selectable for the current run.

### Manual visual-chart workflow

- PNG/JPEG screenshots and multi-page PDFs can be imported into an editable visual-chart draft.
- Windows can paste either copied bitmap pixels or one or more image/PDF files copied in Explorer; Android uses image/PDF file picking in this iteration.
- Imports are normalized into immutable, SHA-256-addressed local assets and catalogued in SQLite.
- A chart is arranged as full-width horizontal tab rows. Rows can be reordered, duplicated, cropped, or removed without changing the source asset.
- Each row can use Original, Grayscale, Invert, or High contrast treatment, with a whole-tab dropdown to apply one treatment in one action.
- Existing screenshot lyrics remain part of the source image. A lyric band can receive adjustable contrast and multiple translucent backing-vocal highlight regions.
- Named drafts persist in Song Pool and reopen with their crop, ordering, display, lyric-band, and highlight edits intact.
- Saved visual drafts can be deleted from Song Pool after an explicit confirmation; shared content-addressed source assets are retained.
- A4 export uses deterministic, one-column pagination with optional compact title/artist headers and never includes provenance metadata.
- The real `9mm (squeezed).pdf` reference was imported, split into rows, exported, rendered back to PNG, and visually inspected as a two-page A4 result.

### Bulk visual workflow revision

- `Ctrl+V` invokes Windows paste anywhere in the visual editor. It accepts bitmap pixels and multi-file Explorer selections, while the existing paste button remains available.
- Images, PDFs, and whole screenshot folders can be dragged onto the editor; supported files are recursively collected and imported in stable path order.
- Any imported page or screenshot has a **Split into rows** workspace. It starts with five full-width boxes, supports up to 32 evenly divided rows, and keeps every box visible and independently movable/resizable on the same page.
- **Detect rows** proposes editable boxes from repeated tab/staff systems and guarded blank bands, so manual work is fine tuning rather than drawing every row.
- Crop, lyric-area, manual-highlight, and split-row rectangles now use direct PowerPoint-style movement plus eight edge/corner handles; sliders remain for crop/lyric fine tuning.
- On-device OCR runs through ML Kit on Android and WinRT on Windows. The first imported page suggests title and artist automatically, with a manual re-detect button and editable correction fields.
- OCR input is upscaled, normalized, and contrast-enhanced in a background isolate. Songsterr UI labels such as `Tab` are excluded from artist suggestions.
- The unified backing-vocal highlighter offers recognized-text selection and freeform boxes in one dialog. An optional checkbox extends selected lyric highlights into the corresponding horizontal tab area below.
- The selected split-row box is always painted above overlapping boxes, and desktop wheel input is routed through Flutter's pointer-signal resolver to keep scrolling responsive.
- Export uses the same conservative row detector as the split workspace, trims uniform outer whitespace, and compacts tall unsplit images without changing the saved chart. Staff-line grouping plus lyric/rhythm guard padding avoids the earlier clipped-notation cuts. Inter-row PDF spacing is 2 points; title and artist render only on page one, and later pages reclaim the header space.
- Preview work crops first, caps preview width, runs image processing in a background isolate, reuses a bounded LRU cache, and isolates row repainting. Full-resolution processing remains reserved for final PDF export.
- The MIT-licensed OCR plugin is vendored under `third_party/flutter_ocr_native`; its Windows WinRT initialization is patched to join Flutter runner's existing STA apartment instead of aborting during startup.

## Current limitations

- Semantic sample-song data and theme preferences are not persisted yet; visual-chart drafts are persisted.
- Direct URL import is still a workflow placeholder. Image/PDF and OCR intake work on Windows and Android; clipboard-image paste is currently Windows-only.
- The notation painter is an early semantic rendering spike, not full engraving.
- Setlist storage/export, full tab OMR/semantic conversion, safe state transfer, Android gig mode, source adapters, semantic lyric editing, and note editing for imported visual charts remain future slices.
- Title/artist and text-region OCR are assistive proposals and must remain user-correctable. The "corresponding tab below" option is currently a geometric same-column extension, not semantic note-to-lyric alignment.
- Export whitespace detection is intentionally conservative. Tiny isolated footer marks or source page numbers can preserve trailing whitespace rather than risk deleting notation or lyrics.
- `file_picker` is pinned to 10.3.10 because its current 11.x Android plugin assumes Flutter's built-in Kotlin migration. `file_picker`, `desktop_drop`, and `flutter_ocr_native` currently emit the same future Kotlin-migration warning, although the APK builds successfully today.

## Reference examples (external, not committed)

- `9mm.pdf`: four A4 pages with standard notation and bass tab.
- `9mm (squeezed).pdf`: one-page tab-only manual compression; demonstrates useful density and unreadable line/number collisions.
- `Nothing's gonna change my love for you - George benson.pdf`: one-page collage from scrolling-tab video screenshots.
- `Thank You for the Venom Bass Tab` Songsterr screenshot: target structure for rhythm stems, sections, measure numbers, and syllable-aligned lyrics.

## Implementation sequence

### Slice 1 - foundation and visual fallback

- **Complete:** Flutter, Windows/Android targets, local Git, product navigation, an initial semantic domain model, renderer, editor, and both platform builds are verified.
- **Complete:** Establish the SQLite repository boundary, content-addressed asset storage, schema-v1 draft persistence, and deterministic A4 layout primitives.
- **Complete:** Implement visual Song Pool drafts, PDF/PNG/JPEG intake, Windows clipboard intake, cropping/arrangement, reversible lyric emphasis, and A4 single-song export.
- **Complete:** Add compact title/artist PDF visibility and per-row/whole-tab display treatments without committing to OCR.
- **Next:** Exercise the manual flow on a physical Android tablet, tune stage-readable density with real Songsterr screenshots, and add ordered setlist PDF export.

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
