#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
verification_dir=$(cd "$script_dir/.." && pwd)
vivado_root=${VIVADO_ROOT:-${XILINX_VIVADO:-}}
if [[ -z $vivado_root ]]; then
    echo "set VIVADO_ROOT or source the Vivado settings script first" >&2
    exit 2
fi
cmodel_zip="$vivado_root/data/ip/xilinx/xfft_v9_1/cmodel/xfft_v9_1_bitacc_cmodel_lin64.zip"
input_file=${1:-"$verification_dir/ref_data/tb_fft_wrapper_ref.txt"}
output_file=${2:-"$verification_dir/tb_output/expected_tb_fft_wrapper_bitaccurate.txt"}

if [[ ! -f "$cmodel_zip" ]]; then
    echo "AMD XFFT bit-accurate model archive not found: $cmodel_zip" >&2
    exit 2
fi

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

unzip -q "$cmodel_zip" -d "$build_dir"
g++ -std=c++17 -O2 \
    -I"$build_dir" \
    "$script_dir/xfft_bitaccurate_reference.cpp" \
    -L"$build_dir" \
    -Wl,-rpath,"$build_dir" \
    -lIp_xfft_v9_1_bitacc_cmodel \
    -o "$build_dir/xfft_bitaccurate_reference"

# MATLAB prepends its bundled C++ runtime to LD_LIBRARY_PATH.  The helper is
# compiled with the host compiler, so inheriting MATLAB's older libstdc++ can
# make the executable fail before main() with a missing GLIBCXX symbol.  Keep
# only the extracted AMD model directory here; the loader will use the normal
# host runtime for all remaining dependencies.
LD_LIBRARY_PATH="$build_dir" \
    "$build_dir/xfft_bitaccurate_reference" "$input_file" "$output_file"

echo "XFFT_BITACCURATE_REFERENCE_PASS $output_file"
