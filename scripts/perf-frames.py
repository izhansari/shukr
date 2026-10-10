#!/usr/bin/env python3
# perf-frames.py <frames.log> — counts the late frames FrameMonitor wrote (-perfFrames): while the pager moves (what a
# finger feels) vs while it's idle (mostly the UI test reading the screen before each swipe — not there in real use).
import sys,re
moving=idle=0; mv_ms=0; lines=open(sys.argv[1]).read().splitlines()
for l in lines:
    m=re.search(r"late +([\d.]+) ms \((\d+) frames\)\s+pager (\w+)",l)
    if not m: continue
    ms,fr,ph=float(m.group(1)),int(m.group(2)),m.group(3)
    if ph in("interacting","decelerating","animating"): moving+=fr; mv_ms+=ms
    else: idle+=fr
swipes=sum(1 for l in lines if "pager interacting" in l)
print(f"swipes {swipes}: dropped while moving {moving} ({moving/max(swipes,1):.2f} per swipe), while idle {idle} (the test's own screen reads)")
