#!/usr/bin/env python3
"""jumps.py — find one-frame jumps (blinks, pops) in a re-timed recording (scripts/circle-check.sh strip).

Reads raw 8-bit gray frames (W×H each) from stdin, split into a grid of tiles. A tile "jumps" at frame i when it
changes a lot between i-1 and i but is nearly still just before and just after: a cut, not an animation (an
animation spreads its change over several frames). Prints one line per jump: frame, time, tile, size.

  ffmpeg … -vf "fps=60,scale=W:H,format=gray" -f rawvideo - | jumps.py W H 60 [threshold] [offset seconds]
"""
import sys

def main():
    w, h, fps = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
    threshold = float(sys.argv[4]) if len(sys.argv) > 4 else 3.0    # mean |Δ| in a tile, 0…255
    offset = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0       # the recording time of frame 0
    cols, rows = 4, 8
    tw, th = w // cols, h // rows
    size = w * h
    frames = []
    data = sys.stdin.buffer
    while True:
        f = data.read(size)
        if len(f) < size:
            break
        frames.append(f)
    if len(frames) < 3:
        print("too few frames"); return

    def tile_means(a, b):
        out = []
        for r in range(rows):
            for c in range(cols):
                total = 0
                for y in range(r * th, (r + 1) * th, 2):            # every other row: plenty, twice as fast
                    o = y * w + c * tw
                    ra, rb = a[o:o + tw], b[o:o + tw]
                    total += sum(abs(x - z) for x, z in zip(ra, rb))
                out.append(total / (tw * ((th + 1) // 2)))
        return out

    diffs = [None] + [tile_means(frames[i - 1], frames[i]) for i in range(1, len(frames))]
    hits = {}
    for i in range(12, len(frames) - 1):                            # the first 0.2 s: the trim's own edge
        for t in range(cols, rows * cols):                          # row 0 is the status bar: skipped
            d, before, after = diffs[i][t], diffs[i - 1][t], diffs[i + 1][t]
            if d >= threshold and before < d * 0.2 and after < d * 0.2:
                # The recorder sometimes captures at ~30 Hz: re-timed to 60, a smooth move changes every other frame
                # (change, still, change). Already moving two frames before = that cadence (its last step included), not
                # a cut: a cut comes out of stillness (B1, a ring holding then leaping, had nothing moving before it).
                # A cut in the middle of a 30 Hz move can't be told from the move itself — look at the strip there.
                around = diffs[i - 2][t] if i >= 2 and diffs[i - 2] else 0
                if around >= d * 0.3:
                    continue
                hits.setdefault(i, []).append((t, d))
    # A thin arc sweeping fast changes the one tile its head crosses in one frame: not a cut. A real cut moves
    # several tiles at once (the flourish's ring: 6), or one by a lot (a pop: Δ44).
    hits = {i: t for i, t in hits.items() if len(t) >= 2 or max(d for _, d in t) >= 10}
    for i, tiles in sorted(hits.items()):
        where = ", ".join(f"r{t // cols}c{t % cols}" for t, _ in tiles)
        print(f"jump  t={offset + i / fps:6.2f}s  frame {i:4d}  {len(tiles):2d} tile(s), max Δ{max(d for _, d in tiles):5.1f}  [{where}]")
    print(f"{len(hits)} one-frame jump(s) in {len(frames)} frames" + ("" if hits else " — clean"))

if __name__ == "__main__":
    main()
