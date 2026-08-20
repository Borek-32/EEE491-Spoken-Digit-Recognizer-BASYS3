#include "xfft_v9_1_bitacc_cmodel.h"

#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <vector>

int main(int argc, char **argv) {
    if (argc != 3) {
        std::cerr << "usage: xfft_bitaccurate_reference <tb_fft_ref.txt> <output.txt>\n";
        return 2;
    }

    std::ifstream input_file(argv[1]);
    if (!input_file) {
        std::cerr << "cannot open input reference: " << argv[1] << "\n";
        return 2;
    }

    int sample_period_x10us = 0;
    int tone_hz = 0;
    int amplitude = 0;
    int fft_length = 0;
    input_file >> sample_period_x10us >> tone_hz >> amplitude >> fft_length;
    if (!input_file || fft_length != 512) {
        std::cerr << "expected a valid 512-sample FFT reference file\n";
        return 2;
    }

    constexpr int nfft = 9;
    constexpr int sample_count = 1 << nfft;
    constexpr double input_scale = static_cast<double>(1 << 19);

    std::vector<double> real_input(sample_count);
    std::vector<double> imag_input(sample_count, 0.0);
    for (int i = 0; i < sample_count; ++i) {
        int sample = 0;
        input_file >> sample;
        if (!input_file) {
            std::cerr << "input reference ended before sample 511\n";
            return 2;
        }
        real_input[i] = static_cast<double>(sample) / input_scale;
    }

    xilinx_ip_xfft_v9_1_generics generics{};
    generics.C_NFFT_MAX = nfft;
    generics.C_ARCH = 4;             // radix-2 lite burst I/O
    generics.C_HAS_NFFT = 0;
    generics.C_USE_FLT_PT = 0;
    generics.C_INPUT_WIDTH = 20;
    generics.C_TWIDDLE_WIDTH = 16;
    generics.C_HAS_SCALING = 0;
    generics.C_HAS_BFP = 0;
    generics.C_HAS_ROUNDING = 0;     // truncation
    generics.C_NSSR = 1;
    generics.C_SYSTOLICFFT_INV = 0;

    xilinx_ip_xfft_v9_1_state *state = xilinx_ip_xfft_v9_1_create_state(generics);
    if (state == nullptr) {
        std::cerr << "AMD XFFT model state creation failed\n";
        return 1;
    }

    std::vector<int> scaling_schedule(nfft, 0);
    xilinx_ip_xfft_v9_1_inputs model_input{};
    model_input.nfft = nfft;
    model_input.xn_re = real_input.data();
    model_input.xn_re_size = sample_count;
    model_input.xn_im = imag_input.data();
    model_input.xn_im_size = sample_count;
    model_input.scaling_sch = scaling_schedule.data();
    model_input.scaling_sch_size = nfft;
    model_input.direction = 1;

    std::vector<double> real_output(sample_count);
    std::vector<double> imag_output(sample_count);
    xilinx_ip_xfft_v9_1_outputs model_output{};
    model_output.xk_re = real_output.data();
    model_output.xk_re_size = sample_count;
    model_output.xk_im = imag_output.data();
    model_output.xk_im_size = sample_count;

    const int status = xilinx_ip_xfft_v9_1_bitacc_simulate(state, model_input, &model_output);
    xilinx_ip_xfft_v9_1_destroy_state(state);
    if (status != 0 || model_output.xk_re_size != sample_count ||
        model_output.xk_im_size != sample_count) {
        std::cerr << "AMD XFFT bit-accurate simulation failed\n";
        return 1;
    }

    std::ofstream output_file(argv[2]);
    if (!output_file) {
        std::cerr << "cannot create output reference: " << argv[2] << "\n";
        return 2;
    }

    for (int bin = 0; bin < sample_count / 2; ++bin) {
        const auto real_word = static_cast<std::int64_t>(std::llround(real_output[bin] * input_scale));
        const auto imag_word = static_cast<std::int64_t>(std::llround(imag_output[bin] * input_scale));
        const auto magnitude = static_cast<std::uint64_t>(real_word * real_word + imag_word * imag_word);
        output_file << bin << ' ' << (magnitude >> 29) << '\n';
    }

    return 0;
}
