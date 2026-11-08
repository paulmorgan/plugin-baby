# Plugin Baby

A local, personal macOS app for managing your audio plugins. Phase 1.

## What it does (Phase 1)

- **Catalog & search** — scans `~/Library/Audio/Plug-Ins` for Audio Unit (`.component`),
  VST3, VST, and CLAP plugins; shows name, manufacturer, format, version, architecture,
  and size; search and filter by format.
- **Chains / presets** — group plugins into named, ordered chains; saved locally.
- **Audition** — play an audio sample through an **Audio Unit effect** and A/B it with a
  bypass toggle. (VST3/CLAP hosting is a later phase — see `DESIGN.md`.)
- **Archive / delete / restore** — move a plugin out of `~/Library` into a local archive
  (recoverable), restore it to its original location, or delete it to the **Trash**.
  Archive-first: nothing is destroyed without a recoverable copy.

Scope is the **user domain only** (`~/Library/Audio/Plug-Ins`); no admin rights needed.
System `/Library` plugins are a Phase 2 item.

## Build & run

```bash
./build.sh
open build/PluginBaby.app
```

`build.sh` compiles the Swift sources directly with `swiftc` and assembles a `.app`
bundle. It does **not** use SwiftPM, because the standalone Command Line Tools on this
machine ship a broken SwiftPM manifest library (`swift build` fails to link the
manifest). `Package.swift` is included for when full **Xcode** is installed — then you
can open the package and build/run from Xcode, and raise the deployment target to
macOS 15.

Requirements: the Xcode Command Line Tools (`xcode-select --install`). Builds for the
Mac's native architecture.

## Where your data lives

```
~/Library/Application Support/Plugin Baby/
  chains.json             your chains
  archive/                archived plugin bundles
  archive-manifest.json   record of what's archived + where to restore it
  samples/                (reserved for saved audition samples)
```

## Project layout

```
Sources/PluginBaby/
  PluginBabyApp.swift        app entry
  AppModel.swift             central state + operations
  Models/                    Plugin, PluginFormat, Architecture, Chain, ArchiveEntry
  Services/
    PluginScanner.swift      filesystem scan + lipo/codesign metadata
    AuditionEngine.swift      AVAudioEngine host for AU effects
    AudioComponentDescriptionReader.swift
    ArchiveManager.swift     move / restore / trash with a manifest
    Persistence.swift        JSON storage
    Shell.swift              run lipo/codesign/xattr
  Views/                     Catalog, Chains, Audition, Archive
```

## Notes & limits

- AU auditioning covers **effect** units (`aufx`/`aumf`). Instruments need a test-MIDI
  source (Phase 2).
- Auditioning uses classic v2 Audio Units loaded from `~/Library/Audio/Plug-Ins/Components`.
- The app is **not sandboxed** (it must read/move files in `~/Library`), so it can't go on
  the App Store — fine for personal use.
