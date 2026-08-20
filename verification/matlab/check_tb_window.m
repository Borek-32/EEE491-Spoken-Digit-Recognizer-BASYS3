close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_window_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_window_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_window_output.txt');
coeff_file = fullfile(script_dir, '..', 'mem_init_files', 'blk_mem_gen_0.mif');

ref = int64(readmatrix(ref_file));
start_sample = ref(1, 1);
sample_step = ref(1, 2);
sample_count = ref(1, 3);

adc_data = int64(zeros(sample_count, 1));
for i = 1:sample_count
    adc_data(i) = start_sample + (i - 1) * sample_step;
end

coeff_lines = strip(readlines(coeff_file));
coeff_lines = coeff_lines(strlength(coeff_lines) > 0);
coeff = int64(zeros(sample_count, 1));
for i = 1:sample_count
    coeff(i) = int64(bin2dec(coeff_lines(i)));
end

expected = int64(zeros(sample_count, 2));
for i = 1:sample_count
    product = adc_data(i) * coeff(i);
    stored_word = product;
    while stored_word < 0
        stored_word = stored_word + 1048576;
    end
    while stored_word > 1048575
        stored_word = stored_word - 1048576;
    end
    expected(i, :) = [i - 1 stored_word];
end

writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    error('Missing testbench output: %s', out_file);
end

actual = int64(readmatrix(out_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_window output size mismatch');
end

diff = actual - expected;
if any(diff(:) ~= 0)
    disp([expected actual diff]);
    error('tb_window mismatch');
end

figure('Name', 'tb_window', 'Position', [100 100 1600 900]);
set(gcf, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
subplot(3, 1, 1);
plot(double(0:(sample_count - 1)), double(adc_data));
grid on; title('input ADC waveform');
subplot(3, 1, 2);
plot(double(expected(:, 1)), double(expected(:, 2))); hold on;
plot(double(actual(:, 1)), double(actual(:, 2)), '--');
grid on; legend('expected', 'testbench'); title('window RAM output');
subplot(3, 1, 3);
plot(double(expected(:, 1)), double(diff(:, 2)));
grid on; title('window output error');
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);

disp('tb_window PASS');
