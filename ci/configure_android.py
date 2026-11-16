import json
import os
from pathlib import Path
import re
import subprocess

def main():
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    java = os.environ.get("JAVA_HOME")
    if not sdk or not java:
        raise RuntimeError("Android SDK and Java paths must be provided")
    sdk = Path(sdk)
    manager = sdk / "cmdline-tools/latest/bin/sdkmanager"
    subprocess.run([str(manager), "--licenses"], input="y\n" * 200, text=True, check=True,
                   stdout=subprocess.DEVNULL)
    subprocess.run([str(manager), "platform-tools", "build-tools;35.0.1", "platforms;android-36"],
                   check=True)
    config_root = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    settings = config_root / "godot/editor_settings-4.6.tres"
    if not settings.is_file():
        raise RuntimeError("Run Godot editor import before configuring Android")
    text = settings.read_text(encoding="utf-8")
    values = {"export/android/java_sdk_path": java,
              "export/android/android_sdk_path": str(sdk)}
    for key, value in values.items():
        line = key + " = " + json.dumps(value)
        pattern = re.compile(r"^" + re.escape(key) + r" = .*", re.MULTILINE)
        if pattern.search(text):
            text = pattern.sub(lambda match: line, text)
        else:
            text += "\n" + line + "\n"
    settings.write_text(text, encoding="utf-8")

if __name__ == "__main__":
    main()
