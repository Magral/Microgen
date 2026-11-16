"""Import the user's source archive into this repository; never replace CI."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import stat
import zipfile

PROTECTED = {".git", ".github", "ci"}

def import_source(root):
    root = Path(root).resolve()
    if (root / "project.godot").is_file():
        return {"ready": True, "imported": [], "archive": None}
    archives = [p for p in root.rglob("*.zip")
                if "source" in p.name.lower()
                and ".git" not in p.relative_to(root).parts]
    if not archives:
        return {"ready": False, "imported": [], "archive": None}
    if len(archives) != 1:
        raise ValueError("Upload exactly one source ZIP archive")
    archive = archives[0]
    with zipfile.ZipFile(archive) as z:
        infos = z.infolist()
        if len(infos) > 2000 or sum(i.file_size for i in infos) > 500_000_000:
            raise ValueError("Source archive is too large")
        for info in infos:
            path = PurePosixPath(info.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in info.filename:
                raise ValueError("Unsafe archive path")
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError("Archive symlinks are not supported")
        manifests = [i for i in infos if not i.is_dir()
                     and PurePosixPath(i.filename).name == "project.godot"]
        if len(manifests) != 1:
            raise ValueError("Archive must contain exactly one Godot project")
        prefix = PurePosixPath(manifests[0].filename).parts[:-1]
        pending = []
        seen = set()
        for info in infos:
            if info.is_dir():
                continue
            parts = PurePosixPath(info.filename).parts
            if parts[:len(prefix)] != prefix:
                continue
            relative = PurePosixPath(*parts[len(prefix):])
            if not relative.parts or relative.parts[0] in PROTECTED:
                continue
            if relative.as_posix() in seen:
                raise ValueError("Duplicate path in source archive")
            seen.add(relative.as_posix())
            destination = root.joinpath(*relative.parts)
            if not destination.resolve().is_relative_to(root):
                raise ValueError("Destination escapes repository")
            pending.append((info, destination, relative.as_posix()))
        imported = []
        for info, destination, relative in pending:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(z.read(info))
            imported.append(relative)
    return {"ready": (root / "project.godot").is_file(),
            "imported": imported, "archive": str(archive.relative_to(root))}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    report = import_source(args.root)
    Path(args.report).write_text(json.dumps(report), encoding="utf-8")
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as f:
            f.write("ready=" + str(report["ready"]).lower() + "\n")
            f.write("imported=" + str(bool(report["imported"])).lower() + "\n")
    print("Project ready" if report["ready"] else
          "Waiting: upload Microgen-0.1.0-source.zip to repository root")

if __name__ == "__main__":
    main()
