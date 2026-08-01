# Music Tabbler documentation map

Updated: 1 August 2026

Use this page to distinguish current source-of-truth documents from historical
checkpoint evidence. Historical documents are retained because their exact
tests, release hashes, and regression observations remain useful; they do not
override the active status below.

## Read first

1. `HANDOVER.md` - current branch, verified checkpoint, and immediate next work.
2. `CURRENT_STATUS.md` - implemented product behavior and honest limitations.
3. `SPEC.md` - settled product decisions and user-facing requirements.
4. `../ARCHITECTURE.md` - technical boundaries and dependency direction.
5. `ROADMAP.md` - contract tracker and remaining validation gates.
6. `TECHNICAL_DEBT.md` - intentionally deferred limitations and design debt.
7. `BUGS_MT504_VALIDATION.md` - stable VT issue ledger and active test queue.

## Active validation

- `BUGS_MT504_VALIDATION.md` is the canonical list of reproduced, repaired,
  deferred, and newly reported issues.
- `COMPUTER_USE_FULL_APP_ROUND.md` is the reusable desktop regression matrix.
  Its dated priority sections are checkpoint evidence; use the open VT entries
  and queue near the end of the bug ledger to choose the next run.
- Physical Android checks are the current hardware gate. Do not infer tablet,
  S Pen, lifecycle, or keep-awake success from desktop or widget tests.

## Historical checkpoint documents

- `HANDOVER_MT504_VISUAL_TRANSFORM.md` - MT-504-to-MT-601 implementation
  handover before the Apple and Windows follow-up passes.
- `COMPUTER_USE_SEMANTIC_DETECTION_ROUND.md` - original read-only semantic
  diagnosis matrix that produced VT-015 evidence.
- `COMBINED_USER_TEST_MT203.md` - MT-107-to-MT-203 test checkpoint.
- `COMBINED_USER_TEST_SPRINT6.md` - semantic/recognition/transformation test
  checkpoint through Sprint 6.
- `releases/` - immutable release notes and checks for those exact artifacts.
  Old test counts in release notes are intentionally not updated.

## Maintenance rule

- Update `HANDOVER.md`, `CURRENT_STATUS.md`, `ROADMAP.md`, technical debt, and
  the VT ledger together at each verified checkpoint.
- Record a new stable VT ID before patching a newly reproduced defect.
- Do not copy full historical narratives into every active document; link to
  the bug or release entry instead.
- Keep user-owned scores, screenshots, state files, and copyrighted material
  outside Git.
