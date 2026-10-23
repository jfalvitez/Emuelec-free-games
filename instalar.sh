#!/bin/bash
# Free games catalog installer for EmuELEC
BASE="https://raw.githubusercontent.com/jfalvitez/Emuelec-free-games/refs/heads/main"
DIR="/storage/catalog"

# Remove the previous install (old Spanish-named folders). Downloaded games are not touched.
rm -rf /storage/catalogo /storage/roms/ports_scripts/Catalogo

mkdir -p "$DIR/lists"
echo "$BASE" > "$DIR/base_url.txt"

cat > "$DIR/generate.py" << 'PYEOF'
import glob
import json
import os
import re
import shutil

DIR = os.environ.get("CATALOG_DIR", "/storage/catalog")
ROMS = os.environ.get("ROMS_DIR", "/storage/roms")
ROOT = os.path.join(ROMS, "ports_scripts", "Catalog")
NAMES = {"nes": "NES", "snes": "SNES", "atarilynx": "Atari Lynx"}


def slug(t):
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")


def clean(t):
    return re.sub(r'[\\/:*?"<>|]', "", t).strip()


shutil.rmtree(ROOT, ignore_errors=True)
os.makedirs(ROOT, exist_ok=True)
total = 0
skipped = 0
for path in sorted(glob.glob(os.path.join(DIR, "lists", "*.jsonl"))):
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        try:
            j = json.loads(line)
            system = j["system"]
            label = j["label"]
        except Exception:
            skipped += 1
            continue
        folder = os.path.join(ROOT, NAMES.get(system, system))
        os.makedirs(folder, exist_ok=True)
        entry = os.path.join(folder, clean(label) + ".sh")
        with open(entry, "w") as f:
            f.write("#!/bin/bash\npython3 %s/download.py %s %s\n" % (DIR, system, slug(label)))
        os.chmod(entry, 0o755)
        total += 1

upd = os.path.join(ROOT, "Update Catalog.sh")
with open(upd, "w") as f:
    f.write("#!/bin/bash\npython3 %s/update.py\n" % DIR)
os.chmod(upd, 0o755)
print("%d entries created in %s (%d invalid lines skipped)" % (total, ROOT, skipped))
PYEOF

cat > "$DIR/download.py" << 'PYEOF'
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile

DIR = os.environ.get("CATALOG_DIR", "/storage/catalog")
ROMS = os.environ.get("ROMS_DIR", "/storage/roms")
LOG = os.path.join(DIR, "log.txt")
EXT = {"nes": ".nes", "snes": ".sfc", "atarilynx": ".lnx"}
VALID = {
    "nes": (".nes", ".unf", ".unif", ".fds"),
    "snes": (".sfc", ".smc", ".fig", ".swc", ".bs", ".st", ".bin"),
    "atarilynx": (".lnx", ".lyx", ".o"),
}


def log(m):
    with open(LOG, "a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + m + "\n")


def slug(t):
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")


def clean(t):
    return re.sub(r'[\\/:*?"<>|]', "", t).strip()


def reload_menu():
    # Restart EmulationStation so it sees the new game
    if os.environ.get("CATALOG_NO_RELOAD"):
        return
    subprocess.Popen(["systemctl", "restart", "emustation"], start_new_session=True)


def curl(url, out):
    return subprocess.run(["curl", "-L", "-s", "-f", "-o", out, url]).returncode


def main():
    system, key = sys.argv[1], sys.argv[2]
    rec = None
    for line in open(os.path.join(DIR, "lists", system + ".jsonl"), encoding="utf-8"):
        if line.strip():
            try:
                j = json.loads(line)
            except Exception:
                continue
            if slug(j["label"]) == key:
                rec = j
                break
    if not rec:
        log("NOT FOUND: %s %s" % (system, key))
        return
    name = clean(rec["label"])
    dest = os.path.join(ROMS, system)
    os.makedirs(dest, exist_ok=True)
    for e in (".zip", EXT.get(system, ".bin")):
        if os.path.exists(os.path.join(dest, name + e)):
            log("ALREADY INSTALLED: " + name)
            return
    url = rec.get("url")
    if not url:
        if curl(rec["page"], "/tmp/catalog_page.html") != 0:
            log("FAILED to open the page of " + name)
            return
        txt = open("/tmp/catalog_page.html", encoding="utf-8", errors="ignore").read()
        m = re.search(r"download_file/(\d+)", txt)
        if not m:
            log("NO DOWNLOAD LINK on the page of " + name)
            return
        url = "https://www.zophar.net/download_file/" + m.group(1)
    tmp = "/tmp/catalog_rom"
    if curl(url, tmp) != 0 or not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
        log("FAILED download of " + name)
        return
    with open(tmp, "rb") as f:
        head = f.read(512)
    if b"<html" in head.lower():
        log("FAILED (got a web page instead of the game): " + name)
        os.remove(tmp)
        return
    ext = ".zip" if head[:2] == b"PK" else EXT.get(system, ".bin")
    if ext == ".zip" and system in VALID:
        try:
            inside = zipfile.ZipFile(tmp).namelist()
        except Exception:
            log("FAILED (damaged zip): " + name)
            os.remove(tmp)
            return
        if not any(n.lower().endswith(VALID[system]) for n in inside):
            log("NOT A %s ROM (zip contains: %s): %s" % (system, ", ".join(inside), name))
            os.remove(tmp)
            return
    shutil.move(tmp, os.path.join(dest, name + ext))
    log("OK: %s -> %s/%s%s" % (name, system, name, ext))
    reload_menu()


main()
PYEOF

cat > "$DIR/update.py" << 'PYEOF'
import glob
import json
import os
import shutil
import subprocess
import sys
import time

DIR = os.environ.get("CATALOG_DIR", "/storage/catalog")
LOG = os.path.join(DIR, "log.txt")


def log(m):
    with open(LOG, "a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + m + "\n")


def curl(url, out):
    return subprocess.run(["curl", "-L", "-s", "-f", "-o", out, url]).returncode


def check(path):
    good = 0
    bad = []
    for n, line in enumerate(open(path, encoding="utf-8", errors="ignore"), 1):
        line = line.strip()
        if not line:
            continue
        try:
            j = json.loads(line)
            j["label"]
            j["system"]
            good += 1
        except Exception:
            bad.append(n)
    return good, bad


def main():
    base = open(os.path.join(DIR, "base_url.txt")).read().strip()
    names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(DIR, "lists", "*.jsonl")))
    for name in names:
        tmp = "/tmp/catalog_" + name
        url = base + "/" + name
        if base.startswith("http"):
            url += "?t=%d" % int(time.time())
        if curl(url, tmp) != 0:
            log("UPDATE FAILED to download " + name + " (kept the old list)")
            continue
        good, bad = check(tmp)
        if good == 0:
            log("UPDATE SKIPPED " + name + ": no valid lines (kept the old list)")
            continue
        shutil.move(tmp, os.path.join(DIR, "lists", name))
        msg = "UPDATED %s (%d games)" % (name, good)
        if bad:
            msg += " - invalid lines ignored: " + ",".join(str(b) for b in bad)
        log(msg)
    subprocess.run([sys.executable, os.path.join(DIR, "generate.py")])
    if not os.environ.get("CATALOG_NO_RELOAD"):
        subprocess.Popen(["systemctl", "restart", "emustation"], start_new_session=True)


main()
PYEOF

for s in nes snes atarilynx; do
  curl -L -s -f -o "$DIR/lists/$s.jsonl" "$BASE/$s.jsonl?t=$(date +%s)" || echo "Could not download the $s list"
done
python3 "$DIR/generate.py"
systemctl restart emustation
echo "Done. Open Ports > Catalog. Use 'Update Catalog' there to refresh the lists."
