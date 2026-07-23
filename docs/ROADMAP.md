# Music Tabbler post-MVP roadmap

This is the master implementation tracker for Music Tabbler. Update it at every
contract merge and sprint checkpoint. Detailed product and architecture rules
remain in `docs/SPEC.md` and `ARCHITECTURE.md`.

## Status legend

- `[x]` merged into the current sprint or `master`
- `[~]` implementation or user verification in progress
- `[ ]` not started
- `[!]` legally or externally gated
- `[d]` intentionally deferred technical debt

## Working agreement

For each cycle:

1. Start from the updated sprint integration branch.
2. Implement one bounded contract without packaging a release.
3. Delegate only bounded inventories, boilerplate, and test matrices to local
   Qwen as described in `AGENTS.md`.
4. Run focused tests, the full relevant suite, `flutter analyze`, and
   `git diff --check`.
5. Continue automatically through implementation and automated debugging.
6. Stop only when user judgment or real-device/manual visual testing is needed.
7. Give the user a short, exact, non-programmer test checklist.
8. Fix reported defects and repeat the automated checks.
9. Commit and merge only after the contract's user-test gate passes.
10. Update this document before starting the next contract.

Do not build installers, package releases, or publish assets during ordinary
development cycles unless the user explicitly requests a release checkpoint.

## Branch structure

```text
mvp/v0.1.0                    Immutable historical MVP
master                        Stable integration branch
└── codex/sprint-<theme>      Current sprint integration branch
    └── codex/mt-###-<slug>   One independently mergeable contract
```

The MVP branch is archival. Feature branches merge into their sprint branch.
Only a verified sprint merges into `master`.

## Current checkpoint

- [x] Preserve `mvp/v0.1.0` at the MVP checkpoint.
- [x] Keep `master` as the stable integration branch.
- [x] Establish `codex/sprint-gig-ready`.
- [x] MT-101 Stage-density profiles.
- [x] MT-104 Versioned migrations and stable identities.
- [x] MT-106 Ordered setlist repository.
- [~] MT-107 Setlist editor UI.
  - [x] Create, rename, delete, open, reorder, duplicate, and remove entries.
  - [x] Automated narrow-layout and reference-safety coverage.
  - [~] Resolve referenced-chart deletion clearly and atomically.
  - [~] Add named, light-red non-playing placeholders.
  - [~] Extract the ordered list into a reusable setlist sidebar/panel for
    later gig-mode composition.
  - [ ] User verification and merge gate.
- [ ] MT-108 Combined setlist A4 export.
- [ ] MT-105 Persistent per-device preferences, if it does not endanger the
  gig-critical PDF path.

MT-102 master-crop persistence and MT-103 Japanese OCR diagnostics remain
documented debt unless they materially block gig preparation.

## Ordered contracts

### Sprint 1 — Gig-ready setlists and PDFs

- [x] **MT-101 — Stage-density profiles**
  - Named deterministic visual export profiles tested against real charts.
- [d] **MT-102 — Master crop persistence**
  - Retain split-dialog master sides across detection, editing, and reopen.
- [d] **MT-103 — OCR diagnostics and Japanese fixtures**
  - Report the local OCR engine/languages and measure Unicode extraction.
- [x] **MT-104 — Versioned migrations and stable identities**
  - Migration-tested song and chart-variant identities preserving MVP drafts.
- [ ] **MT-105 — Persistent per-device preferences**
  - Theme and display choices survive restart without entering transferable
    library state.
- [x] **MT-106 — Ordered setlist repository**
  - Persistent ordered references, stable entry IDs, duplicates, and safe
    deletion policy.
- [~] **MT-107 — Setlist editor UI**
  - Usable setlist management plus reusable ordered sidebar data/presentation.
- [ ] **MT-108 — Combined setlist A4 export**
  - One deterministic ordered PDF, retaining duplicates and song boundaries.

### Sprint 2 — Performance surfaces

- [ ] **MT-109 — Shared performance-page deck**
  - One page/song sequence shared by preview, gig mode, and PDF planning.
- [ ] **MT-110 — Desktop performance preview**
  - Full-screen Windows rehearsal of one chart or an entire set.
- [ ] **MT-111 — Android visual-workflow parity**
  - Physical-tablet import, edit, save, reopen, and export.
- [ ] **MT-112 — Gig navigation, fullscreen, and keep-awake**
  - Swipe navigation, safe previous/exit behavior, active-only keep-awake, and
    the reusable editable setlist sidebar.
- [ ] **MT-113 — Vector annotation core**
  - Reversible normalized strokes that never alter source pixels.
- [ ] **MT-114 — S Pen and tablet annotation hardening**
  - Stylus detection, palm behavior, pressure, orientation, and lifecycle QA.

### Sprint 3 — Local provenance and safe portability

- [ ] **MT-115 — Local provenance and pasted-link records**
  - Store and open a user-entered source URL without fetching it or printing it.
- [ ] **MT-201 — Secure portable-container core**
  - Versioned manifest, checksums, staging, limits, and path validation.
- [ ] **MT-202 — `.mtsong` bundles**
  - Round-trip one song and its variants, assets, provenance, and annotations.
- [ ] **MT-203 — `.mtstate`, backups, conflicts, and restore**
  - Transactional whole-library transfer with recoverable snapshots.

### Sprint 4 — Semantic foundation

- [ ] **MT-301 — Persist the semantic foundation**
  - Save and reopen current semantic notes, measures, tuning, and lyrics.
- [ ] **MT-302 — Rhythm and navigation schema**
  - Exact beats, voices, rests, tuplets, signatures, repeats, endings, sections.
- [ ] **MT-303 — Instrument, technique, lyric, and confidence schema**
  - Arbitrary tunings/string counts, techniques, lyric alignment, proposals.
- [ ] **MT-304 — Shared screen/PDF semantic renderer**
  - Platform-independent primitives consumed by both screen and PDF.
- [ ] **MT-305 — Persisted core note/rest editor**
  - Direct reversible string, fret, pitch, duration, rest, beat, and measure edits.
- [ ] **MT-306 — Structure, tuning, technique, and lyric editor**
  - Complete manual semantic editing and backing-vocal presentation controls.
- [ ] **MT-307 — MusicXML interchange boundary**
  - Documented supported subset with explicit loss diagnostics.

### Sprint 5 — Recognition and correction

- [ ] **MT-401 — Recognition corpus and metrics**
  - Rights-safe fixtures, annotations, confidence, and correction-cost baselines.
- [ ] **MT-402 — Tablature structure/fret proposal engine**
  - Editable systems, measures, strings, and fret proposals from local images.
- [ ] **MT-403 — Rhythm, technique, section, and lyric recognition**
  - Extend proposals while retaining uncertainty and source mappings.
- [ ] **MT-404 — Side-by-side correction and gig-ready verification**
  - Accept/edit/reject proposals without replacing verified work.

### Sprint 6 — Musical transformations

- [ ] **MT-501 — Pitch transposition**
  - Reversible sounding-pitch transformation preserving rhythm and lyrics.
- [ ] **MT-502 — Same-pitch re-tabbing**
  - Adapt tuning/string count while preserving sounding pitch.
- [ ] **MT-503 — Ranked fingerings and saved variants**
  - Explainable alternatives retained alongside the original.

### Sprint 7 — Polish and platform expansion

- [ ] **MT-601 — Reversible visual deskew**
  - Preview/apply/reset geometry without modifying original assets.
- [ ] **MT-602 — macOS/iOS feasibility checkpoint**
  - Evidence-based supported/deferred decision on actual Apple hardware.

## Legal and open-source boundary

The open-source core may store a user-entered URL as local provenance, open it
in the normal browser, attach manually imported files, and remain fully usable
offline. It must not silently fetch or reproduce remote content.

- [!] **LG-001 — Open-source and dependency-rights audit**
- [!] **LG-002 — Generic external-source adapter boundary**
- [!] **LG-003 — Songsterr provider module**
- [!] **LG-004 — Ultimate Guitar provider module**
- [!] **LG-005 — YouTube provider/frame acquisition**
- [!] **LG-006 — Search/scouring integrations**

Automated fetching, scraping, downloading, browser control, indexing, or video
frame acquisition stays outside normal feature sprints until the exact action
has passed the relevant terms, content-rights, dependency-license, security,
and human legal review. VPN use or a private repository does not remove those
requirements. The manual screenshot/PDF workflow must always remain available.

## Contract merge gate

Every contract must:

- deliver a usable vertical improvement;
- preserve existing libraries and immutable source assets;
- keep the manual screenshot/PDF workflow working;
- include focused automated coverage and regression checks;
- define cancellation, error, and data-safety behavior;
- pass its non-programmer manual verification;
- receive final primary-agent review;
- avoid unrelated future work and release packaging.

## Gig priority

Before the 16 August 2026 gig, prioritize reliable Windows-created, stage-readable
PDFs from user-supplied screenshots/PDFs, ordered setlists, and backing-vocal
highlights. Android parity, gig mode, annotations, semantic recognition,
transformations, portable state, online adapters, deskew, and Apple platforms
must not endanger that fallback and should normally remain post-gig work.
