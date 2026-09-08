#!/usr/bin/env python3
"""Dev server for the web game + map editor: static files from the repo root, plus PUT writes for the editable data files.
Usage: python3 web/gate-room/tools/edit_server.py [port]   (run from the repo root; .claude/launch.json does this)
Only these paths accept PUT (JSON body, validated): data/*.json, web/gate-room/data/*.json
"""
import json, os, re, subprocess, sys, threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
ENCODERS, LOCK = {}, threading.Lock()  # name → ffmpeg process (frames arrive in order on one connection chain)
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
        # keep the file's existing indentation, ASCII-escaping and trailing-newline style so saves don't reformat the repo data
        indent, nl = '\t', '\n'
        try:
            with open(target) as f: existing = f.read()
            m = re.match(r'^(\s+)', existing.split('\n')[1]); indent = m.group(1) if m else '\t'; nl = '\n' if existing.endswith('\n') else ''
        except Exception: pass
        with open(target, 'w') as f: json.dump(data, f, indent=indent, ensure_ascii=True); f.write(nl)
        self.send_response(200); self.end_headers(); self.wfile.write(f'wrote {self.path} ({len(body)} bytes)'.encode())
    def reply(self, code, text):
        self.send_response(code); self.end_headers(); self.wfile.write(text.encode())
    def do_POST(self):
        # recorder.js streams JPEG frames: /rec/start?name=&fps= spawns ffmpeg reading image2pipe on stdin, /rec/frame appends
        # one frame, /rec/stop closes the pipe → ~/Desktop/<name>.mp4. Fixed frame rate = smooth video however slow the game ran.
        from urllib.parse import urlparse, parse_qs
        u = urlparse(self.path); q = parse_qs(u.query); name = q.get('name', ['gameplay'])[0]
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if not re.match(r'^[A-Za-z0-9_\-]+$', name): return self.reply(400, 'bad name')
        target = os.path.join(os.path.expanduser('~/Desktop'), f'{name}.mp4')
        if u.path == '/rec/start':
            fps = int(q.get('fps', ['30'])[0])
            with LOCK:
                if name in ENCODERS: ENCODERS.pop(name).stdin.close()
                ENCODERS[name] = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', str(fps), '-i', '-', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'veryfast', '-crf', '23', target], stdin=subprocess.PIPE)
            return self.reply(200, f'encoding {target} at {fps} fps')
        if u.path == '/rec/frame':
            enc = ENCODERS.get(name)
            if not enc: return self.reply(409, 'not recording')
            with LOCK: enc.stdin.write(body)
            return self.reply(200, 'ok')
        if u.path == '/rec/stop':
            enc = ENCODERS.pop(name, None)
            if not enc: return self.reply(409, 'not recording')
            enc.stdin.close(); enc.wait()
            return self.reply(200, f'saved {target} ({os.path.getsize(target) / 1e6:.1f} MB)')
        self.reply(400, 'bad request')
    def log_message(self, fmt, *args):
        if self.command == 'PUT' or (self.command == 'POST' and '/rec/frame' not in self.path): super().log_message(fmt, *args)

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8090
    print(f'serving {ROOT} on http://127.0.0.1:{port}  (PUT enabled for data/*.json, localhost only)')
    ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()  # localhost only: the PUT endpoint is unauthenticated by design (dev tool)
