# ADC121S101 alignment trial: future hardware procedure

Current status: historical JTAG configuration **PASS**; ADC endpoint capture
**NOT RUN**. Programming establishes FPGA configuration only.

## Rebuild and identity gate

Use the standalone project's optional candidate-source argument to create a
fresh external build, then calculate the generated bitstream's SHA-256. Program
only after visually inspecting the intended live JTAG target:

```bash
vivado -mode batch -notrace \
  -source ../hardware/program_candidate.tcl \
  -tclargs /external/results/PCB.bit \
  YOUR_EXPLICIT_JTAG_TARGET_SUBSTRING \
  YOUR_EXPLICIT_64_HEX_BITSTREAM_SHA256
```

No device serial, UART port, bitstream or log path is embedded in this release.
Retain the fresh programming transcript outside the checkout.

## Electrical safety

1. Establish common ground between FPGA, ADC board and voltage source.
2. Measure ADC supply `VA`; do not assume exactly 3.300 V.
3. Never apply `Vin > VA`, and never drive an unpowered ADC input.
4. Use a low-impedance midscale source.
5. Use approximately `VA - 50 mV` for the upper point to avoid overshoot.
6. Release BTNU before changing analog voltage.

## Capture sequence

Call `../hardware/capture_adc121s101_trial.m` with an explicit UART port and
external output directory. The UART format is 921600 baud, 8 data bits, no
parity, one stop bit; each signed word is transmitted low byte first.

For each voltage point:

1. Keep BTNU released; press/release BTNC and require LD0 high.
2. Apply the input and record DMM measurements of `VA` and `Vin`.
3. Open and flush the explicit UART endpoint while BTNU remains released.
4. Press and hold BTNU only after the flush; capture an even byte count.
5. Release BTNU before disconnecting or changing voltage.
6. Retain raw bytes, decoded values, time, source/bitstream hashes, board tag,
   `VA`, and `Vin` in the external evidence directory.

Reject a run after a USB disconnect, odd byte count, or decoded value outside
`-2048..+2047`.

## Expected values and empty result record

`ideal_code = min(4095, floor(4096 * Vin / VA))`; centered result is
`ideal_code - 2048`.

| Field | Ground | Midscale | Upper point |
| --- | --- | --- | --- |
| Capture time | NOT RUN | NOT RUN | NOT RUN |
| Measured `VA` | NOT RUN | NOT RUN | NOT RUN |
| Measured `Vin` | NOT RUN | NOT RUN | NOT RUN |
| First raw UART words | NOT RUN | NOT RUN | NOT RUN |
| Median / range | NOT RUN | NOT RUN | NOT RUN |
| PASS / FAIL | NOT RUN | NOT RUN | NOT RUN |

Ground alone cannot distinguish a corrected receiver from a lost-MSB case.
Measured midscale and the upper point are decisive.
