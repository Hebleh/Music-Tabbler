# Music Tabbler product specification

## Purpose

Music Tabbler turns user-supplied PDF pages and images into compact,
stage-readable visual tablature charts. It is local-first and designed around a
musician who needs reliable A4 and tablet output more than speculative musical
interpretation.

The former semantic editor/recognition product is sunset. Visual content is the
supported source of truth. Legacy semantic payloads are archived or skipped
safely during migration and import; they are not active chart variants.

## Core workflow

1. Import PDF, PNG, JPEG, clipboard images, or an Android-shared PDF.
2. Keep originals as immutable content-addressed assets.
3. Detect, split, crop, reorder, and deskew rows nondestructively.
4. Review local raster/positioned-PDF OCR and correct tokens explicitly.
5. Apply reviewed visual string/fret transformation without changing source
   rows.
6. Save visual charts in the Song Pool and reference them from ordered setlists.
7. Export a single chart or combined setlist to deterministic A4 PDF, or open
   the same performance deck in Gig Mode.

Manual screenshot/PDF editing is always a supported fallback. Failed OCR, row
detection, or transformation must never prevent users from keeping and
exporting the visual source.

## Visual drafts and variants

A visual draft stores ordered strips plus nondestructive crop, deskew, treatment,
lyric-highlight, OCR-review, visual-transform, annotation, and export settings.
The original asset remains recoverable. Automatic recognition is an editable
proposal and is never silently treated as verified music.

Songs may have multiple visual variants. Setlists reference variant IDs and may
contain duplicates and named placeholders. Deleting a referenced chart requires
an explicit user choice; missing legacy references remain visible.

## OCR and visual transformation

- OCR may use positioned PDF text and/or local raster recognition.
- Review exposes detected systems, strings, bar lines, tokens, ambiguity, and
  connected-notation seam risks.
- Users can keep a tokenless row visually unchanged rather than losing it.
- Visual transformation keeps source and target tunings, string routing, fret
  offsets, capo, and selected-string adjustments explicit and reviewable.
- The supported transformation changes rendered visual rows; it does not claim
  a semantic reconstruction of rhythm, pitch, or notation.

Accuracy claims require a named fixture set, metric, threshold, and manual
correction count.

## Lyrics and annotations

Backing-vocal highlighting is a nondestructive visual overlay with adjustable
contrast. Extending a highlight to corresponding tab is geometric mapping, not
semantic note/lyric alignment.

Stylus, touch, and mouse performance annotations are vector overlays. They can
be undone or erased, hidden in Gig Mode, and independently included in PDF.
They never modify source pixels.

## PDF and Gig Mode

- A4 is the required PDF page size.
- One chart exporter handles visual drafts.
- One cached performance-deck builder is shared by preview, Gig Mode, and
  setlist export; the setlist PDF exporter renders that deck.
- Existing density, pagination, filename, annotation, and layout behavior is
  deterministic.
- Provenance is app-only and never appears in chart or PDF output.

Gig Mode provides:

- light-on-black initial theme, with a lockable theme control;
- persisted set-wide zoom and session-local per-song zoom;
- left/center/right bar alignment, left by default;
- reflowed individual bars that fill available rows and screens;
- tap-to-hide toolbar while unlocked;
- stage lock that freezes theme/alignment/annotation controls;
- swipe and explicit previous/next navigation;
- keep-awake/fullscreen integration;
- editable setlist drawer and vector annotation controls.

## Local state and recovery

- SQLite schema v6 is visual-only.
- Before semantic retirement migration, a permanent checksummed v2 backup is
  created and validated. Startup aborts without database changes if it fails.
- `.mtsong` and `.mtstate` schema v3 contain visual data only.
- Legacy schema-v2 containers are safely readable after full path/checksum
  validation: visual data imports, semantic variants are skipped and reported,
  and affected setlist entries become same-position placeholders.
- Replacement imports validate in staging, preserve a last-known-good backup,
  and install atomically.
- Device-local appearance preferences are not overwritten by library state.
- Corrupt, incomplete, unsupported, or cancelled imports leave installed data
  untouched.

## Provenance

Charts may retain file identity, title/artist/instrument labels, import date,
method, and notes inside the app. Provenance remains private to the library and
is never rendered into charts or PDFs.

## Acceptance principles

- Visual charts remain editable across save/reopen, export, state transfer, and
  schema migration.
- Failed processing/export/import preserves the last verified library.
- Visual behavior and defaults are shared across Windows and planned Android.
- OCR and transforms remain reviewable and reversible.
- No active runtime or persisted v6/v3 format contains semantic product data.
