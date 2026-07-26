# Combined Windows user test through Sprint 6

Use this as the single Windows test gate for the implemented roadmap through
MT-503. Android testing and building are intentionally deferred until the
Windows workflow has been corrected to the user's satisfaction.

Do not test state replacement against the only copy of an important library.
Export a `.mtstate` backup somewhere outside Music Tabbler before beginning.

## Launch and reporting

- Launch the current development version with `dev.bat`.
- For each failure, report the section/item, what you clicked, what happened,
  what you expected, and a screenshot or short recording where useful.
- Say whether the failure still happens after fully closing and reopening the
  app.

## A. Existing visual workflow regression

- [ ] Existing songs, crops, highlights, annotations, source details, and
  setlists are still present.
- [ ] Scroll to the bottom of the longest visual chart and wheel all the way
  back to Row 1 without sticking or jiggle.
- [ ] Open the chart highlighter, add and remove a freeform highlight, and
  confirm the editor and song PDF agree.
- [ ] Export a representative setlist with **Balanced** and **Stage-readable**.
  Neither export may report a minimum-row-height error.
- [ ] Every song occurrence starts on a new page in PDF, Performance preview,
  and Gig mode.
- [ ] Preview and Gig mode show no overflow stripes. Their back/exit controls
  work even if preparing a page fails.
- [ ] Gig annotations appear promptly, survive close/reopen, erase without a
  long hang, and can be cleared without clearing chart-editor highlights.

## B. Setlists, placeholders, and local source records

- [ ] A gig can contain duplicate songs and a light-red `Not playing`
  placeholder. Reordering persists after restart.
- [ ] Deleting a referenced Song Pool chart removes every selected reference
  and does not resurrect the chart after the gig is deleted.
- [ ] The gig sidebar lists songs and placeholders, jumps to an item, and
  supports reordering and placeholder editing.
- [ ] Pasting a URL creates an empty local chart plus editable provenance. It
  intentionally does **not** download the remote tab.
- [ ] Source details survive restart and never appear in exported PDFs.

## C. Portable data safety

- [ ] Export a song as `.mtsong` and import it into the same library. An
  identical import is retained as a separately named/identified variant.
- [ ] Export `.mtstate`, confirm it is non-empty, and keep that external backup.
- [ ] On a disposable library, cancel a replacement and import a corrupt file.
  Both leave the installed library unchanged.
- [ ] Replace with a valid state, restore its automatic backup, and confirm the
  prior songs and setlists return.

## D. Semantic editing and MusicXML

- [ ] Open a semantic chart. Add/edit/delete a note and rest, change beat and
  duration, undo, save, fully close, and reopen.
- [ ] Edit tuning/capo, a section, repeat/ending, technique, lyric alignment,
  and backing-vocal state. Save/reopen and confirm all remain.
- [ ] Toggle tablature and standard notation independently. Compare the screen
  with the semantic PDF; title visibility must not move the music.
- [ ] Export MusicXML, import that file as a new chart, and confirm supported
  notes, rhythm, tuning, lyrics, and repeats survive. Any unsupported content
  must be reported rather than silently claimed as preserved.

## E. 9mm recognition and urgent +1 test

Use these three files as one comparison set:

- Original source:
  `C:\Users\Gerri\OneDrive - Nanyang Technological University\Guitar shiet\9mm.pdf`
- Manually squeezed reference:
  `C:\Users\Gerri\OneDrive - Nanyang Technological University\Guitar shiet\9mm (squeezed).pdf`
- Existing Music Tabbler export, named only for differentiation:
  `C:\Users\Gerri\OneDrive\Desktop\10mm.pdf`

First test only a short, easy-to-check portion:

- [ ] Import `9mm.pdf` and split one combined notation-plus-tab system into a
  row without deleting the original source.
- [ ] Choose **Recognize semantic proposal**, **4-string EADG**, and
  **Notation above tablature**.
- [ ] Confirm ordinary frets and `X` dead notes appear as unverified proposals.
- [ ] Compare every proposed event against the source preview. Correct errors,
  reject false events, and verify only notes you have checked.
- [ ] Mark the checked sample gig-ready, choose **Transpose chart**, enter `+1`,
  and save the result as a separate variant.
- [ ] Confirm every sounding pitch is one semitone higher. In the common
  same-string case, each fret should be exactly one higher; rhythm, lyrics,
  sections, and the original chart must remain unchanged.
- [ ] Export the transposed sample PDF and compare it visually with the
  original measure.

Do not rely on a full-song +1 export until the short sample is correct and the
complete recognized chart has been manually verified. Report missed events,
wrong strings, wrong frets, duplicated events, or truncated rows with a
screenshot of the source and proposal.

## F. Re-tabbing and ranked alternatives

- [ ] From a verified four-string sample, choose **Adapt tuning / strings** and
  create a BEADG variant. Sounding pitches and rhythm must not change.
- [ ] Choose **Compare fingerings**. Alternatives must be distinct,
  deterministically ranked, and explained.
- [ ] Save two alternatives. Restart the app and confirm the original and both
  variants remain separate; editing one must not alter the others.
- [ ] If a note cannot be played in the requested tuning/range, the operation
  must fail clearly without saving a partial chart.

## Gate

Sprint 4 through Sprint 6 remain on the feature branch until this Windows pass
is reported and its defects are corrected. Do not build Android or package a
release at this gate.
