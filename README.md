# Music Tabbler

Music Tabbler is a local-first visual chart editor for turning user-supplied
tablature screenshots and PDFs into compact, stage-readable charts. Local OCR
is an editable aid; the supported source of truth remains the preserved visual
material.

The first implementation target is Windows. Android follows as a full peer application, with gig mode optimized for tablets and stylus annotation. A4 PDF remains a first-class output on every platform.

## Status

The project has a working Flutter application with a Windows-first visual-chart workflow and an Android target. See the current-status and handover documents before continuing development.

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

## Windows MVP release

The `v0.1.0` checkpoint is Windows x64 only. GitHub release assets include a single-file user-level installer and a portable ZIP containing the complete Flutter runtime. The installer places the app under Local AppData and adds a Start Menu shortcut; the portable ZIP can be extracted anywhere before running `music_tabbler.exe`.

The MVP binaries are unsigned, so Windows SmartScreen may show an unknown-publisher warning. Windows 10 or later and the current Microsoft Visual C++ Redistributable are required.

Repository visibility and open-source licensing are intentionally undecided until the third-party source, copyright, and dependency questions have been reviewed. No license is granted by this repository unless a license file is added later.
