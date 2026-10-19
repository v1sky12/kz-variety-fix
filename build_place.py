"""Rebuild active Source arrays; preserve geometry, backups and other data."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

from rbxl_container import add_module_script, chunks, property_header, public_report, replace_source_arrays, validate

ROOT = Path(__file__).resolve().parent
PACKAGE_FILES = ("INSTALL_KZ_VARIETY_FIX.md", "PLAYTEST_RU.md", "BLOCKS_RU.md", "PHYSICS_RU.md", "special_blocks_audit.json", "install_kz_variety_fix.py", "rbxl_container.py", "requirements.txt")


def verify_sources(data: bytes, compiler: Path | None = None) -> dict:
    report = validate(data)
    manifest = json.loads((ROOT / "src/manifest.json").read_text())
    for filename, target in manifest.items():
        instance = target["id"]
        if report["paths"].get(instance) != target["path"]:
            raise ValueError(f"instance/path mismatch: {filename}")
        if report["sources"][instance] != (ROOT / "src" / filename).read_bytes():
            raise ValueError(f"place has stale source: {filename}")
    if report["disabled"].get(16976) is not True or report["disabled"].get(16977) is not False:
        raise ValueError("expected exactly one active movement motor")
    if compiler is not None:
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for instance, source in report["sources"].items():
                path = Path(directory) / f"{instance}.luau"
                path.write_bytes(source)
                paths.append(str(path))
            subprocess.run([str(compiler.resolve()), "--null", *paths], check=True, stdout=subprocess.DEVNULL)
        report["compiled_scripts"] = report["scripts"]
    return public_report(report)


def build(base: bytes) -> bytes:
    manifest = json.loads((ROOT / "src/manifest.json").read_text())
    before = validate(base)
    for filename, target in manifest.items():
        create = target.get("create")
        if target["id"] not in before["paths"] and create:
            if create["class"] != "ModuleScript":
                raise ValueError("only explicit ModuleScript additions are supported")
            base = add_module_script(base, target["id"], create["parent"], target["path"].rsplit("/", 1)[1],
                                     (ROOT / "src" / filename).read_bytes())
            before = validate(base)
    replacements = {}
    for filename, target in manifest.items():
        if before["paths"].get(target["id"]) != target["path"]:
            raise ValueError(f"wrong base place for {filename}")
        replacements[target["id"]] = (ROOT / "src" / filename).read_bytes()
    result = replace_source_arrays(base, replacements)
    after = validate(result)
    if before["paths"] != after["paths"] or before["disabled"] != after["disabled"]:
        raise ValueError("build changed place structure or script activation")
    for instance, source in before["sources"].items():
        if instance not in replacements and source != after["sources"][instance]:
            raise ValueError(f"backup source changed: {instance}")
    for old, new in zip(chunks(base), chunks(result), strict=True):
        if old.encoded != new.encoded:
            if old.tag != b"PROP" or property_header(old.payload)[1] != b"Source":
                raise ValueError("build modified non-Source data")
    verify_sources(result)
    return result


def make_zip(data: bytes, path: Path) -> None:
    verify_sources(data)
    members = {"kz_variety_fix.rbxl": data}
    for name in PACKAGE_FILES:
        members[name] = (ROOT / name).read_bytes()
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in members.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 19, 0, 0, 0))
            archive.writestr(info, content, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None or archive.read("kz_variety_fix.rbxl") != data:
            raise ValueError("ZIP verification failed")


def verify_rojo(data: bytes, executable: Path) -> str:
    """Independently deserialize the full place with Rojo's rbx_binary reader."""
    version = subprocess.check_output([str(executable.resolve()), "--version"], text=True).strip()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "src").mkdir()
        project = root / "default.project.json"
        project.write_text(json.dumps({"name": "KZFormatCheck", "syncbackRules": {"ignoreTrees": [""]},
                                       "tree": {"$className": "DataModel", "$path": "src"}}))
        place = root / "check.rbxl"
        place.write_bytes(data)
        # syncback deserializes before applying ignoreTrees. Ignore the export:
        # valid Roblox siblings can share names, which a Rojo project forbids.
        # Dry-run additionally prevents all filesystem mutations.
        result = subprocess.run([str(executable.resolve()), "syncback", str(project), "--input", str(place),
                                 "--dry-run", "--non-interactive"], capture_output=True, text=True)
        if result.returncode:
            raise ValueError("Rojo rejected the place:\n" + result.stderr)
    return version


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=ROOT / "kz_variety_fix.rbxl")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--luau-compile", type=Path)
    parser.add_argument("--rojo", type=Path, help="independent full RBXL deserialization")
    args = parser.parse_args()
    data = args.base.read_bytes()
    if not args.check:
        data = build(data)
    report = verify_sources(data, args.luau_compile)
    if args.rojo:
        report["rojo_validated"] = True
        report["rojo_version"] = verify_rojo(data, args.rojo)
    if not args.check:
        (ROOT / "kz_variety_fix.rbxl").write_bytes(data)
        make_zip(data, ROOT / "kz_variety_fix_updated.zip")
    else:
        with zipfile.ZipFile(ROOT / "kz_variety_fix_updated.zip") as archive:
            if archive.testzip() is not None or archive.read("kz_variety_fix.rbxl") != data:
                raise ValueError("stale or corrupt ZIP")
            for name in PACKAGE_FILES:
                if archive.read(name) != (ROOT / name).read_bytes():
                    raise ValueError(f"stale ZIP helper: {name}")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
