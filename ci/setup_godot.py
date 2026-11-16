"""Install the exact official engine and APK templates, verifying SHA-256."""
import hashlib
import os
from pathlib import Path
import shutil
import urllib.request
import zipfile

VERSION = "4.6.3"
ASSETS = {
    "Godot_v4.6.3-stable_linux.x86_64.zip":
        "d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3",
    "Godot_v4.6.3-stable_export_templates.tpz":
        "3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8",
}

def download(name, expected, directory):
    target = directory / name
    url = "https://github.com/godotengine/godot/releases/download/4.6.3-stable/" + name
    request = urllib.request.Request(url, headers={"User-Agent": "Microgen-CI"})
    digest = hashlib.sha256()
    with urllib.request.urlopen(request, timeout=180) as response, target.open("wb") as f:
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
            f.write(block)
    if digest.hexdigest() != expected:
        raise RuntimeError("Checksum mismatch: " + name)
    return target

def main():
    temporary = Path(os.environ["RUNNER_TEMP"]) / "microgen-godot"
    temporary.mkdir(parents=True, exist_ok=True)
    binary_dir = temporary / "bin"
    binary_dir.mkdir(exist_ok=True)
    names = list(ASSETS)
    engine = download(names[0], ASSETS[names[0]], temporary)
    with zipfile.ZipFile(engine) as z:
        binary_name = "Godot_v4.6.3-stable_linux.x86_64"
        with z.open(binary_name) as src, (binary_dir / "godot").open("wb") as dst:
            shutil.copyfileobj(src, dst)
    (binary_dir / "godot").chmod(0o755)
    template_zip = download(names[1], ASSETS[names[1]], temporary)
    data = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    templates = data / "godot/export_templates/4.6.3.stable"
    templates.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(template_zip) as z:
        for name in ["android_debug.apk", "android_release.apk"]:
            with z.open("templates/" + name) as src, (templates / name).open("wb") as dst:
                shutil.copyfileobj(src, dst)
    with open(os.environ["GITHUB_PATH"], "a", encoding="utf-8") as f:
        f.write(str(binary_dir) + "\n")
    print("Installed official Godot 4.6.3 and Android templates")

if __name__ == "__main__":
    main()
