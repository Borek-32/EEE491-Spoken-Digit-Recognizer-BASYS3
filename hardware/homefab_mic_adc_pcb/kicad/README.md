# Reconciled KiCad source

This directory contains the report-ready schematic and the recovered PCB with
every routed copper island assigned its schematic net name; the one physically
isolated, unused Pmod pad is explicitly retained as `<no net>`.

- `mfcc_homefab_named_nets.kicad_sch`: schematic with the ADC ground joined to
  the existing global `GND` net.
- `mfcc_homefab_named_nets.kicad_pcb`: original board geometry with net names
  added to all pads, routed segments, and vias.
- `mfcc_homefab_named_nets.kicad_pro`: KiCad project settings generated for the
  reconciled pair.
- `tools/`: fail-closed reconstruction and verification scripts.
- `evidence/`: exported netlist, IPC-D-356 netlist, native KiCad checks,
  hashes, and the inspected schematic render.

The pre-reconciliation source copies are retained under `originals/`. Their
SHA-256 values are:

- schematic: `e35c51a3030d64c75fbf8b99cae6bb0e8106192cca6c8ed2968b3d3029f0215c`
- PCB: `d63a80d06c6ad783caed415275df6e86c6c870cf5f2c0cff97cd489689012f88`

## Exact net reconciliation

KiCad 10.0.3 native connectivity found 22 physical copper islands. Twenty-one
use the exact exported schematic names; the remaining island is an intentionally
isolated Pmod pad and remains `<no net>`.

| Island | Exact net | Pads | Segments | Vias |
| --- | --- | ---: | ---: | ---: |
| I001 | `/ref` | 4 | 12 | 0 |
| I002 | `/3v3` | 4 | 26 | 3 |
| I003 | `/JC9` | 2 | 33 | 4 |
| I004 | `GND` | 12 | 50 | 3 |
| I005 | `<no net>` | 1 | 0 | 0 |
| I006 | `/JC4` | 3 | 9 | 2 |
| I007 | `VCC` | 5 | 33 | 2 |
| I008 | `/JC3` | 2 | 4 | 1 |
| I009 | `/filter-out` | 4 | 13 | 1 |
| I010 | `/div-ref` | 4 | 14 | 0 |
| I011 | `/mic` | 3 | 15 | 2 |
| I012 | `/ss2r` | 3 | 6 | 0 |
| I013 | `/div-out` | 3 | 8 | 0 |
| I014 | `/ss2c` | 3 | 8 | 0 |
| I015 | `/amp1` | 3 | 10 | 0 |
| I016 | `/pot1` | 2 | 6 | 0 |
| I017 | `/ss1c` | 3 | 8 | 0 |
| I018 | `/ss1o` | 4 | 10 | 0 |
| I019 | `/amp2` | 2 | 7 | 0 |
| I020 | `/amp-out` | 3 | 4 | 0 |
| I021 | `/ss1r` | 3 | 8 | 0 |
| I022 | `/pot2` | 2 | 3 | 0 |

The exported schematic contains exactly these 21 named nets, and the named PCB
contains the same 21-name set. Coverage is complete: 75 pads, 287 track
segments, and 18 vias are accounted for. The before/after structured geometry
fingerprints are identical.

## Home-fabrication mirror

The successful physical board is mirrored relative to the logical pad numbers
in the recovered footprints. Net assignment therefore follows the working
electrical pins, not the printed geometric pad numbers.

ADC footprint geometry maps to the
[TI ADC121S101 pinout](https://www.ti.com/lit/ds/symlink/adc121s101.pdf)
as follows:

| Geometric pad | Actual ADC pin/function | Net |
| ---: | --- | --- |
| 1 | 3, `VIN` | `/ref` |
| 2 | 2, `GND` | `GND` |
| 3 | 1, `VA` | `/3v3` |
| 4 | 6, `/CS` | `/JC9` |
| 5 | 5, `SDATA` | `/JC4` |
| 6 | 4, `SCLK` | `/JC3` |

For the SO-14 LM324, the actual lead is `15 - geometric pad`. This places the
actual positive supply on geometric pad 11 (`VCC`) and the actual negative
supply on geometric pad 4 (`GND`), and it resolves all four amplifier stages.
The two recovered board diode references are also reversed by role relative to
the schematic; the net assignment follows the electrical clamp nodes.

## Ground correction

The source schematic used both the global `GND` net and a local `/gnd` label
for the ADC. The fabricated PCB has one common ground island. The reconciled
schematic therefore replaces only that local label with a wired global GND
symbol. It now exports one `GND` net and no `/gnd` or anonymous ADC-ground net.

## Verification boundary

`evidence/bundle_validation.json` records `PASS_NET_ASSIGNMENT`:

- 21/21 schematic names equal 21/21 named PCB nets;
- all pads, tracks, and vias are assigned to their native KiCad island;
- one isolated Pmod pad is deliberately left no-net;
- no board geometry changed;
- KiCad DRC reports zero unconnected items.

This does **not** make the legacy home-fabrication layout DRC-clean. The retained
DRC contains 126 inherited findings: 12 errors and 114 warnings, including two
copper-clearance findings, malformed/co-located Pmod holes, courtyard overlaps,
a missing formal `Edge.Cuts` outline, and dangling legacy stubs. The schematic
ERC retains 28 pre-existing structural findings (8 errors and 20 warnings),
principally because the drawing models four op-amp triangles as separate
references rather than one multi-unit LM324 package and omits connector/power
driver detail. These limitations are preserved rather than hidden.

The direct Pmod footprint also joins the geometric contacts corresponding to
JC4 and JC10. The full FPGA design still drives JC10 as a separate `pmod`
output, so that contact must remain physically unpopulated/isolated or the FPGA
constraint must be disabled before treating a future revision as fab-ready.

## Reproduce the checks

Run the net assignment with KiCad's Python runtime:

```bash
flatpak run --command=python3 org.kicad.KiCad \
  tools/assign_schematic_nets.py SOURCE.kicad_pcb OUTPUT.kicad_pcb \
  --manifest evidence/net_assignment_manifest.json
```

Then export the schematic netlist/ERC and PCB DRC with `kicad-cli`, and run:

```bash
python3 tools/verify_named_bundle.py . \
  --desktop-schematic originals/mfcc.kicad_sch \
  --desktop-board originals/mfccsmd.kicad_pcb \
  --output evidence/bundle_validation.json
```

`PASS_NET_ASSIGNMENT` is deliberately narrower than fabrication approval. The
retained 126 PCB DRC and 28 schematic ERC findings remain open. Machine-local
paths in the exported evidence were replaced with repository-relative names;
the visible `borek32` copper marking is retained as intentional attribution.
