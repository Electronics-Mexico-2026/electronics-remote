#!/usr/bin/env python3
"""Aplica la marca Electronics Remote sobre el arbol de RustDesk 1.5.0.

Lo llama branding/apply.sh; no usar suelto. Cada reemplazo es estricto: si el
texto original ya no existe (RustDesk cambio el archivo) falla con error, para
que el CI no publique un build a medio marcar. Es idempotente: si el texto ya
tiene la marca, lo deja pasar.
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
APP = "Electronics Remote"
COMPANY = "Electronics Mexico"
COPYRIGHT = "Electronics Mexico - basado en RustDesk (AGPL-3.0)"

errors = []


def read(rel):
    raw = (ROOT / rel).read_bytes().decode("utf-8")
    return raw.replace("\r\n", "\n"), "\r\n" in raw


def write(rel, text, crlf):
    if crlf:
        text = text.replace("\n", "\r\n")
    (ROOT / rel).write_bytes(text.encode("utf-8"))


def edit(rel, pairs, regex=False):
    text, crlf = read(rel)
    for old, new in pairs:
        if regex:
            text2, n = re.subn(old, lambda m: new, text, flags=re.M)
            if n == 0 and new not in text:
                errors.append(f"{rel}: no encontre /{old}/")
            text = text2
        else:
            if old in text:
                text = text.replace(old, new)
            elif new not in text:
                errors.append(f"{rel}: no encontre {old!r}")
    write(rel, text, crlf)


def rs_str(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


# ---------------------------------------------------------------- config.rs
server = os.environ.get("RENDEZVOUS_SERVER", "").strip()
key = os.environ.get("RS_PUB_KEY", "").strip()
placeholder = os.environ.get("ALLOW_PLACEHOLDER", "") == "1"
if not server or not key:
    if not placeholder:
        sys.exit("ERROR: faltan RENDEZVOUS_SERVER y/o RS_PUB_KEY "
                 "(usa ALLOW_PLACEHOLDER=1 solo para probar compilacion)")
    print("AVISO: ALLOW_PLACEHOLDER=1 -> servidor 'pendiente.invalid' y llave original de RustDesk")
    server = server or "pendiente.invalid"
if server and not re.fullmatch(r"[A-Za-z0-9.\-\[\]:]+", server):
    sys.exit(f"ERROR: RENDEZVOUS_SERVER invalido: {server!r}")
if key and not re.fullmatch(r"[A-Za-z0-9+/]{43}=", key):
    sys.exit("ERROR: RS_PUB_KEY no parece una llave publica de RustDesk (44 caracteres base64)")

cfg = "libs/hbb_common/src/config.rs"
text, cfg_crlf = read(cfg)
n_total = 0
text, n = re.subn(r'(pub static ref APP_NAME: RwLock<String> = RwLock::new\()"[^"]*"',
                  lambda m: f'{m.group(1)}"{APP}"', text)
n_total += n
text, n = re.subn(r'^pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[[^\]]*\];',
                  lambda m: f'pub const RENDEZVOUS_SERVERS: &[&str] = &["{rs_str(server)}"];',
                  text, flags=re.M)
n_total += n
if key:
    text, n = re.subn(r'^pub const RS_PUB_KEY: &str = "[^"]*";',
                      lambda m: f'pub const RS_PUB_KEY: &str = "{key}";', text, flags=re.M)
    n_total += n
else:
    n_total += 1
if n_total != 3:
    errors.append(f"{cfg}: esperaba 3 reemplazos, hubo {n_total}")
write(cfg, text, cfg_crlf)
print(f"config.rs -> APP_NAME={APP!r} RENDEZVOUS_SERVERS=[{server!r}] "
      f"RS_PUB_KEY={'(original)' if not key else key[:6] + '...'}")

# ------------------------------------------- servidor API (rustdesk-api)
# Si el usuario no escribe «Servidor API» en Ajustes, RustDesk cae a
# https://admin.rustdesk.com (src/common.rs, get_api_server_). Ese respaldo
# pasa a ser el panel propio (lejianwen/rustdesk-api). Sin API_SERVER se usa
# http://<host del RENDEZVOUS_SERVER>:21114, que es el puerto de ese panel.
api = os.environ.get("API_SERVER", "").strip().rstrip("/")
if not api:
    host = server
    if host.startswith("["):
        host = host[: host.index("]") + 1]
    elif host.count(":") == 1:
        host = host.split(":")[0]
    api = f"http://{host}:21114"
    print(f"AVISO: API_SERVER vacio -> {api}")
if not re.fullmatch(r"https?://[A-Za-z0-9.\-\[\]:]+(/[A-Za-z0-9._~/\-]*)?", api):
    sys.exit(f"ERROR: API_SERVER invalido: {api!r} (ej. http://IP:21114)")
edit("src/common.rs", [
    ('    "https://admin.rustdesk.com".to_owned()\n}',
     f'    "{rs_str(api)}".to_owned()\n}}'),
])
print(f"common.rs -> servidor API por defecto {api}")

# ---------------------------------------------------- recursos de Windows
edit("flutter/windows/runner/Runner.rc", [
    ('VALUE "CompanyName", "Purslane Tech Pte. Ltd."', f'VALUE "CompanyName", "{COMPANY}"'),
    ('VALUE "FileDescription", "RustDesk Remote Desktop"', f'VALUE "FileDescription", "{APP}"'),
    ('VALUE "ProductName", "RustDesk"', f'VALUE "ProductName", "{APP}"'),
])
edit("flutter/windows/runner/Runner.rc", [
    (r'VALUE "LegalCopyright", "[^"]*"', f'VALUE "LegalCopyright", "{COPYRIGHT}"'),
], regex=True)
for toml in ("Cargo.toml", "libs/portable/Cargo.toml"):
    edit(toml, [
        (r'^LegalCopyright = ".*"$', f'LegalCopyright = "{COPYRIGHT}"'),
        (r'^ProductName = "RustDesk"$', f'ProductName = "{APP}"'),
        (r'^FileDescription = "RustDesk Remote Desktop"$', f'FileDescription = "{APP}"'),
    ], regex=True)

# ------------------------------------------------------------------ Android
res = "flutter/android/app/src/main/res"
edit("flutter/android/app/src/main/AndroidManifest.xml", [
    ('android:label="RustDesk Input"', f'android:label="{APP} Input"'),
    ('android:label="RustDesk"', f'android:label="{APP}"'),
])
edit(f"{res}/values/strings.xml", [
    ('<string name="app_name">RustDesk</string>', f'<string name="app_name">{APP}</string>'),
    ("when RustDesk screen sharing", f"when {APP} screen sharing"),
    ("Keeps the RustDesk remote desktop", f"Keeps the {APP} remote desktop"),
])
edit(f"{res}/values/colors.xml", [
    ('<color name="primary">#FF0071FF</color>',
     '<color name="primary">#FF2572F8</color>\n    <color name="brand_bg">#FF0A0F1C</color>'),
])
edit(f"{res}/values/ic_launcher_background.xml", [
    ('<color name="ic_launcher_background">#ffffff</color>',
     '<color name="ic_launcher_background">#141414</color>'),
])
edit(f"{res}/drawable/launch_background.xml", [
    ('<item android:drawable="@android:color/white" />', '<item android:drawable="@color/brand_bg" />'),
])
edit(f"{res}/drawable-v21/launch_background.xml", [
    ('<item android:drawable="?android:colorBackground" />', '<item android:drawable="@color/brand_bg" />'),
])

# ------------------------------------------------- tema Flutter (MyTheme)
common = "flutter/lib/common.dart"
edit(common, [
    # acento azul / cian de la marca
    ("static const Color accent = Color(0xFF0071FF);", "static const Color accent = Color(0xFF2572F8);"),
    ("static const Color accent50 = Color(0x770071FF);", "static const Color accent50 = Color(0x772572F8);"),
    ("static const Color accent80 = Color(0xAA0071FF);", "static const Color accent80 = Color(0xAA2572F8);"),
    ("static const Color idColor = Color(0xFF00B6F0);", "static const Color idColor = Color(0xFF00ADFF);"),
    ("static const Color button = Color(0xFF2C8CFF);", "static const Color button = Color(0xFF2572F8);"),
    ("static const Color canvasColor = Color(0xFF212121);", "static const Color canvasColor = Color(0xFF141414);"),
    # tema claro: primario de la marca
    ("primary: Colors.blue, secondary: accent, background: grayBg),",
     "primary: accent, secondary: Color(0xFF00ADFF), background: grayBg),"),
    # tema oscuro: fondo azul noche
    ("hoverColor: Color.fromARGB(255, 45, 46, 53),", "hoverColor: Color(0xFF1A2540),"),
    ("scaffoldBackgroundColor: Color(0xFF18191E),", "scaffoldBackgroundColor: Color(0xFF0A0F1C),"),
    ("dialogBackgroundColor: Color(0xFF18191E),", "dialogBackgroundColor: Color(0xFF0F1626),"),
    ("backgroundColor: MaterialStatePropertyAll(Color(0xFF121212)))),",
     "backgroundColor: MaterialStatePropertyAll(Color(0xFF0A0F1C)))),"),
    ("""    colorScheme: ColorScheme.dark(
      primary: Colors.blue,
      secondary: accent,""", """    colorScheme: ColorScheme.dark(
      primary: accent,
      secondary: Color(0xFF00ADFF),"""),
    # superficies (tarjetas, campos, botones) del tema oscuro
    ("Color(0xFF24252B)", "Color(0xFF141C2F)"),
    # bordes con brillo azul
    ("""  static final dark = ColorThemeExtension(
    border: Color(0xFF555555),""", """  static final dark = ColorThemeExtension(
    border: Color(0xFF243A66),"""),
    # modo oscuro predeterminado ("system" sigue disponible si el usuario lo elige)
    ("""      case "dark":
        return ThemeMode.dark;
      default:
        return ThemeMode.system;""", """      case "dark":
        return ThemeMode.dark;
      case "system":
        return ThemeMode.system;
      default:
        return ThemeMode.dark;"""),
])

if errors:
    print("ERRORES de marca:\n  " + "\n  ".join(errors), file=sys.stderr)
    sys.exit(1)
print("Marca aplicada a las fuentes.")
