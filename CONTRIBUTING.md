# Contributing to Music Tabbler

Thank you for helping improve Music Tabbler.

## Development setup

1. Install the current stable Flutter SDK and platform tooling for your target.
2. Run `flutter pub get`.
3. Run `flutter analyze` and `flutter test --reporter compact`.
4. Launch with `dev.bat` on Windows or `./dev.command` on macOS.

## Change expectations

- Keep the application local-first and preserve manual visual editing.
- Treat OCR and geometry detection as editable proposals.
- Never add user charts, screenshots, PDFs, libraries, or exported state files
  to the repository.
- Add a focused regression test for externally observable bug fixes.
- Keep platform-specific behavior behind the existing application contracts.
- Run the focused tests, full suite, and strict analysis before opening a pull
  request.

Bug reports are most useful when they include the platform, app version,
minimal reproduction steps, expected result, actual result, and a cropped
screenshot that contains no private material.
