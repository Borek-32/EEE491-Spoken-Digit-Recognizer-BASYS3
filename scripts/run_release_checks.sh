#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: scripts/run_release_checks.sh BUILD_DIR RESULTS_DIR [--top-smoke] [--jobs N]

BUILD_DIR, RESULTS_DIR and the derived RESULTS_DIR.runtime must be fresh paths
outside the repository. Vivado journals, logs and process state stay in the
derived runtime directory.
VIVADO_BIN overrides the Vivado executable (default: vivado).
MATLAB_BIN overrides the MATLAB executable (default: matlab).
This workflow never opens the hardware manager or programs a device.
EOF
}

if [[ $# -lt 2 ]]; then
    usage
    exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
build_dir=$(readlink -m "$1")
results_dir=$(readlink -m "$2")
runtime_dir=$(readlink -m "${results_dir}.runtime")
shift 2

top_smoke=0
jobs=4
while [[ $# -gt 0 ]]; do
    case "$1" in
        --top-smoke)
            top_smoke=1
            shift
            ;;
        --jobs)
            if [[ $# -lt 2 || ! $2 =~ ^[1-9][0-9]*$ ]]; then
                echo "--jobs requires a positive integer" >&2
                exit 2
            fi
            jobs=$2
            shift 2
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

for output_path in "$build_dir" "$results_dir" "$runtime_dir"; do
    case "$output_path/" in
        "$repo_root/"*)
            echo "output path must be outside the repository: $output_path" >&2
            exit 2
            ;;
    esac
    if [[ -e "$output_path" ]]; then
        echo "output path already exists; choose a fresh path: $output_path" >&2
        exit 2
    fi
done

vivado_cmd=${VIVADO_BIN:-vivado}
matlab_cmd=${MATLAB_BIN:-matlab}

require_command() {
    local command_name=$1
    if [[ $command_name == */* ]]; then
        if [[ ! -x $command_name ]]; then
            echo "executable not found: $command_name" >&2
            exit 2
        fi
    elif ! command -v "$command_name" >/dev/null 2>&1; then
        echo "command not found: $command_name" >&2
        exit 2
    fi
}

require_command python3
require_command "$vivado_cmd"
require_command "$matlab_cmd"
require_command flock
require_command pgrep
require_command grep
require_command tee

# The FFT MATLAB gate uses AMD's packaged bit-accurate C model. A sourced
# Vivado settings script normally exports XILINX_VIVADO; when VIVADO_BIN is an
# explicit executable path, infer the equivalent root so the override remains
# self-contained.
if [[ -z ${VIVADO_ROOT:-} && -z ${XILINX_VIVADO:-} ]]; then
    if [[ $vivado_cmd == */* ]]; then
        vivado_executable=$(readlink -f "$vivado_cmd")
    else
        vivado_executable=$(readlink -f "$(command -v "$vivado_cmd")")
    fi
    inferred_vivado_root=$(cd "$(dirname "$vivado_executable")/.." && pwd)
    if [[ -d $inferred_vivado_root/data/ip/xilinx/xfft_v9_1/cmodel ]]; then
        export VIVADO_ROOT=$inferred_vivado_root
    fi
fi

cd "$repo_root"
python3 scripts/check_release.py
mkdir -p -- "$runtime_dir"

run_vivado() {
    local run_name=$1
    shift
    (
        cd "$runtime_dir"
        "$vivado_cmd" -mode batch -notrace \
            -journal "$runtime_dir/${run_name}.jou" \
            -log "$runtime_dir/${run_name}.log" \
            "$@"
    )
}

run_vivado 01-recreate \
    -source "$repo_root/scripts/recreate_project.tcl" \
    -tclargs "$build_dir"

run_vivado 02-safe-testbenches \
    -source "$repo_root/verification/run_testbenches.tcl" \
    -tclargs "$build_dir"

if [[ $top_smoke -eq 1 ]]; then
    run_vivado 03-top-smoke \
        -source "$repo_root/verification/run_testbenches.tcl" \
        -tclargs "$build_dir" tb_top_module
else
    echo "TOP_SMOKE=NOT_RUN (pass --top-smoke to opt in)"
fi

matlab_lock_dir=${XDG_RUNTIME_DIR:-/tmp}
matlab_lock_path="$matlab_lock_dir/mfcc-release-matlab-$(id -u).lock"
matlab_gate_log="$runtime_dir/matlab-safe.log"
(
    if ! flock -n 9; then
        echo "another MFCC release MATLAB gate holds $matlab_lock_path" >&2
        exit 2
    fi
    if pgrep -x MATLAB >/dev/null 2>&1; then
        echo "another MATLAB process is active; wait for it before running the release gate" >&2
        exit 2
    fi
    cd "$build_dir"
    # R2025b must release the script's onCleanup guards in the batch caller
    # after run() returns; leaving them until process teardown can corrupt its
    # allocator after the FFT graphics workload.
    "$matlab_cmd" -batch \
        "run('verification/matlab/run_safe_module_verifiers.m'); diary('off'); clear cleanup_diary cleanup_state; fprintf('MATLAB_CALLER_CLEANUP_PASS\n');" \
        2>&1 | tee "$matlab_gate_log"
    if ! grep -Fqx 'SAFE_MODULE_VERIFIERS_PASS count=9' "$matlab_gate_log"; then
        echo "MATLAB aggregate PASS marker is missing" >&2
        exit 1
    fi
    if ! grep -Fqx 'MATLAB_CALLER_CLEANUP_PASS' "$matlab_gate_log"; then
        echo "MATLAB caller-cleanup marker is missing" >&2
        exit 1
    fi
) 9>"$matlab_lock_path"

run_vivado 04-build-jc \
    -source "$repo_root/scripts/build_jc_homefab.tcl" \
    -tclargs "$build_dir" "$results_dir" "$jobs"

cd "$repo_root"
python3 scripts/check_release.py
echo "RELEASE_WORKFLOW=PASS"
echo "BUILD_DIR=$build_dir"
echo "RESULTS_DIR=$results_dir"
echo "RUNTIME_DIR=$runtime_dir"
