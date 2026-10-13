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
            payload = zstandard.ZstdDecompressor().decompress(raw, max_output_size=MAX_CHUNK) if compressed else raw
        except zstandard.ZstdError as error:
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


def public_report(report: dict) -> dict:
    return {key: value for key, value in report.items() if key not in ("sources", "paths", "disabled")}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("place", type=Path)
    args = parser.parse_args()
    print(json.dumps(public_report(validate(args.place.read_bytes())), indent=2))
