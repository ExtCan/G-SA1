// G-SA1 core: moving collision objects (see movers.hpp).
#include "movers.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace gsa1 {

namespace {

// far below every map (Source maps live within +-16384): out of every character's reach
const float kParkPos[3] = {0.0f, 0.0f, -120000.0f};

bool same_transform(const float a[3], const float ar[9], const float b[3], const float br[9])
{
    for (int k = 0; k < 3; k++) {
        if (std::fabs(a[k] - b[k]) > 0.01f) {
            return false;
        }
    }
    for (int k = 0; k < 9; k++) {
        if (std::fabs(ar[k] - br[k]) > 1e-5f) {
            return false;
        }
    }
    return true;
}

}  // namespace

void Movers::set_shape(const std::string &key, Shape s)
{
    shapes_[key] = std::make_shared<const Shape>(std::move(s));
}

const Shape *Movers::shape(const std::string &key) const
{
    auto it = shapes_.find(key);
    return it == shapes_.end() ? nullptr : it->second.get();
}

void Movers::drop_shapes(const std::string &prefix)
{
    for (auto it = shapes_.begin(); it != shapes_.end();) {
        if (it->first.compare(0, prefix.size(), prefix) == 0) {
            it = shapes_.erase(it);
        } else {
            ++it;
        }
    }
}

void Movers::update(int32_t ent, const std::string &key, const float pos[3], const float ang[3], bool solid, double now)
{
    Ent &e = ents_[ent];
    if (e.key != key) {
        e.key = key;
        e.shape.reset();
    }
    for (int k = 0; k < 3; k++) {
        e.pos[k] = std::isfinite(pos[k]) ? std::max(-65536.0f, std::min(65536.0f, pos[k])) : 0.0f;
    }
    float a[3];
    for (int k = 0; k < 3; k++) {
        a[k] = std::isfinite(ang[k]) ? std::fmod(ang[k], 360.0f) : 0.0f;
    }
    angle_matrix(a, e.rot);
    e.solid = solid;
    e.seen = now;
}

void Movers::forget(int32_t ent)
{
    auto it = ents_.find(ent);
    if (it != ents_.end()) {
        it->second.seen = -1e300;   // dropped at the next commit (its libsa1 objects need the context)
    }
}

void Movers::drop_ent(sa1_context *ctx, Ent &e)
{
    for (Chunk &c : e.chunks) {
        if (c.id && ctx) {
            sa1_collision_object_remove(ctx, c.id);
            st_.removes++;
        }
        c.id = 0;
    }
    e.chunks.clear();
}

void Movers::clear(sa1_context *ctx)
{
    for (auto &kv : ents_) {
        drop_ent(ctx, kv.second);
    }
    ents_.clear();
}

std::vector<uint32_t> Movers::object_ids() const
{
    std::vector<uint32_t> out;
    for (const auto &kv : ents_) {
        for (const Chunk &c : kv.second.chunks) {
            if (c.id) {
                out.push_back(c.id);
            }
        }
    }
    return out;
}

bool Movers::entity_of(uint32_t object_id, int32_t &ent, uint32_t *chunk) const
{
    if (object_id == 0) {
        return false;
    }
    for (const auto &kv : ents_) {
        for (uint32_t c = 0; c < kv.second.chunks.size(); c++) {
            if (kv.second.chunks[c].id == object_id) {
                ent = kv.first;
                if (chunk) {
                    *chunk = c;
                }
                return true;
            }
        }
    }
    return false;
}

void Movers::commit(sa1_context *ctx, const float *focus, double now)
{
    if (!ctx) {
        return;
    }
    // forgotten / stale entities, shapes resolved
    for (auto it = ents_.begin(); it != ents_.end();) {
        Ent &e = it->second;
        if (now - e.seen > opt.stale) {
            drop_ent(ctx, e);
            it = ents_.erase(it);
            continue;
        }
        if (!e.shape) {
            auto s = shapes_.find(e.key);
            if (s != shapes_.end()) {
                drop_ent(ctx, e);   // a new shape for this entity: its chunks start over
                e.shape = s->second;
                e.chunks.assign(e.shape->chunks.size(), Chunk());
            }
        } else if (e.chunks.size() != e.shape->chunks.size()) {
            drop_ent(ctx, e);
            e.chunks.assign(e.shape->chunks.size(), Chunk());
        }
        ++it;
    }
    // the candidates: chunks of solid entities within range of the focus, nearest first
    struct Cand {
        float d;
        int32_t ent;
        uint32_t chunk;
        float pos[3];
    };
    std::vector<Cand> cand;
    MoverStats &st = st_;
    st.entities = (uint32_t)ents_.size();
    st.solid = st.unknown_shape = 0;
    for (auto &kv : ents_) {
        Ent &e = kv.second;
        if (!e.shape) {
            st.unknown_shape++;
            continue;
        }
        if (!e.solid) {
            continue;
        }
        st.solid++;
        for (uint32_t c = 0; c < e.shape->chunks.size(); c++) {
            const ShapeChunk &ch = e.shape->chunks[c];
            Cand k;
            for (int r = 0; r < 3; r++) {
                k.pos[r] = e.pos[r] + e.rot[3 * r] * ch.center[0] + e.rot[3 * r + 1] * ch.center[1] +
                           e.rot[3 * r + 2] * ch.center[2];
            }
            if (focus) {
                float dx = k.pos[0] - focus[0], dy = k.pos[1] - focus[1], dz = k.pos[2] - focus[2];
                k.d = std::sqrt(dx * dx + dy * dy + dz * dz) - ch.radius;
                if (k.d > opt.range) {
                    continue;
                }
            } else {
                continue;
            }
            k.ent = kv.first;
            k.chunk = c;
            cand.push_back(k);
        }
    }
    std::sort(cand.begin(), cand.end(), [](const Cand &a, const Cand &b) {
        return a.d < b.d || (a.d == b.d && (a.ent < b.ent || (a.ent == b.ent && a.chunk < b.chunk)));
    });
    st.candidates = (uint32_t)cand.size();
    st.over_budget = 0;
    // the selection
    std::vector<std::pair<int32_t, uint32_t>> chosen;
    uint32_t tris = 0;
    for (const Cand &k : cand) {
        const ShapeChunk &ch = ents_[k.ent].shape->chunks[k.chunk];
        uint32_t n = (uint32_t)ch.tris.size();
        if (chosen.size() >= opt.max_active || (tris + n > opt.max_tris && !chosen.empty())) {
            st.over_budget++;
            continue;
        }
        chosen.push_back({k.ent, k.chunk});
        tris += n;
        Ent &e = ents_[k.ent];
        Chunk &c = e.chunks[k.chunk];
        c.used = now;
        if (c.id && !c.parked && same_transform(c.pos, c.rot, k.pos, e.rot)) {
            continue;
        }
        if (c.id) {
            sa1_status s = sa1_collision_object_move(ctx, c.id, k.pos, e.rot);
            if (s == SA1_OK) {
                st.moves++;
                if (c.parked) {
                    st.unparks++;
                }
                c.parked = false;
                std::memcpy(c.pos, k.pos, sizeof c.pos);
                std::memcpy(c.rot, e.rot, sizeof c.rot);
                continue;
            }
            sa1_collision_object_remove(ctx, c.id);   // a stale id: add it again
            c.id = 0;
        }
        uint32_t id = 0;
        sa1_status s = sa1_collision_object_add(ctx, ch.tris.data(), n, k.pos, e.rot, &id);
        if (s != SA1_OK || id == 0) {
            st.failures++;
            st.last_error = sa1_last_error(ctx) ? sa1_last_error(ctx) : "sa1_collision_object_add failed";
            continue;
        }
        st.adds++;
        c.id = id;
        c.parked = false;
        std::memcpy(c.pos, k.pos, sizeof c.pos);
        std::memcpy(c.rot, e.rot, sizeof c.rot);
    }
    std::sort(chosen.begin(), chosen.end());
    // everything else that has an object is parked; the oldest parked ones beyond max_parked are removed
    struct Parked {
        double used;
        int32_t ent;
        uint32_t chunk;
    };
    std::vector<Parked> parked;
    static const float kIdent[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};
    for (auto &kv : ents_) {
        Ent &e = kv.second;
        for (uint32_t c = 0; c < e.chunks.size(); c++) {
            Chunk &ck = e.chunks[c];
            if (!ck.id || std::binary_search(chosen.begin(), chosen.end(), std::make_pair(kv.first, c))) {
                continue;
            }
            if (!ck.parked) {
                if (sa1_collision_object_move(ctx, ck.id, kParkPos, kIdent) == SA1_OK) {
                    ck.parked = true;
                    st.parks++;
                } else {
                    sa1_collision_object_remove(ctx, ck.id);
                    ck.id = 0;
                    st.removes++;
                    continue;
                }
            }
            parked.push_back({ck.used, kv.first, c});
        }
    }
    if (parked.size() > opt.max_parked) {
        std::sort(parked.begin(), parked.end(), [](const Parked &a, const Parked &b) { return a.used < b.used; });
        for (size_t i = 0; i + opt.max_parked < parked.size(); i++) {
            Chunk &ck = ents_[parked[i].ent].chunks[parked[i].chunk];
            sa1_collision_object_remove(ctx, ck.id);
            ck.id = 0;
            ck.parked = false;
            st.removes++;
        }
        parked.resize(opt.max_parked);
    }
    st.active = 0;
    for (const auto &ch : chosen) {
        st.active += ents_[ch.first].chunks[ch.second].id != 0;
    }
    st.active_tris = tris;
    st.parked = (uint32_t)std::min<size_t>(parked.size(), opt.max_parked);
}

}  // namespace gsa1
