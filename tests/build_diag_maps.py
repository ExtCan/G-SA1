#!/usr/bin/env python3
"""Build (and run) tests/diag_maps.cpp: G-SA1 diagnostics on real maps (ramps at speed, tick cost, hangs), through the
0.5 map job (world brushes, displacements, static props; tests/gamefs.hpp reads the props' physics models from the game).

    py -3.12 tests/build_diag_maps.py [--run [--gdi FILE] [-- ARGS... MAP.bsp...]] [--no-snapshot]

Everything is written below build/diag_maps/ only. The sources it compiles with (src/core/bsp.*, util.*,
libsa1_internal_api.hpp) are copied into build/diag_maps/snap/ first, and libsa1 (LIB/build/x86_64-windows/libsa1.a,
LIB/include/*.h) is copied under libsa1's build lock (LIB/build/.build.lock), so concurrent edits / builds of either
project do not leave this test half-built. Compiler: zig c++ (py -3.12 -m ziglang), C++17, x86_64-windows-gnu.
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# libsa1: LIBSA1_ROOT, else ../libsa1 (this project's layout) or ../LibSA1/libsa1 (the LibSA1 repository next to G-SA1)
LIB = os.path.normpath(os.environ.get("LIBSA1_ROOT") or next(
    (d for d in (os.path.join(ROOT, "..", "libsa1"), os.path.join(ROOT, "..", "LibSA1", "libsa1"))
     if os.path.exists(os.path.join(d, "include", "libsa1.h"))), os.path.join(ROOT, "..", "libsa1")))
OUT = os.path.join(ROOT, "build", "diag_maps")
SNAP = os.path.join(OUT, "snap")
CORE = ["bsp.cpp", "bsp.hpp", "util.cpp", "util.hpp", "libsa1_internal_api.hpp", "phy.cpp", "phy.hpp", "shape.cpp",
        "shape.hpp", "mapjob.cpp", "mapjob.hpp", "prepare.cpp", "prepare.hpp",
        "surfaces.cpp", "surfaces.hpp"]   # (0.8's map job uses the surface types: without them this build failed)
TESTS_HPP = ["gamefs.hpp", "mapdrive.hpp"]


class LibLock:
    def __init__(self, timeout=1800.0):
        self.timeout = timeout
        self.f = None

    def __enter__(self):
        import msvcrt
        self.f = open(os.path.join(LIB, "build", ".build.lock"), "a+")
        t0 = time.time()
        while True:
            try:
                self.f.seek(0)
                msvcrt.locking(self.f.fileno(), msvcrt.LK_NBLCK, 1)
                return self
            except OSError:
                if time.time() - t0 > self.timeout:
                    raise TimeoutError("libsa1's build lock is held")
                time.sleep(2.0)

    def __exit__(self, *exc):
        import msvcrt
        try:
            self.f.seek(0)
            msvcrt.locking(self.f.fileno(), msvcrt.LK_UNLCK, 1)
        finally:
            self.f.close()


def snapshot():
    if os.path.isdir(SNAP):
        shutil.rmtree(SNAP)
    os.makedirs(os.path.join(SNAP, "core"))
    os.makedirs(os.path.join(SNAP, "include"))
    for n in CORE:
        shutil.copy2(os.path.join(ROOT, "src", "core", n), os.path.join(SNAP, "core", n))
    for n in TESTS_HPP:
        shutil.copy2(os.path.join(ROOT, "tests", n), os.path.join(SNAP, "core", n))
    with LibLock():
        shutil.copy2(os.path.join(LIB, "build", "x86_64-windows", "libsa1.a"), os.path.join(SNAP, "libsa1.a"))
        for h in glob.glob(os.path.join(LIB, "include", "*.h")):
            shutil.copy2(h, os.path.join(SNAP, "include", os.path.basename(h)))
    a = os.path.join(SNAP, "libsa1.a")
    print("snapshot: libsa1.a %d bytes (LIB build of %s); core sources of %s" % (
        os.path.getsize(a), time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getmtime(a))),
        time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(max(os.path.getmtime(os.path.join(SNAP, "core", n))
                                                              for n in CORE)))))


def build():
    exe = os.path.join(OUT, "diag_maps.exe")
    srcs = [os.path.join(ROOT, "tests", "diag_maps.cpp")] + [os.path.join(SNAP, "core", n) for n in CORE
                                                             if n.endswith(".cpp")]
    cmd = [sys.executable, "-m", "ziglang", "c++", "-target", "x86_64-windows-gnu", "-std=c++17", "-O2", "-g", "-Wall",
           "-Wextra", "-Wno-unused-parameter", "-fno-strict-aliasing", "-DSA1_STATIC",
           "-I" + os.path.join(SNAP, "core"), "-I" + os.path.join(SNAP, "include"), *srcs,
           os.path.join(SNAP, "libsa1.a"), "-lpsapi", "-o", exe]
    r = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    if r.returncode != 0 or len(lines) <= 40:
        print("\n".join(lines[-80:]))
    if r.returncode != 0:
        raise SystemExit("FAILED")
    print("built %s" % exe)
    return exe


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gdi", default=os.environ.get("SA1_TEST_GDI", ""))
    ap.add_argument("--run", action="store_true")
    ap.add_argument("--no-snapshot", action="store_true")
    ap.add_argument("rest", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if not a.no_snapshot:
        snapshot()
    exe = build()
    if a.run:
        rest = [x for x in a.rest if x != "--"]
        r = subprocess.run([exe, "--gdi", a.gdi] + rest)
        sys.exit(r.returncode)


main()
