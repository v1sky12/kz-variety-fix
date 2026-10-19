"""Inventory original special blocks directly from the imported map entities."""
from collections import Counter
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
NAMES = {1: "modifier", 4: "anti_bhop", 5: "start", 6: "finish", 10: "delayed_teleport", 11: "multibhop", 12: "single_bhop", 13: "sequential_bhop", 14: "push"}


def inventory():
    source = (ROOT / "src/KZMapData.luau").read_text()
    data = json.loads(re.search(r"\[====\[(.*?)\]====\]", source, re.S)[1])
    entities = data["entities"]
    result = []
    counts = Counter()
    for entity in entities:
        properties = entity["properties"]
        kind = int(properties.get("timer_trigger_type", 0))
        if kind not in NAMES:
            continue
        counts[NAMES[kind]] += 1
        result.append({
            "id": entity["id"], "type": kind, "name": NAMES[kind], "bounds_cs_units": entity["bounds"],
            "destination": properties.get("timer_teleport_destination", properties.get("target")),
            "teleport_delay_seconds": float(properties.get("timer_teleport_delay", 0)),
            "push_amount_cs_units": properties.get("timer_push_amount", "0 0 0"),
            "push_conditions": [key.removeprefix("timer_push_condition_") for key, value in properties.items() if key.startswith("timer_push_condition_") and value == "1"],
            "push_absolute_source_axes": [axis for axis in "xyz" if properties.get("timer_push_abs_speed_" + axis) == "1"],
            "push_delay_seconds": float(properties.get("timer_push_delay", 0)),
            "push_cooldown_seconds": float(properties.get("timer_push_cooldown", .1)),
            "cancel_push_on_teleport": properties.get("timer_push_cancel_on_teleport", "1") == "1",
            "gravity_multiplier": float(properties.get("timer_modifier_gravity", 1)),
            "jump_multiplier": float(properties.get("timer_modifier_jump_impulse", 1)),
            "slide": properties.get("timer_modifier_enable_slide") == "1",
        })
    return {"entities": len(entities), "raw_ladder_faces": len(data["ladders"]), "counts": {name:counts[name] for name in sorted(NAMES.values())},
            "studio_status": "Not run in Roblox Studio; per-block map playtest remains required.", "blocks": result}


if __name__ == "__main__":
    report = inventory()
    (ROOT / "special_blocks_audit.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report["counts"], sort_keys=True))
