# Home-fabricated microphone and ADC PCB

This directory documents the physical input board used with the full MFCC
design on 19 August 2026. It combines the microphone front end, analog filter,
ADC121S101 interface, local adjustments, power connection, and a Basys 3 Pmod
connection.

## Retained configuration

- FPGA top: `top_module`
- ADC mapping: JC3/N17 `spi_clk`, JC4/P18 `spi_miso`, JC9/P17 `cs_out`
- Full debug stream: Basys 3 USB-UART TX on A18 at 1,000,000 baud
- Canonical constraint: `../../constraints/jc_homefab.xdc`
- Routed implementation evidence: `../../implementation/jc_homefab/`
- Photographs: `photos/`
- Reconciled board source and checks: `kicad/`
- Metadata-free report figures and generator: `report_assets/`

No bitstream or programming log is versioned. Build a fresh bitstream outside
the repository and pass its path, SHA-256 and an explicitly inspected JTAG
target substring to `programming/program_full_mfcc_jc.tcl`.

## Recognition evidence boundary

Bench operation and near-perfect informal recognition were observed during
development, but no pre-labeled live session made with the final FFT/Mel-
corrected image was retained. This release therefore makes no numerical
final-system accuracy claim. The logger under `../../verification/hardware/`
can create a new declared session, but a future run is new evidence and is not
retroactively part of the final report.

## KiCad boundary

The reconciled schematic and PCB share the same exact set of 21 named nets.
KiCad's native connectivity accounts for 75 pads, 287 track segments and 18
vias; one isolated Pmod pad intentionally remains no-net. The home-fabricated
copper is mirrored relative to logical ADC121S101 and LM324 footprint numbering,
as documented in `kicad/README.md`.

Net reconciliation passes, but fab-ready closure is not claimed. The retained
PCB DRC has 12 errors and 114 warnings; schematic ERC has 8 errors and 20
warnings. JC10/R18 is also driven by the FPGA `pmod` output and must remain
physically isolated from an unintended board connection.

## Photograph provenance

The eleven retained photographs cover the July-to-August fabrication sequence.
The repository copies were auto-oriented and stripped of EXIF/GPS metadata.
The July defective UV trial is explicitly development evidence; later operating,
component-side and solder-side images document the final populated board.
Photographs do not independently establish electrical behavior or recognition
accuracy.
