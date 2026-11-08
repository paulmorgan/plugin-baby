// clap_shim.c — implementation of the flat CLAP host surface (see clap_shim.h).
//
// Threading: pb_clap_open / pb_clap_close / pb_clap_note_* are main-thread.
// pb_clap_process runs on the audio thread and must not allocate or block;
// note hand-off uses os_unfair_lock_trylock so it never waits.

#include "clap_shim.h"

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <os/lock.h>
#include <CoreFoundation/CoreFoundation.h>

#include "clap/clap.h"

#define PB_MAX_EVENTS 64

struct pb_clap_handle {
    void                       *dso;
    CFBundleRef                 bundle;      // non-NULL when loaded from a .clap bundle
    const clap_plugin_entry_t  *entry;
    const clap_plugin_t        *plugin;
    clap_host_t                 host;

    bool      active;
    bool      processing;
    uint32_t  in_ch;
    uint32_t  out_ch;
    bool      is_instrument;

    // Note hand-off: main thread fills `pending`, audio thread drains it into
    // `events` at the top of each process() under a try-lock.
    os_unfair_lock lock;
    struct { int16_t key; double vel; bool on; } pending[PB_MAX_EVENTS];
    uint32_t pending_count;

    clap_event_note_t   events[PB_MAX_EVENTS];
    uint32_t            event_count;   // valid only during a process() call
    clap_input_events_t  in_events;
    clap_output_events_t out_events;
};

// --- Host callbacks (minimal: we advertise no host extensions) ----------

static const void *pb_host_get_extension(const clap_host_t *host, const char *id) {
    (void)host; (void)id; return NULL;
}
static void pb_host_request_restart(const clap_host_t *host)  { (void)host; }
static void pb_host_request_process(const clap_host_t *host)  { (void)host; }
static void pb_host_request_callback(const clap_host_t *host) { (void)host; }

// --- Event list vtables -------------------------------------------------

static uint32_t pb_in_events_size(const clap_input_events_t *list) {
    const pb_clap_handle *h = (const pb_clap_handle *)list->ctx;
    return h->event_count;
}
static const clap_event_header_t *pb_in_events_get(const clap_input_events_t *list, uint32_t index) {
    const pb_clap_handle *h = (const pb_clap_handle *)list->ctx;
    if (index >= h->event_count) return NULL;
    return &h->events[index].header;
}
static bool pb_out_events_try_push(const clap_output_events_t *list, const clap_event_header_t *event) {
    (void)list; (void)event; return true;   // we consume (ignore) plugin output events
}

// --- DSO loading --------------------------------------------------------

// Resolve and dlopen the actual mach-O. A .clap is either a bundle directory
// (resolve its executable via CFBundle) or a plain dylib.
static void *pb_load_dso(const char *clap_path, CFBundleRef *out_bundle) {
    *out_bundle = NULL;

    struct stat st;
    if (stat(clap_path, &st) != 0) return NULL;

    if (!S_ISDIR(st.st_mode)) {
        return dlopen(clap_path, RTLD_LOCAL | RTLD_NOW);
    }

    CFStringRef cfpath = CFStringCreateWithCString(NULL, clap_path, kCFStringEncodingUTF8);
    if (!cfpath) return NULL;
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, cfpath, kCFURLPOSIXPathStyle, true);
    CFRelease(cfpath);
    if (!url) return NULL;

    CFBundleRef bundle = CFBundleCreate(NULL, url);
    CFRelease(url);
    if (!bundle) return NULL;

    CFURLRef exe = CFBundleCopyExecutableURL(bundle);
    if (!exe) { CFRelease(bundle); return NULL; }

    char exepath[PATH_MAX];
    Boolean ok = CFURLGetFileSystemRepresentation(exe, true, (UInt8 *)exepath, sizeof(exepath));
    CFRelease(exe);
    if (!ok) { CFRelease(bundle); return NULL; }

    void *dso = dlopen(exepath, RTLD_LOCAL | RTLD_NOW);
    if (!dso) { CFRelease(bundle); return NULL; }

    *out_bundle = bundle;
    return dso;
}

static const clap_plugin_entry_t *pb_get_entry(void *dso) {
    return (const clap_plugin_entry_t *)dlsym(dso, "clap_entry");
}

static bool pb_desc_is_instrument(const clap_plugin_descriptor_t *desc) {
    if (!desc || !desc->features) return false;
    for (const char *const *f = desc->features; *f; ++f) {
        if (strcmp(*f, CLAP_PLUGIN_FEATURE_INSTRUMENT)  == 0 ||
            strcmp(*f, CLAP_PLUGIN_FEATURE_SYNTHESIZER) == 0 ||
            strcmp(*f, CLAP_PLUGIN_FEATURE_SAMPLER)     == 0 ||
            strcmp(*f, CLAP_PLUGIN_FEATURE_DRUM)        == 0 ||
            strcmp(*f, CLAP_PLUGIN_FEATURE_DRUM_MACHINE) == 0) {
            return true;
        }
    }
    return false;
}

static void pb_copy_str(char *dst, size_t cap, const char *src) {
    if (!src) { dst[0] = '\0'; return; }
    strncpy(dst, src, cap - 1);
    dst[cap - 1] = '\0';
}

// --- Discovery ----------------------------------------------------------

int pb_clap_scan(const char *clap_path, pb_clap_descriptor *out, int max) {
    CFBundleRef bundle = NULL;
    void *dso = pb_load_dso(clap_path, &bundle);
    if (!dso) return -1;

    int result = -1;
    const clap_plugin_entry_t *entry = pb_get_entry(dso);
    if (entry && entry->init && entry->init(clap_path)) {
        const clap_plugin_factory_t *factory =
            entry->get_factory ? (const clap_plugin_factory_t *)entry->get_factory(CLAP_PLUGIN_FACTORY_ID) : NULL;
        if (factory && factory->get_plugin_count && factory->get_plugin_descriptor) {
            uint32_t count = factory->get_plugin_count(factory);
            result = (int)count;
            int n = (count < (uint32_t)max) ? (int)count : max;
            for (int i = 0; i < n; ++i) {
                const clap_plugin_descriptor_t *d = factory->get_plugin_descriptor(factory, (uint32_t)i);
                pb_clap_descriptor *o = &out[i];
                memset(o, 0, sizeof(*o));
                if (d) {
                    pb_copy_str(o->id,      sizeof(o->id),      d->id);
                    pb_copy_str(o->name,    sizeof(o->name),    d->name);
                    pb_copy_str(o->vendor,  sizeof(o->vendor),  d->vendor);
                    pb_copy_str(o->version, sizeof(o->version), d->version);
                    o->is_instrument = pb_desc_is_instrument(d);
                }
            }
        }
        if (entry->deinit) entry->deinit();
    }

    if (bundle) CFRelease(bundle);
    dlclose(dso);
    return result;
}

// --- Lifecycle ----------------------------------------------------------

pb_clap_handle *pb_clap_open(const char *clap_path, const char *plugin_id,
                             double sample_rate, uint32_t max_frames) {
    CFBundleRef bundle = NULL;
    void *dso = pb_load_dso(clap_path, &bundle);
    if (!dso) return NULL;

    const clap_plugin_entry_t *entry = pb_get_entry(dso);
    if (!entry || !entry->init || !entry->init(clap_path)) {
        if (bundle) CFRelease(bundle);
        dlclose(dso);
        return NULL;
    }

    const clap_plugin_factory_t *factory =
        entry->get_factory ? (const clap_plugin_factory_t *)entry->get_factory(CLAP_PLUGIN_FACTORY_ID) : NULL;
    if (!factory || !factory->create_plugin) {
        if (entry->deinit) entry->deinit();
        if (bundle) CFRelease(bundle);
        dlclose(dso);
        return NULL;
    }

    pb_clap_handle *h = (pb_clap_handle *)calloc(1, sizeof(*h));
    if (!h) {
        if (entry->deinit) entry->deinit();
        if (bundle) CFRelease(bundle);
        dlclose(dso);
        return NULL;
    }
    h->dso    = dso;
    h->bundle = bundle;
    h->entry  = entry;
    h->lock   = OS_UNFAIR_LOCK_INIT;

    h->host.clap_version   = CLAP_VERSION;
    h->host.host_data      = h;
    h->host.name           = "Plugin Baby";
    h->host.vendor         = "Plugin Baby";
    h->host.url            = "https://github.com/paulmorgan/plugin-baby";
    h->host.version        = "0.1";
    h->host.get_extension  = pb_host_get_extension;
    h->host.request_restart  = pb_host_request_restart;
    h->host.request_process  = pb_host_request_process;
    h->host.request_callback = pb_host_request_callback;

    const clap_plugin_t *plugin = factory->create_plugin(factory, &h->host, plugin_id);
    if (!plugin || !plugin->init || !plugin->init(plugin)) {
        if (plugin && plugin->destroy) plugin->destroy(plugin);
        if (entry->deinit) entry->deinit();
        if (bundle) CFRelease(bundle);
        dlclose(dso);
        free(h);
        return NULL;
    }
    h->plugin = plugin;
    h->is_instrument = pb_desc_is_instrument(plugin->desc);

    // Channel layout from the main audio ports.
    const clap_plugin_audio_ports_t *ports =
        (const clap_plugin_audio_ports_t *)plugin->get_extension(plugin, CLAP_EXT_AUDIO_PORTS);
    if (ports && ports->count && ports->get) {
        clap_audio_port_info_t info;
        if (ports->count(plugin, true) > 0 && ports->get(plugin, 0, true, &info))
            h->in_ch = info.channel_count;
        if (ports->count(plugin, false) > 0 && ports->get(plugin, 0, false, &info))
            h->out_ch = info.channel_count;
    }
    if (h->out_ch == 0) h->out_ch = 2;                 // sane default
    if (h->is_instrument) h->in_ch = 0;                 // instruments take no audio input

    if (!plugin->activate(plugin, sample_rate, 1, max_frames)) {
        plugin->destroy(plugin);
        if (entry->deinit) entry->deinit();
        if (bundle) CFRelease(bundle);
        dlclose(dso);
        free(h);
        return NULL;
    }
    h->active = true;

    if (plugin->start_processing) h->processing = plugin->start_processing(plugin);
    else                          h->processing = true;

    h->in_events.ctx  = h;
    h->in_events.size = pb_in_events_size;
    h->in_events.get  = pb_in_events_get;
    h->out_events.ctx = h;
    h->out_events.try_push = pb_out_events_try_push;

    return h;
}

uint32_t pb_clap_input_channels(const pb_clap_handle *h)  { return h ? h->in_ch : 0; }
uint32_t pb_clap_output_channels(const pb_clap_handle *h) { return h ? h->out_ch : 0; }
bool     pb_clap_is_instrument(const pb_clap_handle *h)   { return h ? h->is_instrument : false; }

void pb_clap_close(pb_clap_handle *h) {
    if (!h) return;
    if (h->plugin) {
        if (h->processing && h->plugin->stop_processing) h->plugin->stop_processing(h->plugin);
        if (h->active && h->plugin->deactivate)          h->plugin->deactivate(h->plugin);
        if (h->plugin->destroy)                          h->plugin->destroy(h->plugin);
    }
    if (h->entry && h->entry->deinit) h->entry->deinit();
    if (h->bundle) CFRelease(h->bundle);
    if (h->dso)    dlclose(h->dso);
    free(h);
}

// --- Audio thread -------------------------------------------------------

bool pb_clap_process(pb_clap_handle *h,
                     const float *const *in, uint32_t in_ch,
                     float *const *out, uint32_t out_ch,
                     uint32_t frames, int64_t steady_time) {
    if (!h || !h->plugin || !h->active) return false;

    // Drain queued notes into CLAP events (non-blocking).
    h->event_count = 0;
    if (os_unfair_lock_trylock(&h->lock)) {
        uint32_t n = h->pending_count;
        if (n > PB_MAX_EVENTS) n = PB_MAX_EVENTS;
        for (uint32_t i = 0; i < n; ++i) {
            clap_event_note_t *ev = &h->events[i];
            memset(ev, 0, sizeof(*ev));
            ev->header.size     = sizeof(clap_event_note_t);
            ev->header.time     = 0;
            ev->header.space_id = CLAP_CORE_EVENT_SPACE_ID;
            ev->header.type     = h->pending[i].on ? CLAP_EVENT_NOTE_ON : CLAP_EVENT_NOTE_OFF;
            ev->header.flags    = CLAP_EVENT_IS_LIVE;
            ev->note_id    = -1;
            ev->port_index = 0;
            ev->channel    = 0;
            ev->key        = h->pending[i].key;
            ev->velocity   = h->pending[i].vel;
        }
        h->event_count   = n;
        h->pending_count = 0;
        os_unfair_lock_unlock(&h->lock);
    }

    clap_audio_buffer_t ib, ob;
    memset(&ib, 0, sizeof(ib));
    memset(&ob, 0, sizeof(ob));
    ib.data32 = (float **)in;    // plugin treats input as read-only
    ib.channel_count = in_ch;
    ob.data32 = (float **)out;
    ob.channel_count = out_ch;

    clap_process_t p;
    memset(&p, 0, sizeof(p));
    p.steady_time         = steady_time;
    p.frames_count        = frames;
    p.transport           = NULL;
    p.audio_inputs        = in ? &ib : NULL;
    p.audio_inputs_count  = in ? 1u : 0u;
    p.audio_outputs       = &ob;
    p.audio_outputs_count = 1;
    p.in_events           = &h->in_events;
    p.out_events          = &h->out_events;

    clap_process_status s = h->plugin->process(h->plugin, &p);
    return s != CLAP_PROCESS_ERROR;
}

// --- Note queue (main thread) ------------------------------------------

static void pb_enqueue(pb_clap_handle *h, int16_t key, double vel, bool on) {
    if (!h) return;
    os_unfair_lock_lock(&h->lock);
    if (h->pending_count < PB_MAX_EVENTS) {
        h->pending[h->pending_count].key = key;
        h->pending[h->pending_count].vel = vel;
        h->pending[h->pending_count].on  = on;
        h->pending_count++;
    }
    os_unfair_lock_unlock(&h->lock);
}

void pb_clap_note_on(pb_clap_handle *h, int16_t key, double velocity) {
    pb_enqueue(h, key, velocity, true);
}
void pb_clap_note_off(pb_clap_handle *h, int16_t key) {
    pb_enqueue(h, key, 0.0, false);
}
void pb_clap_all_notes_off(pb_clap_handle *h) {
    for (int16_t k = 0; k < 128; ++k) pb_enqueue(h, k, 0.0, false);
}
