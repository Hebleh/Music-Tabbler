# Current status

Updated: 11 August 2026

## Repository state

- `master` remains at the verified visual-first checkpoint `17aace3`.
  `refractor` contains the semantic-retirement refactor and subsequent focused
  cleanup; GitHub's remote default branch has not been changed.
- `music-tabbler-library.mtstate`, coverage output, build products, and local
  user data are not repository inputs. The tracked refactor must not alter the
  user's state file.
- Windows remains the primary exercised product target. Flutter/Dart behavior
  stays Android-compatible; macOS is a supported local development/smoke
  target. No release artifacts are produced during ordinary iteration.

## Active product

Music Tabbler is visual-first and local-only:

- PDF, PNG, JPEG, clipboard, and Android shared-PDF intake;
- page/row detection, crop, split, reorder, deskew, and treatment;
- positioned-PDF and raster OCR review with editable tokens and seam risks;
- nondestructive visual string/fret transformation and tuning presets;
- Song Pool variants, ordered setlists, duplicates, and placeholders;
- deterministic single-chart and combined-setlist A4 PDF;
- canonical cached performance decks for preview and Gig Mode;
- Gig bar reflow, alignment, per-song/set-wide zoom, theme, toolbar hiding,
  stage lock, keep-awake, and vector annotations;
- checksummed `.mtsong` / `.mtstate` transfer and atomic recovery.

The semantic editor, semantic recognition, MusicXML, semantic layout/PDF,
pitch transposition, and same-pitch semantic re-tabbing are retired. They are
not active features and are not retained as dormant runtime code.

## Persistence

- Library schema v6 contains visual songs/variants, drafts, setlists, and
  content-addressed assets only.
- Opening a v5 library first creates and validates a permanent checksummed
  `pre-semantic-sunset-<timestamp>.mtstate`. Failure aborts startup while the v5
  database remains unchanged.
- Migration converts semantic setlist references to same-position placeholders
  using song titles, then removes semantic variants, semantic-only orphan songs,
  the semantic table, and the obsolete variant-kind discriminator.
- `.mtsong` and `.mtstate` schema v3 export visual data only.
- Legacy schema-v2 archives are fully validated, their visual content is
  installed, semantic IDs are reported as skipped, and affected setlist
  references become placeholders. A semantic-only song bundle imports nothing.

## Current structure

- Application contracts are separated into library, import, export, and
  platform responsibilities.
- `PortableLibraryStore` is the archive/state persistence boundary; portable
  services do not inspect `LocalLibrary` directories.
- `VisualChartDraft` owns the canonical display-title/artist fallback.
- `VisualDraftEditSession`, `SetlistEditSession`,
  `VisualAnalysisReviewSession`, and `GigViewportSession` own their shared
  non-widget rules.
- `VisualChartPdfExporter`, `CachedPerformanceDeckBuilder`, and
  `SetlistPdfExportService` replace the former triple-purpose PDF service.
- `CachedPerformanceDeckBuilder.cacheDiagnostics` reports cache hits, misses,
  evictions, failures, pending entries, retained page/element counts, and
  estimated retained image bytes without changing the three-deck LRU policy or
  rendered output.

## Verification state

The protected pre-refactor baseline was 268 passing tests, clean strict
analysis, and 72.3% line coverage. Semantic-only tests were intentionally
removed with the product subsystem. Migration, legacy archive, title,
edit-session, Gig viewport/annotation, OCR review, PDF, and widget tests protect
the active behavior. Windows visual goldens now protect representative Gig
viewport composition and analysis waiting/failure states before further
presentation extraction. The current visual-only suite passes 232/232 with
clean strict analysis and 71.1% line coverage (7,122 of 10,021 lines).

## Intentionally unchanged

OCR thresholds, row detection, crop/deskew image processing, visual transform
algorithms, Gig bar repacking, layout constants, isolate messages, pagination,
and PDF appearance were not tuned during the architecture refactor.

## Current limitations

See `docs/TECHNICAL_DEBT.md`. The highest-value remaining work is physical
Android validation, Unicode PDF fonts, and further presentation-file splitting
after visual golden coverage is stronger.
