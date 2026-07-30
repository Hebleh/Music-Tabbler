# Terra Light semantic-detection Computer Use round

This is a read-only validation pass for the current released-source checkpoint.
Terra Light is the tester and evidence recorder. Do not patch source code,
change recognition thresholds, bulk-verify proposals, overwrite a useful chart,
package a release, or contact online tab providers.

## Purpose

Determine where semantic detection fails across the user's real material before
Sol Medium changes the recognition pipeline. The manual visual screenshot/PDF
workflow is the safety baseline and must remain usable throughout.

## Start safely

1. Read, in order:
   - `docs/HANDOVER.md`
   - `AGENTS.md`
   - `docs/CURRENT_STATUS.md`
   - `docs/SPEC.md`
   - `ARCHITECTURE.md`
   - `docs/TECHNICAL_DEBT.md`
   - `docs/BUGS_MT504_VALIDATION.md`
   - this document
2. Use `C:\vibes\Music Tabbler`.
3. Launch current source with `dev.bat`, not the packaged beta.
4. Use copies of charts for recognition. Never replace or bulk-verify the
   user's useful visual originals.
5. Observe the app immediately before every Computer Use action.
6. Store screenshots under a local ignored validation folder. Do not commit the
   copyrighted source charts or rendered pages.
7. Record results under VT-015 in `docs/BUGS_MT504_VALIDATION.md`. Add a new
   stable VT ID only when the failure is materially different.

## Fixture inventory

First list every visible Song Pool entry and test each entry that has a visual
source. The known local examples include:

- `9mm.pdf`, `9mm (squeezed).pdf`, and the Music Tabbler `10mm.pdf` export;
- Thank You for the Venom / the existing 43-row Songsterr screenshot chart;
- Motion Sickness;
- Rock With You;
- Nothing's Gonna Change My Love for You;
- FLOW COLORS;
- When the Day Is Done;
- ABWY / Kitani;
- Hypotheticals;
- Dad / Drop D;
- Fiction / Sumika;
- Lemoyne;
- Scandal Baby / Scandol.

Some examples have PDF, screenshot, PowerPoint, Word, or Guitar Pro source
material. Only formats the app currently accepts are recognition inputs. For an
unsupported source, use an existing PDF/image derivative if available and
record the unsupported original format without converting it during this pass.

## Per-chart procedure

For every accepted PDF or image example:

1. Duplicate or create a disposable visual chart from the source.
2. Confirm the visual chart itself still displays correctly.
3. Run visual tab analysis and record:
   - source type: positioned PDF, raster PDF, PNG, or JPEG;
   - detected tab-system and row count versus visible source count;
   - detected string count and any tuning suggestion;
   - whether all rows can be reviewed or only a partial/current row;
   - missed, duplicated, or fragmented fret/dead-note tokens;
   - measure numbers or headings mistaken for frets;
   - confidence and fallback path.
4. Start `Recognize semantic proposal`.
5. Do not use `Verify all`. Inspect representative proposals from the first,
   middle, and final detected systems.
6. For each representative system, record:
   - separate selectable notes versus concatenated digits;
   - correct source string;
   - horizontal/beat alignment;
   - measure assignment;
   - source-comparison image availability;
   - rests, ties, techniques, lyrics, and section labels;
   - missing or obviously invented events.
7. Toggle tab and notation independently. Record rendering problems separately
   from detection problems.
8. Save, close, and reopen only the disposable proposal. Confirm the proposal
   state and source mapping survive.
9. Cancel or delete the disposable semantic copy. Confirm the original visual
   chart remains unchanged.

## Required focused comparisons

### 9mm

- Treat the user's report that semantic detection is not working as reproduced
  only after observing it in the current development build.
- Compare `9mm.pdf`, the manually squeezed PDF, the Music Tabbler export, and
  one screenshot-rendered form.
- Count visible source rows and detected semantic systems.
- Capture the first clear divergence between source and proposal.
- Classify the primary failure as row/system detection, token OCR, string
  assignment, beat placement, measure-number filtering, or renderer layout.
- Do not attempt semantic `+1` transposition unless the short reviewed sample is
  musically trustworthy. The visual `+1` path remains the fallback.

### Thank You for the Venom

- Recheck the former concatenated `3132333435`/measure-label failure.
- Confirm far rows are included, proposals remain individually selectable, and
  selecting a proposal opens the corresponding source row.

### Motion Sickness

- Record semantic detection before any transform.
- In the transform UI, verify the operation is still functionally DADG to
  BEADG, but record the song-specific preset label as naming debt.

### Rock With You

- Record whether positioned-PDF analysis or raster fallback is used.
- Verify the functional configuration remains D#G#C#F# to BEADG, song pitch
  -2, target capo 2, and unused high G.
- Record the song-specific preset label and free-form tuning controls as UX
  debt, not recognition failures.

## Evidence table

For every chart, append one row to the VT-015 evidence table with:

| Chart/source | Input kind | Visible rows | Detected rows | Token quality | String/beat alignment | Review mapping | Save/reopen | Primary failure | Screenshot |
|---|---|---:|---:|---|---|---|---|---|---|

Use short factual descriptions. Do not infer musical correctness where the
source cannot be read confidently.

## Stop condition

Stop after:

- every visible Song Pool example with a supported visual source has one
  evidence row;
- all known local examples above are tested or explicitly marked unavailable /
  unsupported;
- `9mm` has a captured first divergence and primary failure classification;
- no source code was edited;
- the original visual charts were confirmed unchanged.

Report:

- charts tested, skipped, or blocked;
- the VT-015 evidence table;
- new VT IDs, if any;
- screenshot paths;
- which failure class should be investigated first by Sol Medium;
- a clear statement that Terra made no source patch.
