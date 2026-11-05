// G-SA1 core: the feature "frontend": see frontend.hpp.
#include "frontend.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

#include "preview.hpp"
#include "util.hpp"

namespace gsa1 {
namespace frontend {

const char *event_name(Event::Kind k)
{
    switch (k) {
    case Event::Select:
        return "select";
    case Event::Pick:
        return "pick";
    case Event::Done:
        return "done";
    case Event::Cancel:
        return "cancel";
    case Event::Music:
        return "music";
    }
    return "?";
}

// Source's AngleVectors backwards. forward = (cp cy, cp sy, -sp); at roll 0 right0 = (sy, -cy, 0), up0 = (sp cy, sp sy, cp); a roll r
// makes up = cos r up0 + sin r right0
void view_angles(const float f[3], const float u[3], float out[3])
{
    const double kDeg = 180.0 / 3.14159265358979323846;
    double fl = std::sqrt((double)f[0] * f[0] + (double)f[1] * f[1] + (double)f[2] * f[2]);
    if (!(fl > 1e-9)) {
        out[0] = out[1] = out[2] = 0.0f;
        return;
    }
    double fx = f[0] / fl, fy = f[1] / fl, fz = f[2] / fl;
    double yaw = std::atan2(fy, fx);
    double pitch = std::atan2(-fz, std::sqrt(fx * fx + fy * fy));
    double sy = std::sin(yaw), cy = std::cos(yaw), sp = std::sin(pitch), cp = std::cos(pitch);
    double sr = (double)u[0] * sy - (double)u[1] * cy;
    double cr = (double)u[0] * sp * cy + (double)u[1] * sp * sy + (double)u[2] * cp;
    double roll = (sr == 0.0 && cr == 0.0) ? 0.0 : std::atan2(sr, cr);
    out[0] = (float)(pitch * kDeg);
    out[1] = (float)(yaw * kDeg);
    out[2] = (float)(roll * kDeg);
}

#if defined(GSA1_HAS_FRONTEND)

sa1_status Frontend::fail(sa1_status st, const char *what, std::string &err)
{
    const char *e = live_ctx_ ? sa1_last_error(live_ctx_) : nullptr;
    err = format("%s: %s", what, e && *e ? e : sa1_status_string(st));
    st_.last_error = err;
    if (st == SA1_ERR_GAME_FAULT) {
        st_.faults++;
    }
    return st;
}

void Frontend::bind(const void *ctx)
{
    if (ctx != ctx_) {
        forget();
        ctx_ = ctx;
    }
}

void Frontend::forget()
{
    fe_ = nullptr;
    live_ctx_ = nullptr;
    ctx_ = nullptr;
    rendered_ = false;
    render_kind_ = -1;
}

sa1_status Frontend::open(Session &se, int32_t slot, int32_t language, bool dialog, std::string &err)
{
    sa1_context *ctx = se.ready() ? se.ctx() : nullptr;
    bind(ctx);
    if (!ctx) {
        err = "G-SA1 is not initialised (the disc is not loaded yet)";
        return SA1_ERR_NOT_LOADED;
    }
    if (fe_) {
        err = "a front end is open already";
        return SA1_ERR_LIMIT;
    }
    live_ctx_ = ctx;
    sa1_frontend_desc d;
    std::memset(&d, 0, sizeof d);
    d.struct_size = sizeof d;
    d.flags = dialog ? SA1_FRONTEND_SHOW_DIALOG : 0u;
    d.language = language;
    d.slot = slot;
    d.open_slots = ~0u;             // G-SA1 has no lock: every slot, the game's own switch (7 slots)
    double t0 = now_ms();
    sa1_status st = sa1_frontend_open(ctx, &d, &fe_);
    st_.open_ms = now_ms() - t0;
    if (st != SA1_OK || !fe_) {
        fe_ = nullptr;
        return fail(st != SA1_OK ? st : SA1_ERR_NOT_FOUND, "sa1_frontend_open", err);
    }
    st_.opens++;
    holder_.kind = 0;
    holder_.id = 0;
    holder_.rendered = false;
    rendered_ = false;
    render_kind_ = -1;
    return SA1_OK;
}

#if defined(SA1_API_SKIN)
sa1_status Frontend::set_skin(const sa1_skin_desc *skin, bool voiceless, std::string &err)
{
    if (!fe_) {
        err = "the front end is not open";
        return SA1_ERR_NOT_LOADED;
    }
    sa1_status st = sa1_frontend_set_skin(fe_, skin);
    if (st != SA1_OK) {
        return fail(st, "sa1_frontend_set_skin", err);
    }
    skin_on_ = skin != nullptr;
    skin_voiceless_ = skin_on_ && voiceless;
    rendered_ = false;      // the holder batches again with the archive it may keep
    return SA1_OK;
}
#endif

void Frontend::close()
{
    if (fe_) {
        sa1_frontend_close(fe_);
        fe_ = nullptr;
        st_.closes++;
    }
    skin_on_ = skin_voiceless_ = false;
    rendered_ = false;
    render_kind_ = -1;
}

sa1_status Frontend::tick(float dt, float sx, float sy, uint32_t buttons, uint32_t &frames, std::string &err)
{
    frames = 0;
    if (!fe_) {
        err = "no front end is open";
        return SA1_ERR_NOT_FOUND;
    }
    sa1_frontend_input in;
    std::memset(&in, 0, sizeof in);
    in.struct_size = sizeof in;
    in.stick_x = sx;
    in.stick_y = sy;
    in.buttons = buttons;
    double t0 = now_ms();
    sa1_status st = sa1_frontend_tick(fe_, dt, &in, &frames);
    double ms = now_ms() - t0;
    if (st != SA1_OK) {
        return fail(st, "sa1_frontend_tick", err);
    }
    st_.ticks++;
    st_.frames += frames;
    st_.tick_ms_last = ms;
    st_.tick_ms_max = std::max(st_.tick_ms_max, ms);
    return SA1_OK;
}

sa1_status Frontend::state(sa1_frontend_state &out, std::string &err)
{
    std::memset(&out, 0, sizeof out);
    out.struct_size = sizeof out;
    if (!fe_) {
        err = "no front end is open";
        return SA1_ERR_NOT_FOUND;
    }
    sa1_status st = sa1_frontend_state_get(fe_, &out);
    return st == SA1_OK ? st : fail(st, "sa1_frontend_state_get", err);
}

sa1_status Frontend::events(Audio *audio, std::vector<Event> &out, std::string &err)
{
    out.clear();
    if (!fe_) {
        err = "no front end is open";
        return SA1_ERR_NOT_FOUND;
    }
    if (buf_.empty()) {
        buf_.resize(256);
    }
    for (;;) {
        uint32_t n = 0;
        sa1_status st = sa1_frontend_poll(fe_, buf_.data(), (uint32_t)buf_.size(), &n);
        if (st != SA1_OK) {
            return fail(st, "sa1_frontend_poll", err);
        }
        bool mute_voices = false;
#if defined(SA1_API_SKIN)
        if (skin_on_ && skin_voiceless_) {
            sa1_frontend_state fs;
            std::memset(&fs, 0, sizeof fs);
            fs.struct_size = sizeof fs;
            mute_voices = sa1_frontend_state_get(fe_, &fs) == SA1_OK && fs.slot == 0;
        }
#endif
        for (uint32_t i = 0; i < n; i++) {
            const sa1_event &e = buf_[i];
            switch (e.type) {
            case SA1_EVENT_SOUND:
            case SA1_EVENT_SOUND_STOP:
            case SA1_EVENT_VOICE:
                if (e.type == SA1_EVENT_SOUND) {
                    st_.sounds++;
                    st_.last_sound = e.id;
                } else if (e.type == SA1_EVENT_VOICE) {
                    st_.voices++;
                    st_.last_voice = e.id;
                }
                if (audio && !(mute_voices && voice_class(e))) {
                    audio->event(e);
                }
                break;
            case SA1_EVENT_JINGLE: {
                // never the mixer: the host's jukebox plays the music (one source of it, RC2)
                Event v;
                v.kind = Event::Music;
                v.id = (e.arg == kMusicStop || e.arg == kMusicStop2 || e.id == 0u) ? -1 : (int32_t)e.id;
                out.push_back(v);
                break;
            }
            case SA1_EVENT_FRONTEND: {
                Event v;
                v.id = (int32_t)e.id;
                bool known = true;
                switch (e.arg) {
                case SA1_FRONTEND_EV_SELECT:
                    v.kind = Event::Select;
                    break;
                case SA1_FRONTEND_EV_PICK:
                    v.kind = Event::Pick;
                    break;
                case SA1_FRONTEND_EV_DONE:
                    v.kind = Event::Done;
                    break;
                case SA1_FRONTEND_EV_CANCEL:
                    v.kind = Event::Cancel;
                    break;
                default:
                    known = false;
                    break;
                }
                if (known) {
                    out.push_back(v);
                }
                break;
            }
            default:
                break;
            }
        }
        if (n < buf_.size()) {
            break;
        }
    }
    return SA1_OK;
}

sa1_status Frontend::screen(const sa1_screen *&out, std::string &err)
{
    out = nullptr;
    if (!fe_) {
        err = "no front end is open";
        return SA1_ERR_NOT_FOUND;
    }
    sa1_status st = sa1_frontend_screen(fe_, &out);
    if (st != SA1_OK || !out) {
        return fail(st != SA1_OK ? st : SA1_ERR_NOT_FOUND, "sa1_frontend_screen", err);
    }
    return SA1_OK;
}

sa1_status Frontend::render(Session &se, int32_t &kind, std::string &err)
{
    kind = render_kind_;
    if (!fe_) {
        err = "no front end is open";
        return SA1_ERR_NOT_FOUND;
    }
    const sa1_render *r = nullptr;
    int32_t k = 0;
    sa1_status st = sa1_frontend_render(fe_, &r, &k);
    if (st != SA1_OK || !r) {
        return fail(st != SA1_OK ? st : SA1_ERR_NOT_FOUND, "sa1_frontend_render", err);
    }
    kind = k;
    if (rendered_ && k == render_kind_ && r->generation == holder_.r_gen) {
        return SA1_OK;              // the same frame: the holder's batches and prepared view stay
    }
    preview::copy_render(holder_, *r);
    holder_.kind = k;
    // the kind's texture archives (Session::build_batches keeps a draw's texture only below this count)
    uint32_t na = 0;
    if (k == SA1_KIND_FRONTEND) {
        std::string ignored;
        uint32_t count = 0;
        while (na < 64u && se.texture_count(k, na, count, ignored)) {
            na++;
        }
    } else {
        na = se.texture_archives(k);
    }
    holder_.num_archives = na;
#if defined(SA1_API_SKIN)
    // (metal099e.md RM.4: build_batches tests the holder's flag: without it he is white on this screen only)
    holder_.create_extra = skin_on_ ? SA1_CREATE_SKIN : 0u;
#endif
    se.rebatch(holder_);
    holder_.view_ready = false;
    rendered_ = true;
    render_kind_ = k;
    return SA1_OK;
}

sa1_status Frontend::view(float eye[3], float forward[3], float up[3], float &fov, std::string &err)
{
    if (!fe_) {
        err = "no front end is open";
        return SA1_ERR_NOT_FOUND;
    }
    sa1_status st = sa1_frontend_view(fe_, eye, forward, up, &fov);
    return st == SA1_OK ? st : fail(st, "sa1_frontend_view", err);
}

#endif  // GSA1_HAS_FRONTEND

}  // namespace frontend
}  // namespace gsa1
