#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 DUT_VHDL FRESH_EXTERNAL_RUN_DIR" >&2
    exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
dut=$(readlink -f "$1")
run_dir=$(readlink -m "$2")

if [[ ! -f "$dut" ]]; then
    echo "DUT not found: $dut" >&2
    exit 2
fi
if [[ -e "$run_dir" ]]; then
    echo "run directory already exists; choose a fresh path: $run_dir" >&2
    exit 2
fi

tool_path() {
    local tool=$1
    if [[ -n ${VIVADO_BIN:-} ]]; then
        printf '%s/%s\n' "${VIVADO_BIN%/}" "$tool"
    else
        command -v "$tool"
    fi
}

xvhdl=$(tool_path xvhdl)
xelab=$(tool_path xelab)
xsim=$(tool_path xsim)

mkdir -p "$run_dir"
cd "$run_dir"

"$xvhdl" --2008 "$here/clk_wiz_0_sim.vhd" 2>&1 | tee xvhdl_clk_wiz.log
"$xvhdl" --2008 "$dut" 2>&1 | tee xvhdl_dut.log
"$xvhdl" --2008 "$here/tb_adc121s101_uart.vhd" 2>&1 | tee xvhdl_tb.log
"$xelab" --debug typical tb_adc121s101_uart \
    --snapshot tb_adc121s101_uart_sim 2>&1 | tee xelab.log
"$xsim" tb_adc121s101_uart_sim --runall --log xsim.log

if rg -q '^Note: PASS:' xsim.log && ! rg -q '^(Error|Failure):' xsim.log; then
    echo "SIMULATION_RESULT=PASS"
    echo "PASS_LOG=$run_dir/xsim.log"
    exit 0
fi

echo "simulation did not meet the ADC/UART acceptance criteria" >&2
echo "FAIL_LOG=$run_dir/xsim.log" >&2
exit 1
