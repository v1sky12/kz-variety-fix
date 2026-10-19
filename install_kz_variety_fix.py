#!/usr/bin/env python3
"""Validate, back up and atomically install/restore a kz_variety_fix place."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile
from rbxl_container import validate
MAX_PLACE_SIZE = 256 * 1024 * 1024

def check_place(path: Path) -> None:
    validate(path.read_bytes())

def replace_place(data: bytes, destination: Path) -> Path | None:
    validate(data)
    destination.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    with tempfile.TemporaryDirectory(dir=destination.parent) as directory:
        staged = Path(directory) / destination.name
        with staged.open('wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if destination.exists():
            stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
            descriptor, name = tempfile.mkstemp(prefix=destination.name+'.backup-'+stamp+'-', dir=destination.parent)
            os.close(descriptor)
            backup = Path(name)
            try:
                shutil.copy2(destination, backup)
            except OSError:
                backup.unlink(missing_ok=True)
                raise
        os.replace(staged, destination)
    return backup

def install(package: Path, destination: Path) -> Path | None:
    with zipfile.ZipFile(package) as archive:
        names = [entry for entry in archive.infolist() if entry.filename.lower().endswith('.rbxl')]
        if len(names) != 1:
            raise ValueError('package must contain exactly one .rbxl')
        if names[0].file_size > MAX_PLACE_SIZE:
            raise ValueError('place file exceeds installer size limit')
        bad_member = archive.testzip()
        if bad_member is not None:
            raise ValueError(f'ZIP checksum failed: {bad_member}')
        data = archive.read(names[0])
    return replace_place(data, destination)

def rollback(backup: Path, destination: Path) -> Path | None:
    return replace_place(backup.read_bytes(), destination)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    add = sub.add_parser('install');add.add_argument('package',type=Path);add.add_argument('place',type=Path)
    restore = sub.add_parser('rollback');restore.add_argument('backup',type=Path);restore.add_argument('place',type=Path)
    args = parser.parse_args()
    try:
        backup = install(args.package,args.place) if args.command=='install' else rollback(args.backup,args.place)
        print('installed' if args.command=='install' else 'restored',args.place)
        print('backup',backup if backup is not None else 'none')
        return 0
    except (OSError,ValueError,zipfile.BadZipFile) as error:
        print(f'error: {error}',file=sys.stderr)
        return 1
if __name__=='__main__': raise SystemExit(main())
