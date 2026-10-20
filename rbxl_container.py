"""Read and validate binary Roblox containers before distributing a place.

Source edits must be made to parsed values, then serialized with new byte
lengths. Editing the decompressed PROP byte buffer directly is unsafe.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import struct

import zstandard
import lz4.block

MAGIC = b"<roblox!\x89\xff\r\n\x1a\n"
MAX_CHUNK = 256 * 1024 * 1024


class ContainerError(ValueError):
    pass


def uint(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise ContainerError(f"missing uint32 at byte {offset}")
    return struct.unpack_from("<I", data, offset)[0]


def read_string(data: bytes, offset: int) -> tuple[bytes, int]:
    length = uint(data, offset)
    start = offset + 4
    if length > len(data) - start:
        raise ContainerError(
            f"string length {length} exceeds remaining data {len(data) - start}"
        )
    return data[start:start + length], start + length


def write_string(value: bytes) -> bytes:
    return struct.pack("<I", len(value)) + value


def read_strings(data: bytes, offset: int, count: int) -> list[bytes]:
    values = []
    for index in range(count):
        try:
            value, offset = read_string(data, offset)
        except ContainerError as error:
            raise ContainerError(f"string {index + 1}/{count}: {error}") from error
        values.append(value)
    if offset != len(data):
        raise ContainerError(f"{len(data) - offset} bytes after string array")
    return values


def decode_references(data: bytes, count: int) -> list[int]:
    if len(data) != count * 4:
        raise ContainerError("incorrect reference-array size")
    result, previous = [], 0
    for index in range(count):
        encoded = int.from_bytes(bytes(data[index + row * count] for row in range(4)), "big")
        delta = (encoded >> 1) ^ -(encoded & 1)
        previous += delta
        result.append(previous)
    return result


@dataclass
class Chunk:
    tag: bytes
    payload: bytes
    encoded: bytes


def chunks(data: bytes) -> list[Chunk]:
    if len(data) < 32 or data[:14] != MAGIC:
        raise ContainerError("invalid RBXL header")
    if data[14:16] != b"\0\0":
        raise ContainerError("unsupported RBXL version")
    result, position = [], 32
    while position < len(data):
        if position + 16 > len(data):
            raise ContainerError("truncated chunk header")
        tag = data[position:position + 4]
        compressed, uncompressed, reserved = struct.unpack_from("<III", data, position + 4)
        size = compressed or uncompressed
        end = position + 16 + size
        if end > len(data) or uncompressed > MAX_CHUNK:
            raise ContainerError(f"invalid {tag!r} chunk size at byte {position}")
        raw = data[position + 16:end]
        try:
            if not compressed:
                payload = raw
            elif raw.startswith(b"\x28\xb5\x2f\xfd"):
                payload = zstandard.ZstdDecompressor().decompress(raw, max_output_size=MAX_CHUNK)
            else:
                payload = lz4.block.decompress(raw, uncompressed_size=uncompressed)
        except (zstandard.ZstdError, lz4.block.LZ4BlockError) as error:
            raise ContainerError(f"cannot decompress {tag!r} at byte {position}: {error}") from error
        if len(payload) != uncompressed:
            raise ContainerError(f"incorrect decompressed length for {tag!r}")
        result.append(Chunk(tag, payload, data[position:end]))
        position = end
        if tag == b"END\0":
            if payload != b"</roblox>" or position != len(data):
                raise ContainerError("invalid RBXL footer or trailing data")
            break
    if not result or result[-1].tag != b"END\0":
        raise ContainerError("missing RBXL END chunk")
    return result


def property_header(payload: bytes) -> tuple[int, bytes, int, int]:
    class_id = uint(payload, 0)
    name, offset = read_string(payload, 4)
    if offset >= len(payload):
        raise ContainerError("missing property type")
    return class_id, name, payload[offset], offset + 1


def validate(data: bytes) -> dict:
    all_chunks = chunks(data)
    classes, references, parents = {}, set(), {}
    source_count, property_count = 0, 0
    sources, names, disabled = {}, {}, {}
    for chunk_index, chunk in enumerate(all_chunks):
        payload = chunk.payload
        try:
            if chunk.tag == b"INST":
                class_id = uint(payload, 0)
                class_name, offset = read_string(payload, 4)
                if offset >= len(payload):
                    raise ContainerError("missing INST service flag")
                service = payload[offset]
                count = uint(payload, offset + 1)
                offset += 5
                ids = decode_references(payload[offset:offset + count * 4], count)
                if len(payload) != offset + count * 4 + (count if service else 0):
                    raise ContainerError("incorrect INST payload size")
                if class_id in classes or any(r < 0 or r in references for r in ids) or len(set(ids)) != count:
                    raise ContainerError("duplicate or invalid INST references")
                references.update(ids)
                classes[class_id] = (class_name, ids)
            elif chunk.tag == b"PROP":
                class_id, name, kind, offset = property_header(payload)
                if class_id not in classes:
                    raise ContainerError("PROP references unknown class")
                ids = classes[class_id][1]
                if kind == 1:
                    values = read_strings(payload, offset, len(ids))
                    property_count += 1
                    if name == b"Source":
                        for instance, value in zip(ids, values):
                            value.decode("utf-8", errors="strict")
                            sources[instance] = value
                        source_count += len(values)
                    elif name == b"Name":
                        names.update(zip(ids, (value.decode("utf-8") for value in values)))
                elif kind == 2:
                    values = payload[offset:]
                    if len(values) != len(ids) or any(value not in (0, 1) for value in values):
                        raise ContainerError("incorrect boolean property array")
                    if name == b"Disabled":
                        disabled.update(zip(ids, (bool(value) for value in values)))
            elif chunk.tag == b"PRNT":
                if not payload or payload[0] != 0:
                    raise ContainerError("unsupported PRNT version")
                count = uint(payload, 1)
                if len(payload) != 5 + count * 8:
                    raise ContainerError("incorrect PRNT payload size")
                ids = decode_references(payload[5:5 + count * 4], count)
                values = decode_references(payload[5 + count * 4:], count)
                for instance, parent in zip(ids, values):
                    if instance not in references or instance in parents or (parent != -1 and parent not in references):
                        raise ContainerError("invalid or duplicate parent reference")
                    parents[instance] = parent
        except (ContainerError, UnicodeDecodeError) as error:
            raise ContainerError(f"chunk {chunk_index} {chunk.tag!r}: {error}") from error
    if len(classes) != uint(data, 16) or len(references) != uint(data, 20):
        raise ContainerError("instance/class counts disagree with RBXL header")
    if set(parents) != references:
        raise ContainerError("parent table does not cover all instances")
    paths = {}
    for instance in references:
        chain, seen, current = [], set(), instance
        while current != -1:
            if current in seen:
                raise ContainerError("cycle in parent table")
            seen.add(current)
            chain.append(names.get(current, str(current)))
            current = parents[current]
        paths[instance] = "/".join(reversed(chain))
    return {
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data), "chunks": len(all_chunks), "classes": len(classes),
        "instances": len(references), "string_properties": property_count,
        "scripts": source_count, "sources": sources, "paths": paths,
        "disabled": disabled,
    }


def replace_source_arrays(data: bytes, replacements: dict[int, bytes]) -> bytes:
    """Serialize edits by instance ID with byte-correct string lengths."""
    report = validate(data)
    unknown = set(replacements) - set(report["sources"])
    if unknown:
        raise ContainerError(f"unknown script instances: {sorted(unknown)}")
    class_ids = {}
    output = [data[:32]]
    for chunk in chunks(data):
        if chunk.tag == b"INST":
            name, offset = read_string(chunk.payload, 4)
            count = uint(chunk.payload, offset + 1)
            class_ids[uint(chunk.payload, 0)] = decode_references(chunk.payload[offset + 5:offset + 5 + count * 4], count)
        if chunk.tag == b"PROP":
            cid, name, kind, offset = property_header(chunk.payload)
            if name == b"Source" and kind == 1:
                ids = class_ids[cid]
                values = read_strings(chunk.payload, offset, len(ids))
                if set(ids) & set(replacements):
                    payload = chunk.payload[:offset] + b"".join(write_string(replacements.get(i, value)) for i, value in zip(ids, values))
                    compressed = zstandard.ZstdCompressor(level=3).compress(payload)
                    output.append(chunk.tag + struct.pack("<III", len(compressed), len(payload), 0) + compressed)
                    continue
        output.append(chunk.encoded)
    result = b"".join(output)
    validate(result)
    return result


def encode_references(values: list[int]) -> bytes:
    encoded, previous = [], 0
    for value in values:
        delta = value - previous
        if not -(1 << 31) <= delta < (1 << 31):
            raise ContainerError("reference delta exceeds int32")
        encoded.append(((delta << 1) ^ (delta >> 31)).to_bytes(4, "big"))
        previous = value
    return bytes(value[row] for row in range(4) for value in encoded)


def encode_chunk(tag: bytes, payload: bytes) -> bytes:
    compressed = zstandard.ZstdCompressor(level=3).compress(payload)
    return tag + struct.pack("<III", len(compressed), len(payload), 0) + compressed


def declarations(data: bytes) -> dict[int, tuple[bytes, list[int]]]:
    result = {}
    for chunk in chunks(data):
        if chunk.tag == b"INST":
            name, offset = read_string(chunk.payload, 4)
            count = uint(chunk.payload, offset + 1)
            result[uint(chunk.payload, 0)] = (name, decode_references(chunk.payload[offset + 5:offset + 5 + count * 4], count))
    return result


def audit_kz_runtime(data: bytes) -> dict:
    """Require the canonical KZ runtime scripts, with no duplicate controllers.

    ServerStorage backups and shared ModuleScripts do not count as starter
    controllers. This is a package layout check, not execution of user code.
    """
    from collections import Counter
    report = validate(data)
    kinds = {ref: name for name, refs in declarations(data).values() for ref in refs}
    expected = {
        "StarterPlayer/StarterPlayerScripts/KZClassicControls",
        "StarterPlayer/StarterPlayerScripts/KZClassicHUD",
        "StarterPlayer/StarterPlayerScripts/KZClassicCrouchPose",
        "StarterPlayer/StarterPlayerScripts/KZClassicChat",
        "StarterPlayer/StarterPlayerScripts/KZClassicMovement",
        "ServerScriptService/KZClassicGameplay",
    }
    scopes = ("Workspace/", "StarterPlayer/", "StarterGui/", "ServerScriptService/", "ReplicatedFirst/")
    active = Counter(report["paths"][ref] for ref in report["sources"]
                     if kinds[ref] != b"ModuleScript" and not report["disabled"].get(ref, False)
                     and report["paths"][ref].startswith(scopes))
    unexpected = sorted(path for path in active if path not in expected or active[path] != 1)
    missing = sorted(expected - active.keys())
    if unexpected or missing:
        raise ContainerError(f"KZ runtime controller conflict or incomplete package: unexpected={unexpected}, missing={missing}")
    return {"runtime_script_count": sum(active.values()), "runtime_scripts": sorted(active)}


def property_values(payload: bytes, count: int) -> list[bytes]:
    """Split supported typed arrays without decoding or rounding their values."""
    _, _, kind, offset = property_header(payload)
    raw = payload[offset:]
    if kind == 1:
        return read_strings(payload, offset, count)
    if kind == 2:
        if len(raw) != count:
            raise ContainerError("incorrect boolean array size")
        return [bytes([v]) for v in raw]
    if kind in (4, 14, 16):
        rotations = [b""] * count
        components = 1 if kind == 4 else 3
        if kind == 16:
            cursor = 0
            for index in range(count):
                if cursor >= len(raw):
                    raise ContainerError("truncated CFrame rotation")
                size = 37 if raw[cursor] == 0 else 1
                rotations[index] = raw[cursor:cursor + size]
                cursor += size
            raw = raw[cursor:]
        if len(raw) != components * count * 4:
            raise ContainerError("incorrect numeric property array size")
        return [rotations[i] + bytes(raw[c * count * 4 + row * count + i]
                                    for c in range(components) for row in range(4)) for i in range(count)]
    raise ContainerError(f"unsupported property patch type: {kind}")


def encode_property_values(kind: int, values: list[bytes]) -> bytes:
    if kind == 1:
        return b"".join(write_string(v) for v in values)
    if kind == 2:
        if any(v not in (b"\0", b"\1") for v in values):
            raise ContainerError("invalid boolean patch")
        return b"".join(values)
    if kind in (4, 14, 16):
        prefix = b""
        components = 1 if kind == 4 else 3
        if kind == 16:
            rotations = [v[:-12] for v in values]
            if any(len(r) != (37 if r and r[0] == 0 else 1) for r in rotations):
                raise ContainerError("invalid CFrame rotation patch")
            prefix = b"".join(rotations)
            values = [v[-12:] for v in values]
        if any(len(v) != components * 4 for v in values):
            raise ContainerError("invalid numeric patch size")
        return prefix + bytes(v[c * 4 + row] for c in range(components) for row in range(4) for v in values)
    raise ContainerError(f"unsupported property patch type: {kind}")


def replace_scene_properties(data: bytes, model: bytes, edits: dict[int, dict]) -> bytes:
    """Copy only declared values from isolated, named patch instances.

    Existing array values retain their exact encoded bytes, including opaque
    AttributesSerialize values and compact/expanded CFrame rotation formats.
    """
    before, patch = validate(data), validate(model)
    classes, patch_classes = declarations(data), declarations(model)
    patch_ids = {path: ref for ref, path in patch["paths"].items()}
    wanted = {}
    for target, edit in edits.items():
        if before["paths"].get(target) != edit["path"]:
            raise ContainerError(f"scene patch target moved: {target}")
        source = patch_ids.get(f"Target_{target}")
        if source is None:
            raise ContainerError(f"scene patch instance missing: {target}")
        for name in edit["properties"]:
            if name in ("Source", "Name", "Parent", "Disabled"):
                raise ContainerError("scene patch cannot modify identity or scripts")
            wanted[(source, name.encode())] = target
    replacements = {}
    for chunk in chunks(model):
        if chunk.tag != b"PROP":
            continue
        cid, name, kind, _ = property_header(chunk.payload)
        ids = patch_classes[cid][1]
        relevant = [ref for ref in ids if (ref, name) in wanted]
        if relevant:
            values = property_values(chunk.payload, len(ids))
            for ref, value in zip(ids, values):
                if (ref, name) in wanted:
                    replacements[(wanted[(ref, name)], name)] = (kind, value)
    if len(replacements) != len(wanted):
        raise ContainerError("patch model omits a declared property")
    output, applied = [data[:32]], set()
    for chunk in chunks(data):
        if chunk.tag == b"PROP":
            cid, name, kind, offset = property_header(chunk.payload)
            ids = classes[cid][1]
            if any((ref, name) in replacements for ref in ids):
                values = property_values(chunk.payload, len(ids))
                for index, ref in enumerate(ids):
                    if (ref, name) in replacements:
                        patch_kind, value = replacements[(ref, name)]
                        if patch_kind != kind:
                            raise ContainerError("scene property type mismatch")
                        values[index] = value
                        applied.add((ref, name))
                output.append(encode_chunk(chunk.tag, chunk.payload[:offset] + encode_property_values(kind, values)))
                continue
        output.append(chunk.encoded)
    if applied != set(replacements):
        raise ContainerError("target place omits a declared property")
    result = b"".join(output)
    after = validate(result)
    if before["paths"] != after["paths"] or before["sources"] != after["sources"] or before["disabled"] != after["disabled"]:
        raise ContainerError("scene patch changed instance identity or scripts")
    return result


def append_block_model(data: bytes, model: bytes, parent: int, root_name: str) -> bytes:
    """Append a Folder/Part subtree without rewriting existing class groups."""
    before, added = validate(data), validate(model)
    if parent not in before["paths"] or added["scripts"]:
        raise ContainerError("invalid block model or destination")
    root_path = before["paths"][parent] + "/" + root_name
    if root_path in before["paths"].values():
        raise ContainerError("block subtree already exists")
    old_classes, new_classes = declarations(data), declarations(model)
    if any(name not in (b"Folder", b"Part") for name, _ in new_classes.values()):
        raise ContainerError("block additions support only Folder and Part")
    if [p for p in added["paths"].values() if "/" not in p] != [root_name]:
        raise ContainerError("block model must contain exactly its declared root")
    ids = {old: max(before["paths"]) + 1 + i for i, old in enumerate(sorted(added["paths"]))}
    cids = {old: max(old_classes) + 1 + i for i, old in enumerate(sorted(new_classes))}
    declarations_out, properties_out, new_ids, new_parents = [], [], [], []
    for chunk in chunks(model):
        if chunk.tag == b"INST":
            cid = uint(chunk.payload, 0)
            name, offset = read_string(chunk.payload, 4)
            if chunk.payload[offset] != 0:
                raise ContainerError("block model cannot add a service")
            refs = new_classes[cid][1]
            payload = struct.pack("<I", cids[cid]) + write_string(name) + b"\0" + struct.pack("<I", len(refs)) + encode_references([ids[r] for r in refs])
            declarations_out.append(encode_chunk(b"INST", payload))
        elif chunk.tag == b"PROP":
            cid, name, kind, offset = property_header(chunk.payload)
            payload = struct.pack("<I", cids[cid]) + chunk.payload[4:]
            if kind in (28, 29):
                raise ContainerError("shared strings or protected script data unsupported in block model")
            if kind == 19:
                refs = decode_references(chunk.payload[offset:], len(new_classes[cid][1]))
                if any(r != -1 and r not in ids for r in refs):
                    raise ContainerError("external reference in block model")
                payload = payload[:offset] + encode_references([ids[r] if r != -1 else -1 for r in refs])
            properties_out.append(encode_chunk(b"PROP", payload))
        elif chunk.tag == b"PRNT":
            count = uint(chunk.payload, 1)
            refs = decode_references(chunk.payload[5:5 + count * 4], count)
            parents = decode_references(chunk.payload[5 + count * 4:], count)
            new_ids.extend(ids[r] for r in refs)
            new_parents.extend(parent if r == -1 else ids[r] for r in parents)
        elif chunk.tag != b"END\0":
            raise ContainerError(f"unsupported block model chunk: {chunk.tag!r}")
    header = bytearray(data[:32])
    struct.pack_into("<II", header, 16, before["classes"] + added["classes"], before["instances"] + added["instances"])
    output, parent_tables = [bytes(header)], 0
    for chunk in chunks(data):
        if chunk.tag == b"PRNT":
            parent_tables += 1
            count = uint(chunk.payload, 1)
            refs = decode_references(chunk.payload[5:5 + count * 4], count)
            parents = decode_references(chunk.payload[5 + count * 4:], count)
            output.extend(declarations_out + properties_out)
            output.append(encode_chunk(b"PRNT", b"\0" + struct.pack("<I", count + len(new_ids)) + encode_references(refs + new_ids) + encode_references(parents + new_parents)))
        else:
            output.append(chunk.encoded)
    if parent_tables != 1:
        raise ContainerError("block insertion requires one parent table")
    result = b"".join(output)
    after = validate(result)
    if any(after["paths"][r] != path for r, path in before["paths"].items()) or after["sources"] != before["sources"] or after["disabled"] != before["disabled"]:
        raise ContainerError("block insertion changed an existing instance")
    return result


def add_module_script(data: bytes, instance: int, parent: int, name: str, source: bytes) -> bytes:
    """Add one isolated class group; preserve every pre-existing property array."""
    report = validate(data)
    source.decode("utf-8", errors="strict")
    if instance < 0 or instance in report["paths"] or parent not in report["paths"]:
        raise ContainerError("invalid new module or parent reference")
    if not name or "/" in name or any(path == report["paths"][parent] + "/" + name for path in report["paths"].values()):
        raise ContainerError("duplicate or invalid module name")
    items = chunks(data)
    cid = max(uint(c.payload, 0) for c in items if c.tag == b"INST") + 1
    declarations = [encode_chunk(b"INST", struct.pack("<I", cid) + write_string(b"ModuleScript") + b"\0" + struct.pack("<I", 1) + encode_references([instance]))]
    for prop, value in ((b"Name", name.encode()), (b"Source", source)):
        declarations.append(encode_chunk(b"PROP", struct.pack("<I", cid) + write_string(prop) + b"\1" + write_string(value)))
    header = bytearray(data[:32])
    struct.pack_into("<II", header, 16, report["classes"] + 1, report["instances"] + 1)
    output = [bytes(header)]
    parent_chunks = 0
    for chunk in items:
        if chunk.tag == b"PRNT":
            parent_chunks += 1
            count = uint(chunk.payload, 1)
            ids = decode_references(chunk.payload[5:5 + 4 * count], count)
            parents = decode_references(chunk.payload[5 + 4 * count:], count)
            output.extend(declarations)
            output.append(encode_chunk(b"PRNT", b"\0" + struct.pack("<I", count + 1) + encode_references(ids + [instance]) + encode_references(parents + [parent])))
        else:
            output.append(chunk.encoded)
    if parent_chunks != 1:
        raise ContainerError("module insertion requires one parent table")
    result = b"".join(output)
    after = validate(result)
    if any(after["paths"][i] != p for i, p in report["paths"].items()) or after["sources"] != report["sources"] | {instance: source}:
        raise ContainerError("module insertion changed an existing instance")
    return result


def public_report(report: dict) -> dict:
    return {key: value for key, value in report.items() if key not in ("sources", "paths", "disabled")}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("place", type=Path)
    args = parser.parse_args()
    print(json.dumps(public_report(validate(args.place.read_bytes())), indent=2))
