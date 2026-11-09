<p align="center">
  <img src="docs/banner.jpg" alt="Plugin Baby — an audio plugin manager for macOS" width="100%">
</p>

# Plugin Baby

A local, personal macOS app for managing, auditioning, and organizing your audio
plugins. Built with SwiftUI + AppKit + AVFoundation. Everything stays on your Mac —
there is no account, no network, and no telemetry.

> The name is a nod to Muse's "Plug In Baby." The app's artwork and theme are original.

## What it does

**Catalog & search**
Scans both `~/Library/Audio/Plug-Ins` (User) and `/Library/Audio/Plug-Ins` (System)
for Audio Unit (`.component`), VST3, VST, and CLAP plugins — whether a plugin is a
bundle or a plain dylib. Shows name, manufacturer, format, **where** it lives
(User/System), version, architecture (Intel / Apple Silicon / Universal), code-sign
status, and size. Search and filter by format; reveal any plugin in Finder. The
catalog is **cached between launches** for an instant start, and offers to rescan when
the saved list is more than 30 days old.

**Audition**
Load a plugin and hear it, with a live spectrum and level meters:
- **Audio Unit effects** (`aufx`/`aumf`) process an audio sample — the bundled default,
  or one you choose — with an A/B **bypass** toggle; **instruments** (`aumu`) play a
  test MIDI note.
- **CLAP effects and instruments** host through a bundled C shim, with **live parameter
  sliders** the app builds from the plugin's own parameter list and writes on the audio
  thread while it plays.
- **Open editor** opens an Audio Unit's own interface in its own window. If a plugin
  provides no editor of its own, the app builds a **generic parameter editor** from the
  AU's parameter tree, so a plugin's controls are always reachable.

**Chains / presets**
Group plugins into named, ordered chains with notes, saved locally.

**Archive / restore / delete**
Move a plugin out of its plugins folder into a local archive (recoverable), restore it
to its original location, or send it to the **Trash**. Archive-first: nothing is
destroyed without a recoverable copy. Archiving or restoring a **System** (`/Library`)
plugin prompts for admin rights via the standard macOS dialog; the archived copy is
handed back to your user account so later restore/delete need no further prompt.

## Build & run

```bash
./build.sh
open build/PluginBaby.app
```

`build.sh` compiles the Swift sources directly with `swiftc` and assembles a `.app`
bundle. It deliberately does **not** use SwiftPM: the standalone Command Line Tools on
the development machine ship a broken SwiftPM manifest library (`swift build` fails to
link the manifest). `Package.swift` is kept for when full **Xcode** is installed — then
you can open the package, build/run from Xcode, and raise the deployment target to
macOS 15 (Sequoia), the intended minimum.

**Requirements:** Xcode Command Line Tools (`xcode-select --install`). Builds for the
Mac's native architecture.

## App icon

The icon is generated from code (no bundled image assets):

```bash
./make-icon.sh    # Tools/MakeIcon.swift -> Resources/AppIcon.icns
```

## Where your data lives

Plugin Baby stores everything under one folder, picking the first writable location
from this list (so it still works if `~/Library/Application Support` is misconfigured):

1. `~/Library/Application Support/Plugin Baby/`
2. `~/Library/Plugin Baby/`
3. `~/.plugin-baby/`

```
<data folder>/
  chains.json             your chains
  archive/                archived plugin bundles
  archive-manifest.json   record of what's archived + where to restore it
  plugins-cache.json      last good catalog scan (for an instant start)
  samples/                (reserved for saved audition samples)
```

## Project layout

> **New to the code?** Start with [`docs/CODE-TOUR.md`](docs/CODE-TOUR.md) — a
> guided, beginner-friendly walk through the source in reading order.

```
Sources/PluginBaby/
  PluginBabyApp.swift        app entry
  AppModel.swift             central state + operations
  Theme.swift                colors, wordmark, brand gradient
  Models/                    Plugin, PluginFormat, PluginDomain, Architecture,
                             Chain, ArchiveEntry
  Services/
    PluginScanner.swift        filesystem scan (User + System) + lipo/codesign metadata
    AuditionEngine.swift       AVAudioEngine host for AU effects & instruments + editor
    AudioComponentDescriptionReader.swift   classify AU effect vs instrument
    ArchiveManager.swift       move / restore / trash with a manifest
    PrivilegedFileOps.swift    admin-authorized moves for /Library plugins
    Persistence.swift          JSON storage with writable-location fallback
    Shell.swift                run lipo/codesign/xattr
  Views/                     Catalog, Chains, Audition, Archive, ContentView
Tools/MakeIcon.swift         generates the app icon
Verify/main.swift            headless end-to-end check (scan + archive round-trip + render)
Sources/CLAPBridge/          C shim + vendored CLAP headers for hosting CLAP plugins
DESIGN.md                    design doc and locked decisions
docs/CODE-TOUR.md            beginner's guided walk through the source
```

## Notes & limits

- Live auditioning covers **Audio Units** (effects and instruments) and **CLAP**
  (effects and instruments, with app-drawn parameter sliders) via a bundled C host
  shim — see `docs/CLAP-AUDITION.md`. CLAP is ABI-verified against a reference plugin
  but not yet tested against a commercial CLAP. VST3 hosting is still a later phase
  (`docs/VST3-AUDITION.md`).
- The app is **not sandboxed** (it must read and move files in the plugins folders), so
  it isn't an App Store candidate — fine for personal use. It is a plugin host, so it
  loads third-party plugin binaries (`dlopen`) by design.
- Universal binaries, code-sign status, and architecture are read with `lipo` and
  `codesign`.

## Roadmap

Done: catalog + search with a cached plugin list, chains, AU effect & instrument
audition, AU editor window with a generic parameter-tree fallback, CLAP effect &
instrument audition with live parameter sliders, live spectrum + level metering, AU
validation via `auval`, archive/restore/delete, System-domain support with
admin-authorized moves, original electric theme and icon.

Candidates next: VST3 hosting, crash-safe scanning, an on-screen keyboard for
instruments, favorites/tags/categories, and hosting a whole chain live.
