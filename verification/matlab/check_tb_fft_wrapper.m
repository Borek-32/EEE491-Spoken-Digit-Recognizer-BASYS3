close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_fft_wrapper_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_fft_wrapper_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_fft_wrapper_output.txt');
bitaccurate_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_fft_wrapper_bitaccurate.txt');
rtl_file = fullfile(script_dir, '..', '..', 'rtl', 'FFT.vhd');
tb_file = fullfile(script_dir, '..', '..', 'testbench', 'tb_FFT.vhd');
if ~exist('fft_figure_dir', 'var') || isempty(fft_figure_dir)
    fft_figure_dir = fullfile(script_dir, '..', 'figures', 'fft_alignment_fixed_20260713_final');
end
if ~exist(fft_figure_dir, 'dir'); mkdir(fft_figure_dir); end

fid = fopen(ref_file, 'r');
header = fscanf(fid, '%d', 4);
input_waveform = int64(fscanf(fid, '%d'));
fclose(fid);

sample_period_x10us = int64(header(1));
tone_hz = int64(header(2));
amplitude = int64(header(3));
fft_length = int64(header(4));

bin_count = int64(256);
tone_bin = idivide(tone_hz * fft_length * sample_period_x10us, int64(10000000), 'floor');
fft_peak = idivide(fft_length * amplitude, int64(2), 'floor');
stored_word = bitshift(fft_peak * fft_peak, -29);

expected = int64(zeros(double(bin_count), 2));
for i = 1:double(bin_count)
    expected(i, :) = [i - 1 0];
end
if tone_bin >= 0 && tone_bin < bin_count
    expected(double(tone_bin) + 1, :) = [tone_bin stored_word];
end

writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    error('Missing testbench output: %s', out_file);
end
if ~isfile(bitaccurate_file)
    error('Missing AMD XFFT bit-accurate reference: %s', bitaccurate_file);
end

output_info = dir(out_file);
dependency_info = [dir(ref_file); dir(rtl_file); dir(tb_file)];
if output_info.datenum < max([dependency_info.datenum])
    error('Stale tb_fft_wrapper output: rerun tb_FFT after editing its RTL, bench, or input reference');
end

actual = int64(readmatrix(out_file));
bitaccurate = int64(readmatrix(bitaccurate_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_fft_wrapper output size mismatch');
end
if ~isequal(size(bitaccurate), size(expected))
    error('AMD XFFT bit-accurate reference size mismatch');
end

diff = actual - expected;
expected_addresses = int64((0:(double(bin_count) - 1))');
if any(actual(:, 1) ~= expected_addresses)
    error('tb_fft_wrapper address column is not the complete ordered range 0..255');
end
if any(bitaccurate(:, 1) ~= expected_addresses)
    error('AMD XFFT bit-accurate address column is not the complete ordered range 0..255');
end

[expected_peak_value, expected_peak_row] = max(expected(:, 2));
[actual_peak_value, actual_peak_row] = max(actual(:, 2));
expected_peak_bin = expected(expected_peak_row, 1);
actual_peak_bin = actual(actual_peak_row, 1);
max_abs_error = max(abs(diff(:, 2)));
mismatched_bins = nnz(diff(:, 2) ~= 0);
bitaccurate_diff = actual - bitaccurate;
bitaccurate_max_abs_error = max(abs(bitaccurate_diff(:, 2)));
bitaccurate_mismatched_bins = nnz(bitaccurate_diff(:, 2) ~= 0);
% A uniform 64-count gate is deliberately much tighter than the former
% percentage-of-peak bound, which could hide a skipped input sample.  For this
% fixed stimulus, the AMD bit-accurate model is also required to match exactly.
per_bin_tolerance = int64(64) * ones(size(expected(:, 2)), 'int64');
bins_over_tolerance = find(abs(diff(:, 2)) > per_bin_tolerance);
max_allowed_error = max(per_bin_tolerance);

full_figure = figure('Name', 'tb_fft_wrapper', 'Position', [100 100 1600 900]);
set(full_figure, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
subplot(3, 1, 1);
plot(double(0:(length(input_waveform) - 1)), double(input_waveform));
grid on; title(['input waveform, tone = ' num2str(tone_hz) ' Hz, Ts = ' num2str(double(sample_period_x10us) / 10) ' us']);
subplot(3, 1, 2);
plot(double(expected(:, 1)), double(expected(:, 2))); hold on;
plot(double(bitaccurate(:, 1)), double(bitaccurate(:, 2)), ':');
plot(double(actual(:, 1)), double(actual(:, 2)), '--');
grid on; legend('integer ideal', 'AMD bit-accurate model', 'RTL testbench');
title(['FFT magnitude output: expected peak bin ' num2str(expected_peak_bin) ...
    ', DUT peak bin ' num2str(actual_peak_bin)]);
subplot(3, 1, 3);
stem(double(expected(:, 1)), double(diff(:, 2)));
grid on; title(['RTL - integer ideal: max |error| = ' num2str(max_abs_error) ...
    '; RTL - AMD model: max |error| = ' num2str(bitaccurate_max_abs_error)]);
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);

closeup_bins = max(int64(0), tone_bin - int64(6)):min(bin_count - int64(1), tone_bin + int64(6));
closeup_rows = double(closeup_bins + 1);
closeup_figure = figure('Name', 'tb_fft_wrapper_peak_alignment', 'Position', [140 140 1400 700]);
set(closeup_figure, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
stem(double(expected(closeup_rows, 1)), double(expected(closeup_rows, 2)), 'filled'); hold on;
stem(double(bitaccurate(closeup_rows, 1)), double(bitaccurate(closeup_rows, 2)), ':');
stem(double(actual(closeup_rows, 1)), double(actual(closeup_rows, 2)), '--');
grid on; xlim([double(closeup_bins(1)) - 0.5 double(closeup_bins(end)) + 0.5]);
legend('integer ideal', 'AMD bit-accurate model', 'RTL testbench', 'Location', 'best');
title(['FFT peak-address check: expected = ' num2str(expected_peak_bin) ...
    ', DUT = ' num2str(actual_peak_bin)]);
xlabel('FFT bin / RAM address'); ylabel('magnitude-squared word');
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);

exportgraphics(full_figure, fullfile(fft_figure_dir, 'tb_fft_wrapper.png'), 'Resolution', 300);
savefig(full_figure, fullfile(fft_figure_dir, 'tb_fft_wrapper.fig'));
exportgraphics(closeup_figure, fullfile(fft_figure_dir, 'tb_fft_wrapper_peak_alignment.png'), 'Resolution', 300);
savefig(closeup_figure, fullfile(fft_figure_dir, 'tb_fft_wrapper_peak_alignment.fig'));

if actual_peak_bin ~= expected_peak_bin
    error('tb_fft_wrapper peak address FAIL: expected bin %d, DUT address %d', ...
        expected_peak_bin, actual_peak_bin);
end
if max_abs_error > max_allowed_error
    error('tb_fft_wrapper magnitude FAIL: max abs error %d exceeds tolerance %d', ...
        max_abs_error, max_allowed_error);
end
if ~isempty(bins_over_tolerance)
    first_bad_row = bins_over_tolerance(1);
    error('tb_fft_wrapper per-bin magnitude FAIL at bin %d: error %d exceeds tolerance %d', ...
        expected(first_bad_row, 1), abs(diff(first_bad_row, 2)), per_bin_tolerance(first_bad_row));
end
if bitaccurate_mismatched_bins ~= 0
    error('tb_fft_wrapper AMD bit-accurate FAIL: %d bins differ, max abs error %d', ...
        bitaccurate_mismatched_bins, bitaccurate_max_abs_error);
end

disp(['tb_fft_wrapper PASS. Tone bin = ' num2str(tone_bin) ...
    ', DUT peak bin = ' num2str(actual_peak_bin) ...
    ', expected peak = ' num2str(expected_peak_value) ...
    ', DUT peak = ' num2str(actual_peak_value) ...
    ', mismatched bins = ' num2str(mismatched_bins) ...
    ', bins over tolerance = ' num2str(numel(bins_over_tolerance)) ...
    ', max abs error = ' num2str(max_abs_error) ...
    ' (limit ' num2str(max_allowed_error) ')' ...
    ', AMD-model mismatches = ' num2str(bitaccurate_mismatched_bins) ...
    ', AMD-model max abs error = ' num2str(bitaccurate_max_abs_error) ...
    ', Ts = ' num2str(double(sample_period_x10us) / 10) ' us']);
