# ADC121S101 SPI-alignment trial (19 August 2026)

## Status

**Simulation PASS; implementation PASS; historical JTAG configuration PASS;
ADC endpoint capture NOT RUN.** This isolated diagnostic did not modify the
full MFCC `rtl/ADC.vhd`.

## Hypothesis and candidate

Bench observations near -2048 counts at 0 V but near 0 around the ADC supply
were consistent with a lost most-significant bit. The recovered receiver made
CS and the first falling SCLK edge coincide, did not explicitly retain a full
16-edge frame, and could sample before the ADC's worst-case access time.

The candidate in `candidate/PCB.vhd` asserts CS before the first transition,
captures exactly 16 falling edges, keeps the final 12 straight-binary bits,
discards the first completed conversion after start, averages the next 32, and
subtracts 2048 once. Its SHA-256 is
`a0171a70c302a14324324ea2dcbe9c7db5a120b0992fcf97e270fb91682063c6`.
The baseline source SHA-256 is
`751c59a1592b73d9a1a77779d09f4339b96f97ef051685ae126386492618f96f`.

## Retained results

The purpose-built model used worst-case 3.3 V `tACC=40 ns`, optional leading
zero phase behavior, exact 16-edge framing, a nontrivial discarded frame, and
six 32-frame endpoint groups. The candidate returned centered values `-2048,
-2047, -1, 0, 1, 2047` for raw codes `000, 001, 7FF, 800, 801, FFF`; the
baseline failed the same checks. See `results/SIMULATION_RESULTS.md`.

The retained Vivado 2025.2 reports show WNS `+6.874 ns`, WHS `+0.106 ns`,
192/192 routable nets complete, zero DRC/methodology findings, the 100 MHz and
36 MHz clocks, and the JC mapping N17/P18/P17. External ADC input timing remains
unclosed, and inherited CDC findings remain disclosed.

Historical evidence recorded successful FPGA configuration of the candidate.
The public release removes the machine-specific JTAG identity, programming log,
bitstream, checkpoint and waveform/log products. A repeat must rebuild the
candidate, supply an explicit target and hash to `hardware/program_candidate.tcl`,
and retain new evidence outside the checkout.

## Evidence boundary

No measured `VA`, `Vin`, or raw UART endpoint capture was retained. Functional
ADC validation is therefore **NOT RUN**, not inferred from simulation,
implementation, or JTAG configuration. The decisive future measurements remain
0 V, measured midscale, and approximately `VA - 50 mV`, following
`results/HARDWARE_TEST_PROCEDURE.md`.

The timing/framing criteria follow the TI ADC121S101 Rev. H datasheet, especially
Figure 2 and Sections 8.3, 8.3.1, 8.3.2, and 8.4.2.
