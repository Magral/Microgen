"""Remove non-runtime native symbols before Android alignment and signing."""
import argparse
import re
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZipFile

NATIVE_LIBRARY = re.compile(r"lib/arm64-v8a/[^/]+\.so")
SIGNATURE = re.compile(r"META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))", re.IGNORECASE)
DEBUG_SECTION = re.compile(r"\.(?:z?debug_[^\s]+|symtab|gnu_debugdata|gnu_debuglink)\s")


def strip_apk(source, destination, strip, readelf):
    count = 0
    with ZipFile(source) as original, ZipFile(destination, "w") as output:
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / "library.so"
            for info in original.infolist():
                if SIGNATURE.fullmatch(info.filename):
                    continue
                data = original.read(info)
                if NATIVE_LIBRARY.fullmatch(info.filename):
                    size = len(data)
                    library.write_bytes(data)
                    subprocess.run([strip, "--strip-unneeded", "--remove-section=.gnu_debuglink", "--remove-section=.gnu_debugdata", library], check=True)
                    sections = subprocess.check_output([readelf, "--sections", "--wide", library], text=True)
                    if DEBUG_SECTION.search(sections):
                        raise RuntimeError(f"Debug sections remain in {info.filename}")
                    if ".dynsym" not in sections:
                        raise RuntimeError(f"Runtime symbols missing in {info.filename}")
                    data = library.read_bytes()
                    print(f"{info.filename}: {size:,} -> {len(data):,} bytes")
                    count += 1
                # Alignment is restored by zipalign after the ZIP is rewritten.
                info.extra = b""
                output.writestr(info, data)
    if count == 0:
        raise RuntimeError("No ARM64 native libraries were found")
    print(f"APK before signing: {source.stat().st_size:,} -> {destination.stat().st_size:,} bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--strip", required=True)
    parser.add_argument("--readelf", required=True)
    args = parser.parse_args()
    strip_apk(args.source, args.destination, args.strip, args.readelf)
