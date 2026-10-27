// G-SA1 core: loading a map's collision in the background (see mapjob.hpp).
#include "mapjob.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <set>
#include <type_traits>

#include "util.hpp"

namespace gsa1 {

namespace {

const uint32_t kPipelineVersion = 6;     // bump when the cleaning changes its result (old cache files are rebuilt)
                                         // 4: surface-type tags (0.8)
                                         // 5: 0.9.2 - bounded thin-wall middle faces, open sliver hulls, thin stacks,
                                         //    the guard, no-hull displacements, coplanar down faces (one bump: the
                                         //    owner's caches rebuild once)
                                         // 6: 0.9.3 - front-only ceilings instead of left-out undersides, curved
                                         //    surfaces (sadc docs/research/gsa1_091b_ceiling.md FIX-C3,
                                         //    gsa1_091a_loop.md LOOP-G1; one bump for the round), the brushes beside a
                                         //    displacement kept (tunnel floors) and the up faces under displacement
                                         //    ground left out (disp_brush_exact, disp_cover_max: same round, same bump)
const uint32_t kCacheFormat = 5;      // 2: MapStats with the thin-wall counts; 3: surface-type tags and slots (0.8);
                                      // 4: MapStats with 0.9.2's counts; 5: MapStats with 0.9.3's counts
const char kCacheMagic[8] = {'G', 'S', 'A', '1', 'M', 'A', 'P', 'C'};
const uint64_t kMaxFed = 512ull << 20;   // bytes a map may hand over
const size_t kMaxFile = 16u << 20;       // one model file
const size_t kMaxCache = 768u << 20;     // a cache file
const size_t kMaxVmt = 256u << 10;       // one .vmt
const size_t kMaxScript = 1u << 20;      // one surfaceproperties script
const size_t kMaxFiles = 30000;          // files a map may ask the addon for
const uint32_t kMaxMaterialRounds = 4;   // Materials stages (patch includes of includes ...)
const uint32_t kMaxTypes = 8192;         // surface-type slots
const char kManifest[] = "scripts/surfaceproperties_manifest.txt";
const char kSurfaceScript[] = "scripts/surfaceproperties.txt";

static_assert(std::is_trivially_copyable<MapStats>::value, "MapStats is stored as bytes in the cache");

struct CacheHeader {
    char magic[8];
    uint32_t format;
    uint32_t options;                    // MapJobOptions::hash()
    uint32_t key_crc;                    // CRC-32 of the map's header (1036 bytes)
    uint32_t payload_crc;
    uint64_t map_size;
    uint64_t payload_bytes;
    uint32_t world_tris, models, stats_bytes, reserved;
};
static_assert(sizeof(CacheHeader) == 56, "cache header");

uint32_t fnv1a(const std::string &s)
{
    uint32_t h = 2166136261u;
    for (unsigned char c : s) {
        h = (h ^ c) * 16777619u;
    }
    return h;
}

void put(std::string &o, const void *p, size_t n)
{
    o.append((const char *)p, n);
}

template <class T> void put_v(std::string &o, const T &v)
{
    put(o, &v, sizeof v);
}

struct ByteReader {
    const uint8_t *p;
    size_t n, pos = 0;
    bool get(void *dst, size_t k)
    {
        if (k > n - pos) {
            return false;
        }
        std::memcpy(dst, p + pos, k);
        pos += k;
        return true;
    }
    template <class T> bool v(T &x) { return get(&x, sizeof x); }
};

bool tri_ok(const sa1_collision_tri &t, float lim)
{
    for (int v = 0; v < 3; v++) {
        for (int k = 0; k < 3; k++) {
            if (!std::isfinite(t.v[v][k]) || std::fabs(t.v[v][k]) > lim) {
                return false;
            }
        }
    }
    return true;
}

std::string serialize(const MapResult &res, uint32_t options, uint32_t key, uint64_t size)
{
    std::string pl;
    uint32_t sb = (uint32_t)sizeof(MapStats);
    put(pl, &res.st, sizeof res.st);
    put(pl, res.world.data(), res.world.size() * sizeof(sa1_collision_tri));
    put_v(pl, (uint32_t)res.world_tag.size());
    put(pl, res.world_tag.data(), res.world_tag.size() * sizeof(uint32_t));
    for (const auto &kv : res.models) {
        const Shape &s = kv.second;
        put_v(pl, (int32_t)kv.first);
        put_v(pl, (uint32_t)s.chunks.size());
        put_v(pl, s.tris);
        put(pl, s.mins, sizeof s.mins);
        put(pl, s.maxs, sizeof s.maxs);
        for (const ShapeChunk &c : s.chunks) {
            put(pl, c.center, sizeof c.center);
            put_v(pl, c.radius);
            put_v(pl, (uint32_t)c.tris.size());
            put(pl, c.tris.data(), c.tris.size() * sizeof(sa1_collision_tri));
        }
    }
    // the surface-type slots: letter, chain (Review G1: a cache hit needs no surfaceproperties script)
    put_v(pl, (uint32_t)res.types.size());
    for (const SurfaceType &t : res.types) {
        put_v(pl, (uint8_t)t.letter);
        put_v(pl, (uint8_t)t.chain.size());
        for (const std::string &n : t.chain) {
            put_v(pl, (uint8_t)n.size());
            put(pl, n.data(), n.size());
        }
    }
    CacheHeader h;
    std::memset(&h, 0, sizeof h);
    std::memcpy(h.magic, kCacheMagic, 8);
    h.format = kCacheFormat;
    h.options = options;
    h.key_crc = key;
    h.payload_crc = crc32(pl.data(), pl.size());
    h.map_size = size;
    h.payload_bytes = pl.size();
    h.world_tris = (uint32_t)res.world.size();
    h.models = (uint32_t)res.models.size();
    h.stats_bytes = sb;
    std::string out;
    out.reserve(sizeof h + pl.size());
    put(out, &h, sizeof h);
    out += pl;
    return out;
}

// a cache file (untrusted: a server's Lua can write into garrysmod/data) -> the result; false + why
bool deserialize(const std::string &data, uint32_t options, uint32_t key, uint64_t size, MapResult &out, std::string &why)
{
    CacheHeader h;
    if (data.size() < sizeof h) {
        why = "the cache file is truncated";
        return false;
    }
    std::memcpy(&h, data.data(), sizeof h);
    if (std::memcmp(h.magic, kCacheMagic, 8) != 0 || h.format != kCacheFormat) {
        why = "the cache file has another format";
        return false;
    }
    if (h.key_crc != key || h.map_size != size) {
        why = "the map changed since the cache file was written";
        return false;
    }
    if (h.options != options) {
        why = "the cache file was built with other settings";
        return false;
    }
    if (h.payload_bytes != data.size() - sizeof h || h.stats_bytes != sizeof(MapStats)) {
        why = "the cache file is damaged (sizes)";
        return false;
    }
    const uint8_t *pl = (const uint8_t *)data.data() + sizeof h;
    if (crc32(pl, (size_t)h.payload_bytes) != h.payload_crc) {
        why = "the cache file is damaged (checksum)";
        return false;
    }
    ByteReader in{pl, (size_t)h.payload_bytes};
    MapResult res;
    if (!in.get(&res.st, sizeof res.st) || h.world_tris > SA1_MAX_COLLISION_TRIS ||
        (uint64_t)h.world_tris * sizeof(sa1_collision_tri) > in.n - in.pos || h.models > 65536) {
        why = "the cache file is damaged (counts)";
        return false;
    }
    res.world.resize(h.world_tris);
    in.get(res.world.data(), res.world.size() * sizeof(sa1_collision_tri));
    for (const sa1_collision_tri &t : res.world) {
        if (!tri_ok(t, 65536.0f)) {
            why = "the cache file is damaged (world)";
            return false;
        }
    }
    uint32_t ntags = 0;
    if (!in.v(ntags) || (ntags != 0 && ntags != h.world_tris) || (uint64_t)ntags * sizeof(uint32_t) > in.n - in.pos) {
        why = "the cache file is damaged (surface tags)";
        return false;
    }
    res.world_tag.resize(ntags);
    in.get(res.world_tag.data(), res.world_tag.size() * sizeof(uint32_t));
    for (uint32_t m = 0; m < h.models; m++) {
        int32_t id;
        uint32_t nchunks, tris;
        Shape s;
        if (!in.v(id) || !in.v(nchunks) || !in.v(tris) || !in.get(s.mins, sizeof s.mins) || !in.get(s.maxs, sizeof s.maxs) ||
            id <= 0 || nchunks == 0 || nchunks > 4096) {
            why = "the cache file is damaged (models)";
            return false;
        }
        s.tris = tris;
        uint32_t sum = 0;
        for (uint32_t c = 0; c < nchunks; c++) {
            ShapeChunk ch;
            uint32_t nt;
            if (!in.get(ch.center, sizeof ch.center) || !in.v(ch.radius) || !in.v(nt) || nt == 0 ||
                nt > SA1_MAX_OBJECT_TRIS || (uint64_t)nt * sizeof(sa1_collision_tri) > in.n - in.pos ||
                !std::isfinite(ch.radius) || ch.radius > 4.0f * SA1_MAX_OBJECT_RADIUS) {
                why = "the cache file is damaged (chunks)";
                return false;
            }
            ch.tris.resize(nt);
            in.get(ch.tris.data(), nt * sizeof(sa1_collision_tri));
            for (const sa1_collision_tri &t : ch.tris) {
                if (!tri_ok(t, 4.0f * SA1_MAX_OBJECT_RADIUS)) {
                    why = "the cache file is damaged (chunk triangles)";
                    return false;
                }
            }
            for (int k = 0; k < 3; k++) {
                if (!std::isfinite(ch.center[k]) || std::fabs(ch.center[k]) > 65536.0f) {
                    why = "the cache file is damaged (chunk centre)";
                    return false;
                }
            }
            sum += nt;
            s.chunks.push_back(std::move(ch));
        }
        if (sum != tris) {
            why = "the cache file is damaged (model triangles)";
            return false;
        }
        res.models[id] = std::move(s);
    }
    uint32_t ntypes = 0;
    if (!in.v(ntypes) || ntypes > kMaxTypes) {
        why = "the cache file is damaged (surface types)";
        return false;
    }
    res.types.resize(ntypes);
    for (SurfaceType &t : res.types) {
        uint8_t letter = 0, nchain = 0;
        if (!in.v(letter) || !in.v(nchain) || nchain == 0 || nchain > 16) {
            why = "the cache file is damaged (surface type)";
            return false;
        }
        t.letter = (char)letter;
        for (uint8_t c = 0; c < nchain; c++) {
            uint8_t len = 0;
            std::string n;
            if (!in.v(len) || len == 0 || len > in.n - in.pos) {
                why = "the cache file is damaged (surface type name)";
                return false;
            }
            n.resize(len);
            in.get(&n[0], len);
            if (!valid_surface_name(n)) {
                why = "the cache file is damaged (surface type name)";
                return false;
            }
            t.chain.push_back(std::move(n));
        }
    }
    for (uint32_t tag : res.world_tag) {
        uint32_t a = tag & 0xFFFFu, b = tag >> 16;
        if ((a != kNoSurface && a >= ntypes) || (b != kNoSurface && b != kHiddenSurface && b >= ntypes)) {
            why = "the cache file is damaged (surface tag)";
            return false;
        }
    }
    if (in.pos != in.n) {
        why = "the cache file is damaged (trailing bytes)";
        return false;
    }
    out = std::move(res);
    return true;
}

std::string phy_path(const std::string &mdl)
{
    if (mdl.size() < 5 || mdl.compare(mdl.size() - 4, 4, ".mdl") != 0) {
        return std::string();
    }
    return mdl.substr(0, mdl.size() - 4) + ".phy";
}

}  // namespace

uint32_t crc32(const void *p, size_t n, uint32_t crc)
{
    static const struct Table {
        uint32_t t[256];
        Table()
        {
            for (uint32_t i = 0; i < 256; i++) {
                uint32_t c = i;
                for (int k = 0; k < 8; k++) {
                    c = (c & 1u) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                }
                t[i] = c;
            }
        }
    } table;
    const uint8_t *b = (const uint8_t *)p;
    crc = ~crc;
    for (size_t i = 0; i < n; i++) {
        crc = table.t[(crc ^ b[i]) & 0xFFu] ^ (crc >> 8);
    }
    return ~crc;
}

bool solid_brush_class(const std::string &c)
{
    static const char *const kSolid[] = {
        "func_door",        "func_door_rotating", "func_movelinear",   "func_tracktrain",       "func_tanktrain",
        "func_train",       "func_rotating",      "func_platrot",      "func_plat",             "func_brush",
        "func_wall",        "func_wall_toggle",   "func_breakable",    "func_breakable_surf",   "func_physbox",
        "func_physbox_multiplayer", "func_pushable", "func_button",    "func_rot_button",       "momentary_rot_button",
        "func_lookdoor",    "func_conveyor",      "func_reflective_glass", "func_monitor",      "func_lod",
        "func_guntarget",   "func_detail_blocker",
    };
    for (const char *k : kSolid) {
        if (c == k) {
            return true;
        }
    }
    return false;
}

uint32_t MapJobOptions::hash() const
{
    const BspWorldOptions &w = world;
    BspWorldOptions m = mover_options(w.thin_wall_max);   // the brush models are cleaned with the world's thin walls
    std::string s = format("pipeline %u; sp %d %.3f; bm %d; w %d %d %d %d %d %.3f %u %d %d %d %d %.3f %.3f %d %.3f %d %d "
                           "%.3f %d %.3f %.3f; m %.3f %.3f %d %.3f %.3f %u %.3f %.3f; tw %.3f %.3f; st %d",
                           kPipelineVersion, (int)static_props, prop_min_size, (int)brush_models, (int)w.displacements,
                           (int)w.water, (int)w.playerclip, (int)w.skip_displacement_brushes, (int)w.kill_plane,
                           w.kill_margin, (unsigned)w.max_triangles, (int)w.disp_transpose, (int)w.disp_tags,
                           (int)w.disp_side_flip, (int)w.remove_hidden, w.one_way_max, w.one_way_walkable,
                           (int)w.one_way_cross, w.thin_floor_min, (int)w.stair_ramps, (int)w.stair_min_steps,
                           w.stair_max_rise, (int)w.stair_flag, w.tess_max, w.low_ceiling_max, m.one_way_max,
                           m.thin_floor_min, (int)m.one_way_cross, m.tess_max, kChunkRadius, (unsigned)kChunkTris,
                           m.one_way_walkable, m.low_ceiling_max, w.thin_wall_max, m.thin_wall_max,
                           (int)surface_types);
    // 0.9.2's rules (world and moving objects)
    s += format("; 092 %d %d %d %d %d %d %d %d", (int)w.thin_stacks, (int)w.guard, (int)w.disp_nohull,
                (int)w.coplanar_down, (int)m.thin_stacks, (int)m.guard, (int)m.disp_nohull, (int)m.coplanar_down);
    // 0.9.3's rules (front-only ceilings, curved surfaces); the GRID's undersides_drop is applied at preparation (not here)
    s += format("; 093 %d %d %.3f %.3f %.3f; %d %d %.3f %.3f %.3f", (int)w.one_way_front_only, (int)w.curved,
                w.curved_max_angle, w.curved_min_radius, w.curved_ribbon_max, (int)m.one_way_front_only, (int)m.curved,
                m.curved_max_angle, m.curved_min_radius, m.curved_ribbon_max);
    // 0.9.3's tunnel floors and buried up faces (world only: brush models have no displacements)
    s += format("; 093t %d %.3f", (int)w.disp_brush_exact, w.disp_cover_max);
    return fnv1a(s);
}

const char *map_state_name(MapState s)
{
    switch (s) {
    case MapState::Idle: return "idle";
    case MapState::Cache: return "cache";
    case MapState::Reading: return "reading";
    case MapState::Parsing: return "parsing";
    case MapState::Files: return "files";
    case MapState::Materials: return "materials";
    case MapState::Building: return "building";
    case MapState::Preparing: return "preparing";
    case MapState::Ready: return "ready";
    case MapState::Failed: return "failed";
    }
    return "?";
}

MapJob::MapJob() {}

MapJob::~MapJob()
{
    cancel();
}

std::string MapJob::error() const
{
    std::lock_guard<std::mutex> g(m_);
    return error_;
}

void MapJob::fail(const std::string &msg)
{
    std::lock_guard<std::mutex> g(m_);
    if (error_.empty()) {
        error_ = msg;
    }
}

double MapJob::elapsed_ms() const
{
    return t0_ > 0.0 ? now_ms() - t0_ : 0.0;
}

bool MapJob::start_common(const std::string &map, const MapJobOptions &o, std::string &err)
{
    if (state() != MapState::Idle) {
        err = "this map job was started already";
        return false;
    }
    map_ = map;
    opt_ = o;
    t0_ = now_ms();
    key_crc_ = crc32(header_, sizeof header_);
    result_ = MapResult();
    result_.map = map;
    return true;
}

bool MapJob::start_file(const std::string &map, const std::string &path, const MapJobOptions &o, std::string &err)
{
    std::unique_ptr<FileByteSource> f(new FileByteSource());
    if (!f->open(path, err)) {
        return false;
    }
    if (f->size() < sizeof header_ || !f->read(0, header_, sizeof header_)) {
        err = "not a BSP file (too short)";
        return false;
    }
    std::unique_ptr<Bsp> b(new Bsp());
    if (!b->open(*f, err)) {
        return false;
    }
    size_ = f->size();
    if (!start_common(map, o, err)) {
        return false;
    }
    path_ = path;
    fed_mode_ = false;
    src_ = std::move(f);
    bsp_ = std::move(b);
    run_worker(MapState::Cache);
    return true;
}

bool MapJob::start_fed(const std::string &map, const void *header, size_t n, uint64_t size, const MapJobOptions &o,
                       std::string &err)
{
    if (!header || n < sizeof header_ || size < sizeof header_ || size > (4ull << 30)) {
        err = "not a BSP file (header)";
        return false;
    }
    std::unique_ptr<RangeByteSource> rs(new RangeByteSource(size));
    rs->add(0, header, sizeof header_);
    std::unique_ptr<Bsp> b(new Bsp());
    if (!b->open(*rs, err)) {
        return false;
    }
    std::memcpy(header_, header, sizeof header_);
    size_ = size;
    if (!start_common(map, o, err)) {
        return false;
    }
    fed_mode_ = true;
    ranges_ = rs.get();
    src_ = std::move(rs);
    bsp_ = std::move(b);
    run_worker(MapState::Cache);
    return true;
}

void MapJob::run_worker(MapState stage)
{
    set_state(stage);
    worker_done_ = false;
    worker_ok_ = false;
    worker_running_ = true;
    worker_ = std::thread([this, stage]() {
        try {
            if (cancel_) {
                fail("cancelled");
            } else if (stage == MapState::Cache) {
                stage_cache();
            } else if (stage == MapState::Parsing) {
                stage_parse();
            } else if (stage == MapState::Materials) {
                stage_materials();
            } else if (stage == MapState::Building) {
                stage_build();
            } else if (stage == MapState::Preparing) {
                stage_prepare();
            }
        } catch (const std::exception &e) {
            fail(std::string("internal error: ") + e.what());
            worker_ok_ = false;
        } catch (...) {
            fail("internal error");
            worker_ok_ = false;
        }
        worker_done_ = true;
    });
}

void MapJob::wait()
{
    if (worker_running_ && worker_.joinable()) {
        worker_.join();
    }
}

void MapJob::cancel()
{
    cancel_ = true;
    if (worker_.joinable()) {
        worker_.join();
    }
    worker_running_ = false;
    MapState s = state();
    if (s != MapState::Ready && s != MapState::Failed && s != MapState::Idle) {
        fail("cancelled");
        set_state(MapState::Failed);
    }
}

void MapJob::poll()
{
    if (worker_running_) {
        if (!worker_done_) {
            return;
        }
        if (worker_.joinable()) {
            worker_.join();
        }
        worker_running_ = false;
        MapState s = state();
        if (!worker_ok_ || cancel_) {
            fail(cancel_ ? "cancelled" : "failed");
            set_state(MapState::Failed);
            progress_ = 1.0f;
            return;
        }
        if (s == MapState::Cache) {
            if (cache_hit_) {
                result_.st.total_ms = elapsed_ms();
                if (opt_.prepare) {
                    run_worker(MapState::Preparing);
                } else {
                    result_.ready_ms = elapsed_ms();
                    set_state(MapState::Ready);
                    progress_ = 1.0f;
                }
            } else if (fed_mode_) {
                set_state(MapState::Reading);
                progress_ = 0.05f;
            } else {
                run_worker(MapState::Parsing);
            }
        } else if (s == MapState::Parsing) {
            files_total_ = (uint32_t)files_.size();
            if (!files_.empty()) {
                set_state(MapState::Files);
                progress_ = 0.55f;
            } else {
                run_worker(MapState::Building);
            }
        } else if (s == MapState::Materials) {
            // the .vmt / scripts were parsed: their includes and the manifest's files are another round of files
            files_total_ = (uint32_t)files_.size();
            if (files_done_ < files_.size()) {
                set_state(MapState::Files);
            } else {
                run_worker(MapState::Building);
            }
        } else if (s == MapState::Building) {
            result_.st.total_ms = elapsed_ms();
            if (opt_.prepare) {
                run_worker(MapState::Preparing);
            } else {
                result_.ready_ms = elapsed_ms();
                set_state(MapState::Ready);
                progress_ = 1.0f;
            }
        } else if (s == MapState::Preparing) {
            result_.ready_ms = elapsed_ms();
            set_state(MapState::Ready);
            progress_ = 1.0f;
        }
        return;
    }
    MapState s = state();
    if (s == MapState::Reading) {
        uint64_t need = bytes_needed();
        if (need == 0) {
            result_.st.bytes_fed = fed_bytes_;
            run_worker(MapState::Parsing);
        } else {
            progress_ = 0.05f + 0.4f * (float)((double)fed_bytes_ / (double)(fed_bytes_ + need));
        }
    } else if (s == MapState::Files) {
        if (files_done_ >= files_.size()) {
            result_.st.files_fed = files_done_;
            run_worker(unparsed_ > 0 ? MapState::Materials : MapState::Building);
        } else {
            progress_ = 0.55f + 0.1f * (float)files_done_ / (float)files_.size();
        }
    }
}

void MapJob::needs(std::vector<std::pair<uint64_t, uint64_t>> &out, size_t max_ranges, uint64_t max_bytes)
{
    out.clear();
    if (state() != MapState::Reading || !ranges_ || worker_running_) {
        return;
    }
    std::vector<std::pair<uint64_t, uint64_t>> all, gaps;
    bsp_->needed_ranges(all);
    std::sort(all.begin(), all.end());
    for (const auto &rg : all) {
        ranges_->missing(rg.first, rg.second, gaps);
    }
    std::sort(gaps.begin(), gaps.end());
    uint64_t piece = std::max<uint64_t>(max_bytes, 4096);
    uint64_t last_end = 0;
    for (const auto &g : gaps) {
        uint64_t o = std::max(g.first, last_end), e = g.first + g.second;   // overlapping lump ranges: once
        while (o < e && out.size() < max_ranges) {
            uint64_t l = std::min(piece, e - o);
            out.push_back({o, l});
            o += l;
        }
        last_end = std::max(last_end, e);
        if (out.size() >= max_ranges) {
            break;
        }
    }
}

uint64_t MapJob::bytes_needed()
{
    std::vector<std::pair<uint64_t, uint64_t>> n;
    needs(n, (size_t)-1, ~0ull);
    uint64_t sum = 0;
    for (const auto &rg : n) {
        sum += rg.second;
    }
    return sum;
}

bool MapJob::feed(uint64_t ofs, const void *p, size_t n, std::string &err)
{
    if (state() != MapState::Reading || !ranges_ || worker_running_) {
        err = "the map job is not reading";
        return false;
    }
    if (!p || !ranges_->add(ofs, p, n)) {
        err = "the bytes lie outside the map";
        return false;
    }
    fed_bytes_ += n;
    if (ranges_->bytes() > kMaxFed) {
        fail("the map handed over more than 512 MB");
        set_state(MapState::Failed);
        err = "too much data";
        return false;
    }
    return true;
}

void MapJob::files(std::vector<std::pair<std::string, uint32_t>> &out, size_t max) const
{
    out.clear();
    if (state() != MapState::Files) {
        return;
    }
    for (const auto &kv : files_) {
        if (out.size() >= max) {
            break;
        }
        if (!kv.second.done) {
            out.push_back({kv.first, kv.second.max});
        }
    }
}

bool MapJob::feed_file(const std::string &path, const void *p, size_t n, std::string &err)
{
    if (state() != MapState::Files) {
        err = "the map job is not waiting for model files";
        return false;
    }
    auto it = files_.find(path);
    if (it == files_.end()) {
        err = "the map job did not ask for this file";
        return false;
    }
    FileEntry &e = it->second;
    if (e.done) {
        return true;
    }
    size_t limit = e.kind == FileKind::Vmt ? kMaxVmt : e.kind == FileKind::Script ? kMaxScript : kMaxFile;
    if (!p || (e.max == 0 && n > limit)) {
        e.missing = true;
    } else {
        e.data.assign((const char *)p, e.max ? std::min<size_t>(n, e.max) : n);
    }
    e.done = true;
    files_done_++;
    if (e.kind == FileKind::Vmt || e.kind == FileKind::Script) {
        unparsed_++;
    }
    return true;
}

bool MapJob::take(MapResult &out)
{
    if (state() != MapState::Ready || taken_) {
        return false;
    }
    out = std::move(result_);
    taken_ = true;
    return true;
}

// ---- the stages (worker thread) -------------------------------------------------------------------------------------
void MapJob::stage_cache()
{
    cache_hit_ = false;
    worker_ok_ = true;
    if (opt_.cache_dir.empty()) {
        result_.cache_note = "no cache directory";
        return;
    }
    std::string path = join_path(opt_.cache_dir, map_ + ".dat");
    if (!file_exists(path)) {
        result_.cache_note = "not in the cache yet";
        return;
    }
    double t = now_ms();
    std::string data, err;
    if (!read_small_file(path, kMaxCache, data, err)) {
        result_.cache_note = "the cache file cannot be read: " + err;
        return;
    }
    MapResult r;
    std::string why;
    if (!deserialize(data, opt_.hash(), key_crc_, size_, r, why)) {
        result_.cache_note = why;
        return;
    }
    r.map = map_;
    r.from_cache = true;
    r.cache_ms = now_ms() - t;
    result_ = std::move(r);
    cache_hit_ = true;
    apply_classes();   // the class table of this job on the cached tags (no surfaceproperties script needed: G1)
    progress_ = 0.9f;
}

// the surface classes of opt_.surfaces on the tagged world (worker; after a build's cache write and after a cache hit)
void MapJob::apply_classes()
{
    apply_surface_classes(result_.world, result_.world_tag, result_.types, opt_.surfaces, result_.surf);
}

void MapJob::stage_parse()
{
    double t = now_ms();
    std::string err;
    if (!bsp_->load(err)) {
        fail(err);
        return;
    }
    progress_ = 0.5f;
    MapStats &st = result_.st;
    // brush models of the solid brush entities (func_brush with Solidity 1 is never solid)
    std::vector<BspEntity> ents;
    std::set<int32_t> ids;
    std::string eerr;
    int32_t nmodels = bsp_->model_count();
    if (bsp_->entities(ents, eerr)) {
        st.entities = (uint32_t)ents.size();
        for (const BspEntity &e : ents) {
            const std::string *cls = e.get("classname"), *model = e.get("model");
            if (!cls || !model || model->size() < 2 || (*model)[0] != '*' || !solid_brush_class(*cls)) {
                continue;
            }
            const std::string *sol = e.get("Solidity");
            if (*cls == "func_brush" && sol && *sol == "1") {
                continue;
            }
            int32_t id = std::atoi(model->c_str() + 1);
            if (id > 0 && id < nmodels) {
                ids.insert(id);
                st.brush_entities++;
            }
        }
    }
    if (opt_.brush_models) {
        model_ids_.assign(ids.begin(), ids.end());
    }
    // static props: the model files they need
    if (opt_.static_props) {
        BspPropInfo info;
        std::string perr;
        if (!bsp_->static_props(props_, info, perr)) {
            result_.props_note = perr;
            props_.clear();
        }
        st.props = info.props;
        st.prop_version = info.version;
        for (const BspStaticProp &p : props_) {
            if (p.solid == 6) {
                std::string path = phy_path(p.model);
                if (!path.empty()) {
                    files_[path].max = 0;
                    st.props_solid++;
                }
            } else if (p.solid == 2) {
                files_[p.model].max = 136;
                files_[p.model].kind = FileKind::Mdl;
                st.props_solid++;
            }
        }
        st.prop_models = (uint32_t)files_.size();
    }
    // surface types (0.8): the .vmt of every material a collision face uses, and the surfaceproperties scripts (the
    // manifest, with GMod's own script as the fallback); patch includes and the manifest's files follow in Materials
    if (opt_.surface_types) {
        std::string merr;
        if (bsp_->materials(mats_, merr)) {
            st.materials = (uint32_t)mats_.names.size();
            st.materials_bad = mats_.bad;
            for (size_t i = 0; i < mats_.names.size(); i++) {
                if (!mats_.used[i]) {
                    continue;
                }
                st.materials_used++;
                std::string path = vmt_path(mats_.names[i]);
                if (path.empty() || files_.size() >= kMaxFiles) {
                    st.materials_bad++;
                    continue;
                }
                files_[path].kind = FileKind::Vmt;
            }
        }
        files_[kManifest].kind = FileKind::Script;
        files_[kSurfaceScript].kind = FileKind::Script;
    }
    st.parse_ms = now_ms() - t;
    progress_ = 0.55f;
    worker_ok_ = true;
}

// the .vmt files and scripts fed since the last round: parsed; the materials patches include and the files the
// manifest lists are added for the next Files round (Review G2: on the worker, not in poll())
void MapJob::stage_materials()
{
    MapStats &st = result_.st;
    round_++;
    st.material_rounds = round_;
    std::vector<std::pair<std::string, FileKind>> add;
    for (auto &kv : files_) {
        FileEntry &e = kv.second;
        if (!e.done || e.parsed || (e.kind != FileKind::Vmt && e.kind != FileKind::Script)) {
            continue;
        }
        e.parsed = true;
        if (e.kind == FileKind::Vmt) {
            if (e.missing || e.data.empty()) {
                st.vmt_missing++;
            } else {
                VmtInfo vi;
                std::string perr;
                if (parse_vmt(e.data.data(), e.data.size(), vi, perr)) {
                    st.vmt_found++;
                    if (vi.shader == "patch") {
                        st.vmt_patches++;
                        if (!vi.include.empty() && round_ < kMaxMaterialRounds) {
                            add.push_back({vi.include, FileKind::Vmt});
                        }
                    }
                    vmts_[kv.first] = std::move(vi);
                } else {
                    st.vmt_bad++;
                }
            }
            std::string().swap(e.data);
        } else if (kv.first == kManifest && !e.missing && !e.data.empty()) {
            std::vector<std::string> list;
            std::string perr;
            if (SurfacePropDb::parse_manifest(e.data.data(), e.data.size(), list, perr) && !list.empty()) {
                manifest_files_ = list;
                manifest_ok_ = true;
                for (const std::string &f : list) {
                    add.push_back({f, FileKind::Script});
                }
            }
        }
        if (cancel_) {
            return;
        }
    }
    for (const auto &a : add) {
        if (!files_.count(a.first) && files_.size() < kMaxFiles) {
            files_[a.first].kind = a.second;
        }
    }
    unparsed_ = 0;
    progress_ = 0.6f;
    worker_ok_ = true;
}

void MapJob::stage_build()
{
    double t = now_ms();
    MapStats &st = result_.st;
    std::string err;
    // the model files
    std::map<std::string, PhyModel> phys;
    std::map<std::string, std::vector<float>> boxes;
    for (auto &kv : files_) {
        FileEntry &e = kv.second;
        if (e.kind != FileKind::Phy && e.kind != FileKind::Mdl) {
            continue;   // materials and scripts (below)
        }
        if (e.missing || e.data.empty()) {
            st.prop_models_missing++;
            continue;
        }
        std::string perr;
        if (e.kind == FileKind::Phy) {
            PhyModel m;
            if (parse_phy(e.data.data(), e.data.size(), m, perr)) {
                phys[kv.first] = std::move(m);
            } else {
                st.prop_models_bad++;
            }
        } else {
            float mn[3], mx[3];
            if (parse_mdl_hull(e.data.data(), e.data.size(), mn, mx, perr)) {
                boxes[kv.first] = {mn[0], mn[1], mn[2], mx[0], mx[1], mx[2]};
            } else {
                st.prop_models_bad++;
            }
        }
        std::string().swap(e.data);
        if (cancel_) {
            return;
        }
    }
    progress_ = 0.7f;
    // surface types (0.8): the scripts' types (every one gets a slot, so the Q menu lists them all), the materials'
    // $surfaceprop / $surfaceprop2 through their .vmt (patches followed), per TEXDATA entry a slot
    SurfacePropDb db;
    std::vector<SurfaceType> &types = result_.types;
    std::map<std::string, uint16_t> type_index;
    auto slot = [&](const std::string &name) -> uint16_t {
        if (name.empty() || !valid_surface_name(name)) {
            return kNoSurface;
        }
        auto it = type_index.find(name);
        if (it != type_index.end()) {
            return it->second;
        }
        if (types.size() >= kMaxTypes) {
            return kNoSurface;
        }
        uint16_t sl = (uint16_t)types.size();
        types.push_back(db.resolve(name));
        type_index[name] = sl;
        return sl;
    };
    BspSurfaceSlots slots;
    if (opt_.surface_types) {
        std::vector<std::string> scripts = manifest_ok_ ? manifest_files_ : std::vector<std::string>{kSurfaceScript};
        for (const std::string &f : scripts) {
            auto it = files_.find(f);
            std::string perr;
            if (it != files_.end() && !it->second.missing && !it->second.data.empty() &&
                db.add_script(it->second.data.data(), it->second.data.size(), perr)) {
                st.surface_scripts++;
            }
        }
        for (auto &kv : files_) {
            if (kv.second.kind == FileKind::Script) {
                std::string().swap(kv.second.data);
            }
        }
        for (const std::string &n : db.names()) {
            slot(n);
        }
        const uint16_t def = slot("default");
        auto lookup = [&](const std::string &path) -> const VmtInfo * {
            auto it = vmts_.find(path);
            return it == vmts_.end() ? nullptr : &it->second;
        };
        std::vector<uint16_t> name_sp(mats_.names.size(), def), name_sp2(mats_.names.size(), kNoSurface);
        for (size_t i = 0; i < mats_.names.size(); i++) {
            if (!mats_.used[i]) {
                continue;
            }
            VmtSurface vs = resolve_vmt(vmt_path(mats_.names[i]), lookup);
            uint16_t a = slot(vs.sp);
            name_sp[i] = a != kNoSurface ? a : def;
            if (!vs.sp2.empty()) {
                name_sp2[i] = slot(vs.sp2);
                st.vmt_blends++;
            }
            st.vmt_default += !vs.found || !vs.explicit_sp;
            st.vmt_includes_missing += vs.include_missing;
        }
        slots.sp.assign(mats_.texdata_name.size(), def);
        slots.sp2.assign(mats_.texdata_name.size(), kNoSurface);
        for (size_t td = 0; td < mats_.texdata_name.size(); td++) {
            int32_t ni = mats_.texdata_name[td];
            if (ni >= 0) {
                slots.sp[td] = name_sp[(size_t)ni];
                slots.sp2[td] = name_sp2[(size_t)ni];
            }
        }
        std::map<std::string, VmtInfo>().swap(vmts_);
    }
    progress_ = 0.72f;
    // the static props' convex pieces, placed: world = origin + R(angles) * (scale * model)
    std::vector<ConvexSolid> solids;
    // the guard (0.9.2, gsa1_090_water.md GRID-GUARD): a prop whose pieces all lie outside the world model's bounds + 64
    // units is not placed (build_world leaves out the triangles of the others that reach out there)
    float wmn[3], wmx[3];
    const bool guard = opt_.world.guard && bsp_->model_bounds(0, wmn, wmx);
    auto outside_world = [&](size_t first) {
        if (!guard || first >= solids.size()) {
            return false;
        }
        for (size_t i = first; i < solids.size(); i++) {
            const std::vector<float> &t = solids[i].tris;
            for (size_t k = 0; k + 2 < t.size(); k += 3) {
                if (t[k] >= wmn[0] - 64.0f && t[k] <= wmx[0] + 64.0f && t[k + 1] >= wmn[1] - 64.0f &&
                    t[k + 1] <= wmx[1] + 64.0f && t[k + 2] >= wmn[2] - 64.0f && t[k + 2] <= wmx[2] + 64.0f) {
                    return false;   // a corner inside
                }
            }
        }
        return true;
    };
    for (const BspStaticProp &p : props_) {
        if (p.solid != 6 && p.solid != 2) {
            continue;
        }
        float m[9];
        angle_matrix(p.angles, m);
        const float sc = p.scale;
        const size_t first = solids.size();
        if (p.solid == 6) {
            auto it = phys.find(phy_path(p.model));
            if (it == phys.end()) {
                st.props_missing++;
                continue;
            }
            const PhyModel &pm = it->second;
            double dx = pm.maxs[0] - pm.mins[0], dy = pm.maxs[1] - pm.mins[1], dz = pm.maxs[2] - pm.mins[2];
            if (std::sqrt(dx * dx + dy * dy + dz * dz) * sc < opt_.prop_min_size) {
                st.props_small++;
                continue;
            }
            uint32_t hulls = 0;
            for (size_t hi = 0; hi < pm.hulls.size(); hi++) {
                const std::vector<float> &h = pm.hulls[hi];
                ConvexSolid cs;
                if (opt_.surface_types && hi < pm.hull_solid.size() && pm.hull_solid[hi] < pm.solid_surfaceprop.size()) {
                    cs.sp = slot(pm.solid_surfaceprop[pm.hull_solid[hi]]);
                    st.props_surfaceprop += cs.sp != kNoSurface;
                }
                cs.tris.resize(h.size());
                for (size_t i = 0; i + 2 < h.size(); i += 3) {
                    float v[3] = {h[i] * sc, h[i + 1] * sc, h[i + 2] * sc};
                    for (int r = 0; r < 3; r++) {
                        cs.tris[i + (size_t)r] = p.origin[r] + m[3 * r] * v[0] + m[3 * r + 1] * v[1] + m[3 * r + 2] * v[2];
                    }
                }
                solids.push_back(std::move(cs));
                hulls++;
            }
            if (outside_world(first)) {
                solids.resize(first);
                st.props_outside++;
                continue;
            }
            st.props_hulls += hulls;
            st.props_placed++;
        } else {
            auto it = boxes.find(p.model);
            if (it == boxes.end()) {
                st.props_missing++;
                continue;
            }
            const std::vector<float> &b = it->second;
            float mn[3] = {b[0] * sc, b[1] * sc, b[2] * sc}, mx[3] = {b[3] * sc, b[4] * sc, b[5] * sc};
            double dx = mx[0] - mn[0], dy = mx[1] - mn[1], dz = mx[2] - mn[2];
            if (std::sqrt(dx * dx + dy * dy + dz * dz) < opt_.prop_min_size) {
                st.props_small++;
                continue;
            }
            ConvexSolid cs;
            box_solid(mn, mx, m, p.origin, cs);
            solids.push_back(std::move(cs));
            if (outside_world(first)) {
                solids.resize(first);
                st.props_outside++;
                continue;
            }
            st.props_hulls++;
            st.props_bbox++;
            st.props_placed++;
        }
    }
    std::vector<BspStaticProp>().swap(props_);
    if (cancel_) {
        return;
    }
    // the static world: brushes, displacements and the props, cleaned together (and tagged with surface types)
    if (!bsp_->build_world(opt_.world, &solids, result_.world, st.world, err, opt_.surface_types ? &slots : nullptr,
                           opt_.surface_types ? &result_.world_tag : nullptr)) {
        fail(err);
        return;
    }
    st.surface_types = (uint32_t)types.size();
    std::vector<ConvexSolid>().swap(solids);
    progress_ = 0.9f;
    // the solid brush entities' models (moving objects), with the world's thin-wall threshold
    BspWorldOptions mo = mover_options(opt_.world.thin_wall_max);
    for (int32_t id : model_ids_) {
        if (cancel_) {
            return;
        }
        std::vector<sa1_collision_tri> tris;
        BspWorldStats ms;
        std::string merr;
        if (!bsp_->build_model(id, mo, tris, ms, merr) || tris.empty()) {
            st.brush_models_empty++;
            continue;
        }
        Shape s;
        make_shape(tris, s);
        st.brush_models++;
        st.brush_model_tris += s.tris;
        st.brush_model_chunks += (uint32_t)s.chunks.size();
        result_.models[id] = std::move(s);
    }
    st.build_ms = now_ms() - t;
    st.total_ms = elapsed_ms();
    // the cache file
    if (!opt_.cache_dir.empty()) {
        double tc = now_ms();
        std::string werr;
        std::string data = serialize(result_, opt_.hash(), key_crc_, size_);
        std::string sep = result_.cache_note.empty() ? "" : "; ";
        if (!make_dirs(opt_.cache_dir)) {
            result_.cache_note += sep + "the cache directory cannot be created";
        } else if (!write_file_replace(join_path(opt_.cache_dir, map_ + ".dat"), data, werr)) {
            result_.cache_note += sep + "the cache file cannot be written: " + werr;
        } else {
            result_.cache_written = true;
        }
        result_.cache_ms = now_ms() - tc;
    }
    apply_classes();   // after the cache file: it keeps the tags, never the class bits
    progress_ = 0.92f;
    worker_ok_ = true;
}

// libsa1's GRID synthesis of the static world (prepare.hpp), on this worker: what the first sa1_character_create after
// sa1_collision_set_static did on the game's thread until 0.5.0 (0.1-0.4 s on a big map). A failure is not fatal:
// MapApply then hands libsa1 the triangles (the first character synthesizes them, as before). 0.9.2 (GRID-FALLBACK):
// on libsa1's safety limit once more without the triangles outside the world's bounds; a world that is still too big
// gets prep.too_big and a plain message in prep.error.
void MapJob::stage_prepare()
{
    progress_ = 0.93f;
    if (cancel_) {
        return;
    }
    prepare_world_guarded(result_.world, result_.st.world.mins, result_.st.world.maxs, opt_.grid, result_.prep);
    if (cancel_) {
        return;   // worker_ok_ stays false: poll() reports "cancelled"; the result is released with the job
    }
    progress_ = 1.0f;
    worker_ok_ = true;
}

}  // namespace gsa1
