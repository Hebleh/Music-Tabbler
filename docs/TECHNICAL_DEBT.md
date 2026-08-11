# Technical debt

Updated: 11 August 2026

This file lists accepted limitations in the active visual-first product. The
retired semantic subsystem is not technical debt and must not be restored.

## LocalLibrary transactional façade

Schema DDL and content-addressed asset handling are now extracted, and
`PortableLibraryStore` prevents application services from inspecting concrete
paths. `LocalLibrary` intentionally remains the single transactional SQL façade
for songs, variants, drafts, and setlists. Further repository splitting should
only happen if it reduces transaction coupling rather than multiplying stores.

## Large presentation files

The visual editor, analysis review, transform dialog, and Gig screen remain
large. Their coordination rules are moving into tested sessions; further
splitting should follow those boundaries. A mechanical widget/file shuffle
without stronger screenshot/golden coverage would move complexity rather than
reduce it. Windows goldens currently protect representative Gig viewport
composition, the open Gig setlist drawer, the unlocked Gig toolbar, analysis
waiting/failure cards, and the complete analysis review layout. The Gig setlist
drawer, stage surface, zoom controls, and command bar, plus the review canvas,
row list, toolbar, and inspector, are now isolated from route/session
coordination; each remaining extracted surface still needs its own
representative baseline.

The former monolithic widget regression entrypoint is now organized into
visual/import, setlist, and performance workflow parts with shared test support.
This is test-structure cleanup only; presentation extraction still requires the
surface-specific golden coverage described above.

## Unicode PDF headers

The `pdf` package's built-in Helvetica fonts do not cover Japanese or general
Unicode title/artist text. Rasterized source notation remains intact. A future
fix should bundle a reviewed, license-compatible Unicode font and add rendered
Latin/Japanese PDF fixtures; no remote runtime font dependency is acceptable.

## OCR metadata and visual proposals

Japanese title/artist detection remains unreliable on Windows. Keep metadata
manually editable and never authoritative. Visual OCR can still miss or fragment
digits, rests, and connected notation; review and draw/edit/delete controls are
the supported correction path. Accuracy work needs named fixtures and measured
manual corrections.

## Split-row controls and visual coverage

Master side-crop positions persist, but the mixed-width Detect/edit/reopen/reset
interaction matrix still needs a Windows device pass. Representative visual
goldens are also needed before aggressive presentation splitting.

## Platform validation

- Android shared-PDF import is implemented but native share-sheet/content-URI
  validation awaits a JDK and physical/emulated device.
- Physical Android tablet, stylus, keep-awake, rotation, and long-gig behavior
  remain hardware gates.
- macOS is a development/smoke target; signed/notarized distribution is outside
  ordinary iteration.

## Source and legal gates

Online source adapters and public distribution remain gated by source terms,
content rights, dependency licenses, and application licensing. User-initiated
local PDF sharing is ordinary file intake, but it does not grant rights to
redistribute the source material.
