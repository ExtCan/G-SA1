// skin_args.hpp - round 0.9.9f (metal099e.md 4.2): a skin's entry (feat/sh_skins.lua GSA1.Skins.DescOf, a flat table) as libsa1's sa1_skin_desc. The data names the character: base, model
// source, animation overrides and voice live in the entry; libsa1 holds no Metal Sonic numbers. The struct and what it points at live as long as this object: libsa1 reads them during the call only.
#pragma once
#include "libsa1.h"
#include "GarrysMod/Lua/Interface.h"
#include <cstdint>
#include <string>
#include <vector>

#if defined(SA1_API_SKIN)
namespace gsa1 {
namespace skinargs {

using GarrysMod::Lua::ILuaBase;
namespace LT = GarrysMod::Lua::Type;

inline bool get_string(ILuaBase *L, int t, const char *k, std::string &out)
{
    L->PushString(k);
    L->RawGet(t);
    bool ok = L->GetType(-1) == LT::String;
    if (ok) {
        out = L->GetString(-1);
    }
    L->Pop();
    return ok;
}

inline bool get_number(ILuaBase *L, int t, const char *k, double &out)
{
    L->PushString(k);
    L->RawGet(t);
    bool ok = L->GetType(-1) == LT::Number;
    if (ok) {
        out = L->GetNumber(-1);
    }
    L->Pop();
    return ok;
}

// the numbers of an array field; at most max, each lo..hi
inline bool get_array(ILuaBase *L, int t, const char *k, double lo, double hi, size_t max, std::vector<int> &out)
{
    out.clear();
    L->PushString(k);
    L->RawGet(t);
    bool ok = L->GetType(-1) == LT::Table;
    if (ok) {
        int a = L->Top();
        for (int i = 1;; i++) {
            L->PushNumber((double)i);
            L->RawGet(a);
            int ty = L->GetType(-1);
            if (ty != LT::Number) {
                L->Pop();
                ok = ty == LT::Nil || ty == LT::None;
                break;
            }
            double v = L->GetNumber(-1);
            L->Pop();
            if (!(v >= lo && v <= hi) || out.size() >= max) {
                ok = false;
                break;
            }
            out.push_back((int)v);
        }
    }
    L->Pop();
    return ok;
}

struct SkinArgs {
    std::string model_file, model_sha1, tex_file, tex_sha1, id;
    std::vector<uint16_t> keep;
    std::vector<sa1_skin_part> parts;
    std::vector<uint16_t> anim, walk, fast; // pairs
    sa1_skin_desc d;
    SkinArgs() { d = sa1_skin_desc(); }

    // the table at stack index t (absolute); false: what is wrong in err
    bool read(ILuaBase *L, int t, std::string &err)
    {
        double load = 0.0, first = 0.0, end = 0.0, root = 0.0, scale = 0.0, lift = 0.0, turn = 0.0, ball = -1.0;
        std::vector<int> k, p, a, w;
        if (!get_string(L, t, "model_file", model_file) || !get_string(L, t, "model_sha1", model_sha1) || !get_string(L, t, "tex_file", tex_file) ||
            !get_string(L, t, "tex_sha1", tex_sha1) || !get_number(L, t, "model_load", load) || !get_number(L, t, "model_first", first) ||
            !get_number(L, t, "model_end", end) || !get_number(L, t, "model_root", root) || !get_number(L, t, "scale", scale) || !get_number(L, t, "lift", lift) ||
            !get_number(L, t, "turn", turn) || !get_number(L, t, "ball_texture", ball)) {
            err = "extras.skin: a field of the entry is missing (GSA1.Skins.DescOf)";
            return false;
        }
        if (!get_array(L, t, "keep", 0.0, 65535.0, 64, k) || !get_array(L, t, "parts", -1.0, 127.0, 4 * 32, p) || p.size() % 4 != 0 || !get_array(L, t, "anim", 0.0, 1023.0, 32, a) ||
            a.size() % 2 != 0 || !get_array(L, t, "anim_walk", 0.0, 1023.0, 16, w) || w.size() % 2 != 0) {
            err = "extras.skin: keep, parts, anim, anim_walk: arrays of whole numbers, parts by four, anim by two";
            return false;
        }
        // 0.9.9g: the way between a walk and a run, the glow; absent: none
        std::vector<int> f;
        double fast_on = 0.0, fast_off = 0.0, gr = 0.0, gg = 0.0, gb = 0.0, inflate = 0.0;
        L->PushString("anim_fast");
        L->RawGet(t);
        bool has_fast = L->GetType(-1) == LT::Table;
        L->Pop();
        if (has_fast && (!get_array(L, t, "anim_fast", 0.0, 1023.0, 16, f) || f.size() % 2 != 0)) {
            err = "extras.skin: anim_fast: an array of whole numbers, by two";
            return false;
        }
        get_number(L, t, "fast_on", fast_on);
        get_number(L, t, "fast_off", fast_off);
        get_number(L, t, "glow_r", gr);
        get_number(L, t, "glow_g", gg);
        get_number(L, t, "glow_b", gb);
        get_number(L, t, "glow_inflate", inflate);
        keep.assign(k.begin(), k.end());
        parts.resize(p.size() / 4);
        for (size_t i = 0; i < parts.size(); i++) {
            parts[i].joint_node = (int8_t)p[4 * i];
            parts[i].mesh_node = (int8_t)p[4 * i + 1];
            parts[i].bone_end = (int8_t)p[4 * i + 2];
            parts[i].driver_bone_end = (int8_t)p[4 * i + 3];
        }
        anim.assign(a.begin(), a.end());
        walk.assign(w.begin(), w.end());
        d = sa1_skin_desc();
        d.struct_size = sizeof d;
        d.model_file = model_file.c_str();
        d.model_sha1 = model_sha1.c_str();
        d.model_load = (uint32_t)load;
        d.model_first = (uint32_t)first;
        d.model_end = (uint32_t)end;
        d.model_root = (uint32_t)root;
        d.tex_file = tex_file.c_str();
        d.tex_sha1 = tex_sha1.c_str();
        d.tex_keep = keep.data();
        d.num_tex_keep = (uint32_t)keep.size();
        d.scale = (float)scale;
        d.lift = (float)lift;
        d.turn = (int32_t)turn;
        d.ball_texture = (int32_t)ball;
        d.parts = parts.data();
        d.num_parts = (uint32_t)parts.size();
        d.anim = reinterpret_cast<const uint16_t (*)[2]>(anim.data());
        d.num_anim = (uint32_t)(anim.size() / 2);
        d.anim_walk = reinterpret_cast<const uint16_t (*)[2]>(walk.data());
        d.num_anim_walk = (uint32_t)(walk.size() / 2);
        fast.assign(f.begin(), f.end());
        d.anim_fast = reinterpret_cast<const uint16_t (*)[2]>(fast.data());
        d.num_anim_fast = (uint32_t)(fast.size() / 2);
        d.fast_on = (float)fast_on;
        d.fast_off = (float)fast_off;
        d.glow_rgb[0] = (float)gr;
        d.glow_rgb[1] = (float)gg;
        d.glow_rgb[2] = (float)gb;
        d.glow_inflate = (float)inflate;
#if SA1_API_SKIN >= 3
        // 1.0.0-beta1 (sadc docs/research/gsa1_100_select.md 4.3.1, 4.3.2): the skin's identity (many skins at once), its base and the trails' colour; absent: none
        double bk = 0.0, tr = 0.0, tg = 0.0, tb = 0.0;
        id.clear();
        get_string(L, t, "id", id);
        get_number(L, t, "base_kind", bk);
        get_number(L, t, "trail_r", tr);
        get_number(L, t, "trail_g", tg);
        get_number(L, t, "trail_b", tb);
        if (id.size() > 64) {
            err = "extras.skin: id: at most 64 characters";
            return false;
        }
        if (!(tr >= 0.0 && tr <= 1.0 && tg >= 0.0 && tg <= 1.0 && tb >= 0.0 && tb <= 1.0)) {
            err = "extras.skin: trail_r, trail_g, trail_b: 0 to 1";
            return false;
        }
        d.id = id.empty() ? nullptr : id.c_str();
        d.base_kind = (int32_t)bk;
        d.trail_rgb[0] = (float)tr;
        d.trail_rgb[1] = (float)tg;
        d.trail_rgb[2] = (float)tb;
#endif
        return true;
    }
};

}  // namespace skinargs
}  // namespace gsa1
#endif  // SA1_API_SKIN
