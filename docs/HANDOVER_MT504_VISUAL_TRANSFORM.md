# MT-504–MT-506 visual-transform checkpoint

> Historical checkpoint: superseded by `HANDOVER.md`, `CURRENT_STATUS.md`, and
> the VT ledger after Apple validation and the Windows post-Apple regression.
> Counts and branch details below intentionally describe that earlier snapshot.

Last updated: 29 July 2026

## Stop point

- Branch: `codex/mt-504-visual-tab-analysis`
- MT-504–MT-506 and MT-601 are complete for the `v0.2.0-beta.1+2`
  pre-legal checkpoint.
- VT-012 wheel ownership and VT-014 Gig loading/cache behavior are fixed in
  source and passed Windows Computer Use. A physical-wheel confirmation remains
  part of final user acceptance.
- Normal development remains dev-script-only. Packaging is permitted for this
  checkpoint because the user explicitly requested Windows and Android
  artifacts.
- Flutter SDK: `C:\Codex\SDKs\flutter`
- Windows Computer Use test library:
  `C:\vibes\Music Tabbler\tmp\computer-use-library-20260728`
- Windows profile executable:
  `C:\vibes\Music Tabbler\build\windows\x64\runner\Profile\music_tabbler.exe`

## Implemented work present in the working tree

- Unified positioned-PDF and raster/OCR visual-tab analysis.
- Review UI for detected systems, strings, tokens, and seam-crossing notation.
- Visual all-string/selected-string pitch offsets.
- Four-to-five-string monotonic routing with one unused target string.
- Motion Sickness and Rock With You example presets.
- Reversible visual transforms with immutable base strips.
- Semantic string routing, capo, and selected-string pitch changes.
- Reversible visual deskew.
- Persistence and bundle/state round-trip support for the new visual data.

## Last verified automated baseline

Current source baseline:

- `flutter test --reporter compact`: 201/201 passed.
- `flutter analyze`: no issues.
- The focused raster diagnostic found eight Motion Sickness tab systems.

The tuning-label patch described below has **not** been tested yet. Therefore,
190/190 is not evidence for the current exact working tree.

## Completed Computer Use checks

### 9mm positioned PDF

- Positioned analysis detected the real tab.
- Applied an all-string `+1` visual transform.
- App reported 822 reviewed fret/dead-note tokens transformed.
- Visual spot checks confirmed `0 -> 1`, `12 -> 13`, and `X` unchanged.
- Toolbar Undo restored the original as one operation.
- Reapply, Save, close, reopen preserved the transform.
- Exported:
  `C:\vibes\Music Tabbler\output\9mm-plus1-validation.pdf`
- Rendered:
  `C:\vibes\Music Tabbler\tmp\rendered\9mm-plus1\page-1.png`
- The rendered A4 page was visually inspected: compact, unclipped, and headed
  with target tuning/capo/pitch metadata.

### Motion Sickness raster workflow

- Positioned text correctly fell back to Raster/OCR when fret data was
  insufficient.
- Raster review displayed eight systems and 70 enabled native/template-agreed
  fret/dead-note proposals. Low-confidence disagreements remained disabled.
- Selected preset:
  `Motion Sickness: DADG -> BEADG`.
- Confirmed:
  - source low-to-high `D A D G`;
  - target low-to-high `B E A D G`;
  - pitch change `0`;
  - capo `0`;
  - low `D -> B` at `+3`;
  - unused `E`.
- The insertion seam initially failed safely because a connected component was
  unresolved.
- In System 1, the relevant Gap 3 component was assigned to the lower string.
- Reapplying then completed successfully and produced five string lines.

## Defect found at the stop point

Computer Use showed that the transformed Motion Sickness row retained the
source tuning labels instead of presenting clean target labels
`G D A E B` from top to bottom.

A local, unverified patch was added to:

- `lib/application/visual_tab_transform_service.dart`
- `test/visual_tab_transform_service_test.dart`

The patch:

- relabels only the first transformed system in the whole chart;
- clears the old tuning-label gutter;
- draws the target labels in top-to-bottom order;
- adds a regression assertion that the transformed first-system gutter
  contains label ink.

Treat this patch as a candidate, not as verified work. Its formatting and
geometry must be checked before any further feature work.

## Exact resume sequence

1. Run formatting on the two files changed by the final patch.
2. Run the focused transform test:

   ```powershell
   & 'C:\Codex\SDKs\flutter\bin\flutter.bat' test test\visual_tab_transform_service_test.dart
   ```

3. If focused tests pass, run:

   ```powershell
   & 'C:\Codex\SDKs\flutter\bin\flutter.bat' test --reporter compact
   & 'C:\Codex\SDKs\flutter\bin\flutter.bat' analyze
   git diff --check
   ```

4. Rebuild the Windows development/profile executable. Do not package.
5. Reopen the isolated Computer Use library and reapply or edit the saved
   Motion Sickness transform.
6. Verify on the first transformed system:
   - exactly five string lines;
   - labels read `G D A E B` top-to-bottom;
   - the inserted `E` string is empty;
   - reviewed low-D notes appear on B with `+3`;
   - A, D, and G routes remain unchanged;
   - ties, beams, rests, and bar lines are not clipped or displaced.
7. Export Motion Sickness, render every page to PNG, and inspect it.
8. Validate the Rock With You preset:
   - source `D# G# C# F#`;
   - target `B E A D G`;
   - global pitch `-2`;
   - target capo `2`;
   - unused high G;
   - unchanged fret numbers.
9. Perform a real UI check of reversible deskew.
10. Rerun the final automated suite after any fixes.
11. Update `docs/ROADMAP.md` and `docs/CURRENT_STATUS.md` only from verified
    evidence.
12. Create the MacBook Air/macOS/iOS Simulator handover. Physical iPhone
    testing is unavailable and must not be claimed.
13. Stop for one combined user test. Do not enter `LG-001`–`LG-006`.

## Remaining cautions

- Raster/OCR output is reviewable assistance, not bulletproof transcription.
- Disabled or missed proposals must not silently change a fret.
- The apparent failure of injected `Ctrl+Z` during Computer Use may be an input
  injection artifact: toolbar Undo worked and the shortcut is covered in code.
  Recheck once, but do not redesign shortcut handling without reproducible
  evidence.
- Removing a saved transform through the UI is a local deletion and requires
  action-time confirmation under the Computer Use policy. Automated service
  coverage already exercises removal.
- Real user PDFs/screenshots remain external local fixtures and must not be
  committed.
- Pasted source links remain provenance-only. Automated provider acquisition
  remains legally gated.
