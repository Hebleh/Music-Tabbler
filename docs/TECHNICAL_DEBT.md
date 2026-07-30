# Technical debt

This file records accepted limitations that are intentionally deferred beyond the Windows MVP checkpoint.

## OCR metadata detection

- **Japanese title/artist detection remains unreliable on Windows.** The native OCR adapter can request installed Japanese recognition, but real score headings still fail to populate the editor metadata fields consistently.
- Keep title and artist manually editable and never treat OCR metadata as authoritative.
- A future fix needs a repeatable Japanese/Latin fixture set, confirmation that the Windows Japanese OCR capability is installed, per-engine result diagnostics, and explicit metadata accuracy tests.

## Split-row master crop

- **Master side-crop positions do not persist reliably through all split-dialog actions or reopenings.** The row crops themselves remain saved; the convenience master-control position is the deferred part.
- Do not infer the master position from saved row edges until mixed-width and individually adjusted rows have a defined behavior.
- A future fix should persist explicit per-source master-control state and add widget coverage for detect, evenly divide, add, delete, reopen, and cancel/apply flows.

## Unicode PDF headers

- **The current PDF title/artist widgets use the `pdf` package's built-in
  Helvetica fonts, which do not cover Japanese or general Unicode text.**
  Rasterized source notation remains unchanged, but a manually entered
  non-Latin title or artist may not render correctly in the compact PDF header.
- Do not add a remotely downloaded font or an unreviewed system-font dependency.
- A future fix should bundle a license-compatible Unicode font after the
  open-source dependency/asset audit, use it in both single-chart and setlist
  PDF headers, and add Latin/Japanese rendered-PDF fixtures.

## Visual transformation limitations

- Visual string insertion preserves and shifts pixels around the chosen seam,
  adds the new line, extends detected bar lines, and redraws reviewed frets.
  Connected-component detection is intentionally conservative: unusual marks
  crossing an internal seam may require a musician to choose whether the whole
  highlighted component moves with the upper or lower string region.
- Positioned-PDF visual analysis deliberately rejects notation staves that
  contain no reviewed fret/dead-note tokens. Sparse PDFs and screenshots fall
  back to local raster/OCR, whose missed or fragmented digits remain editable
  proposals.
- Visual deskew is limited to plus or minus seven degrees. It stores immutable
  pre-deskew crop/overlay geometry so Reset is exact; split and crop controls
  are disabled while deskew is active, requiring users to reset first before
  changing those boundaries.
- macOS/iOS feasibility cannot be concluded from the Windows checkout. MT-602
  requires an actual build and workflow run on the user's MacBook Air.

## Semantic recognition on real full-song charts

- **The current semantic proposal produced from the real `9mm` chart is not
  usable.** The visual chart remains the reliable source and must not be
  replaced, transposed, or marked gig-ready from that semantic result.
- Treat this as a recognition and review-pipeline limitation, not evidence that
  the source PDF or the manual visual workflow is invalid.
- A future fix must begin with a read-only Computer Use comparison across every
  saved Song Pool example and the known local PDF/screenshot fixtures. Record
  whether each failure comes from row/system detection, token recognition,
  string assignment, beat placement, measure-number filtering, or semantic
  rendering before changing code.
- The acceptance target is a separately selectable, source-aligned proposal for
  every playable fret/dead note, with uncertainty left visibly unverified.
  Until then, visual transforms remain the supported route for real gig charts.

## Visual analysis review density

- **Visual tab analysis should display all detected tab rows together in one
  scrollable review surface.** Reviewing one row or a partial subset at a time
  makes full-song omissions and inconsistent string detection difficult to
  notice.
- The combined review must preserve usable zoom, selection, correction, and
  before/after visibility. It must not eagerly decode every full-resolution
  source image on the UI thread or reintroduce the long-chart scrolling stall.
- A future implementation should use stable row placeholders and bounded image
  caching while allowing the user to see the complete detected-row inventory,
  confidence, and unresolved ambiguities before applying a transform.

## Visual transform preset naming

- **Presets must describe reusable tuning/routing operations rather than song
  names.** The existing `Motion Sickness` and `Rock With You` labels are useful
  fixtures but are not appropriate product-facing preset names.
- Preferred descriptive labels and subtitles are:
  - `Drop-D 4-string -> BEADG 5-string`
    (`DADG -> BEADG`, unused E, low D routed to B at +3).
  - `Half-step-down 4-string -> BEADG 5-string`
    (`D#G#C#F# -> BEADG`, song pitch -2, target capo 2, unused high G).
- Fixture/song names may remain in tests and documentation only.

## Per-string tuning offset controls

- Replace free-form tuning entry as the primary path with one row per string:
  the base/open note, decrement button, signed integer semitone field, increment
  button, and the calculated final open note.
- Example: `E  [-]  -2  [+]  -> D`. Repeat independently for every source and
  target string, while retaining an Advanced path for arbitrary confirmed
  tunings and octaves.
- The derived note must update immediately, preserve explicit string order, and
  make the distinction between tuning change, global song transposition, target
  capo, and selected-string pitch change clear. No tuning may be silently
  inferred from a song-specific preset.
