// G-SA1 core: the map's collision prepared for libsa1 off the game's thread (see prepare.hpp).
#include "prepare.hpp"

#include <cstring>

#include "util.hpp"

namespace gsa1 {

PreparedRef::PreparedRef(const PreparedRef &o) : p_(o.p_)
{
    if (p_) {
        sa1_collision_prepared_retain(p_);
    }
}

void PreparedRef::reset()
{
    if (p_) {
        sa1_collision_prepared_release(p_);
        p_ = nullptr;
    }
}

bool PreparedRef::info(sa1_collision_prepared_info &out) const
{
    std::memset(&out, 0, sizeof out);
    out.struct_size = sizeof out;
    return p_ && sa1_collision_prepared_info_get(p_, &out) == SA1_OK;
}

void source_coords(sa1_coords &out)
{
    std::memset(&out, 0, sizeof out);
    out.struct_size = sizeof out;
    sa1_coords_preset(SA1_COORDS_PRESET_SOURCE, &out);
}

bool prepare_world(const std::vector<sa1_collision_tri> &tris, const PrepareOptions &o, PrepareResult &out)
{
    out = PrepareResult();
    out.triangles = (uint32_t)tris.size();
    double t0 = now_ms();
    if (tris.size() > SA1_MAX_COLLISION_TRIS) {
        out.error = format("%zu triangles: more than libsa1 takes (%u)", tris.size(), (unsigned)SA1_MAX_COLLISION_TRIS);
        out.status = SA1_ERR_LIMIT;
        return false;
    }
    // a private context: the default host (malloc / free, stdio: thread-safe), no log, the SOURCE coordinates
    sa1_host h;
    sa1_host_defaults(&h);
    h.log = nullptr;
    sa1_context *ctx = nullptr;
    sa1_status st = sa1_init(&h, &ctx);
    if (SA1_FAILED(st) || !ctx) {
        out.error = format("sa1_init: %s", sa1_status_string(st));
        return false;
    }
    sa1_coords co;
    source_coords(co);
    sa1_set_coords(ctx, &co);
    sa1_collision_grid g;
    std::memset(&g, 0, sizeof g);
    g.struct_size = sizeof g;
    g.flags = (o.keep_undersides ? SA1_GRID_KEEP_UNDERSIDES : 0u) | (o.undersides_drop ? SA1_GRID_UNDERSIDES_DROP : 0u);
    g.under_reach = o.under_reach > 0.0f ? o.under_reach : 0.0f;
    bool defaults = !o.keep_undersides && !o.undersides_drop && !(o.under_reach > 0.0f);
    sa1_collision_prepared *p = nullptr;
    st = sa1_collision_prepare_tris(ctx, tris.empty() ? nullptr : tris.data(), (uint32_t)tris.size(),
                                    defaults ? nullptr : &g, &p);
    PreparedRef ref(p);   // one reference, also when it failed
    sa1_shutdown(ctx);    // the prepared geometry keeps a copy of the allocator, not the context
    sa1_collision_prepared_info info;
    bool have = ref.info(info);
    out.ms = now_ms() - t0;
    if (SA1_FAILED(st) || !have || info.status != SA1_OK) {
        out.error = have && info.message[0] ? std::string(info.message) : std::string(sa1_status_string(st));
        out.status = have && SA1_FAILED(info.status) ? info.status : (SA1_FAILED(st) ? st : SA1_ERR_INVALID_ARGUMENT);
        return false;
    }
    out.prepared = std::move(ref);
    out.ok = true;
    out.grid_triangles = info.grid_triangles;
    out.grid_objects = info.grid_objects;
    out.grid_undersides = info.grid_undersides;
    out.grid_front_only = info.grid_front_only;   // (0 from a libsa1 before SA1_API_CEILING: struct_size gated)
    out.grid_curved = info.grid_curved;
    out.bytes = info.bytes;
    return true;
}

bool prepare_world_guarded(const std::vector<sa1_collision_tri> &tris, const float *mins, const float *maxs,
                           const PrepareOptions &o, PrepareResult &out)
{
    double t0 = now_ms();
    if (prepare_world(tris, o, out)) {
        return true;
    }
    if (out.status != SA1_ERR_LIMIT) {
        return false;   // not a size problem: as before (MapApply hands the triangles over)
    }
    const std::string first = out.error;
    // the guard's filter (bsp.hpp BspWorldOptions::guard): a corner outside the world's bounds + 64 units
    std::vector<sa1_collision_tri> kept;
    uint32_t dropped = 0;
    bool bounds = mins && maxs && maxs[0] > mins[0] && maxs[1] > mins[1] && maxs[2] > mins[2];
    if (bounds) {
        kept.reserve(tris.size());
        for (const sa1_collision_tri &t : tris) {
            bool in = (t.surface & SA1_SURFACE_KILL) != 0;
            if (!in) {
                in = true;
                for (int v = 0; v < 3 && in; v++) {
                    for (int k = 0; k < 3; k++) {
                        float c = t.v[v][k];
                        if (!(c >= mins[k] - 64.0f && c <= maxs[k] + 64.0f)) {
                            in = false;
                            break;
                        }
                    }
                }
            }
            if (in) {
                kept.push_back(t);
            } else {
                dropped++;
            }
        }
    }
    PrepareResult again;
    if (dropped > 0) {
        if (prepare_world(kept, o, again)) {
            again.retried = true;
            again.left_out = dropped;
            again.triangles = (uint32_t)tris.size();
            again.ms = now_ms() - t0;
            out = std::move(again);
            return true;
        }
    }
    const std::string lib = dropped > 0 ? again.error : first;
    out = PrepareResult();
    out.triangles = (uint32_t)tris.size();
    out.status = SA1_ERR_LIMIT;
    out.too_big = true;
    out.retried = dropped > 0;
    out.left_out = dropped;
    out.ms = now_ms() - t0;
    out.error = format("this map's collision is too big for the game: its %u triangles need more than the game's "
                       "collision memory holds (64 MB, about 2.6 to 3 million triangles once they are cut into the "
                       "game's pieces)%s, so no character can be created on this map (libsa1: %s)",
                       (unsigned)tris.size(),
                       dropped > 0 ? format(", also without the %u triangles outside the map", (unsigned)dropped).c_str()
                                   : "",
                       lib.c_str());
    return false;
}

}  // namespace gsa1
