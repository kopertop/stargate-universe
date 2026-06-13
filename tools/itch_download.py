#!/usr/bin/env python3
"""Download free itch.io uploads (e.g. Quaternius packs) from the CLI.

Walks itch's free-download flow: game page -> csrf token -> /download_url ->
tokened download page -> /file/<upload_id> -> signed CDN URL -> fetch.

Usage: python3 tools/itch_download.py <itch game url> <output dir>
"""
import http.cookiejar
import json
import re
import sys
import urllib.parse
import urllib.request


def main() -> None:
	base = sys.argv[1].rstrip("/")
	out_dir = sys.argv[2]
	cj = http.cookiejar.CookieJar()
	op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
	op.addheaders = [("User-Agent", "Mozilla/5.0")]
	html = op.open(base).read().decode()
	csrf = re.search(r'name="csrf_token" value="([^"]+)"', html).group(1)
	data = urllib.parse.urlencode({"csrf_token": csrf}).encode()
	dl_url = json.loads(op.open(base + "/download_url", data).read().decode())["url"]
	html2 = op.open(dl_url).read().decode()
	uploads = re.findall(r'data-upload_id="(\d+)"', html2)
	names = re.findall(r'<strong[^>]*title="([^"]+)"', html2)
	csrf2 = re.search(r'name="csrf_token" value="([^"]+)"', html2)
	csrf_use = csrf2.group(1) if csrf2 else csrf
	print("uploads:", list(zip(uploads, names)))
	for uid, name in zip(uploads, names):
		if "[Source]" in name:
			print("skip source-tier:", name)
			continue
		d2 = urllib.parse.urlencode({"csrf_token": csrf_use}).encode()
		j = json.loads(op.open(f"{base}/file/{uid}?source=view_game", d2).read().decode())
		url = j.get("url", "")
		if not url:
			print("NO URL for", name)
			continue
		dest = f"{out_dir}/{name}"
		print("downloading:", name)
		with op.open(url) as r, open(dest, "wb") as f:
			while True:
				chunk = r.read(1 << 20)
				if not chunk:
					break
				f.write(chunk)
		print("saved:", dest)


if __name__ == "__main__":
	main()
