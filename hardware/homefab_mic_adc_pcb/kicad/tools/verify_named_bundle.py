#!/usr/bin/env python3
"""Fail-closed verification for the repaired home-fabricated PCB bundle."""

from __future__ import annotations

from collections import Counter
import argparse
import hashlib
import json
from pathlib import Path
import re


EXPECTED_NETS = {
    "/3v3", "/JC3", "/JC4", "/JC9", "/amp-out", "/amp1",
    "/amp2", "/div-out", "/div-ref", "/filter-out", "/mic",
    "/pot1", "/pot2", "/ref", "/ss1c", "/ss1o", "/ss1r",
    "/ss2c", "/ss2r", "GND", "VCC",
}
SOURCE_SCHEMATIC_SHA256 = "e35c51a3030d64c75fbf8b99cae6bb0e8106192cca6c8ed2968b3d3029f0215c"
SOURCE_BOARD_SHA256 = "d63a80d06c6ad783caed415275df6e86c6c870cf5f2c0cff97cd489689012f88"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def schematic_nets(netlist: Path) -> set[str]:
    pattern = re.compile(r'\(net\s+\(code\s+"?\d+"?\)\s+\(name\s+"([^"]+)"\)')
    return {match.group(1) for match in pattern.finditer(netlist.read_text())}


def recursive_violations(value):
    if isinstance(value, dict):
        if "severity" in value and "type" in value:
            yield value
        for child in value.values():
            yield from recursive_violations(child)
    elif isinstance(value, list):
        for child in value:
            yield from recursive_violations(child)


def verify(base: Path, desktop_schematic: Path, desktop_board: Path, output: Path) -> None:
    paths = {
        "schematic": base / "mfcc_homefab_named_nets.kicad_sch",
        "board": base / "mfcc_homefab_named_nets.kicad_pcb",
        "netlist": base / "evidence/mfcc_homefab_named_nets.net",
        "ipc_d_356": base / "evidence/mfcc_homefab_named_nets.d356",
        "manifest": base / "evidence/net_assignment_manifest.json",
        "pcb_drc": base / "evidence/pcb_drc_initial.json",
        "schematic_erc": base / "evidence/schematic_erc.json",
        "render": base / "evidence/schematic_render/mfcc_homefab_named_nets_cropped.png",
    }
    missing = [str(path) for path in paths.values() if not path.is_file()]
    if missing:
        raise RuntimeError(f"missing artifacts: {missing}")

    source_hashes = {
        "desktop_schematic": sha(desktop_schematic),
        "desktop_board": sha(desktop_board),
    }
    if source_hashes["desktop_schematic"] != SOURCE_SCHEMATIC_SHA256:
        raise RuntimeError("authoritative Desktop schematic changed after snapshot")
    if source_hashes["desktop_board"] != SOURCE_BOARD_SHA256:
        raise RuntimeError("authoritative Desktop PCB changed after snapshot")

    manifest = json.loads(paths["manifest"].read_text())
    manifest_nets = {item["net"] for item in manifest["islands"] if item["net"] is not None}
    exported_nets = schematic_nets(paths["netlist"])
    if manifest_nets != EXPECTED_NETS:
        raise RuntimeError(f"PCB manifest net set differs: {sorted(manifest_nets ^ EXPECTED_NETS)}")
    if exported_nets != EXPECTED_NETS:
        raise RuntimeError(f"schematic net set differs: {sorted(exported_nets ^ EXPECTED_NETS)}")
    if sha(paths["board"]) != manifest["output_sha256"]:
        raise RuntimeError("named PCB hash differs from its assignment manifest")
    expected_totals = {
        "islands": 22, "named_islands": 21, "no_net_islands": 1,
        "pads": 75, "segments": 287, "vias": 18,
    }
    if manifest["totals"] != expected_totals:
        raise RuntimeError(f"unexpected PCB totals: {manifest['totals']}")
    if manifest["geometry_fingerprint_before"] != manifest["geometry_fingerprint_after"]:
        raise RuntimeError("geometry changed during net assignment")

    drc = json.loads(paths["pcb_drc"].read_text())
    drc_counts = Counter(item["severity"] for item in drc["violations"])
    if drc.get("unconnected_items"):
        raise RuntimeError("KiCad DRC reports unconnected items after net assignment")
    erc = json.loads(paths["schematic_erc"].read_text())
    erc_items = list(recursive_violations(erc))
    erc_counts = Counter(item["severity"] for item in erc_items)

    result = {
        "status": "PASS_NET_ASSIGNMENT",
        "scope": "exact net naming and coverage; not a claim that the legacy PCB is DRC-clean",
        "source_hashes": source_hashes,
        "artifact_hashes": {name: sha(path) for name, path in paths.items()},
        "schematic_net_count": len(exported_nets),
        "pcb_named_net_count": len(manifest_nets),
        "exact_net_set": sorted(EXPECTED_NETS),
        "pcb_coverage": manifest["totals"],
        "geometry_unchanged": True,
        "pcb_drc": {
            "violations": len(drc["violations"]),
            "by_severity": dict(sorted(drc_counts.items())),
            "unconnected_items": len(drc.get("unconnected_items", [])),
        },
        "schematic_erc": {
            "violations": len(erc_items),
            "by_severity": dict(sorted(erc_counts.items())),
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Wrote {output}")
    print("PASS_NET_ASSIGNMENT")
    print("21/21 schematic nets equal 21/21 PCB named nets")
    print("75 pads, 287 segments, 18 vias; one intentionally isolated no-net Pmod pad")
    print(f"PCB DRC boundary: {len(drc['violations'])} inherited findings, 0 unconnected items")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("--desktop-schematic", type=Path, required=True)
    parser.add_argument("--desktop-board", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    verify(args.base, args.desktop_schematic, args.desktop_board, args.output)


if __name__ == "__main__":
    main()
