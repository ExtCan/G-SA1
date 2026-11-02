// G-SA1 core: the follower set (see follower.hpp).
#include "follower.hpp"

#include <algorithm>
#include <cstdio>
#include <cstring>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace gsa1 {

const char *const kReasonCycle = "a follower cannot follow itself or one of its own followers";
const char *const kReasonMemory = "not enough free memory";
const char *const kReasonMaxChars = "too many characters";
const char *const kReasonMaxFollowers = "too many followers";
const char *const kReasonNoApi = "this libsa1 has no followers (round 0.9.8, SA1_API_FOLLOWER)";

uint32_t follower_far_every(uint32_t rate)
{
    rate = std::max(kFollowerRateMin, std::min(kFollowerRateMax, rate));
    return std::max(1u, (60u + rate / 2u) / rate);
}

bool follower_far_due(uint64_t frame, int32_t id, uint32_t rate)
{
    return (frame + (uint64_t)(uint32_t)id) % follower_far_every(rate) == 0;
}

const FollowerSet::Entry *FollowerSet::find(int32_t id) const
{
    for (const Entry &e : list_) {
        if (e.id == id) {
            return &e;
        }
    }
    return nullptr;
}

FollowerSet::Entry *FollowerSet::find(int32_t id)
{
    for (Entry &e : list_) {
        if (e.id == id) {
            return &e;
        }
    }
    return nullptr;
}

bool FollowerSet::is_follower(int32_t id) const
{
    return find(id) != nullptr;
}

int32_t FollowerSet::leader_of(int32_t id) const
{
    const Entry *e = find(id);
    return e ? e->leader : -1;
}

int32_t FollowerSet::kind_of(int32_t id) const
{
    const Entry *e = find(id);
    return e ? e->kind : -1;
}

const FollowerOpts *FollowerSet::opts_of(int32_t id) const
{
    const Entry *e = find(id);
    return e ? &e->opt : nullptr;
}

bool FollowerSet::can_follow(int32_t follower, int32_t leader, std::string &err) const
{
    if (leader == 0) {
        return true;
    }
    // walks up from the new leader: reaching the follower is a cycle
    int32_t at = leader;
    for (size_t guard = 0; guard <= list_.size() + 1u; guard++) {
        if (follower != 0 && at == follower) {
            err = kReasonCycle;
            return false;
        }
        const Entry *e = find(at);
        if (!e || e->leader == 0) {
            return true;
        }
        at = e->leader;
    }
    err = kReasonCycle;     // (a chain longer than the set: cannot happen while can_follow guards every link)
    return false;
}

void FollowerSet::add(int32_t id, int32_t kind, int32_t leader, const FollowerOpts &o)
{
    if (find(id)) {
        return;
    }
    Entry e;
    e.id = id;
    e.kind = kind;
    e.leader = leader;
    e.opt = o;
    list_.push_back(e);
    dirty_ = true;
    gen_++;
}

void FollowerSet::set_leader(int32_t id, int32_t leader)
{
    Entry *e = find(id);
    if (e && e->leader != leader) {
        e->leader = leader;
        dirty_ = true;
        gen_++;
    }
}

void FollowerSet::feed(int32_t id, const LeaderFeed &f)
{
    Entry *e = find(id);
    if (e) {
        e->feed = f;
    }
}

const LeaderFeed *FollowerSet::feed_of(int32_t id) const
{
    const Entry *e = find(id);
    return e ? &e->feed : nullptr;
}

void FollowerSet::remove(int32_t id)
{
    for (size_t i = 0; i < list_.size(); i++) {
        if (list_[i].id == id) {
            list_.erase(list_.begin() + (std::ptrdiff_t)i);
            dirty_ = true;
            gen_++;
            return;
        }
    }
}

size_t FollowerSet::leader_gone(int32_t id, const float last_pos[3], float last_yaw)
{
    size_t n = 0;
    for (Entry &e : list_) {
        if (e.leader == id) {
            e.leader = 0;
            e.feed.valid = true;
            std::memcpy(e.feed.pos, last_pos, sizeof e.feed.pos);
            std::memset(e.feed.vel, 0, sizeof e.feed.vel);
            e.feed.yaw = last_yaw;
            e.feed.ground = true;
            n++;
        }
    }
    if (n) {
        dirty_ = true;
        gen_++;
    }
    return n;
}

int32_t FollowerSet::root_of(int32_t id) const
{
    const Entry *e = find(id);
    if (!e) {
        return -1;
    }
    for (size_t guard = 0; guard <= list_.size() + 1u; guard++) {
        if (e->leader == 0) {
            return 0;
        }
        const Entry *up = find(e->leader);
        if (!up) {
            return e->leader;
        }
        e = up;
    }
    return 0;
}

void FollowerSet::rebuild() const
{
    dirty_ = false;
    order_.clear();
    for (auto &l : levels_) {
        l.clear();
    }
    // Kahn's algorithm by levels: a follower is placed when its leader is no follower or is placed already
    std::vector<int32_t> level_of(list_.size(), -1);
    auto index_of = [this](int32_t id) -> int {
        for (size_t i = 0; i < list_.size(); i++) {
            if (list_[i].id == id) {
                return (int)i;
            }
        }
        return -1;
    };
    size_t placed = 0;
    for (int32_t lv = 0; placed < list_.size(); lv++) {
        size_t before = placed;
        if (levels_.size() <= (size_t)lv) {
            levels_.resize((size_t)lv + 1u);
        }
        for (size_t i = 0; i < list_.size(); i++) {
            if (level_of[i] >= 0) {
                continue;
            }
            int up = list_[i].leader != 0 ? index_of(list_[i].leader) : -1;
            if (up < 0 || (level_of[(size_t)up] >= 0 && level_of[(size_t)up] < lv)) {
                level_of[i] = lv;
                levels_[(size_t)lv].push_back(list_[i].id);
                placed++;
            }
        }
        if (placed == before) {
            // a cycle (can_follow refuses them; nothing here may hang): the rest ticks last
            for (size_t i = 0; i < list_.size(); i++) {
                if (level_of[i] < 0) {
                    level_of[i] = lv;
                    levels_[(size_t)lv].push_back(list_[i].id);
                    placed++;
                }
            }
        }
    }
    while (!levels_.empty() && levels_.back().empty()) {
        levels_.pop_back();
    }
    for (const auto &l : levels_) {
        order_.insert(order_.end(), l.begin(), l.end());
    }
}

const std::vector<std::vector<int32_t>> &FollowerSet::levels() const
{
    if (dirty_) {
        rebuild();
    }
    return levels_;
}

const std::vector<int32_t> &FollowerSet::order() const
{
    if (dirty_) {
        rebuild();
    }
    return order_;
}

bool follower_event_mixes(uint32_t type, bool sounds)
{
    switch (type) {
    case kEventJingle:
        return false;
    case kEventSoundStop:
        return true;
    case kEventSound:
    case kEventVoice:
        return sounds;
    default:
        return true;
    }
}

bool follower_event_for_lua(uint32_t type)
{
    return type != kEventSound && type != kEventSoundStop && type != kEventVoice && type != kEventJingle &&
           type != kEventRumble;
}

namespace {
MemoryProbe g_memory_probe = nullptr;
}

uint64_t available_physical_bytes()
{
#ifdef _WIN32
    MEMORYSTATUSEX ms;
    std::memset(&ms, 0, sizeof ms);
    ms.dwLength = sizeof ms;
    if (GlobalMemoryStatusEx(&ms)) {
        return (uint64_t)ms.ullAvailPhys;
    }
    return UINT64_MAX;
#else
    std::FILE *f = std::fopen("/proc/meminfo", "r");
    if (!f) {
        return UINT64_MAX;
    }
    char line[256];
    uint64_t out = UINT64_MAX;
    while (std::fgets(line, sizeof line, f)) {
        unsigned long long kb = 0;
        if (std::sscanf(line, "MemAvailable: %llu kB", &kb) == 1) {
            out = (uint64_t)kb * 1024u;
            break;
        }
    }
    std::fclose(f);
    return out;
#endif
}

void set_memory_probe(MemoryProbe p)
{
    g_memory_probe = p;
}

bool follower_memory_ok()
{
    uint64_t avail = g_memory_probe ? g_memory_probe() : available_physical_bytes();
    return avail == UINT64_MAX || avail >= kFollowerMemoryGuardMb * 1024u * 1024u;
}

}  // namespace gsa1
