# ADC121S101 datasheet-derived behavioral RTL simulation

Date: 19 August 2026

## Evidence boundary

This is RTL simulation evidence, not a bench result. The purpose-built digital
behavioral model derives selected serial behavior from the TI ADC121S101 Rev. H
datasheet and uses the 2.7-3.6 V worst-case values `tACC=40 ns`, `tEN=20 ns`,
and `tDIS=25 ns`. It models the phase-dependent optional fourth leading zero,
the `Z2/Z1/Z0` prefix, `DB11..DB0` MSB-first, 16 falling edges, and TRI-STATE
after the last edge. It does not model analog conversion, board-level signal
integrity, or assert every acquisition, quiet-time, and throughput requirement.

## Stimulus and assertions

- Frame zero deliberately carries raw code `A5A` as a conservative dummy and
  must be discarded by this trial. This does not claim that every `start_in`
  transition is equivalent to ADC power-up or that TI requires that discard.
- Six following groups each contain 32 identical conversions: `000`, `001`,
  `7FF`, `800`, `801`, and `FFF`.
- Every closed frame must have exactly 16 falling SCLK edges.
- CS must precede the first falling SCLK edge by at least 10 ns.
- UART is decoded low byte first and compared against the centered signed word.
- The testbench accelerates UART to 10,000,000 baud. It checks UART framing,
  byte order, and word values; it does not verify the production 921600 baud.

## Preserved baseline: FAIL

The preserved source produced 12 falling edges in its first frame and 17 in
later frames. Later frames also asserted CS and the first falling SCLK edge
together, giving 0 ns setup. The baseline log therefore contains the expected
frame-count, setup, and value failures.

The model does not claim to reproduce the exact near-zero full-scale bench
value. Once the invalid baseline receiver samples SDATA after TRI-STATE, the
physical input level is uncontrolled and need not resolve like the simulator.

Evidence: `baseline_simulation_xsim.log` and `baseline_simulation.wdb`.

## Isolated candidate: PASS

| ADC raw | UART word | Signed result |
|---:|---:|---:|
| `000` | `F800` | -2048 |
| `001` | `F801` | -2047 |
| `7FF` | `FFFF` | -1 |
| `800` | `0000` | 0 |
| `801` | `0001` | 1 |
| `FFF` | `07FF` | 2047 |

The deliberately injected `A5A` first frame did not contaminate the first
average. Every candidate frame that closed during this simulation contained
exactly 16 falling edges, and no CS-setup, UART, frame-count, or signed-value
assertion failed. The first-frame monitor reported 55.556 ns from CS assertion
to the first falling SCLK edge and reported the optional fourth leading zero as
exercised. The final PASS occurred at 340.385 us.

Evidence: `candidate_simulation_xsim.log` and `candidate_simulation.wdb`.

## Reproduction

From the `sim/` directory:

```bash
./run_xsim.sh
./run_xsim.sh ../baseline/PCB.vhd
```

The first command must exit zero. The baseline command is expected to exit one.

## Remaining gate

Hardware is NOT RUN. The candidate becomes a confirmed fix only when a new
bitstream produces retained UART captures near -2048 at 0 V, 0 at midscale,
and +2047 at full scale.
