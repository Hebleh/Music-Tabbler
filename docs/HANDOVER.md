# Music Tabbler handover

Updated: 13 August 2026

Read `AGENTS.md`, `CURRENT_STATUS.md`, `SPEC.md`, and `../ARCHITECTURE.md`
before changing the repository.

## Product state

Music Tabbler is a local-first, visual-first Flutter application. Its supported
workflow covers local PDF/image import, row preparation, editable OCR review,
non-destructive visual tab transformation, Song Pool and setlist management,
deterministic A4 export, and Gig Mode with annotations.

The persistence layer uses visual-only library schema v6 and portable schema
v3. Older containers are validated before their supported visual content is
installed. State replacement is staged, backed up, and atomic.

## Verification baseline

- 249 automated tests pass; 5 platform-gated tests are skipped.
- Strict `flutter analyze` is clean.
- Representative screen and PDF fixtures have been checked.
- macOS development launch has been smoke-tested.

## Development commands

```zsh
flutter pub get
flutter analyze
flutter test --reporter compact
./dev.command
```

On Windows, use `dev.bat` for a development launch.

## Change rules

- Preserve visual input and manual editing as reliable fallbacks.
- Keep recognition output editable and visibly unverified until accepted.
- Never modify user libraries or portable state files during tests.
- Keep source provenance out of rendered charts and PDFs.
- Add migration tests before changing persisted schemas or archive formats.
- Do not tune OCR, row detection, image processing, transformation, bar
  repacking, or PDF layout as a side effect of structural cleanup.
- Use focused tests while iterating, followed by the full suite and strict
  analysis before publishing changes.

## Remaining platform validation

- Validate Android shared-PDF intake, lifecycle, stylus, and keep-awake behavior
  on physical hardware.
- Validate iOS file sharing, lifecycle, and performance behavior on physical
  hardware with a signed development build.
- Add a reviewed Unicode PDF font and rendered multilingual fixtures.
