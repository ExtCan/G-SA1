// G-SA1 core: the feature "preview" (see preview.hpp).
#include "preview.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstring>

#include "util.hpp"

namespace gsa1 {
namespace preview {

namespace {

double ms_now()
{
    using namespace std::chrono;
    return (double)duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count() / 1000.0;
}

std::string lib_error(sa1_context *ctx, const char *what, sa1_status st)
{
    const char *e = ctx ? sa1_last_error(ctx) : nullptr;
    return format("%s: %s%s%s", what, sa1_status_string(st), (e && *e) ? ": " : "", (e && *e) ? e : "");
}

}  // namespace

int32_t showcase_kind(int32_t kind)
{
    switch (kind) {
    case SA1_CHAR_SONIC:
    case SA1_CHAR_TAILS:
    case SA1_CHAR_KNUCKLES:
    case SA1_CHAR_AMY:
    case SA1_CHAR_GAMMA:
    case SA1_CHAR_BIG:
        return kind;
    default:
        return SA1_CHAR_SONIC;
    }
}

const char *code_of(sa1_status st)
{
    switch (st) {
    case SA1_ERR_NOT_FOUND:
        return "not_found";
    case SA1_ERR_GAME_FAULT:
        return "fault";
    case SA1_ERR_UNSUPPORTED:
        return "unsupported";
    case SA1_ERR_LIMIT:
        return "limit";
    case SA1_ERR_NOT_LOADED:
        return "not_ready";
    case SA1_ERR_INVALID_ARGUMENT:
        return "bad_argument";
    default:
        return sa1_status_string(st);
    }
}

void copy_render(Character &c, const sa1_render &r)
{
    c.rendered = true;
    c.r_gen = r.generation;
    c.r_alpha = r.alpha;
    c.r_interpolated = r.interpolated;
    std::memcpy(c.r_pos, r.position, sizeof c.r_pos);
    c.r_yaw = r.yaw;
    uint32_t nt = (r.positions && r.normals && r.uvs && r.colors) ? r.num_triangles : 0u;
    c.r_triangles = nt;
    if (nt) {
        c.r_tpos.assign(r.positions, r.positions + (size_t)nt * 9u);
        c.r_tnrm.assign(r.normals, r.normals + (size_t)nt * 9u);
        c.r_tuv.assign(r.uvs, r.uvs + (size_t)nt * 6u);
        c.r_tcol.assign(r.colors, r.colors + (size_t)nt * 12u);
    } else {
        c.r_tpos.clear();
        c.r_tnrm.clear();
        c.r_tuv.clear();
        c.r_tcol.clear();
    }
    if (r.draws && r.num_draws) {
        c.r_draws.assign(r.draws, r.draws + r.num_draws);
    } else {
        c.r_draws.clear();
    }
    c.shadow_draws = 0;
    for (const sa1_draw &d : c.r_draws) {
        c.shadow_draws += (d.flags & SA1_DRAW_SHADOW) ? 1u : 0u;
    }
    if (r.sprites && r.num_sprites) {
        c.r_sprites.assign(r.sprites, r.sprites + r.num_sprites);
    } else {
        c.r_sprites.clear();
    }
    uint32_t nl = r.line_vertices ? (r.num_line_vertices & ~1u) : 0u;
    if (nl) {
        c.r_lines.assign(r.line_vertices, r.line_vertices + nl);
    } else {
        c.r_lines.clear();
    }
    bool has_flags = r.struct_size >= offsetof(sa1_render, flags) + sizeof(uint32_t);
    c.r_flags = has_flags ? r.flags : 0u;
    c.r_shifted = false;
    c.r_drawn_root = false;
    c.sprite_max = 0.0f;
    for (const sa1_sprite &sp : c.r_sprites) {
        float w = std::fabs(sp.rect[2] - sp.rect[0]);
        if (std::isfinite(w)) {
            c.sprite_max = std::max(c.sprite_max, w);
        }
    }
    c.render_count++;
}

void Previews::bind(const void *ctx)
{
    if (ctx != ctx_) {
        if (!copies_.empty()) {
            forget();
        }
        ctx_ = ctx;
    }
}

void Previews::forget()
{
    if (!copies_.empty()) {
        st_.forgets++;
    }
    copies_.clear();
}

Copy *Previews::find(uint32_t id)
{
    auto it = copies_.find(id);
    return it == copies_.end() ? nullptr : it->second.get();
}

#if defined(GSA1_HAS_PREVIEW)

sa1_status Previews::add(sa1_context *ctx, const Desc &d, uint32_t &id, std::string &err)
{
    id = 0;
    if (!ctx) {
        err = "no context";
        return SA1_ERR_NOT_LOADED;
    }
    sa1_preview_desc pd;
    std::memset(&pd, 0, sizeof pd);
    pd.struct_size = sizeof pd;
    pd.kind = d.kind;
    pd.type = d.type;
    std::memcpy(pd.rotation, d.rotation, sizeof pd.rotation);
    std::memcpy(pd.params, d.params, sizeof pd.params);
    pd.state = d.state;
    pd.user_bits = d.user_bits;
    uint32_t lid = 0;
    sa1_status st = sa1_preview_add(ctx, &pd, &lid);
    if (st != SA1_OK || lid == 0) {
        err = lib_error(ctx, "sa1_preview_add", st);
        st_.last_error = err;
        if (st == SA1_ERR_GAME_FAULT) {
            st_.faults++;
        }
        return st != SA1_OK ? st : SA1_ERR_LIMIT;
    }
    std::unique_ptr<Copy> c(new Copy());
    c->id = lid;
    c->desc = d;
    c->holder.kind = d.kind;
    c->holder.id = 0;
    copies_[lid] = std::move(c);
    st_.adds++;
    id = lid;
    return SA1_OK;
}

sa1_status Previews::remove(sa1_context *ctx, uint32_t id)
{
    auto it = copies_.find(id);
    if (it == copies_.end()) {
        return SA1_ERR_NOT_FOUND;
    }
    copies_.erase(it);
    st_.removes++;
    // (NOT_FOUND from libsa1: a disc reload freed it already - gone either way)
    sa1_status st = ctx ? sa1_preview_remove(ctx, id) : SA1_OK;
    return st == SA1_ERR_NOT_FOUND ? SA1_OK : st;
}

sa1_status Previews::clear(sa1_context *ctx, size_t &count)
{
    count = copies_.size();
    copies_.clear();
    st_.clears++;
    return ctx ? sa1_preview_clear(ctx) : SA1_OK;
}

sa1_status Previews::tick(sa1_context *ctx, float dt, std::string &err)
{
    if (!ctx) {
        err = "no context";
        return SA1_ERR_NOT_LOADED;
    }
    if (!std::isfinite(dt) || dt < 0.0f) {
        dt = 0.0f;
    }
    double t0 = ms_now();
    sa1_status st = sa1_preview_tick(ctx, std::min(dt, 0.5f));
    st_.tick_ms_last = ms_now() - t0;
    st_.tick_ms_max = std::max(st_.tick_ms_max, st_.tick_ms_last);
    st_.ticks++;
    if (st != SA1_OK) {
        err = lib_error(ctx, "sa1_preview_tick", st);
        st_.last_error = err;
        if (st == SA1_ERR_GAME_FAULT) {
            st_.faults++;
        }
    }
    return st;
}

sa1_status Previews::render(Session &se, uint32_t id, float alpha, bool &changed, std::string &err)
{
    changed = false;
    Copy *c = find(id);
    sa1_context *ctx = se.ctx();
    if (!c) {
        err = "no such preview (added before a new disc load?)";
        return SA1_ERR_NOT_FOUND;
    }
    if (!ctx) {
        err = "no context";
        return SA1_ERR_NOT_LOADED;
    }
    if (!std::isfinite(alpha)) {
        alpha = 1.0f;
    }
    bool last = alpha >= 1.0f;
    if (last && c->rendered_last && c->holder.rendered) {
        sa1_preview_info pi;
        std::memset(&pi, 0, sizeof pi);
        pi.struct_size = sizeof pi;
        sa1_status si = sa1_preview_info_get(ctx, id, &pi);
        if (si == SA1_OK && pi.steps == c->steps_rendered) {
            st_.skipped++;
            return SA1_OK;
        }
    }
    const sa1_render *r = nullptr;
    sa1_status st = sa1_preview_render(ctx, id, last ? 1.0f : alpha, &r);
    if (st != SA1_OK || !r) {
        err = lib_error(ctx, "sa1_preview_render", st);
        st_.last_error = err;
        if (st == SA1_ERR_GAME_FAULT) {
            st_.faults++;
        }
        return st != SA1_OK ? st : SA1_ERR_NOT_FOUND;
    }
    copy_render(c->holder, *r);
    if (c->holder.num_archives == 0) {
        // the kind's texture archives (Session::build_batches keeps a draw's texture only below this count)
        c->holder.num_archives = se.texture_archives(c->desc.kind);
    }
    se.rebatch(c->holder);
    c->holder.view_ready = false;
    c->rendered_last = last;
    if (last) {
        sa1_preview_info pi;
        std::memset(&pi, 0, sizeof pi);
        pi.struct_size = sizeof pi;
        c->steps_rendered = sa1_preview_info_get(ctx, id, &pi) == SA1_OK ? pi.steps : 0u;
    }
    st_.renders++;
    changed = true;
    return SA1_OK;
}

sa1_status ring_places(sa1_context *ctx, int32_t kind, const objects::Desc &d, std::vector<Place> &out,
                       std::string &err)
{
    out.clear();
    if (d.type == SA1_OBJTYPE_RING) {
        out.push_back(Place());
        return SA1_OK;
    }
    if (d.type != SA1_OBJTYPE_O_GRING) {
        err = format("ring places of a ring line or circle (type %u), not of type %u", (unsigned)SA1_OBJTYPE_O_GRING,
                     (unsigned)d.type);
        return SA1_ERR_INVALID_ARGUMENT;
    }
    if (!ctx) {
        err = "no context";
        return SA1_ERR_NOT_LOADED;
    }
    objects::Desc z = d;
    z.pos[0] = z.pos[1] = z.pos[2] = 0.0f;
    std::vector<sa1_set_record> recs;
    if (!objects::make_records(z, kHuPerUnit, 0, recs, err)) {
        return SA1_ERR_INVALID_ARGUMENT;
    }
    float places[kRingsPerRecord * 3];
    uint32_t bits[kRingsPerRecord];
    for (uint32_t k = 0; k < (uint32_t)recs.size(); k++) {
        const sa1_set_record &r = recs[k];
        uint32_t n = 0;
        sa1_status st = sa1_preview_ring_places(ctx, kind, r.params, r.rotation, places, bits, kRingsPerRecord, &n);
        if (st != SA1_OK) {
            err = lib_error(ctx, "sa1_preview_ring_places", st);
            out.clear();
            return st;
        }
        for (uint32_t i = 0; i < n && i < kRingsPerRecord; i++) {
            Place p;
            for (int a = 0; a < 3; a++) {
                p.pos[a] = (float)((double)r.position[a] + (double)places[3u * i + (uint32_t)a]);
            }
            p.record = k;
            p.bit = bits[i];
            out.push_back(p);
        }
    }
    return SA1_OK;
}

#else  // a libsa1 without previews: the feature reports what it lacks

sa1_status Previews::add(sa1_context *, const Desc &, uint32_t &id, std::string &err)
{
    id = 0;
    err = "this libsa1 has no object previews (SA1_API_PREVIEW)";
    return SA1_ERR_NOT_IMPLEMENTED;
}

sa1_status Previews::remove(sa1_context *, uint32_t id)
{
    return copies_.erase(id) ? SA1_OK : SA1_ERR_NOT_FOUND;
}

sa1_status Previews::clear(sa1_context *, size_t &count)
{
    count = copies_.size();
    copies_.clear();
    return SA1_OK;
}

sa1_status Previews::tick(sa1_context *, float, std::string &)
{
    return SA1_OK;
}

sa1_status Previews::render(Session &, uint32_t, float, bool &changed, std::string &err)
{
    changed = false;
    err = "this libsa1 has no object previews (SA1_API_PREVIEW)";
    return SA1_ERR_NOT_IMPLEMENTED;
}

sa1_status ring_places(sa1_context *, int32_t, const objects::Desc &, std::vector<Place> &out, std::string &err)
{
    out.clear();
    err = "this libsa1 has no object previews (SA1_API_PREVIEW)";
    return SA1_ERR_NOT_IMPLEMENTED;
}

#endif

}  // namespace preview
}  // namespace gsa1
