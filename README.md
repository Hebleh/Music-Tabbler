# Music Tabbler

Music Tabbler is a local-first visual tablature editor for turning
user-supplied PDF scores, screenshots, and images into compact charts that are
easier to read on stage.

It is made and tested with both **guitar and bass** in mind. The visual analysis
and transformation workflow supports different source and output string counts,
tunings, and layouts instead of assuming every chart is a six-string guitar or
a four-string bass.

Music Tabbler preserves the original visual material. OCR and geometry
detection help you work faster, but remain editable proposals: the app never
silently declares a detected fret, string, or row musically correct.

## Main aims

- Make dense tablature more readable on tablets, laptops, and printed A4 pages.
- Let guitarists and bassists adapt visual tabs between tunings and string
  counts without redrawing the source score by hand.
- Keep automated detection reviewable, reversible, and backed by the original
  imported material.
- Organize songs into reusable variants and ordered setlists.
- Provide a practical Gig Mode that prioritizes usable screen space and quick
  navigation on stage.
- Keep charts and processing local: no required account, cloud processing,
  telemetry, or network connection.

## Features

### Visual import and row preparation

- Import PDF, PNG, and JPEG files.
- Paste or import screenshots and clipboard images on supported desktop
  platforms.
- Receive a PDF through Android's system share flow (native device validation
  is still in progress).
- Detect tablature rows from full pages in one action.
- Split, crop, reorder, duplicate, delete, and deskew rows.
- Preserve immutable source assets while edits remain nondestructive.
- Undo edits and autosave visual drafts.

### Editable tablature analysis

- Analyze selectable PDF text and/or rasterized page content locally.
- Detect tab systems, string lines, bar lines, fret/dead-note tokens, and
  ambiguous connected notation.
- Estimate the source string count before analysis so an incorrect system guess
  is visible early.
- Analyze every row automatically when opening the review workflow.
- Review tokens directly over the source image.
- Draw a missing token, edit its fret and string, merge or separate proposals,
  hide false positives, and delete incorrect proposals.
- Keep a row visually unchanged when it cannot be analyzed reliably.

Recognition is deliberately presented as assistance, not verification. Results
will vary with score quality, typography, scan resolution, notation, and
instrument layout.

### Guitar and bass transformation

- Set independent source and target tunings.
- Work with variable string counts rather than fixed guitar/bass-only models.
- Add or remove strings above or below the current instrument layout.
- Route source strings to target strings explicitly.
- Apply fret offsets, capo changes, and selected-string adjustments.
- Use included guitar, bass, and extended-range tuning presets.
- Review the transformed visual result before replacing the active chart.
- Transform manually added tokens through the same canonical path as detected
  tokens.
- Retain the source rows so the transformation can be changed or removed.

The transformation operates on reviewed visual tablature. It does not attempt
to recreate or rewrite the score's complete rhythm or standard notation.

### Song Pool and setlists

- Save charts into a local Song Pool.
- Keep multiple visual variants of the same song.
- Create, rename, reorder, duplicate, and remove setlist entries.
- Add named placeholders for songs that are not ready yet.
- Keep missing references visible instead of silently dropping them.
- Export and import individual songs with `.mtsong` bundles.

### PDF export

- Export a chart to deterministic A4 PDF.
- Export an ordered setlist as one combined performance PDF.
- Choose per-strip display and PDF density.
- Include or exclude title, artist, and nondestructive annotations.
- Keep private source provenance out of rendered charts and PDFs.

### Gig Mode

- Build a performance deck from a song or setlist.
- Reflow individually detected bars to use available screen width.
- Set a persistent set-wide zoom and a separate per-song zoom.
- Align bars left, center, or right; left alignment is the default.
- Switch between light and dark stage themes.
- Tap the stage to hide or reveal the toolbar.
- Lock the stage layout and controls against accidental changes.
- Navigate with swipes or explicit previous/next controls.
- Keep the display awake and use fullscreen integration where supported.
- Draw nondestructive stylus, touch, or mouse annotations with undo and erase
  controls.
- Decide independently whether annotations are visible in Gig Mode or included
  in PDF output.

### Local library and recovery

- Store the working library locally in SQLite.
- Deduplicate imported assets with content-addressed storage.
- Export or import the full visual library with a checksummed `.mtstate`
  bundle.
- Validate archives in staging before replacing installed data.
- Retain a last-known-good backup and install valid state atomically.
- Leave the installed library untouched when an import is corrupt, incomplete,
  unsupported, or cancelled.

## Typical workflow

1. **Import the score.** Add a PDF, PNG, or JPEG from the Visual Chart Editor.
2. **Prepare the rows.** Use **Detect rows**, then inspect the generated strips.
   Crop, split, deskew, reorder, or keep full pages where needed.
3. **Open visual transformation.** Choose the transformation action from the
   editor and confirm the proposed source string count.
4. **Review the analysis.** Inspect each row's detected systems and tokens.
   Correct mistakes with draw, edit, merge, separate, visibility, and delete
   controls. Preserve difficult rows unchanged when appropriate.
5. **Choose the instrument mapping.** Set the source and target tunings, string
   counts, routing, capo, and fret changes. Preview before accepting.
6. **Save the chart.** Give the song and variant useful names in the Song Pool.
7. **Build a setlist.** Add chart variants and placeholders, then arrange the
   performance order.
8. **Perform or export.** Open Gig Mode for a reflowed stage view, or export the
   chart/setlist as A4 PDF.
9. **Back up the library.** Export an `.mtstate` file and store it somewhere
   separate from the device running Music Tabbler.

## Installation and platform status

| Platform | Current status |
| --- | --- |
| Android | A release-mode test APK is available from the latest prerelease. Physical-device acceptance testing remains ongoing. |
| Windows | Primary desktop target and extensively exercised during development. Build from source; a current public installer is not yet published. |
| macOS | Development and live-smoke target. Build from source; the current public release has no signed/notarized package. |
| iOS | The release target compiles, but no installable IPA is published because Apple signing and provisioning are not configured for the project. |

### Android test APK

Download the APK and checksum from the
[releases page](https://github.com/Hebleh/Music-Tabbler/releases).

1. Download `Music-Tabbler-...-Android-test.apk` on the Android device.
2. If prompted, allow that browser or file manager to install unknown apps.
3. Open the APK and confirm installation.
4. Keep a separate `.mtstate` backup before testing upgrades or state imports.

The current prerelease APK uses an Android **debug signing certificate**. It is
for direct testing, not a Play Store production build. A future build signed
with a different key may require uninstalling this test build first; back up
the library before doing so.

## Build and run from source

### Prerequisites

- A current stable Flutter SDK compatible with `pubspec.yaml`.
- Git.
- Platform tooling for the target you intend to run:
  - Visual Studio with Desktop development with C++ for Windows;
  - Xcode and CocoaPods for macOS/iOS;
  - JDK 17 and the Android SDK/NDK for Android.

Then clone and fetch dependencies:

```sh
git clone https://github.com/Hebleh/Music-Tabbler.git
cd Music-Tabbler
flutter pub get
flutter devices
```

### Windows development launch

From Command Prompt, PowerShell, or by double-clicking the launcher:

```bat
dev.bat
```

Useful variants:

```bat
dev.bat -Clean
dev.bat -Device windows
dev.bat -Device <flutter-device-id> --dart-define=NAME=VALUE
```

`dev.ps1` is the underlying PowerShell launcher.

### macOS development launch

Double-click `dev.command` in Finder or run:

```zsh
./dev.command
```

Useful variants:

```zsh
./dev.command --clean
./dev.command --device macos
./dev.command --device <flutter-device-id> --dart-define=NAME=VALUE
```

### Direct Flutter launch

For Android, iOS, or another configured target:

```sh
flutter run -d <flutter-device-id>
```

The development launchers run `flutter run` with hot reload. They do not create
release packages.

## Verification

Before submitting changes:

```sh
flutter analyze
flutter test --reporter compact
```

The current public checkpoint has:

- 249 passing automated tests;
- 5 explicitly skipped platform-gated tests;
- clean strict static analysis;
- behavior tests for import/editing, visual analysis, string-count-aware
  transformation, manual tokens, setlists, PDF layout, Gig Mode, annotations,
  portable state, and migration/recovery;
- representative Windows visual goldens and PDF layout checks;
- successful macOS smoke testing and unsigned iOS release compilation.

These checks do not replace physical-device validation or musician review.
Music Tabbler does not claim a universal OCR accuracy percentage.

## Privacy and data ownership

- No Music Tabbler account is required.
- Core processing and storage are local to the device.
- The app has no required cloud processing, telemetry, or CDN assets.
- Imported source material and library state remain under the user's control.
- Source provenance may be retained inside the local library but is excluded
  from rendered charts and exported PDFs.
- Users are responsible for the files they import and share.

## Known limitations

- OCR can miss or fragment fret numbers, rests, time signatures, slides,
  sustains, chords, and connected notation. Use the review controls and retain
  the original row when automation is uncertain.
- Japanese and general Unicode title/artist text may not render correctly in
  exported PDF headers until a reviewed Unicode font is bundled.
- Android share-sheet intake, stylus behavior, lifecycle, rotation, and long
  set performance still need broader physical-device coverage.
- iOS currently has no signed distributable package.
- Public Windows and signed/notarized macOS packages are not yet available for
  the current checkpoint.

See [current status](docs/CURRENT_STATUS.md), [technical debt](docs/TECHNICAL_DEBT.md),
and the [roadmap](docs/ROADMAP.md) for more detail.

## Project documentation

- [Product specification](docs/SPEC.md)
- [Architecture](ARCHITECTURE.md)
- [Current status](docs/CURRENT_STATUS.md)
- [Roadmap](docs/ROADMAP.md)
- [Technical debt](docs/TECHNICAL_DEBT.md)
- [Development handover](docs/HANDOVER.md)
- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Contributing

Issues and focused pull requests are welcome. Bug reports should include the
platform, app version, minimal reproduction steps, expected result, actual
result, and a cropped screenshot or synthetic fixture that contains no private
material.

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before changing behavior-sensitive
code. In particular, recognition must remain editable, state imports must never
discard the installed library on failure, and user-owned charts or state files
must not be committed to the repository.

Security-sensitive reports should follow [SECURITY.md](SECURITY.md).

## License

Music Tabbler is licensed under the [MIT License](LICENSE). Bundled and fetched
third-party components retain their respective licenses.
