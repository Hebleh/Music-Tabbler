# Music Tabbler

Music Tabbler is a local-first visual chart editor for turning user-supplied
tablature screenshots and PDFs into compact, stage-readable charts. Local OCR
is an editable aid; the supported source of truth remains the preserved visual
material.

It is designed and tested with both guitar and bass tablature in mind,
including different source and output string counts, tunings, and
instrument-specific layouts.

The application targets Windows, macOS, Android, and iOS. Gig Mode is
optimized for stage displays and stylus annotation, while deterministic A4 PDF
remains a first-class output.

## Status

The project has a working Flutter application with visual import, OCR review,
non-destructive tab transformation, setlists, PDF export, and Gig Mode.

- Product requirements: [`docs/SPEC.md`](docs/SPEC.md)
- Architecture: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Current status and next slice: [`docs/CURRENT_STATUS.md`](docs/CURRENT_STATUS.md)
- Current working-tree handover: [`docs/HANDOVER.md`](docs/HANDOVER.md)
- Agent guidance: [`AGENTS.md`](AGENTS.md)

## Development launch

From Command Prompt, PowerShell, or by double-clicking the file:

```bat
dev.bat
```

This runs the Windows app using `flutter run` with hot reload and does not create a release package. Useful variants:

```bat
dev.bat -Clean
dev.bat -Device <flutter-device-id>
dev.bat -Device windows --dart-define=NAME=VALUE
```

`dev.ps1` remains available for direct PowerShell use.

On macOS, double-click `dev.command` in Finder or run it from Terminal:

```zsh
./dev.command
```

It defaults to the macOS desktop target and accepts the equivalent development
options:

```zsh
./dev.command --clean
./dev.command --device <flutter-device-id>
./dev.command --device macos --dart-define=NAME=VALUE
```

Use `flutter devices` to find an Android device ID. Release builds and versioned packaging are intentionally separate and should only be run for an explicit release or milestone checkpoint.

## Releases

Release assets are published on GitHub when their target platform can be built
and verified. Android prerelease APKs may use development signing and are
labelled accordingly. Apple installation packages require a valid Apple
Developer signing identity and provisioning profile.

## License

Music Tabbler is available under the [MIT License](LICENSE). Third-party
components retain their own licenses.
