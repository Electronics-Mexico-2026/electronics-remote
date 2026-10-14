#!/usr/bin/env python3
"""Genera todos los iconos de Electronics Remote a partir de branding/src/.

Salida: branding/generated/<ruta-del-repo>, que branding/apply.sh copia encima
del arbol de RustDesk. Se corre en local (requiere Pillow) y el resultado se
versiona, asi el CI no necesita Pillow.

    python3 branding/gen_icons.py
"""
import base64
import io
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None

HERE = Path(__file__).resolve().parent
SRC = HERE / "src"
OUT = HERE / "generated"
BG = (0x14, 0x14, 0x14, 255)

ICON = Image.open(SRC / "icon-1024.png").convert("RGBA")
ISO = Image.open(SRC / "isotipo-256.png").convert("RGBA")
FG = Image.open(SRC / "android-foreground-432.png").convert("RGBA")
STAT = Image.open(SRC / "ic_stat_logo-256.png").convert("RGBA")


def out(rel):
    p = OUT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def resized(im, size):
    return im.resize((size, size), Image.LANCZOS)


def save_png(im, rel, size=None):
    if size:
        im = resized(im, size)
    im.save(out(rel), optimize=True)


def round_icon(size):
    """Circulo #141414 con la «e» centrada (ic_launcher_round)."""
    big = size * 4
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
    canvas.paste(Image.new("RGBA", (big, big), BG), (0, 0), mask)
    iso = resized(ISO, int(big * 0.62))
    off = (big - iso.size[0]) // 2
    canvas.alpha_composite(iso, (off, off))
    return canvas.resize((size, size), Image.LANCZOS)


def main():
    if OUT.exists():
        shutil.rmtree(OUT)

    # --- res/ (Rust: icono del exe/dll, bandeja, MSI, Linux/mac) ---
    shutil.copy(SRC / "icon.ico", out("res/icon.ico"))
    shutil.copy(SRC / "tray-icon.ico", out("res/tray-icon.ico"))
    save_png(ICON, "res/icon.png")
    save_png(ICON, "res/mac-icon.png")
    for name, s in [("32x32.png", 32), ("64x64.png", 64), ("128x128.png", 128),
                    ("128x128@2x.png", 256)]:
        save_png(ICON, f"res/{name}", s)

    # --- Windows runner (icono embebido en rustdesk.exe) ---
    shutil.copy(SRC / "icon.ico", out("flutter/windows/runner/resources/app_icon.ico"))

    # --- flutter/assets (icono de ventana, accesos directos, logo) ---
    shutil.copy(SRC / "icon.ico", out("flutter/assets/icon.ico"))
    save_png(ICON, "flutter/assets/icon.png", 256)
    # icon.svg (respaldo de loadIcon): SVG con la imagen PNG incrustada.
    buf = io.BytesIO()
    resized(ICON, 128).save(buf, format="PNG", optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode()
    out("flutter/assets/icon.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" width="128" height="128" '
        'viewBox="0 0 128 128"><image width="128" height="128" '
        f'xlink:href="data:image/png;base64,{b64}" href="data:image/png;base64,{b64}"/></svg>\n',
        encoding="utf-8")
    # Logo horizontal (fondo oscuro) para la pantalla principal; max 300x60.
    logo = Image.open(SRC / "logo-horizontal-negro.png").convert("RGBA")
    h = 180
    w = round(logo.size[0] * h / logo.size[1])
    logo = logo.resize((w, h), Image.LANCZOS)
    logo.save(out("flutter/assets/logo.png"), optimize=True)
    logo.save(out("flutter/assets/logo_dark.png"), optimize=True)

    # --- Android ---
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    base = "flutter/android/app/src/main/res"
    for d, k in dens.items():
        save_png(ICON, f"{base}/mipmap-{d}/ic_launcher.png", int(48 * k))
        round_icon(int(48 * k)).save(out(f"{base}/mipmap-{d}/ic_launcher_round.png"), optimize=True)
        save_png(FG, f"{base}/mipmap-{d}/ic_launcher_foreground.png", int(108 * k))
        save_png(STAT, f"{base}/mipmap-{d}/ic_stat_logo.png", int(24 * k))

    n = sum(1 for p in OUT.rglob("*") if p.is_file())
    print(f"{n} archivos generados en {OUT}")


if __name__ == "__main__":
    main()
