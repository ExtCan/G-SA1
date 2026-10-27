#!/usr/bin/env python3
"""Build G-SA1: the Garry's Mod client module gmcl_gsa1_<platform>.dll and the offline core tests.

    py -3.12 build.py                         # snapshot libsa1, build win64 + linux64, verify exports
    py -3.12 build.py --test [--gdi GAME.gdi] [--bsp MAP.bsp] [--maps DIR] [--fuzz N] [--seconds S] [--verbose]
    py -3.12 build.py --target x86_64-windows # one target
    py -3.12 build.py --no-snapshot           # reuse build/deps (do not touch libsa1's build lock)
    py -3.12 build.py --lib-build             # first build libsa1 itself for every target (LIB: build.py --target ...)
    py -3.12 build.py --clean
    py -3.12 build.py --libsa1 DIR --gmod DIR # libsa1's folder; Garry's Mod's garrysmod folder for the tests

Where things are (nothing of one PC is written here): LIB = libsa1's folder, --libsa1, else LIBSA1_ROOT, else
../libsa1 or ../LibSA1/libsa1 (the first with include/libsa1.h). The tests' Garry's Mod (read-only: gm_construct, the
VPKs, lua_shared.dll) = --gmod, else GARRYSMOD_DIR, else the first Steam library with GarrysMod/garrysmod (Steam's
registry entry and default places, each with its libraryfolders.vdf); it is passed to the tests as GARRYSMOD_DIR
(tests/gmod_paths.hpp searches the same way when a test is run by hand). The disc: --gdi, else SA1_TEST_GDI.

The snapshot refuses a target whose LIB/build/<target>/libsa1.a is older than libsa1's sources (LIB/include,
LIB/src, the lowered game code in LIB/build/pclower/ga64, LIB/build/gen): a libsa1 build that ran for one target only
must not leave another target linked against an old archive (0.5.0's linux64 module was; --allow-stale overrides).
With --maps DIR, binding_test also times the game's thread on DIR/gm_freespace_13.bsp when it is there.

With --test on Windows, the addon's Lua is also tested in Garry's Mod's own LuaJIT (its bin/win64/lua_shared.dll,
loaded read-only; GMOD_LUA_SHARED overrides the path; skipped with a message when it is not there): tests/lua_host.c
runs tests/log_test.lua (the session log), tests/warm_test.lua (the material pre-warm against core_test's material
census) and tests/frame_test.lua (the whole client frame against a mock of GMod and the module); 0.8:
tests/texture_alpha_test.lua (the textures' alpha against a render-target pixel model of GMod, tests/lua_mock_rt.lua)
and tests/render_test.lua (the character's drawing: the blob shadow, camera-relative drawing, the draw list).

Features (sadc docs/research/gsa1_rounds_plan.md section 5, G0): every src/module/*.cpp is compiled into the module
(gsa1_module.cpp, gsa1_feature.cpp and each feature's bind_<feature>.cpp, which registers itself with GSA1_FEATURE);
--test also builds and runs every tests/feat_<feature>_test.cpp (linked like core_test: the core and libsa1) and every
tests/feat_<feature>_binding_test.cpp (linked like binding_test: the module's objects and the mock Lua stack of
tests/mock_lua.hpp), each with --gdi GAME.gdi when one is given, and runs every tests/feat_<feature>_test.lua in
Garry's Mod's LuaJIT like the other Lua tests (tests/seam_test.lua: the addon's feature loading, menu pages, ConVar
helper and HasFeature). The features found are listed at the start.

Builds of this directory are serialised by an exclusive lock on build/.build.lock (another agent's or terminal's
build of g-sa1 waits for this one; --lock-timeout); libsa1's own lock is taken inside it, for the snapshot only.

Compiler: zig through Python (`py -3.12 -m ziglang`, the 0.16.0 libsa1 pins), C++17, static libc++.
libsa1 is linked statically from LIB/build/<target>/libsa1.a (SA1_STATIC). The archive and LIB/include/libsa1.h
are copied into build/deps/ under libsa1's own build lock (LIB/build/.build.lock), so a concurrent libsa1 build
never hands us a half-written archive. Outputs: build/<target>/gmcl_gsa1_win64.dll | gmcl_gsa1_linux64.dll,
core_test, binding_test, collision_test, pad_test, map_test (.exe), build/BUILD_INFO.txt (snapshot hashes,
gmod-module-base commit, exports / imports).
"""
import argparse
import concurrent.futures
import glob
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
# libsa1 (find_libsa1: --libsa1 / LIBSA1_ROOT / ../libsa1 / ../LibSA1/libsa1); set again by main() from the arguments
LIB = os.path.normpath(os.path.join(ROOT, "..", "libsa1"))
GMB = os.path.join(ROOT, "third_party", "gmod-module-base")
ZIG_PIN = "0.16.0"

TARGETS = {
    # key: (zig triple, module file name, test exe name, runnable here)
    "x86_64-windows": ("x86_64-windows-gnu", "gmcl_gsa1_win64.dll", ".exe", os.name == "nt"),
    "x86_64-linux": ("x86_64-linux-gnu.2.17", "gmcl_gsa1_linux64.dll", "", sys.platform.startswith("linux")),
}
CORE = sorted(glob.glob(os.path.join(ROOT, "src", "core", "*.cpp")))
MODULE = os.path.join(ROOT, "src", "module", "gsa1_module.cpp")
# the module's sources: gsa1_module.cpp, the feature registry gsa1_feature.cpp, every feature's bind_<feature>.cpp
MODULES = sorted(glob.glob(os.path.join(ROOT, "src", "module", "*.cpp")))
TEST = os.path.join(ROOT, "tests", "core_test.cpp")
BINDING = os.path.join(ROOT, "tests", "binding_test.cpp")
COLLISION = os.path.join(ROOT, "tests", "collision_test.cpp")
PADTEST = os.path.join(ROOT, "tests", "pad_test.cpp")
MAPTEST = os.path.join(ROOT, "tests", "map_test.cpp")
LUAHOST = os.path.join(ROOT, "tests", "lua_host.c")
# the features' tests (G0): tests/feat_<feature>_test.cpp (core), tests/feat_<feature>_binding_test.cpp (module + mock)
FEAT_BINDING_TESTS = sorted(glob.glob(os.path.join(ROOT, "tests", "feat_*_binding_test.cpp")))
FEAT_TESTS = sorted(t for t in glob.glob(os.path.join(ROOT, "tests", "feat_*_test.cpp")) if t not in FEAT_BINDING_TESTS)
LUA_TESTS = ["log_test.lua", "warm_test.lua", "frame_test.lua", "seam_test.lua", "texture_alpha_test.lua", "weapon_test.lua",
             "render_test.lua"] + sorted(
    os.path.basename(t) for t in glob.glob(os.path.join(ROOT, "tests", "feat_*_test.lua")))
# Garry's Mod's LuaJIT for the Lua tests: GMOD_LUA_SHARED, else <GarrysMod>/bin/win64/lua_shared.dll of the install
# find_garrysmod() finds (set by main())
GMOD_LUA_SHARED = os.environ.get("GMOD_LUA_SHARED", "")
CXXFLAGS = ["-std=c++17", "-O2", "-g", "-Wall", "-Wextra", "-Wno-unused-parameter", "-fno-strict-aliasing"]


def find_libsa1(explicit=""):
    """libsa1's folder: --libsa1, else LIBSA1_ROOT, else ../libsa1 (this project's layout) or ../LibSA1/libsa1 (the
    LibSA1 repository cloned next to G-SA1), the first that has include/libsa1.h"""
    for d in (explicit, os.environ.get("LIBSA1_ROOT", "")):
        if d:
            return os.path.normpath(os.path.abspath(d))
    for d in (os.path.join(ROOT, "..", "libsa1"), os.path.join(ROOT, "..", "LibSA1", "libsa1")):
        if os.path.exists(os.path.join(d, "include", "libsa1.h")):
            return os.path.normpath(d)
    return os.path.normpath(os.path.join(ROOT, "..", "libsa1"))


def find_garrysmod(explicit=""):
    """Garry's Mod's garrysmod folder, which the tests read (read-only): --gmod, else GARRYSMOD_DIR, else the first Steam
    library with steamapps/common/GarrysMod/garrysmod (STEAM_DIR, Steam's own registry entry, Steam's default install
    places; each with the libraries listed in its steamapps/libraryfolders.vdf); "" when there is none.
    tests/gmod_paths.hpp searches the same way for test programs run by hand."""
    for d in (explicit, os.environ.get("GARRYSMOD_DIR", "")):
        if d:
            return os.path.normpath(d)
    steams = [os.environ.get("STEAM_DIR", "")]
    if os.name == "nt":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as k:
                steams.append(winreg.QueryValueEx(k, "SteamPath")[0])
        except OSError:
            pass
        steams += [r"C:\Program Files (x86)\Steam", r"C:\Program Files\Steam"]
    else:
        home = os.path.expanduser("~")
        steams += [os.path.join(home, ".steam", "steam"), os.path.join(home, ".local", "share", "Steam")]
    for steam in (s for s in steams if s):
        libs = [steam]
        try:
            with open(os.path.join(steam, "steamapps", "libraryfolders.vdf"), encoding="utf-8", errors="replace") as f:
                libs += [m.replace("\\\\", "\\") for m in re.findall(r'"path"\s+"((?:[^"\\]|\\.)*)"', f.read())]
        except OSError:
            pass
        for lib in libs:
            gm = os.path.join(lib, "steamapps", "common", "GarrysMod", "garrysmod")
            if os.path.isdir(gm):
                return os.path.normpath(gm)
    return ""


def zig(*args):
    return [sys.executable, "-m", "ziglang"] + list(args)


def run(cmd, cwd=ROOT):
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    return p.returncode, p.stdout


def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---- libsa1 snapshot under its build lock -------------------------------------------------------------------
class LibLock:
    """LIB/build.py serialises its builds with an exclusive lock on byte 0 of LIB/build/.build.lock; this build.py
    serialises its own the same way on build/.build.lock (GsaLock)."""

    def __init__(self, timeout, path=None, what="libsa1's build lock (a libsa1 build is running)"):
        self.timeout = timeout
        self.f = None
        self.path = path or os.path.join(LIB, "build", ".build.lock")
        self.what = what

    def __enter__(self):
        path = self.path
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.f = open(path, "a+")
        t0 = time.time()
        said = False
        while True:
            try:
                if os.name == "nt":
                    import msvcrt
                    self.f.seek(0)
                    msvcrt.locking(self.f.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(self.f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                return self
            except OSError:
                if time.time() - t0 > self.timeout:
                    self.f.close()
                    self.f = None
                    raise TimeoutError("%s is held" % self.what)
                if not said:
                    print("waiting for %s ..." % self.what, flush=True)
                    said = True
                time.sleep(2.0)

    def __exit__(self, *exc):
        if self.f:
            try:
                if os.name == "nt":
                    import msvcrt
                    self.f.seek(0)
                    msvcrt.locking(self.f.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(self.f.fileno(), fcntl.LOCK_UN)
            finally:
                self.f.close()


def GsaLock(timeout):
    return LibLock(timeout, os.path.join(ROOT, "build", ".build.lock"),
                   "G-SA1's build lock (another build of g-sa1 is running)")


def lib_newest_source():
    """(mtime, path) of libsa1's newest input: headers, sources, the lowered game code, the generated stubs."""
    best = (0.0, "")
    roots = [(os.path.join(LIB, "include"), (".h",)), (os.path.join(LIB, "src"), (".c", ".h")),
             (os.path.join(LIB, "build", "pclower", "ga64"), (".c", ".h")), (os.path.join(LIB, "build", "gen"), (".c", ".h"))]
    for root, exts in roots:
        for dirpath, _dirs, files in os.walk(root):
            for n in files:
                if n.endswith(exts):
                    p = os.path.join(dirpath, n)
                    t = os.path.getmtime(p)
                    if t > best[0]:
                        best = (t, p)
    return best


def check_fresh(keys, allow_stale):
    """Every target's archive must be newer than libsa1's newest input (2 s of file-time slack)."""
    newest, src = lib_newest_source()
    lines, stale = [], []
    for k in keys:
        a = os.path.join(LIB, "build", k, "libsa1.a")
        if not os.path.exists(a):
            continue
        t = os.path.getmtime(a)
        ok = t + 2.0 >= newest
        lines.append("%s/libsa1.a %s (archive %s, newest libsa1 input %s: %s)" % (
            k, "fresh" if ok else "STALE", time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)),
            time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(newest)), os.path.relpath(src, LIB)))
        if not ok:
            stale.append(k)
    for l in lines:
        print("libsa1 freshness: " + l)
    if stale and not allow_stale:
        raise RuntimeError("libsa1.a is older than libsa1's sources for %s: rebuild libsa1 (py -3.12 build.py "
                           "--lib-build, or LIB: py -3.12 build.py --target <target>) or pass --allow-stale"
                           % ", ".join(stale))
    return lines


def lib_build(keys):
    for k in keys:
        cmd = [sys.executable, os.path.join(LIB, "build.py"), "--target", k]
        print("libsa1: %s" % " ".join(cmd), flush=True)
        r = subprocess.run(cmd, cwd=LIB, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
        tail = r.stdout.strip().splitlines()[-6:]
        print("\n".join("  " + l for l in tail))
        if r.returncode != 0:
            raise RuntimeError("the libsa1 build for %s failed (exit %d)" % (k, r.returncode))


def snapshot(keys, timeout, allow_stale=False):
    deps = os.path.join(ROOT, "build", "deps")
    os.makedirs(os.path.join(deps, "include"), exist_ok=True)
    lines = []
    with LibLock(timeout):
        fresh = check_fresh(keys, allow_stale)
        for h in ("libsa1.h", "libsa1_audio.h"):
            shutil.copy2(os.path.join(LIB, "include", h), os.path.join(deps, "include", h))
        for k in keys:
            src = os.path.join(LIB, "build", k, "libsa1.a")
            if not os.path.exists(src):
                raise FileNotFoundError("%s is missing: build libsa1 first (LIB: py -3.12 build.py)" % src)
            os.makedirs(os.path.join(deps, k), exist_ok=True)
            shutil.copy2(src, os.path.join(deps, k, "libsa1.a"))
    for h in ("libsa1.h", "libsa1_audio.h"):
        lines.append("%s  sha1 %s" % (h, sha1(os.path.join(deps, "include", h))))
    for k in keys:
        a = os.path.join(deps, k, "libsa1.a")
        lines.append("%s/libsa1.a  sha1 %s  %d bytes  (LIB build of %s)" % (
            k, sha1(a), os.path.getsize(a), time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getmtime(a)))))
    lines += ["freshness: " + l for l in fresh]
    with open(os.path.join(deps, "SNAPSHOT.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("libsa1 snapshot taken %s\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
        f.write("\n".join(lines) + "\n")
    print("libsa1 snapshot: " + "; ".join(lines))


def gmb_commit():
    head = os.path.join(GMB, ".git", "HEAD")
    try:
        ref = open(head).read().strip()
        if ref.startswith("ref: "):
            name = ref[5:]
            p = os.path.join(GMB, ".git", name)
            if os.path.exists(p):
                return open(p).read().strip(), name
            packed = os.path.join(GMB, ".git", "packed-refs")
            for line in open(packed):
                if line.strip().endswith(name):
                    return line.split()[0], name
        return ref, "detached"
    except OSError:
        return "unknown", "unknown"


# ---- binary inspection (exports / imports) ------------------------------------------------------------------
def pe_info(path):
    data = open(path, "rb").read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    optsz = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    dd = opt + (112 if magic == 0x20B else 96)
    secs = []
    for i in range(nsec):
        s = pe + 24 + optsz + 40 * i
        vsz, va, rawsz, raw = struct.unpack_from("<IIII", data, s + 8)   # VirtualSize, VirtualAddress, raw size, raw ptr
        secs.append((va, max(vsz, rawsz), raw))

    def off(rva):
        for va, sz, raw in secs:
            if va <= rva < va + sz:
                return rva - va + raw
        raise ValueError("rva")

    def cstr(o):
        return data[o:data.index(b"\0", o)].decode("ascii", "replace")

    exports, imports = [], []
    erva = struct.unpack_from("<I", data, dd)[0]
    if erva:
        e = off(erva)
        nnames, names = struct.unpack_from("<I", data, e + 24)[0], struct.unpack_from("<I", data, e + 32)[0]
        for i in range(nnames):
            exports.append(cstr(off(struct.unpack_from("<I", data, off(names) + 4 * i)[0])))
    irva = struct.unpack_from("<I", data, dd + 8)[0]
    if irva:
        o = off(irva)
        while True:
            name = struct.unpack_from("<I", data, o + 12)[0]
            if name == 0:
                break
            imports.append(cstr(off(name)))
            o += 20
    return sorted(exports), sorted(set(imports))


def elf_info(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF" or data[4] != 2:
        raise ValueError("not ELF64")
    shoff = struct.unpack_from("<Q", data, 0x28)[0]
    shentsize, shnum = struct.unpack_from("<HH", data, 0x3A)
    secs = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize) for i in range(shnum)]
    exports, needed_versions = [], set()
    for (name, typ, flags, addr, offset, size, link, info, align, entsize) in secs:
        if typ == 11:  # SHT_DYNSYM
            stro = secs[link][4]
            for i in range(size // 24):
                st_name, st_info, st_other, st_shndx, st_value, st_size = struct.unpack_from("<IBBHQQ", data, offset + 24 * i)
                bind = st_info >> 4
                if st_shndx != 0 and bind in (1, 2) and st_name:
                    exports.append(data[stro + st_name:data.index(b"\0", stro + st_name)].decode())
        if typ == 0x6FFFFFFE:  # SHT_GNU_verneed
            stro = secs[link][4]
            o = offset
            for _ in range(info):
                vn_version, vn_cnt, vn_file, vn_aux, vn_next = struct.unpack_from("<HHIII", data, o)
                a = o + vn_aux
                for _ in range(vn_cnt):
                    vna_hash, vna_flags, vna_other, vna_name, vna_next = struct.unpack_from("<IHHII", data, a)
                    needed_versions.add(data[stro + vna_name:data.index(b"\0", stro + vna_name)].decode())
                    a += vna_next
                o += vn_next
    return sorted(set(exports)), sorted(needed_versions)


# ---- build ------------------------------------------------------------------------------------------------
def build_target(key, args, info):
    triple, modname, exe, runnable = TARGETS[key]
    windows = "windows" in triple
    out = os.path.join(ROOT, "build", key)
    obj = os.path.join(out, "obj")
    os.makedirs(obj, exist_ok=True)
    deps_inc = os.path.join(ROOT, "build", "deps", "include")
    lib = os.path.join(ROOT, "build", "deps", key, "libsa1.a")
    if not os.path.exists(lib):
        print("[%s] no libsa1 snapshot (%s): run without --no-snapshot" % (key, lib))
        return False
    base = ["-target", triple] + CXXFLAGS + ["-DSA1_STATIC", "-I" + deps_inc, "-I" + os.path.join(ROOT, "src", "core")]
    if not windows:
        base += ["-fPIC", "-fvisibility=hidden"]
    headers = (glob.glob(os.path.join(ROOT, "src", "core", "*.hpp")) + glob.glob(os.path.join(deps_inc, "*.h")) +
               glob.glob(os.path.join(ROOT, "src", "module", "*.hpp")) + glob.glob(os.path.join(ROOT, "tests", "*.hpp")))
    hdr_time = max(os.path.getmtime(h) for h in headers)
    sources = CORE + MODULES + [TEST, BINDING, COLLISION, PADTEST, MAPTEST] + FEAT_TESTS + FEAT_BINDING_TESTS
    seen = {}
    for s in sources:
        b = os.path.splitext(os.path.basename(s))[0]
        if b in seen:
            # one object directory: a feature's files are bind_<feature>.cpp (module) and <feature>.cpp (core)
            print("[%s] FAILED: %s and %s would share the object %s.o (rename one)" % (
                key, os.path.relpath(seen[b], ROOT), os.path.relpath(s, ROOT), b))
            return False
        seen[b] = s
    lua_side = MODULES + [BINDING] + FEAT_BINDING_TESTS    # the sources that include gmod-module-base
    jobs = []
    for s in sources:
        o = os.path.join(obj, os.path.splitext(os.path.basename(s))[0] + ".o")
        flags = list(base)
        if s in lua_side:
            flags += ["-I" + os.path.join(GMB, "include")]
        if s in MODULES and windows:
            # gmod-module-base picks the Win64 lua_State layout with MSVC's _M_X64; the module static_asserts the
            # resulting offset (120) (zig's clang defines it as 100 for x86_64-windows-gnu as well: no conflict)
            flags += ["-D_M_X64=100"]
        if s == MODULE:
            # gsa1.Status().build (the session log's header): when the module was compiled, against which libsa1
            flags += ['-DGSA1_BUILD_INFO="%s libsa1 %s"' % (time.strftime("%Y-%m-%d %H:%M"), sha1(lib)[:12])]
        need = args.clean or not os.path.exists(o) or os.path.getmtime(o) < max(os.path.getmtime(s), hdr_time)
        if s in lua_side:
            gm_h = glob.glob(os.path.join(GMB, "include", "GarrysMod", "Lua", "*.h"))
            need = need or (os.path.exists(o) and os.path.getmtime(o) < max(os.path.getmtime(h) for h in gm_h))
        if need:
            jobs.append((s, o, zig("c++", *flags, "-c", s, "-o", o)))
    ok = True
    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        for (s, o, cmd), (rc, text) in zip(jobs, ex.map(lambda j: run(j[2]), jobs)):
            if text.strip():
                print(text.rstrip())
            if rc != 0:
                print("[%s] FAILED: %s" % (key, os.path.relpath(s, ROOT)))
                ok = False
    if not ok:
        return False
    print("[%s] %d object(s) compiled" % (key, len(jobs)))
    core_objs = [os.path.join(obj, os.path.splitext(os.path.basename(s))[0] + ".o") for s in CORE]
    mod_objs = [os.path.join(obj, os.path.splitext(os.path.basename(s))[0] + ".o") for s in MODULES]
    test_obj = os.path.join(obj, "core_test.o")
    binding_obj = os.path.join(obj, "binding_test.o")
    collision_obj = os.path.join(obj, "collision_test.o")
    pad_obj = os.path.join(obj, "pad_test.o")
    map_obj = os.path.join(obj, "map_test.o")
    module = os.path.join(out, modname)
    test = os.path.join(out, "core_test" + exe)
    binding = os.path.join(out, "binding_test" + exe)
    collision = os.path.join(out, "collision_test" + exe)
    pad = os.path.join(out, "pad_test" + exe)
    maptest = os.path.join(out, "map_test" + exe)
    if windows:
        # only gmod13_open / gmod13_close carry dllexport, so lld exports nothing else (no auto-export);
        # the export table is checked below
        link_mod = zig("c++", "-target", triple, "-shared", "-o", module, *mod_objs, *core_objs, lib, "-lcomdlg32")
        link_test = zig("c++", "-target", triple, "-o", test, test_obj, *core_objs, lib)
        link_binding = zig("c++", "-target", triple, "-o", binding, binding_obj, *mod_objs, *core_objs, lib, "-lcomdlg32")
        link_collision = zig("c++", "-target", triple, "-o", collision, collision_obj, *core_objs, lib)
        link_pad = zig("c++", "-target", triple, "-o", pad, pad_obj, *core_objs, lib)
        link_map = zig("c++", "-target", triple, "-o", maptest, map_obj, *core_objs, lib)
    else:
        vs = os.path.join(obj, "exports.map")
        with open(vs, "w", newline="\n") as f:
            f.write("{\n  global: gmod13_open; gmod13_close;\n  local: *;\n};\n")
        link_mod = zig("c++", "-target", triple, "-shared", "-o", module, *mod_objs, *core_objs, lib,
                       "-lm", "-lpthread", "-ldl", "-Wl,--version-script=" + vs, "-Wl,--no-undefined",
                       "-Wl,--strip-debug")
        link_test = zig("c++", "-target", triple, "-o", test, test_obj, *core_objs, lib, "-lm", "-lpthread", "-ldl")
        link_binding = zig("c++", "-target", triple, "-o", binding, binding_obj, *mod_objs, *core_objs, lib, "-lm",
                           "-lpthread", "-ldl")
        link_collision = zig("c++", "-target", triple, "-o", collision, collision_obj, *core_objs, lib, "-lm",
                             "-lpthread", "-ldl")
        link_pad = zig("c++", "-target", triple, "-o", pad, pad_obj, *core_objs, lib, "-lm", "-lpthread", "-ldl")
        link_map = zig("c++", "-target", triple, "-o", maptest, map_obj, *core_objs, lib, "-lm", "-lpthread", "-ldl")
    links = [("module", link_mod), ("core_test", link_test), ("binding_test", link_binding),
             ("collision_test", link_collision), ("pad_test", link_pad), ("map_test", link_map)]
    # the features' tests: feat_*_test like core_test, feat_*_binding_test like binding_test
    sys_libs = ["-lcomdlg32"] if windows else ["-lm", "-lpthread", "-ldl"]
    for s in FEAT_TESTS + FEAT_BINDING_TESTS:
        name = os.path.splitext(os.path.basename(s))[0]
        objs = [os.path.join(obj, name + ".o")] + (mod_objs if s in FEAT_BINDING_TESTS else []) + core_objs
        links.append((name, zig("c++", "-target", triple, "-o", os.path.join(out, name + exe), *objs, lib, *sys_libs)))
    for what, cmd in links:
        rc, text = run(cmd)
        lines = text.strip().splitlines()
        if rc != 0 or len(lines) <= 40:
            print("\n".join(lines[-200:]))
        else:
            # zig compiles its libc++ once per target and cache, with thousands of header warnings
            print("[%s] (%d lines of linker / runtime-library output hidden)" % (key, len(lines)))
        if rc != 0:
            print("[%s] LINK FAILED: %s" % (key, what))
            return False
    # what the module exports and imports
    if windows:
        exports, imports = pe_info(module)
        info.append("%s: %s, %d bytes, sha1 %s" % (key, modname, os.path.getsize(module), sha1(module)))
        info.append("  exports: %s" % ", ".join(exports))
        info.append("  imports: %s" % ", ".join(imports))
        print("[%s] %s: exports %s; imports %s" % (key, modname, exports, ", ".join(imports)))
    else:
        exports, versions = elf_info(module)
        info.append("%s: %s, %d bytes, sha1 %s" % (key, modname, os.path.getsize(module), sha1(module)))
        info.append("  exports: %s" % ", ".join(exports))
        info.append("  needs: %s" % ", ".join(versions))
        print("[%s] %s: exports %s; needs %s" % (key, modname, exports, ", ".join(versions)))
    if exports != ["gmod13_close", "gmod13_open"]:
        print("[%s] FAILED: the module must export exactly gmod13_open and gmod13_close" % key)
        return False
    if windows:
        # the Lua test host (Garry's Mod's own LuaJIT, loaded at run time)
        host = os.path.join(out, "lua_host.exe")
        if args.clean or not os.path.exists(host) or os.path.getmtime(host) < os.path.getmtime(LUAHOST):
            rc, text = run(zig("cc", "-target", triple, "-O2", LUAHOST, "-o", host))
            if rc != 0:
                print(text.rstrip())
                print("[%s] LINK FAILED: lua_host" % key)
                return False
    print("[%s] built %s, %s, %s, %s, %s, %s and %d feature test(s)" % (
        key, os.path.relpath(module, ROOT), os.path.relpath(test, ROOT), os.path.relpath(binding, ROOT),
        os.path.relpath(collision, ROOT), os.path.relpath(pad, ROOT), os.path.relpath(maptest, ROOT),
        len(FEAT_TESTS) + len(FEAT_BINDING_TESTS)))
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target", default="all", choices=sorted(TARGETS) + ["all"])
    ap.add_argument("--no-snapshot", action="store_true", help="reuse build/deps")
    ap.add_argument("--lib-build", action="store_true", help="build libsa1 for the targets first (LIB build.py)")
    ap.add_argument("--allow-stale", action="store_true", help="snapshot a libsa1.a older than libsa1's sources")
    ap.add_argument("--lock-timeout", type=float, default=1800.0)
    ap.add_argument("--clean", action="store_true")
    ap.add_argument("--test", action="store_true",
                    help="run pad_test, core_test, binding_test, collision_test and map_test (runnable targets)")
    ap.add_argument("--gdi", default=os.environ.get("SA1_TEST_GDI", ""))
    ap.add_argument("--libsa1", default="", help="libsa1's folder (default: LIBSA1_ROOT, ../libsa1 or "
                    "../LibSA1/libsa1)")
    ap.add_argument("--gmod", default="", help="Garry's Mod's garrysmod folder for the tests (default: GARRYSMOD_DIR "
                    "or found through Steam's library list)")
    ap.add_argument("--bsp", default="")
    ap.add_argument("--maps", default="", help="map_test: a directory with more maps (static prop checks)")
    ap.add_argument("--fuzz", type=int, default=60)
    ap.add_argument("--seconds", type=float, default=6.0)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    global LIB, GMOD_LUA_SHARED
    LIB = find_libsa1(args.libsa1)
    gm = find_garrysmod(args.gmod)
    if gm:
        os.environ["GARRYSMOD_DIR"] = gm          # the tests' default Garry's Mod (tests/gmod_paths.hpp)
    if not GMOD_LUA_SHARED and gm:
        GMOD_LUA_SHARED = os.path.join(os.path.dirname(gm), "bin", "win64", "lua_shared.dll")
    if GMOD_LUA_SHARED:
        os.environ["GMOD_LUA_SHARED"] = GMOD_LUA_SHARED   # lua_host loads this one
    keys = sorted(TARGETS) if args.target == "all" else [args.target]
    try:
        with GsaLock(args.lock_timeout):
            return build_and_test(args, keys)
    except TimeoutError as e:
        print("FAILED: %s" % e)
        return 1


def build_and_test(args, keys):
    rel = lambda ps: ", ".join(os.path.relpath(p, ROOT) for p in ps) or "none"
    print("features: module sources %s; feature tests %s; Lua tests %s" % (
        rel(MODULES), rel(FEAT_TESTS + FEAT_BINDING_TESTS), ", ".join(LUA_TESTS)))
    rc, ver = run(zig("version"))
    if ver.strip() != ZIG_PIN:
        print("warning: zig %s (libsa1 is built with %s)" % (ver.strip(), ZIG_PIN))
    if args.clean:
        for k in keys:
            shutil.rmtree(os.path.join(ROOT, "build", k), ignore_errors=True)
    try:
        if args.lib_build:
            lib_build(keys)
        if not args.no_snapshot:
            snapshot(keys, args.lock_timeout, args.allow_stale)
    except (RuntimeError, TimeoutError, FileNotFoundError) as e:
        print("FAILED: %s" % e)
        return 1
    commit, branch = gmb_commit()
    info = ["G-SA1 build %s" % time.strftime("%Y-%m-%d %H:%M:%S"),
            "gmod-module-base %s (%s), https://github.com/Facepunch/gmod-module-base" % (commit, branch),
            "zig %s" % ver.strip()]
    snap = os.path.join(ROOT, "build", "deps", "SNAPSHOT.txt")
    if os.path.exists(snap):
        info += [l.rstrip() for l in open(snap, encoding="utf-8")]
    ok = True
    for k in keys:
        ok = build_target(k, args, info) and ok
    with open(os.path.join(ROOT, "build", "BUILD_INFO.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(info) + "\n")
    if not ok:
        return 1
    if args.test:
        for k in keys:
            triple, modname, exe, runnable = TARGETS[k]
            if not runnable:
                print("[%s] the tests are built, not run (not this platform)" % k)
                continue
            extra = (["--gdi", args.gdi] if args.gdi else []) + (["--bsp", args.bsp] if args.bsp else [])
            big = os.path.join(args.maps, "gm_freespace_13.bsp") if args.maps else ""
            timing = ["--timing-bsp", big] if big and os.path.exists(big) else []
            cmds = [[os.path.join(ROOT, "build", k, "pad_test" + exe)],
                    [os.path.join(ROOT, "build", k, "core_test" + exe), "--fuzz", str(args.fuzz), "--seconds",
                     str(args.seconds)] + extra + (["--verbose"] if args.verbose else []),
                    [os.path.join(ROOT, "build", k, "binding_test" + exe)] + extra + timing,
                    [os.path.join(ROOT, "build", k, "collision_test" + exe)] + extra,
                    [os.path.join(ROOT, "build", k, "map_test" + exe)] + (["--gdi", args.gdi] if args.gdi else []) +
                    (["--maps", args.maps] if args.maps else [])]
            # the features' tests (G0), each with the disc when there is one
            for s in FEAT_TESTS + FEAT_BINDING_TESTS:
                cmds.append([os.path.join(ROOT, "build", k, os.path.splitext(os.path.basename(s))[0] + exe)] +
                            (["--gdi", args.gdi] if args.gdi else []))
            host = os.path.join(ROOT, "build", k, "lua_host" + exe)
            if "windows" in triple and GMOD_LUA_SHARED and os.path.exists(GMOD_LUA_SHARED):
                tests_dir, addon_lua = os.path.join(ROOT, "tests"), os.path.join(ROOT, "addon", "lua")
                census = os.path.join(ROOT, "build", k, "material_census.txt")
                for lt in LUA_TESTS:
                    cmds.append([host, os.path.join(tests_dir, lt), tests_dir, addon_lua] +
                                ([census] if lt == "warm_test.lua" else []))
            elif "windows" in triple:
                print("[%s] the Lua tests are skipped: Garry's Mod's lua_shared.dll is not at %s (set GMOD_LUA_SHARED "
                      "or GARRYSMOD_DIR, or pass --gmod)" % (k, GMOD_LUA_SHARED or "(Garry's Mod not found)"))
            failed = []
            for cmd in cmds:
                print("[%s] %s" % (k, " ".join('"%s"' % c if " " in c else c for c in cmd)), flush=True)
                r = subprocess.run(cmd)
                if r.returncode != 0:
                    ok = False
                    failed.append(os.path.basename(cmd[1] if cmd[0] == host else cmd[0]))
            print("[%s] %d test program(s) run, %s" % (k, len(cmds), ("FAILED: " + ", ".join(failed)) if failed
                                                       else "all passed"), flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
