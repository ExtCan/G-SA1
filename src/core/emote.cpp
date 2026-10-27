// G-SA1 core: the shared part of the feature "emote" (round 0.9.4a, the end mode HOLD 0.9.4b; see emote.hpp).
#include "emote.hpp"

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
    if (key.size() < 2 || key.size() > 4 || (key[0] != 'a' && key[0] != 'x')) {
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
    index = v;
    return true;
}

std::string emote_key(uint32_t source, uint32_t index)
{
    return (source == 0u ? std::string("a") : std::string("x")) + std::to_string(index);
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
                                        "setpiece", "hurt", "fish", "swim", "board", "super"};
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
