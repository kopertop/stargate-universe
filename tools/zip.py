#!/usr/bin/env python3
"""Create the itch.io HTML5 zip using Python's stdlib zipfile.

Fallback for systems without the `zip` binary (e.g. minimal EC2, some CI runners).
Called by build.sh when `zip` is not on PATH.

Usage: python3 tools/zip.py <dist_dir> <zip_name> [item ...]
  <dist_dir>   — the dist/ directory containing the build output
  <zip_name>   — output filename (e.g. sgu-destiny-html5.zip)
  [item ...]   — files/dirs to include (relative to dist_dir), defaults to all

The zip is created with ZIP_DEFLATED compression. Files are stored with
paths relative to dist_dir so index.html is at the zip root.
"""
import os
import sys
import zipfile


def make_zip(dist_dir, zip_name, items=None):
    dist = os.path.abspath(dist_dir)
    zip_path = os.path.join(dist, zip_name)

    if os.path.exists(zip_path):
        os.remove(zip_path)

    if items is None:
        items = [f for f in os.listdir(dist) if f != zip_name]

    count = 0
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for item in items:
            path = os.path.join(dist, item)
            if os.path.isfile(path):
                zf.write(path, item)
                count += 1
            elif os.path.isdir(path):
                for root, _dirs, files in os.walk(path):
                    for f in files:
                        fp = os.path.join(root, f)
                        arcname = os.path.relpath(fp, dist)
                        zf.write(fp, arcname)
                        count += 1

    return zip_path, count


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <dist_dir> <zip_name> [item ...]", file=sys.stderr)
        sys.exit(1)

    dist_dir = sys.argv[1]
    zip_name = sys.argv[2]
    items = sys.argv[3:] if len(sys.argv) > 3 else None

    zip_path, count = make_zip(dist_dir, zip_name, items)
    size = os.path.getsize(zip_path)
    print(f"   {size}  {zip_path}  ({count} files)")