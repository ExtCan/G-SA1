// G-SA1 core: a map's collision, loaded in the background (sadc docs/research/gsa1_ramp_freeze.md fixes 2, 5, 6, 8).
//
// G64's sources, cleaned (bsp.hpp): the world brushes, the displacements and the static props (their physics models,
// .phy, or their model's box) make the STATIC world (libsa1 GRID); the brush models of solid brush entities (doors,
// trains, func_brush, breakables: *1, *2, ...) become SHAPES of moving objects (shape.hpp, movers.hpp). The result
// goes into a per-map cache file (garrysmod/data/gsa1/cache/<map>.dat: map-derived only, versioned, keyed by the
// CRC-32 of the map's header - every lump's offset and size and the map revision - and its size), so a second
// visit loads it in about a second instead of reading and cleaning the map again.
//
// Where the bytes come from: a map the module found itself (garrysmod/maps, addons/*/maps) is read by the worker
// thread; for workshop and mounted maps the addon reads through Garry's Mod's own file system and hands over only
// the byte ranges needs() lists (the lumps G-SA1 reads: a few MB of a 100 MB map), a few MB per frame. Model files
// (.phy, the first bytes of .mdl) always come from the addon (files()): they live in VPKs, GMAs and the map's pak.
//
// Stages: Cache (worker) -> Reading (addon feeds lumps; file maps skip it) -> Parsing (worker: lumps, entities,
// static prop list, material names) -> Files (addon feeds model files, the collision materials' .vmt and the
// surfaceproperties scripts) <-> Materials (worker, 0.8: parses the fed .vmt / scripts and asks for the materials patch
// files include and the files the scripts' manifest lists: another Files round, at most 4) -> Building (worker: props
// placed, world cleaned and tagged with surface types, brush models, cache written, surface classes applied) ->
// Preparing (worker, 0.5.1: libsa1's GRID synthesis of the world, prepare.hpp; also after a cache hit, since the
// prepared geometry is not cached on disk) -> Ready.
// Surface types (0.8, sadc docs/research/gsa1_060_dig.md F1-F4 with its Review R4; surfaces.hpp): the cache keeps each
// world triangle's surface-type tag and the slots' base chains and letters, never the class bits; the classes of
// MapJobOptions::surfaces are applied to the result on the worker after a build and after a cache hit alike (so a
// change of the class table is a cache hit plus a preparation, no rebuild, and MapApply's fallback - the triangles
// without preparation - carries them too: Review G5). The cache key does not cover the .vmt / script / .phy contents:
// after a workshop update of a material the old types stay until gsa1_cache_purge (Review G12). The main thread calls poll() once per frame (it
// only joins a finished worker and starts the next stage); nothing slow ever runs on it. The main thread hands the
// result to its libsa1 context (sa1_collision_set_prepared: O(1)); the preparation itself uses a private context.
// A job that is replaced or cancelled need not be waited for: request_cancel() and idle() let the module drop it
// once its worker has finished (a running libsa1 preparation cannot be interrupted).
#pragma once

#include <atomic>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "bsp.hpp"
#include "phy.hpp"
#include "prepare.hpp"
#include "shape.hpp"
#include "surfaces.hpp"

namespace gsa1 {

// the brush entity classes whose models collide (solid brush entities); triggers, clips, illusionary brushes, area
// portals, ladders and water are left out
bool solid_brush_class(const std::string &classname);

uint32_t crc32(const void *p, size_t n, uint32_t crc = 0);

struct MapJobOptions {
    BspWorldOptions world;                // the static world
    bool static_props = true;             // static props' physics models in the static world
    float prop_min_size = 8.0f;           // Hammer units: props whose collision is smaller (cans, bottles) are left out
    bool brush_models = true;             // shapes of the solid brush entities' models (cleaned with world.thin_wall_max)
    std::string cache_dir;                // "" = no cache file
    bool prepare = true;                  // the libsa1 GRID synthesis on the worker too (MapResult::prep)
    PrepareOptions grid;                  // its parameters (not in hash(): the cache holds the cleaned triangles; 0.9.3:
                                          // grid.undersides_drop = the Q menu's "Solid ceilings" off - a cache hit and
                                          // a new preparation, no rebuild)
    bool surface_types = true;            // read the materials' surface types (.vmt, surfaceproperties scripts) and
                                          // tag the world with them (false: no tags, no material files)
    SurfaceSettings surfaces;             // the class table applied to the tags (not in hash(): applied after the cache)
    uint32_t hash() const;                // of everything that changes the result (and the pipeline's version)
};

struct MapStats {
    BspWorldStats world;                  // build_world (with the static props)
    uint32_t props = 0;                   // static props in the map
    uint32_t props_solid = 0;             // ... solid (physics model or box)
    uint32_t props_placed = 0;            // placed in the static world
    uint32_t props_hulls = 0;             // their convex pieces
    uint32_t props_missing = 0;           // no physics model / box found
    uint32_t props_small = 0;             // smaller than prop_min_size
    uint32_t props_bbox = 0;              // placed as their model's box (SOLID_BBOX)
    uint32_t prop_models = 0, prop_models_missing = 0, prop_models_bad = 0;
    int32_t prop_version = 0;
    uint32_t brush_models = 0, brush_model_tris = 0, brush_model_chunks = 0, brush_models_empty = 0;
    uint32_t entities = 0, brush_entities = 0;
    double parse_ms = 0, build_ms = 0, total_ms = 0;
    uint64_t bytes_fed = 0;
    uint32_t files_fed = 0;
    // surface types (0.8): the materials of the collision faces and their files
    uint32_t materials = 0, materials_used = 0, materials_bad = 0;   // TEXDATA names; used by collision faces; unusable
    uint32_t vmt_found = 0, vmt_missing = 0, vmt_bad = 0;           // .vmt files fed (includes too), missing, not parsed
    uint32_t vmt_patches = 0, vmt_includes_missing = 0;             // patch materials; ... whose include is missing
    uint32_t vmt_default = 0;             // used materials without a $surfaceprop (Source's "default") or without a file
    uint32_t vmt_blends = 0;              // used materials with a $surfaceprop2
    uint32_t surface_scripts = 0;         // surfaceproperties scripts read (manifest's files or surfaceproperties.txt)
    uint32_t surface_types = 0;           // slots (every type of the scripts + names they lack)
    uint32_t material_rounds = 0;         // Materials stages run
    uint32_t props_surfaceprop = 0;       // static props' convex pieces with a surface type from their .phy
    // 0.9.2
    uint32_t props_outside = 0;           // static props entirely outside the world model's bounds + 64 units: not
                                          // placed (BspWorldOptions::guard; their parts out there: world.tris_outside)
};

struct MapResult {
    std::string map;
    std::vector<sa1_collision_tri> world;
    std::map<int32_t, Shape> models;      // brush models by index (*N)
    MapStats st;
    bool from_cache = false, cache_written = false;
    double cache_ms = 0.0;                // reading it (from_cache) or writing it
    std::string cache_note;               // why the cache was not used, and why it was not written ("" = used)
    std::string props_note;               // why the static props are missing ("" = fine)
    PrepareResult prep;                   // MapJobOptions::prepare: the world for sa1_collision_set_prepared
    double ready_ms = 0.0;                // from the start to Ready (the preparation included)
    // surface types (0.8): per world triangle its tag (bsp.hpp surface_tag; empty: none), the slots' types (base chain
    // and letter, cached: Review G1), and the classes MapJobOptions::surfaces put on `world` (already ORed in)
    std::vector<uint32_t> world_tag;
    std::vector<SurfaceType> types;
    SurfaceSummary surf;
};

enum class MapState : int { Idle = 0, Cache, Reading, Parsing, Files, Materials, Building, Preparing, Ready, Failed };
const char *map_state_name(MapState s);

class MapJob {
public:
    MapJob();
    ~MapJob();
    MapJob(const MapJob &) = delete;
    MapJob &operator=(const MapJob &) = delete;

    // a map the module found (the worker reads it); map: a validated bare name (the cache file's name)
    bool start_file(const std::string &map, const std::string &path, const MapJobOptions &o, std::string &err);
    // a map the addon reads: its first 1036 bytes (the header) and the file's size
    bool start_fed(const std::string &map, const void *header, size_t n, uint64_t size, const MapJobOptions &o,
                   std::string &err);
    void cancel();                        // stops (joins) the worker; state Failed ("cancelled")
    void request_cancel() { cancel_ = true; }   // the same without waiting: the worker stops at its next check
    bool idle() const { return !worker_running_.load() || worker_done_.load(); }   // no worker running: delete it now
    void poll();                          // main thread, once per frame
    void wait();                          // joins a running worker (tests and tools; poll() afterwards)
    MapState state() const { return (MapState)state_.load(); }
    float progress() const { return progress_.load(); }
    std::string error() const;
    const std::string &map() const { return map_; }
    const MapJobOptions &options() const { return opt_; }
    bool fed() const { return fed_mode_; }
    double elapsed_ms() const;
    // Reading: the byte ranges still missing, cut into pieces of at most max_bytes (at most max_ranges)
    void needs(std::vector<std::pair<uint64_t, uint64_t>> &out, size_t max_ranges, uint64_t max_bytes);
    uint64_t bytes_needed();
    uint64_t bytes_fed() const { return fed_bytes_; }
    bool feed(uint64_t ofs, const void *p, size_t n, std::string &err);
    // Files: the files still missing: path ("models/....phy", "materials/....vmt", "scripts/....txt") and how many bytes
    // are wanted (0 = all)
    void files(std::vector<std::pair<std::string, uint32_t>> &out, size_t max) const;
    uint32_t files_total() const { return files_total_.load(); }
    uint32_t files_done() const { return files_done_; }
    // p == nullptr: the file does not exist / cannot be read
    bool feed_file(const std::string &path, const void *p, size_t n, std::string &err);
    // Ready: moves the result out (once)
    bool take(MapResult &out);

private:
    enum class FileKind : uint8_t { Phy, Mdl, Vmt, Script };
    struct FileEntry {
        uint32_t max = 0;
        FileKind kind = FileKind::Phy;
        bool done = false, missing = false, parsed = false;
        std::string data;
    };
    bool start_common(const std::string &map, const MapJobOptions &o, std::string &err);
    void run_worker(MapState stage);
    void stage_cache();
    void stage_parse();
    void stage_materials();
    void stage_build();
    void apply_classes();
    void stage_prepare();
    void fail(const std::string &msg);
    void set_state(MapState s) { state_.store((int)s); }

    std::string map_, path_;
    MapJobOptions opt_;
    bool fed_mode_ = false;
    std::unique_ptr<ByteSource> src_;
    RangeByteSource *ranges_ = nullptr;
    std::unique_ptr<Bsp> bsp_;
    uint8_t header_[1036] = {};
    uint64_t size_ = 0;
    uint32_t key_crc_ = 0;
    std::atomic<int> state_{(int)MapState::Idle};
    std::atomic<float> progress_{0.0f};
    std::thread worker_;
    std::atomic<bool> worker_running_{false}, worker_done_{false}, cancel_{false}, worker_ok_{false};
    mutable std::mutex m_;
    std::string error_;
    double t0_ = 0.0;
    uint64_t fed_bytes_ = 0;
    uint32_t files_done_ = 0;
    // between the stages (owned by whichever thread runs the current stage)
    std::vector<BspStaticProp> props_;
    std::vector<int32_t> model_ids_;
    std::map<std::string, FileEntry> files_;
    std::atomic<uint32_t> files_total_{0};   // files_.size() for MapPoll (the workers add entries)
    uint32_t unparsed_ = 0;                  // .vmt / scripts fed and not parsed yet (a Materials stage is due)
    uint32_t round_ = 0;                     // Materials stages run
    BspMaterials mats_;
    std::map<std::string, VmtInfo> vmts_;    // parsed .vmt files by path
    std::vector<std::string> manifest_files_;
    bool manifest_ok_ = false;
    bool cache_hit_ = false;
    MapResult result_;
    bool taken_ = false;
};

}  // namespace gsa1
