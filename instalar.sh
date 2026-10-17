#!/bin/bash
# Instalador del catalogo de juegos libres para EmuELEC
BASE="https://raw.githubusercontent.com/jfalvitez/Emuelec-free-games/refs/heads/main"
DIR="/storage/catalogo"
mkdir -p "$DIR/listas"

cat > "$DIR/generar.py" << 'PYEOF'
import glob
import json
import os
import re
import shutil

DIR = os.environ.get("CATALOGO_DIR", "/storage/catalogo")
ROMS = os.environ.get("ROMS_DIR", "/storage/roms")
RAIZ = os.path.join(ROMS, "ports_scripts", "Catalogo")
NOMBRES = {"nes": "NES", "snes": "SNES", "atarilynx": "Atari Lynx"}


def slug(t):
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")


def limpio(t):
    return re.sub(r'[\\/:*?"<>|]', "", t).strip()


shutil.rmtree(RAIZ, ignore_errors=True)
total = 0
for archivo in sorted(glob.glob(os.path.join(DIR, "listas", "*.jsonl"))):
    for linea in open(archivo, encoding="utf-8"):
        linea = linea.strip()
        if not linea:
            continue
        j = json.loads(linea)
        sistema = j["system"]
        carpeta = os.path.join(RAIZ, NOMBRES.get(sistema, sistema))
        os.makedirs(carpeta, exist_ok=True)
        ruta = os.path.join(carpeta, limpio(j["label"]) + ".sh")
        with open(ruta, "w") as s:
            s.write("#!/bin/bash\npython3 %s/descargar.py %s %s\n" % (DIR, sistema, slug(j["label"])))
        os.chmod(ruta, 0o755)
        total += 1
print("%d entradas creadas en %s" % (total, RAIZ))
PYEOF

cat > "$DIR/descargar.py" << 'PYEOF'
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile

DIR = os.environ.get("CATALOGO_DIR", "/storage/catalogo")
ROMS = os.environ.get("ROMS_DIR", "/storage/roms")
LOG = os.path.join(DIR, "log.txt")
EXT = {"nes": ".nes", "snes": ".sfc", "atarilynx": ".lnx"}
VALIDAS = {
    "nes": (".nes", ".unf", ".unif", ".fds"),
    "snes": (".sfc", ".smc", ".fig", ".swc", ".bs", ".st", ".bin"),
    "atarilynx": (".lnx", ".lyx", ".o"),
}


def log(m):
    with open(LOG, "a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + m + "\n")


def slug(t):
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")


def limpio(t):
    return re.sub(r'[\\/:*?"<>|]', "", t).strip()


def curl(url, salida):
    return subprocess.run(["curl", "-L", "-s", "-f", "-o", salida, url]).returncode


def main():
    sistema, clave = sys.argv[1], sys.argv[2]
    reg = None
    for linea in open(os.path.join(DIR, "listas", sistema + ".jsonl"), encoding="utf-8"):
        if linea.strip():
            j = json.loads(linea)
            if slug(j["label"]) == clave:
                reg = j
                break
    if not reg:
        log("NO ENCONTRADO: %s %s" % (sistema, clave))
        return
    nombre = limpio(reg["label"])
    destino = os.path.join(ROMS, sistema)
    os.makedirs(destino, exist_ok=True)
    for e in (".zip", EXT.get(sistema, ".bin")):
        if os.path.exists(os.path.join(destino, nombre + e)):
            log("YA ESTABA: " + nombre)
            return
    url = reg.get("url")
    if not url:
        if curl(reg["page"], "/tmp/pagina_catalogo.html") != 0:
            log("FALLO al abrir la pagina de " + nombre)
            return
        txt = open("/tmp/pagina_catalogo.html", encoding="utf-8", errors="ignore").read()
        m = re.search(r"download_file/(\d+)", txt)
        if not m:
            log("SIN ENLACE de descarga en la pagina de " + nombre)
            return
        url = "https://www.zophar.net/download_file/" + m.group(1)
    tmp = "/tmp/rom_catalogo"
    if curl(url, tmp) != 0 or not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
        log("FALLO la descarga de " + nombre)
        return
    with open(tmp, "rb") as f:
        cab = f.read(512)
    if b"<html" in cab.lower():
        log("FALLO (llego una pagina web, no el juego): " + nombre)
        os.remove(tmp)
        return
    ext = ".zip" if cab[:2] == b"PK" else EXT.get(sistema, ".bin")
    if ext == ".zip" and sistema in VALIDAS:
        try:
            dentro = zipfile.ZipFile(tmp).namelist()
        except Exception:
            log("FALLO (zip danado): " + nombre)
            os.remove(tmp)
            return
        if not any(n.lower().endswith(VALIDAS[sistema]) for n in dentro):
            log("NO ES UNA ROM de %s (el zip trae: %s): %s" % (sistema, ", ".join(dentro), nombre))
            os.remove(tmp)
            return
    shutil.move(tmp, os.path.join(destino, nombre + ext))
    log("OK: %s -> %s/%s%s" % (nombre, sistema, nombre, ext))


main()
PYEOF

for s in nes snes atarilynx; do
  curl -L -s -f -o "$DIR/listas/$s.jsonl" "$BASE/$s.jsonl" || echo "No pude bajar la lista $s"
done
python3 "$DIR/generar.py"
echo "Listo. Ahora en EmuELEC: Start > Game Settings > Update Gamelists, y busca Ports > Catalogo."
