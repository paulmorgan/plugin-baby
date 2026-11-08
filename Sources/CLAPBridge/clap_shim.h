// clap_shim.h — flat C surface over the CLAP plugin ABI, for Swift to call.
//
// No CLAP types leak across this boundary: Swift sees only plain C. The shim
// owns all the function-pointer/vtable gymnastics (see clap_shim.c).
//
// Covers Plugin Baby's CLAP auditioning MVP: discover plugins in a .clap,
// open one, read its channel layout, run audio through it (effects), and
// trigger notes (instruments). See docs/CLAP-AUDITION.md.
#ifndef PB_CLAP_SHIM_H
#define PB_CLAP_SHIM_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct pb_clap_handle pb_clap_handle;

// One plugin's advertised metadata (a .clap may contain several).
typedef struct {
    char id[256];
    char name[128];
    char vendor[128];
    char version[64];
    bool is_instrument;   // true for synths/samplers/drums; false for effects
} pb_clap_descriptor;

// --- Discovery (no instantiation) ---------------------------------------
// Scan a .clap bundle or dylib and fill up to `max` descriptors.
// Returns the number of plugins found (may exceed `max`), or -1 if the
// module could not be loaded as a CLAP.
int pb_clap_scan(const char *clap_path, pb_clap_descriptor *out, int max);

// --- Lifecycle ----------------------------------------------------------
// Open a specific plugin id from a .clap and prepare it for processing at
// the given sample rate and maximum block size. Returns NULL on failure.
pb_clap_handle *pb_clap_open(const char *clap_path, const char *plugin_id,
                             double sample_rate, uint32_t max_frames);

uint32_t pb_clap_input_channels(const pb_clap_handle *h);
uint32_t pb_clap_output_channels(const pb_clap_handle *h);
bool     pb_clap_is_instrument(const pb_clap_handle *h);

// Tear down: stop/deactivate/destroy the plugin and unload the module.
void pb_clap_close(pb_clap_handle *h);

// --- Audio thread -------------------------------------------------------
// Process `frames` of planar float audio. `in` may be NULL (instruments).
// `in`/`out` are arrays of channel pointers: in[ch][frame]. Returns false
// only if the plugin reported a hard error.
//
// Real-time safe: no allocation, no blocking. Note delivery uses a
// try-lock, so a contended block simply defers pending notes by one buffer.
bool pb_clap_process(pb_clap_handle *h,
                     const float *const *in, uint32_t in_ch,
                     float *const *out, uint32_t out_ch,
                     uint32_t frames, int64_t steady_time);

// --- Instrument note control (main thread) ------------------------------
// Queued; delivered at the start of the next pb_clap_process call.
void pb_clap_note_on(pb_clap_handle *h, int16_t key, double velocity);
void pb_clap_note_off(pb_clap_handle *h, int16_t key);
void pb_clap_all_notes_off(pb_clap_handle *h);

#ifdef __cplusplus
}
#endif

#endif // PB_CLAP_SHIM_H
