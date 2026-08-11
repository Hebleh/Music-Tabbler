# Music Tabbler architecture

## Direction

Use Flutter/Dart for the shared Windows and Android application, with iOS and macOS left technically viable. Flutter owns navigation, editing, custom chart rendering, gig mode, and pointer/stylus interaction. Windows is implemented and packaged first; Android is a full target, not a separate viewer codebase.

The active product path is visual import/OCR review/transform/Gig output. The
existing semantic core remains isolated and persistence-compatible while its UI
and runtime service wiring are sunset; no destructive schema removal is part of
that sunset.

## Layers

1. **Domain** - songs, variants, tracks, measures, events, lyrics, tunings, fingering candidates, setlists, provenance, annotations, validation, and migrations.
2. **Application** - import jobs, recognition review, transformations, layout requests, exports, state transfer, backup/restore, and conflict policy.
3. **Infrastructure** - SQLite repositories, content-addressed assets, archive/checksum handling, source adapters, OCR/OMR engine adapters, and platform file pickers.
4. **Presentation** - song pool, setlists, visual import/OCR review,
   backing-vocal highlighting, chart preview, and gig mode.

## Persistence and bundles

- SQLite stores indexed library/domain state.
- Imported PDFs/images and other binary assets are immutable content-addressed files referenced by SHA-256.
- Vector annotations and semantic chart data remain separate from source pixels.
- Use versioned JSON-compatible domain serialization internally; provide MusicXML import/export at the boundary.
- Reserve `.mtsong` for portable song bundles and `.mtstate` for full-library snapshots. Both are ZIP containers with a manifest and checksums, not opaque database copies.

State import is transactional:

1. copy the bundle to staging;
2. validate container, manifest, schema compatibility, checksums, and referenced assets;
3. migrate a staged copy if supported;
4. build and query the staged database/domain graph;
5. show the import/conflict summary;
6. create a last-known-good backup;
7. atomically install the accepted state;
8. retain five valid backups and expose restore.

No validation failure modifies installed state. Divergent song edits become variants. A whole-library conflict is never auto-merged.

## Key interfaces

### Source adapter

Accepts a normalized URL and returns source metadata plus zero or more user-authorized acquisition candidates. Adapters are domain-specific, independently disableable, and may return `manualImportRequired` without treating it as failure. Search supplies URLs to the same adapters; it is not a separate ingestion path.

### Recognition engine

Consumes normalized page/frame images and optional source hints. Returns a semantic proposal, element/measure confidence, structural diagnostics, and source-coordinate mappings. The engine cannot mark a result verified.

Desktop research may use Python tooling, but the interface and fixtures must not bind the product to a desktop-only runtime. A production recognition engine intended for full Android parity must use a mobile-compatible local runtime or a platform implementation with equivalent serialized results.

### Transformation engine

Operates only on semantic data. Pitch transposition and same-pitch re-tabbing are separate commands with reversible results. Fingering strategies return ranked candidates and diagnostics rather than mutating the active variant.

### Layout and renderer

Consumes semantic chart content plus an explicit layout profile and produces platform-independent layout primitives. Screen and PDF backends consume the same primitives. Source provenance is absent from the render input by construction.

The floating title/artist header is an overlay/safe-margin element; toggling it must not reflow measures. Dark/light screen theme is device-local. PDF theme is chosen per export.

## Recognition strategy

Build recognition around a fixture corpus and an interactive correction loop:

1. clean Songsterr screenshots with tab, rhythm, sections, and syllable-aligned lyrics;
2. exported PDFs and clean static images;
3. video-derived scrolling-tab frames, including overlap detection and deduplication.

Use geometry and music constraints as well as OCR: staff/string line detection, measure segmentation, temporal positions, tuning/pitch consistency, rhythm totals, repeat structure, and lyric baselines. Existing OMR may inform or seed standard-notation recognition, but tablature requires dedicated evaluation.

## Platform plan

- **Windows first:** complete editor foundation, local library, A4 export, fixtures, and recognition experiments.
- **Android next:** same domain/application packages and full UI capabilities, with layouts adapted for touch/tablet; add gig-mode hardening and S Pen validation.
- **iOS/macOS later:** keep shared packages portable, but do not claim support until built and tested on Apple hardware.

## Security, legal, and privacy boundary

- No required cloud services, accounts, telemetry, or remote inference.
- Never execute active content from imported archives or documents.
- Normalize and validate archive paths to prevent traversal; enforce size/count limits before extraction.
- Treat online source adapters as separately gated experiments. Anti-detection does not create permission.
- Do not bundle a browser binary or dependency whose redistribution terms are incompatible with the chosen application license.
