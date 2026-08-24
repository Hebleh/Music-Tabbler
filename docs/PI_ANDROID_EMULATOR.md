# Pi/Qwen guide: Android emulator and tab-corpus handoff

This document describes the Music Tabbler Android test environment and the
evidence Pi/Qwen must provide when it is asked to procure a broader tab corpus.
It is an operational reference, not permission to broaden a delegated task.

## Current responsibility boundary

- Pi/Qwen may procure, inventory, and classify **rights-safe tab fixtures** when
  Codex explicitly delegates that bounded task.
- Codex owns emulator interaction, visual inspection, musical correctness,
  transformation judgment, bug fixes, release scope, and final verification.
- Pi/Qwen must not use, automate, reinstall, redistribute, or extract content
  from the modified Songsterr APK. The APK parked under
  `C:\vibes\AndroidTestApps` is outside the rights-safe corpus workflow.
- Pasted Songsterr links remain provenance-only. A local PDF that the user has
  manually exported may be tested, but it must not be committed or
  redistributed unless its rights are documented.
- Public regression fixtures should be synthetic, self-authored, or obtained
  from a source whose license permits the intended use.

## Installed emulator

| Item | Current value |
|---|---|
| AVD name | `MusicTabbler_API35` |
| AVD home | `C:\vibes\AndroidEmulators` |
| AVD data | `C:\vibes\AndroidEmulators\MusicTabbler_API35.avd` |
| Device profile | Pixel Tablet, 2560 x 1600, 320 dpi |
| Android API | 35 |
| ABI | `x86_64` |
| Android SDK | `C:\Users\Gerri\AppData\Local\Android\Sdk` |
| ADB | `C:\Users\Gerri\AppData\Local\Android\Sdk\platform-tools\adb.exe` |
| Emulator | `C:\Users\Gerri\AppData\Local\Android\Sdk\emulator\emulator.exe` |
| Music Tabbler package | `com.gerri.music_tabbler` |
| Main activity | `com.gerri.music_tabbler/.MainActivity` |
| Evidence directory | `C:\vibes\AndroidEmulators` |

Do not assume the serial is always `emulator-5554`. Discover it with `adb
devices -l` on every run.

## Starting the AVD

Use the existing AVD. Do not create, reset, wipe, or reconfigure it.

```powershell
$sdk = 'C:\Users\Gerri\AppData\Local\Android\Sdk'
$env:ANDROID_AVD_HOME = 'C:\vibes\AndroidEmulators'

Start-Process `
  -FilePath "$sdk\emulator\emulator.exe" `
  -ArgumentList @(
    '-avd', 'MusicTabbler_API35',
    '-no-window',
    '-no-audio',
    '-gpu', 'swiftshader_indirect',
    '-no-snapshot-save'
  ) `
  -WindowStyle Hidden

& "$sdk\platform-tools\adb.exe" wait-for-device
& "$sdk\platform-tools\adb.exe" devices -l
```

Wait until this returns `1` before running a scenario:

```powershell
& "$sdk\platform-tools\adb.exe" -s <serial> shell getprop sys.boot_completed
```

If more than one Android device is connected, every command must include
`-s <serial>`.

## Safe read-only inspection

These commands establish the current state without changing app data:

```powershell
& "$sdk\platform-tools\adb.exe" -s <serial> shell wm size
& "$sdk\platform-tools\adb.exe" -s <serial> shell wm density
& "$sdk\platform-tools\adb.exe" -s <serial> shell dumpsys window | `
  Select-String 'mCurrentFocus|mFocusedApp'
& "$sdk\platform-tools\adb.exe" -s <serial> shell dumpsys package `
  com.gerri.music_tabbler | Select-String 'versionCode=|versionName='
```

For a non-visual UI snapshot, dump Android accessibility/UIAutomator XML:

```powershell
& "$sdk\platform-tools\adb.exe" -s <serial> shell uiautomator dump `
  /sdcard/window.xml
& "$sdk\platform-tools\adb.exe" -s <serial> pull `
  /sdcard/window.xml C:\vibes\AndroidEmulators\<run>-window.xml
```

UI XML is useful for control text, enabled state, selection state, and bounds.
It is not proof that a rendered tab, crop, tie, note, or PDF is visually or
musically correct.

## Screenshots and logs

Codex uses screenshots for visual review. Pi/Qwen may collect them only when a
delegated task explicitly asks for collection; a text-only model must not claim
that it visually inspected them.

```powershell
& "$sdk\platform-tools\adb.exe" -s <serial> shell screencap -p `
  /sdcard/music-tabbler-screen.png
& "$sdk\platform-tools\adb.exe" -s <serial> pull `
  /sdcard/music-tabbler-screen.png `
  C:\vibes\AndroidEmulators\<run>-screen.png

& "$sdk\platform-tools\adb.exe" -s <serial> logcat -d -v threadtime `
  Flutter:* AndroidRuntime:E ActivityTaskManager:W '*:S'
```

Before reproducing a failure, clear only the log buffer, not app data:

```powershell
& "$sdk\platform-tools\adb.exe" -s <serial> logcat -c
```

## Installing a development APK without losing the library

`adb install -r` replaces the package while preserving its app data. Confirm
the package name and version after installation.

```powershell
& "$sdk\platform-tools\adb.exe" -s <serial> install -r <apk-path>
& "$sdk\platform-tools\adb.exe" -s <serial> shell dumpsys package `
  com.gerri.music_tabbler | Select-String 'versionCode=|versionName='
```

Never use any of these without explicit user approval:

- `adb uninstall com.gerri.music_tabbler`
- `adb shell pm clear com.gerri.music_tabbler`
- emulator `-wipe-data`
- deleting or replacing the AVD directory

Those actions destroy the installed library, preferences, annotations, or
emulator state.

## Launching and stopping Music Tabbler

```powershell
& "$sdk\platform-tools\adb.exe" -s <serial> shell am force-stop `
  com.gerri.music_tabbler
& "$sdk\platform-tools\adb.exe" -s <serial> shell monkey `
  -p com.gerri.music_tabbler `
  -c android.intent.category.LAUNCHER 1
```

`force-stop` ends the running process but does not clear saved data. Stop the
AVD cleanly with:

```powershell
& "$sdk\platform-tools\adb.exe" -s <serial> emu kill
```

## Moving a test tab onto the emulator

Use a copied test artifact, never the only copy of a user's chart:

```powershell
& "$sdk\platform-tools\adb.exe" -s <serial> push `
  <local-pdf-or-image> /sdcard/Download/
```

Open Music Tabbler and select the file through **Add PDF** or **Add PNG/JPEG**.
The Android document picker is the supported import path. A share-intent test
must use a legitimate `content://` URI supplied by the source application; do
not invent a `file://` share URI.

## Pi/Qwen corpus-procurement contract

When Codex asks for a wider dataset, Pi/Qwen should return a manifest rather
than attempting the app workflow. Each entry must contain:

1. source project and exact URL;
2. exact upstream revision, release, or download date;
3. license file URL and the fixture's applicable license;
4. local temporary path;
5. SHA-256 hash;
6. file type and page/image dimensions where applicable;
7. musical/visual features covered;
8. whether the fixture may be committed, or is local-test-only;
9. any ambiguous provenance or redistribution risk.

The desired feature matrix includes:

- 4, 5, 6, 7, and 8 strings;
- an unused added string at the top, middle, and bottom;
- standard, Drop D, lowered, raised, and arbitrary confirmed tunings;
- global and selected-string pitch changes;
- capos;
- one- and two-digit frets, `0`, sustained `(n)`, and `X`;
- hammer-ons, pull-offs, slides, ties, bends, harmonics, rests, beams, and bars;
- opening and mid-song time-signature changes;
- light, dark, inverted, cropped, scaled, skewed, and noisy raster sources;
- positioned PDFs, raster PDFs, PNGs, and JPEGs.

Reject or flag any candidate that requires an account, bypasses a paid feature,
uses an unofficial modified client, lacks a traceable license, or would place a
copyrighted song tab in public Git history.

## Required handoff format

Pi/Qwen's final response should be concise and evidence-based:

```text
Corpus root: <temporary local path>
Upstream revisions: <source=commit/release pairs>
Fixture count: <count by type>
License result: <commit-safe / local-only / rejected counts>
Scenario gaps: <features still missing>
Manifest: <path>
Failure modes: <at least one plausible corpus or test blind spot>
```

Codex then independently verifies hashes and licenses, chooses the test subset,
runs the analyzers and transforms, inspects rendered output, and decides whether
any synthetic regression fixture belongs in the repository.

## Evidence naming

Use a unique run prefix such as `amano-beta9-20260823` and keep all transient
artifacts under `C:\vibes\AndroidEmulators` or the repository's ignored `tmp`
directory:

```text
<run>-environment.txt
<run>-window-01.xml
<run>-screen-01.png
<run>-logcat.txt
<run>-results.md
```

Never report a scenario as passed from command exit status alone. A transform
passes only after Codex confirms the expected notes, string routing, tuning,
capo, unchanged notation, crop boundaries, persistence, and exported result.
