close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_debug_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_debug_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_debug_output.txt');

ref = int64(readmatrix(ref_file));
frame_addr = ref(1, 1);
mode_record = ref(1, 2);
comp_digit = ref(1, 3);
comp_valid = ref(1, 4);
comp_record = ref(1, 5);
comp_idx3 = ref(1, 6);

expected = int64(zeros(1362, 1));
row = 1;

expected(row) = int64(hex2dec('AABBCC00')); row = row + 1;
expected(row) = frame_addr; row = row + 1;
expected(row) = mode_record * 128 + comp_valid * 64 + comp_record * 32 + comp_idx3 * 16 + comp_digit; row = row + 1;

expected(row) = int64(hex2dec('AABBCC01')); row = row + 1;
for i = 0:511
    expected(row) = mod(frame_addr + int64(i), int64(512));
    row = row + 1;
end

expected(row) = int64(hex2dec('AABBCC02')); row = row + 1;
for i = 0:511
    expected(row) = int64(hex2dec('00020000')) + int64(i);
    row = row + 1;
end

expected(row) = int64(hex2dec('AABBCC03')); row = row + 1;
for i = 0:255
    expected(row) = int64(hex2dec('30000000')) + int64(i);
    row = row + 1;
end

expected(row) = int64(hex2dec('AABBCC04')); row = row + 1;
for i = 0:31
    expected(row) = int64(hex2dec('40000000')) + int64(i);
    row = row + 1;
end

expected(row) = int64(hex2dec('AABBCC05')); row = row + 1;
for i = 0:31
    expected(row) = int64(hex2dec('50000000')) + int64(i);
    row = row + 1;
end

expected(row) = int64(hex2dec('AABBCC06')); row = row + 1;
for i = 0:7
    expected(row) = int64(hex2dec('00006000')) + int64(i);
    row = row + 1;
end

expected(row) = int64(hex2dec('AA5503CC'));
writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    error('Missing testbench output: %s', out_file);
end

lines = strip(readlines(out_file));
lines = lines(strlength(lines) > 0);
actual = int64(zeros(length(lines), 1));
for i = 1:length(lines)
    actual(i) = int64(hex2dec(char(lines(i))));
end

if length(actual) ~= length(expected)
    error('tb_debug output size mismatch');
end

diff = actual - expected;
if any(diff ~= 0)
    bad = find(diff ~= 0, 10);
    disp([bad expected(bad) actual(bad) diff(bad)]);
    error('tb_debug mismatch');
end

figure('Name', 'tb_debug', 'Position', [100 100 1600 900]);
set(gcf, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
subplot(3, 1, 1);
bar(double([frame_addr mode_record comp_digit comp_valid comp_record comp_idx3]));
set(gca, 'XTick', 1:6, 'XTickLabel', {'frame', 'mode', 'digit', 'valid', 'record', 'idx3'});
grid on; title('debug input stimulus');
subplot(3, 1, 2);
plot(double(expected(1:80)), '-o'); hold on;
plot(double(actual(1:80)), '--x');
grid on; legend('expected', 'testbench'); title('first 80 UART words');
subplot(3, 1, 3);
stem(double(diff));
grid on; title('UART word error');
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);

disp('tb_debug PASS');
