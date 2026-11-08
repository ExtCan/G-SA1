// G-SA1 core: the feature "frontend" (round 0.9.8; sadc docs/research/gsa1_098_plan.md 5.5, 6.10 with its review R98.11, R98.20;
// charsel098.md 6.6; libsa1's "the game's own front end", SA1_API_FRONTEND). No GMod dependency: the module's bind_frontend.cpp
// and the offline tests drive exactly this code.
//
// One private libsa1 world per open runs the game's menu overlay ADVERTISE: Character Select, run by the game's own code. Here:
// the one open front end of the session's context, its events split into what goes to the mixer (the game's sounds and voices,
// through Audio::event) and what goes to Lua (select, pick, done, cancel, music: the host's jukebox plays the music, so there is
// exactly one source of it whatever gsa1_sound_bgm says), and a gsa1::Character used only as a render-state holder (no world:
// Session::rebatch / Session::prepare_view and the module's EmitBatch loop work on it as on a character's last render).
//
// Game thread only, between ticks: never inside a character's tick, outside the parallel contract (the plan's A11). libsa1 closes
// an open front end on sa1_unload_disc and sa1_shutdown, so the pointer here goes before either (R98.20): close() from the
// feature's close and shutdown hooks; forget() for a context that is gone.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "libsa1_internal_api.hpp"
#include "session.hpp"

#if defined(SA1_API_FRONTEND)
#define GSA1_HAS_FRONTEND 1
#endif

namespace gsa1 {
namespace frontend {

#if defined(GSA1_HAS_FRONTEND)
const bool kAvailable = true;
#else
const bool kAvailable = false;
#endif

// the host's music requests: the game's background music request is an SA1_EVENT_JINGLE whose arg names the game's call; these
// two calls mean "stop", as does id 0 (libsa1's frontend_test: "JINGLE id 0 = the music stop")
const uint32_t kMusicStop = 0x8C107ADAu;     // the game's music stop
const uint32_t kMusicStop2 = 0x8C107AAAu;    // the menu's own stop request (charsel098 6.5)

// what Lua hears of a front end
struct Event {
    enum Kind : int { Select = 0, Pick, Done, Cancel, Music };
    Kind kind = Select;
    int32_t id = -1;                    // the slot (-1: none); Music: the track (-1: stop)
};
const char *event_name(Event::Kind k);

struct Stats {
    uint64_t opens = 0, closes = 0, ticks = 0, frames = 0, sounds = 0, voices = 0, faults = 0;
    int64_t last_voice = -1, last_sound = -1;
    double open_ms = 0.0, tick_ms_last = 0.0, tick_ms_max = 0.0;
    std::string last_error;
};

// the angles (degrees: pitch, yaw, roll, Source's order) of a view with this forward and up
void view_angles(const float forward[3], const float up[3], float out[3]);

#if defined(GSA1_HAS_FRONTEND)
class Frontend {
public:
    // the context the open front end belongs to: another context (or none) forgets it (libsa1 freed it with that context)
    void bind(const void *ctx);
    // forgets the front end without calling libsa1 (the context is gone)
    void forget();
    // SA1_ERR_LIMIT with one open; SA1_ERR_NOT_LOADED without the disc; slot 0..6 (the first selection), language 0 Japanese,
    // 1 English; dialog: the game's own dialog (SA1_FRONTEND_SHOW_DIALOG)
    sa1_status open(Session &se, int32_t slot, int32_t language, bool dialog, std::string &err);
    void close();
    bool is_open() const { return fe_ != nullptr; }
#if defined(SA1_API_SKIN)
    // 0.9.9f (sa1_frontend_set_skin; nullptr: Sonic): voiceless: slot 0's voices stay out of the mixer while it is on (metal099e.md 4.5)
    sa1_status set_skin(const sa1_skin_desc *skin, bool voiceless, std::string &err);
#endif
#if defined(SA1_API_SKIN) && SA1_API_SKIN >= 3
    // 1.0.0-beta1 (sa1_frontend_set_upgrade_models; sadc docs/research/gsa1_100_select.md 4.3.3): the display set of the upgrades in the menu's world, for the TUs of
    // `kind` (SA1_CHAR_*); value 0 = the game, SA1_UPGRADE_MODELS_ON | bits = these upgrades' parts
    sa1_status set_upgrade_models(int32_t kind, uint32_t value, std::string &err);
#endif
    // whole frames of 1/60 s for dt (libsa1 keeps the rest; at most 8); buttons: SA1_FRONTEND_B_*
    sa1_status tick(float dt, float sx, float sy, uint32_t buttons, uint32_t &frames, std::string &err);
    sa1_status state(sa1_frontend_state &out, std::string &err);
    // pops libsa1's events: sounds and voices go to audio (nullptr: dropped), the rest into out (cleared first)
    sa1_status events(Audio *audio, std::vector<Event> &out, std::string &err);
    // the last frame's 2D draws (library-owned, valid until the next tick or close)
    sa1_status screen(const sa1_screen *&out, std::string &err);
    // the selected slot's 3D draws of the last frame into the holder and its batches, when they changed; kind: their texture kind
    sa1_status render(Session &se, int32_t &kind, std::string &err);
    sa1_status view(float eye[3], float forward[3], float up[3], float &fov, std::string &err);
    Character &holder() { return holder_; }
    int32_t render_kind() const { return render_kind_; }
    const Stats &stats() const { return st_; }

private:
    sa1_status fail(sa1_status st, const char *what, std::string &err);

    const void *ctx_ = nullptr;
    sa1_context *live_ctx_ = nullptr;
    sa1_frontend *fe_ = nullptr;
    bool skin_on_ = false, skin_voiceless_ = false;
    Character holder_;
    int32_t render_kind_ = -1;
    bool rendered_ = false;
    std::vector<sa1_event> buf_;
    Stats st_;
};
#endif

}  // namespace frontend
}  // namespace gsa1
