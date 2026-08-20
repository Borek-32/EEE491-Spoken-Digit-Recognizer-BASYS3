close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_mel_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_mel_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_mel_output.txt');
coeff_file = fullfile(script_dir, '..', 'mem_init_files', 'blk_mem_gen_6.mif');
if ~exist('mel_figure_dir', 'var') || isempty(mel_figure_dir)
    mel_figure_dir = fullfile(script_dir, '..', 'figures', 'mel_address_identity_fixed_20260727');
end
if ~exist(mel_figure_dir, 'dir'); mkdir(mel_figure_dir); end

ref = int64(readmatrix(ref_file));
start_bin = ref(1, 1);
bin_step = ref(1, 2);
bin_count = ref(1, 3);

fft_data = int64(zeros(bin_count, 1));
for i = 1:bin_count
    fft_data(i) = start_bin + (i - 1) * bin_step;
end

coeff_lines = strip(readlines(coeff_file));
coeff_lines = coeff_lines(strlength(coeff_lines) > 0);
coeff = int64(zeros(32 * 256, 1));
for i = 1:length(coeff)
    coeff(i) = int64(bin2dec(coeff_lines(i)));
end

expected = int64(zeros(32, 2));
for filter_idx = 0:31
    accumulator = int64(0);
    for bin_idx = 0:255
        coeff_addr = filter_idx * 256 + bin_idx + 1;
        fft_addr = bin_idx;
        accumulator = accumulator + fft_data(fft_addr + 1) * coeff(coeff_addr);
    end
    stored_word = bitshift(accumulator, -16);
    stored_word = mod(stored_word, int64(4294967296));
    expected(filter_idx + 1, :) = [filter_idx stored_word];
end

writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    error('Missing testbench output: %s', out_file);
end

actual = int64(readmatrix(out_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_mel output size mismatch');
end

diff = actual - expected;
if any(diff(:) ~= 0)
    disp([expected actual diff]);
    disp(['tb_mel max abs error = ' num2str(max(abs(diff(:))))]);
    error('tb_mel FAIL: expected and DUT outputs differ');
else
    disp('tb_mel PASS');
end

mel_figure = figure('Name', 'tb_mel', 'Position', [100 100 1600 900]);
set(mel_figure, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
subplot(3, 1, 1);
plot(double(0:(bin_count - 1)), double(fft_data));
grid on; title('input FFT waveform');
subplot(3, 1, 2);
plot(double(expected(:, 1)), double(expected(:, 2)), '-o'); hold on;
plot(double(actual(:, 1)), double(actual(:, 2)), '--x');
grid on; legend('expected', 'testbench'); title('MEL output');
subplot(3, 1, 3);
stem(double(expected(:, 1)), double(diff(:, 2)));
grid on; title('MEL error');
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);

exportgraphics(mel_figure, fullfile(mel_figure_dir, 'tb_mel_address_identity.png'), 'Resolution', 300);
savefig(mel_figure, fullfile(mel_figure_dir, 'tb_mel_address_identity.fig'));
