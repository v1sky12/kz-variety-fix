#!/usr/bin/env python3
"""Install or roll back a kz_variety_fix.rbxl package safely."""
from __future__ import annotations
import argparse, shutil, sys, tempfile, zipfile
from datetime import datetime, timezone
from pathlib import Path

def check_place(path: Path) -> None:
    with path.open('rb') as f:
        head=f.read(8); f.seek(-8,2); tail=f.read(8)
    if head != b'<roblox!' or tail != b'/roblox>':
        raise ValueError(f'not a valid RBXL container: {path}')

def install(package: Path, destination: Path) -> Path:
    with zipfile.ZipFile(package) as z:
        z.testzip()
        names=[n for n in z.namelist() if n.lower().endswith('.rbxl')]
        if len(names)!=1: raise ValueError('package must contain exactly one .rbxl')
        with tempfile.TemporaryDirectory(dir=destination.parent) as td:
            extracted=Path(td)/Path(names[0]).name
            extracted.write_bytes(z.read(names[0])); check_place(extracted)
            stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
            backup=destination.with_name(destination.name+'.backup-'+stamp)
            if destination.exists(): shutil.copy2(destination,backup)
            shutil.copy2(extracted,destination)
    return backup if 'backup' in locals() else Path()

def main() -> int:
    ap=argparse.ArgumentParser(); sub=ap.add_subparsers(dest='cmd',required=True)
    i=sub.add_parser('install');i.add_argument('package',type=Path);i.add_argument('place',type=Path)
    r=sub.add_parser('rollback');r.add_argument('backup',type=Path);r.add_argument('place',type=Path)
    a=ap.parse_args()
    try:
        if a.cmd=='install':
            backup=install(a.package,a.place); print('installed',a.place); print('backup',backup or 'none')
        else:
            check_place(a.backup); shutil.copy2(a.backup,a.place); print('restored',a.place)
        return 0
    except (OSError,ValueError,zipfile.BadZipFile) as e: print(f'error: {e}',file=sys.stderr); return 1
if __name__=='__main__': raise SystemExit(main())
