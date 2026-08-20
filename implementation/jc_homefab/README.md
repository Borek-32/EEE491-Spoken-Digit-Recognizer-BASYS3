# Retained JC/home-fabricated-board implementation evidence

This directory contains sanitized text evidence from the isolated Vivado 2025.2
implementation completed on 19 August 2026. The public build input is
`../../constraints/jc_homefab.xdc`; the reports here are not consumed during a
clean rebuild.

## Pin profile

| Signal | Basys 3 contact | Package pin | Direction |
| --- | --- | --- | --- |
| `spi_clk` | JC3 | N17 | output |
| `spi_miso` | JC4 | P18 | input |
| `cs_out` | JC9 | P17 | output |

The XDC is a complete 39-port profile, not an overlay. JC10/R18 remains driven
by the separate `pmod` output and must be physically isolated unless a future
board revision makes that connection intentionally compatible.

## Retained result

- Top `top_module`, part `xc7a35tcpg236-1`
- Implementation through `write_bitstream`: complete
- WNS `+0.671 ns`; WHS `+0.020 ns`
- 12,824/12,824 routable nets routed; zero routing errors
- DRC: 0 errors, 0 critical warnings, 0 warnings, 11 advisories
- 5,603 LUTs, 8,437 registers, 23.5 BRAM tiles, 15 DSPs
- All 39 scalarized ports constrained exactly once

The public release excludes the generated `.bit`, routed `.dcp`, Vivado logs,
IP-status dump, and original-tree protection hashes. Rebuild with
`../../scripts/recreate_project.tcl` and `../../scripts/build_jc_homefab.tcl`;
generated results remain outside the checkout.

## Evidence boundary

This is an internal FPGA implementation PASS. It is not external ADC timing
closure or a standalone hardware-function proof. The methodology report retains
36 `TIMING-18` warnings for 18 inputs and 18 outputs without I/O delays. The
full MFCC design also retains the legacy ADC receiver; the isolated diagnostic's
corrected SPI candidate is not silently substituted here.

Machine-local command paths in these retained text reports were replaced with
`<isolated-build>` for publication. Numerical findings and report bodies were
otherwise retained.
