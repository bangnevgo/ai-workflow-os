#!/usr/bin/env python3
"""make_demo_gif.py — buat GIF demo terminal dari output CLI asli.

Menjalankan narasi `workflow` di root sementara (NEVGO_HOME), menangkap output,
lalu merender animasi "terminal window" ala GitHub dark. Output: <repo>/demo.gif
"""
import os, subprocess, sys, tempfile, textwrap

W = "/home/user/nevgo/workflow"
OUT = "/home/user/nevgo/demo.gif"

# ---------- jalankan CLI di root temp ----------
T = tempfile.mkdtemp(prefix="nevgo-gif-")
WEB = os.path.join(T, "divisions", "website")   # divisi di dalam root temp!
env = dict(os.environ, NEVGO_HOME=T, NEVGO_NO_GIT="1")
subprocess.run([W, "init"], env=env, capture_output=True)

def run(args, cwd=WEB):
    r = subprocess.run([W] + args, cwd=cwd, env=env, capture_output=True, text=True)
    return (r.stdout + r.stderr).splitlines()

# Scene: display prompt (boleh multi-baris dgn kontinuasi '\'), argv asli, filter
SCENES = [
 dict(prompt=["# one CLI. every platform. one ledger."],
      show="comment"),
 dict(prompt=["$ cd divisions/website", "$ workflow whoami"],
      run=["whoami"],
      keep=["divisi"]),   # hanya tampilkan baris divisi (root/ledger memuat path temp)
 dict(prompt=["# mark the work as started"],
      show="comment"),
 dict(prompt=["$ workflow submit --project checkout-redesign --status SIAP-JALAN",
              "$ # platform-a starts the task"],
      run=["submit", "--project", "checkout-redesign", "--status", "SIAP-JALAN", "--actor", "platform-a"]),
 dict(prompt=["# later, platform-b claims it is done... without any proof",
              "$ workflow submit --project checkout-redesign --status SELESAI --actor platform-b"],
      run=["submit", "--project", "checkout-redesign", "--status", "SELESAI", "--actor", "platform-b"],
      pause=9),   # beri waktu baca momen ditolak
 dict(prompt=["# REJECTED. not warned — rejected. zero bytes written.",
              "# and the refusal is itself recorded as data:"],
      show="comment"),
 dict(prompt=["$ workflow rejections --division website"],
      run=["rejections", "--division", "website"],
      head=3),  # cukup: header + entry + alasan pertama
 dict(prompt=["# now with concrete evidence + how it was verified:",
              "$ workflow submit --project checkout-redesign --status SELESAI \\",
              "      --evidence \"url live: checkout.nevgo.id, screenshot terlampir\" \\",
              "      --verification \"curl -I checkout.nevgo.id -> 200 OK, dicek manual\" \\",
              "      --actor platform-b"],
      run=["submit", "--project", "checkout-redesign", "--status", "SELESAI", "--actor", "platform-b",
           "--evidence", "url live: checkout.nevgo.id, screenshot terlampir",
           "--verification", "curl -I checkout.nevgo.id -> 200 OK, dicek manual"]),
 dict(prompt=["# every line is hash-chained. check integrity anytime:",
              "$ workflow verify"],
      run=["verify"],
      keep=["website", "konsisten"]),
 dict(prompt=["# ready when you are."],
      show="comment"),
]

captured = []
for i, sc in enumerate(SCENES):
    if "run" in sc:
        lines = run(sc["run"])
        if sc.get("keep"):
            lines = [l for l in lines if any(k in l for k in sc["keep"])]
        # buang baris kosong & path absolut temp yang bocor
        lines = [l for l in lines if l.strip() and T not in l]
        if sc.get("head"):
            lines = lines[: sc["head"]]
    else:
        lines = []
    captured.append(lines)

# ---------- render GIF ----------
from PIL import Image, ImageDraw, ImageFont

try:
    FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
    FONT_R = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
    f = ImageFont.truetype(FONT_R, 15)
    fb = ImageFont.truetype(FONT_B, 15)
except Exception:
    f = fb = ImageFont.load_default()

FS = 15
CW = f.getlength("M")            # lebar satu karakter monospace
LH = 23                          # line height
PADX, PADY = 22, 14
CWIN_W, TITLE_H = 880, 40
BODY_H = 560
W, H = CWIN_W, TITLE_H + BODY_H
CHARS = int((CWIN_W - 2 * PADX) / CW) - 1

# palet GitHub dark
BG      = (13, 17, 23)
HEADER  = (22, 27, 34)
BORDER  = (48, 54, 61)
TXT     = (201, 209, 217)
DIM     = (139, 148, 158)
GREEN   = (63, 185, 80)
RED     = (248, 81, 73)
YELLOW  = (210, 153, 34)
BLUE    = (88, 166, 255)
CYAN    = (86, 182, 194)
DOT_CR  = (255, 92, 86); DOT_CY = (255, 189, 46); DOT_CG = (39, 201, 63)

def fit(s):
    s = s.rstrip()
    if len(s) > CHARS:
        s = s[: CHARS - 1] + "…"
    return s

def classify(s):
    t = s.strip()
    if t.startswith("#"):
        return BLUE
    if t.startswith("DITOLAK") or t.startswith("✗") or t.startswith("GAGAL"):
        return RED
    if t.startswith("OK "):
        return GREEN
    if t.startswith("$"):
        return None          # prompt khusus
    if s.startswith("  ") and ("—" not in t) and not t.startswith("-"):
        return DIM
    if "konsisten" in s or "Semua store" in s:
        return GREEN
    return TXT

def line_img_parts(s):
    """kembalikan daftar (teks, warna) agar bisa warnai prompt $ & arg."""
    parts = []
    if s.startswith("$"):
        i = s.find(" ")
        parts.append(("$", GREEN))
        rest = s[i+1:]
        # argumen dalam tanda kutip -> warna lain
        import re
        head = []
        for tok in re.split(r"(\s+|--[a-z-]+)", rest):
            if tok.startswith("--") and tok.strip():
                parts.append((tok, CYAN))
            elif tok.strip() == "":
                parts.append((tok, TXT))
            else:
                parts.append((tok, TXT))
        return parts
    col = classify(s)
    if col is None:
        col = TXT
    return [(s, col)]

def colorize_leading(s, col):
    return [(s, col)]

def draw_window(img):
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=12, fill=BG, outline=BORDER)
    # header
    d.rounded_rectangle([2, 2, W - 3, TITLE_H - 4], radius=10, fill=HEADER)
    d.rectangle([2, TITLE_H - 20, W - 3, TITLE_H - 4], fill=HEADER)
    d.ellipse([16, 13, 28, 25], fill=DOT_CR)
    d.ellipse([34, 13, 46, 25], fill=DOT_CY)
    d.ellipse([52, 13, 64, 25], fill=DOT_CG)
    # title
    tt = "platform-a@nevgo: ~/nevgo/divisions/website"
    tw = d.textlength(tt, font=f)
    d.text(((W - tw) / 2, 13), tt, font=f, fill=DIM)

def build_frames(visible_lines, frame_pause):
    """visible_lines: list baris (teks|parts) yang tampil pada frame ini."""
    img = Image.new("RGB", (W, H), (0, 0, 0))
    draw_window(img)
    d = ImageDraw.Draw(img)
    y = TITLE_H + PADY + 4
    x = PADX
    for ln in visible_lines:
        parts = ln if isinstance(ln, list) else colorize_leading(ln, classify(ln))
        for text, col in parts:
            d.text((x, y), text, font=f, fill=col)
            x += f.getlength(text)
        y += LH
        x = PADX
    return img

def lines_stack(frame_pause=3):
    """event stream -> list frame; tiap frame = list baris tampil.
    Prompt butuh 2 frame (bisa dibaca), hasil 1 frame per baris, jeda
    antar-scene bisa diatur per scene lewat kunci 'pause'."""
    frames = []
    stack = []                      # baris kumulatif (bagian yang tampil)
    for i, sc in enumerate(SCENES):
        prompts = sc["prompt"]
        results = captured[i]
        pause = sc.get("pause", frame_pause)
        # tulis prompt (2 frame supaya sempat dibaca)
        for p in prompts:
            stack.append(p)
            frames.append(list(stack))
            frames.append(list(stack))
        # tulis hasil
        for r in results:
            stack.append(r)
            frames.append(list(stack))
        # jeda antar scene
        for _ in range(pause):
            frames.append(list(stack))
    return frames, stack

MAX_VIS = int((BODY_H - PADY - 8) / LH) + 1   # baris maks yang muat

def finalize(frames, max_vis=MAX_VIS):
    out = []
    for fr in frames:
        out.append(fr[-max_vis:] if len(fr) > max_vis else fr)
    return out

def render(frames):
    imgs = []
    for fr in frames:
        vis = [fit(s) if isinstance(s, str) else None for s in fr]
        # prompt multi-baris dengan kontinuasi tetap tampil utuh: karena max_vis
        img = Image.new("RGB", (W, H), (0, 0, 0))
        draw_window(img)
        d = ImageDraw.Draw(img)
        y = TITLE_H + PADY + 4
        for s in vis:
            x = PADX
            if s is None:
                parts = fr[vis.index(s)] if False else []
            parts = line_img_parts(s)
            for text, col in parts:
                d.text((x, y), text, font=f, fill=col)
                x += f.getlength(text)
            y += LH
        imgs.append(img)
    return imgs

# --- perintah prompt pendek untuk menambah kedalaman: buat scrolling halus ---
# tiap perintah diberi 'pengetikan' cepat per baris; kita sudah buat di lines_stack.
frames, full = lines_stack()
frames_final = finalize(frames)
imgs = render(frames_final)

# durasi antar frame: 220ms — jeda antar scene dihasilkan frame_pause ekstra
imgs[0].save(OUT, save_all=True, append_images=imgs[1:],
             duration=220, loop=0, optimize=True)

# --- laporan & validasi teknis (tanpa mata) ---
import collections
GREEN_RGB = (63, 185, 80); RED_RGB = (248, 81, 73); BLUE_RGB = (88, 166, 255)
n_green = n_red = n_blue = 0
min_dim = None
for idx, im in enumerate(imgs):
    from PIL import ImageStat
    cols = im.getcolors(maxcolors=1 << 20) or []
    cnt = dict((c, n) for n, c in cols)
    if cnt.get(GREEN_RGB, 0) > 400: n_green += 1
    if cnt.get(RED_RGB, 0) > 100: n_red += 1
    if cnt.get(BLUE_RGB, 0) > 200: n_blue += 1
    # deteksi frame kosong (semua = bg/header/dots)
    hist = im.histogram()
    non_bg = sum(hist[:]) - hist[13*3]  # kira bg #0d1117 ~ (13,17,23)
    if min_dim is None or non_bg < min_dim:
        min_dim = non_bg
print("frame:", len(imgs), "| ukuran:", os.path.getsize(OUT), "bytes")
print(f"frame mengandung OK-hijau: {n_green}, DITOLAK-merah: {n_red}, komentar-biru: {n_blue}")
print("frame dengan isi terkecil (non-bg px):", min_dim)

# validasi bisa dibuka ulang & jumlah frame GIF sesuai
from PIL import Image as Im2
g = Im2.open(OUT)
print("validasi GIF: frame terhitung =", g.n_frames, "| size =", g.size)

