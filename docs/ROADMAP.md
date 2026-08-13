# Music Tabbler roadmap

Updated: 13 August 2026

The supported product direction is visual-first. Historical semantic contracts
are archived in Git and release/validation documents; they are not future work.

## Completed foundation

- [x] Local visual PDF/image/clipboard import with immutable assets.
- [x] Row detection, split/crop/reorder/deskew, undo, and autosave.
- [x] Editable positioned-PDF/raster OCR review and seam-risk handling.
- [x] Nondestructive visual string/fret transformation and tuning presets.
- [x] Song Pool variants, ordered setlists, duplicates, and placeholders.
- [x] Single-chart and combined-setlist deterministic A4 PDF.
- [x] Shared cached performance deck, preview, and Gig Mode.
- [x] Gig bar reflow, alignment, two-level zoom, theme, toolbar hiding, stage
  lock, keep-awake, and vector annotation controls.
- [x] Checksummed `.mtsong` / `.mtstate` transfer with staged atomic install.
- [x] Android system-share PDF intake implementation (native validation
  deferred until hardware/tooling is available).

## Architecture refactor

- [x] Protect and push the verified visual baseline.
- [x] Add backup-gated library v6 semantic retirement migration.
- [x] Add visual-only portable schema v3 with safe legacy-v2 skipping.
- [x] Delete semantic domain, editor, recognition, transform, rendering,
  MusicXML, and dedicated tests.
- [x] Establish `PortableLibraryStore` and coherent contract files.
- [x] Canonicalize display labels and active edit/review/Gig sessions.
- [x] Separate chart PDF, cached deck, and setlist PDF services.
- [x] Complete final full-suite, static-analysis, checksum, PDF-render, and
  macOS smoke gate.

## Next three cleanup tasks

1. Split the largest presentation files by existing session boundaries. The
   first Windows Gig-viewport, analysis-placeholder, and full analysis-review
   goldens are now in place. The Gig setlist drawer has its own full-shell
   golden and is separated from route/session coordination; the Gig zoom
   stage surface, zoom controls, and command bar likewise share an
   unlocked-toolbar golden and have isolated widgets. The analysis canvas, row
   list, toolbar, and inspector are also separated; extend the relevant surface
   before each remaining extraction.
2. [x] Split the monolithic widget regression file by product workflow without
   weakening behavior-level assertions. Visual/import, setlist, and performance
   regressions now share one entrypoint and common test support through Dart
   parts.
3. [x] Add explicit cache/eviction diagnostics for very large performance
   decks while preserving the current canonical deck builder and output.

## Product validation

- [ ] Validate Android shared-PDF intake and full editing on physical hardware.
- [ ] Run musician review against representative full-song transformed charts.
- [ ] Add licensed Unicode PDF fonts and Latin/Japanese rendered fixtures.
- [ ] Re-run Windows stage-distance and stylus interaction checks after the
  next device-available checkpoint.

## Working agreement

Each change should extend the closest externally meaningful test, run focused
checks, then finish with the complete relevant suite and strict analysis. Do
not build release packages during normal iteration. OCR, row geometry, visual
transformation, and PDF layout changes require their own feature/bug workflow;
they must not be bundled into architectural cleanup.
