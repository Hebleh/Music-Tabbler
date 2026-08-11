# Music Tabbler architecture

## Direction

Music Tabbler is a local-first Flutter application whose active product model is
visual. Users import PDF pages or images, isolate tab rows, review local OCR,
apply nondestructive visual transforms, organize charts into setlists, and use
the same stored rows for deterministic PDF and Gig Mode output.

The former semantic chart subsystem is retired. Runtime code must not recreate
`SongChart`, MusicXML, semantic editing, semantic recognition, pitch
transposition, or semantic rendering. Schema migration and legacy-container
readers may treat old semantic payloads as opaque data solely to archive or
skip them safely.

## Layers and ownership

1. **Domain** owns visual drafts, strips, crops, highlights, annotations,
   reviewed OCR geometry, transform configuration, songs, variants, setlists,
   and device preferences. It has no Flutter, SQLite, archive, or platform code.
2. **Application** owns editing sessions, visual analysis coordination,
   transformations, Gig viewport rules, deterministic deck/PDF preparation, and
   portable-container workflows. It depends on contracts, not `LocalLibrary`.
3. **Infrastructure** owns SQLite, schema migration, content-addressed assets,
   archive/checksum validation, file pickers, local OCR adapters, and platform
   channels.
4. **Presentation** owns widgets, canvas painting, dialogs, navigation, busy
   states, and user-facing errors. It delegates persistent mutation and shared
   interaction rules to application sessions.

Canonical rule owners:

- `VisualChartDraft.displayTitle` / `displayArtist`: chart labels everywhere.
- `VisualDraftEditSession`: visual draft history, autosave, commit, and undo.
- `SetlistEditSession`: setlist entry replacement, ordering, timestamps, and
  persistence.
- `VisualAnalysisReviewSession`: multi-row analysis progress, retries, and
  failures.
- `GigViewportSession`: page movement, zoom overrides, alignment, theme,
  toolbar visibility, and stage lock.
- `CachedPerformanceDeckBuilder`: the one cached setlist-to-deck path used by
  Gig Mode, preview, and setlist PDF.

## Contracts

Application boundaries are grouped by responsibility:

- `library_contracts.dart`: chart, song-variant, setlist, bundle/state transfer,
  and `PortableLibraryStore`.
- `import_contracts.dart`: files, shared PDFs, and local text recognition.
- `export_contracts.dart`: chart PDF, setlist PDF, and performance decks.
- `platform_contracts.dart`: preferences, keep-awake/fullscreen, and URLs.

`PortableLibraryStore` is the only persistence boundary used by `.mtstate` and
`.mtsong` services. Those services do not inspect database or asset-directory
layouts.

## Persistence and migration

- SQLite schema v6 stores visual songs/variants, drafts, setlists, and asset
  references. The obsolete semantic table and variant-kind discriminator do
  not exist in v6.
- Before a v5 library is migrated, a checksummed, validated
  `pre-semantic-sunset-<timestamp>.mtstate` is written to a permanent retired
  backup area. Failure aborts startup before database modification.
- Semantic setlist references become same-position placeholders using their
  song title. Visual drafts, assets, visual songs, setlists, entry IDs,
  placeholders, and vector annotations are preserved.
- Assets are immutable and content-addressed by SHA-256.
- `.mtsong` and `.mtstate` schema v3 are visual-only ZIP containers with a
  manifest and checksums.
- Legacy schema-v2 containers are fully path/checksum validated before install.
  Visual content is installed; semantic IDs are reported as skipped; affected
  setlist entries become placeholders. Semantic-only song bundles import
  nothing and report no supported visual variant.
- State replacement validates in staging, creates a last-known-good backup,
  and installs atomically. Validation or cancellation never modifies the
  installed library.

## Visual processing and output

OCR and geometry are editable proposals, never verified music. Row detection,
crop, deskew, OCR, visual string routing, and bar repacking remain independent
algorithms with characterization tests. Structural refactors must not adjust
their thresholds or output as a side effect.

`VisualChartPdfExporter` renders one draft. `CachedPerformanceDeckBuilder`
creates the canonical performance deck. `SetlistPdfExportService` renders that
deck to A4. Screen and PDF retain deterministic layout inputs; provenance is
excluded from rendered output by construction.

Annotations are nondestructive vector overlays on visual strips. Visibility and
PDF inclusion are explicit stored choices.

## Platform and safety boundaries

- Windows is the first fully exercised target; shared Dart behavior remains
  Android-compatible. macOS is used for local development and smoke checks.
- No required cloud account, cloud processing, telemetry, or CDN assets.
- Imported archives never execute content. Paths, counts, sizes, and checksums
  are validated before extraction or installation.
- Source adapters must not bypass authentication, paid features, CAPTCHAs,
  rate limits, or access restrictions.
