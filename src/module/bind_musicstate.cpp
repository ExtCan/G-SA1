// G-SA1 module: the game's music state, feature "musicstate" (round 0.9.1: sadc docs/research/gsa1_070_drown.md J1 with
// its review R4.4; libsa1_audio.h header version 4, sa1_audio_mixer_music_state). What the game's music does in the
// module's mixer - the jingle that replaces the background music now (the drowning countdown, invincibility, speed
// shoes, fishing), its kind, length and time left, the game's music stop at the drown - so the addon's jukebox
// (feat/cl_jukebox.lua) can pause while the game plays a jingle and carry on afterwards. The 1-up is a sound effect
// (tone 704), not a jingle: it never shows here.
//
// Lua API (feature version 1; GSA1.HasFeature("musicstate")):
//   gsa1.AudioMusicState([out]) -> out | nil, message, code
//       out (filled in place, no garbage): {jingle (music number, -1 none; -1 always with the jingles off), left
//       (seconds until it ends by itself; -1 while it loops or its length is not known yet), stopped (bool: after the
//       game's music stop - the drown - until its next music cue), bgm (the background music the game asked for, -1),
//       kind (gsa1.MUSIC_STATE.JINGLE_*), waiting (bool: not heard yet), loops (bool), length, time (seconds), started,
//       ended (counters), last_jingle (-1), last_end (gsa1.MUSIC_STATE.END_*), bgm_playing (bool), name (the jingle's
//       file, "TIMER.ADX"; "" without a jingle)}. nil, message, "not_open" while the sound banks are not open (the
//       game's sound off, or still opening); "unsupported" with a libsa1 older than audio header 4.
//   gsa1.AudioMusicEnd() -> true | false, message: ends the game's music in the mixer - its jingle and the music stop -
//       with every sound (sa1_audio_mixer_stop(mixer, 0)): the character whose world played it is gone.
//   gsa1.MUSIC_STATE = {JINGLE_NONE, JINGLE_OTHER, JINGLE_COUNTDOWN, JINGLE_INVINCIBLE, JINGLE_SPEED_UP, JINGLE_FISHING,
//       JINGLE_FISH_CAUGHT, JINGLE_FISH_LOST, JINGLE_ITEM, JINGLE_CONTINUE, END_NONE, END_PLAYED, END_RESTORE, END_STOP,
//       END_MUSIC, END_REPLACED, END_HOST, END_FAILED, HEADER_VERSION}
// The mixer runs on the Lua thread (gsa1.AudioUpdate renders it there), so these calls need no lock.
#include <string>

#include "GarrysMod/Lua/Interface.h"

#include "../core/audio.hpp"
#include "gsa1_feature.hpp"
#include "gsa1_module_internal.hpp"

using GarrysMod::Lua::ILuaBase;
using namespace gsa1::mod;

// gsa1.AudioMusicState([out]) -> out | nil, message, code
GSA1_FN(gsa1_musicstate_AudioMusicState)
{
#if defined(SA1_AUDIO_HEADER_VERSION) && SA1_AUDIO_HEADER_VERSION >= 4
    gsa1::Session *se = session();
    if (!se) {
        return push_nil_msg(LUA, "the module failed to start", "not_ready");
    }
    gsa1::MusicState s;
    if (!se->audio().music_state(s)) {
        return push_nil_msg(LUA, "the game's sound is not open", "not_open");
    }
    int t = out_table(LUA, 1);
    raw_num(LUA, t, "jingle", s.jingle);
    raw_num(LUA, t, "left", s.jingle_left);
    raw_bool(LUA, t, "stopped", s.stopped);
    raw_num(LUA, t, "bgm", s.bgm);
    raw_num(LUA, t, "kind", s.kind);
    raw_bool(LUA, t, "waiting", s.waiting);
    raw_bool(LUA, t, "loops", s.loops);
    raw_num(LUA, t, "length", s.length);
    raw_num(LUA, t, "time", s.time);
    raw_num(LUA, t, "started", s.started);
    raw_num(LUA, t, "ended", s.ended);
    raw_num(LUA, t, "last_jingle", s.last_jingle);
    raw_num(LUA, t, "last_end", s.last_end);
    raw_bool(LUA, t, "bgm_playing", s.bgm_playing);
    raw_str(LUA, t, "name", s.jingle >= 0 ? se->audio().music_name(s.jingle) : std::string());
    return 1;
#else
    return push_nil_msg(LUA, "this module was built with a libsa1 older than audio header 4", "unsupported");
#endif
}

// gsa1.AudioMusicEnd() -> true | false, message
GSA1_FN(gsa1_musicstate_AudioMusicEnd)
{
    gsa1::Session *se = session();
    if (!se) {
        return push_false_msg(LUA, "the module failed to start", "not_ready");
    }
    if (!se->audio().end_music()) {
        return push_false_msg(LUA, "the game's sound is not open", "not_open");
    }
    LUA->PushBool(true);
    return 1;
}

namespace {

void musicstate_open(ILuaBase *L, int t)
{
    L->PushString("MUSIC_STATE");
    L->CreateTable();
    int c = L->Top();
#if defined(SA1_AUDIO_HEADER_VERSION) && SA1_AUDIO_HEADER_VERSION >= 4
    raw_num(L, c, "JINGLE_NONE", SA1_AUDIO_JINGLE_NONE);
    raw_num(L, c, "JINGLE_OTHER", SA1_AUDIO_JINGLE_OTHER);
    raw_num(L, c, "JINGLE_COUNTDOWN", SA1_AUDIO_JINGLE_COUNTDOWN);
    raw_num(L, c, "JINGLE_INVINCIBLE", SA1_AUDIO_JINGLE_INVINCIBLE);
    raw_num(L, c, "JINGLE_SPEED_UP", SA1_AUDIO_JINGLE_SPEED_UP);
    raw_num(L, c, "JINGLE_FISHING", SA1_AUDIO_JINGLE_FISHING);
    raw_num(L, c, "JINGLE_FISH_CAUGHT", SA1_AUDIO_JINGLE_FISH_CAUGHT);
    raw_num(L, c, "JINGLE_FISH_LOST", SA1_AUDIO_JINGLE_FISH_LOST);
    raw_num(L, c, "JINGLE_ITEM", SA1_AUDIO_JINGLE_ITEM);
    raw_num(L, c, "JINGLE_CONTINUE", SA1_AUDIO_JINGLE_CONTINUE);
    raw_num(L, c, "END_NONE", SA1_AUDIO_JINGLE_END_NONE);
    raw_num(L, c, "END_PLAYED", SA1_AUDIO_JINGLE_END_PLAYED);
    raw_num(L, c, "END_RESTORE", SA1_AUDIO_JINGLE_END_RESTORE);
    raw_num(L, c, "END_STOP", SA1_AUDIO_JINGLE_END_STOP);
    raw_num(L, c, "END_MUSIC", SA1_AUDIO_JINGLE_END_MUSIC);
    raw_num(L, c, "END_REPLACED", SA1_AUDIO_JINGLE_END_REPLACED);
    raw_num(L, c, "END_HOST", SA1_AUDIO_JINGLE_END_HOST);
    raw_num(L, c, "END_FAILED", SA1_AUDIO_JINGLE_END_FAILED);
    raw_num(L, c, "HEADER_VERSION", SA1_AUDIO_HEADER_VERSION);
#else
    raw_num(L, c, "HEADER_VERSION", 0);
#endif
    L->RawSet(t);
}

const gsa1::FeatureFn k_musicstate_fns[] = {
    {"AudioMusicState", gsa1_musicstate_AudioMusicState},
    {"AudioMusicEnd", gsa1_musicstate_AudioMusicEnd},
};

}  // namespace

GSA1_FEATURE(musicstate, 1, k_musicstate_fns, musicstate_open, nullptr, gsa1::kCloseDefault);
