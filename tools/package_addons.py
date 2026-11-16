"""Build or check the standalone ZIP downloads for this collection."""

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, BadZipFile, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS = ROOT / "downloads"


def package_files(toc):
    folder = toc.parent
    files = {}
    for path in sorted(folder.rglob("*")):
        relative = path.relative_to(folder)
        if any(part.startswith(".") or part == "__pycache__" for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f"{path} is a symlink. Include the distributable file in the addon folder.")
        if path.is_file() and path.name.lower() not in {"thumbs.db", "desktop.ini"}:
            files[relative.as_posix()] = path

    lines = toc.read_text(encoding="utf-8-sig").splitlines()
    version = None
    for line in lines:
        line = line.strip()
        if line.lower().startswith("## version:"):
            version = line.partition(":")[2].strip()
        if line and not line.startswith("#") and line.replace("\\", "/") not in files:
            raise ValueError(f"{toc.name} references a missing file: {line}")
    if not version or not re.fullmatch(r"[\w][\w.+-]*", version, re.ASCII):
        raise ValueError(f"Missing or invalid ## Version in {toc.name}")
    if "README.md" not in files:
        raise ValueError(f"Missing install guide in {folder.name}")
    return DOWNLOADS / f"{folder.name}-{version}.zip", {
        f"{folder.name}/{name}": path for name, path in files.items()
    }


def release_bytes(path):
    data = path.read_bytes()
    if path.suffix.lower() in {".toc", ".lua", ".xml", ".md", ".txt"}:
        # Match the repository's LF checkout even after a Windows editor saves CRLF.
        return data.replace(b"\r\n", b"\n")
    return data


def verify_archive(archive, files):
    with ZipFile(archive) as package:
        if sorted(package.namelist()) != sorted(files):
            raise ValueError(f"{archive.name} has different files from the addon folder")
        for name, source in files.items():
            if package.read(name) != release_bytes(source):
                raise ValueError(f"{archive.name} contains a different version of {name}")


def build_archive(destination, files):
    destination.parent.mkdir(exist_ok=True)
    # Build and check the replacement before exposing it as a download.
    with tempfile.NamedTemporaryFile(dir=destination.parent, suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
    try:
        with ZipFile(temporary, "w") as package:
            for name, source in files.items():
                # Fixed metadata keeps local timestamps and permissions out of releases.
                entry = ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                package.writestr(entry, release_bytes(source), compress_type=ZIP_DEFLATED)
        verify_archive(temporary, files)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("addons", nargs="*", help="addon folder names (default: all)")
    parser.add_argument("--check", action="store_true", help="verify existing ZIPs without changing them")
    args = parser.parse_args()
    manifests = {p.stem: p for p in sorted(ROOT.glob("*/*.toc")) if p.stem == p.parent.name}
    if not manifests:
        parser.error("no addon manifests found")
    unknown = set(args.addons) - manifests.keys()
    if unknown:
        parser.error(f"unknown addon(s): {', '.join(sorted(unknown))}")
    for name in args.addons or manifests:
        destination, files = package_files(manifests[name])
        if args.check:
            verify_archive(destination, files)
        else:
            build_archive(destination, files)
        print(f"Verified {destination.relative_to(ROOT)} ({len(files)} files)")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, BadZipFile) as error:
        sys.exit(str(error))
