#!/usr/bin/env python3
"""Dev server for the web game + map editor: static files from the repo root, plus PUT writes for the editable data files.
Usage: python3 web/gate-room/tools/edit_server.py [port]   (run from the repo root; .claude/launch.json does this)
Only these paths accept PUT (JSON body, validated): data/*.json, web/gate-room/data/*.json
"""
import json, os, re, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
WRITABLE = re.compile(r'^/(data|web/gate-room/data)/[A-Za-z0-9_\-]+\.json$')

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=ROOT, **kw)
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store'); super().end_headers()
    def do_PUT(self):
        if not WRITABLE.match(self.path):
            self.send_response(403); self.end_headers(); self.wfile.write(b'not writable'); return
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        try: data = json.loads(body)
        except Exception as e:
            self.send_response(400); self.end_headers(); self.wfile.write(f'bad json: {e}'.encode()); return
        target = os.path.join(ROOT, self.path.lstrip('/'))
        indent = '\t'  # keep the file's existing indentation style so saves don't reformat the repo data
        try:
            with open(target) as f: second = f.read().split('\n')[1]
            m = re.match(r'^(\s+)', second); indent = m.group(1) if m else '\t'
        except Exception: pass
        with open(target, 'w') as f: json.dump(data, f, indent=indent, ensure_ascii=True)  # existing files escape non-ASCII (\u2014); keep diffs clean; f.write('\n')
        self.send_response(200); self.end_headers(); self.wfile.write(f'wrote {self.path} ({len(body)} bytes)'.encode())
    def log_message(self, fmt, *args):
        if self.command == 'PUT': super().log_message(fmt, *args)

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8090
    print(f'serving {ROOT} on http://127.0.0.1:{port}  (PUT enabled for data/*.json, localhost only)')
    ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()  # localhost only: the PUT endpoint is unauthenticated by design (dev tool)
