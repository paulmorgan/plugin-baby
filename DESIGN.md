# Plugin Baby — Design Doc

> Personal, local macOS app. No distribution, code signing, notarization, or
> licensing. Target: **macOS 15 (Sequoia)** or later. This document is for review
> **before** any code is written.

## 1. Goal

A native macOS app for managing your installed audio plugins on your own machine:

1. **Catalog & search** — find and browse every installed plugin with useful metadata.
2. **Chains / presets** — group plugins into named chains you can save and recall.
3. **Audition** — play a chosen audio sample through a selected plugin to hear it.
4. **Archive / delete / restore** — move plugins out of the way, remove them, and
   put them back later, without losing anything.

Non-goals: selling or sharing the app, DAW-style multi-track mixing, cloud sync.

## 2. The one hard constraint: hosting formats

"Audition a plugin with a sample" means *hosting* the plugin — loading it, running
audio through it, and playing the result. How hard that is depends entirely on format:

| Format | Catalog & search | Archive / delete / restore | Audition (play a sample through it) |
|---|---|---|---|
| **Audio Unit (AU / AUv3)** | ✅ Native APIs | ✅ | ✅ Native via `AVAudioEngine` |
| **VST3** | ✅ Filesystem scan | ✅ | ⚠️ Needs a custom VST3 host (VST3 SDK) — large separate effort |
| **VST2** | ✅ Filesystem scan | ✅ | ⚠️ Same, plus licensing restrictions on the old VST2 SDK |
| **CLAP** | ✅ Filesystem scan | ✅ | ⚠️ Needs a custom CLAP host |

**Recommendation:** build **AU auditioning first**. It's fully supported by Apple's
frameworks, including showing the plugin's own UI. Catalog/archive/restore cover all
formats from day one. VST3/CLAP hosting is a Phase 3 item only if you decide you need it.

> **CLAP auditioning is now scoped** — see [`docs/CLAP-AUDITION.md`](docs/CLAP-AUDITION.md).
> It's the cheapest non-AU format to host (MIT, header-only C), MVP ≈ 1 week.

This matters because most commercial plugins ship **both** an AU and a VST3 build, so
AU-only auditioning still covers the large majority of what you own.

## 3. Where plugins live

| Location | Needs admin? | Covered in MVP |
|---|---|---|
| `~/Library/Audio/Plug-Ins/{Components,VST3,VST,CLAP}` | No | ✅ Yes |
| `/Library/Audio/Plug-Ins/{Components,VST3,VST,CLAP}` | **Yes** (system dir) | Phase 2 |

For a personal app, the **user domain (`~/Library`) needs no admin rights** and is the
safe place to start. Touching `/Library` requires privilege escalation (an admin
prompt or a privileged helper); we add that in Phase 2 so the risky part is opt-in.

The app runs **non-sandboxed** — a sandboxed app can't freely read or move files in
`~/Library/Audio/Plug-Ins`. Fine for local personal use; it just can't go on the App Store.

## 4. Feature detail

### 4.1 Catalog & search
- **AU:** enumerate via `AVAudioUnitComponentManager` → name, manufacturer, type,
  subtype, version, category, sandbox-safety. Fast and reliable.
- **VST3/VST/CLAP:** scan the plugin folders for bundles; read `Contents/Info.plist`
  and bundle structure for name/manufacturer/version; detect architectures with `lipo`.
- **Search/filter:** by name, manufacturer, format, category, architecture
  (Intel / Apple Silicon / Universal), and archived-vs-installed state.
- **Per-plugin detail:** path, size, version, formats present, code-signature status,
  reveal-in-Finder.

### 4.2 Chains / presets
- A **Chain** = an ordered, named list of plugin references (+ optional notes).
- Create, rename, reorder, duplicate, delete chains.
- A chain references plugins by a stable identity (manufacturer + name + format), so it
  survives the plugin being archived/restored, and flags if a referenced plugin is missing.
- Persisted as JSON (or SwiftData) in Application Support — see §6.

### 4.3 Audition (AU-first)
- Pick a plugin + pick an audio sample (bundled defaults + your own files: WAV/AIFF/mp3/etc).
- Signal path: `AVAudioPlayerNode → AVAudioUnit (the plugin) → main mixer → output`.
- Transport: play / loop / stop; dry/wet bypass toggle to A/B the effect; output level meter.
- Optionally open the **plugin's own editor UI** (`requestViewController`) in a window.
- Instruments vs effects: effects process the sample; instruments can be driven by a
  simple test MIDI note / sequence instead of the sample (Phase 2).

### 4.4 Archive / delete / restore — the safety-critical part
Design principle: **archive-first, never destroy without a recoverable copy.**

- **Archive:** move the plugin bundle from its install folder into an app-managed
  archive folder, and write a manifest entry recording original path, format, version,
  code-signature, permissions, and timestamp. The plugin disappears from DAWs but is
  fully recoverable.
- **Delete:** two modes —
  - *Soft delete* (default): archive it, then it's gone from the system but restorable.
  - *Hard delete:* move to the **system Trash** (not an unrecoverable `rm`), with a
    confirmation naming exactly what's being removed. Only offered for already-archived
    items or with an explicit extra confirmation.
- **Restore:** move the bundle from the archive back to its recorded original location,
  re-apply permissions, and clear the quarantine flag so macOS/Gatekeeper still trusts it.
- **Integrity:** archiving uses a move (preserving the signed bundle intact); the manifest
  records a checksum so a tampered/incomplete archive is detected on restore.

Guardrails:
- Warn if a DAW is running (archiving/deleting under a live host can confuse plugin caches).
- Refuse to follow symlinks; validate the target is a real plugin bundle before moving.
- Everything is reversible except hard-delete, which always routes through Trash.

## 5. Architecture

Native **Swift + SwiftUI** (AppKit where needed, e.g. plugin editor windows).

```
UI (SwiftUI)
 ├─ Catalog view (list + search + detail)
 ├─ Chains view
 ├─ Audition view (transport, meters, plugin UI host)
 └─ Archive view (archived items, restore)
        │
Services
 ├─ PluginScanner      — AU (AVAudioUnitComponentManager) + filesystem scan + lipo
 ├─ AuditionEngine     — AVAudioEngine graph, file playback, AU hosting
 ├─ ArchiveManager     — move/restore bundles, Trash integration, manifest + checksums
 └─ Persistence        — chains + archive manifest (JSON or SwiftData)
        │
Models: Plugin, PluginFormat, Architecture, Chain, ArchiveEntry
```

Frameworks: SwiftUI, AVFoundation/AudioToolbox (AU hosting), AppKit (NSWorkspace, Trash,
editor windows), CoreAudioKit (plugin UIs).

## 6. Data & storage

- `~/Library/Application Support/Plugin Baby/`
  - `chains.json` — your chains/presets
  - `archive/` — moved plugin bundles
  - `archive-manifest.json` — one record per archived plugin (original path, metadata, checksum)
  - `samples/` — your saved audition samples
- No database server, no network. Everything local and inspectable.

## 7. Risks & open questions

- **VST3/CLAP auditioning** is the big one — out of MVP scope; confirm AU-first is OK.
- **System-domain plugins** (`/Library`) need admin rights — Phase 2; MVP is `~/Library` only.
- **Re-signing after lipo:** if we later add Intel-slice stripping, thinned bundles must be
  re-signed or they won't load. (Not in your selected feature set — noted for completeness.)
- **DAW plugin caches:** archiving/restoring may require the DAW to rescan. We surface a note.
- **Instrument vs effect auditioning:** effects are straightforward; instruments need a test
  MIDI source — propose Phase 2.

## 8. Suggested build phases

- **Phase 1 (MVP):** Catalog & search (all formats) · Archive/delete/restore (`~/Library`) ·
  AU audition with a sample · Chains. Covers your four requested capabilities.
- **Phase 2:** System-domain (`/Library`) with admin prompt · instrument auditioning ·
  plugin editor UI windows.
- **Phase 3 (optional):** VST3 / CLAP hosting for full-format auditioning.

## 9. Decisions (locked)

1. **AU-first auditioning** for the MVP — yes. VST3/CLAP are catalog & archive only for now.
2. **MVP scope = `~/Library` only** — yes. System `/Library` deferred to Phase 2.
3. **App name:** Plugin Baby.
4. **Minimum macOS:** 15 (Sequoia) — lets us use SwiftData and current SwiftUI / AVFoundation APIs freely.
