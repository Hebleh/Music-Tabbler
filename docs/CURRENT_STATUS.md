# Current status

Updated: 24 July 2026

## Repository state

- Product and architecture decisions are documented.
- A shared Flutter project targets Windows and Android from one codebase.
- `dev.bat` is the normal Windows development entry point and wraps `dev.ps1`; release builds and packaging are reserved for explicit release or milestone checkpoints.
- Accepted post-MVP limitations are tracked in `docs/TECHNICAL_DEBT.md`.
- Contract progress and the implementation-to-user-testing cycle are tracked in
  `docs/ROADMAP.md`.
- A local Git repository exists on `master` with the private `Hebleh/Music-Tabbler` remote. Public licensing remains intentionally undecided.
- The first product shell replaces the generated counter application.
- The repository is private pending legal/source-adapter and public-license review.

## Verified foundation

- Flutter 3.44.6 stable and Dart 3.12.2 are installed.
- `flutter doctor -v` reports no issues for Windows or Android.
- Windows uses Visual Studio Build Tools 2022 17.14.25 and Windows SDK 10.0.26100.0.
- Android uses API 36, Build Tools 36.0.0, Platform Tools 37.0.0, Emulator 36.6.11, NDK 28.2.13676358, CMake 3.22.1, and JDK 21.0.10.
- `flutter analyze --no-pub` passes with no issues, and the current source suite passes 125/125 tests.
- `flutter build windows --release --no-pub` produces the `v0.1.0+1` Windows runtime.
- `tool/package_windows.ps1` produces a single-file user-level installer EXE, a portable ZIP, and SHA-256 sidecars for the Windows MVP.
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
- Direct URL intake creates a fully local provenance record without fetching the
  URL. Source details remain editable and are excluded from PDFs.
- Dark/light app, gig-theme, and display preferences persist per device and are
  deliberately excluded from portable library state.

### Manual visual-chart workflow

- PNG/JPEG screenshots and multi-page PDFs can be imported into an editable visual-chart draft.
- Windows can paste either copied bitmap pixels or one or more image/PDF files copied in Explorer; Android uses image/PDF file picking in this iteration.
- Imports are normalized into immutable, SHA-256-addressed local assets and catalogued in SQLite.
- SQLite now uses ordered, transactional `PRAGMA user_version` migrations. Schema v2 adds stable song and chart-variant identities while preserving the existing visual-chart payloads and immutable assets.
- Existing MVP draft IDs remain stable visual-variant IDs. Legacy drafts receive deterministic song identities, and multiple visual variants can explicitly share one song identity through a separate repository boundary.
- SQLite schema v3 adds persistent setlists with stable setlist and entry identities, optional scheduled date and notes, and explicit entry ordering. The same chart variant may appear repeatedly without copying its chart.
- Setlist saves and reorders are transactional. Missing variants and cross-setlist entry-ID conflicts roll back cleanly. The setlist editor supports duplicate chart entries, named light-red non-playing placeholders, drag reordering, and explicit referenced-chart removal.
- Combined setlist A4 export preserves song, duplicate, and placeholder order
  under one selected Original, Balanced, or Stage-readable density profile.
- A chart is arranged as full-width horizontal tab rows. Rows can be reordered, duplicated, cropped, or removed without changing the source asset.
- Each row can use Original, Grayscale, Invert, or High contrast treatment, with a whole-tab dropdown to apply one treatment in one action.
- Existing screenshot lyrics remain part of the source image. A lyric band can receive adjustable contrast and multiple translucent backing-vocal highlight regions.
- Named drafts persist in Song Pool and reopen with their crop, ordering, display, lyric-band, and highlight edits intact.
- Saved visual drafts can be deleted from Song Pool after an explicit confirmation; shared content-addressed source assets are retained.
- A4 export uses deterministic, one-column pagination with optional compact title/artist headers and never includes provenance metadata.
- A4 export offers three persisted density profiles. **Original** preserves the v0.1.0 portrait behavior for old and new drafts by default, **Balanced** uses more conservative compaction with a 34-point row-height floor, and **Stage-readable** uses landscape A4 with a 48-point row-height floor for larger at-a-glance content.
- The real `9mm (squeezed).pdf` reference was imported, split into rows, exported, rendered back to PNG, and visually inspected as a two-page A4 result.

### Bulk visual workflow revision

- `Ctrl+V` invokes Windows paste anywhere in the visual editor. It accepts bitmap pixels and multi-file Explorer selections, while the existing paste button remains available.
- Images, PDFs, and whole screenshot folders can be dragged onto the editor; supported files are recursively collected and imported in stable path order.
- Any imported page or screenshot has a **Split into rows** workspace. Reopening it from any already-split sibling restores every row box from that source page instead of showing only the clicked crop. It supports up to 32 evenly divided rows and keeps every box visible and independently movable/resizable on the same page.
- **Detect rows** proposes editable boxes from repeated tab/staff systems and guarded blank bands. Dark-theme line thresholds cover Songsterr-style pages as well as white score pages.
- Two sticky master side-crop bars now live in a fixed control rail above the scrollable page. They catch a row only when an inward drag actually crosses that row edge, retain their positions through detect/even/add/delete actions, then pull caught edges together in either direction. Individual row-box resizing remains independent. Selected row boxes delete with Backspace/Delete.
- Crop, manual-highlight, and split-row rectangles use direct PowerPoint-style movement plus eight edge/corner handles. Gesture calculations use total pointer travel from the drag start, avoiding lost movement during fast drags. The old separate lyric-area workflow is retained only for loading older saved drafts; new highlight editing happens in the chart highlighter.
- On-device OCR runs through ML Kit on Android and WinRT on Windows. Windows tries installed English, Japanese, and profile recognizers, preserves non-Latin words, and chooses the result with the most recognized content. Metadata parsing accepts Japanese titles. Detection always reruns against the original full page, even after its title row has been removed.
- OCR input is upscaled, normalized, and contrast-enhanced in a background isolate. Songsterr UI labels such as `Tab` are excluded from artist suggestions.
- The chart-wide backing-vocal highlighter combines every current split and unsplit chart row in order. Recognized-text selection and freeform boxes share one dialog; freeform boxes can be selected, moved, resized, or deleted after drawing and replace the old separate lyric-area workflow. An optional checkbox extends recognized lyric highlights into the corresponding horizontal tab area below.
- Highlight coordinates are crop-local while editing and are mapped back to the source asset when saved. This keeps highlights attached to the correct split row and visible in the editor preview.
- The selected split-row box is always painted above overlapping boxes. Visual row previews reserve deterministic heights before asynchronous image work completes, and the native list owns wheel scrolling; this prevents lazy preview loading from repeatedly shifting the scroll extent while moving upward through long charts.
- Export uses the same conservative row detector as the split workspace, trims uniform outer whitespace, and compacts tall unsplit images without changing the saved chart. Shared source files are read and decoded once per export group, image processing and PDF assembly run off the UI isolate, and precomputed aspect ratios avoid layout-time image decoding. Staff-line grouping plus lyric/rhythm guard padding avoids the earlier clipped-notation cuts. The PDF uses a 5-point outer margin, adds no artificial inter-row gap, renders title/artist only on page one, and lets later pages reclaim the header space.
- Split rows carry an image-source or PDF-page chip, Song Pool cards show persisted last-edited metadata, and Untitled charts with an artist fall back to that artist as the card title without a placeholder subtitle.
- Visual treatments include a combined **Invert + high contrast** option for turning Songsterr's inverted greys into stronger stage-readable whites and blacks.
- Highlight pixels are flattened into the processed image as an opaque PNG containing a translucent-looking yellow blend. Editor and PDF renderers therefore cannot replace highlighted regions with black/white transparency blocks.
- Every completed editor mutation autosaves locally after a short debounce. Writes are serialized, Ctrl+Z/the toolbar undo restores up to 50 prior draft snapshots, and the restored state is autosaved. Saved/freeform highlight boxes and selected split boxes support Backspace/Delete in their editors.
- Preview work crops first, caps preview width, runs image processing in a background isolate, reuses a bounded LRU cache, and isolates row repainting. Full-resolution processing remains reserved for final PDF export.
- The MIT-licensed OCR plugin is vendored under `third_party/flutter_ocr_native`. Flutter's Windows runner remains STA, while blocking WinRT bitmap/OCR waits run on a dedicated MTA worker and return plain results on the original platform thread. This prevents the debug C++/WinRT `!is_sta_thread()` assertion when opening the highlighter.

### Performance, Android, and portable data

- A shared deterministic performance deck drives setlist PDF planning, desktop
  preview, and Android gig navigation so page/song ordering cannot drift.
- Desktop preview and Android gig mode provide explicit next/previous/exit
  behavior. Android fullscreen and keep-awake state are active only during gig
  mode and are released on exit or lifecycle changes.
- The gig sidebar shows the complete editable set order, supports placeholders,
  reordering, and direct jumps.
- Vector annotations use normalized coordinates, autosave without changing
  source assets, support undo/erase/visibility, and enter PDF output only when
  explicitly enabled.
- Android input distinguishes stylus, inverted-stylus eraser, and touch/palm
  input; pressure is preserved where the device supplies it.
- `.mtsong` bundles round-trip a song's visual variants, assets, provenance,
  and annotations through a checksummed, size-limited portable container.
- `.mtstate` transfers the whole song/setlist library. Import fully stages and
  validates content before changes, supports merge or replacement, creates a
  recoverable last-known-good backup before replacement, retains five backups,
  and can restore them. Device preferences are excluded.
- Portable archives reject traversal, ambiguous or duplicate paths, unsupported
  ZIP structures, undeclared files, excessive expansion, checksum failures, and
  corrupt pre-existing content-addressed assets.

## Current limitations

- Semantic sample-song data is not persisted yet; visual-chart drafts and
  per-device preferences are persisted.
- Direct URL records do not download or scrape content. Image/PDF and OCR intake
  work on Windows and Android; clipboard-image paste is currently Windows-only.
- The notation painter is an early semantic rendering spike, not full engraving.
- Full tab OMR/semantic conversion, source adapters, semantic lyric editing, and
  note editing for imported visual charts remain future slices.
- Title/artist and text-region OCR are assistive proposals and must remain user-correctable. OCR is now performed on each cropped chart row with stronger upscaling so small, faint, widely spaced lyric fragments have more pixels to work with, but isolated characters may still need freeform selection. The "corresponding tab below" option is currently a geometric same-column extension, not semantic note-to-lyric alignment.
- Japanese OCR on Windows requires the optional Japanese Windows OCR language capability to be installed. If `ja-JP` is unavailable, the plugin falls back to the installed English/profile recognizers.
- Export whitespace detection is intentionally conservative. Tiny isolated footer marks or source page numbers can preserve trailing whitespace rather than risk deleting notation or lyrics.
- The reported 43-row upward wheel-scroll stall is covered by a regression test after stabilizing preview heights. It still needs user confirmation with the real saved chart through `dev.bat`.
- Performance preview, Android parity, S Pen behavior, and portable state are
  implemented but still await the combined physical-device/user verification
  gate recorded in `docs/ROADMAP.md`.
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
- **Complete:** Add deterministic Original, Balanced, and Stage-readable export profiles and approve the landscape Stage-readable result against a real Songsterr screenshot.
- **Complete:** Add versioned migrations and stable song/chart-variant identities with fresh, legacy-upgrade, idempotence, rollback, future-schema, and asset-integrity coverage.
- **Complete:** Add ordered setlist storage with duplicate references, stable entry identities, transactional reordering, and safe chart-reference blocking.
- **Complete pending combined user verification:** setlist editor, combined
  setlist PDF, performance preview/gig mode, Android parity, annotations, local
  provenance, `.mtsong`, and recoverable `.mtstate` transfer.

### Slice 2 - semantic editor

- Implement measures, rhythms, notes/rests, strings/frets, tuning presets, repeats, sections, lyrics, semantic rendering, and direct note editing.
- Import/export MusicXML fixtures where supported.
- Add backing-vocal edit/preview mode and combined setlist PDF export.

### Slice 3 - Songsterr screenshot recognition

- Build fixture annotations and accuracy metrics.
- Recognize line/measure geometry, fret digits, rhythm, sections, and lyrics into a reviewable proposal.
- Add side-by-side correction and explicit gig-ready verification.

### Slice 4 - transformations and safe transfer

- Add pitch transposition, re-tabbing, ranked fingering candidates, and
  original/adapted variants. Portable `.mtsong`/`.mtstate`, backups, conflicts,
  and restore are implemented pending combined user verification.

### Slice 5 - Android parity and gig hardening

- Exercise the implemented full workflow on the user's physical Android tablet.
- Swipe navigation, keep-awake behavior, tablet layouts, and S Pen vector
  annotations are implemented pending physical-device verification.

## Near-term acceptance target

For the 16 August 2026 gig, prioritize dependable Windows-created PDFs from user-supplied Songsterr screenshots, with readable compression and editable/highlighted backing-vocal lyrics. Semantic recognition and Android parity should advance behind that fallback but must not endanger it.

## Open decisions and research gates

- Confirm whether macOS becomes a supported full platform after Android.
- Establish measured stage-readable density through iterative user review.
- Define the annotated fixture corpus and acceptance thresholds for each recognition source.
- Select Flutter packages only after license, Windows/Android support, and deterministic rendering spikes.
- Review source terms/content rights before distributing online adapters or deciding repository visibility/license.
- Evaluate Crawl4AI/ordinary browser automation for direct known URLs; use SearXNG only for discovery; keep stealth-browser experiments isolated and unbundled unless separately approved and license-compatible.
