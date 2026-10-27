// G-SA1 core: sound (see audio.hpp).
#include "audio.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

#include "util.hpp"

namespace gsa1 {

// ---- Audio: libsa1's mixer --------------------------------------------------------------------------------------
Audio::~Audio()
{
    shutdown();
}

static uint32_t mix_flags(const AudioOptions &o)
{
    uint32_t f = (o.bgm ? SA1_AUDIO_MIX_MUSIC : 0u) | (o.jingles ? 0u : SA1_AUDIO_MIX_NO_JINGLES) |
                 (o.voices ? 0u : SA1_AUDIO_MIX_NO_VOICES) | (o.voices_3d ? SA1_AUDIO_MIX_3D_VOICES : 0u);
#if defined(SA1_AUDIO_MIX_RESTART_REPEATS)
    // 0.9.4a (super2_plan.md 10.3): the same one-shot tone of a character restarts instead of piling up (the rings)
    if (o.restart_repeats) {
        f |= SA1_AUDIO_MIX_RESTART_REPEATS;
    }
#endif
    return f;
}

static void close_handle(Audio::Handle &h)
{
    if (h.mixer) {
        sa1_audio_mixer_destroy(h.mixer);
        h.mixer = nullptr;
    }
    if (h.audio) {
        sa1_audio_close(h.audio);   // joins libsa1's loader thread
        h.audio = nullptr;
    }
    if (h.ctx) {
        sa1_shutdown(h.ctx);
        h.ctx = nullptr;
    }
}

// on a worker: a private context (default allocator and files: thread-safe; the SOURCE coordinates the mixer's
// positions are in), the sound banks and a mixer
static bool open_handle(const std::string &gdi, bool japanese, uint32_t flags, AudioLogFn log, void *user,
                        Audio::Handle &h, std::string &err, std::string &notes)
{
    sa1_host host;
    sa1_host_defaults(&host);
    host.user = user;
    host.log = log;
    host.log_level = SA1_LOG_INFO;
    sa1_status st = sa1_init(&host, &h.ctx);
    if (SA1_FAILED(st) || !h.ctx) {
        h.ctx = nullptr;
        err = format("sa1_init: %s", sa1_status_string(st));
        return false;
    }
    sa1_coords co;
    std::memset(&co, 0, sizeof co);
    co.struct_size = sizeof co;
    sa1_coords_preset(SA1_COORDS_PRESET_SOURCE, &co);
    sa1_set_coords(h.ctx, &co);
    sa1_audio_desc d;
    std::memset(&d, 0, sizeof d);
    d.struct_size = sizeof d;
    d.gdi_path = gdi.c_str();
    d.flags = japanese ? SA1_AUDIO_JAPANESE : 0u;
    d.stage = SA1_AUDIO_STAGE_DEFAULT;
    d.characters = 0;
    st = sa1_audio_open(h.ctx, &d, &h.audio);
    if (SA1_FAILED(st) || !h.audio) {
        h.audio = nullptr;
        err = format("sa1_audio_open: %s: %s", sa1_status_string(st), sa1_last_error(h.ctx));
        close_handle(h);
        return false;
    }
    sa1_audio_mixer_desc md;
    std::memset(&md, 0, sizeof md);
    md.struct_size = sizeof md;
    md.sample_rate = Audio::kRate;
    md.flags = flags;
    md.max_voices = 0;
    sa1_status ms = sa1_audio_mixer_create(h.audio, &md, &h.mixer);
    if (SA1_FAILED(ms) || !h.mixer) {
        h.mixer = nullptr;
        err = format("sa1_audio_mixer_create: %s", sa1_status_string(ms));
        close_handle(h);
        return false;
    }
    notes = st == SA1_PARTIAL ? "some sound banks or the voice archive are missing (see the log)" : "";
    return true;
}

void Audio::close_later(Handle h)
{
    if (!h.ctx && !h.audio && !h.mixer) {
        return;
    }
    std::unique_ptr<Worker> w(new Worker());
    w->start([h]() mutable { close_handle(h); });
    graveyard_.add(std::move(w));
}

// the open that is running is not wanted any more: its worker closes what it opens, or its result is closed here
void Audio::abandon_pending()
{
    if (!pending_) {
        return;
    }
    Handle h;
    {
        std::lock_guard<std::mutex> g(pending_->m);
        pending_->abandoned = true;
        if (pending_->done) {
            h = pending_->h;
            pending_->h = Handle();
        }
    }
    close_later(h);
    if (pending_worker_) {
        graveyard_.add(std::move(pending_worker_));
    }
    pending_.reset();
}

void Audio::open_async(const std::string &gdi, bool japanese)
{
    abandon_pending();
    Handle old = cur_;
    cur_ = Handle();
    close_later(old);
    graveyard_.reap();
    open_error_.clear();
    auto p = std::make_shared<Pending>();
    p->japanese = japanese;
    pending_ = p;
    pending_t0_ = now_ms();
    uint32_t flags = mix_flags(opt_);
    AudioLogFn log = log_fn_;
    void *user = log_user_;
    std::string path = gdi;
    pending_worker_.reset(new Worker());
    pending_worker_->start([p, path, japanese, flags, log, user]() {
        double t0 = now_ms();
        Handle h;
        std::string err, notes;
        bool ok = open_handle(path, japanese, flags, log, user, h, err, notes);
        std::lock_guard<std::mutex> g(p->m);
        if (p->abandoned) {
            close_handle(h);
        } else {
            p->h = h;
        }
        p->ok = ok;
        p->error = err;
        p->notes = notes;
        p->ms = now_ms() - t0;
        p->done = true;
    });
}

int Audio::poll(std::string &msg)
{
    graveyard_.reap();
    if (!pending_) {
        return 0;
    }
    std::shared_ptr<Pending> p = pending_;
    {
        std::lock_guard<std::mutex> g(p->m);
        if (!p->done) {
            return 0;
        }
    }
    if (pending_worker_) {
        pending_worker_->join();   // finished: no wait
        pending_worker_.reset();
    }
    pending_.reset();
    if (!p->ok) {
        open_error_ = p->error;
        msg = p->error;
        return -1;
    }
    cur_ = p->h;
    japanese_ = p->japanese;
    open_ms_ = p->ms;
    notes_ = p->notes;
    apply(opt_);
    if (duck_ < 1.0f) {
        // a jukebox plays: the new mixer starts ducked
        sa1_audio_mixer_duck(cur_.mixer, duck_, (duck_jingles_ ? SA1_AUDIO_DUCK_JINGLES : 0u) | SA1_AUDIO_DUCK_NOW);
    }
    // 0.9.4a: the stage rules recorded for the characters (the first open, a re-open, a disc change: a new mixer)
    apply_rules();
    msg = format("sound banks opened in %.0f ms on a worker thread (%s voices)%s%s", open_ms_,
                 japanese_ ? "Japanese" : "English", notes_.empty() ? "" : "; ", notes_.c_str());
    return 1;
}

void Audio::wait()
{
    if (pending_worker_) {
        pending_worker_->join();
    }
}

double Audio::opening_ms() const
{
    return pending_ ? now_ms() - pending_t0_ : 0.0;
}

bool Audio::open(const std::string &gdi, bool japanese, std::string &err)
{
    open_async(gdi, japanese);
    wait();
    std::string msg;
    int r = poll(msg);
    err = r > 0 ? notes_ : msg;
    return r > 0;
}

void Audio::close()
{
    abandon_pending();
    Handle h = cur_;
    cur_ = Handle();
    close_later(h);
}

void Audio::shutdown()
{
    close();
    graveyard_.join_all();
}

void Audio::apply(const AudioOptions &o)
{
    auto clampv = [](float v) { return std::isfinite(v) ? std::max(0.0f, std::min(4.0f, v)) : 1.0f; };
    opt_ = o;
    opt_.master = clampv(o.master);
    opt_.sfx = clampv(o.sfx);
    opt_.voice = clampv(o.voice);
    opt_.music = clampv(o.music);
    if (!cur_.mixer) {
        return;
    }
    sa1_audio_mixer_volume(cur_.mixer, SA1_AUDIO_VOL_MASTER, opt_.master);
    sa1_audio_mixer_volume(cur_.mixer, SA1_AUDIO_VOL_SFX, opt_.sfx);
    sa1_audio_mixer_volume(cur_.mixer, SA1_AUDIO_VOL_VOICE, opt_.voice);
    sa1_audio_mixer_volume(cur_.mixer, SA1_AUDIO_VOL_MUSIC, opt_.music);
    sa1_audio_mixer_flags(cur_.mixer, mix_flags(opt_));
}

bool Audio::set_duck(float gain, bool jingles)
{
    if (!std::isfinite(gain) || gain < 0.0f || gain > 1.0f) {
        return false;
    }
    if (gain == duck_ && jingles == duck_jingles_) {
        return true;
    }
    duck_ = gain;
    duck_jingles_ = jingles;
    if (cur_.mixer) {
        // libsa1 ramps the music (and with SA1_AUDIO_DUCK_JINGLES the jingles) linearly, 0.5 s for a full swing
        sa1_audio_mixer_duck(cur_.mixer, gain, jingles ? SA1_AUDIO_DUCK_JINGLES : 0u);
    }
    return true;
}

void Audio::event(const sa1_event &e)
{
    events_++;
    if (e.type == SA1_EVENT_SOUND || e.type == SA1_EVENT_SOUND_STOP || e.type == SA1_EVENT_VOICE ||
        e.type == SA1_EVENT_JINGLE) {
        sound_events_++;
    }
    if (cur_.mixer) {
        sa1_audio_mixer_event(cur_.mixer, &e);
    }
}

void Audio::character(int32_t id, const float pos[3], bool local)
{
    if (cur_.mixer && id > 0) {
        sa1_audio_mixer_character(cur_.mixer, id, pos, local ? 1 : 0);
    }
}

void Audio::stop(int32_t id)
{
    if (id > 0) {
        rules_.erase(id);   // libsa1's sa1_audio_mixer_stop(mixer, id) forgets the character's rules too
    }
    if (cur_.mixer) {
        sa1_audio_mixer_stop(cur_.mixer, id);
    }
}

// ---- 0.9.4a: stage rules (libsa1_audio.h version 5; sadc docs/research/super2_sound.md 7.1) -----------------------
bool Audio::has_stage_rules() const
{
#if defined(SA1_AUDIO_HAS_STAGE_RULES)
    return true;
#else
    return false;
#endif
}

int32_t Audio::apply_rule(int32_t id, uint32_t slot, const StageRule &r)
{
#if defined(SA1_AUDIO_HAS_STAGE_RULES)
    if (!cur_.mixer) {
        return kRuleNotApplied;
    }
    // the character's mixer entry is made if needed; no disc access here (the loader thread reads the stage's banks)
    sa1_status st = sa1_audio_mixer_stage_rule(cur_.mixer, (sa1_character_id)id, slot, r.stage, r.first, r.last);
    if (SA1_FAILED(st)) {
        rules_refused_++;
        if (log_fn_) {
            log_fn_(log_user_, SA1_LOG_WARN,
                    format("audio: the stage rule of character %d (slot %u: tones %u-%u from stage %d) was refused: %s",
                           (int)id, (unsigned)slot, (unsigned)r.first, (unsigned)r.last, (int)r.stage,
                           sa1_status_string(st))
                        .c_str());
        }
        return (int32_t)st;
    }
    rules_applied_++;
    return (int32_t)SA1_OK;
#else
    (void)id;
    (void)slot;
    (void)r;
    return (int32_t)SA1_ERR_UNSUPPORTED;
#endif
}

void Audio::apply_rules()
{
    for (auto &kv : rules_) {
        for (uint32_t s = 0; s < kRuleSlots; s++) {
            if (kv.second.rule[s].stage >= 0) {
                kv.second.status[s] = apply_rule(kv.first, s, kv.second.rule[s]);
            }
        }
    }
}

bool Audio::set_stage_rule(int32_t id, uint32_t slot, const StageRule &r)
{
    if (!has_stage_rules() || id <= 0 || slot >= kRuleSlots) {
        return false;
    }
    auto it = rules_.find(id);
    if (r.stage < 0) {
        // clear: the mixer forgets the slot; the registry drops a character without rules
        if (it == rules_.end() || it->second.rule[slot].stage < 0) {
            return true;
        }
        int32_t st = apply_rule(id, slot, StageRule());
        it->second.rule[slot] = StageRule();
        it->second.status[slot] = 0;
        bool any = false;
        for (uint32_t s = 0; s < kRuleSlots; s++) {
            any = any || it->second.rule[s].stage >= 0;
        }
        if (!any) {
            rules_.erase(it);
        }
        return st == (int32_t)SA1_OK || st == kRuleNotApplied;
    }
    RuleSet &rs = rules_[id];
    rs.rule[slot] = r;
    rs.status[slot] = apply_rule(id, slot, r);
    return rs.status[slot] == (int32_t)SA1_OK || rs.status[slot] == kRuleNotApplied;
}

bool Audio::stage_rule(int32_t id, uint32_t slot, StageRule &out) const
{
    out = StageRule();
    auto it = rules_.find(id);
    if (it == rules_.end() || slot >= kRuleSlots || it->second.rule[slot].stage < 0) {
        return false;
    }
    out = it->second.rule[slot];
    return true;
}

int32_t Audio::rule_status(int32_t id, uint32_t slot) const
{
    auto it = rules_.find(id);
    if (it == rules_.end() || slot >= kRuleSlots || it->second.rule[slot].stage < 0) {
        return -1000;
    }
    return it->second.status[slot];
}

int32_t Audio::stage_state(int32_t stage) const
{
#if defined(SA1_AUDIO_HAS_STAGE_RULES)
    if (!cur_.audio) {
        return -1;
    }
    return sa1_audio_stage_state(cur_.audio, stage);
#else
    (void)stage;
    return -1;
#endif
}

size_t Audio::rule_characters() const
{
    return rules_.size();
}

void Audio::listener(const float pos[3], const float fwd[3], const float up[3])
{
    if (cur_.mixer) {
        sa1_audio_mixer_listener(cur_.mixer, pos, fwd, up);
    }
}

bool Audio::render(int16_t *out, uint32_t frames)
{
    if (!cur_.mixer) {
        std::memset(out, 0, (size_t)frames * 4u);
        return false;
    }
    frames_ += frames;
    return sa1_audio_mixer_render(cur_.mixer, out, frames) == SA1_OK;
}

bool Audio::stats(sa1_audio_stats &out) const
{
    std::memset(&out, 0, sizeof out);
    out.struct_size = sizeof out;
    return cur_.audio && sa1_audio_get_stats(cur_.audio, &out) == SA1_OK;
}

uint32_t Audio::active() const
{
    return cur_.mixer ? sa1_audio_mixer_active(cur_.mixer) : 0u;
}

bool Audio::music_state(MusicState &o) const
{
    o = MusicState();
#if defined(SA1_AUDIO_HEADER_VERSION) && SA1_AUDIO_HEADER_VERSION >= 4
    if (!cur_.mixer) {
        return false;
    }
    sa1_audio_music_state s;
    std::memset(&s, 0, sizeof s);
    s.struct_size = sizeof s;
    if (sa1_audio_mixer_music_state(cur_.mixer, &s) != SA1_OK) {
        return false;
    }
    o.valid = true;
    o.jingle = s.jingle;
    o.jingle_left = std::isfinite(s.jingle_left) ? s.jingle_left : -1.0f;
    o.stopped = s.stopped != 0;
    o.bgm = s.bgm;
    o.kind = s.jingle_kind;
    o.waiting = s.jingle_waiting != 0;
    o.loops = s.jingle_loops != 0;
    o.length = std::isfinite(s.jingle_length) ? s.jingle_length : 0.0f;
    o.time = std::isfinite(s.jingle_time) ? s.jingle_time : 0.0f;
    o.started = s.jingles_started;
    o.ended = s.jingles_ended;
    o.last_jingle = s.last_jingle;
    o.last_end = s.last_end;
    o.bgm_playing = s.bgm_playing != 0;
    return true;
#else
    return false;
#endif
}

std::string Audio::music_name(int32_t music) const
{
    if (!cur_.audio || music < 0) {
        return std::string();
    }
    const char *n = sa1_audio_music_name(cur_.audio, (uint32_t)music);
    return n ? std::string(n) : std::string();
}

bool Audio::end_music()
{
    if (!cur_.mixer) {
        return false;
    }
    sa1_audio_mixer_stop(cur_.mixer, 0);
    return true;
}

// ---- OutputLead (0.9.2a) --------------------------------------------------------------------------------------------
double OutputLead::update(double frame_s)
{
    if (!std::isfinite(frame_s) || frame_s < 0.0) {
        frame_s = 0.0;
    }
    // the 0.9.1 rule: two frames + 30 ms (the frame clamped to 250 ms) ...
    double lead = 2.0 * std::min(frame_s, 0.25) + 0.03;
    // ... and the slowest frame of the last 4 s x 1.25 + 20 ms (this frame included)
    win_.push_back(frame_s);
    sum_ += frame_s;
    while (win_.size() > 1 && sum_ - win_.front() >= kWindow) {
        sum_ -= win_.front();
        win_.pop_front();
    }
    lead = std::max(lead, slowest() * 1.25 + 0.02);
    lead_ = std::max(kMin, std::min(kMax, lead));
    return lead_;
}

double OutputLead::slowest() const
{
    double m = 0.0;
    for (double f : win_) {
        m = std::max(m, f);
    }
    return m;
}

void OutputLead::reset()
{
    win_.clear();
    sum_ = 0.0;
    lead_ = kMin;
}

// ---- AudioOut: a push stream on Garry's Mod's BASS (2.4; bass.hpp) -------------------------------------------------
AudioOut::~AudioOut()
{
    stop();
    if (fn_) {
        bass_release();
    }
    fn_ = nullptr;
}

bool AudioOut::bind(std::string &err)
{
    if (fn_) {
        return true;
    }
    fn_ = bass_acquire(err);
    if (!fn_) {
        return false;
    }
    name_ = bass_name(fn_);
    return true;
}

bool AudioOut::start(uint32_t rate, std::string &err)
{
    stop();
    error_.clear();
    if (!bind(err)) {
        error_ = err;
        return false;
    }
    if (fn_->GetDevice() == bass::kFail) {
        err = "Garry's Mod's BASS has no output device (not initialised)";
        error_ = err;
        return false;
    }
    // STREAMPROC_PUSH, 16-bit stereo, BASS's playback buffer 0: the push queue is the latency
    stream_ = bass_push_stream(fn_, rate, err);
    if (!stream_) {
        error_ = err;
        return false;
    }
    rate_ = rate;
    paused_ = false;
    volume_ = -1.0f;
    lead_.reset();
    return true;
}

void AudioOut::stop()
{
    if (stream_ && fn_) {
        fn_->StreamFree(stream_);
    }
    stream_ = 0;
}

uint32_t AudioOut::queued_frames() const
{
    if (!stream_) {
        return 0;
    }
    return bass_queued_frames(fn_, stream_);
}

uint32_t AudioOut::playback_frames() const
{
    if (!stream_) {
        return 0;
    }
    return bass_playback_frames(fn_, stream_);
}

uint32_t AudioOut::top_up(double frame_s)
{
    double lead = lead_.update(frame_s);
    if (!stream_) {
        return 0;
    }
    uint32_t target = (uint32_t)(lead * (double)rate_);
    uint32_t queued = queued_frames();
    if (queued >= target) {
        return 0;
    }
    // 256 frames (5.8 ms) more than the target, so not every frame pushes a sliver; at most a quarter second at once
    return std::min<uint32_t>(target - queued + 256u, rate_ / 4u);
}

bool AudioOut::push(const int16_t *pcm, uint32_t frames)
{
    if (!stream_ || frames == 0) {
        return false;
    }
    if (!paused_ && fn_->ChannelIsActive(stream_) == bass::kActiveStalled) {
        underruns_++;
    }
    if (fn_->StreamPutData(stream_, pcm, frames * 4u) == bass::kFail) {
        error_ = format("BASS_StreamPutData failed (BASS error %d)", fn_->ErrorGetCode());
        return false;
    }
    if (!paused_ && fn_->ChannelIsActive(stream_) == 0) {
        fn_->ChannelPlay(stream_, 0);
    }
    return true;
}

void AudioOut::pause(bool p)
{
    if (!stream_ || p == paused_) {
        return;
    }
    paused_ = p;
    if (p) {
        fn_->ChannelPause(stream_);
    } else {
        fn_->ChannelPlay(stream_, 0);
    }
}

void AudioOut::volume(float v)
{
    if (!stream_ || !std::isfinite(v)) {
        return;
    }
    v = std::max(0.0f, std::min(1.0f, v));
    if (std::fabs(v - volume_) < 1e-4f) {
        return;
    }
    volume_ = v;
    fn_->ChannelSetAttribute(stream_, bass::kAttribVol, v);
}

int32_t AudioOut::global_stream_volume() const
{
    if (!fn_) {
        return -1;
    }
    uint32_t g = fn_->GetConfig(bass::kConfigGvolStream);
    return g == bass::kFail ? -1 : (int32_t)g;
}

}  // namespace gsa1
