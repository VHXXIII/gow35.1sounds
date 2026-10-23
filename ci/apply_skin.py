#!/usr/bin/env python3
"""Reference implementation of what Win11Skin.ps1 does on the user's PC:
compose layers, tint the accent layers, fill the placeholders."""
import os, sys, shutil, glob
from PIL import Image

def mix(a, b, k):
    return tuple(int(round(a[i] * (1 - k) + b[i] * k)) for i in range(3))

def apply(tpl, out, accent, font, bar=None, soft=0.28):
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    groups = {}
    for f in os.listdir(tpl):
        if not f.endswith(".png"):
            continue
        stem = f[:-4]
        base, _, layer = stem.partition("+")
        groups.setdefault(base, {})[layer or "full"] = os.path.join(tpl, f)
    for base, parts in groups.items():
        if "full" in parts:
            shutil.copy(parts["full"], os.path.join(out, base + ".png"))
            continue
        first = next(iter(parts.values()))
        size = Image.open(first).size
        im = Image.new("RGBA", size, (0, 0, 0, 0))
        for layer in ("under", "accent", "over"):
            if layer not in parts:
                continue
            l = Image.open(parts[layer]).convert("RGBA")
            if layer == "accent":
                a = l.getchannel("A")
                l = Image.new("RGBA", l.size, tuple(accent) + (0,))
                l.putalpha(a)
            im.alpha_composite(l)
        im.save(os.path.join(out, base + ".png"))
    xml = open(os.path.join(tpl, "theme.xml.tpl"), encoding="utf-8").read()
    hx = lambda c: "#%02X%02X%02X" % tuple(c)
    # bar colour is already baked in; soft selection colour derives from it
    barhex = None
    import re
    m = re.search(r'bgcolor1="(#[0-9A-F]{6})"', xml)
    barc = tuple(int(m.group(1)[i:i+2], 16) for i in (1, 3, 5))
    xml = xml.replace("@ACCENT_SOFT@", hx(mix(barc, accent, soft))).replace("@ACCENT@", hx(accent))
    open(os.path.join(out, "theme.xml"), "w", encoding="utf-8").write(xml)
    shutil.copy(font, os.path.join(out, "font.ttf"))

if __name__ == "__main__":
    tpl, out, accent, font = sys.argv[1:5]
    acc = tuple(int(accent.lstrip("#")[i:i+2], 16) for i in (0, 2, 4))
    apply(tpl, out, acc, font)
