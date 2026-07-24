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
