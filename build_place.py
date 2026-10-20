"""Apply declared map repairs and rebuild active Source arrays safely."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

from rbxl_container import (add_module_script, append_block_model, audit_kz_runtime, chunks, declarations, property_header,
                            property_values, public_report, replace_scene_properties, replace_source_arrays, validate,
                            decode_references, uint)

ROOT = Path(__file__).resolve().parent
VERSIONED_ZIP = "kz_variety_fix_V7_21.zip"
PACKAGE_FILES = ("INSTALL_KZ_VARIETY_FIX.md", "PLAYTEST_RU.md", "BLOCKS_RU.md", "PHYSICS_RU.md", "SCENE_CHANGES_RU.md",
                 "scene/placements.json", "scene/route_blocks.json", "scene/manifest.json", "special_blocks_audit.json",
                 "install_kz_variety_fix.py", "rbxl_container.py", "requirements.txt")


def scene_manifest() -> dict:
    return json.loads((ROOT / "scene/manifest.json").read_text())


def verify_scene(data: bytes) -> dict:
    manifest = scene_manifest()
    edits = {int(ref): edit for ref, edit in manifest["edits"].items()}
    if replace_scene_properties(data, (ROOT / "scene/property_edits.rbxm").read_bytes(), edits) != data:
        raise ValueError("place has stale scene properties")
    for addition in manifest["additions"]:
        verify_scene_subtree(data, manifest, addition)
    return {"placed_original_zones": manifest["originalZones"], "practice_reset_zones": 2,
            "verified_bhop_supports": manifest["verifiedBhopSupports"], "water_openings": 1,
            "visible_route_blocks": manifest["visibleRouteBlocks"]}


def verify_scene_subtree(data: bytes, manifest: dict, addition: dict) -> None:
    expected_model = (ROOT / "scene" / addition["file"]).read_bytes()
    expected, actual = validate(expected_model), validate(data)
    prefix = manifest["mapPath"] + "/"
    root = prefix + addition["rootName"]
    existing = {path.removeprefix(prefix): ref for ref, path in actual["paths"].items()
                if path == root or path.startswith(root + "/")}
    if set(existing) != set(expected["paths"].values()):
        raise ValueError("block placement subtree differs from its declared model")
    def values(container: bytes, selected: set[int]) -> dict:
        classes = declarations(container)
        result = {}
        for chunk in chunks(container):
            if chunk.tag == b"PROP":
                cid, name, kind, _ = property_header(chunk.payload)
                ids = classes[cid][1]
                if selected.intersection(ids):
                    for ref, value in zip(ids, property_values(chunk.payload, len(ids))):
                        if ref in selected:
                            result[ref, name] = (kind, value)
        return result
    expected_values = values(expected_model, set(expected["paths"]))
    actual_values = values(data, set(existing.values()))
    for (ref, name), value in expected_values.items():
        target = existing[expected["paths"][ref]]
        if actual_values.get((target, name)) != value:
            raise ValueError(f"block placement property differs: {expected['paths'][ref]} / {name!r}")


def apply_scene(data: bytes) -> bytes:
    manifest = scene_manifest()
    data = replace_scene_properties(data, (ROOT / "scene/property_edits.rbxm").read_bytes(),
                                    {int(ref): edit for ref, edit in manifest["edits"].items()})
    for addition in manifest["additions"]:
        paths = validate(data)["paths"]
        root = manifest["mapPath"] + "/" + addition["rootName"]
        if root not in paths.values():
            data = append_block_model(data, (ROOT / "scene" / addition["file"]).read_bytes(), manifest["mapId"], addition["rootName"])
    verify_scene(data)
    return data


def verify_preservation(base: bytes, result: bytes) -> dict:
    """Prove every old instance/property survives outside declared edits."""
    before, after = validate(base), validate(result)
    if any(after["paths"].get(ref) != path for ref, path in before["paths"].items()):
        raise ValueError("build moved or removed an original instance")
    manifest = json.loads((ROOT / "src/manifest.json").read_text())
    source_ids = {target["id"] for target in manifest.values()}
    scene = scene_manifest()
    allowed = {(int(ref), name.encode()) for ref, edit in scene["edits"].items() for name in edit["properties"]}
    if any(before["paths"][ref] != scene["mapPath"] and not before["paths"][ref].startswith(scene["mapPath"] + "/") for ref, _ in allowed):
        raise ValueError("scene edit targets a protected map or backup")
    def indexed(data):
        inst, props, parents, opaque = {}, {}, {}, []
        for chunk in chunks(data):
            if chunk.tag == b"INST":
                inst[uint(chunk.payload, 0)] = chunk.payload
            elif chunk.tag == b"PROP":
                cid, name, _, _ = property_header(chunk.payload)
                if (cid, name) in props:
                    raise ValueError("duplicate property array")
                props[cid, name] = chunk.payload
            elif chunk.tag == b"PRNT":
                count = uint(chunk.payload, 1)
                refs = decode_references(chunk.payload[5:5 + count * 4], count)
                values = decode_references(chunk.payload[5 + count * 4:], count)
                parents.update(zip(refs, values))
            else:
                opaque.append((chunk.tag, chunk.payload))
        return inst, props, parents, opaque
    oi, op, parent_before, opaque_before = indexed(base)
    ni, np, parent_after, opaque_after = indexed(result)
    if any(ni.get(cid) != payload for cid, payload in oi.items()) or opaque_before != opaque_after:
        raise ValueError("build altered an original declaration or opaque chunk")
    if any(parent_after.get(ref) != parent for ref, parent in parent_before.items()):
        raise ValueError("build reparented an original instance")
    if any(key[0] in oi and key not in op for key in np):
        raise ValueError("build added an undeclared property to an original class group")
    classes = declarations(base)
    changed_sources, changed_properties = set(), []
    for (cid, name), payload in op.items():
        if (cid, name) not in np:
            raise ValueError("build removed an original property array")
        replacement = np[cid, name]
        if replacement == payload:
            continue
        if property_header(payload)[2] != property_header(replacement)[2]:
            raise ValueError("build changed an original property type")
        refs = classes[cid][1]
        for ref, old, new in zip(refs, property_values(payload, len(refs)), property_values(replacement, len(refs))):
            if old == new:
                continue
            if name == b"Source" and ref in source_ids:
                changed_sources.add(ref)
            elif (ref, name) in allowed:
                changed_properties.append({"id": ref, "path": before["paths"][ref], "property": name.decode()})
            else:
                raise ValueError(f"undeclared change: {before['paths'][ref]} / {name!r}")
    return {"changed_sources": [before["paths"][ref] for ref in sorted(changed_sources)],
            "changed_scene_properties": changed_properties,
            "protected_script_sources": len(before["sources"]) - len(changed_sources),
            "all_original_instance_ids_and_parents_preserved": True}


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
    scene = verify_scene(data)
    runtime = audit_kz_runtime(data)
    return public_report(report) | scene | runtime


def build(base: bytes) -> bytes:
    original = base
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
    base = apply_scene(base)
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
    verify_preservation(original, result)
    return result


def make_zip(data: bytes, path: Path) -> None:
    verify_sources(data)
    members = {"kz_variety_fix.rbxl": data}
    for name in PACKAGE_FILES:
        members[name] = (ROOT / name).read_bytes()
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in members.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 20, 0, 0, 0))
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
        (ROOT / VERSIONED_ZIP).write_bytes((ROOT / "kz_variety_fix_updated.zip").read_bytes())
    else:
        if (ROOT / VERSIONED_ZIP).read_bytes() != (ROOT / "kz_variety_fix_updated.zip").read_bytes():
            raise ValueError("stale versioned ZIP")
        with zipfile.ZipFile(ROOT / "kz_variety_fix_updated.zip") as archive:
            if archive.testzip() is not None or archive.read("kz_variety_fix.rbxl") != data:
                raise ValueError("stale or corrupt ZIP")
            for name in PACKAGE_FILES:
                if archive.read(name) != (ROOT / name).read_bytes():
                    raise ValueError(f"stale ZIP helper: {name}")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
