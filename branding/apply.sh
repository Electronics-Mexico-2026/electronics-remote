#!/usr/bin/env bash
# Aplica la marca «Electronics Remote» sobre el checkout de RustDesk.
# Se corre en CI despues de `actions/checkout` con submodulos (runners Windows
# con Git Bash y Ubuntu). Requiere python3 (sin Pillow: los iconos ya vienen
# generados en branding/generated/ por branding/gen_icons.py).
#
# Variables:
#   RENDEZVOUS_SERVER  host[:puerto] del hbbs propio (obligatoria)
#   RS_PUB_KEY         llave publica id_ed25519.pub del servidor (obligatoria)
#   API_SERVER         panel lejianwen/rustdesk-api, ej. http://IP:21114
#                      (opcional; vacio = http://<host del RENDEZVOUS_SERVER>:21114)
#   ALLOW_PLACEHOLDER  =1 permite compilar sin servidor (pendiente.invalid +
#                      llave original de RustDesk). SOLO para probar compilacion.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -f libs/hbb_common/src/config.rs ]; then
  echo "ERROR: falta libs/hbb_common (haz checkout con submodules: recursive)" >&2
  exit 1
fi

PY=python3
if ! command -v "$PY" >/dev/null 2>&1 || ! "$PY" -c 'import sys' >/dev/null 2>&1; then
  PY=python
fi

echo "== Electronics Remote: iconos"
cp -Rv branding/generated/. ./ | sed 's/^/  /'

echo "== Electronics Remote: fuentes"
"$PY" branding/patch_sources.py "$ROOT"

echo "== Electronics Remote: verificacion"
grep -n 'APP_NAME: RwLock<String>\|^pub const RENDEZVOUS_SERVERS\|^pub const RS_PUB_KEY' \
  libs/hbb_common/src/config.rs
echo "Listo."
