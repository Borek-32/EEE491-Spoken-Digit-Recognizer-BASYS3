#!/usr/bin/env python3
"""Assign schematic net names to the recovered netless MFCC PCB.

Run with KiCad's Python runtime.  Connectivity is determined by KiCad itself;
no distance approximation is used.  The source hash, island count, membership,
and geometry are all fail-closed so this script cannot silently relabel a
different layout.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path

import pcbnew


SOURCE_SHA256 = "d63a80d06c6ad783caed415275df6e86c6c870cf5f2c0cff97cd489689012f88"

# Local schematic labels are slash-prefixed in KiCad's exported netlist.
# I004 intentionally uses the global GND name: the physical board has one
# ground island, so the repaired schematic replaces its separate local /gnd.
ISLAND_NETS = {
    "I001": "/ref",
    "I002": "/3v3",
    "I003": "/JC9",
    "I004": "GND",
    "I005": None,
    "I006": "/JC4",
    "I007": "VCC",
    "I008": "/JC3",
    "I009": "/filter-out",
    "I010": "/div-ref",
    "I011": "/mic",
    "I012": "/ss2r",
    "I013": "/div-out",
    "I014": "/ss2c",
    "I015": "/amp1",
    "I016": "/pot1",
    "I017": "/ss1c",
    "I018": "/ss1o",
    "I019": "/amp2",
    "I020": "/amp-out",
    "I021": "/ss1r",
    "I022": "/pot2",
}

EXPECTED_COUNTS = {
    "I001": (4, 12, 0), "I002": (4, 26, 3), "I003": (2, 33, 4),
    "I004": (12, 50, 3), "I005": (1, 0, 0), "I006": (3, 9, 2),
    "I007": (5, 33, 2), "I008": (2, 4, 1), "I009": (4, 13, 1),
    "I010": (4, 14, 0), "I011": (3, 15, 2), "I012": (3, 6, 0),
    "I013": (3, 8, 0), "I014": (3, 8, 0), "I015": (3, 10, 0),
    "I016": (2, 6, 0), "I017": (3, 8, 0), "I018": (4, 10, 0),
    "I019": (2, 7, 0), "I020": (3, 4, 0), "I021": (3, 8, 0),
    "I022": (2, 3, 0),
}

EXPECTED_PADS = {
    "I001": {"D1.2", "D2.1", "RA.2", "REF**@157.250,68.750.1"},
    "I002": {"CDC@130.750,65.250.1", "D1.1", "REF**@155.920,65.040.1", "REF**@157.250,68.750.3"},
    "I003": {"REF**@155.920,65.040.8", "REF**@157.250,68.750.4"},
    "I004": {"324.4", "C3.2", "C5.1", "CDC@130.750,65.250.2", "CDC@143.750,65.250.2", "D2.2", "GND.1", "R2.1", "REF**@155.920,65.040.3", "REF**@155.920,65.040.4", "REF**@157.250,68.750.2", "REF**@162.750,84.750.1"},
    "I005": {"REF**@155.920,65.040.2"},
    "I006": {"REF**@155.920,65.040.5", "REF**@155.920,65.040.6", "REF**@157.250,68.750.5"},
    "I007": {"324.11", "9V.1", "CDC@143.750,65.250.1", "R1.2", "R3.2"},
    "I008": {"REF**@155.920,65.040.7", "REF**@157.250,68.750.6"},
    "I009": {"324.1", "324.2", "C4.2", "RA.1"},
    "I010": {"324.13", "324.14", "R4.2", "R5.1"},
    "I011": {"C1.2", "R3.1", "REF**@162.750,84.750.2"},
    "I012": {"C4.1", "R10.1", "R9.2"},
    "I013": {"324.12", "R1.1", "R2.2"},
    "I014": {"324.3", "C5.2", "R10.2"},
    "I015": {"324.10", "C1.1", "R4.1"},
    "I016": {"POT.3", "R5.2"},
    "I017": {"324.5", "C3.1", "R8.2"},
    "I018": {"324.6", "324.7", "C2.1", "R9.1"},
    "I019": {"324.9", "POT.2"},
    "I020": {"324.8", "R6.1", "R7.2"},
    "I021": {"C2.2", "R7.1", "R8.1"},
    "I022": {"POT.1", "R6.2"},
}


def uuid(item) -> str:
    return item.m_Uuid.AsString()


def mm(value: int) -> float:
    return value / 1_000_000.0


def kind(item) -> str:
    if isinstance(item, pcbnew.PAD):
        return "pad"
    return "via" if item.Type() == pcbnew.PCB_VIA_T else "segment"


def inventory(board):
    footprints = list(board.GetFootprints())
    ref_counts = Counter(fp.GetReference() for fp in footprints)
    objects = {}
    pad_names = {}
    for fp in footprints:
        pos = fp.GetPosition()
        ref = fp.GetReference()
        tag = ref if ref_counts[ref] == 1 else f"{ref}@{mm(pos.x):.3f},{mm(pos.y):.3f}"
        for pad in fp.Pads():
            objects[uuid(pad)] = pad
            pad_names[uuid(pad)] = f"{tag}.{pad.GetNumber()}"
    for track in board.GetTracks():
        objects[uuid(track)] = track
    return objects, pad_names


def components(board):
    board.BuildConnectivity()
    connectivity = board.GetConnectivity()
    objects, pad_names = inventory(board)
    adjacency = defaultdict(set)
    for item in objects.values():
        a = uuid(item)
        for neighbour in list(connectivity.GetConnectedTracks(item)) + list(connectivity.GetConnectedPads(item)):
            b = uuid(neighbour)
            if b in objects and a != b:
                adjacency[a].add(b)
                adjacency[b].add(a)
    groups = []
    seen = set()
    for start in objects:
        if start in seen:
            continue
        todo = [start]
        seen.add(start)
        group = []
        while todo:
            current = todo.pop()
            group.append(current)
            for neighbour in adjacency[current]:
                if neighbour not in seen:
                    seen.add(neighbour)
                    todo.append(neighbour)
        groups.append(group)

    def points(group):
        result = []
        for u in group:
            item = objects[u]
            if kind(item) in {"pad", "via"}:
                result.append(item.GetPosition())
            else:
                result.extend([item.GetStart(), item.GetEnd()])
        return result

    groups.sort(key=lambda group: (
        min(p.y for p in points(group)),
        min(p.x for p in points(group)),
        min(group),
    ))
    return objects, pad_names, groups


def validate_groups(objects, pad_names, groups):
    if len(groups) != 22:
        raise RuntimeError(f"expected 22 KiCad copper islands, found {len(groups)}")
    records = []
    for number, group in enumerate(groups, 1):
        island = f"I{number:03d}"
        counts = Counter(kind(objects[u]) for u in group)
        actual_counts = (counts["pad"], counts["segment"], counts["via"])
        if actual_counts != EXPECTED_COUNTS[island]:
            raise RuntimeError(f"{island} counts changed: {actual_counts} != {EXPECTED_COUNTS[island]}")
        actual_pads = {pad_names[u] for u in group if kind(objects[u]) == "pad"}
        if actual_pads != EXPECTED_PADS[island]:
            raise RuntimeError(f"{island} pad membership changed: {sorted(actual_pads)}")
        records.append({
            "id": island,
            "net": ISLAND_NETS[island],
            "counts": {"pads": counts["pad"], "segments": counts["segment"], "vias": counts["via"]},
            "pads": sorted(actual_pads),
            "uuids": sorted(group),
        })
    return records


def geometry_fingerprint(board):
    records = []
    for fp in board.GetFootprints():
        p = fp.GetPosition()
        records.append(("footprint", uuid(fp), p.x, p.y, fp.GetOrientationDegrees(), fp.GetLayer()))
        for pad in fp.Pads():
            pos, size, drill = pad.GetPosition(), pad.GetSize(), pad.GetDrillSize()
            records.append(("pad", uuid(pad), pos.x, pos.y, size.x, size.y, drill.x, drill.y, pad.GetShape(), tuple(sorted(pad.GetLayerSet().Seq()))))
    for item in board.GetTracks():
        if kind(item) == "via":
            p = item.GetPosition()
            records.append(("via", uuid(item), p.x, p.y, item.GetWidth(pcbnew.F_Cu), item.GetDrillValue(), tuple(sorted(item.GetLayerSet().Seq()))))
        else:
            a, b = item.GetStart(), item.GetEnd()
            records.append(("segment", uuid(item), a.x, a.y, b.x, b.y, item.GetWidth(), item.GetLayer()))
    records.append(("totals", len(list(board.GetFootprints())), len(list(board.GetTracks())), len(list(board.GetDrawings())), board.GetAreaCount()))
    return hashlib.sha256(repr(sorted(records, key=repr)).encode()).hexdigest()


def assign(source: Path, output: Path, manifest: Path) -> None:
    source_bytes = source.read_bytes()
    source_sha = hashlib.sha256(source_bytes).hexdigest()
    if source_sha != SOURCE_SHA256:
        raise RuntimeError(f"source SHA-256 changed: {source_sha}")
    board = pcbnew.LoadBoard(str(source))
    before_geometry = geometry_fingerprint(board)
    objects, pad_names, groups = components(board)
    records = validate_groups(objects, pad_names, groups)

    net_objects = {}
    for name in sorted({name for name in ISLAND_NETS.values() if name is not None}):
        net = pcbnew.NETINFO_ITEM(board, name)
        board.Add(net)
        net_objects[name] = net
    for record, group in zip(records, groups):
        net_name = record["net"]
        if net_name is None:
            continue
        for u in group:
            objects[u].SetNet(net_objects[net_name])

    output.parent.mkdir(parents=True, exist_ok=True)
    if not pcbnew.SaveBoard(str(output), board):
        raise RuntimeError(f"KiCad failed to save {output}")

    checked = pcbnew.LoadBoard(str(output))
    after_geometry = geometry_fingerprint(checked)
    if after_geometry != before_geometry:
        raise RuntimeError("geometry fingerprint changed while assigning nets")
    checked_objects, checked_pad_names, checked_groups = components(checked)
    checked_records = validate_groups(checked_objects, checked_pad_names, checked_groups)
    for record, group in zip(checked_records, checked_groups):
        expected = record["net"] or ""
        actual = {checked_objects[u].GetNetname() for u in group}
        if actual != {expected}:
            raise RuntimeError(f"{record['id']} net verification failed: {sorted(actual)} != {expected!r}")

    payload = {
        "source": str(source),
        "source_sha256": source_sha,
        "output": str(output),
        "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "kicad_version": pcbnew.Version(),
        "method": "native KiCad connectivity; fail-closed 22-island membership; SetNet on every pad, segment and via",
        "geometry_fingerprint_before": before_geometry,
        "geometry_fingerprint_after": after_geometry,
        "totals": {"islands": 22, "named_islands": 21, "no_net_islands": 1, "pads": 75, "segments": 287, "vias": 18},
        "islands": checked_records,
    }
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Wrote {output}")
    print(f"Wrote {manifest}")
    print(f"Output SHA-256: {payload['output_sha256']}")
    print("PASS: 21 named islands, 1 NC island, all 75 pads/287 segments/18 vias accounted for; geometry unchanged")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    assign(args.source, args.output, args.manifest)


if __name__ == "__main__":
    main()
