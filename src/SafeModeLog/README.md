# SafeModeLog

> Xem crash log và tìm tweak khiến máy vào Safe Mode.

SafeModeLog reads your device's crash reports and points at the tweak behind each crash. Crashes of SpringBoard (the ones that drop you into Safe Mode) are ranked first, so the tweak to remove is usually at the top of the list.

It's an app, not an injected tweak, so it still opens while the device is in Safe Mode, when every tweak is switched off.

- **Supports**: iOS 15.0 and later, rootless jailbreaks (Dopamine, palera1n, NekoJB)
- **Reads**: `/var/mobile/Library/Logs/CrashReporter` (and the newer `osanalytics/DiagnosticReports` folder when present)

## Install

Add the source in Sileo or Zebra, then install **SafeModeLog**:

[![Add to Sileo](https://img.shields.io/badge/Add%20to-Sileo-0A84FF?style=for-the-badge)](https://ductruongvu23.github.io/repo/#sileo)
[![Add to Zebra](https://img.shields.io/badge/Add%20to-Zebra-111111?style=for-the-badge)](https://ductruongvu23.github.io/repo/#zebra)

Or add `https://ductruongvu23.github.io/repo/` as a source by hand.

## Usage

### Stuck in Safe Mode

1. Open **SafeModeLog** from the home screen.
2. Look at the top of **Suspects**. Red entries crashed SpringBoard or backboardd, which is what triggers Safe Mode.
3. Uninstall or update that tweak in Sileo / Zebra, then respring.
4. Still landing in Safe Mode? Pull down to refresh and check the next suspect.

### The screens

| Screen | What it shows |
| --- | --- |
| Suspects | Each blamed tweak with its crash count, which processes it crashed and when it last happened. Tap one to see only its crashes. |
| Crash logs | Every crash report, newest first, with its suspect. |
| Crash detail | Exception, reason, the suspect, every piece of jailbreak code in the stack, and the backtraces with tweak frames marked `▶`. The share button sends the full original `.ips` (what tweak developers ask for). |

### How a suspect is chosen

For each crash, SafeModeLog walks the stack from the crash point down and picks the first **tweak code** it finds: an injected dylib (`TweakInject` / `DynamicLibraries`) or a tweak's Settings pane (`PreferenceBundles`).

- For an uncaught exception, it looks where the exception was thrown (`lastExceptionBacktrace`) before the crashed thread, because the crashed thread then only shows `abort()`.
- Hooking plumbing that sits in every tweak's stack (ElleKit, Substrate, libhooker, the loader) is never blamed.
- If only a shared library (Cephei, AltList…) is on the stack, it is blamed and marked **(library)**: often a tweak using it is at fault.

A suspect is usually the cause, not always: a harmless tweak that hooks a busy method can appear in someone else's crash. Check the detail screen and how often each name shows up.

## Build

This package is built by the [repo](../../)'s CI. A push that changes `src/SafeModeLog/`:
1. runs the parser tests on macOS (`tests/CrashLogTests.m`),
2. builds the rootless `.deb` with Theos on Linux,
3. commits it into `debs/` and republishes the source.

Bump `Version:` in `control` to ship an update to people who already installed it.

Local build: [Theos](https://theos.dev/docs/installation) with iPhoneOS16.5.sdk, then:

```bash
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

Run the tests on a Mac:

```bash
clang -fobjc-arc -framework Foundation CrashLog.m tests/CrashLogTests.m -o tests/run && tests/run
```

## Project layout

```
SafeModeLog/
├── CrashLog.h/.m          # .ips parsing, blame logic, suspect ranking (Foundation only)
├── main.m                 # app: suspects + crash list, detail screen
├── tests/CrashLogTests.m  # parser tests, run in CI on macOS
├── entitlements.plist     # no-sandbox, to read crash logs
├── Resources/             # Info.plist, app icons
├── layout/DEBIAN/         # postinst / prerm: register the home screen icon
├── Makefile
└── control
```

## License

MIT.
