"""Execute actual place modules under Luau with Roblox value-type fixtures."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent


def literal(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{" + ",".join(literal(v) for v in value) + "}"
    return "{" + ",".join("[" + literal(k) + "]=" + literal(v) for k, v in value.items()) + "}"


def module(name):
    return (ROOT / "src" / (name + ".luau")).read_text()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", required=True, type=Path)
    args = parser.parse_args()
    fixture = (ROOT / "tests/roblox_fixture.luau").read_text()
    data_source = module("KZMapData")
    data = json.loads(re.search(r"\[====\[(.*?)\]====\]", data_source, re.S)[1])
    # Supply the real imported entities and ladders to the actual map adapter.
    prelude = "local fixture=(function()\n" + fixture + "\nend)()\n"
    prelude += "local Vector3,CFrame=fixture.Vector3,fixture.CFrame\nlocal warn=print\n"
    prelude += "local typeof=function(v) local m=type(v)=='table' and getmetatable(v);return m and m.__type or type(v) end\n"
    prelude += 'local Enum={PartType={Block="Block"}}\n'
    prelude += "local imported=" + literal(data) + "\n"
    prelude += "local game={GetService=function() return {JSONDecode=function() return imported end} end}\n"
    for variable, name in (("Blocks", "KZBlockController"), ("Core", "KZClassicCore"), ("Collision", "KZBrushCollision"), ("Motor", "KZBrushMotor"), ("Bhop", "KZBhop"), ("Data", "KZMapData")):
        # Module closures deliberately do not share Core with the motor. In
        # Roblox each ModuleScript has its own global environment as well.
        if variable == "Motor":
            prelude += "local Motor=(function() local Core=nil\n" + module(name) + "\nend)()\n"
        elif variable in ("Bhop", "Data"):
            prelude += "local " + variable + "=(function() local script={Parent={WaitForChild=function(_,n) return n end}};local require=function(n) assert(n=='KZBlockController');return Blocks end\n" + module(name) + "\nend)()\n"
        else:
            prelude += "local " + variable + "=(function()\n" + module(name) + "\nend)()\n"
    server_prelude = prelude + (ROOT / "tests/server_fixture.luau").read_text()
    server_prelude += "\nlocal server=(function()\n" + module("KZClassicGameplay")
    server_prelude += "\nreturn {states=states,action=action,moveTo=moveTo,push=push,startRun=startRun,outputs=outputs,applyOutput=applyOutput}\nend)()\n"
    client_prelude = prelude + (ROOT / "tests/client_fixture.luau").read_text()
    client_prelude += "\nlocal client=(function()\n" + module("KZClassicMovement")
    client_prelude += "\nreturn {setup=setup,session=function() return session end,fallback=fallback,ladderStep=ladderStep,readInput=readInput}\nend)()\n"
    status = 0
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "physics.luau"
        path.write_text(prelude + (ROOT / "tests/physics.luau").read_text())
        status |= subprocess.run([str(args.luau.resolve()), str(path)], cwd=ROOT).returncode
        path = Path(directory) / "blocks.luau"
        path.write_text(prelude + (ROOT / "tests/blocks.luau").read_text())
        status |= subprocess.run([str(args.luau.resolve()), str(path)], cwd=ROOT).returncode
        path = Path(directory) / "client.luau"
        path.write_text(client_prelude + (ROOT / "tests/client.luau").read_text())
        status |= subprocess.run([str(args.luau.resolve()), str(path)], cwd=ROOT).returncode
        path = Path(directory) / "network.luau"
        path.write_text(server_prelude + (ROOT / "tests/network.luau").read_text())
        status |= subprocess.run([str(args.luau.resolve()), str(path)], cwd=ROOT).returncode
    return status


if __name__ == "__main__":
    raise SystemExit(main())
