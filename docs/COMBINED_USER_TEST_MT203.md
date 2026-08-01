# Combined MT-107 through MT-203 user test

> Historical checkpoint checklist. Use `docs/README.md` and the open queue in
> `BUGS_MT504_VALIDATION.md` for current testing; retain this file for the exact
> MT-107-to-MT-203 acceptance steps.

Use this checklist for the single Windows and Samsung-tablet verification gate.
Do not test replacement or restore against the only copy of an important
library. Keep the exported Windows `.mtstate` somewhere outside Music Tabbler
before continuing.

## Test artifacts

- Windows development launch: `dev.bat`
- Windows debug executable:
  `build\windows\x64\runner\Debug\music_tabbler.exe`
- Android debug APK:
  `build\app\outputs\flutter-apk\app-debug.apk`
- APK SHA-256:
  `1D1842A646482712A8D31BB2892E7FC76AF989CFF15C25A82C4701AB027B274E`

## A. Windows baseline and setlist

- [ ] Launch with `dev.bat`. Existing songs and edits are still present.
- [ ] Open the real long chart, scroll to its final row, then wheel all the way
  back to Row 1. Report any sticking, jiggle, or large wheel delay.
- [ ] Open the chart highlighter. Confirm it opens without a Visual C++ error,
  existing highlights appear, and a new freeform highlight appears in both the
  editor preview and exported song PDF.
- [ ] Change the app theme and display preferences, fully close the app, reopen
  it, and confirm they persist.
- [ ] Create a test gig. Add at least three charts, add one chart twice, and add
  a named placeholder for a song you do not play.
- [ ] Confirm the placeholder is light red and says `Not playing`.
- [ ] Drag the songs and placeholder into a different order. Close and reopen
  the gig and confirm the exact order persists.
- [ ] Delete a Song Pool chart that is present in the test gig. Accept the
  explicit removal prompt, then confirm it disappears from both Song Pool and
  every occurrence in the gig.
- [ ] Delete the test gig, restart Music Tabbler, and confirm the deleted chart
  does not return.

## B. Windows PDF and performance views

- [ ] Recreate a representative gig with several real charts, a duplicate, and
  a placeholder.
- [ ] Export it once with **Balanced** and once with **Stage-readable**. Neither
  export should show the former minimum-row-height error.
- [ ] In each PDF, confirm exact setlist order, retained duplicate, light-red
  placeholder, no clipped notation or lyrics, no provenance URL, compact page
  usage, and one header per song occurrence.
- [ ] Open **Performance preview** and traverse every page forward and backward.
  Compare its order with the PDF and exit through its explicit control.
- [ ] Start **Gig mode** on Windows as a quick functional check. Open the setlist
  sidebar, jump to a song, reorder entries, add/edit/remove a placeholder, and
  confirm the main page follows the changed order.

## C. Local URL and `.mtsong`

- [ ] From **New / Import**, paste a specific tab URL. Confirm no content is
  downloaded and a local editable chart/source record is created.
- [ ] Open **Source details**, edit the provider/version/notes, copy the URL,
  and open it in the normal browser.
- [ ] Save, close, and reopen the chart. Confirm its source details persist and
  its exported PDF contains none of them.
- [ ] From Song Pool, export that song as `.mtsong`.
- [ ] Import the `.mtsong` into the same library. An identical import should
  create a separate, independently deletable chart identity without changing
  existing setlist references.
- [ ] Make an edit, export again, and import into the other device later.
  Confirm the divergent version is retained as a separate variant rather than
  overwriting the existing one.

## D. Safe Windows-to-Android transfer

- [ ] Use **Library transfer and recovery** to export the Windows library as
  `.mtstate`. Keep this file outside the app and confirm it is not zero bytes.
- [ ] Install the debug APK on the Samsung tablet. A fresh install should start
  with the gig display using light content on black.
- [ ] On the tablet, choose **Replace from .mtstate** and select the Windows
  export. Verify the songs, setlists, placeholders, source details, highlights,
  and annotations expected from Windows.
- [ ] Make a small disposable change on Android. Export an Android `.mtstate`.
- [ ] On Windows, use **Import and keep local library** with that Android state.
  Confirm local content remains and divergent imported content is added rather
  than silently replacing it.

## E. Replacement failure and recovery

Perform this section on the disposable Android copy, not the only important
Windows library.

- [ ] Replace the Android library with a different valid `.mtstate`. Confirm a
  recoverable backup appears under **Restore a backup**.
- [ ] Restore the prior backup and confirm the earlier songs/setlists return.
- [ ] Cancel a replacement from the file picker. Confirm nothing changes.
- [ ] Try importing an obviously invalid file renamed to `.mtstate`. Confirm an
  error appears and the installed library remains unchanged.
- [ ] Repeat enough valid replacements to create more than five backups.
  Confirm only the five newest are offered.

## F. Android visual workflow and gig mode

- [ ] Import one image and one multi-page PDF using Android pickers. Split/crop
  rows, add a highlight, save, close, reopen, and export a song PDF.
- [ ] Open a gig and start **Gig mode**. Confirm fullscreen presentation and
  that the display stays awake while gig mode is active.
- [ ] Swipe left/right and use previous/next buttons. Confirm the first/last
  page cannot accidentally leave the gig.
- [ ] Press Android Back. It should instruct you to use **Exit** rather than
  unexpectedly closing gig mode.
- [ ] Open the sidebar, jump to a song, reorder songs, and add/edit/remove a
  light-red placeholder.
- [ ] Exit gig mode. Confirm normal system bars/screen-sleep behavior returns.

## G. S Pen annotations

- [ ] Draw several strokes with the S Pen using light and heavy pressure.
- [ ] Rest a palm while drawing. It should not navigate pages or create an
  unexpected touch stroke.
- [ ] Use the inverted S Pen/eraser tip if available, the eraser tool, undo,
  hide/show, and **Include annotations in PDF**.
- [ ] Rotate the tablet, change pages, close/reopen the app, and confirm strokes
  remain aligned with the same tab row.
- [ ] Export once with PDF inclusion off and once on. Confirm annotations appear
  only in the enabled export and the underlying source image remains unchanged.

## Report format

For each failure, send:

1. Checklist section and item.
2. What you tapped or dragged.
3. What happened.
4. What you expected.
5. Screenshot or short screen recording where useful.
6. Whether it reproduces after fully closing and reopening the app.

Leave every roadmap contract at `[~]` until this checklist is completed and the
reported defects are fixed.
