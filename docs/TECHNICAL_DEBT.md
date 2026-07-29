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
