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

def display_command():
    return [] if os.environ.get("DISPLAY") else ["xvfb-run", "-a"]

def main():
    env = os.environ
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    for name in ["core", "simulation", "genome", "ui", "input_regions", "jelly", "fluid", "harvest", "absorption", "organic_fx", "pigment", "growth_contact", "tissue_damage"]:
        path = "tests/test_" + name + ".gd"
        if Path(path).is_file():
            run(name, ["godot", "--headless", "--path", ".", "--script", path])
    if Path("tests/test_touch.gd").is_file():
        run("touch", display_command() + ["godot", "--path", ".",
                      "--audio-driver", "Dummy", "--script", "tests/test_touch.gd"])

    if Path("core/genome.gd").is_file():
        for mode in ["game", "gallery"]:
            target = str(Path("build/Microgen-" + mode + ".png").resolve())
            run("render-" + mode, display_command() + ["godot", "--path", ".",
                "--audio-driver", "Dummy", "--", "--preview=" + mode, "--capture=" + target])

    if Path("core/genome.gd").is_file():
        run("motion", display_command() + ["godot", "--path", ".", "--audio-driver", "Dummy",
            "--write-movie", "build/Microgen-motion.avi", "--fixed-fps", "30", "--quit-after", "360",
            "--", "--preview=organic"])
        run("encode-motion", ["ffmpeg", "-y", "-i", "build/Microgen-motion.avi", "-an",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "24", "build/Microgen-motion.mp4"])
        Path("build/Microgen-motion.avi").unlink()

if __name__ == "__main__":
    main()
