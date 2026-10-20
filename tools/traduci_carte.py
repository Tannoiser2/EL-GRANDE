#!/usr/bin/env python3
"""Traduce in italiano le carte scansionate in inglese (Intrigo & il Re, Colonie).

Per ogni carta, nelle zone indicate (titolo, righe di testo), si cancella l'inchiostro ricostruendo la
pergamena (inpaint) e si scrive il testo italiano con un carattere simile all'originale.
Le zone stanno in un file python (dizionario S): {"nome": {"t": titolo [x0,y0,x1,y1], "e": zone da
cancellare, "b": area del testo, "l": etichette [x0,y0,x1,y1,"testo"]}}.
Uso: traduci_carte.py <cartella sorgenti> <cartella destinazione> <testi.json> <zone.py> [prefisso]
"""
import json, sys, os, runpy
import cv2, numpy as np
from PIL import Image, ImageDraw, ImageFont

FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "fonts")
INK = (40, 26, 16)


def font(name, size, weight=None):
    f = ImageFont.truetype(os.path.join(FONTS, name), size)
    if weight:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    return f


def wrap(draw, text, fnt, width):
    lines = []
    for para in text.split("\n"):
        cur = ""
        for w in para.split(" "):
            t = (cur + " " + w).strip()
            if draw.textlength(t, font=fnt) <= width or not cur:
                cur = t
            else:
                lines.append(cur)
                cur = w
        lines.append(cur)
    return lines


def erase(im, rects):
    H, W = im.shape[:2]
    gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
    mask = np.zeros((H, W), np.uint8)
    for r in rects:
        x0, y0, x1, y1 = [int(v) for v in r[:4]]
        x0, y0 = max(0, x0), max(0, y0)
        x1, y1 = min(W, x1), min(H, y1)
        sub = gray[y0:y1, x0:x1]
        mask[y0:y1, x0:x1] |= ((sub < 175).astype(np.uint8) * 255)
    mask = cv2.dilate(mask, np.ones((7, 7), np.uint8))
    return cv2.inpaint(im, mask, 9, cv2.INPAINT_TELEA)


def fit_title(d, title, rect):
    x0, y0, x1, y1 = rect
    size = int((y1 - y0) * 0.78)
    while size > 16:
        f = font("AlegreyaSC-Bold.ttf", size)
        if d.textlength(title, font=f) <= min(max(x1 - x0, 360) + 40, 600 - x0):
            return f
        size -= 2
    return font("AlegreyaSC-Bold.ttf", size)


def body(d, text, rect, maxsize=50):
    x0, y0, x1, y1 = rect
    size = maxsize
    while size > 14:
        f = font("Alegreya.ttf", size, 520)
        ls = wrap(d, text, f, x1 - x0)
        lh = int(size * 1.13)
        if len(ls) * lh <= (y1 - y0):
            break
        size -= 1
    y = y0 + max(0, ((y1 - y0) - len(ls) * lh) // 2)
    for l in ls:
        d.text((x0, y), l, font=f, fill=INK)
        y += lh


def process(src, dst, title, text, z):
    im = cv2.imread(src)
    rects = list(z.get("e", []))
    if z.get("t"):
        rects.append(z["t"])
    for l in z.get("l", []):
        rects.append(l[:4])
    im = erase(im, rects)
    pil = Image.fromarray(cv2.cvtColor(im, cv2.COLOR_BGR2RGB))
    d = ImageDraw.Draw(pil)
    if z.get("t") and title and "\n" in title:
        # titolo su più righe, allineato a destra come sull'originale
        t = z["t"]
        tl = title.split("\n")
        lh = (t[3] - t[1]) / len(tl)
        f = font("AlegreyaSC-Bold.ttf", int(lh * 0.8))
        for i, l in enumerate(tl):
            d.text((t[2], t[1] + lh * (i + 0.85)), l, font=f, fill=INK, anchor="rs")
    elif z.get("t") and title:
        t = z["t"]
        f = fit_title(d, title, t)
        d.text((t[0], t[3] - (t[3] - t[1]) * 0.12), title, font=f, fill=INK, anchor="ls")
    elif title:
        text = title + ". " + text
    body(d, text, z["b"])
    for l in z.get("l", []):
        f = font("Alegreya.ttf", max(16, int((l[3] - l[1]) * 0.85)), 650)
        d.text((l[0] + 4, l[3] - 4), l[4], font=f, fill=INK, anchor="ls")
    pil.save(dst)


if __name__ == "__main__":
    src, dst, js, zf = sys.argv[1:5]
    pre = sys.argv[5] if len(sys.argv) > 5 else ""
    texts = json.load(open(js, encoding="utf-8"))
    zones = runpy.run_path(zf)["S"]
    os.makedirs(dst, exist_ok=True)
    for name, (title, text) in texts.items():
        key = name.replace(pre, "").split(".")[0]
        process(os.path.join(src, name), os.path.join(dst, name), title, text, zones[key])
