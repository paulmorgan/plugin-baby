# Scope: CLAP auditioning

> How Plugin Baby could host **CLAP** plugins for live auditioning, the way it
> already hosts Audio Units. Companion to `DESIGN.md` §2 (hosting formats).
> Status: **proposal / not yet built.**

## TL;DR

CLAP is the cheap win among the non-AU formats: an open, **MIT-licensed,
header-only C API** with no SDK to link and no licensing friction for this repo.
The work is real but bounded — most of it is (a) a small C shim that owns the
CLAP vtables and (b) a render path, since `AVAudioEngine` will not host anything
that isn't an `AVAudioUnit`.

**MVP (load + effect audio) ≈ 1 week.** GUI and instruments are separable
follow-ups.

---

## 1. Why CLAP and not VST3 first

| | CLAP | VST3 |
|---|---|---|
| API surface | Header-only **C** (`clap/clap.h`) | Large **C++** SDK, COM-like |
| License | **MIT** — vendor the headers, done | GPLv3 *or* signed Steinberg agreement |
| Host complexity | Load dylib, fill one host struct, `process()` | Factories, `IComponent`/`IEditController`, `ProcessData` |
| GUI embedding | `clap.gui` → `NSView` parent | `IPlugView` → `NSView` |
| Plugin coverage | Growing, still a minority | Nearly universal |

CLAP buys us a second hosted format for a fraction of VST3's effort and **zero
licensing exposure** against the repo's Apache-2.0 license. VST3 stays Phase 3+.

---

## 2. The core constraint

`AVAudioEngine` connects `AVAudioUnit` nodes only. CLAP plugins are not AUs, so
we cannot `engine.connect(player, to: clapPlugin)`. Instead we **render CLAP
ourselves** and hand the result to the engine through an `AVAudioSourceNode`.

That node's render block runs on the **audio thread** — which is exactly where
CLAP's `process()` is required to run, so the models line up cleanly. Everything
else (activate, GUI, parameters) runs on the main thread.

The existing meter tap (`installMeterTap` on `mainMixerNode`) is backend-agnostic
and works unchanged, because it taps the mixer downstream of whatever node feeds
it.

---

## 3. Module layout

```
Sources/
  CLAPBridge/                 # new C target
    include/clap/…            # vendored MIT headers (clap v1.2.x)
    clap_shim.h               # clean C interface Swift calls
    clap_shim.c               # owns the vtables + host callbacks
    module.modulemap          # exposes clap_shim.h to Swift
  PluginBaby/
    Services/
      CLAPHost.swift          # Swift wrapper around the shim (load/activate/gui)
      CLAPAuditionBackend.swift  # AVAudioSourceNode render path + metering
      AuditionEngine.swift    # becomes an orchestrator over backends (see §6)
```

Why a C shim rather than calling CLAP from Swift directly: CLAP is all **nested
function-pointer structs** (`plugin->activate(plugin, …)`, host callback vtables
we must supply). That is miserable and error-prone from Swift. The shim presents
a flat, Swift-friendly C surface and keeps the pointer gymnastics in one audited
file.

---

## 4. The C shim interface (sketch)

```c
// clap_shim.h — what Swift sees. Opaque handle; no CLAP types leak into Swift.
typedef struct clap_host_handle clap_host_handle;

typedef struct {
    char   id[256];
    char   name[256];
    char   vendor[256];
    char   version[64];
    bool   is_instrument;     // from features: CLAP_PLUGIN_FEATURE_INSTRUMENT
} pb_clap_descriptor;

// --- discovery (no instantiation) ---
int  pb_clap_scan(const char *clap_path, pb_clap_descriptor *out, int max);

// --- lifecycle ---
clap_host_handle *pb_clap_open(const char *clap_path, const char *plugin_id,
                               double sample_rate, uint32_t max_frames);
void pb_clap_close(clap_host_handle *);

// --- audio (called on the audio thread; no allocation inside) ---
// in/out are planar float: in[ch][frame]. Returns frames written.
uint32_t pb_clap_process(clap_host_handle *,
                         const float *const *in,  uint32_t in_ch,
                         float *const *out, uint32_t out_ch,
                         uint32_t frames, int64_t steady_time);

// --- note events for instruments (Phase D) ---
void pb_clap_note_on (clap_host_handle *, int16_t key, double velocity);
void pb_clap_note_off(clap_host_handle *, int16_t key);

// --- GUI (Phase C): embed into a host NSView ---
bool pb_clap_gui_supported(clap_host_handle *);
bool pb_clap_gui_embed(clap_host_handle *, void *parent_nsview,
                       uint32_t *w, uint32_t *h);
void pb_clap_gui_destroy(clap_host_handle *);
```

Inside, the shim:

- `dlopen`s the `.clap` binary (a macOS bundle → `Contents/MacOS/<exec>`; some
  ship as a plain dylib) and `dlsym`s **`clap_entry`** (`clap_plugin_entry_t`).
- `entry->init(path)` → `entry->get_factory("clap.plugin-factory")` →
  `create_plugin(host, id)`.
- Supplies the **`clap_host_t`** struct: name/vendor/version, plus
  `get_extension`, `request_restart`, `request_process`, `request_callback`.
  These are the fiddly bit — `request_callback` must be marshalled back to the
  main thread (post to a queue the Swift side drains and calls
  `plugin->on_main_thread`).
- Queries `clap.audio-ports` for channel layout; activates with the engine's
  sample rate and `[1, maxFrames]`; calls `start_processing` before the first
  `process`.

---

## 5. The render path (Swift)

`CLAPAuditionBackend` owns an `AVAudioSourceNode` with a non-interleaved float
format (planar — a direct match for CLAP's `data32`):

```
sourceNode render block (audio thread):
  1. pull `frameCount` frames from the decoded sample buffer (looping playhead)
  2. point `in[ch]` at those frames; `out[ch]` at the ABL buffers
  3. pb_clap_process(handle, in, inCh, out, outCh, frameCount, steadyTime)
  4. steadyTime += frameCount
```

Hard rules inside the block: **no allocation, no locks, no Swift ARC churn** —
preallocate scratch pointers at activate time; the sample buffer is decoded once
up front into a contiguous planar `[Float]` per channel.

Engine graph: `sourceNode → mainMixerNode → output`. Metering reuses the existing
mixer tap untouched. For an **effect**, the sample is the input; for an
**instrument** (Phase D), inputs are silent and note events drive it.

---

## 6. Where it slots into the current engine

`AuditionEngine` is AU-specific today (`AVAudioUnit.instantiate`,
`engine.connect`, `MusicDeviceMIDIEvent`). Introduce a thin seam:

```swift
protocol AuditionBackend {           // load / play / stop / openEditor
    func load(_ plugin: Plugin) async
    func play(); func stop()
    var canOpenEditor: Bool { get }
    func openEditor()
}
```

- `AUAuditionBackend` — today's code, moved behind the protocol.
- `CLAPAuditionBackend` — the new path.

`AuditionEngine` keeps the published UI state (`isPlaying`, `statusMessage`,
`outputLevel`, `spectrum`, sample selection — all unchanged) and the shared mixer
tap, and dispatches to the backend chosen by `plugin.format`. The default-sample
plumbing we just shipped is reused as-is: a CLAP **effect** gets the same sample.

UI change is one line: `DetailPanel`'s Preview button is currently
`.disabled(plugin.format != .audioUnit)` — widen it to allow `.clap` once the
backend lands. The editor window (`presentEditor` + the async-resize observer we
built for AUs) is reused for CLAP GUIs; CLAP reports size via `clap.gui`
`get_size`/`set_size`, so the same "fit the window to the view" logic applies.

---

## 7. Build system

The project builds with `swiftc` directly (no SwiftPM/Xcode). Mixed C+Swift needs
a two-step `build.sh`:

1. `clang -c Sources/CLAPBridge/clap_shim.c -ISources/CLAPBridge/include -o clap_shim.o`
2. `swiftc … -import-objc-header Sources/CLAPBridge/clap_shim.h clap_shim.o -o …`

Link `-ldl` for `dlopen`. No third-party libraries — only the vendored MIT
headers. (If we later adopt full Xcode/SwiftPM, this becomes a plain C target.)

---

## 8. Phases & estimate

| Phase | Deliverable | Risk | Est. |
|---|---|---|---|
| **A** | Load + introspect: `dlopen`, entry/factory, descriptors, audio-ports. Real CLAP metadata in the catalog; "loadable?" health check. | Low | ~1 day |
| **B** | **Effect audio** via `AVAudioSourceNode` + shim `process`. Preview enabled for CLAP. **← MVP ends here** | Medium | 2–4 days |
| **C** | GUI embedding (`clap.gui` cocoa → reuse editor window). | Medium | 2–3 days |
| **D** | Instruments (note events via `in_events`) + basic parameter defaults. | Medium | ~2 days |

MVP (A+B) ≈ **one week**. C and D are independent and optional.

---

## 9. Risks & open questions

- **Audio-thread discipline.** The render block and `process()` must be
  allocation- and lock-free. This is the main place bugs hide; budget care, not
  just code.
- **Host-callback correctness.** `request_restart` (plugin asks to re-activate),
  `request_callback` (main-thread work), and thread-safety of extension calls
  must be honoured or plugins misbehave. Defensive host, per the CLAP host
  guidelines.
- **GUI quirks.** Floating vs embedded, scale factor, resize negotiation — we
  already solved the AU analogue, so this is familiar ground, not new ground.
- **Plugin variety.** Real-world CLAPs vary; validate against a few (e.g. Surge
  XT, Vital, u-he builds) early.
- **No `auval` equivalent.** CLAP has no system validator; "validation" for CLAP
  means our own load-and-activate smoke test (fits the existing
  `ValidationStatus` model as a different check).

## 10. Decision needed before building

1. **MVP line** — ship A+B (audio only) first, GUI/instruments later? (recommended)
2. **Backend seam** — refactor `AuditionEngine` to the `AuditionBackend` protocol
   now, or add CLAP alongside and refactor once it's proven?
3. **CLAP header version** to vendor (propose latest stable **1.2.x**).
