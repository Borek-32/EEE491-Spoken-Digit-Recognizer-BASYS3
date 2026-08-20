# Standalone PCB ADC-to-UART diagnostic

This directory isolates the recovered `PCB.vhd` diagnostic from the MFCC
recognizer. Top `PCB` reads the external SPI ADC, averages 32 conversions,
recenters the 12-bit samples, and transmits signed 16-bit values over the
Basys 3 USB-UART connection.

## Reproducible inputs

- `src/PCB.vhd`: recovered baseline RTL, SHA-256
  `751c59a1592b73d9a1a77779d09f4339b96f97ef051685ae126386492618f96f`
- `constraints/pcb_adc_uart_basys3.xdc`: standalone JC constraints
- `ip/clk_wiz_0/clk_wiz_0.xci`: 100 MHz to 36 MHz Clocking Wizard metadata
- `recreate_project.tcl` and `build_and_verify.tcl`: out-of-tree interfaces
- `build_evidence/`: retained text reports from the 19 August reconstruction
- `trials/adc121s101_spi_alignment_20260819/`: preserved baseline/candidate
  source comparison and explicitly bounded evidence

Generated XPR, IP products, DCP, bitstream, log and cache files are excluded.

## Recreate and build

Choose fresh directories outside the public repository:

```bash
vivado -mode batch -notrace -source recreate_project.tcl \
  -tclargs ../../../../pcb-adc-build
vivado -mode batch -notrace -source build_and_verify.tcl \
  -tclargs ../../../../pcb-adc-build ../../../../pcb-adc-results 4
```

An optional second recreation argument selects an explicit RTL file. This is
how the retained SPI-alignment candidate can be rebuilt without replacing the
baseline source:

```bash
vivado -mode batch -notrace -source recreate_project.tcl \
  -tclargs ../../../../pcb-adc-candidate-build \
  trials/adc121s101_spi_alignment_20260819/candidate/PCB.vhd
```

The scripts refuse in-tree or pre-existing output directories. The build gate
checks routed setup/hold timing, complete routing, DRC, methodology, the 100 MHz
and 36 MHz clocks, and the exact eight-port package-pin map. A generated
bitstream is copied only to the external results directory.

## Retained reconstruction result

Vivado 2025.2 reported WNS `+6.899 ns`, WHS `+0.131 ns`, all 203 routable nets
complete, and zero DRC/methodology findings. That is internal implementation
evidence, not complete hardware validation. The external SPI ports have no
ADC-datasheet-derived input/output delays.

The retained CDC report still contains 133 `CDC-1` critical findings, 12
`CDC-15` warnings and four `CDC-3` informational findings for asynchronous
buttons/reset and the handshake-held sample transfer. This recovered design is
not claimed CDC-clean. Hardware capture was not rerun for the reconstruction.
