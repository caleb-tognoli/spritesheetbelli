"""Builds the native library and copies it where extension/sbelli_native.gdextension
looks for it, with the licenses of the crates in it (see write_licenses). Run from
anywhere: python native/build.py [--debug]

On macOS it builds for Apple Silicon and Intel and joins them into one library."""

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

NATIVE = Path(__file__).resolve().parent
BIN = NATIVE.parent / "extension" / "bin"
MACOS_TARGETS = ["aarch64-apple-darwin", "x86_64-apple-darwin"]
## Shown in About > Licenses, see ui/main/about_dialog.gd
LICENSES = BIN / "native_licenses.txt"
## License texts of crates that don't ship theirs, by the start of their names
LICENSE_FALLBACKS = {"godot": "MPL-2.0.txt", "objc2": "objc2-MIT.txt"}


def cargo_build(profile: str, target: str | None) -> Path:
    command = ["cargo", "build", "--locked"]
    if profile == "release":
        command.append("--release")
    if target:
        command += ["--target", target]
    subprocess.run(command, cwd=NATIVE, check=True)
    out = Path(os.environ.get("CARGO_TARGET_DIR", NATIVE / "target"))
    if target:
        out /= target
    return out / profile


def write_licenses() -> None:
    """Lists the crates built into the library on any platform, and their license texts.
    Proc macros and build dependencies only run while building, so they aren't listed."""
    metadata = json.loads(
        subprocess.run(
            ["cargo", "metadata", "--format-version", "1", "--locked"],
            cwd=NATIVE,
            check=True,
            capture_output=True,
        ).stdout
    )
    packages = {p["id"]: p for p in metadata["packages"]}
    nodes = {n["id"]: n for n in metadata["resolve"]["nodes"]}
    built: set[str] = set()
    pending = [metadata["resolve"]["root"]]
    while pending:
        for dep in nodes[pending.pop()]["deps"]:
            package = packages[dep["pkg"]]
            normal = any(kind["kind"] is None for kind in dep["dep_kinds"])
            macro = any("proc-macro" in t["kind"] for t in package["targets"])
            if normal and not macro and dep["pkg"] not in built:
                built.add(dep["pkg"])
                pending.append(dep["pkg"])

    crates = sorted((packages[i] for i in built), key=lambda p: p["name"])
    lines = ["Libraries of the native extension", ""]
    texts: dict[str, list[str]] = {}
    for crate in crates:
        lines.append(f"{crate['name']} {crate['version']}: {crate['license']}, {crate['repository']}")
        folder = Path(crate["manifest_path"]).parent
        files = sorted(
            f for f in folder.iterdir() if f.name.upper().startswith(("LICEN", "COPYING", "NOTICE"))
        )
        if not files:
            fallback = next(v for k, v in LICENSE_FALLBACKS.items() if crate["name"].startswith(k))
            files = [NATIVE / "licenses" / fallback]
        for file in files:
            text = file.read_text(encoding="utf-8").strip()
            texts.setdefault(text, []).append(crate["name"])
    for text, names in texts.items():
        lines += ["", "", "Used by " + ", ".join(dict.fromkeys(names)), "", text]
    LICENSES.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", action="store_true", help="build without optimizations")
    profile = "debug" if parser.parse_args().debug else "release"
    BIN.mkdir(parents=True, exist_ok=True)
    write_licenses()

    system = platform.system()
    if system == "Windows":
        built = cargo_build(profile, None) / "sbelli_native.dll"
        shutil.copy2(built, BIN / "sbelli_native.windows.x86_64.dll")
    elif system == "Linux":
        built = cargo_build(profile, None) / "libsbelli_native.so"
        shutil.copy2(built, BIN / "libsbelli_native.linux.x86_64.so")
    elif system == "Darwin":
        parts = [cargo_build(profile, t) / "libsbelli_native.dylib" for t in MACOS_TARGETS]
        out = BIN / "libsbelli_native.macos.dylib"
        subprocess.run(["lipo", "-create", *map(str, parts), "-output", str(out)], check=True)
    else:
        sys.exit(f"No native library for {system}")


if __name__ == "__main__":
    main()
