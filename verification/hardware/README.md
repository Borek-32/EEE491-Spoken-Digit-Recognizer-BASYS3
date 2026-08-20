# Live MFCC hardware capture

These MATLAB functions parse the `top_module` debug protocol at 1,000,000 baud.
They are distinct from the standalone 921,600-baud ADC/UART diagnostic.

No final labeled accuracy session is included. To create a new session, first
build and program a fresh JC bitstream, retain the programming transcript, and
provide every machine-specific value explicitly:

```matlab
cd('verification/hardware')
run_live_accuracy_session(10, uartPort, jtagTarget, bitPath, ...
    expectedBitSha256, programmingLogPath, evidenceOutputDirectory)
```

The launcher requires a nonempty UART port and JTAG target identity, verifies
the exact bitstream hash, checks a recent PASS programming record, and refuses
post-result retries. It pre-generates a balanced randomized schedule of 100
declared trials (ten per digit) by default. For each prompt, the operator arms
the UART and then starts one spoken-digit acquisition.

A completed session contains the schedule and metadata, raw bytes and decoded
MAT data for each trial, append-after-every-trial CSV, per-digit metrics, a
confusion matrix with a separate protocol-failure column, a summary, logger
source snapshot, programming provenance, lifecycle index, and SHA-256 manifest.
The primary metric is correct/planned; conditional correct/protocol-complete and
transport completion are reported separately.

Run the non-hardware evidence-path self-test with:

```matlab
run_live_accuracy_session("selftest")
```

Each live trial contains 63 frames. Each frame contains 1,362 big-endian 32-bit
words: marker/address/COMP status, 512 ADC words, 512 WINDOW words, 256 FFT
words, 32 MEL words, 32 LOGMEL words, eight DCT words, and the end marker. The
decision is accepted only from frame address 15,872.
