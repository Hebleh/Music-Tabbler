# Music Tabbler documentation map

Updated: 13 August 2026

These documents describe the current visual-first product and its development
contracts.

## Read first

1. `HANDOVER.md` - current branch, verified checkpoint, and immediate next work.
2. `CURRENT_STATUS.md` - implemented product behavior and honest limitations.
3. `SPEC.md` - settled product decisions and user-facing requirements.
4. `../ARCHITECTURE.md` - technical boundaries and dependency direction.
5. `ROADMAP.md` - contract tracker and remaining validation gates.
6. `TECHNICAL_DEBT.md` - intentionally deferred limitations and design debt.

Physical Android and iOS checks remain hardware/signing gates. Do not infer
tablet, stylus, lifecycle, keep-awake, or share-sheet success from desktop and
widget tests alone.

## Maintenance rule

- Update `HANDOVER.md`, `CURRENT_STATUS.md`, `ROADMAP.md`, and technical debt
  together at each verified checkpoint.
- Keep checkpoint narratives in private development records rather than the
  public product documentation.
- Keep user-owned scores, screenshots, state files, and copyrighted material
  outside Git.
