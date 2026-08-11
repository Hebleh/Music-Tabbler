# Music Tabbler handover

Updated: 11 August 2026

Read `AGENTS.md`, `docs/CURRENT_STATUS.md`, `docs/SPEC.md`, and
`ARCHITECTURE.md` before changing the repository. Preserve the manual visual
workflow and never discard user work.

## Immediate state

- Windows workspace: `C:\vibes\Music Tabbler`
- macOS workspace: `/Users/guh/Vibes/Codex/Music Tabbler`
- Stable branch: `master` at visual-first checkpoint `17aace3`
- Active working branch: `refractor`
- Remote: private `Hebleh/Music-Tabbler`
- Remote default branch: unchanged
- Normal macOS launch: `./dev.command`
- Normal Windows launch: `dev.bat`
- Do not create release builds or packages without an explicit release request.

The user's `music-tabbler-library.mtstate` is deliberately untracked. Its
protected checksum at refactor start is:

```text
e8c6b9d5d7d112b0cd3688a6173bb810535a48b28c860dab49b9f41978332cc9
```

`docs/.Rhistory` is unrelated user data and must remain untouched/uncommitted.

## Refactor outcome

The active app remains behavior-compatible and visual-first. The only intended
product removal is the sunset semantic subsystem.

- Library v6 performs a backup-gated semantic retirement migration.
- Portable `.mtstate` / `.mtsong` schema v3 is visual-only and safely reads
  legacy v2 archives.
- Semantic product/domain/runtime files and dedicated tests are removed.
- Portable services depend on `PortableLibraryStore`, not `LocalLibrary` paths.
- Application contracts are grouped into library/import/export/platform files.
- Display labels, visual draft editing, setlist editing, analysis review, and
  Gig viewport rules each have a canonical owner.
- Chart PDF, cached performance deck, and setlist PDF are separate services.

The migration tests explicitly cover mixed v5 data, semantic setlist references,
successful backup, backup failure without mutation, and idempotent reopen.
Legacy container tests cover mixed and semantic-only imports plus malformed
payloads that never modify installed state.

Final automated gate: 231/231 active tests pass, strict `flutter analyze` is
clean, and line coverage is 71.1% (7,115 of 10,014 lines). Representative
single-chart portrait A4 and four-page setlist landscape A4 PDFs were rendered
through Poppler and visually inspected. The macOS debug app built, started to a
live Dart VM service, and exited cleanly; automation could not foreground its
window (`open` returned 1). The protected `.mtstate` checksum remained exact.

## Rules for follow-up work

- Do not restore `SongChart`, semantic tables, MusicXML, or semantic feature
  branches. Legacy readers may only archive/skip opaque payloads.
- Do not tune OCR, row detection, transform, image-processing, bar-repacking,
  or PDF layout while doing structural cleanup.
- Extend behavior-level tests before moving behavior-sensitive code.
- Keep presentation responsibilities (canvas/dialogs/navigation) separate from
  application sessions.
- Application services must not import infrastructure implementations.
- Run focused tests after each extraction, then one complete suite and strict
  analysis at the final gate.

## Verification commands

```zsh
git status --short
git diff --check
flutter analyze
flutter test --reporter compact
shasum -a 256 music-tabbler-library.mtstate
./dev.command
```

Use the development launcher only for smoke testing; do not package a release.

## Deliberately deferred

- Native Android shared-PDF verification awaits an available JDK/device.
- Analysis canvas rendering is split from review coordination. Windows goldens
  now protect representative Gig viewport composition and analysis
  waiting/failure cards. Extend the relevant visual baseline before each
  remaining presentation extraction; avoid a mechanical shuffle that only
  relocates complexity.
- Gig annotation persistence, deck patching, and one-step undo now live in
  `GigAnnotationSession`; stroke capture and dialogs remain presentation work.
- The canonical cached performance-deck builder exposes local cache diagnostics
  for hits, misses, evictions, failures, pending work, retained deck structure,
  and estimated image bytes. Its three-entry LRU policy and output are
  unchanged.
- `LocalLibrary` remains the atomic SQL façade while ordered schema migration
  and content-addressed asset handling live in focused infrastructure helpers.

Historical Apple, Windows, release, and fixture validation documents remain in
`docs/` as archived evidence. Their semantic-era statements describe those
historical checkpoints, not the current product architecture.
