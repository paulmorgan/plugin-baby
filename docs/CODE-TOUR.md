# Code tour — start here

A guided walk through Plugin Baby's source, written for someone who has never
opened this repo (or much SwiftUI) before. Read it top to bottom once; after
that the per-file headers and `DESIGN.md` fill in the detail.

## 1. What the app is, in one paragraph

Plugin Baby scans the two folders where macOS keeps audio plugins, shows what
it finds, lets you **hear** a plugin on a sample, group plugins into **chains**,
and **archive / restore / delete** them safely. Everything is local — no
network, no account. It's a normal SwiftUI/AppKit Mac app plus one small piece
of C that lets it host CLAP plugins (see §5).

## 2. The mental model (read this before the code)

The whole app is three layers, and the folders match them one-to-one:

```
Models/     plain data        — "what a plugin IS"        (structs & enums, no logic)
Services/   the doers         — "how we scan/host/move"   (talk to the disk, audio, tools)
Views/      the screen        — "what you SEE"            (SwiftUI, no business logic)
```

One object ties them together: **`AppModel`**. It holds the lists the UI shows
(plugins, chains, archive) and the actions the UI triggers (rescan, archive,
validate…). Views read from `AppModel` and call its methods; `AppModel` calls
the Services; Services return Models. Data flows **up** (disk → Services →
AppModel → Views), actions flow **down** (a button → AppModel → a Service).

If you remember one thing: **AppModel is the hub. Start there.**

## 3. A reading path (≈8 files, in order)

1. **[`PluginBabyApp.swift`](../Sources/PluginBaby/PluginBabyApp.swift)** — the
   `@main` entry point. Four lines of substance: make one `AppModel`, show
   `ContentView`, load data on launch. This is where the app begins.
2. **[`Models/Plugin.swift`](../Sources/PluginBaby/Models/Plugin.swift)** — the
   central noun. Everything else describes, lists, or acts on a `Plugin`. The
   other Models (`PluginFormat`, `PluginDomain`, `Architecture`, …) are small
   enums it uses; skim them.
3. **[`AppModel.swift`](../Sources/PluginBaby/AppModel.swift)** — the hub from
   §2. Read it slowly. The `// MARK:` lines divide it into filtering, dashboard
   stats, validation, archive, and chains — each a few short methods.
4. **[`Views/ContentView.swift`](../Sources/PluginBaby/Views/ContentView.swift)**
   — the window shell: a sidebar listing the five sections, and a detail area
   that swaps in one screen per section. This is the map of the UI.
5. **[`Services/PluginScanner.swift`](../Sources/PluginBaby/Services/PluginScanner.swift)**
   — how the plugin list gets filled: walk the folders, read each bundle's
   metadata. The clearest Service to read first.
6. **[`Views/DashboardView.swift`](../Sources/PluginBaby/Views/DashboardView.swift)**
   — the home screen, and a good example of a View assembling small reusable
   pieces (`StatTile`, `PluginCard`, `DetailPanel`).
7. **[`Services/AuditionEngine.swift`](../Sources/PluginBaby/Services/AuditionEngine.swift)**
   — the most involved Service: it hosts an Audio Unit and plays audio through
   it. Skim on the first pass; come back when you care about sound.
8. **[`DESIGN.md`](../DESIGN.md)** — the "why": locked decisions and trade-offs.

That's the whole app in one sitting. Everything below is reference.

## 4. The folders, file by file

### `Models/` — the nouns (plain data, no behavior)
| File | What it is |
|---|---|
| `Plugin.swift` | One installed/archived plugin on disk. The central type. |
| `PluginFormat.swift` | AU / VST3 / VST / CLAP, and where macOS installs each. |
| `PluginDomain.swift` | User (`~/Library`) vs System (`/Library`, needs admin). |
| `Architecture.swift` | Intel / Apple Silicon / Universal. |
| `PluginHealth.swift` | A quick offline "is anything wrong?" read. |
| `ValidationStatus.swift` | Result of Apple's `auval` check on an AU. |
| `Chain.swift` | A named, ordered group of plugins. |
| `ArchiveEntry.swift` | A record of a plugin moved into the archive. |

### `Services/` — the doers (the only layer that touches disk/audio/tools)
| File | What it does |
|---|---|
| `PluginScanner.swift` | Scans the plugin folders → `[Plugin]`. |
| `AuditionEngine.swift` | Hosts an **Audio Unit** and plays sound through it. |
| `CLAPHost.swift` | Thin Swift wrapper over the C CLAP shim (see §5). |
| `CLAPAuditionBackend.swift` | Plays audio through a **CLAP** plugin. |
| `AudioComponentDescriptionReader.swift` | Classifies an AU: effect vs instrument. |
| `SpectrumAnalyzer.swift` | Turns audio into the spectrum bars you see. |
| `ValidationService.swift` | Runs `auval` (Apple's validator). |
| `ArchiveManager.swift` | Move / restore / trash a plugin, with a manifest. |
| `PrivilegedFileOps.swift` | Admin-authorized moves for System plugins. |
| `Persistence.swift` | Reads/writes the local JSON files. |
| `Shell.swift` | Runs a command-line tool (`lipo`, `codesign`, …). |

### `Views/` — the screen (SwiftUI; reads `AppModel`, holds no business logic)
**Screens** (one per sidebar section): `DashboardView`, `CatalogView`,
`ChainsView`, `AuditionView`, `ArchiveView`, tied together by `ContentView`.

**Reusable components** (small, self-contained, used by several screens):
| File | Component(s) |
|---|---|
| `StatTile.swift` | A labelled number tile for the dashboard. |
| `PluginCard.swift` | A plugin row + `FormatBadge` chip. |
| `DetailPanel.swift` | The right-hand "selected plugin" panel. |
| `Visualizers.swift` | `SpectrumView` — the neon audio bars. |
| `BrandLogo.swift` | The code-drawn plug mark + wordmark. |

### Elsewhere
- **`Theme.swift`** — all colors, the gradient, and the wordmark in one place.
  Change the look here, not scattered through the Views.
- **`Tools/MakeIcon.swift`** — generates the app icon from code.
- **`Verify/main.swift`** — a headless check (scan + archive round-trip +
  render) you can run without the UI; see `verify.sh`.

## 5. The one non-Swift piece: `Sources/CLAPBridge/`

CLAP plugins are a C API, so hosting them needs a little C. To keep that
complexity in one audited place:

- `include/clap/…` — the official CLAP headers (vendored, MIT-licensed).
- `clap_shim.c` / `clap_shim.h` — a **flat, Swift-friendly C wrapper**. It does
  all the fiddly pointer/vtable work and exposes plain functions
  (`pb_clap_open`, `pb_clap_process`, …). No CLAP types leak into Swift.
- Swift talks to it through `CLAPHost.swift`; `build.sh` compiles the C and
  links it in. Full detail: [`docs/CLAP-AUDITION.md`](CLAP-AUDITION.md).

You can read and understand the entire Swift app without opening this folder.

## 6. How to run it

```bash
./build.sh            # compiles and assembles PluginBaby.app
open build/PluginBaby.app
./verify.sh           # optional: headless end-to-end check, no UI
```

See the README for requirements and the `swiftc`-not-Xcode explanation.

## 7. House rules (so it stays readable)

- **Keep the layers honest.** Views don't touch the disk; Services don't import
  SwiftUI; Models hold no logic. If a file is reaching across layers, that's the
  smell.
- **One file, one job.** Every file opens with a `///` line stating that job.
  New file → give it one. Files stay small (most are under ~150 lines).
- **Reusable UI lives in its own file** under `Views/`, named after the
  component, so it can be read — and reused — on its own.
- **Colors and brand go through `Theme.swift`**, never hard-coded in a View.
