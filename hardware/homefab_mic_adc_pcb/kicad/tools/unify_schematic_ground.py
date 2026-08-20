#!/usr/bin/env python3
"""Replace the ADC-only local `gnd` label with the schematic's global GND.

The source schematic already contains the standard KiCad GND symbol.  This
script clones that embedded symbol instance onto the ADC ground junction,
instead of relying on a local label named `GND` (which would export as /GND).
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import uuid


SOURCE_SHA256 = "e35c51a3030d64c75fbf8b99cae6bb0e8106192cca6c8ed2968b3d3029f0215c"
LOCAL_GND_LABEL_UUID = "c21617be-9e2d-42da-94da-25d746e78ecc"
TEMPLATE_GND_SYMBOL_UUID = "4670ab66-d4b8-4e14-bbbd-5e52e886ac65"
TEMPLATE_GND_PIN_UUID = "2eca9f66-e0b0-40e4-984f-a3bc3d502928"
# Put the global GND symbol below the ADC ground rail, away from the clamp
# diodes, and connect it with an explicit short vertical wire and junction.
RAIL_X = 138.43
RAIL_Y = 128.27
TARGET_X = 138.43
TARGET_Y = 130.81


def blocks(text: str, head: str):
    pattern = re.compile(r"\(" + re.escape(head) + r"(?=[\s\)])")
    for match in pattern.finditer(text):
        start = match.start()
        depth = 0
        quoted = False
        escaped = False
        for index in range(start, len(text)):
            char = text[index]
            if quoted:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    quoted = False
                continue
            if char == '"':
                quoted = True
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    yield start, index + 1, text[start:index + 1]
                    break


def find_uuid_block(text: str, head: str, wanted_uuid: str):
    token = f'(uuid "{wanted_uuid}")'
    matches = [block for block in blocks(text, head) if token in block[2]]
    if len(matches) != 1:
        raise RuntimeError(f"expected one {head} block for {wanted_uuid}, found {len(matches)}")
    return matches[0]


def number(value: float) -> str:
    return f"{value:.6f}".rstrip("0").rstrip(".")


def translated_symbol(template: str) -> str:
    first_at = re.search(r"\(at\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\)", template)
    if not first_at:
        raise RuntimeError("GND template lacks placement")
    source_x, source_y = float(first_at.group(1)), float(first_at.group(2))
    dx, dy = TARGET_X - source_x, TARGET_Y - source_y

    def shift(match: re.Match) -> str:
        x = float(match.group(1)) + dx
        y = float(match.group(2)) + dy
        return f"(at {number(x)} {number(y)} {match.group(3)})"

    result = re.sub(
        r"\(at\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\)",
        shift,
        template,
    )
    symbol_uuid = str(uuid.uuid5(uuid.NAMESPACE_URL, "mfcc-homefab-adc-global-gnd-symbol"))
    pin_uuid = str(uuid.uuid5(uuid.NAMESPACE_URL, "mfcc-homefab-adc-global-gnd-pin"))
    result = result.replace(TEMPLATE_GND_SYMBOL_UUID, symbol_uuid)
    result = result.replace(TEMPLATE_GND_PIN_UUID, pin_uuid)
    result = result.replace("#PWR02", "#PWR07")
    # The symbol sits in the narrow gap between the ground rail and the signal
    # rail.  Keep the unmistakable ground glyph but hide its repeated value
    # text so it does not collide with the adjacent `ref` label.
    result = re.sub(
        r'(\(property "Value" "GND"\s+\(at [^)]+\))',
        r'\1\n\t\t\t(hide yes)',
        result,
        count=1,
    )
    return result


def repair(source: Path, output: Path) -> None:
    source_bytes = source.read_bytes()
    digest = hashlib.sha256(source_bytes).hexdigest()
    if digest != SOURCE_SHA256:
        raise RuntimeError(f"source SHA-256 changed: {digest}")
    text = source_bytes.decode()
    label_start, label_end, label = find_uuid_block(text, "label", LOCAL_GND_LABEL_UUID)
    if not label.startswith('(label "gnd"'):
        raise RuntimeError("target label is no longer the expected local gnd")
    _, _, template = find_uuid_block(text, "symbol", TEMPLATE_GND_SYMBOL_UUID)
    junction_uuid = str(uuid.uuid5(uuid.NAMESPACE_URL, "mfcc-homefab-adc-ground-junction"))
    wire_uuid = str(uuid.uuid5(uuid.NAMESPACE_URL, "mfcc-homefab-adc-ground-wire"))
    junction = (
        f'(junction\n'
        f'\t\t(at {number(RAIL_X)} {number(RAIL_Y)})\n'
        f'\t\t(diameter 0)\n'
        f'\t\t(color 0 0 0 0)\n'
        f'\t\t(uuid "{junction_uuid}")\n'
        f'\t)'
    )
    wire = (
        f'(wire\n'
        f'\t\t(pts\n'
        f'\t\t\t(xy {number(RAIL_X)} {number(RAIL_Y)}) (xy {number(TARGET_X)} {number(TARGET_Y)})\n'
        f'\t\t)\n'
        f'\t\t(stroke\n'
        f'\t\t\t(width 0)\n'
        f'\t\t\t(type default)\n'
        f'\t\t)\n'
        f'\t\t(uuid "{wire_uuid}")\n'
        f'\t)'
    )
    replacement = junction + "\n\t" + wire + "\n\t" + translated_symbol(template)
    repaired = text[:label_start] + replacement + text[label_end:]
    if f'(uuid "{LOCAL_GND_LABEL_UUID}")' in repaired:
        raise RuntimeError("local gnd label was not removed")
    if repaired.count('(property "Reference" "#PWR07"') != 1:
        raise RuntimeError("replacement GND power symbol was not created exactly once")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(repaired)
    print(f"Wrote {output}")
    print(f"Output SHA-256: {hashlib.sha256(output.read_bytes()).hexdigest()}")
    print("PASS: replaced ADC local /gnd label with a wired global GND power symbol")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    repair(args.source, args.output)


if __name__ == "__main__":
    main()
