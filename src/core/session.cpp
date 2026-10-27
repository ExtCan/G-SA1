// G-SA1 core: libsa1 session (see session.hpp).
#include "session.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <exception>

#include "config.hpp"
#include "util.hpp"

namespace gsa1 {

namespace {

const double kPairSeconds = 1.0 / 30.0;
const size_t kMaxLogLines = 512;
const size_t kMaxEvents = 4096;
// 0.9.3 (round 6a): Super Sonic (kind 8) with libsa1's API 0.4 (SA1_API_SUPER); his world is a Sonic world on the
// Perfect Chaos stage, and the disc load also gives Sonic his Super forms (SA1_LOAD_SUPER_FORMS) for the transformation
#if defined(SA1_API_SUPER)
const uint32_t kPlayableMask = (1u << SA1_CHAR_SONIC) | (1u << SA1_CHAR_TAILS) | (1u << SA1_CHAR_KNUCKLES) |
                               (1u << SA1_CHAR_AMY) | (1u << SA1_CHAR_GAMMA) | (1u << SA1_CHAR_BIG) |
                               (1u << SA1_CHAR_SUPER_SONIC);
const uint32_t kLoadSuperForms = SA1_LOAD_SUPER_FORMS;
const uint32_t kStateSuper = SA1_STATE_SUPER;
#else
const uint32_t kStateSuper = 0u;
const uint32_t kPlayableMask = (1u << SA1_CHAR_SONIC) | (1u << SA1_CHAR_TAILS) | (1u << SA1_CHAR_KNUCKLES) |
                               (1u << SA1_CHAR_AMY) | (1u << SA1_CHAR_GAMMA) | (1u << SA1_CHAR_BIG);
const uint32_t kLoadSuperForms = 0u;
#endif

void log_cb(void *user, int32_t level, const char *message)
{
    static_cast<Session *>(user)->log_line(level, message);
}

void replace_all(std::string &s, const std::string &what, const std::string &with)
{
    if (what.empty()) {
        return;
    }
    size_t pos = 0;
    while ((pos = s.find(what, pos)) != std::string::npos) {
        s.replace(pos, what.size(), with);
        pos += with.size();
    }
}

uint64_t fnv(uint64_t h, const void *p, size_t n)
{
    const uint8_t *b = (const uint8_t *)p;
    for (size_t i = 0; i < n; i++) {
        h = (h ^ b[i]) * 1099511628211ull;
    }
    return h;
}

float dot3(const float *a, const float *b)
{
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

void normalize3(float *v)
{
    float l = std::sqrt(dot3(v, v));
    if (l > 1e-12f && std::isfinite(l)) {
        v[0] /= l;
        v[1] /= l;
        v[2] /= l;
    } else {
        v[0] = 0.0f;
        v[1] = 0.0f;
        v[2] = 1.0f;
    }
}

// The upgrades (sadc src/1st_read): PInitialize 8C06C350 (code_8C06C300.c) reads the flags with func_8C09068E and
// sets the equipment bits; what each bit does: Sonic 0x2 light speed dash (code_8C0B11C0.c: charge 210 frames),
// 0x1 with it a faster charge (120 frames), 0x4 the light speed attack on a target; Tails 0x8 the anklet model and
// a stronger air stick (code_8C0B6148.c, code_8C06F6C0.c), 0x10 the tail attack chain (code_8C0BEBE0.c); Knuckles
// 0x40 digging (code_8C0C80D4.c), 0x20 the charged punch (code_8C0C450A.c), both the hand models
// (code_8C0C4C2E.c); Amy 0x100 the feather and its jump attack (code_8C0DA106.c, code_8C0D7960.c), 0x80 the long
// hammer (code_8C0D6B40.c); E-102 0x400 the hover (code_8C0D1916.c), 0x200 the laser blaster parts and lock-ons
// (code_8C0CFACE.c, code_8C0D3C00.c); Big 0x1000 the life belt (underwater, code_8C0E488C.c), 0x800 the power rod
// (code_8C0DFFA0.c, code_8C0E6812.c); the lures: func_8C0E6E80 (code_8C0E6DA0.c) counts flags 0x1DE..0x1E1.
// PInitialize's Sonic case falls through into Tails' and E-102's into Big's (the game's own code); only the
// character's own flags are set here.
const UpgradeDef kUpgrades[] = {
    {SA1_CHAR_SONIC, "light_speed_shoes", "Light Speed Shoes", 0x8D, 0x0002},
    {SA1_CHAR_SONIC, "crystal_ring", "Crystal Ring", 0x8E, 0x0001},
    {SA1_CHAR_SONIC, "ancient_light", "Ancient Light", 0x9F, 0x0004},
    {SA1_CHAR_TAILS, "jet_anklet", "Jet Anklet", 0xCD, 0x0008},
    {SA1_CHAR_TAILS, "rhythm_badge", "Rhythm Badge", 0xDB, 0x0010},
    {SA1_CHAR_KNUCKLES, "shovel_claw", "Shovel Claw", 0x119, 0x0040},
    {SA1_CHAR_KNUCKLES, "fighting_gloves", "Fighting Gloves", 0x11A, 0x0020},
    {SA1_CHAR_AMY, "warrior_feather", "Warrior Feather", 0x152, 0x0100},
    {SA1_CHAR_AMY, "long_hammer", "Long Hammer", 0x15E, 0x0080},
    {SA1_CHAR_GAMMA, "jet_booster", "Jet Booster", 0x189, 0x0400},
    {SA1_CHAR_GAMMA, "laser_blaster", "Laser Blaster", 0x18A, 0x0200},
    {SA1_CHAR_BIG, "life_belt", "Life Belt", 0x1D0, 0x1000},
    {SA1_CHAR_BIG, "power_rod", "Power Rod", 0x1D1, 0x0800},
    {SA1_CHAR_BIG, "lure_1", "Lure upgrade 1", 0x1DE, 0},
    {SA1_CHAR_BIG, "lure_2", "Lure upgrade 2", 0x1DF, 0},
    {SA1_CHAR_BIG, "lure_3", "Lure upgrade 3", 0x1E0, 0},
    {SA1_CHAR_BIG, "lure_4", "Lure upgrade 4", 0x1E1, 0},
};

}  // namespace

uint32_t playable_kinds()
{
    return kPlayableMask;
}

const UpgradeDef *upgrade_table(size_t &count)
{
    count = sizeof kUpgrades / sizeof kUpgrades[0];
    return kUpgrades;
}

int32_t upgrade_kind(int32_t kind)
{
    // 0.9.3a (design 6.5): Super Sonic's world is a Sonic world (game character 0: PInitialize's Sonic case reads Sonic's
    // flags 0x8D / 0x8E / 0x9F); his upgrades are Sonic's
    return kind == kKindSuperSonic ? (int32_t)SA1_CHAR_SONIC : kind;
}

const UpgradeDef *find_upgrade(int32_t kind, const std::string &name)
{
    kind = upgrade_kind(kind);
    for (const UpgradeDef &u : kUpgrades) {
        if (u.kind == kind && name == u.name) {
            return &u;
        }
    }
    return nullptr;
}

void exact_stick(float x, float y, float &sx, float &sy)
{
    if (!std::isfinite(x) || !std::isfinite(y)) {
        sx = sy = 0.0f;
        return;
    }
    float m = std::sqrt(x * x + y * y);
    if (m < 1e-4f) {
        sx = sy = 0.0f;
        return;
    }
    if (m > 1.0f) {
        x /= m;
        y /= m;
    }
    // pad units after the game's dead zone (127 - 12 = 115 at full deflection); pad y is negative forward
    float dx = x * 115.0f, dy = -y * 115.0f;
    float px = std::round(dx + (dx >= 0.0f ? 12.0f : -12.0f));
    float py = std::round(dy + (dy >= 0.0f ? 12.0f : -12.0f));
    px = std::max(-127.0f, std::min(127.0f, px));
    py = std::max(-127.0f, std::min(127.0f, py));
    sx = px / 127.0f;
    sy = -py / 127.0f;
}

bool paint_runs(const TextureRuns &t, std::vector<uint8_t> &rgba)
{
    rgba.assign((size_t)t.width * t.height * 4u, 0);
    const uint8_t *r = (const uint8_t *)t.runs.data();
    if (t.runs.size() != (size_t)t.run_count * 10u) {
        return false;
    }
    for (uint32_t i = 0; i < t.run_count; i++, r += 10) {
        uint32_t x = r[0] | (r[1] << 8), y = r[2] | (r[3] << 8), len = r[4] | (r[5] << 8);
        if (y >= t.height || x + len > t.width || len == 0) {
            return false;
        }
        for (uint32_t k = 0; k < len; k++) {
            std::memcpy(&rgba[((size_t)y * t.width + x + k) * 4u], r + 6, 4);
        }
    }
    return true;
}

Session::Session() {}

Session::~Session()
{
    shutdown();
}

const char *disc_state_name(DiscState s)
{
    switch (s) {
    case DiscState::Idle: return "idle";
    case DiscState::Loading: return "loading";
    case DiscState::Ready: return "ready";
    case DiscState::Failed: return "failed";
    }
    return "?";
}

// any thread: libsa1 logs from the disc load's worker and the sound banks' worker too
void Session::log_line(int32_t level, const char *msg)
{
    const char *tag = level >= SA1_LOG_ERROR ? "error" : level >= SA1_LOG_WARN ? "warn" : level >= SA1_LOG_INFO ? "info" : "debug";
    std::string line = std::string("libsa1 ") + tag + ": " + (msg ? msg : "");
    std::lock_guard<std::mutex> g(log_m_);
    if (log_.size() >= kMaxLogLines) {
        log_.pop_front();
    }
    log_.push_back(std::move(line));
}

std::vector<std::string> Session::take_log()
{
    std::deque<std::string> lines;
    {
        std::lock_guard<std::mutex> g(log_m_);
        lines.swap(log_);
    }
    std::vector<std::string> out;
    out.reserve(lines.size());
    for (const std::string &s : lines) {
        out.push_back(scrub(s));
    }
    return out;
}

std::string Session::last_error() const
{
    return last_error_;
}

std::string Session::scrub(const std::string &msg) const
{
    std::string s = msg;
    for (const std::string *d : {&disc_dir_, &config_dir_}) {
        if (d->size() < 3) {
            continue;
        }
        const char *tag = (d == &disc_dir_) ? "<disc>" : "<config>";
        std::string a = *d, b = *d;
        std::replace(a.begin(), a.end(), '/', '\\');
        std::replace(b.begin(), b.end(), '\\', '/');
        replace_all(s, a, tag);
        replace_all(s, b, tag);
    }
    return s;
}

// The disc on a worker thread (0.5.1): a context of its own until poll_init installs it, so nothing else touches it
// while it loads. SA1_LOAD_WORLD_IMAGES composes the world image of every kind there too (1ST_READ.BIN and the
// overlays read, checked and unpacked: 30-60 ms per kind that the first world of each kind otherwise spent on the
// creating thread).
bool Session::init_async(const std::string &gdi_path, std::string &err)
{
    if (disc_state_ == DiscState::Loading || ready()) {
        return true;
    }
    shutdown();
    disc_dir_ = parent_dir(gdi_path);
    config_dir_ = config_dir();
    gdi_path_ = gdi_path;
    init_error_.clear();
    auto res = std::make_shared<InitResult>();
    init_result_ = res;
    init_t0_ = now_ms();
    disc_state_ = DiscState::Loading;
    init_worker_.reset(new Worker());
    Session *self = this;
    std::string path = gdi_path;
    try {
        init_worker_->start([self, res, path]() {
            double t0 = now_ms();
            sa1_host h;
            sa1_host_defaults(&h);
            h.user = self;
            h.log = log_cb;       // Session::log_line is thread-safe
            h.log_level = SA1_LOG_INFO;
            sa1_context *c = nullptr;
            sa1_status st = sa1_init(&h, &c);
            if (SA1_FAILED(st) || !c) {
                res->status = SA1_FAILED(st) ? st : SA1_ERR_OUT_OF_MEMORY;
                res->error = format("sa1_init failed: %s", sa1_status_string(res->status));
                return;
            }
            sa1_coords co;
            source_coords(co);   // 4.0 Hammer units per SA1 unit, Z up
            sa1_set_coords(c, &co);
            sa1_load_options lo;
            std::memset(&lo, 0, sizeof lo);
            lo.struct_size = sizeof lo;
            lo.characters = kPlayableMask;
            lo.flags = SA1_LOAD_DEFAULT | SA1_LOAD_WORLD_IMAGES | kLoadSuperForms;
            st = sa1_load_disc(c, path.c_str(), &lo);
            res->ms = now_ms() - t0;
            res->status = st;
            if (SA1_FAILED(st)) {
                res->error = format("cannot load the disc (%s): %s", sa1_status_string(st), sa1_last_error(c));
                sa1_shutdown(c);
                return;
            }
            res->ctx = c;
        });
    } catch (const std::exception &e) {
        init_worker_.reset();
        init_result_.reset();
        disc_state_ = DiscState::Failed;
        init_error_ = std::string("cannot start the disc's loading thread: ") + e.what();
        err = init_error_;
        return false;
    }
    return true;
}

int Session::poll_init()
{
    if (disc_state_ != DiscState::Loading || !init_worker_ || !init_worker_->done()) {
        return 0;
    }
    init_worker_->join();
    init_worker_.reset();
    std::shared_ptr<InitResult> res = init_result_;
    init_result_.reset();
    if (res && res->ctx) {
        ctx_ = res->ctx;
        res->ctx = nullptr;
        disc_ms_ = res->ms;
        disc_loaded_ = true;
        disc_state_ = DiscState::Ready;
        if (res->status == SA1_PARTIAL) {
            log_line(SA1_LOG_WARN, "the disc loaded partially (some optional files are missing; see the log)");
        }
        // 0.9.3: Sonic's Super forms (SA1_LOAD_SUPER_FORMS gives him the SUPERSONIC archive after his own)
        super_forms_ = false;
        for (uint32_t a = 0, na = kLoadSuperForms ? texture_archives(SA1_CHAR_SONIC) : 0u; a < na; a++) {
            uint32_t n = 0;
            std::string e, name;
            if (texture_count(SA1_CHAR_SONIC, a, n, e, &name) && name == "SUPERSONIC") {
                super_forms_ = true;
            }
        }
        return 1;
    }
    init_error_ = scrub(res ? res->error : std::string("the disc's loading thread failed"));
    disc_state_ = DiscState::Failed;
    return -1;
}

double Session::disc_wait_ms() const
{
    return disc_state_ == DiscState::Loading ? now_ms() - init_t0_ : 0.0;
}

bool Session::init(const std::string &gdi_path, std::string &err)
{
    if (ready()) {
        shutdown();
    }
    if (!init_async(gdi_path, err)) {
        return false;
    }
    if (init_worker_) {
        init_worker_->join();
    }
    if (poll_init() < 0 || !ready()) {
        err = init_error_.empty() ? std::string("the disc did not load") : init_error_;
        return false;
    }
    return true;
}

void Session::finish_init_worker()
{
    if (init_worker_) {
        init_worker_->join();   // only at shutdown: a load cannot be interrupted
        init_worker_.reset();
    }
    if (init_result_ && init_result_->ctx) {
        sa1_shutdown(init_result_->ctx);
        init_result_->ctx = nullptr;
    }
    init_result_.reset();
}

void Session::shutdown()
{
    finish_init_worker();
    destroy_all();
    audio_close();
    movers_.clear(ctx_);
    world_prep_.reset();
    if (ctx_) {
        sa1_shutdown(ctx_);
        ctx_ = nullptr;
    }
    disc_loaded_ = false;
    disc_state_ = DiscState::Idle;
    events_.clear();
    black_.clear();
    super_forms_ = false;
}

bool Session::audio_open_async(bool japanese, std::string &err)
{
    if (!ready()) {
        err = "not initialised (no disc loaded)";
        return false;
    }
    audio_.set_log(log_cb, this);
    audio_.open_async(gdi_path_, japanese);
    return true;
}

int Session::poll_audio(std::string &msg)
{
    std::string m;
    int r = audio_.poll(m);
    msg = scrub(m);
    if (r > 0) {
        for (const auto &c : chars_) {
            audio_.character(c->id, c->st.position, !c->puppet);
        }
    }
    return r;
}

bool Session::audio_open(bool japanese, std::string &err)
{
    if (!audio_open_async(japanese, err)) {
        return false;
    }
    audio_.wait();
    std::string msg;
    int r = poll_audio(msg);
    err = r > 0 ? scrub(audio_.notes()) : msg;
    return r > 0;
}

void Session::audio_close()
{
    audio_.close();
}

bool Session::set_world(const std::vector<sa1_collision_tri> &tris, std::string &err)
{
    if (!ctx_) {
        err = "not initialised";
        return false;
    }
    double t0 = now_ms();
    sa1_status st = sa1_collision_set_static(ctx_, tris.empty() ? nullptr : tris.data(), (uint32_t)tris.size());
    world_ms_ = now_ms() - t0;
    if (SA1_FAILED(st)) {
        err = scrub(format("sa1_collision_set_static: %s: %s", sa1_status_string(st), sa1_last_error(ctx_)));
        return false;
    }
    world_prep_.reset();
    return true;
}

bool Session::set_world_prepared(const PreparedRef &p, std::string &err)
{
    if (!ctx_) {
        err = "not initialised";
        return false;
    }
    if (!p) {
        err = "no prepared collision";
        return false;
    }
    double t0 = now_ms();
    sa1_status st = sa1_collision_set_prepared(ctx_, p.get());
    world_ms_ = now_ms() - t0;
    if (SA1_FAILED(st)) {
        err = scrub(format("sa1_collision_set_prepared: %s: %s", sa1_status_string(st), sa1_last_error(ctx_)));
        return false;
    }
    world_prep_ = p;
    return true;
}

void Session::commit_movers(double now)
{
    if (!ctx_) {
        return;
    }
    const float *focus = nullptr;
    for (const auto &c : chars_) {
        if (!c->puppet && !c->faulted) {
            focus = c->st.position;
            break;
        }
    }
    movers_.commit(ctx_, focus, now);
}

bool Session::world_info(sa1_collision_info &out) const
{
    std::memset(&out, 0, sizeof out);
    out.struct_size = sizeof out;
    return ctx_ && sa1_collision_info_get(ctx_, &out) == SA1_OK;
}

void Session::refresh_state(Character &c)
{
    std::memset(&c.st, 0, sizeof c.st);
    c.st.struct_size = sizeof c.st;
    sa1_character_state_ex(ctx_, c.id, &c.st);
}

int32_t Session::create(int32_t kind, const float pos[3], float yaw, std::string &err, double *ms,
                        const std::vector<const UpgradeDef *> *upgrades, int32_t start_rings, const CreateExtra *extra)
{
    if (!ready()) {
        err = "not initialised (no disc loaded)";
        return 0;
    }
    if (kind < 0 || kind >= SA1_CHAR_COUNT || !((kPlayableMask >> kind) & 1u)) {
        err = kSuperApi ? "this character cannot be played (Sonic, Tails, Knuckles, Amy, E-102, Big and Super Sonic can)"
                        : "this character cannot be played (Sonic, Tails, Knuckles, Amy, E-102 and Big can)";
        return 0;
    }
    // 0.9.3 (Super Sonic): the extra create flags and the Super flags, checked here so that a wrong one is named
    CreateExtra ex;
    if (extra) {
        ex = *extra;
    }
    if (ex.flags & ~kCreateExtraFlags) {
        err = format("create flags 0x%X: only SUPER_CAPABLE and WATER_FLOOR (gsa1.SUPER) can be given",
                     (unsigned)ex.flags);
        return 0;
    }
#if defined(SA1_API_SUPER)
    if ((ex.flags & SA1_CREATE_SUPER_CAPABLE) && kind != SA1_CHAR_SONIC && kind != SA1_CHAR_SUPER_SONIC) {
        err = "only Sonic can turn Super (SUPER_CAPABLE)";
        return 0;
    }
    if ((ex.flags & SA1_CREATE_SUPER_CAPABLE) && kind == SA1_CHAR_SONIC && !super_forms_) {
        err = "Sonic cannot turn Super: his Super forms are not loaded from the disc (the SUPERSONIC archive)";
        return 0;
    }
    if (ex.super_given && kind != SA1_CHAR_SUPER_SONIC && !(ex.flags & SA1_CREATE_SUPER_CAPABLE)) {
        err = "super flags are for Super Sonic or a Sonic who can turn Super (SUPER_CAPABLE)";
        return 0;
    }
#endif
    if (ex.super_given && (ex.super_flags & ~kSuperHostFlags)) {
        err = format("super flags 0x%X: only NO_DRAIN, KEEP_AT_ZERO, FAITHFUL_REVERT%s (gsa1.SUPER; the sea plane is the "
                     "Perfect Chaos stage's own water, which G-SA1's worlds never have)", (unsigned)ex.super_flags,
                     kSuperGeneralApi ? ", GENERAL, START, WATER_WHILE_SUPER and START_NORMAL" : "");
        return 0;
    }
    if (!pos || !std::isfinite(pos[0]) || !std::isfinite(pos[1]) || !std::isfinite(pos[2]) || !std::isfinite(yaw) ||
        std::fabs(pos[0]) > 65536.0f || std::fabs(pos[1]) > 65536.0f || std::fabs(pos[2]) > 65536.0f) {
        err = "invalid position or yaw";
        return 0;
    }
    if (chars_.size() >= 16) {
        err = "too many characters";
        return 0;
    }
    sa1_character_desc d;
    std::memset(&d, 0, sizeof d);
    d.struct_size = sizeof d;
    d.kind = kind;
    d.flags = SA1_CREATE_WORLD;
    d.position[0] = pos[0];
    d.position[1] = pos[1];
    d.position[2] = pos[2];
    d.yaw = yaw;
    // 0.9.2 (rings F7, gsa1_090_rings.md review R4.11): the start rings, through the game's own ring calls when libsa1
    // builds the world (before its first step)
    if (start_rings >= 0) {
        d.flags |= SA1_CREATE_START_RINGS;
        d.start_rings = std::min(start_rings, kStartRingsMax);
    }
    // 0.9.3: Super Sonic's world (sa1_character_desc.super_flags is at the struct's tail: struct_size covers it)
    d.flags |= ex.flags;
#if defined(SA1_API_SUPER)
    if (ex.super_given) {
        d.flags |= SA1_CREATE_SUPER;
        d.super_flags = ex.super_flags;
    }
#endif
    // upgrades: flags 0..127 through sa1_character_desc.upgrades, the others written into the world before its
    // first step (every upgrade flag of the game is above 127: set_event_flags)
    std::vector<uint16_t> flags, high;
    uint32_t bits = 0;
    if (upgrades) {
        for (const UpgradeDef *u : *upgrades) {
            if (!u || u->kind != upgrade_kind(kind) || u->flag >= 512) {
                err = "an upgrade of another character";
                return 0;
            }
            if (std::find(flags.begin(), flags.end(), u->flag) != flags.end()) {
                continue;
            }
            flags.push_back(u->flag);
            bits |= u->equipment;
            if (u->flag < 128) {
                d.upgrades[u->flag >> 5] |= 1u << (u->flag & 31u);
                d.flags |= SA1_CREATE_UPGRADES;
            } else {
                high.push_back(u->flag);
            }
        }
    }
    sa1_character_id id = 0;
    double t0 = now_ms();
    sa1_status st = sa1_character_create_ex(ctx_, &d, &id);
    if (!SA1_FAILED(st) && !high.empty() && !set_event_flags(id, high, err)) {
        sa1_character_destroy(ctx_, id);
        return 0;
    }
    if (ms) {
        *ms = now_ms() - t0;
    }
    if (SA1_FAILED(st)) {
        err = scrub(format("cannot create the character (%s): %s", sa1_status_string(st), sa1_last_error(ctx_)));
        return 0;
    }
    if (st == SA1_PARTIAL) {
        log_line(SA1_LOG_WARN, "the character's world has no land (no static collision was set)");
    }
    std::unique_ptr<Character> c(new Character());
    c->id = id;
    c->kind = kind;
    c->num_archives = texture_archives(kind);
    c->upgrade_flags = flags;
    c->upgrade_bits = bits;
    c->start_rings = start_rings >= 0 ? std::min(start_rings, kStartRingsMax) : -1;
    c->create_extra = ex.flags;
    c->super_given = ex.super_given;
    c->super_flags = ex.super_given ? ex.super_flags : 0u;
#if defined(SA1_API_SUPER)
    c->super_capable = kind == SA1_CHAR_SUPER_SONIC || (ex.flags & SA1_CREATE_SUPER_CAPABLE) != 0;
#endif
    refresh_state(*c);
    c->super = (c->st.flags & kStateSuper) != 0;
    std::memcpy(c->prev_pos, c->st.position, sizeof c->prev_pos);
    // 0.9.4a: a super-capable character's whoosh comes from the Perfect Chaos stage's sound bank (super2_sound.md 7.2)
    if (c->super_capable && whoosh_) {
        whoosh_rule(*c);
    }
    Character *raw = c.get();
    chars_.push_back(std::move(c));
    render(raw->id, 1.0f);      // the CPU pose of the start action until the first pair
    return id;
}

// Event flags above 127 (the upgrades): written into the world's B_8C799920 after sa1_character_create_ex built it
// (SA1_CREATE_WORLD) and before its first step, where PInitialize reads them. One byte per flag, set to 1 as the
// game's own setters do (8C088C74; 8C09068E tests for nonzero); the arena is little-endian like the Dreamcast and
// the word access is bounded to it.
bool Session::set_event_flags(sa1_character_id id, const std::vector<uint16_t> &flags, std::string &err)
{
    struct sa1g_world *w = ctx_ ? sa1_character_world(ctx_, id) : nullptr;
    if (!w) {
        err = "the upgrades cannot be set: the character has no world";
        return false;
    }
    for (uint16_t f : flags) {
        if (f >= 512) {
            err = format("event flag %u does not exist", (unsigned)f);
            return false;
        }
        uint32_t a = kEventFlagsAddr + f, word = a & ~3u, v = 0;
        if (sa1g_world_rd32(w, word, &v) != 0) {
            err = "the upgrades cannot be set: the event flags are not in the world";
            return false;
        }
        uint32_t shift = 8u * (a & 3u);
        v = (v & ~(0xFFu << shift)) | (1u << shift);
        if (sa1g_world_wr32(w, word, v) != 0) {
            err = "the upgrades cannot be set: the event flags are not in the world";
            return false;
        }
    }
    return true;
}

int32_t Session::create_puppet(int32_t kind, std::string &err)
{
    if (!ready()) {
        err = "not initialised (no disc loaded)";
        return 0;
    }
    if (kind < 0 || kind >= SA1_CHAR_COUNT) {
        err = "unknown character";
        return 0;
    }
    sa1_character_desc d;
    std::memset(&d, 0, sizeof d);
    d.struct_size = sizeof d;
    d.kind = kind;
    d.flags = SA1_CREATE_PUPPET;
    sa1_character_id id = 0;
    sa1_status st = sa1_character_create_ex(ctx_, &d, &id);
    if (SA1_FAILED(st)) {
        err = scrub(format("cannot create the puppet (%s): %s", sa1_status_string(st), sa1_last_error(ctx_)));
        return 0;
    }
    std::unique_ptr<Character> c(new Character());
    c->id = id;
    c->kind = kind;
    c->puppet = true;
    c->num_archives = texture_archives(kind);
    refresh_state(*c);
    chars_.push_back(std::move(c));
    return id;
}

bool Session::destroy(int32_t id)
{
    for (size_t i = 0; i < chars_.size(); i++) {
        if (chars_[i]->id == id) {
            audio_.stop(id);
            if (ctx_) {
                sa1_character_destroy(ctx_, id);   // libsa1's own queue goes with the world
            }
            chars_.erase(chars_.begin() + (std::ptrdiff_t)i);
            // E2 (0.9.2a, gsa1_091b_itembox.md section 6 and its review R.4.1): tick() and take_events() moved this
            // character's events into the session-wide queue; a character destroyed before the next poll_events (the
            // addon removes or restarts it in the frame its tick failed) left them there for the next character -
            // the owner's "Tails's game code faulted (address 8C05D930)", Knuckles' fault 104 s late. The audio side
            // already had them (take_events) and audio_.stop(id) above ends their sounds.
            size_t before = events_.size();
            events_.erase(std::remove_if(events_.begin(), events_.end(),
                                         [id](const sa1_event &e) { return e.character == (sa1_character_id)id; }),
                          events_.end());
            stale_events_dropped_ += before - events_.size();
            return true;
        }
    }
    return false;
}

void Session::destroy_all()
{
    while (!chars_.empty()) {
        destroy(chars_.back()->id);
    }
}

Character *Session::get(int32_t id)
{
    for (auto &c : chars_) {
        if (c->id == id) {
            return c.get();
        }
    }
    return nullptr;
}

std::vector<int32_t> Session::ids() const
{
    std::vector<int32_t> out;
    for (const auto &c : chars_) {
        out.push_back(c->id);
    }
    return out;
}

void Session::take_events()
{
    if (!ctx_) {
        return;
    }
    sa1_event buf[64];
    for (int round = 0; round < 64; round++) {
        uint32_t n = 0;
        if (sa1_poll_events(ctx_, buf, 64, &n) != SA1_OK || n == 0) {
            break;
        }
        for (uint32_t i = 0; i < n; i++) {
            // 0.9.3: a Perfect Chaos stage tone of a Super world is not played from Emerald Coast's stage bank
            // (kStageTonesFirst; the event still goes to Lua); 0.9.4a: the whoosh is, through its stage rule (admit_sound)
            const sa1_event &e = buf[i];
            if (admit_sound(e)) {
                audio_.event(e);
            }
            if (events_.size() >= kMaxEvents) {
                events_.pop_front();
            }
            events_.push_back(buf[i]);
        }
        if (n < 64) {
            break;
        }
    }
}

// ---- 0.9.4a: the aura's whoosh through libsa1's stage rules (sadc docs/research/super2_sound.md 7.2, super2_plan.md 6.4
// task 5 with its review R.14) ------------------------------------------------------------------------------------------
void Session::whoosh_rule(const Character &c)
{
    StageRule r;
    if (whoosh_) {
        r.stage = kStagePerfectChaos;
        r.first = kWhooshFirst;
        r.last = kWhooshLast;
    }
    audio_.set_stage_rule(c.id, kRuleWhoosh, r);
}

bool Session::set_super_whoosh(bool on)
{
    bool was = whoosh_;
    whoosh_ = on;
    if (!audio_.has_stage_rules()) {
        return false;
    }
    for (const auto &c : chars_) {
        if (!c->super_capable || c->puppet) {
            continue;
        }
        if (was && !on && audio_.is_open()) {
            // what the whoosh still plays ends now (a stop matches by tone, whatever bank the sound came from); the game
            // sends its own stops later, and the guard keeps those out once the rule is gone
            for (uint32_t tone = kWhooshFirst; tone <= kWhooshLast; tone++) {
                sa1_event e;
                std::memset(&e, 0, sizeof e);
                e.type = SA1_EVENT_SOUND_STOP;
                e.id = tone;
                e.character = c->id;
                std::memcpy(e.position, c->st.position, sizeof e.position);
                e.step = c->st.step;
                audio_.event(e);
            }
        }
        whoosh_rule(*c);
    }
    return true;
}

bool Session::whoosh_routed(int32_t id) const
{
    if (!whoosh_ || !audio_.has_stage_rules()) {
        return false;
    }
    StageRule r;
    if (!audio_.stage_rule(id, kRuleWhoosh, r) || r.stage != kStagePerfectChaos || r.first != kWhooshFirst ||
        r.last != kWhooshLast) {
        return false;
    }
    // review R.14: a rule libsa1 refused (SA1_ERR_LIMIT) would leave 1035 / 1036 resolving from G-SA1's own stage bank,
    // which is never relied on; a rule not applied yet (no mixer) has nowhere to play anyway
    int32_t st = audio_.rule_status(id, kRuleWhoosh);
    return st == (int32_t)SA1_OK || st == kRuleNotApplied;
}

uint32_t Session::whoosh_characters() const
{
    uint32_t n = 0;
    for (const auto &c : chars_) {
        n += c->super_capable && !c->puppet && whoosh_routed(c->id);
    }
    return n;
}

bool Session::admit_sound(const sa1_event &e)
{
    if (!mute_stage_tones_ || (e.type != SA1_EVENT_SOUND && e.type != SA1_EVENT_SOUND_STOP) || e.id < kStageTonesFirst ||
        e.id > kStageTonesLast) {
        return true;
    }
    Character *c = get((int32_t)e.character);
    if (!c || !c->super_capable) {
        return true;
    }
    if (e.id >= kWhooshFirst && e.id <= kWhooshLast && whoosh_routed(c->id)) {
        return true;
    }
    c->stage_tones_muted++;
    stage_tones_dropped_++;
    return false;
}

void Session::poll_events(std::vector<sa1_event> &out)
{
    take_events();
    out.assign(events_.begin(), events_.end());
    events_.clear();
}

sa1_status Session::tick(int32_t id, float stick_x, float stick_y, float camera_yaw, uint32_t buttons, float dt,
                         bool raw_stick, const TickExtra *extra)
{
    Character *c = get(id);
    if (!c || !ctx_) {
        last_error_ = "no such character";
        return SA1_ERR_NOT_FOUND;
    }
    if (c->puppet) {
        last_error_ = "a puppet does not tick";
        return SA1_ERR_UNSUPPORTED;
    }
    if (c->faulted) {
        last_error_ = "the character's world faulted earlier; recreate the character";
        return SA1_ERR_GAME_FAULT;
    }
    if (!std::isfinite(dt) || dt < 0.0f) {
        dt = 0.0f;
    }
    dt = std::min(dt, 0.25f);
    auto clamp1 = [](float v) { return std::isfinite(v) ? std::max(-1.0f, std::min(1.0f, v)) : 0.0f; };
    sa1_input in;
    std::memset(&in, 0, sizeof in);
    in.struct_size = sizeof in;
    if (raw_stick) {
        in.stick_x = clamp1(stick_x);
        in.stick_y = clamp1(stick_y);
    } else {
        exact_stick(clamp1(stick_x), clamp1(stick_y), in.stick_x, in.stick_y);
    }
    in.camera_yaw = std::isfinite(camera_yaw) ? camera_yaw : 0.0f;
    in.buttons = buttons & (SA1_BUTTON_JUMP | SA1_BUTTON_ACTION | SA1_BUTTON_ACTION2 | SA1_BUTTON_L | SA1_BUTTON_R);
    // 0.9.2 (gsa1_090_water.md WTR-A, G-SA1 half): the host's water at the character for every pair of this tick (libsa1
    // reads it when struct_size covers host_flags: sizeof in, with this header). Without extra: 0, the game's own rule.
    uint32_t hflags = extra ? (extra->host_flags & kHostFlagsKnown) : 0u;
#if defined(SA1_API_092)
    in.host_flags = hflags;
#endif
    c->host_flags_last = hflags;
    if (hflags != 0u) {
        c->host_flag_ticks++;
    }
    // the host camera (0.9.4's sa1_input tail; plan 6.10 task 8): passed when libsa1 declares it, else only recorded
    bool cam = extra && extra->camera && std::isfinite(extra->cam_pos[0]) && std::isfinite(extra->cam_pos[1]) &&
               std::isfinite(extra->cam_pos[2]) && std::isfinite(extra->cam_target[0]) &&
               std::isfinite(extra->cam_target[1]) && std::isfinite(extra->cam_target[2]);
    c->host_camera_last = cam;
    if (cam) {
        std::memcpy(c->host_cam_last, extra->cam_pos, sizeof extra->cam_pos);
        std::memcpy(c->host_cam_last + 3, extra->cam_target, sizeof extra->cam_target);
#if defined(SA1_INPUT_HOST_CAMERA)
        std::memcpy(in.host_cam_pos, extra->cam_pos, sizeof in.host_cam_pos);
        std::memcpy(in.host_cam_target, extra->cam_target, sizeof in.host_cam_target);
#endif
    }
    float before[3];
    std::memcpy(before, c->st.position, sizeof before);
    uint32_t step0 = c->st.step;
    double t0 = now_ms();
    sa1_status st = sa1_character_tick(ctx_, id, &in, dt, nullptr, nullptr);
    c->tick_ms_last = now_ms() - t0;
    c->tick_ms_max = std::max(c->tick_ms_max, c->tick_ms_last);
    if (SA1_FAILED(st)) {
        // 0.9.2 (gsa1_090_faults.md F3.2, review R.2.5): a fatal stub (SA1_ERR_NOT_IMPLEMENTED) kills the world just as a
        // game code fault does - libsa1 would re-enter the step every tick, re-run the tasks before the stub and fail in it
        // again - so both mark the character faulted (the addon restarts it, cl_character.lua GSA1.TickFault)
        if (st == SA1_ERR_GAME_FAULT || st == SA1_ERR_NOT_IMPLEMENTED) {
            c->faulted = true;
            c->fault_status = st;
        }
        refresh_state(*c);
        take_events();
        last_error_ = scrub(format("%s: %s", sa1_status_string(st), sa1_last_error(ctx_)));
        return st;
    }
    refresh_state(*c);
    // 0.9.3: the form (Super Sonic or normal Sonic) after this tick
    bool sup = (c->st.flags & kStateSuper) != 0;
    if (sup != c->super) {
        c->super = sup;
        c->super_changes++;
        c->super_step = c->st.step;
    }
    uint32_t pairs = (c->st.step - step0) / 2u;
    c->pairs_last = pairs;
    c->pairs_total += pairs;
    c->acc += (double)dt - (double)pairs * kPairSeconds;
    if (c->acc < 0.0) {
        c->acc = 0.0;
    }
    if (c->acc >= kPairSeconds) {
        c->acc = std::fmod(c->acc, kPairSeconds);   // libsa1 dropped a backlog (more than 8 pairs)
    }
    c->alpha = (float)(c->acc / kPairSeconds);
    if (pairs == 1) {
        std::memcpy(c->prev_pos, before, sizeof before);
    } else if (pairs > 1) {
        for (int k = 0; k < 3; k++) {
            c->prev_pos[k] = c->st.position[k] - c->st.velocity[k] * (float)kPairSeconds;
        }
    }
    if (pairs > 0) {
        if (!c->upgrades_checked) {
            // PInitialize ran in the first step: the equipment it derived from the flags
            c->upgrades_checked = true;
            uint32_t got = c->st.equipment & 0x7FFFu;
            c->upgrades_ok = (got & c->upgrade_bits) == c->upgrade_bits;
            if (!c->upgrades_ok) {
                log_line(SA1_LOG_WARN, format("upgrades: the game's equipment is 0x%04X, the upgrades ask for 0x%04X",
                                              (unsigned)got, (unsigned)c->upgrade_bits).c_str());
            }
        }
    }
    audio_.character(id, c->st.position, true);
    take_events();
    return SA1_OK;
}

sa1_status Session::pose(int32_t id, int32_t action, float frame, const float pos[3], float yaw)
{
    Character *c = get(id);
    if (!c || !ctx_) {
        last_error_ = "no such character";
        return SA1_ERR_NOT_FOUND;
    }
    sa1_pose p;
    std::memset(&p, 0, sizeof p);
    p.struct_size = sizeof p;
    p.action = action;
    p.frame = frame;
    std::memcpy(p.position, pos, sizeof p.position);
    p.yaw = yaw;
    sa1_status st = sa1_character_pose(ctx_, id, &p, nullptr);
    if (SA1_FAILED(st)) {
        last_error_ = scrub(format("%s: %s", sa1_status_string(st), sa1_last_error(ctx_)));
        return st;
    }
    std::memcpy(c->prev_pos, c->st.position, sizeof c->prev_pos);
    refresh_state(*c);
    audio_.character(id, pos, false);
    return SA1_OK;
}

// 0.9.3 (Super Sonic, plan 14.1a): the game's player request in the character's world (sa1_character_order: SetInputP(0,
// order) now, taken at the world's next step); a world that cannot turn Super is refused here with the reason
sa1_status Session::order(int32_t id, int32_t order)
{
    Character *c = get(id);
    if (!c || !ctx_) {
        last_error_ = "no such character";
        return SA1_ERR_NOT_FOUND;
    }
    if (c->puppet) {
        last_error_ = "a puppet takes no orders";
        return SA1_ERR_UNSUPPORTED;
    }
    if (c->faulted) {
        last_error_ = "the character's world faulted earlier; recreate the character";
        return SA1_ERR_GAME_FAULT;
    }
#if defined(SA1_API_SUPER)
    if (order != SA1_ORDER_SUPER && order != SA1_ORDER_NORMAL) {
        last_error_ = "only the orders SUPER (46) and NORMAL (47)";
        return SA1_ERR_INVALID_ARGUMENT;
    }
    if (!c->super_capable) {
        last_error_ = c->kind == SA1_CHAR_SONIC ? "this Sonic cannot turn Super (he was not created SUPER_CAPABLE)"
                                                : "only Sonic and Super Sonic can turn Super";
        return SA1_ERR_UNSUPPORTED;
    }
    sa1_status st = sa1_character_order(ctx_, id, order);
    if (SA1_FAILED(st)) {
        last_error_ = scrub(format("sa1_character_order: %s: %s", sa1_status_string(st), sa1_last_error(ctx_)));
    }
    return st;
#else
    (void)order;
    last_error_ = "this libsa1 has no Super Sonic (API 0.4)";
    return SA1_ERR_UNSUPPORTED;
#endif
}

// 0.9.3a (design 6.9): the page's voice Preview - the tone as the game's sound call makes it (SA1_EVENT_SOUND, bank 0 as
// in the push grunt's call 8C0940DA(1116, 0, 0, 0)), straight into the mixer; not an event of any world
bool Session::preview_sound(int32_t id, uint32_t tone)
{
    if (tone == 0 || tone > 2047 || !audio_.is_open()) {
        return false;
    }
    sa1_event e;
    std::memset(&e, 0, sizeof e);
    e.type = SA1_EVENT_SOUND;
    e.id = tone;
    Character *c = id > 0 ? get(id) : nullptr;
    if (c) {
        e.character = (sa1_character_id)id;
        std::memcpy(e.position, c->st.position, sizeof e.position);
        e.step = c->st.step;
    }
    audio_.event(e);
    return true;
}

bool Session::preview_voice(int32_t id, uint32_t voice)
{
    if (voice > 4095 || !audio_.is_open()) {
        return false;
    }
    sa1_event e;
    std::memset(&e, 0, sizeof e);
    e.type = SA1_EVENT_VOICE;
    e.id = voice;
    Character *c = id > 0 ? get(id) : nullptr;
    if (c) {
        e.character = (sa1_character_id)id;
        std::memcpy(e.position, c->st.position, sizeof e.position);
        e.step = c->st.step;
    }
    audio_.event(e);
    return true;
}

// ---- rendering --------------------------------------------------------------------------------------------------
sa1_status Session::render(int32_t id, float alpha)
{
    Character *c = get(id);
    if (!c || !ctx_) {
        last_error_ = "no such character";
        return SA1_ERR_NOT_FOUND;
    }
    if (!std::isfinite(alpha)) {
        alpha = 1.0f;
    }
    double t0 = now_ms();
    const sa1_render *r = nullptr;
    sa1_status st = sa1_character_render(ctx_, id, alpha, &r);
    if (SA1_FAILED(st) || !r) {
        last_error_ = scrub(format("sa1_character_render: %s: %s", sa1_status_string(st), sa1_last_error(ctx_)));
        return SA1_FAILED(st) ? st : SA1_ERR_NOT_FOUND;
    }
    c->rendered = true;
    c->r_gen = r->generation;
    c->r_alpha = r->alpha;
    c->r_interpolated = r->interpolated;
    std::memcpy(c->r_pos, r->position, sizeof c->r_pos);
    c->r_yaw = r->yaw;
    uint32_t nt = (r->positions && r->normals && r->uvs && r->colors) ? r->num_triangles : 0u;
    c->r_triangles = nt;
    c->r_tpos.assign(r->positions, r->positions + (size_t)nt * 9u);
    c->r_tnrm.assign(r->normals, r->normals + (size_t)nt * 9u);
    c->r_tuv.assign(r->uvs, r->uvs + (size_t)nt * 6u);
    c->r_tcol.assign(r->colors, r->colors + (size_t)nt * 12u);
    c->r_draws.assign(r->draws, r->draws + (r->draws ? r->num_draws : 0u));
    c->shadow_draws = 0;
    for (const sa1_draw &d : c->r_draws) {
        c->shadow_draws += (d.flags & SA1_DRAW_SHADOW) ? 1u : 0u;
    }
    c->r_sprites.assign(r->sprites, r->sprites + (r->sprites ? r->num_sprites : 0u));
    uint32_t nl = r->line_vertices ? (r->num_line_vertices & ~1u) : 0u;
    c->r_lines.assign(r->line_vertices, r->line_vertices + nl);
    // libsa1 moves every draw it could not match with the previous pair along with the interpolated root itself
    // (sa1_character.c root_shift, the libsa1 of G-SA1's 0.5 round); the frame is drawn exactly as libsa1 returns it
    // (0.4-0.5.1's follow_root moved such a frame a second time: sadc docs/research/gsa1_vertical_flicker.md, cause A).
    // r_shifted only reports it: libsa1's own flag when it has sa1_render.flags, else the old guess (which also flagged
    // frames libsa1 did not move: the first pair after a creation or after the CPU-pose fallback).
    bool has_flags = r->struct_size >= offsetof(sa1_render, flags) + sizeof(uint32_t);
    c->r_flags = has_flags ? r->flags : 0u;
    c->r_shifted = has_flags ? ((r->flags & SA1_RENDER_MOVED_WITH_ROOT) != 0 && !r->interpolated)
                             : (!r->interpolated && r->alpha < 1.0f);
    c->r_drawn_root = has_flags && (r->flags & SA1_RENDER_DRAWN_ROOT) != 0;
    if (c->r_shifted) {
        c->shifted_count++;
    }
    c->sprite_max = 0.0f;
    for (const sa1_sprite &sp : c->r_sprites) {
        float w = std::fabs(sp.rect[2] - sp.rect[0]);
        if (std::isfinite(w)) {
            c->sprite_max = std::max(c->sprite_max, w);
        }
    }
    c->render_count++;
    build_batches(*c);
    c->view_ready = false;
    c->render_ms = now_ms() - t0;
    return SA1_OK;
}

static uint32_t draw_wrap(const sa1_draw &d, const Character &c)
{
    if (d.archive < 0 || d.texture < 0) {
        return 0;
    }
    if (d.prim != SA1_PRIM_TRIANGLES) {
        return WRAP_CLAMP_U | WRAP_CLAMP_V;   // sprites: UVs span the image (no bleeding from the far edge)
    }
    if (d.source == SA1_SOURCE_POLYGON && d.material == 0) {
        // the game's textured 3D polygons (njDrawPolygon3D / njDrawTriangle3D, libsa1 round 4c F4: the Light Speed
        // ribbons, the barrier) carry no material: while their UVs stay inside the texture they use the clamped render
        // target the spawn painted, as sprites do, so their first draw creates no render target (round 4c, the Light
        // Speed charge freeze); UVs outside [0, 1] repeat
        uint32_t end = std::min(d.first + d.count, c.r_triangles);
        for (uint32_t t = d.first; t < end; t++) {
            for (int k = 0; k < 6; k++) {
                float u = c.r_tuv[(size_t)t * 6u + (size_t)k];
                if (!(u >= -0.001f && u <= 1.001f)) {
                    return 0;
                }
            }
        }
        return WRAP_CLAMP_U | WRAP_CLAMP_V;
    }
    uint32_t w = 0;
    if (d.material & SA1_MAT_CLAMP_U) {
        w |= WRAP_CLAMP_U;
    }
    if (d.material & SA1_MAT_CLAMP_V) {
        w |= WRAP_CLAMP_V;
    }
    if (d.material != 0 && SA1_MAT_FILTER(d.material) == 0) {
        w |= WRAP_POINT;
    }
    return w;
}

// 0.9.1, translucency T1 (sadc docs/research/gsa1_070_translucency.md section 7 with its review R2.1, R3.2, R3.3, R4).
// The game's fading copies - Tails' blur tails and ball copies (alpha 170 / 85), Amy's hammer ghosts (76 / 51), E-102's
// etx_right3 parts (216) - are palette-lit blended draws whose translucency is their vertex alpha. With gsa1_lighting 1
// their materials are VertexLitGeneric, which ignores $vertexalpha and $vertexcolor (Source SDK 2013
// vertexlitgeneric_dx9_helper.cpp; the owner's stdshader_dx9.dll 0x180063CDD), so 0.4 - 0.9.0 drew them solid. A lit
// translucent batch now carries that alpha (RenderBatch::alpha, key suffix ".a<alpha>") and the Lua side puts it into
// the material's $alpha. Only pass 1, not SA1_DRAW_UNLIT, not the shadow's mask: unlit materials honour $vertexalpha, and
// their alphas change from pair to pair (the stars' |sin|, the Light Speed streaks), which would make a key and a
// material per value.
static bool alpha_keyed(uint32_t pass, uint32_t flags, uint32_t wrap)
{
    return pass == 1 && !(flags & SA1_DRAW_UNLIT) && !(wrap & WRAP_MASK);
}

// the vertex alpha of draw d (count primitives from d.first): every colour's, constant for every lit draw libsa1 emits
// (the review counted them, also interpolated); when not, the mean and varied = true
static uint8_t draw_alpha(const sa1_draw &d, const Character &c, uint32_t count, bool &varied)
{
    uint32_t n = 0, sum = 0;
    int lo = 255, hi = 0;
    auto add = [&](int a) {
        n++;
        sum += (uint32_t)a;
        lo = std::min(lo, a);
        hi = std::max(hi, a);
    };
    if (d.prim == SA1_PRIM_TRIANGLES) {
        for (uint32_t t = d.first; t < d.first + count; t++) {
            for (uint32_t k = 0; k < 3; k++) {
                add(c.r_tcol[(size_t)t * 12u + (size_t)k * 4u + 3u]);
            }
        }
    } else if (d.prim == SA1_PRIM_SPRITES) {
        for (uint32_t s = d.first; s < d.first + count; s++) {
            add(c.r_sprites[s].color[3]);
        }
    } else if (d.prim == SA1_PRIM_LINES) {
        for (uint32_t s = d.first; s < d.first + count; s++) {
            add(c.r_lines[2u * s].color[3]);
            add(c.r_lines[2u * s + 1u].color[3]);
        }
    }
    if (n == 0) {
        return 255;
    }
    if (lo != hi) {
        varied = true;
        return (uint8_t)((sum + n / 2u) / n);
    }
    return (uint8_t)lo;
}

// the alpha a lit translucent batch state keys: the first kMaxLitAlphas exact values of the state, later ones rounded
// to a multiple of 17 (the review's guard for lit fades to come, e.g. the 1.0 game objects)
static uint8_t keyed_alpha(Character &c, uint64_t state, uint8_t a, bool &rounded)
{
    if (a == 255) {
        return 255;
    }
    std::vector<uint8_t> &seen = c.lit_alphas[state];
    for (uint8_t s : seen) {
        if (s == a) {
            return a;
        }
    }
    if (seen.size() < kMaxLitAlphas) {
        seen.push_back(a);
        return a;
    }
    rounded = true;
    return (uint8_t)std::min(255u, ((uint32_t)a + 8u) / 17u * 17u);
}

// 0.9.4 (sadc docs/research/gsa1_094_plan.md review R.1): a libsa1 draw of more than kMaxBatchTriangles output triangles
// - libsa1 merges consecutive draws of one state, so a run of 84+ ring models without their blobs between is one draw -
// becomes pieces of at most that many, each a draw of r_draws in the same place of the game's order (0.9.3a skipped such
// a draw whole: every ring of the run vanished). Returns how many draws were split.
static uint32_t split_large_draws(Character &c)
{
    auto avail_of = [&c](const sa1_draw &d) -> uint32_t {
        return d.prim == SA1_PRIM_TRIANGLES ? c.r_triangles
               : d.prim == SA1_PRIM_SPRITES ? (uint32_t)c.r_sprites.size()
               : d.prim == SA1_PRIM_LINES   ? (uint32_t)c.r_lines.size() / 2u
                                            : 0u;
    };
    auto per_of = [](const sa1_draw &d) -> uint32_t {
        return d.prim == SA1_PRIM_TRIANGLES ? kMaxBatchTriangles : kMaxBatchTriangles / 2u;
    };
    bool any = false;
    for (const sa1_draw &d : c.r_draws) {
        uint32_t avail = avail_of(d);
        if (d.first < avail && d.count > 0 && std::min(d.count, avail - d.first) > per_of(d)) {
            any = true;
            break;
        }
    }
    if (!any) {
        return 0;
    }
    uint32_t split = 0;
    std::vector<sa1_draw> out;
    out.reserve(c.r_draws.size() + 8u);
    for (const sa1_draw &d : c.r_draws) {
        uint32_t avail = avail_of(d);
        uint32_t count = d.first < avail ? std::min(d.count, avail - d.first) : 0u;
        uint32_t per = per_of(d);
        if (count <= per) {
            out.push_back(d);
            continue;
        }
        split++;
        for (uint32_t f = d.first; f < d.first + count; f += per) {
            sa1_draw p = d;
            p.first = f;
            p.count = std::min(per, d.first + count - f);
            out.push_back(p);
        }
    }
    c.r_draws.swap(out);
    return split;
}

void Session::build_batches(Character &c)
{
    c.batch_count = 0;
    c.out_triangles = 0;
    c.split_draws = split_large_draws(c);
    c.split_draws_total += c.split_draws;
    int32_t last_blend = -1;
    for (uint32_t di = 0; di < (uint32_t)c.r_draws.size(); di++) {
        const sa1_draw &d = c.r_draws[di];
        uint32_t avail = d.prim == SA1_PRIM_TRIANGLES ? c.r_triangles
                         : d.prim == SA1_PRIM_SPRITES ? (uint32_t)c.r_sprites.size()
                         : d.prim == SA1_PRIM_LINES   ? (uint32_t)c.r_lines.size() / 2u
                                                      : 0u;
        if (d.first >= avail || d.count == 0) {
            continue;
        }
        uint32_t count = std::min(d.count, avail - d.first);
        uint32_t tris = d.prim == SA1_PRIM_TRIANGLES ? count : 2u * count;
        if (tris > kMaxBatchTriangles) {
            continue;
        }
        bool textured = d.archive >= 0 && d.texture >= 0 && (uint32_t)d.archive < std::max(1u, c.num_archives);
        uint32_t f = d.flags & kBatchKeyFlags;
        if (d.prim != SA1_PRIM_TRIANGLES) {
            f |= SA1_DRAW_DOUBLE_SIDED;
        }
        uint32_t pass = (f & SA1_DRAW_BLEND) ? 1u : 0u;
        uint8_t bs = pass ? d.blend_src : (uint8_t)SA1_BLEND_ONE, bd = pass ? d.blend_dst : (uint8_t)SA1_BLEND_ZERO;
        int32_t ar = textured ? d.archive : -1, tx = textured ? d.texture : -1;
        uint32_t wrap = textured ? draw_wrap(d, c) : 0u;
        // the blob shadow (libsa1's SA1_DRAW_SHADOW: OBJ_REGULAR's black "shadow" texture, SRC_ALPHA / INV_SRC_ALPHA,
        // the diffuse alpha 204) as a darkening mask (WRAP_MASK; sadc docs/research/gsa1_060_shadow.md G3)
        if ((d.flags & SA1_DRAW_SHADOW) && pass && textured && d.prim == SA1_PRIM_TRIANGLES &&
            !(d.flags & SA1_DRAW_ADDITIVE) && bs == SA1_BLEND_SRC_ALPHA && bd == SA1_BLEND_INV_SRC_ALPHA &&
            texture_black(c.kind, ar, tx)) {
            wrap |= WRAP_MASK;
        }
#if defined(SA1_DRAW_SUPER_GOLD)
        // 0.9.4a (super2_plan.md 6.4 task 2): a textured draw libsa1 marked gold draws the texture's golden variant (its own
        // render target: the wrap is in the batch key, the merge tests and the render target's name)
        if ((d.flags & SA1_DRAW_SUPER_GOLD) && textured) {
            wrap |= WRAP_GOLD;
        }
#endif
        // a lit translucent draw's vertex alpha (T1 above): only draws of equal alpha share a batch
        uint8_t alpha = 255;
        if (alpha_keyed(pass, f, wrap)) {
            bool varied = false, rounded = false;
            uint8_t a = draw_alpha(d, c, count, varied);
            uint64_t state = ((uint64_t)(uint8_t)ar << 48) | ((uint64_t)(uint16_t)tx << 32) | ((uint64_t)(f & 0xFFFFu) << 16) |
                             ((uint64_t)(bs & 15u) << 12) | ((uint64_t)(bd & 15u) << 8) | (uint64_t)(wrap & 0xFFu);
            alpha = keyed_alpha(c, state, a, rounded);
            c.lit_alpha_varied += varied ? 1u : 0u;
            c.lit_alpha_rounded += rounded ? 1u : 0u;
            if ((varied || rounded) && !c.lit_alpha_logged) {
                c.lit_alpha_logged = true;
                log_line(SA1_LOG_WARN, format("G-SA1 render: a lit see-through draw of character kind %d (texture %d of "
                                              "archive %d, flags %X) %s; reported once per character", c.kind, tx, ar, f,
                                              varied ? "had several vertex alphas (the material takes their mean)"
                                                     : "has more alphas than G-SA1 keeps exactly (rounded to steps of 17)")
                                           .c_str());
            }
        }
        // the batch: opaque - any batch of the same state; blended - only the last blended batch (game order)
        int32_t target = -1;
        if (pass == 0) {
            for (uint32_t b = 0; b < c.batch_count; b++) {
                const RenderBatch &rb = c.batches[b];
                if (rb.pass == 0 && rb.archive == ar && rb.texture == tx && rb.flags == f && rb.wrap == wrap &&
                    rb.triangles + tris <= kMaxBatchTriangles) {
                    target = (int32_t)b;
                    break;
                }
            }
        } else if (last_blend >= 0) {
            const RenderBatch &rb = c.batches[(size_t)last_blend];
            if (rb.archive == ar && rb.texture == tx && rb.flags == f && rb.wrap == wrap && rb.blend_src == bs &&
                rb.blend_dst == bd && rb.alpha == alpha && rb.triangles + tris <= kMaxBatchTriangles) {
                target = last_blend;
            }
        }
        if (target < 0) {
            if (c.batches.size() <= c.batch_count) {
                c.batches.resize(c.batch_count + 1);
            }
            RenderBatch &nb = c.batches[c.batch_count];
            nb.pass = pass;
            nb.archive = ar;
            nb.texture = tx;
            nb.flags = f;
            nb.all_flags = 0;
            nb.material = d.material;
            nb.blend_src = bs;
            nb.blend_dst = bd;
            nb.source = d.source;
            nb.prims = 0;
            nb.wrap = wrap;
            nb.order = d.order;
            nb.triangles = 0;
            nb.alpha = alpha;
            nb.draws.clear();
            nb.key = format("%d.%d.%X.%u.%u.%u.%u", ar, tx, f, (unsigned)bs, (unsigned)bd, wrap, pass);
            if (alpha < 255) {
                nb.key += format(".a%u", (unsigned)alpha);   // (existing keys and census states stay as they were)
            }
            target = (int32_t)c.batch_count++;
        }
        RenderBatch &rb = c.batches[(size_t)target];
        rb.all_flags |= d.flags;
        rb.prims |= (uint8_t)(1u << (d.prim & 7u));
        rb.triangles += tris;
        rb.draws.push_back(di);
        c.out_triangles += tris;
        if (pass) {
            last_blend = target;
        }
    }
    uint64_t sig = 1469598103934665603ull;
    for (uint32_t b = 0; b < c.batch_count; b++) {
        const RenderBatch &rb = c.batches[b];
        sig = fnv(sig, rb.key.data(), rb.key.size());
        sig = fnv(sig, &rb.triangles, sizeof rb.triangles);
        sig = fnv(sig, &rb.all_flags, sizeof rb.all_flags);
    }
    if (sig != c.batch_sig || c.batch_gen == 0) {
        c.batch_sig = sig;
        c.batch_gen++;
    }
}

double triangle_pixels(const float eye[3], const float right[3], const float up[3], const float fwd[3], double tan_h,
                       double tan_v, double width, double height, const float *a, const float *b, const float *c)
{
    const double znear = 3.0;
    const float *P[3] = {a, b, c};
    double cam[3][3];
    for (int i = 0; i < 3; i++) {
        double d[3] = {(double)P[i][0] - eye[0], (double)P[i][1] - eye[1], (double)P[i][2] - eye[2]};
        cam[i][0] = d[0] * right[0] + d[1] * right[1] + d[2] * right[2];
        cam[i][1] = d[0] * up[0] + d[1] * up[1] + d[2] * up[2];
        cam[i][2] = d[0] * fwd[0] + d[1] * fwd[1] + d[2] * fwd[2];
    }
    // near clip (at most 4 points), then the projection
    double poly[4][3];
    int np = 0;
    for (int i = 0; i < 3; i++) {
        const double *p0 = cam[i], *p1 = cam[(i + 1) % 3];
        bool in0 = p0[2] >= znear, in1 = p1[2] >= znear;
        if (in0) {
            poly[np][0] = p0[0];
            poly[np][1] = p0[1];
            poly[np][2] = p0[2];
            np++;
        }
        if (in0 != in1) {
            double t = (znear - p0[2]) / (p1[2] - p0[2]);
            poly[np][0] = p0[0] + t * (p1[0] - p0[0]);
            poly[np][1] = p0[1] + t * (p1[1] - p0[1]);
            poly[np][2] = znear;
            np++;
        }
    }
    if (np < 3) {
        return 0.0;
    }
    double s[2][12][2];   // ping-pong buffers of the screen clip (each of the 4 edges adds at most one point)
    int ns = np, cur = 0;
    for (int i = 0; i < np; i++) {
        s[0][i][0] = width * 0.5 + poly[i][0] / poly[i][2] * (width * 0.5) / tan_h;
        s[0][i][1] = height * 0.5 - poly[i][1] / poly[i][2] * (height * 0.5) / tan_v;
    }
    for (int edge = 0; edge < 4 && ns >= 3; edge++) {
        int axis = edge >> 1;
        double lim = (edge & 1) ? (axis ? height : width) : 0.0;
        bool keep_ge = (edge & 1) == 0;
        int no = 0;
        for (int i = 0; i < ns && no < 11; i++) {
            const double *p0 = s[cur][i], *p1 = s[cur][(i + 1) % ns];
            bool in0 = keep_ge ? p0[axis] >= lim : p0[axis] <= lim;
            bool in1 = keep_ge ? p1[axis] >= lim : p1[axis] <= lim;
            if (in0) {
                s[cur ^ 1][no][0] = p0[0];
                s[cur ^ 1][no][1] = p0[1];
                no++;
            }
            if (in0 != in1) {
                double t = (lim - p0[axis]) / (p1[axis] - p0[axis]);
                s[cur ^ 1][no][0] = p0[0] + t * (p1[0] - p0[0]);
                s[cur ^ 1][no][1] = p0[1] + t * (p1[1] - p0[1]);
                no++;
            }
        }
        cur ^= 1;
        ns = no;
    }
    if (ns < 3) {
        return 0.0;
    }
    double area = 0.0;
    for (int i = 0; i < ns; i++) {
        const double *p0 = s[cur][i], *p1 = s[cur][(i + 1) % ns];
        area += p0[0] * p1[1] - p1[0] * p0[1];
    }
    double px = std::fabs(area) * 0.5;
    return std::isfinite(px) ? px : 0.0;
}

void Session::prepare_view(Character &c, const float eye[3], const float right[3], const float up[3],
                           const ViewOptions &opt)
{
    double t0 = now_ms();
    for (int k = 0; k < 3; k++) {
        c.view_eye[k] = std::isfinite(eye[k]) ? eye[k] : 0.0f;
        c.view_right[k] = std::isfinite(right[k]) ? right[k] : 0.0f;
        c.view_up[k] = std::isfinite(up[k]) ? up[k] : 0.0f;
    }
    normalize3(c.view_right);
    normalize3(c.view_up);
    c.view_opt = opt;
    // 0.8, camera-relative drawing (ViewOptions::relative): every position is written as p - O, subtracted in double
    double O[3] = {0.0, 0.0, 0.0};
    if (opt.relative) {
        for (int k = 0; k < 3; k++) {
            O[k] = std::isfinite(opt.origin[k]) ? (double)opt.origin[k] : 0.0;
            c.view_opt.origin[k] = (float)O[k];
        }
    }
    auto rel = [&O](const float *p, float *out) {
        for (int k = 0; k < 3; k++) {
            out[k] = (float)((double)p[k] - O[k]);
        }
    };
    const float *R = c.view_right, *U = c.view_up;
    float E[3];   // the eye in the same frame as the written positions
    rel(c.view_eye, E);
    // a pixel of a 75 degree, 1080-line view at distance d is about d * 2 tan(37.5 deg) / 1080 wide
    const float px_per_dist = 0.001425f;
    static const int ccw_to_cw[3] = {0, 2, 1};
    // the screen for the coverage (round 4c E5): forward = up x right (Source: right-handed, z up)
    bool cover = opt.fov > 1.0f && opt.fov < 179.0f && opt.width >= 16.0f && opt.height >= 16.0f &&
                 std::isfinite(opt.fov) && std::isfinite(opt.width) && std::isfinite(opt.height);
    float F[3] = {U[1] * R[2] - U[2] * R[1], U[2] * R[0] - U[0] * R[2], U[0] * R[1] - U[1] * R[0]};
    normalize3(F);
    double tan_h = 0.0, tan_v = 0.0, screen = 1.0;
    if (cover) {
        // Source's Hor+: fov is the horizontal field of view of a 4:3 view
        double t43 = std::tan((double)opt.fov * 3.14159265358979323846 / 360.0);
        tan_h = t43 * ((double)opt.width / (double)opt.height) / (4.0 / 3.0);
        tan_v = t43 * 0.75;
        screen = (double)opt.width * (double)opt.height;
    }
    double cover_all = 0.0, cover_sprites = 0.0;
    for (uint32_t b = 0; b < c.batch_count; b++) {
        RenderBatch &rb = c.batches[b];
        size_t nv = (size_t)rb.triangles * 3u;
        rb.pos.resize(nv * 3u);
        rb.nrm.resize(nv * 3u);
        rb.uv.resize(nv * 2u);
        rb.col.resize(nv * 4u);
        bool env = (rb.flags & SA1_DRAW_ENV_MAP) != 0;
        // gsa1_vertexcolor 0 drops the vertex colour of textured draws only (round 4c F6): an untextured draw (the
        // Light Speed aura, ribbons, lines) is nothing but its vertex colour; palette-lit draws are white already; the
        // blob shadow keeps it (its diffuse alpha is the shadow's darkness: sadc docs/research/gsa1_060_shadow.md R.3.3a)
        bool white = !opt.vertex_color && !(rb.flags & SA1_DRAW_PALETTE_LIT) && rb.archive >= 0 &&
                     !(rb.flags & SA1_DRAW_SHADOW);
        // the shadow's mask path (WRAP_MASK): the vertex colour (a, a, a, 255), so texture (RGB = the texel's alpha) x
        // vertex colour = a x tex.a, the share of the destination the game's SRC_ALPHA / INV_SRC_ALPHA blend removes
        bool mask = (rb.wrap & WRAP_MASK) != 0;
        rb.need_normal = opt.lit && !(rb.flags & SA1_DRAW_UNLIT);
        rb.need_uv = rb.archive >= 0 || env;
        size_t v = 0;
        auto put = [&](const float *p, const float *n, float u, float tv, const uint8_t *col) {
            if (v >= nv) {
                return;
            }
            std::memcpy(&rb.pos[v * 3u], p, 12);
            std::memcpy(&rb.nrm[v * 3u], n, 12);
            if (env) {
                u = 0.5f + 0.5f * dot3(n, R);
                tv = 0.5f - 0.5f * dot3(n, U);
            }
            rb.uv[v * 2u] = u;
            rb.uv[v * 2u + 1u] = tv;
            std::memcpy(&rb.col[v * 4u], col, 4);
            if (white) {
                rb.col[v * 4u] = rb.col[v * 4u + 1u] = rb.col[v * 4u + 2u] = 255;
            } else if (mask) {
                rb.col[v * 4u] = rb.col[v * 4u + 1u] = rb.col[v * 4u + 2u] = col[3];
                rb.col[v * 4u + 3u] = 255;
            }
            v++;
        };
        for (uint32_t di : rb.draws) {
            const sa1_draw &d = c.r_draws[di];
            if (d.prim == SA1_PRIM_TRIANGLES) {
                uint32_t end = std::min(d.first + d.count, c.r_triangles);
                for (uint32_t t = d.first; t < end; t++) {
                    for (int k = 0; k < 3; k++) {
                        int corner = opt.flip ? k : ccw_to_cw[k];
                        size_t i3 = (size_t)t * 9u + (size_t)corner * 3u;
                        float pr[3];
                        rel(&c.r_tpos[i3], pr);
                        put(pr, &c.r_tnrm[i3], c.r_tuv[(size_t)t * 6u + (size_t)corner * 2u],
                            c.r_tuv[(size_t)t * 6u + (size_t)corner * 2u + 1u], &c.r_tcol[(size_t)t * 12u + (size_t)corner * 4u]);
                    }
                }
            } else if (d.prim == SA1_PRIM_SPRITES) {
                uint32_t end = std::min(d.first + d.count, (uint32_t)c.r_sprites.size());
                for (uint32_t s = d.first; s < end; s++) {
                    const sa1_sprite &sp = c.r_sprites[s];
                    float ca = std::cos(sp.angle), sa = std::sin(sp.angle);
                    float corner[4][3], cuv[4][2], n[3], anchor[3];
                    rel(sp.position, anchor);
                    static const int cx[4] = {0, 2, 2, 0}, cy[4] = {1, 1, 3, 3};
                    for (int k = 0; k < 4; k++) {
                        float x = sp.rect[cx[k]], y = sp.rect[cy[k]];
                        float xr = x * ca - y * sa, yr = x * sa + y * ca;
                        for (int j = 0; j < 3; j++) {
                            corner[k][j] = anchor[j] + R[j] * xr - U[j] * yr;
                        }
                        cuv[k][0] = cx[k] == 0 ? sp.uv[0] : sp.uv[2];
                        cuv[k][1] = cy[k] == 1 ? sp.uv[1] : sp.uv[3];
                    }
                    for (int j = 0; j < 3; j++) {
                        n[j] = E[j] - anchor[j];
                    }
                    normalize3(n);
                    // top-left, top-right, bottom-right is clockwise on screen: Source's front
                    static const int cw[6] = {0, 1, 2, 0, 2, 3}, ccw[6] = {0, 2, 1, 0, 3, 2};
                    const int *ord = opt.flip ? ccw : cw;
                    for (int k = 0; k < 6; k++) {
                        put(corner[ord[k]], n, cuv[ord[k]][0], cuv[ord[k]][1], sp.color);
                    }
                }
            } else if (d.prim == SA1_PRIM_LINES) {
                uint32_t end = std::min(d.first + d.count, (uint32_t)c.r_lines.size() / 2u);
                for (uint32_t s = d.first; s < end; s++) {
                    const sa1_line_vertex &a = c.r_lines[2u * s], &bv = c.r_lines[2u * s + 1u];
                    float dir[3], mid[3], to_eye[3], side[3], n[3], pa[3], pb[3];
                    rel(a.position, pa);
                    rel(bv.position, pb);
                    for (int j = 0; j < 3; j++) {
                        dir[j] = pb[j] - pa[j];
                        mid[j] = 0.5f * (pa[j] + pb[j]);
                        to_eye[j] = E[j] - mid[j];
                    }
                    float dist = std::sqrt(dot3(to_eye, to_eye));
                    side[0] = dir[1] * to_eye[2] - dir[2] * to_eye[1];
                    side[1] = dir[2] * to_eye[0] - dir[0] * to_eye[2];
                    side[2] = dir[0] * to_eye[1] - dir[1] * to_eye[0];
                    normalize3(side);
                    std::memcpy(n, to_eye, sizeof n);
                    normalize3(n);
                    float hw = std::max(0.05f, 0.5f * opt.line_pixels * px_per_dist * dist);
                    float q[4][3];   // a - s, a + s, b + s, b - s
                    for (int j = 0; j < 3; j++) {
                        q[0][j] = pa[j] - side[j] * hw;
                        q[1][j] = pa[j] + side[j] * hw;
                        q[2][j] = pb[j] + side[j] * hw;
                        q[3][j] = pb[j] - side[j] * hw;
                    }
                    const uint8_t *qc[4] = {a.color, a.color, bv.color, bv.color};
                    static const float quv[4][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};
                    // (q0, q1, q2) is counter-clockwise seen from the eye: Source's front is (q0, q2, q1)
                    static const int cw[6] = {0, 2, 1, 0, 3, 2}, ccw[6] = {0, 1, 2, 0, 2, 3};
                    const int *ord = opt.flip ? ccw : cw;
                    for (int k = 0; k < 6; k++) {
                        put(q[ord[k]], n, quv[ord[k]][0], quv[ord[k]][1], qc[ord[k]]);
                    }
                }
            }
        }
        // never fewer vertices than the batch declares (mesh.Begin's count): degenerate filler at the last point
        while (v < nv) {
            static const float zero[3] = {0, 0, 1};
            static const uint8_t clear[4] = {0, 0, 0, 0};
            float pp[3];
            if (v > 0) {
                std::memcpy(pp, &rb.pos[(v - 1) * 3u], sizeof pp);
            } else {
                rel(c.r_pos, pp);
            }
            put(pp, zero, 0.0f, 0.0f, clear);
        }
        if (cover && rb.pass == 1) {
            double px = 0.0;
            for (size_t t = 0; t < (size_t)rb.triangles; t++) {
                px += triangle_pixels(E, R, U, F, tan_h, tan_v, opt.width, opt.height, &rb.pos[t * 9u], &rb.pos[t * 9u + 3u],
                                      &rb.pos[t * 9u + 6u]);
            }
            cover_all += px;
            if (rb.prims & (1u << SA1_PRIM_SPRITES)) {
                cover_sprites += px;
            }
        }
    }
    c.view_cover = cover ? (float)(cover_all / screen) : 0.0f;
    c.view_cover_sprites = cover ? (float)(cover_sprites / screen) : 0.0f;
    c.view_ready = true;
    c.view_ms = now_ms() - t0;
}

// ---- textures ---------------------------------------------------------------------------------------------------
uint32_t Session::texture_archives(int32_t kind)
{
    if (!ready() || kind < 0 || kind >= SA1_CHAR_COUNT) {
        return 0;
    }
    sa1_character_info info;
    std::memset(&info, 0, sizeof info);
    info.struct_size = sizeof info;
    if (sa1_character_info_get(ctx_, kind, &info) != SA1_OK || !info.loaded) {
        return 0;
    }
    return std::min<uint32_t>(info.num_archives, 64u);
}

bool Session::texture_count(int32_t kind, uint32_t archive, uint32_t &count, std::string &err, std::string *name)
{
    count = 0;
    if (!ready()) {
        err = "not initialised";
        return false;
    }
    const char *nm = nullptr;
    sa1_status st = sa1_texture_archive(ctx_, kind, archive, &nm, &count);
    if (SA1_FAILED(st)) {
        err = scrub(format("%s: %s", sa1_status_string(st), sa1_last_error(ctx_)));
        return false;
    }
    if (name) {
        *name = nm ? nm : "";
    }
    return true;
}

bool Session::texture_runs(int32_t kind, uint32_t archive, uint32_t index, TextureRuns &out, std::string &err,
                           uint32_t variant)
{
    out = TextureRuns();
    if (!ready()) {
        err = "not initialised";
        return false;
    }
    sa1_texture_info ti;
    std::memset(&ti, 0, sizeof ti);
    ti.struct_size = sizeof ti;
    sa1_status st;
    if (variant > 0) {
        // 0.9.4a (review R.6): libsa1's variant of the texture (the golden Light Speed charge: SA1_TEXTURE_VARIANT_SUPER_GOLD)
#if defined(SA1_TEXTURE_VARIANT_SUPER_GOLD)
        st = sa1_texture_variant_get(ctx_, kind, archive, index, variant, &ti);
#else
        err = "this libsa1 has no texture variants (round 0.9.4a)";
        return false;
#endif
    } else {
        st = sa1_texture_get(ctx_, kind, archive, index, &ti);
    }
    if (variant > 0 && st == SA1_ERR_NOT_FOUND) {
        // (sa1_texture_variant_get leaves no text of its own: the context's last error would be an older call's)
        err = format("texture %u of archive %u of character %d has no variant %u (libsa1 makes the golden one for Sonic's "
                     "SON_EFF lcharge01-04 only)", (unsigned)index, (unsigned)archive, (int)kind, (unsigned)variant);
        return false;
    }
    if (SA1_FAILED(st)) {
        err = scrub(format("%s: %s", sa1_status_string(st), sa1_last_error(ctx_)));
        return false;
    }
    if (!ti.rgba || ti.width == 0 || ti.height == 0 || ti.width > 4096 || ti.height > 4096) {
        err = "the texture could not be decoded";
        return false;
    }
    out.width = ti.width;
    out.height = ti.height;
    out.pixel_format = ti.pixel_format;
    out.data_format = ti.data_format;
    out.alpha = ti.alpha;
    out.name = ti.name ? ti.name : "";
    const uint8_t *px = ti.rgba;
    int best = -1;
    for (uint32_t y = 0; y < ti.height; y++) {
        uint32_t x = 0;
        while (x < ti.width) {
            const uint8_t *p = px + ((size_t)y * ti.width + x) * 4;
            uint32_t len = 1;
            while (x + len < ti.width && len < 65535u && std::memcmp(p, p + 4 * len, 4) == 0) {
                len++;
            }
            if (p[0] | p[1] | p[2] | p[3]) {
                uint8_t rec[10] = {(uint8_t)x, (uint8_t)(x >> 8), (uint8_t)y, (uint8_t)(y >> 8),
                                   (uint8_t)len, (uint8_t)(len >> 8), p[0], p[1], p[2], p[3]};
                out.runs.append((const char *)rec, sizeof rec);
                out.run_count++;
                int lum = std::max(p[0], std::max(p[1], p[2]));
                if (p[3] == 255 && lum > best) {
                    best = lum;
                    out.has_canary = true;
                    out.canary_x = x;
                    out.canary_y = y;
                    std::memcpy(out.canary, p, 4);
                }
            }
            x += len;
        }
    }
    return true;
}

bool Session::texture_black(int32_t kind, int32_t archive, int32_t index)
{
    if (!ready() || kind < 0 || archive < 0 || index < 0) {
        return false;
    }
    uint64_t key = ((uint64_t)(uint32_t)kind << 40) ^ ((uint64_t)(uint32_t)archive << 20) ^ (uint64_t)(uint32_t)index;
    auto it = black_.find(key);
    if (it != black_.end()) {
        return it->second;
    }
    bool black = false;
    sa1_texture_info ti;
    std::memset(&ti, 0, sizeof ti);
    ti.struct_size = sizeof ti;
    if (sa1_texture_get(ctx_, kind, (uint32_t)archive, (uint32_t)index, &ti) == SA1_OK && ti.rgba && ti.width > 0 &&
        ti.height > 0 && ti.width <= 4096 && ti.height <= 4096) {
        black = true;
        const uint8_t *p = ti.rgba;
        for (size_t i = 0, n = (size_t)ti.width * ti.height; i < n && black; i++, p += 4) {
            black = (p[0] | p[1] | p[2]) == 0;
        }
    }
    black_[key] = black;
    return black;
}

bool Session::texture_pixel(int32_t kind, uint32_t archive, uint32_t index, uint32_t x, uint32_t y, uint8_t out[4])
{
    if (!ready()) {
        return false;
    }
    sa1_texture_info ti;
    std::memset(&ti, 0, sizeof ti);
    ti.struct_size = sizeof ti;
    if (sa1_texture_get(ctx_, kind, archive, index, &ti) != SA1_OK || !ti.rgba || x >= ti.width || y >= ti.height) {
        return false;
    }
    std::memcpy(out, ti.rgba + ((size_t)y * ti.width + x) * 4u, 4);
    return true;
}

}  // namespace gsa1
