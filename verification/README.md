# VHDL, XSim and MATLAB verification

This directory contains the VHDL-bench inputs and retained outputs, MATLAB
fixed-point cross-checks, IP memory images, and the bounded XSim runner. A clean
run operates on the copy created in an external Vivado project, so new output
does not modify the public checkout.

Flow:

1. A VHDL bench reads `ref_data/*.txt`.
2. It writes integer results to `tb_output/*.txt`.
3. The matching script in `matlab/` computes an independent fixed-point result
   and compares it with the fresh bench output.

The default runner covers nine module benches. `tb_ADC` is deliberately
rejected because the long acquisition simulation is CPU-intensive and requires
active monitoring. `tb_top_module` is opt-in.

After recreating the project with the external paths from the root
`REPRODUCIBILITY.md`, run XSim from that external runtime directory and MATLAB
from the external build directory:

```bash
repo_root=$(pwd -P)
build_dir=$(readlink -m ../mfcc-build-v1.0.0)
runtime_dir=$(readlink -m ../mfcc-runtime-v1.0.0)

(
  cd "$runtime_dir"
  vivado -mode batch -notrace \
    -journal "$runtime_dir/02-safe-testbenches.jou" \
    -log "$runtime_dir/02-safe-testbenches.log" \
    -source "$repo_root/verification/run_testbenches.tcl" \
    -tclargs "$build_dir"
)

matlab_lock=${XDG_RUNTIME_DIR:-/tmp}/mfcc-release-matlab-$(id -u).lock
matlab_log="$runtime_dir/matlab-safe.log"
(
  set -euo pipefail
  if ! flock -n 9; then
    echo "another MFCC release MATLAB gate is active" >&2
    exit 2
  fi
  if pgrep -x MATLAB >/dev/null 2>&1; then
    echo "another MATLAB process is active; wait before running this gate" >&2
    exit 2
  fi
  cd "$build_dir"
  if ! matlab -batch \
    "run('verification/matlab/run_safe_module_verifiers.m'); diary('off'); clear cleanup_diary cleanup_state; fprintf('MATLAB_CALLER_CLEANUP_PASS\n');" \
    2>&1 | tee "$matlab_log"; then
    echo "MATLAB verification process failed" >&2
    exit 1
  fi
  grep -Fqx 'SAFE_MODULE_VERIFIERS_PASS count=9' "$matlab_log"
  grep -Fqx 'MATLAB_CALLER_CLEANUP_PASS' "$matlab_log"
) 9>"$matlab_lock"
```

The caller-side cleanup after `run(...)` avoids a MATLAB R2025b allocator abort
during batch-process teardown; it does not bypass any checker. The lock and
process check keep this memory-intensive gate from overlapping another MATLAB
job. A valid run exits zero and emits both the aggregate and caller-cleanup PASS
markers.

The FFT gate requires the DUT peak address to match the expected bin, each
integer-reference magnitude error to remain within 64 counts, and all 256
words to match the retained AMD XFFT v9.1 bit-accurate reference exactly.

The retained `tb_output/` files establish what was checked during development;
they are not silently substituted for a fresh run.
