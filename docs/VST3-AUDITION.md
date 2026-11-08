# Scope: VST3 auditioning

> How Plugin Baby could host **VST3** plugins for live auditioning, the way it
> already hosts Audio Units. Companion to `DESIGN.md` §2 and
> [`docs/CLAP-AUDITION.md`](CLAP-AUDITION.md).
> Status: **proposal / not yet built.**

## TL;DR

VST3 is the high-value, high-cost format: almost every commercial plugin ships
it, but hosting it means a **C++ host against Steinberg's VST3 SDK**, and the
**licensing is a real decision** — GPLv3 or a signed Steinberg agreement — that
applies no matter which library or language wrapper you use.

For this app (native Swift/AppKit on `AVAudioEngine`), the clean path is a
**direct VST3 SDK C++ shim** that reuses the exact architecture already laid out
for CLAP. JUCE is a faster-to-working alternative with its own tradeoffs. A Rust
crate (`vst3-host`) exists but is a poor fit here.

**Estimate: MVP (effect audio) ≈ 2–3 weeks** — notably more than CLAP's ~1 week.

---

## 1. The licensing gate (decide this first)

VST3's interface definitions are **Steinberg intellectual property**, distributed
under a **dual license**:

- **GPLv3** — free, but obligates the whole app that links it to GPLv3. Plugin
  Baby is currently Apache-2.0; shipping a GPLv3 VST3 host would force the app
  (or at least the host component) to GPLv3.
- **Proprietary Steinberg VST3 license** — a signed agreement with Steinberg, for
  closed-source/other-licensed distribution.

This is **not avoidable by choosing a different wrapper.** JUCE bundles the VST3
SDK; the Rust `vst3`/`vst3-host` crates ship "pre-generated bindings" to
Steinberg's interfaces. An MIT or permissive label on a *wrapper* covers that
wrapper's own code, not Steinberg's interface IP underneath.

For a **personal, non-distributed** build (which `DESIGN.md` already states Plugin
Baby is), GPLv3 obligations are largely moot — they bite on *distribution*. So:

> **Open question O1:** Is Plugin Baby staying personal/local (GPLv3 is fine), or
> is public distribution intended (then: accept GPLv3 for the whole app, isolate
> the host in a separately-licensed helper process, or get a Steinberg agreement)?

The **process-isolation** option (below) doubles as a clean licensing boundary:
run the VST3 host in a **separate helper executable** that talks to the main app
over IPC. The GPLv3 obligation then attaches to the helper, not the Apache-2.0
app. This is also the most robust design for crash safety.

---

## 2. Options compared

| Approach | Fit with Swift / AVAudioEngine / AppKit | Effort | License reality |
|---|---|---|---|
| **Direct Steinberg VST3 SDK (C++ shim)** | ★★★ Reuses the CLAP shim + `AVAudioSourceNode` + editor-window pattern | High | GPLv3 / Steinberg agreement |
| **JUCE** (`AudioPluginFormatManager`) | ★★ Hosts VST3 **and** AU uniformly, editor support — but JUCE wants to own the app/run-loop; awkward inside native AppKit | Medium | AGPLv3 / commercial **+** VST3 SDK |
| **`vst3-host` (Rust crate)** | ★ Rust FFI; drives its own CPAL audio + objc2 window | Medium–High | MIT wrapper **+** VST3 SDK underneath |

### Why direct SDK is the pick here

The app already owns its audio graph (`AVAudioEngine`) and its editor window (with
the async-resize logic we built for AUs). The direct-SDK path slots into both.
JUCE and `vst3-host` each want to **own** audio output and/or the window, which we'd
have to fight. JUCE additionally assumes control of the application message loop,
which is an impedance mismatch for a native AppKit/SwiftUI app — you end up
embedding a framework to use ~5% of it.

### When JUCE would win

If the goal shifted to "host *everything* (VST3 + AU + VST2) through one uniform
API with editors, fast," JUCE's `AudioPluginFormatManager` is battle-tested and
would save host code — at the cost of framework weight and AGPL/commercial
licensing. Worth revisiting only if the format list grows beyond AU + CLAP + VST3.

---

## 3. Architecture (direct SDK path)

Mirrors the CLAP plan — same seam, same render model, same editor reuse.

```
Sources/
  VST3Bridge/                 # new C++ target
    sdk/…                     # Steinberg VST3 SDK (GPLv3) — vendored or submodule
    vst3_shim.h               # clean C interface Swift calls (no VST3 types leak)
    vst3_shim.cpp             # owns IComponent / IAudioProcessor / IPlugView
  PluginBaby/
    Services/
      VST3Host.swift          # Swift wrapper around the shim
      VST3AuditionBackend.swift  # AVAudioSourceNode render path + metering
      AuditionEngine.swift    # orchestrator over AuditionBackend (see CLAP §6)
```

The `AuditionBackend` protocol proposed in `CLAP-AUDITION.md` §6 is the shared
seam: `AUAuditionBackend` (today), `CLAPAuditionBackend`, `VST3AuditionBackend`.
Building CLAP first establishes that seam; VST3 then reuses it.

### The C++ shim does the heavy lifting

VST3 is a COM-like component model. The shim owns it and exposes a flat C surface:

- **Load:** open the `.vst3` bundle, get the `GetPluginFactory` entry, enumerate
  classes, create the `IComponent`, query `IAudioProcessor` and (for the editor)
  `IEditController`, connect the two, `setupProcessing`, `setActive(true)`.
- **Process (audio thread):** fill a `Steinberg::Vst::ProcessData` — input/output
  `AudioBusBuffers` (planar float, matching CLAP and our `AVAudioSourceNode`),
  `processContext`, parameter/event queues — and call `process()`.
- **Editor (reuse our window):** `IEditController::createView("editor")` →
  `IPlugView`; attach to an `NSView` via `plugView->attached(nsview, "NSView")`.
  VST3 reports size through `getSize`/`onSize`/`canResize` — feed that into the
  same "fit the window to the view" logic we already wrote for AU editors.

### Render path (Swift)

Identical in shape to CLAP §5: an `AVAudioSourceNode` whose render block pulls
sample frames (looping), calls `vst3_shim_process(in, out, frames)`, and writes
the output buffers — **no allocation, no locks** on the audio thread. The existing
`mainMixerNode` meter tap is reused unchanged.

---

## 4. Process isolation (recommended, not optional for VST3)

VST3 plugins are third-party native code; a bad one crashes the host. Running the
VST3 shim in a **separate helper process** (XPC on macOS, or a plain child process
+ shared-memory audio ring) gives:

1. **Crash safety** — a plugin crash takes down the helper, not Plugin Baby.
2. **A clean license boundary** — the GPLv3-linked host lives in the helper; the
   Apache-2.0 app talks to it over IPC (see §1).

Cost: real IPC engineering (shared-memory audio transport at low latency, plus
forwarding the editor `NSView` across the process boundary — macOS supports remote
views, but it's fiddly). This is the single biggest reason VST3 is ~2–3× the CLAP
effort. For a **personal** build you *could* skip isolation (in-process shim, like
CLAP) and add it later; for distribution it's strongly advised.

---

## 5. Build system

Like CLAP, the `swiftc`-based `build.sh` gains a native compile step — but C++,
and much larger:

1. Build the VST3 SDK + `vst3_shim.cpp` with `clang++` (the SDK ships CMake; we'd
   either vendor a minimal subset or add a CMake step).
2. Link the resulting objects/lib into the Swift build (`-import-objc-header
   vst3_shim.h`, link `libc++`).

The SDK is large and C++ — if VST3 lands, this is the point where adopting full
**Xcode/SwiftPM** (with a proper C++ target) starts to pay for itself over the
hand-rolled `swiftc` script.

---

## 6. Phases & estimate

| Phase | Deliverable | Risk | Est. |
|---|---|---|---|
| **A** | SDK integration + build: factory enumerate, create component, read bus/arrangement. Real VST3 metadata; "loadable?" check. | Medium | 2–3 days |
| **B** | **Effect audio** (in-process shim) via `AVAudioSourceNode` + `process()`. Preview enabled for VST3. **← personal-use MVP** | High | ~1 week |
| **C** | Editor hosting (`IPlugView` → reuse editor window). | Medium–High | 3–4 days |
| **D** | Instruments (note events via event queues) + parameter defaults. | Medium | 2–3 days |
| **E** | Process isolation (XPC helper + shared-memory audio + remote view). *Required for distribution.* | High | 1–1.5 weeks |

In-process MVP (A+B) ≈ **1.5–2 weeks**; with editor (C) ≈ **2.5–3 weeks**.
Isolation (E) is a further, separable chunk.

---

## 7. Risks & open questions

- **O1 — licensing (see §1):** personal vs distributed decides everything
  downstream (GPLv3 acceptance, or helper-process isolation, or Steinberg deal).
- **Audio-thread discipline:** same rule as CLAP — allocation- and lock-free
  `process()` and render block.
- **COM lifetime/refcounting:** VST3's `addRef`/`release` and component↔controller
  connection must be exact; leaks and use-after-free hide here.
- **Editor embedding across formats:** AU and VST3 both hand us an `NSView`; the
  window infra generalizes, but VST3's resize negotiation differs in detail.
- **Build weight:** the SDK is heavy C++; likely the trigger to move to Xcode/SwiftPM.
- **No `auval` equivalent:** validation = our own load-and-activate smoke test,
  same as proposed for CLAP (fits the existing `ValidationStatus` model).

## 8. Recommendation & sequencing

1. **Ship CLAP first** (cheaper, MIT, no licensing gate) — it establishes the
   `AuditionBackend` seam, the C-shim build step, and the render path that VST3
   reuses.
2. **Answer O1** before writing VST3 code.
3. **VST3 via the direct SDK shim**, in-process for a personal build; add the XPC
   helper (and its license boundary) only if/when distribution is on the table.
4. Keep **JUCE** in your back pocket — reconsider only if the goal becomes
   "one uniform host for AU + VST3 + VST2 + everything, fast."
