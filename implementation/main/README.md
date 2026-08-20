# Historical main implementation reports

These four text reports preserve the routed result from the finalized main
project before public-repository reconstruction. They record WNS `+0.630 ns`,
WHS `+0.014 ns`, complete routing, and routed DRC/utilization data.

No corresponding baseline constraint file is packaged: the only public build
profile is `../../constraints/jc_homefab.xdc`. These reports are historical
evidence, not inputs to `scripts/recreate_project.tcl`, and must not be read as
proof of ADC board-level timing because 36 `TIMING-18` missing-I/O-delay
warnings remain in the timing summary.
