"""Regenerate the declared block placements and water edits using Lune."""
from pathlib import Path
import argparse
import json
import subprocess
import tempfile
from rbxl_container import validate

ROOT = Path(__file__).resolve().parent
MAP_PATH = 'Workspace/KZ_Variety_CS2_ROBLOX_V22'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lune', required=True, type=Path)
    parser.add_argument('--base', type=Path, default=ROOT / 'kz_variety_fix.rbxl')
    args = parser.parse_args()
    report = validate(args.base.read_bytes())
    paths = {path: ref for ref, path in report['paths'].items()
             if path == MAP_PATH or path.startswith(MAP_PATH + '/')}
    if MAP_PATH not in paths:
        raise ValueError('Active calibrated map missing')
    with tempfile.TemporaryDirectory() as directory:
        ids = Path(directory) / 'ids.json'
        ids.write_text(json.dumps(paths))
        subprocess.run([str(args.lune.resolve()), 'run', 'tools/generate_scene.luau',
                        str(args.base.resolve()), str(ids)], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
