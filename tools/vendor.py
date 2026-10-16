#!/usr/bin/env python3
"""Vendor Three.js addons and assets for the itch.io build.

Data-driven replacement for the inline heredocs in build.sh.
Reads tools/assets.json for the asset manifest and resolves the
Three.js addon import graph automatically.

Usage: python3 tools/vendor.py <src_dir> <dist_dir> <three_version>

This is the extracted, testable version of the build logic that was
previously inline in build.sh as fragile Python heredocs.
"""
import re
import sys
import os
import subprocess
import pathlib
import json


def vendor_addons(src_dir, out_dir, cdn_base):
    """Download Three.js addon files by resolving the import graph from src/."""
    src = pathlib.Path(src_dir)
    out = pathlib.Path(out_dir)
    cdn = cdn_base.rstrip('/')

    seeds = set()
    for f in src.glob('*.js'):
        for m in re.finditer(r"""['"]three/addons/([^'"]+)['"]""", f.read_text()):
            seeds.add(m.group(1))

    todo, done = list(seeds), set()
    while todo:
        rel = todo.pop()
        if rel in done:
            continue
        done.add(rel)
        dst = pathlib.Path(out, rel)
        dst.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['curl', '-fsSL', f'{cdn}/{rel}', '-o', str(dst)], check=True)
        for m in re.finditer(r"""from\s+['"](\.{1,2}/[^'"]+)['"]""", dst.read_text()):
            todo.append(os.path.normpath(os.path.join(os.path.dirname(rel), m.group(1))))

    return sorted(done)


def rewrite_index(src_html, dst_html):
    """Rewrite index.html: CDN import map → local vendor paths, inject asset root."""
    h = pathlib.Path(src_html).read_text()
    h = h.replace(
        '"three": "https://cdn.jsdelivr.net/npm/three@0.180.0/build/three.module.js"',
        '"three": "./vendor/three/build/three.module.js"'
    )
    h = h.replace(
        '"three/addons/": "https://cdn.jsdelivr.net/npm/three@0.180.0/examples/jsm/"',
        '"three/addons/": "./vendor/three/examples/jsm/"'
    )
    h = h.replace(
        '<script type="module" src="./src/main.js"></script>',
        '<script>window.__ASSET_ROOT = "./assets/";</script>\n<script type="module" src="./src/main.js"></script>'
    )
    assert 'cdn.jsdelivr' not in h, 'CDN reference left in index.html'
    pathlib.Path(dst_html).write_text(h)


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <src_dir> <dist_dir> <three_version>", file=sys.stderr)
        sys.exit(1)

    here = pathlib.Path(__file__).resolve().parent.parent
    src_dir = sys.argv[1]
    dist_dir = sys.argv[2]
    three_ver = sys.argv[3]
    cdn = f"https://cdn.jsdelivr.net/npm/three@{three_ver}"

    # Vendor Three.js core
    build_dir = pathlib.Path(dist_dir, 'vendor/three/build')
    build_dir.mkdir(parents=True, exist_ok=True)
    for fname in ('three.module.js', 'three.core.js'):
        subprocess.run(
            ['curl', '-fsSL', f'{cdn}/build/{fname}', '-o', str(build_dir / fname)],
            check=True
        )

    # Vendor addons by resolving import graph
    addons_dir = pathlib.Path(dist_dir, 'vendor/three/examples/jsm')
    addons = vendor_addons(src_dir, addons_dir, f"{cdn}/examples/jsm")
    print(f"   vendored {len(addons)} addon files: {addons}")

    # Rewrite index.html
    rewrite_index(
        str(here / 'index.html'),
        str(pathlib.Path(dist_dir, 'index.html'))
    )
    print(f"   rewrote index.html → {dist_dir}/index.html")


if __name__ == '__main__':
    main()