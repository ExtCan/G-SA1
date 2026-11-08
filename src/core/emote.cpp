// G-SA1 core: the shared part of the feature "emote" (round 0.9.4a, the end mode HOLD 0.9.4b; see emote.hpp).
#include "emote.hpp"

#include <cstdio>
#include <cstring>

namespace gsa1 {

uint32_t emote_pass_flags()
{
#if defined(SA1_API_EMOTE)
    uint32_t f = SA1_EMOTE_IN_AIR | SA1_EMOTE_KEEP_INPUT | SA1_EMOTE_NO_PROPS | SA1_EMOTE_NO_TRAIL;
#if defined(SA1_API_EMOTE_HOLD)
    f |= SA1_EMOTE_HOLD;    // round 0.9.4b: an emote that ends in a pose keeps its last frame (objects2_plan.md 11.2)
#endif
    return f;
#else
    return 0u;
#endif
}

bool emote_parse_key(const std::string &key, uint32_t &source, uint32_t &index)
{
    if (key.size() < 2 || key.size() > 4 || (key[0] != 'a' && key[0] != 'x' && key[0] != 'e')) {
        return false;
    }
    uint32_t v = 0;
    for (size_t i = 1; i < key.size(); i++) {
        char c = key[i];
        if (c < '0' || c > '9' || (i == 1 && c == '0' && key.size() > 2)) {
            return false;
        }
        v = v * 10u + (uint32_t)(c - '0');
    }
    if (v > kEmoteKeyMax) {
        return false;
    }
#if defined(SA1_API_EMOTE)
    source = key[0] == 'a' ? SA1_EMOTE_ROW : SA1_EMOTE_EXTRA;
#else
    source = key[0] == 'a' ? 0u : 1u;
#endif
    if (key[0] == 'e') {
        source = kEmoteSourceEvent;     // round 100-EV: "e<n>", a cutscene animation
    }
    index = v;
    return true;
}

std::string emote_key(uint32_t source, uint32_t index)
{
    return (source == 0u ? std::string("a") : source == kEmoteSourceEvent ? std::string("e") : std::string("x")) +
           std::to_string(index);
}

const char *emote_play_name(int32_t play, uint32_t flags)
{
#if defined(SA1_API_EMOTE)
    if (flags & SA1_EMOTE_F_HOLD) {
        return "hold";
    }
    return play == SA1_EMOTE_PLAY_LOOP ? "loop" : "once";
#else
    (void)flags;
    return play == 2 ? "loop" : "once";
#endif
}

const char *emote_class_name(uint32_t cls)
{
    static const char *const names[] = {"stand", "idle", "pose", "move", "air", "brake", "ball", "attack", "carry",
                                        "setpiece", "hurt", "fish", "swim", "board", "super", "cutscene"};
    return cls < sizeof names / sizeof names[0] ? names[cls] : "?";
}

bool emote_list(const sa1_context *ctx, int32_t kind, uint32_t form, std::vector<EmoteEntry> &out, std::string &err)
{
    out.clear();
#if defined(SA1_API_EMOTE)
    if (!ctx) {
        err = "G-SA1 is not initialised";
        return false;
    }
    if (kind < 0 || kind > 8 || form > SA1_EMOTE_FORM_SUPER) {
        err = "EmoteList(kind 0..8, form 0 / 1)";
        return false;
    }
    uint32_t n = sa1_emote_count(ctx, kind, form);
    out.reserve(n);
    for (uint32_t i = 0; i < n; i++) {
        sa1_emote_info info;
        std::memset(&info, 0, sizeof info);
        info.struct_size = sizeof info;
        sa1_status st = sa1_emote_get(ctx, kind, form, i, &info);
        if (SA1_FAILED(st)) {
            err = emote_error(ctx, st);
            out.clear();
            return false;
        }
        EmoteEntry e;
        e.source = info.source;
        e.index = info.index;
        e.key = emote_key(info.source, info.index);
        e.name = info.internal_name ? info.internal_name : "";
        e.label = info.label ? info.label : "";
        e.cls = info.emote_class;
        e.flags = info.flags;
        e.frames = info.frames;
        e.play = info.play;
        e.dup_of = info.dup_of;
#if defined(SA1_API_EMOTE_EVENT)
        // round 100-EV: the cutscene animations' fields (struct_size covers them in libsa1 0.6)
        if (info.source == SA1_EMOTE_EVENT) {
            e.event = info.event;
            e.event_order = info.event_order;
            e.cast = info.cast;
            e.pace = info.pace;
            e.lift = info.lift;
            for (uint32_t k = 0; info.events && k < info.num_events; k++) {
                e.events.push_back(info.events[k]);
            }
        }
#endif
        out.push_back(e);
    }
    return true;
#else
    (void)ctx;
    (void)kind;
    (void)form;
    err = "this libsa1 has no emotes (round 0.9.4a, SA1_API_EMOTE)";
    return false;
#endif
}

sa1_status emote_play(sa1_context *ctx, int32_t id, uint32_t source, uint32_t index, uint32_t flags)
{
#if defined(SA1_API_EMOTE)
    if (!ctx) {
        return SA1_ERR_NOT_LOADED;
    }
    sa1_emote e;
    std::memset(&e, 0, sizeof e);
    e.struct_size = sizeof e;
    e.count = 1;
    e.items[0].source = source;
    e.items[0].index = index;
    e.items[0].play = (flags & kEmoteLoop) ? SA1_EMOTE_PLAY_LOOP : SA1_EMOTE_PLAY_DEFAULT;
    e.items[0].speed = 0.0f;
    e.link = -1;
    e.flags = SA1_EMOTE_CHAIN | (flags & emote_pass_flags());
    return sa1_character_emote(ctx, id, &e);
#else
    (void)ctx;
    (void)id;
    (void)source;
    (void)index;
    (void)flags;
    return SA1_ERR_UNSUPPORTED;
#endif
}

sa1_status emote_stop(sa1_context *ctx, int32_t id, uint32_t how)
{
#if defined(SA1_API_EMOTE)
    if (!ctx) {
        return SA1_ERR_NOT_LOADED;
    }
    return sa1_character_emote_stop(ctx, id, how);
#else
    (void)ctx;
    (void)id;
    (void)how;
    return SA1_ERR_UNSUPPORTED;
#endif
}

std::string emote_notes(const EmoteEntry &e)
{
    std::string s;
    auto add = [&s](const char *w) {
        if (!s.empty()) s += ", ";
        s += w;
    };
#if defined(SA1_API_EMOTE_EVENT)
    if (e.flags & SA1_EMOTE_F_ROOT_MOVES) add("moves away");
    if (e.flags & SA1_EMOTE_F_LIFTED) add("lifted onto the floor");
    if (e.flags & SA1_EMOTE_F_RESTS_ON) add("made to sit on something");
#endif
    if (e.events.size() > 1) {
        add(("in " + std::to_string(e.events.size()) + " cutscenes").c_str());
    }
    return s;
}

std::vector<std::string> emote_cast_names(uint32_t cast)
{
    // SA1_CHAR_* order; the names G-SA1's character table uses for these kinds
    static const char *const names[9] = {"sonic", "eggman", "tails", "knuckles", "tikal", "amy", "gamma", "big", "supersonic"};
    std::vector<std::string> out;
    for (uint32_t k = 0; k < 9u; k++) {
        if (cast & (1u << k)) out.push_back(names[k]);
    }
    return out;
}

std::string emote_event_error(sa1_status st, uint32_t event)
{
    char ev[16];
    std::snprintf(ev, sizeof ev, "EV%04X.PRS", (unsigned)event & 0xFFFFu);
    switch (st) {
    case SA1_ERR_BAD_HASH: return std::string("your disc's ") + ev + " does not match the US 1.005 disc";
    case SA1_ERR_BAD_FORMAT: return std::string("your disc's ") + ev + " cannot be read as the cutscene's file";
    case SA1_ERR_IO: return std::string("could not read ") + ev + " from the disc";
    case SA1_ERR_NOT_LOADED: return "the disc is not loaded";
    case SA1_ERR_OUT_OF_MEMORY: return "out of memory";
    default: {
        const char *s = sa1_status_string(st);
        return std::string("cannot load ") + ev + ": " + (s ? s : "error");
    }
    }
}

bool EmoteEventPool::queue(sa1_context *ctx, int32_t kind, uint32_t index)
{
#if defined(SA1_API_EMOTE_EVENT)
    if (!ctx) return false;
    std::lock_guard<std::mutex> lk(m_);
    if (q_.size() >= 1024u) return false;
    if (busy_ && cur_.ctx == ctx && cur_.kind == kind && cur_.index == index) return true;
    for (const Job &j : q_) {
        if (j.ctx == ctx && j.kind == kind && j.index == index) return true;
    }
    q_.push_back(Job{ctx, kind, index});
    queued_ = queued_ + 1;
    stop_ = false;
    if (!t_.joinable()) {
        t_ = std::thread([this] { run(); });
    }
    cv_.notify_one();
    return true;
#else
    (void)ctx;
    (void)kind;
    (void)index;
    return false;
#endif
}

void EmoteEventPool::run()
{
#if defined(SA1_API_EMOTE_EVENT)
    std::unique_lock<std::mutex> lk(m_);
    for (;;) {
        cv_.wait(lk, [this] { return stop_ || !q_.empty(); });
        if (stop_) break;
        cur_ = q_.front();
        q_.pop_front();
        busy_ = true;
        lk.unlock();
        sa1_status st = sa1_emote_event_ready(cur_.ctx, cur_.kind, cur_.index) == 1
                            ? SA1_OK
                            : sa1_emote_event_load(cur_.ctx, cur_.kind, cur_.index);
        lk.lock();
        last_ = st;
        done_ = done_ + 1;
        busy_ = false;
        cv_.notify_all();
    }
#endif
}

void EmoteEventPool::drain()
{
    {
        std::unique_lock<std::mutex> lk(m_);
        dropped_ = dropped_ + q_.size();
        q_.clear();
        stop_ = true;
        cv_.notify_all();
    }
    if (t_.joinable()) {
        t_.join();     // the load that runs finishes first (one file: milliseconds)
    }
    std::lock_guard<std::mutex> lk(m_);
    stop_ = false;
}

size_t EmoteEventPool::waiting()
{
    std::lock_guard<std::mutex> lk(m_);
    return q_.size() + (busy_ ? 1u : 0u);
}

std::string emote_error(const sa1_context *ctx, sa1_status st)
{
    const char *e = ctx ? sa1_last_error(ctx) : nullptr;
    if (e && *e) {
        return e;
    }
    const char *s = sa1_status_string(st);
    return s ? s : "error";
}

const char *emote_code(sa1_status st)
{
    switch (st) {
    case SA1_ERR_UNSUPPORTED: return "unsupported";
    case SA1_ERR_INVALID_ARGUMENT: return "bad_argument";
    case SA1_ERR_NOT_FOUND: return "not_found";
    case SA1_ERR_LIMIT: return "limit";
    case SA1_ERR_NOT_LOADED: return "not_ready";
#if defined(SA1_ERR_GAME_FAULT)
    case SA1_ERR_GAME_FAULT:
#endif
    case SA1_ERR_NOT_IMPLEMENTED: return "fault";
    default: return "error";
    }
}

}  // namespace gsa1
