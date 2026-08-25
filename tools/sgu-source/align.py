"""Align cold-open spoken lines (gate_room.gd _cap/_cap_now) to the source ASR
segments via Needleman-Wunsch (monotonic, gap-tolerant), producing a timing map
vo_id -> source_start. Dev tool — operates on project data; prints only ids/timestamps."""
import json
import re
import difflib

GATE = "../../scripts/gate_room.gd"
ASR = "asr/transcript.json"

cap_re = re.compile(r'_cap\(\s*"([^"]*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*([0-9.]+)\s*,\s*"([^"]+)"')
capnow_re = re.compile(r'_cap_now\(\s*"([^"]*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*"([^"]+)"')

lines = []
with open(GATE) as f:
    for ln in f:
        m = cap_re.search(ln)
        if m:
            lines.append({"speaker": m.group(1), "text": m.group(2), "at_t": float(m.group(3)), "vo": m.group(4)})
            continue
        m = capnow_re.search(ln)
        if m:
            lines.append({"speaker": m.group(1), "text": m.group(2), "at_t": None, "vo": m.group(3)})

asr = json.load(open(ASR))["segments"]

def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).strip()

L = [norm(x["text"]) for x in lines]
A = [norm(s["text"]) for s in asr]

def sim(a, b):
    if not a or not b:
        return 0.0
    r = difflib.SequenceMatcher(None, a, b).ratio()
    if a in b or b in a:
        r = max(r, 0.7)
    return r

n, m = len(L), len(A)
GAP = -0.2
dp = [[0.0] * (m + 1) for _ in range(n + 1)]
bt = [[0] * (m + 1) for _ in range(n + 1)]   # 0=diag 1=up(skip line) 2=left(skip asr)
for i in range(1, n + 1):
    dp[i][0] = dp[i-1][0] + GAP; bt[i][0] = 1
for j in range(1, m + 1):
    dp[0][j] = dp[0][j-1] + GAP; bt[0][j] = 2
for i in range(1, n + 1):
    for j in range(1, m + 1):
        d = dp[i-1][j-1] + (sim(L[i-1], A[j-1]) - 0.3)
        u = dp[i-1][j] + GAP
        l = dp[i][j-1] + GAP
        best = max(d, u, l)
        dp[i][j] = best
        bt[i][j] = 0 if best == d else (1 if best == u else 2)

# backtrack → pair line i-1 with asr j-1 on diagonal
pair = {}
i, j = n, m
while i > 0 and j > 0:
    if bt[i][j] == 0:
        pair[i-1] = j-1
        i -= 1; j -= 1
    elif bt[i][j] == 1:
        i -= 1
    else:
        j -= 1

amap = []
last_src = 0.0
for idx, li in enumerate(lines):
    if idx in pair:
        seg = asr[pair[idx]]
        src = seg["start"]; sc = round(sim(L[idx], A[pair[idx]]), 2)
        last_src = src
    else:
        src = None; sc = 0.0
    amap.append({"vo": li["vo"], "speaker": li["speaker"], "at_t": li["at_t"],
                 "source_start": src, "score": sc})

json.dump(amap, open("timing_map.json", "w"), indent=2)
print("lines:", n, "asr:", m, "matched:", len(pair))
for a in amap:
    print(f'{a["vo"]:26s} at_t={str(a["at_t"]):>6s}  src={str(a["source_start"]):>7s}  score={a["score"]}')
