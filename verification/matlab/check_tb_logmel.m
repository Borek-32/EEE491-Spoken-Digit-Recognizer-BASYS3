close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_logmel_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_logmel_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_logmel_output.txt');
rom_file = fullfile(script_dir, '..', 'mem_init_files', 'blk_mem_gen_log2_piecewise_rom.mif');

mel_data = uint64(readmatrix(ref_file));

rom_lines = strip(readlines(rom_file));
rom_lines = rom_lines(strlength(rom_lines) > 0);
rom = uint64(zeros(length(rom_lines), 1));
for i = 1:length(rom_lines)
    rom(i) = uint64(bin2dec(rom_lines(i)));
end

expected = int64(zeros(32, 2));
for bin_idx = 0:31
    x = mel_data(bin_idx + 1);
    if x == 0
        x = uint64(1);
    end

    exponent = int64(0);
    for b = 31:-1:0
        if bitand(x, bitshift(uint64(1), b)) ~= 0
            exponent = int64(b);
            break;
        end
    end

    norm_value = bitshift(x, 31 - exponent);
    rom_addr = bitand(bitshift(norm_value, -19), uint64(4095));
    residual = bitand(bitshift(norm_value, -11), uint64(255));
    rom_word = rom(double(rom_addr) + 1);
    base_value = bitshift(rom_word, -12);
    slope_value = bitand(rom_word, uint64(4095));
    product = slope_value * residual;
    interp = base_value + bitshift(product, -8);
    log_value = bitshift(uint64(exponent), 20) + interp;

    expected(bin_idx + 1, :) = [bin_idx int64(log_value)];
end

writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    error('Missing testbench output: %s', out_file);
end

actual = int64(readmatrix(out_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_logmel output size mismatch');
end

diff = actual - expected;
if any(diff(:) ~= 0)
    disp([expected actual diff]);
    disp(['tb_logmel max abs error = ' num2str(max(abs(diff(:))))]);
else
    disp('tb_logmel PASS');
end

figure('Name', 'tb_logmel', 'Position', [100 100 1600 900]);
set(gcf, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
subplot(3, 1, 1);
plot(double(0:(length(mel_data) - 1)), double(mel_data), '-o');
grid on; title('input MEL waveform');
subplot(3, 1, 2);
plot(double(expected(:, 1)), double(expected(:, 2)), '-o'); hold on;
plot(double(actual(:, 1)), double(actual(:, 2)), '--x');
grid on; legend('expected', 'testbench'); title('LOGMEL output');
subplot(3, 1, 3);
stem(double(expected(:, 1)), double(diff(:, 2)));
grid on; title('LOGMEL error');
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);
