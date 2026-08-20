close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_seven_segment_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_seven_segment_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_seven_segment_output.txt');

ref = int64(readmatrix(ref_file));
phase = ref(:, 1);
digit = ref(:, 2);

an = int64(zeros(size(digit)));
seg = int64(zeros(size(digit)));

for i = 1:length(digit)
    if phase(i) == 0
        an(i) = 14;
    elseif phase(i) == 1
        an(i) = 13;
    elseif phase(i) == 2
        an(i) = 11;
    else
        an(i) = 7;
    end

    if digit(i) == 0
        seg(i) = 64;
    elseif digit(i) == 1
        seg(i) = 121;
    elseif digit(i) == 2
        seg(i) = 36;
    elseif digit(i) == 3
        seg(i) = 48;
    elseif digit(i) == 4
        seg(i) = 25;
    elseif digit(i) == 5
        seg(i) = 18;
    elseif digit(i) == 6
        seg(i) = 2;
    elseif digit(i) == 7
        seg(i) = 120;
    elseif digit(i) == 8
        seg(i) = 0;
    elseif digit(i) == 9
        seg(i) = 16;
    elseif digit(i) == 10
        seg(i) = 47;
    elseif digit(i) == 11
        seg(i) = 3;
    elseif digit(i) == 12
        seg(i) = 70;
    elseif digit(i) == 13
        seg(i) = 33;
    elseif digit(i) == 14
        seg(i) = 6;
    else
        seg(i) = 14;
    end
end

expected = [phase digit an seg];
writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    error('Missing testbench output: %s', out_file);
end

actual = int64(readmatrix(out_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_seven_segment output size mismatch');
end

diff = actual - expected;
if any(diff(:) ~= 0)
    disp([expected actual diff]);
    error('tb_seven_segment mismatch');
end

figure('Name', 'tb_seven_segment', 'Position', [100 100 1600 900]);
set(gcf, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
subplot(3, 1, 1);
stairs(double(1:length(digit)), double(digit), '-o'); hold on;
stairs(double(1:length(phase)), double(phase), '--x');
grid on; legend('digit input', 'phase input'); title('seven-segment input stimulus');
subplot(3, 1, 2);
plot(double(expected(:, 2)), double(expected(:, 4)), '-o'); hold on;
plot(double(actual(:, 2)), double(actual(:, 4)), '--x');
grid on; legend('expected', 'testbench'); title('a_to_g');
subplot(3, 1, 3);
stem(double(expected(:, 2)), double(diff(:, 4)));
grid on; title('a_to_g error');
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);

disp('tb_seven_segment PASS');
