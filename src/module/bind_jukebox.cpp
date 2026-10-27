// G-SA1 module: the jukebox feature "jukebox" (sadc docs/research/jukebox.md 6.3 / 6.4 with its Review; plan
// gsa1_rounds_plan.md 10.2, J1). The game's music from the player's own disc on a worker thread of the module
// (src/core/jukebox.hpp), so it keeps playing through hitches of the Lua thread; the Q-menu page is the addon's
// gsa1/feat/cl_jukebox.lua (J2).
//
// Lua API (feature version 1; GSA1.HasFeature("jukebox")):
//   gsa1.MusicList() -> nil, "loading" | nil, message, code | list
//       The first call starts the engine (the disc path comes from the module's config file, as for gsa1.Init: the
//       jukebox needs neither gsa1.Init nor a character). The list holds the tracks on the disc only (109; 69
//       NIGHTS_K.ADX is named by the game but absent), each {music, file, title (the game's sound-test title; nil when
//       the sound test does not list it or the disc's ADVERTISE.PRS is not the supported one: show the file name),
//       page (sound-test page 0..5, -1 not listed), entry (0-based position on it, -1), seconds (the data present),
//       loop (bool), loop_start, loop_end (seconds; without a loop 0 and seconds), rate (Hz), listed, jingle, short
//       (no loop and under 25 s), truncated}.
//   gsa1.JukeboxPlay(ch, music, start_seconds, plan, loops, fade_in, fade_out) -> true, "loading" | false, message, code
//       ch 0..4 (0: the personal jukebox, 2D); plan "forever" (default) | "loops" | "once"; loops 1..1000 (default 2);
//       fades 0..60 s (default 0). start_seconds is plan time; the module's clock of the call goes with it, so the
//       start frame is computed when the sound begins (start + the time the open took).
//   gsa1.JukeboxStop(ch [, fade]) / gsa1.JukeboxPause(ch, paused) / gsa1.JukeboxSeek(ch, t) / gsa1.JukeboxSync(ch, t)
//       -> true | false, message, code. Sync seeks only when the position is more than 0.25 s off.
//   gsa1.JukeboxVolume(ch, volume 0..1) -> true | false, message: 1 = the game's own music level (-1 dB).
//   gsa1.JukeboxPlace(ch, pos, radius) / gsa1.JukeboxPlace(ch, nil) -> true | false, message: a placed (3D) channel
//       with the game's distance curve, or 2D again.
//   gsa1.JukeboxUpdate(eye, forward, up, gmod_volume, music_volume, paused) -> the audible channels
//       Every frame: the listener, GMod's `volume` (applied unless GMod scales BASS's streams itself), the music
//       volume (snd_musicvolume when the addon follows it, else 1) and the game's pause (every channel holds).
//   gsa1.JukeboxState(ch [, out]) -> {music, state ("idle" "loading" "playing" "paused" "ended" "failed"), position
//       (plan seconds), length (the track's seconds), loops_done, error, track_position (seconds in the file),
//       plan_length (0 = forever), plan, loops, paused, volume, placed, queued (seconds in BASS)}
//   gsa1.JukeboxStatus([out]) -> {ready, tracks, active, memory_mb, max_open_ms, underruns, error, started, failed,
//       listed, titles, recoveries, opens, list_ms, backend}
//   gsa1.AudioDuck(gain 0..1, duck_jingles) -> true | false, message: the game's music x gain (libsa1 ramps it over
//       0.5 s); its jingles too only with duck_jingles (the drowning countdown stays audible otherwise).
//   gsa1.JUKEBOX_CHANNELS = 5
// Thread rule (Review G1): these functions only post commands and targets; the engine's worker alone calls BASS (it
// binds BASS itself) and libsa1's music object. Messages never contain the disc's or the config's directory.
#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "GarrysMod/Lua/Interface.h"

#include "../core/config.hpp"
#include "../core/jukebox.hpp"
#include "../core/util.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;
using namespace gsa1::mod;

namespace {

// what the worker's log callback needs (rebuilt at each start, while no worker runs)
struct JbLog {
    gsa1::Session *session = nullptr;
    std::string disc_dir, config_dir;
};

gsa1::Jukebox *g_jb = nullptr;      // made at the first jukebox call (targets can be set before the engine starts)
JbLog g_jb_log;
std::string g_jb_start_error;       // why the engine could not start (no config)
double g_jb_checked = -1e12;        // ms of the last config check

void jb_replace_all(std::string &s, const std::string &what, const std::string &with)
{
    if (what.size() < 3) {
        return;
    }
    size_t pos = 0;
    while ((pos = s.find(what, pos)) != std::string::npos) {
        s.replace(pos, what.size(), with);
        pos += with.size();
    }
}

// the module's scrub plus the jukebox's own disc (the session may not know it: no gsa1.Init needed)
std::string jb_scrub_with(const std::string &m, const std::string &disc_dir, const std::string &config_dir)
{
    std::string s = m;
    for (int k = 0; k < 2; k++) {
        const std::string &d = k == 0 ? disc_dir : config_dir;
        const char *tag = k == 0 ? "<disc>" : "<config>";
        std::string a = d, b = d;
        std::replace(a.begin(), a.end(), '/', '\\');
        std::replace(b.begin(), b.end(), '\\', '/');
        jb_replace_all(s, a, tag);
        jb_replace_all(s, b, tag);
    }
    return s;
}

std::string jb_scrub(const std::string &m)
{
    return jb_scrub_with(scrubbed(m), g_jb_log.disc_dir,
                         g_jb_log.config_dir.empty() ? gsa1::config_dir() : g_jb_log.config_dir);
}

// the engine's worker logs through the session's thread-safe log (gsa1.PollLog, the session log file)
void jb_log_cb(void *user, int32_t level, const char *msg)
{
    const JbLog *l = (const JbLog *)user;
    if (l->session) {
        std::string s = jb_scrub_with(msg ? msg : "", l->disc_dir, l->config_dir);
        l->session->log_line(level, s.c_str());
    }
}

gsa1::Jukebox &jb()
{
    if (!g_jb) {
        g_jb = new gsa1::Jukebox();
    }
    return *g_jb;
}

// starts the engine at the first use, and again when the configured disc changed (checked at most once a second)
bool jb_ensure(std::string &err, const char *&code)
{
    gsa1::Jukebox &j = jb();
    double now = gsa1::now_ms();
    if (j.started() && now - g_jb_checked < 1000.0) {
        return true;
    }
    g_jb_checked = now;
    gsa1::Config cfg;
    std::string e;
    if (!gsa1::load_config(cfg, e)) {
        if (j.started()) {
            return true;    // keep what plays
        }
        g_jb_start_error = e;
        err = e;
        code = "no_config";
        return false;
    }
    if (j.started() && j.gdi() == cfg.disc) {
        return true;
    }
    j.shutdown();           // another disc was chosen: the engine starts again on it
    g_jb_log.session = session();
    g_jb_log.disc_dir = gsa1::parent_dir(cfg.disc);
    g_jb_log.config_dir = gsa1::config_dir();
    gsa1::JukeboxConfig jc;
    jc.gdi = cfg.disc;
    jc.acquire_bass = true;     // the worker binds GMod's BASS: no BASS call on this thread
    jc.log = jb_log_cb;
    jc.log_user = &g_jb_log;
    if (!j.start(jc, e)) {
        g_jb_start_error = e;
        err = e;
        code = "failed";
        return false;
    }
    g_jb_start_error.clear();
    return true;
}

bool absent(ILuaBase *L, int i)
{
    return L->IsType(i, LT::Nil) || L->IsType(i, LT::None);
}

// an optional number in [lo, hi] (absent: def)
bool opt_number(ILuaBase *L, int i, double &out, double def, double lo, double hi)
{
    if (absent(L, i)) {
        out = def;
        return true;
    }
    return arg_number(L, i, out) && out >= lo && out <= hi;
}

int bad(ILuaBase *L, const char *usage)
{
    return push_false_msg(L, usage, "bad_argument");
}

int ok_true(ILuaBase *L)
{
    L->PushBool(true);
    return 1;
}

}  // namespace

// gsa1.MusicList() -> nil, "loading" | nil, message, code | list
GSA1_FN(gsa1_jukebox_MusicList)
{
    std::string err;
    const char *code = "failed";
    if (!jb_ensure(err, code)) {
        return push_nil_msg(LUA, jb_scrub(err), code);
    }
    std::shared_ptr<const std::vector<gsa1::JbTrack>> list;
    std::string msg;
    int r = g_jb->tracks(list, msg);
    if (r == 0) {
        LUA->PushNil();
        LUA->PushString("loading");
        return 2;
    }
    if (r < 0 || !list) {
        return push_nil_msg(LUA, jb_scrub(msg), "failed");
    }
    LUA->CreateTable();
    int t = LUA->Top();
    int n = 0;
    for (const gsa1::JbTrack &k : *list) {
        int e = raw_subtable_i(LUA, t, ++n);
        double rate = k.rate ? (double)k.rate : 1.0;
        raw_num(LUA, e, "music", k.music);
        raw_str(LUA, e, "file", k.file);
        if (k.has_title) {
            raw_str(LUA, e, "title", k.title);
        }
        raw_num(LUA, e, "page", k.listed() ? k.page : -1);
        raw_num(LUA, e, "entry", k.listed() ? k.entry : -1);
        raw_num(LUA, e, "seconds", k.seconds());
        raw_bool(LUA, e, "loop", k.loop);
        raw_num(LUA, e, "loop_start", k.loop_start / rate);
        raw_num(LUA, e, "loop_end", k.loop_end / rate);
        raw_num(LUA, e, "rate", k.rate);
        raw_bool(LUA, e, "listed", k.listed());
        raw_bool(LUA, e, "jingle", k.jingle());
        raw_bool(LUA, e, "short", k.is_short());
        raw_bool(LUA, e, "truncated", k.truncated());
        LUA->Pop();
    }
    return 1;
}

// gsa1.JukeboxPlay(ch, music, start_seconds, plan, loops, fade_in, fade_out) -> true, "loading" | false, message, code
GSA1_FN(gsa1_jukebox_Play)
{
    double call = now_s();     // start anchoring (Review G3): the clock of the call goes with the start
    const char *usage = "JukeboxPlay(channel 0..4, music 0..109, start seconds >= 0, plan \"forever\" | \"loops\" | "
                        "\"once\", loops 1..1000, fade_in 0..60, fade_out 0..60)";
    int32_t ch = 0, music = 0;
    double start = 0.0, loops = 2.0, fi = 0.0, fo = 0.0;
    gsa1::JbPlanSpec spec;
    if (!arg_int(LUA, 1, ch, 0, gsa1::kJukeboxChannels - 1) || !arg_int(LUA, 2, music, 0, 1000000) ||
        !opt_number(LUA, 3, start, 0.0, 0.0, 1e7) || !opt_number(LUA, 5, loops, 2.0, 1.0, 1000.0) ||
        loops != std::floor(loops) || !opt_number(LUA, 6, fi, 0.0, 0.0, 60.0) || !opt_number(LUA, 7, fo, 0.0, 0.0, 60.0)) {
        return bad(LUA, usage);
    }
    if (!absent(LUA, 4)) {
        std::string p;
        if (!arg_string(LUA, 4, p, 16) || !gsa1::jb_plan_parse(p, spec.plan)) {
            return bad(LUA, usage);
        }
    }
    spec.loops = (int32_t)loops;
    spec.fade_in = fi;
    spec.fade_out = fo;
    std::string err;
    const char *code = "failed";
    if (!jb_ensure(err, code)) {
        return push_false_msg(LUA, jb_scrub(err), code);
    }
    if (!g_jb->play(ch, (uint32_t)music, start, spec, call, err)) {
        return push_false_msg(LUA, jb_scrub(err), "not_found");
    }
    LUA->PushBool(true);
    LUA->PushString("loading");
    return 2;
}

// gsa1.JukeboxStop(ch [, fade]) -> true | false, message, code
GSA1_FN(gsa1_jukebox_Stop)
{
    int32_t ch = 0;
    double fade = 0.0;
    if (!arg_int(LUA, 1, ch, 0, gsa1::kJukeboxChannels - 1) || !opt_number(LUA, 2, fade, 0.0, 0.0, 60.0)) {
        return bad(LUA, "JukeboxStop(channel 0..4, fade seconds 0..60)");
    }
    if (g_jb && g_jb->started()) {
        g_jb->stop(ch, fade);
    }
    return ok_true(LUA);
}

// gsa1.JukeboxPause(ch, paused) -> true | false, message, code
GSA1_FN(gsa1_jukebox_Pause)
{
    int32_t ch = 0;
    if (!arg_int(LUA, 1, ch, 0, gsa1::kJukeboxChannels - 1) || !LUA->IsType(2, LT::Bool)) {
        return bad(LUA, "JukeboxPause(channel 0..4, paused boolean)");
    }
    if (!g_jb || !g_jb->started()) {
        return push_false_msg(LUA, "the jukebox is not started (gsa1.MusicList or gsa1.JukeboxPlay starts it)",
                              "not_started");
    }
    g_jb->pause(ch, LUA->GetBool(2));
    return ok_true(LUA);
}

// gsa1.JukeboxSeek(ch, t) -> true | false, message, code
GSA1_FN(gsa1_jukebox_Seek)
{
    int32_t ch = 0;
    double t = 0.0;
    if (!arg_int(LUA, 1, ch, 0, gsa1::kJukeboxChannels - 1) || !arg_number(LUA, 2, t) || t < 0.0 || t > 1e7) {
        return bad(LUA, "JukeboxSeek(channel 0..4, seconds >= 0)");
    }
    if (!g_jb || !g_jb->started()) {
        return push_false_msg(LUA, "the jukebox is not started (gsa1.MusicList or gsa1.JukeboxPlay starts it)",
                              "not_started");
    }
    g_jb->seek(ch, t);
    return ok_true(LUA);
}

// gsa1.JukeboxSync(ch, t) -> true | false, message, code
GSA1_FN(gsa1_jukebox_Sync)
{
    double call = now_s();
    int32_t ch = 0;
    double t = 0.0;
    if (!arg_int(LUA, 1, ch, 0, gsa1::kJukeboxChannels - 1) || !arg_number(LUA, 2, t) || t < 0.0 || t > 1e7) {
        return bad(LUA, "JukeboxSync(channel 0..4, seconds >= 0)");
    }
    if (!g_jb || !g_jb->started()) {
        return push_false_msg(LUA, "the jukebox is not started (gsa1.MusicList or gsa1.JukeboxPlay starts it)",
                              "not_started");
    }
    g_jb->sync(ch, t, call);
    return ok_true(LUA);
}

// gsa1.JukeboxVolume(ch, volume 0..1) -> true | false, message, code
GSA1_FN(gsa1_jukebox_Volume)
{
    int32_t ch = 0;
    double v = 1.0;
    if (!arg_int(LUA, 1, ch, 0, gsa1::kJukeboxChannels - 1) || !arg_number(LUA, 2, v) || v < 0.0 || v > 1.0) {
        return bad(LUA, "JukeboxVolume(channel 0..4, volume 0..1)");
    }
    jb().volume(ch, v);
    return ok_true(LUA);
}

// gsa1.JukeboxPlace(ch, pos, radius) | gsa1.JukeboxPlace(ch, nil) -> true | false, message, code
GSA1_FN(gsa1_jukebox_Place)
{
    int32_t ch = 0;
    if (!arg_int(LUA, 1, ch, 0, gsa1::kJukeboxChannels - 1)) {
        return bad(LUA, "JukeboxPlace(channel 0..4, position Vector, radius > 0) or JukeboxPlace(channel, nil)");
    }
    if (absent(LUA, 2)) {
        jb().place_2d(ch);
        return ok_true(LUA);
    }
    float pos[3];
    double radius = 0.0;
    if (!arg_vector(LUA, 2, pos) || !arg_number(LUA, 3, radius) || radius <= 0.0 || radius > 1e6) {
        return bad(LUA, "JukeboxPlace(channel 0..4, position Vector, radius > 0) or JukeboxPlace(channel, nil)");
    }
    jb().place(ch, pos, radius);
    return ok_true(LUA);
}

// gsa1.JukeboxUpdate(eye, forward, up, gmod_volume, music_volume, paused) -> audible channels
GSA1_FN(gsa1_jukebox_Update)
{
    if (!g_jb) {
        LUA->PushNumber(0);
        return 1;
    }
    float eye[3], fwd[3], up[3];
    bool listener = arg_vector(LUA, 1, eye) && arg_vector(LUA, 2, fwd) && arg_vector(LUA, 3, up);
    double gv = 1.0, mv = 1.0;
    if (!arg_number(LUA, 4, gv)) {
        gv = 1.0;
    }
    if (!arg_number(LUA, 5, mv)) {
        mv = 1.0;
    }
    bool paused = LUA->IsType(6, LT::Bool) && LUA->GetBool(6);
    int n = g_jb->update(listener ? eye : nullptr, listener ? fwd : nullptr, listener ? up : nullptr, gv, mv, paused);
    LUA->PushNumber(n);
    return 1;
}

// gsa1.JukeboxState(ch [, out]) -> table | nil, message, code
GSA1_FN(gsa1_jukebox_State)
{
    int32_t ch = 0;
    if (!arg_int(LUA, 1, ch, 0, gsa1::kJukeboxChannels - 1)) {
        return push_nil_msg(LUA, "JukeboxState(channel 0..4)", "bad_argument");
    }
    gsa1::JbChannelInfo s = g_jb ? g_jb->state(ch) : gsa1::JbChannelInfo();
    int t = out_table(LUA, 2);
    raw_num(LUA, t, "music", s.music);
    raw_str(LUA, t, "state", gsa1::jb_state_name(s.state));
    raw_num(LUA, t, "position", s.position);
    raw_num(LUA, t, "length", s.length);
    raw_num(LUA, t, "loops_done", s.loops_done);
    raw_str(LUA, t, "error", jb_scrub(s.error));
    raw_num(LUA, t, "track_position", s.track_position);
    raw_num(LUA, t, "plan_length", s.plan_length);
    raw_str(LUA, t, "plan", gsa1::jb_plan_name(s.spec.plan));
    raw_num(LUA, t, "loops", s.spec.loops);
    raw_bool(LUA, t, "paused", s.paused);
    raw_num(LUA, t, "volume", s.volume);
    raw_bool(LUA, t, "placed", s.placed);
    raw_num(LUA, t, "queued", s.queued);
    return 1;
}

// gsa1.JukeboxStatus([out]) -> table
GSA1_FN(gsa1_jukebox_Status)
{
    gsa1::JbStatusInfo s = g_jb ? g_jb->status() : gsa1::JbStatusInfo();
    int t = out_table(LUA, 1);
    raw_bool(LUA, t, "ready", s.ready);
    raw_num(LUA, t, "tracks", s.tracks);
    raw_num(LUA, t, "active", s.active);
    raw_num(LUA, t, "memory_mb", s.memory_mb);
    raw_num(LUA, t, "max_open_ms", s.max_open_ms);
    raw_num(LUA, t, "underruns", (double)s.underruns);
    raw_str(LUA, t, "error", jb_scrub(!s.started && !g_jb_start_error.empty() ? g_jb_start_error : s.error));
    raw_bool(LUA, t, "started", s.started);
    raw_bool(LUA, t, "failed", s.failed);
    raw_num(LUA, t, "listed", s.listed);
    raw_bool(LUA, t, "titles", s.titles);
    raw_num(LUA, t, "recoveries", (double)s.recoveries);
    raw_num(LUA, t, "opens", (double)s.opens);
    raw_num(LUA, t, "list_ms", s.list_ms);
    raw_str(LUA, t, "backend", jb_scrub(s.backend));
    return 1;
}

// gsa1.AudioDuck(gain 0..1, duck_jingles) -> true | false, message, code
GSA1_FN(gsa1_jukebox_AudioDuck)
{
    double g = 1.0;
    if (!arg_number(LUA, 1, g) || g < 0.0 || g > 1.0 || !(absent(LUA, 2) || LUA->IsType(2, LT::Bool))) {
        return bad(LUA, "AudioDuck(gain 0..1, duck_jingles boolean)");
    }
    gsa1::Session *s = session();
    if (!s) {
        return push_false_msg(LUA, "the module failed to start");
    }
    bool jingles = LUA->IsType(2, LT::Bool) && LUA->GetBool(2);
    s->audio().set_duck((float)g, jingles);
    return ok_true(LUA);
}

namespace {

void jukebox_open(ILuaBase *L, int t)
{
    raw_num(L, t, "JUKEBOX_CHANNELS", gsa1::kJukeboxChannels);
}

// GMOD_MODULE_CLOSE, first of all (kCloseFirst): the worker's BASS streams go before the sound output and the session
void jukebox_close(ILuaBase *)
{
    if (g_jb) {
        g_jb->shutdown();
        delete g_jb;
        g_jb = nullptr;
    }
    g_jb_log = JbLog();
    g_jb_start_error.clear();
    g_jb_checked = -1e12;
}

const gsa1::FeatureFn k_jukebox_fns[] = {
    {"MusicList", gsa1_jukebox_MusicList},
    {"JukeboxPlay", gsa1_jukebox_Play},
    {"JukeboxStop", gsa1_jukebox_Stop},
    {"JukeboxPause", gsa1_jukebox_Pause},
    {"JukeboxSeek", gsa1_jukebox_Seek},
    {"JukeboxSync", gsa1_jukebox_Sync},
    {"JukeboxVolume", gsa1_jukebox_Volume},
    {"JukeboxPlace", gsa1_jukebox_Place},
    {"JukeboxUpdate", gsa1_jukebox_Update},
    {"JukeboxState", gsa1_jukebox_State},
    {"JukeboxStatus", gsa1_jukebox_Status},
    {"AudioDuck", gsa1_jukebox_AudioDuck},
};

}  // namespace

GSA1_FEATURE(jukebox, 1, k_jukebox_fns, jukebox_open, jukebox_close, gsa1::kCloseFirst);
