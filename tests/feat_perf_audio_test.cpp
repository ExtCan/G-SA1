// feat_perf_audio_test: the game sound's output feed (0.9.2a; sadc docs/research/gsa1_091a_perf.md A0 + A2 with its
// review RC3 / RC6; the owner hears crackles), linked like core_test (the core objects and libsa1; no module, no Lua).
// The output is FakeBass (src/core/bass.hpp) with its opt-in playback buffer model (45 ms, the owner's device: 41-49 ms)
// and a manual clock, so every frame time is exact.
//
//   feat_perf_audio_test [--gdi GAME.gdi] [--verbose]      (the disc is not needed)
//
// Checks (fail on 0.9.1's feed, pass on 0.9.2a's):
//   * 0.9.1's accounting (push queue + BASS_DATA_AVAILABLE, lead clamp(2 x frame + 30 ms, 60, 200)) at 60 fps followed by
//     one 28 ms frame runs the stream dry (the bug, reproduced in the model); AudioOut::top_up (push queue only) does not;
//   * the push queue alone: no stall from single frames up to 65 ms after smooth play; the first one of 80 ms still stalls
//     (the lead after smooth play is 63 ms: the latency stays 0.9.1's), and the second one within 4 s does not (the
//     adaptive lead: 80 x 1.25 + 20 = 120 ms);
//   * OutputLead: 60-63 ms at 60 fps, 120 ms after an 80 ms frame, back to 63 ms 4 s later, at most 250 ms;
//   * a minute of the owner's session-2 frame mix (its histogram, 0.9.1a log): 0.9.1's feed stalls several times more
//     often than 0.9.2a's, which stays under 10 a minute;
//   * the model is opt-in: a fresh FakeBass reports no playback buffer (the jukebox tests keep their numbers);
//   * AudioOut::underruns counts what it saw at push time, no more than the stalls the device had.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "audio.hpp"
#include "bass.hpp"
#include "util.hpp"

using namespace gsa1;

static int g_fail = 0, g_checks = 0;
static bool g_verbose = false;
#define CHECK(cond, ...)                      \
    do {                                      \
        g_checks++;                           \
        std::printf((cond) ? "  ok    " : "  FAIL  "); \
        if (!(cond)) g_fail++;                \
        std::printf(__VA_ARGS__);             \
        std::printf("\n");                    \
        std::fflush(stdout);                  \
    } while (0)

static const uint32_t kRate = 44100;
static std::vector<int16_t> g_zeros(kRate / 2 * 2, 0);

struct FeedResult {
    uint32_t stalls = 0;           // times the stream ran dry (the device's view)
    double stall_ms = 0.0;         // the frames it wanted and did not get
    uint64_t underruns = 0;        // what the feed saw at push time (AudioOut::underruns; 0.9.1's own count)
    double lead_sum = 0.0;         // ms, over the frames
    uint32_t frames = 0;
};

// 0.9.1's feed (gsa1_module.cpp gsa1_lua_AudioUpdate up to 0.9.2): queue = push queue + BASS's playback buffer
static uint32_t old_top_up(const BassApi *api, uint32_t h, double ft)
{
    double ahead = std::max(0.06, std::min(0.2, 2.0 * std::max(0.0, std::min(0.25, ft)) + 0.03));
    uint32_t target = (uint32_t)(ahead * kRate);
    uint32_t q = api->StreamPutData(h, nullptr, 0);
    uint32_t b = api->ChannelGetData(h, nullptr, bass::kDataAvailable);
    uint32_t queued = (q == bass::kFail ? 0u : q / 4u) + (b == bass::kFail ? 0u : b / 4u);
    if (queued >= target) return 0;
    return std::min<uint32_t>(target - queued + 256u, kRate / 4u);
}

// runs `frames_ms` (each frame: the feed, then the frame's time passes) after `warm` frames of 60 fps; the stalls are
// counted from the end of the warm-up. old_feed: 0.9.1's accounting on a raw push stream, else AudioOut (0.9.2a).
static FeedResult run_feed(bool old_feed, const std::vector<double> &frames_ms, double buffer_ms, int warm = 120)
{
    FakeBass &fb = FakeBass::get();
    fb.reset();
    fb.set_manual_clock(true);
    fb.set_playback_buffer_ms(buffer_ms);
    const BassApi *api = fb.api();
    FeedResult r;
    AudioOut out;
    uint32_t h = 0;
    std::string err;
    if (old_feed) {
        h = bass_push_stream(api, kRate, err);
    } else if (!out.start(kRate, err)) {
        std::printf("        AudioOut::start: %s\n", err.c_str());
        return r;
    }
    if (old_feed && !h) {
        std::printf("        bass_push_stream: %s\n", err.c_str());
        return r;
    }
    double ft = 1.0 / 60.0;
    uint32_t stalls0 = 0;
    double stall0 = 0.0;
    uint64_t under0 = 0;
    size_t total = (size_t)warm + frames_ms.size();
    for (size_t i = 0; i < total; i++) {
        if (i == (size_t)warm) {
            FakeBass::Stream s = fb.stream(old_feed ? h : fb.streams().begin()->first);
            stalls0 = s.stalls;
            stall0 = s.stall_frames;
            under0 = out.underruns();
        }
        if (old_feed) {
            uint32_t n = old_top_up(api, h, ft);
            if (n) {
                if (api->ChannelIsActive(h) == bass::kActiveStalled && i >= (size_t)warm) r.underruns++;
                api->StreamPutData(h, g_zeros.data(), n * 4u);
                if (api->ChannelIsActive(h) == bass::kActiveStopped) api->ChannelPlay(h, 0);
            }
            if (i >= (size_t)warm) r.lead_sum += std::max(60.0, std::min(200.0, 2000.0 * std::min(0.25, ft) + 30.0));
        } else {
            uint32_t n = out.top_up(ft);
            if (n) out.push(g_zeros.data(), n);
            if (i >= (size_t)warm) r.lead_sum += out.lead_ms();
        }
        double ms = i < (size_t)warm ? 1000.0 / 60.0 : frames_ms[i - (size_t)warm];
        fb.advance_ms(ms);
        ft = ms / 1000.0;
    }
    FakeBass::Stream s = fb.stream(old_feed ? h : fb.streams().begin()->first);
    r.stalls = s.stalls - stalls0;
    r.stall_ms = (s.stall_frames - stall0) * 1000.0 / kRate;
    if (!old_feed) r.underruns = out.underruns() - under0;
    r.frames = (uint32_t)frames_ms.size();
    if (old_feed) api->StreamFree(h);
    out.stop();
    fb.set_manual_clock(false);
    fb.set_playback_buffer_ms(0.0);
    return r;
}

static std::vector<double> smooth_then(std::vector<double> hitches, double gap_s = 1.0)
{
    std::vector<double> f;
    for (double hms : hitches) {
        f.push_back(hms);
        for (int k = 0; k < (int)(gap_s * 60.0); k++) f.push_back(1000.0 / 60.0);
    }
    return f;
}

static void test_accounting()
{
    std::printf("the push queue against BASS's playback buffer (A0; the model: 45 ms of playback buffer)\n");
    {
        FakeBass &fb = FakeBass::get();
        fb.reset();
        std::string err;
        uint32_t h = bass_push_stream(fb.api(), kRate, err);
        fb.api()->StreamPutData(h, g_zeros.data(), 4410u * 4u);
        fb.api()->ChannelPlay(h, 0);
        uint32_t b = fb.api()->ChannelGetData(h, nullptr, bass::kDataAvailable);
        CHECK(h != 0 && b == 0, "the playback buffer model is opt-in: a fresh FakeBass reports %u bytes in it (the jukebox "
              "tests keep their numbers)", b);
        fb.api()->StreamFree(h);
    }
    std::vector<double> one28 = smooth_then({28.0});
    FeedResult o = run_feed(true, one28, 45.0);
    FeedResult n = run_feed(false, one28, 45.0);
    CHECK(o.stalls >= 1, "0.9.1's feed (push queue + BASS_DATA_AVAILABLE) at 60 fps, then one 28 ms frame: the stream ran "
          "dry %u time(s), %.1f ms (the owner's 109 underruns a minute: every frame over about 25 ms)", o.stalls,
          o.stall_ms);
    CHECK(n.stalls == 0 && n.underruns == 0, "0.9.2a (the push queue only): the same frames, %u stalls, %llu underruns",
          n.stalls, (unsigned long long)n.underruns);
    FeedResult n0 = run_feed(false, one28, 0.0);
    CHECK(n0.stalls == 0, "0.9.2a without a playback buffer (a device that has none): %u stalls", n0.stalls);

    // single frames after smooth play
    std::vector<double> small = smooth_then({20.0, 30.0, 40.0, 50.0, 60.0, 65.0}, 4.5);
    FeedResult s = run_feed(false, small, 45.0);
    FeedResult so = run_feed(true, small, 45.0);
    CHECK(s.stalls == 0 && so.stalls >= 5, "single slow frames of 20-65 ms, 4.5 s apart: 0.9.2a %u stalls, 0.9.1 %u",
          s.stalls, so.stalls);
    std::vector<double> big = smooth_then({80.0}, 4.5);
    FeedResult b1 = run_feed(false, big, 45.0);
    CHECK(b1.stalls == 1, "the first 80 ms frame after smooth play still stalls once (%u): the lead in smooth play stays "
          "0.9.1's 63 ms, so the sound is not later", b1.stalls);
    std::vector<double> two = smooth_then({80.0, 80.0, 100.0}, 1.0);
    FeedResult b2 = run_feed(false, two, 45.0);
    CHECK(b2.stalls == 1, "80 ms, 1 s later 80 ms, 1 s later 100 ms: %u stall(s) (only the first: the adaptive lead covers "
          "the hitches that follow a hitch)", b2.stalls);
}

static void test_lead()
{
    std::printf("the adaptive lead (A2: OutputLead)\n");
    OutputLead L;
    double l = 0;
    for (int i = 0; i < 300; i++) l = L.update(1.0 / 60.0);
    CHECK(std::fabs(l - (2.0 / 60.0 + 0.03)) < 1e-9, "60 fps: %.1f ms (0.9.1: 63.3)", l * 1000.0);
    for (int i = 0; i < 300; i++) l = L.update(1.0 / 144.0);
    CHECK(std::fabs(l - 0.06) < 1e-9, "144 fps: %.1f ms (at least 60)", l * 1000.0);
    l = L.update(0.08);
    double after = l;
    for (int i = 0; i < 60; i++) l = L.update(1.0 / 60.0);
    double one_s = l;
    for (int i = 0; i < 4 * 60; i++) l = L.update(1.0 / 60.0);
    CHECK(std::fabs(after - 0.19) < 1e-9 && std::fabs(one_s - 0.12) < 1e-9 && std::fabs(l - (2.0 / 60.0 + 0.03)) < 1e-9,
          "an 80 ms frame: %.0f ms right after it (2 x 80 + 30), %.0f ms a second later (80 x 1.25 + 20), %.1f ms after "
          "4 more seconds", after * 1000.0, one_s * 1000.0, l * 1000.0);
    l = L.update(0.6);
    double cap = l;
    l = L.update(-1.0);
    double neg = l;
    l = L.update(std::nan(""));
    CHECK(std::fabs(cap - 0.25) < 1e-9 && neg <= 0.25 && l <= 0.25 && l >= 0.06,
          "at most 250 ms (a 600 ms hitch: %.0f ms); bad frame times are taken as 0 (%.0f, %.0f ms)", cap * 1000.0,
          neg * 1000.0, l * 1000.0);
}

// session 2 of the owner's 0.9.1a log (gsa1_091a_perf.md 1): the frame-time histogram, drawn with a fixed seed; the two
// smooth bins as vsync jitter around 16.7 ms (the review's s4j)
static std::vector<double> owner_mix(double seconds)
{
    struct Bin { double lo, hi; uint32_t n; };
    const Bin bins[] = {{16.3, 17.0, 14088}, {17.0, 17.6, 10866}, {20.0, 25.0, 417}, {25.0, 33.0, 265},
                        {33.0, 50.0, 244},   {50.0, 100.0, 86},   {100.0, 250.0, 20}, {250.0, 400.0, 7}};
    uint32_t total = 0;
    for (const Bin &b : bins) total += b.n;
    uint64_t x = 0x9E3779B97F4A7C15ull;
    auto rnd = [&]() {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        return (double)(x >> 11) / (double)(1ull << 53);
    };
    std::vector<double> out;
    double t = 0;
    while (t < seconds * 1000.0) {
        double u = rnd() * total;
        const Bin *pick = &bins[0];
        for (const Bin &b : bins) {
            if (u < b.n) {
                pick = &b;
                break;
            }
            u -= b.n;
        }
        double ms = pick->lo + rnd() * (pick->hi - pick->lo);
        out.push_back(ms);
        t += ms;
    }
    return out;
}

static void test_owner_mix()
{
    std::printf("a minute of the owner's session-2 frame mix (0.9.1a log: 958 underruns in about 460 s)\n");
    std::vector<double> mix = owner_mix(60.0);
    FeedResult o = run_feed(true, mix, 45.0);
    FeedResult n = run_feed(false, mix, 45.0);
    double secs = 0;
    for (double f : mix) secs += f / 1000.0;
    double om = o.stalls * 60.0 / secs, nm = n.stalls * 60.0 / secs;
    CHECK(om > 3.0 * std::max(nm, 1.0) && nm < 10.0,
          "%u frames, %.1f s: 0.9.1's feed ran dry %u times (%.0f a minute, %.2f s missing), 0.9.2a %u times (%.1f a "
          "minute, %.2f s missing); mean lead %.0f / %.0f ms", (unsigned)mix.size(), secs, o.stalls, om, o.stall_ms / 1000.0,
          n.stalls, nm, n.stall_ms / 1000.0, o.lead_sum / std::max(1u, o.frames), n.lead_sum / std::max(1u, n.frames));
    CHECK(n.underruns <= n.stalls, "AudioOut counted %llu underruns at push time for %u stalls of the device",
          (unsigned long long)n.underruns, n.stalls);
}

int main(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        if (std::string(argv[i]) == "--verbose") g_verbose = true;
    }
    std::printf("G-SA1 feat_perf_audio_test\n");
    FakeBass &fb = FakeBass::get();
    fb.reset();
    bass_set_test_api(fb.api());
    test_lead();
    test_accounting();
    test_owner_mix();
    bass_set_test_api(nullptr);
    std::printf("feat_perf_audio_test: %d checks, %d failed\n", g_checks, g_fail);
    return g_fail ? 1 : 0;
}
