#!/usr/bin/env python3
"""Downloads the current OSRS game cache for extract.py.

  python tools/osrs_extract/fetch_cache.py [--out tools/osrs_extract/cache] [--source osrs.world|github]

osrs.world (default): the same cache files the map viewer at osrs.world
loads (main_file_cache.dat2 + .idx, about 250 MB), newest OSRS build first.
github: a shallow clone of github.com/abextm/osrs-cache (a flat cache kept
up to date with every game update; needs git).

The cache is Jagex's: keep it on your machine. tools/osrs_extract/cache/ is
git-ignored.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UA = {"User-Agent": "GielinorLegends-osrs_extract/1.0"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()


def download(url, path):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=600) as r, open(path, "wb") as f:
        total = int(r.headers.get("Content-Length", 0))
        done = 0
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            if total:
                sys.stdout.write("\r  %s %3d%%" % (os.path.basename(path), done * 100 // total))
                sys.stdout.flush()
    print()


def from_osrs_world(out):
    caches = json.loads(get("https://osrs.world/caches/caches.json"))
    osrs = [c for c in caches if c.get("game") == "oldschool" and c.get("environment", "live") == "live"]
    osrs.sort(key=lambda c: (c.get("revision", 0), c.get("timestamp", "")), reverse=True)
    if not osrs:
        sys.exit("osrs.world lists no OSRS cache")
    name = osrs[0]["name"]
    base = "https://osrs.world/caches/%s/" % name
    print("cache %s (revision %s)" % (name, osrs[0].get("revision")))
    os.makedirs(out, exist_ok=True)
    files = ["main_file_cache.dat2", "main_file_cache.idx255"] + ["main_file_cache.idx%d" % i for i in range(26)]
    for f in files:
        try:
            download(base + f, os.path.join(out, f))
        except Exception as e:     # missing indexes are fine
            if f in ("main_file_cache.dat2", "main_file_cache.idx255"):
                raise
            print("  %s: %s (skipped)" % (f, e))
            p = os.path.join(out, f)
            if os.path.exists(p):
                os.remove(p)
    try:
        download(base + "keys.json", os.path.join(out, "keys.json"))
    except Exception:
        pass
    with open(os.path.join(out, "REVISION"), "w") as fh:
        fh.write(str(osrs[0].get("revision", "")))


def from_github(out):
    if shutil.which("git") is None:
        sys.exit("git isn't installed; use --source osrs.world")
    if os.path.exists(os.path.join(out, ".git")):
        subprocess.check_call(["git", "-C", out, "pull", "--ff-only"])
    else:
        subprocess.check_call(["git", "clone", "--depth", "1", "https://github.com/abextm/osrs-cache.git", out])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(HERE, "cache"))
    ap.add_argument("--source", choices=["osrs.world", "github"], default="osrs.world")
    a = ap.parse_args()
    (from_github if a.source == "github" else from_osrs_world)(a.out)
    print("cache ready in %s" % a.out)


if __name__ == "__main__":
    main()
