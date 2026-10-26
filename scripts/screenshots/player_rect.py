"""Prints the player rectangle (the largest pure-black area) of a window snapshot as x,y,w,h.
Usage: python3 player_rect.py snapshot.png"""
import re, subprocess, sys

out = subprocess.run(
    ["magick", sys.argv[1], "-quiet", "-alpha", "off", "-fuzz", "0.5%", "-fill", "white", "+opaque", "#000000",
     "-define", "connected-components:verbose=true", "-define", "connected-components:area-threshold=20000",
     "-connected-components", "4", "null:"],
    capture_output=True, text=True).stdout
best = None
for line in out.splitlines():
    # e.g. "  3: 860x484+20+301 449.5,542.5 415996 srgb(7.5e-06%,7.5e-06%,7.5e-06%)"
    m = re.match(r"\s*\d+: (\d+)x(\d+)\+(\d+)\+(\d+) \S+ ([\d.e+]+) \w+\(([^)]*)\)", line)
    if not m:
        continue
    w, h, x, y, area = int(m[1]), int(m[2]), int(m[3]), int(m[4]), float(m[5])
    black = all(float(c.rstrip("%")) < 1 for c in m[6].split(","))
    if black and (best is None or area > best[4]):
        best = (x, y, w, h, area)
if best is None:
    sys.exit("no black area found")
print(f"{best[0]},{best[1]},{best[2]},{best[3]}")
