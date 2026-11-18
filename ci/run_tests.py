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
    for name in ["core", "simulation", "genome", "ui", "input_regions", "jelly", "fluid", "harvest", "absorption", "organic_fx", "pigment", "growth_contact", "tissue_damage", "size_rules", "mouth_shape", "fragment_shape", "combat_pacing", "new_content", "development", "audio", "fx_style", "sustained_play", "radial_boundary", "organic_volume", "environment", "water_depth", "substrate_mesh", "progression", "combat_stats", "reward_simulation", "ui_rewards", "reward_view", "living_mutations", "cyst_reveal", "functional_evolutions", "genome_legacy", "run_loadout", "genome_view", "updates", "foundation_flow", "volume_reuse", "home_layout", "mobile_display", "organism_slots", "families", "organism_equipment", "capacity_run", "family_body_view", "lineage_flow", "organ_identity", "legacy_panel", "family_write_failure"]:
        path = "tests/test_" + name + ".gd"
        if Path(path).is_file():
            run(name, ["godot", "--headless", "--path", ".", "--script", path])
    if Path("tests/test_touch.gd").is_file():
        run("touch", display_command() + ["godot", "--path", ".",
                      "--audio-driver", "Dummy", "--script", "tests/test_touch.gd"])

    env["MICROGEN_HOME_CAPTURE"] = str(Path("build/Microgen-home.png").resolve())
    run("scroll-touch", display_command() + ["godot", "--path", ".", "--audio-driver", "Dummy", "--script", "tests/test_scroll_touch.gd"])
    run("home-native", display_command() + ["godot", "--path", ".", "--audio-driver", "Dummy", "--script", "tests/test_home_layout.gd"])
    env.pop("MICROGEN_HOME_CAPTURE", None)

    run("tendril-native", display_command() + ["godot", "--path", ".", "--audio-driver", "Dummy", "--script", "tests/test_tendril_shape.gd"])

    run("family-native", display_command() + ["godot", "--path", ".", "--audio-driver", "Dummy", "--script", "tests/test_family_native.gd"])

    run("evolution-art", display_command() + ["godot", "--path", ".", "--audio-driver", "Dummy", "--script", "tests/test_evolution_art.gd"])

    run("mutation-art", display_command() + ["godot", "--path", ".", "--audio-driver", "Dummy", "--script", "tests/test_mutation_art.gd"])

    run("render-cache", display_command() + ["godot", "--path", ".", "--audio-driver", "Dummy", "--script", "tests/test_render_cache.gd"])

    if Path("core/genome.gd").is_file():
        for mode in ["game", "boss-fight", "boss-reward", "gallery", "development", "codex", "jaw", "habitat", "rewards", "feedback", "journal", "mutations", "cyst", "foundation-start", "foundation-genome", "inheritance"]:
            target = str(Path("build/Microgen-" + mode + ".png").resolve())
            run("render-" + mode, display_command() + ["godot", "--path", ".",
                "--audio-driver", "Dummy", "--", "--preview=" + mode, "--capture=" + target])


if __name__ == "__main__":
    main()
