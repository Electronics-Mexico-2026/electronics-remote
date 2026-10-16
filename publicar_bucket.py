#!/usr/bin/env python3
"""Publica un release de Electronics Remote en el bucket público.

El actualizador de la app (Windows y Android) lee primero
  https://storage.googleapis.com/electronics-mexico-webhooks-fotos-publicas/electronics-remote/latest.json
y baja los archivos de electronics-remote/<tag>/<archivo>. Así sigue
funcionando aunque el repo de GitHub sea privado.

Uso (con `gh` y `gcloud` ya autenticados):
  python publicar_bucket.py                 # el último release (Latest)
  python publicar_bucket.py electronics-remote-1.5.0-er.27
  python publicar_bucket.py <tag> --solo-verificar

Pasos: gh release download <tag> -> sube cada archivo a electronics-remote/<tag>/
-> escribe latest.json (Cache-Control: no-cache) con url y sha256 -> verifica por
HTTP que latest.json diga ese tag y que cada archivo bajado tenga su sha256.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

REPO = "Electronics-Mexico-2026/electronics-remote"
BUCKET = "electronics-mexico-webhooks-fotos-publicas"
PREFIJO = "electronics-remote"
TAG_PREFIX = "electronics-remote-"
PUBLICO = f"https://storage.googleapis.com/{BUCKET}/{PREFIJO}"
ARCHIVOS = [
    "ElectronicsRemote-x64.exe",
    "ElectronicsRemote-x64.msi",
    "ElectronicsRemote.apk",
    "ElectronicsRemoteEquipo-x64.exe",
    "ElectronicsRemoteEquipo-x64.msi",
    "SHA256SUMS.txt",
]
TIPOS = {
    ".exe": "application/vnd.microsoft.portable-executable",
    ".msi": "application/x-msi",
    ".apk": "application/vnd.android.package-archive",
    ".txt": "text/plain; charset=utf-8",
}
WIN = os.name == "nt"


def correr(args, **kw):
    print("+", " ".join(args), flush=True)
    return subprocess.run(args, check=True, shell=WIN and args[0] == "gcloud", **kw)


def sha256_de(ruta):
    h = hashlib.sha256()
    with open(ruta, "rb") as f:
        for bloque in iter(lambda: f.read(1 << 20), b""):
            h.update(bloque)
    return h.hexdigest()


def ultimo_tag():
    out = subprocess.run(
        ["gh", "release", "view", "-R", REPO, "--json", "tagName", "-q", ".tagName"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    return out


def bajar_http(url):
    req = urllib.request.Request(url, headers={"Cache-Control": "no-cache", "User-Agent": "publicar_bucket"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def verificar(tag):
    url = f"{PUBLICO}/latest.json?nocache={int(time.time())}"
    latest = json.loads(bajar_http(url))
    if latest.get("tag") != tag:
        sys.exit(f"ERROR: latest.json público dice {latest.get('tag')!r}, se esperaba {tag!r}")
    faltan = [a for a in ARCHIVOS if a not in latest.get("files", {})]
    if faltan:
        sys.exit(f"ERROR: latest.json no lista {faltan}")
    for nombre, f in latest["files"].items():
        if f["url"] != f"{PUBLICO}/{tag}/{nombre}":
            sys.exit(f"ERROR: url inesperada para {nombre}: {f['url']}")
        datos = bajar_http(f["url"])
        got = hashlib.sha256(datos).hexdigest()
        estado = "OK" if got == f["sha256"] else "NO COINCIDE"
        print(f"  {estado}  {nombre}  {len(datos):,} bytes  {got}")
        if got != f["sha256"]:
            sys.exit(f"ERROR: sha256 de {nombre} no coincide")
    print(f"Verificado: {PUBLICO}/latest.json -> {tag}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tag", nargs="?", help="tag del release (por omisión el Latest de GitHub)")
    ap.add_argument("--solo-verificar", action="store_true", help="no sube nada; solo revisa lo público")
    a = ap.parse_args()
    tag = a.tag or ultimo_tag()
    if not tag.startswith(TAG_PREFIX):
        sys.exit(f"ERROR: tag inválido: {tag!r}")
    if a.solo_verificar:
        verificar(tag)
        return
    with tempfile.TemporaryDirectory(prefix="er-bucket-") as tmp:
        correr(["gh", "release", "download", tag, "-R", REPO, "-D", tmp, "--clobber"]
               + sum([["-p", n] for n in ARCHIVOS], []))
        files = {}
        for nombre in ARCHIVOS:
            ruta = os.path.join(tmp, nombre)
            if not os.path.getsize(ruta):
                sys.exit(f"ERROR: {nombre} vacío")
            files[nombre] = {"url": f"{PUBLICO}/{tag}/{nombre}", "sha256": sha256_de(ruta)}
        # Cotejar con el SHA256SUMS.txt que generó el CI.
        with open(os.path.join(tmp, "SHA256SUMS.txt"), encoding="utf-8") as f:
            for linea in f:
                partes = linea.split()
                if len(partes) == 2 and partes[1].lstrip("*") in files:
                    if files[partes[1].lstrip("*")]["sha256"] != partes[0].lower():
                        sys.exit(f"ERROR: {partes[1]} no coincide con SHA256SUMS.txt")
        for nombre in ARCHIVOS:
            ext = os.path.splitext(nombre)[1]
            correr(["gcloud", "storage", "cp", os.path.join(tmp, nombre),
                    f"gs://{BUCKET}/{PREFIJO}/{tag}/{nombre}",
                    f"--content-type={TIPOS[ext]}", "--cache-control=public, max-age=86400"])
        latest = {"tag": tag, "version": tag[len(TAG_PREFIX):], "files": files}
        ruta_json = os.path.join(tmp, "latest.json")
        with open(ruta_json, "w", encoding="utf-8") as f:
            json.dump(latest, f, indent=2)
        correr(["gcloud", "storage", "cp", ruta_json, f"gs://{BUCKET}/{PREFIJO}/latest.json",
                "--content-type=application/json", "--cache-control=no-cache"])
    verificar(tag)


if __name__ == "__main__":
    main()
