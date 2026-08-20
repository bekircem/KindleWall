# Contributing

Bug reports are the most useful thing you can send. Feature work is welcome too, but open an
issue before writing much code — this is a small app with a deliberately narrow scope, and it
is kinder to say "not this one" before you have spent an evening on it.

## Reporting a bug

Use the [bug report form](https://github.com/bekircem/KindleWall/issues/new?template=bug_report.yml).
It asks for the app version, the macOS version, and how you installed it, because those three
answers decide whether a bug can be reproduced at all.

If the bug involves a particular highlight, include the entry from `My Clippings.txt`, between
its `==========` separators. Parsing bugs are nearly always about one specific entry — a title
in an unexpected shape, a locale that formats dates differently. Redact whatever you like; the
shape of the entry matters more than its words.

## Building

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project KindleWall.xcodeproj -scheme KindleWall -configuration Debug build
```

`project.yml` is the source of truth: `KindleWall.xcodeproj` is generated, so run
`xcodegen generate` after adding or removing a file, and never commit project edits made in
Xcode's UI.

## Tests

Two steps, on purpose. The single-step `xcodebuild test` does not stage the test bundle and
fails in a way that looks like a test failure but means the tests never ran:

```sh
xcodebuild -project KindleWall.xcodeproj -scheme KindleWall clean
xcodebuild build-for-testing -project KindleWall.xcodeproj -scheme KindleWall -destination 'platform=macOS,arch=arm64'
xcodebuild test-without-building -project KindleWall.xcodeproj -scheme KindleWall -destination 'platform=macOS,arch=arm64'
```

Always read the `Executed N tests` line before believing a result.

Compiler warnings appear in the **build** log, not the test log — `test-without-building`
recompiles nothing, so grepping its output for warnings always returns zero.

## What the code expects of you

- The app builds in **Swift 6 language mode** with `SWIFT_STRICT_CONCURRENCY: complete`.
  Isolation violations are compile errors, not warnings. Two `@unchecked`-style escape hatches
  exist and both carry a written justification at the declaration; a third needs one too.
- **Services are protocols.** View models take them by protocol so they can be tested without
  touching the disk, the network, or the user's desktop.
- **Constants live in `Utilities/Constants.swift`.** No magic strings or numbers.
- **UI strings are localized**, code and comments are English. User-facing text goes through
  the String Catalog; run `python3 scripts/sync-catalog.py --check` before opening a PR.
  Note that `String`-typed titles and the untaken branch of a ternary never reach the catalog
  on their own — those have shipped untranslated before.
- **Enum raw values that are stored in UserDefaults are storage keys.** Translating one
  silently resets that preference for everyone who had it set. `RotationMode`,
  `ScheduleInterval` and `WallpaperStyle` are pinned by tests for exactly this reason.

## Performance claims

Measured, not guessed, and never from a Debug build — `-Onone` timings mean nothing.
`scripts/soak-measure.sh` produces the numbers.
