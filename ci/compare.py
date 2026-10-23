import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from PIL import Image
import apply_skin
font = os.path.join("pkg", "data", "font-fallback.ttf")
cases = [("dark", "s100", "4CC2FF", "dark_blue"), ("light", "s100", "0067C0", "light_blue"), ("dark", "s150", "E81123", "dark_red150")]
bad = 0
for theme, sc, hexa, name in cases:
    acc = tuple(int(hexa[i:i+2], 16) for i in (0, 2, 4))
    ref = os.path.join("ref", name)
    apply_skin.apply(os.path.join("pkg", "data", theme, sc), ref, acc, font)
    got = os.path.join("out", name)
    worst = 0; files = 0; badfiles = []
    for f in sorted(os.listdir(ref)):
        if not f.endswith(".png"):
            continue
        files += 1
        a = Image.open(os.path.join(ref, f)).convert("RGBA")
        gp = os.path.join(got, f)
        if not os.path.exists(gp):
            badfiles.append((f, "missing")); continue
        b = Image.open(gp).convert("RGBA")
        if a.size != b.size:
            badfiles.append((f, "size %s vs %s" % (a.size, b.size))); continue
        da = a.tobytes(); db = b.tobytes()
        m = max(abs(x - y) for x, y in zip(da, db)) if da != db else 0
        # pixels with alpha 0: colour is irrelevant
        if m:
            m = 0
            pa = a.load(); pb = b.load()
            for y in range(a.size[1]):
                for x in range(a.size[0]):
                    p, q = pa[x, y], pb[x, y]
                    if p[3] == 0 and q[3] == 0: continue
                    m = max(m, max(abs(p[i] - q[i]) for i in range(4)))
        worst = max(worst, m)
        if m > 3: badfiles.append((f, "maxdiff %d" % m))
    xa = open(os.path.join(ref, "theme.xml"), encoding="utf-8").read()
    xb = open(os.path.join(got, "theme.xml"), encoding="utf-8").read().replace("\r\n", "\n")
    print(name, "files", files, "worst pixel diff", worst, "xml equal", xa == xb, "bad", badfiles[:8])
    if badfiles or xa != xb: bad += 1
sys.exit(1 if bad else 0)
