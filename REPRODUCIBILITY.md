# Reproducibility guide

This release separates reproducible inputs from retained historical evidence.
The clean scripts create all Vivado state outside the repository. Existing
reports under `implementation/` are never consumed by the build.

## Reference environment

The release was curated against:

- AMD Vivado 2025.2, build 6299465, IP build 6300035;
- MATLAB R2025b Update 5 (`25.2.0.3177638`);
- KiCad 10.0.3;
- Git 2.53.0;
- Python 3.14.4.

The FPGA part is `xc7a35tcpg236-1`. The clean Vivado recreation does not depend
on an installed Basys 3 board-part definition.

## 1. Verify the release

From the repository root:

```bash
python3 scripts/check_release.py
```

This checks the allowlisted source counts, required files, absence of generated
Vivado products and private machine identifiers, KiCad evidence boundary, Git
clean-filter byte stability for every manifest candidate, and every entry in
`SHA256SUMS`. Run it from a Git working tree so `.gitattributes` can be applied.
Maintainers may regenerate the portable manifest only after an intentional
content change:

```bash
python3 scripts/check_release.py --write-checksums
python3 scripts/check_release.py
```

Paths in `SHA256SUMS` are sorted repository-relative POSIX paths. The manifest
does not include itself or `.git/`.

### Complete non-hardware workflow

The documented steps below are also available through one fail-closed wrapper:

```bash
scripts/run_release_checks.sh ../mfcc-build-v1.0.0 \
  ../mfcc-results-v1.0.0 --top-smoke --jobs 4
```

`--top-smoke` is opt-in; omit it to retain an explicit `TOP_SMOKE=NOT_RUN`
boundary. Set `VIVADO_BIN=/path/to/vivado` or `MATLAB_BIN=/path/to/matlab` to
override the default `vivado` and `matlab` commands. Both supplied output paths
and the derived `RESULTS_DIR.runtime` path must be fresh and outside the
repository. The wrapper keeps Vivado's journals, logs and `.Xil` process state
in that runtime directory. It also refuses to overlap the MATLAB gate with an
existing MATLAB process and serializes concurrent wrapper invocations with a
per-user runtime lock. Physical programming is never part of this workflow.

## 2. Recreate the full JC project

Choose build, results and process-runtime paths outside the checkout that do
not already exist. The standalone commands in the following sections share
these absolute shell variables:

```bash
repo_root=$(pwd -P)
build_dir=$(readlink -m ../mfcc-build-v1.0.0)
results_dir=$(readlink -m ../mfcc-results-v1.0.0)
runtime_dir=$(readlink -m ../mfcc-runtime-v1.0.0)
mkdir -- "$runtime_dir"

(
  cd "$runtime_dir"
  vivado -mode batch -notrace \
    -journal "$runtime_dir/01-recreate.jou" \
    -log "$runtime_dir/01-recreate.log" \
    -source "$repo_root/scripts/recreate_project.tcl" \
    -tclargs "$build_dir"
)
```

The script copies `rtl/`, `testbench/`, `constraints/` and `verification/` into
`../mfcc-build-v1.0.0/`. It stages byte-for-byte `ip/` and `data/`
under the external compatibility path
`../mfcc-build-v1.0.0/mfcc-recog 1.4.srcs/sources_1/`; Vivado validates that
original XCI customization context and the relative COE paths. It then creates
a fresh project, sets VHDL 2008, adds only `constraints/jc_homefab.xdc`, and
reapplies each resolved COE path plus the defining multiplier and FFT
customizations through Vivado's IP API to initialize fresh model state. Vivado
writes the same relative COE values back into the external XCI copies before
regenerating IP. The script refuses to overwrite an existing directory or
build inside the repository.

## 3. Run the bounded behavioral regression

After project recreation:

```bash
(
  cd "$runtime_dir"
  vivado -mode batch -notrace \
    -journal "$runtime_dir/02-safe-testbenches.jou" \
    -log "$runtime_dir/02-safe-testbenches.log" \
    -source "$repo_root/verification/run_testbenches.tcl" \
    -tclargs "$build_dir"
)
```

The default safe set is `tb_CTRL`, `tb_debug`, `tb_WINDOW`, `tb_FFT`, `tb_MEL`,
`tb_LOGMEL`, `tb_DCT`, `tb_comp`, and `tb_seven_segment`. Each bench is bounded
to 20 ms simulated time, and the runner scans XSim's transcript before printing
PASS. `tb_ADC` is rejected by this interface because its long acquisition run
needs an explicitly monitored workflow. `tb_top_module` remains opt-in:

```bash
(
  cd "$runtime_dir"
  vivado -mode batch -notrace \
    -journal "$runtime_dir/03-top-smoke.jou" \
    -log "$runtime_dir/03-top-smoke.log" \
    -source "$repo_root/verification/run_testbenches.tcl" \
    -tclargs "$build_dir" tb_top_module
)
```

Testbench outputs are written beneath the external project's
`verification/tb_output/`, not into the checkout.

Run the matching MATLAB fixed-point checks against that external snapshot:

```bash
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

The FFT checker uses the AMD bit-accurate model packaged with Vivado. Source
the Vivado settings script first, set `VIVADO_ROOT=/path/to/Vivado`, or use the
complete wrapper, which infers that root from an explicit `VIVADO_BIN` path.
The post-`run` cleanup must remain in the batch caller: MATLAB R2025b can abort
during process teardown if the suite's cleanup guards survive that boundary.
The process must exit zero and emit both required PASS markers. Do not run
another MATLAB process concurrently with this verification workload.

The retained `verification/tb_output/` files are historical reference evidence.
A fresh regression should be judged from the external build snapshot.

## 4. Synthesize, implement and validate

Use the fresh results path declared in step 2:

```bash
(
  cd "$runtime_dir"
  vivado -mode batch -notrace \
    -journal "$runtime_dir/04-build-jc.jou" \
    -log "$runtime_dir/04-build-jc.log" \
    -source "$repo_root/scripts/build_jc_homefab.tcl" \
    -tclargs "$build_dir" "$results_dir" 4
)
```

The optional final argument is the positive Vivado job count. The script:

1. resets and runs synthesis and implementation through `write_bitstream`;
2. writes timing, routing, DRC, methodology, utilization, I/O, clocks, CDC and
   timing-check reports outside the repository;
3. requires non-negative routed setup and hold slack;
4. requires every routable net to be routed;
5. rejects DRC error, critical-warning, or warning severity;
6. validates the exact 39-port package-pin dictionary and the 100 MHz clock;
7. copies the generated `.bit` only to the external results directory.

The external-interface limitation remains: the XDC constrains the internal
100 MHz clock but contains no ADC-datasheet-derived input/output delays.

## 5. KiCad evidence

The public `kicad/originals/` copies and reconciled pair are sufficient to rerun
the net assignment and verification. The visible decorative copper username is
retained as intentional public attribution; machine-local filesystem paths are
sanitized. See the directory README for commands and exact limits.

KiCad's Python runtime can rebuild the named-net PCB:

```bash
cd hardware/homefab_mic_adc_pcb/kicad
flatpak run --command=python3 org.kicad.KiCad \
  tools/assign_schematic_nets.py \
  originals/mfccsmd.kicad_pcb mfcc_homefab_named_nets.kicad_pcb \
  --manifest evidence/net_assignment_manifest.json
```

Run the fail-closed bundle verifier after exporting current KiCad netlist,
ERC, DRC and render artifacts as described in the local README:

```bash
python3 tools/verify_named_bundle.py . \
  --desktop-schematic originals/mfcc.kicad_sch \
  --desktop-board originals/mfccsmd.kicad_pcb \
  --output evidence/bundle_validation.json
```

`PASS_NET_ASSIGNMENT` means exact net-name coverage only. It is not a claim of
fab-ready DRC/ERC closure.

## 6. Hardware programming and capture

Build first, then inspect the live hardware target. Programming is deliberately
separate from implementation and is never performed by the build script:

```bash
(
  cd "$runtime_dir"
  vivado -mode batch -notrace \
    -journal "$runtime_dir/05-program-jc.jou" \
    -log "$runtime_dir/05-program-jc.log" \
    -source "$repo_root/hardware/homefab_mic_adc_pcb/programming/program_full_mfcc_jc.tcl" \
    -tclargs "$results_dir/top_module_jc_homefab.bit" \
    YOUR_EXPLICIT_JTAG_TARGET_SUBSTRING \
    YOUR_EXPLICIT_64_HEX_BITSTREAM_SHA256
)
```

The programming script requires and validates the selected bitstream's SHA-256.
It requires exactly one target match and exactly one `xc7a35t` device.

For a new labeled accuracy session, call MATLAB with all environment-specific
inputs. The output directory must be fresh and outside the repository:

```matlab
run_live_accuracy_session(10, uartPort, jtagTarget, bitPath, ...
    expectedBitSha256, programmingLogPath, evidenceOutputDirectory)
```

No retained final-system session is shipped. A newly generated session is new
evidence and must not be confused with the historical claims in the report.
