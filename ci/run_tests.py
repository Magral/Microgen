"""Godot sometimes exits zero after a script error: inspect logs as well."""
from pathlib import Path
import os
import re
import subprocess

ERRORS = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:)|Assertion failed")

def run(name, command):
    print("+", " ".join(command), flush=True)
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=90)
    Path("build/logs").mkdir(parents=True, exist_ok=True)
    Path("build/logs/" + name + ".log").write_text(result.stdout, encoding="utf-8")
    print(result.stdout, flush=True)
    if result.returncode != 0 or ERRORS.search(result.stdout):
        raise RuntimeError(name + " failed")

def main():
    env = os.environ
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    for name in ["core", "simulation", "genome", "ui"]:
        path = "tests/test_" + name + ".gd"
        if Path(path).is_file():
            run(name, ["godot", "--headless", "--path", ".", "--script", path])
    if Path("tests/test_touch.gd").is_file():
        run("touch", ["xvfb-run", "-a", "godot", "--path", ".",
                      "--audio-driver", "Dummy", "--script", "tests/test_touch.gd"])

if __name__ == "__main__":
    main()
