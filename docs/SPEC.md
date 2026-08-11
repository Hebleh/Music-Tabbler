# Music Tabbler product specification

## 1. Purpose

Music Tabbler turns heterogeneous music material into compact, stage-readable visual charts. The primary user is initially a bassist who needs to glance at a tablet or printed A4 page while playing and occasionally singing backing vocals. Visual PDF/image intake, local OCR review, nondestructive transforms, and deterministic Gig/PDF output are the active product path. The earlier semantic editor and recognition product path is sunset; its stored data remains backward-compatible rather than being deleted during migration.

The gig target informing the first iteration is 16 August 2026. The first dependable outcome is a Windows workflow that produces usable A4 charts; Android follows as a full-function peer application, not a reduced viewer.

## 2. Core workflow

The home experience has three first-class areas:

1. **Song Pool** browses processed songs, chart variants, tunings, lyrics, annotations, and source history.
2. **Gigs / Setlists** references songs from the pool in a user-defined order. The same song may appear more than once without copying its underlying chart.
3. **New / Import** accepts local files, clipboard images, a chosen source URL, or secondary search/discovery.

Source intake priority is:

1. Paste a specific Songsterr, Ultimate Guitar, YouTube, or future supported URL that the user already selected.
2. Run the matching source adapter and record the source identity and revision.
3. If automated acquisition or conversion is unavailable, accept screenshots/files while retaining the URL as provenance.
4. Use search/scouring only when the user has not selected a version.

Unsupported or failed links must fall back safely to PDF/image/manual import; they must never block chart creation.

## 3. Semantic chart model

A durable chart stores musical meaning rather than only pixels:

- parts/tracks, measures, beats, voices, tempo and time signatures;
- notes, rests, pitches, durations, ties and tuplets;
- tablature string/fret positions and techniques such as slides, bends, hammer-ons, pull-offs, harmonics, dead notes, and chords;
- per-string tuning with pitch and octave, capo where relevant, and arbitrary string counts;
- repeat barlines, repeat counts, endings, section names, navigation cues, and compact section references;
- editable lyric syllables anchored to beats or note events;
- verification/confidence state for recognized elements;
- nondestructive visual blocks and annotation layers when material has not yet been converted.

MusicXML is an interchange format, not the complete project format. The project also stores source records, chart variants, setlists, display choices, and annotations.

The editor permits direct semantic editing: selecting a string and beat position, entering or changing the fret, choosing a duration, and editing techniques, rests, measures, lyrics, and repeats. Tablature and standard notation can be toggled independently.

## 4. Import and recognition

### Reliable baseline

- Import PDF, PNG, JPEG, and clipboard screenshots.
- Crop, reorder, deskew where feasible, and arrange visual regions.
- Preserve original assets and make visual edits nondestructive.
- Export a useful chart even when semantic conversion is incomplete.

### Semantic recognition goal

OCR/OMR converts an entire source into semantic blocks. Clean Songsterr screenshots are the first accuracy target; exported PDFs and generic images are next; YouTube scrolling-tab capture is designed as a later adapter.

Recognition must:

- detect systems, strings/staves, measures, rhythm, rests, digits, techniques, sections, tunings, and lyrics;
- return confidence at element and measure level;
- flag uncertain or structurally inconsistent results;
- show source and reconstructed output together for correction;
- preserve verified work across re-runs and never silently overwrite it;
- mark a chart gig-ready only after explicit user verification.

"Bulletproof" means high-confidence, measurable, and fully correctable—not an unsupported claim of perfect automation.

## 5. Tuning, transposition, and variants

The default bass preset is five-string BEADG. Presets also include common four-string tuning, and every string is individually editable per song.

Two operations are distinct:

- **Transpose** changes sounding pitches by an interval, then computes playable tablature.
- **Re-tab / adapt tuning** preserves sounding pitches while finding strings and frets for a target tuning or string count.

Original and adapted variants are retained side by side. Re-tabbing generates ranked alternatives rather than silently replacing the original:

1. a feasible uniform-shift or shape-like candidate;
2. a candidate that preserves original string/fret shapes where possible;
3. a candidate minimizing hand movement and fret-span;
4. additional valid alternatives when materially different.

Lowest fret alone is not an optimization goal. Every candidate must preserve pitch and rhythm, report unplayable events, and remain manually editable.

## 6. Lyrics and backing vocals

Full editable lyrics are aligned by syllable to beats or notes in the Songsterr style.

Backing-vocal edit mode lets the user:

- select the phrases or syllables they sing;
- apply a strong backing-vocal highlight;
- adjust the opacity/contrast of the remaining lead-vocal text;
- edit lyric spelling, syllable breaks, alignment, and timing;
- preview the result in normal and gig display modes.

Backing-vocal markings travel with the chart and state bundle.

## 7. Stage layout and PDF

The renderer reflows semantic measures and removes unused whitespace; it must not obtain compactness merely by shrinking below a readable size. Exact density, minimum type size, measure width, and page-break rules will be tuned against the user's examples and stage feedback.

- A4 is the required PDF page size.
- Screen and PDF use the same deterministic chart layout, subject to explicit screen/PDF theme choices.
- Tablature and standard notation are independently toggleable.
- Title and artist are independently toggleable and appear as a compact overlay/safe-margin header that does not cause tablature reflow.
- Source information is accessed through the app UI and is excluded from every PDF.
- Export supports a selected song PDF or an ordered combined setlist PDF.
- The user chooses dark or light output; display theme persists between sessions.

## 8. Gig mode and annotations

Gig mode is available on all platforms but optimized for an Android tablet:

- first-install default is light notation/text on black;
- theme and gig-view preferences persist locally on each device;
- a persisted whole-set zoom provides the default and a session-local
  per-song zoom can override it for an individual setlist entry;
- a plain chart tap hides or restores unlocked controls; stage lock prevents
  the tap from exposing controls;
- distraction-free full-screen chart with large touch targets;
- one swipe advances to the next page or, at the last page, the next song;
- an explicit control returns to the previous page/song and prevents accidental setlist exit;
- the device can be kept awake while gig mode is active;
- S Pen/stylus, touch, and mouse annotations are stored as vector overlays with undo and erasing;
- practice/stage annotations never alter the semantic music and may be toggled or excluded from PDF.

Android ultimately includes the full editor, import, transformation, library, export, and gig functionality available on Windows.

## 9. Local state and recovery

The app has no required cloud synchronization. Users transfer portable files through their preferred storage or cable workflow.

- A song bundle transfers one song, all variants, required assets, lyrics, provenance, and annotations.
- A state bundle transfers the entire library, setlists, and shared content.
- Device-local appearance and platform preferences are not overwritten by imported state.
- Every bundle has a schema version, application version, library/export identity, lineage revision, asset manifest, and SHA-256 checksums.
- Import validates into staging before changing installed data.
- Before a valid replacement, the app creates a recoverable snapshot and retains at least five last-known-good backups.
- Corrupt, incomplete, unsupported, or cancelled imports leave the installed library untouched.
- Divergent song edits are kept as separate named variants; semantic charts are never auto-merged.
- Whole-library conflicts offer cancel, retain current and import as another library, or replace after backup. There is no destructive silent merge.

## 10. Source provenance and distribution boundary

Each chart version may store source site, URL or file identity, source title/artist/instrument naming, contributor or revision identifier when visible, retrieval date, import method, and user notes. Provenance is app-only.

The manual/local workflow is always available. Direct URL import and search adapters are optional modules gated by technical feasibility, source terms, content rights, and dependency licenses. Private repository status or VPN usage does not by itself grant permission to acquire, transform, or redistribute content.

Repository visibility and application licensing remain undecided. Until reviewed, online adapters are experimental and must not bypass authentication, paid features, CAPTCHAs, rate limits, or access controls.

## 11. Acceptance principles

- A chart must remain editable after import, transformation, save/reload, state transfer, and migration.
- Re-rendering unchanged semantic data must produce stable layout and PDF output.
- A failed recognition, transformation, export, or state import must preserve the last verified chart/library.
- Every automatic musical change must be reviewable and reversible.
- Windows and Android must use the same persisted semantic meaning and produce equivalent chart content.
