close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_ctrl_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_ctrl_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_ctrl_output.txt');

ref = int64(readmatrix(ref_file));
if size(ref, 2) == 1
    ref(:, 2) = 1;
end

total_rows = int64(0);
for scenario_idx = 1:size(ref, 1)
    frames_to_check = ref(scenario_idx, 1);
    debug_enable = ref(scenario_idx, 2);
    total_rows = total_rows + 1 + frames_to_check * (6 + debug_enable);
end

expected = int64(zeros(total_rows, 3));
row = 1;

for scenario_idx = 1:size(ref, 1)
    frames_to_check = ref(scenario_idx, 1);
    debug_enable = ref(scenario_idx, 2);

    expected(row, :) = [row - 1 0 0];
    row = row + 1;

    for frame_idx = 0:frames_to_check - 1
        frame_addr = frame_idx * 256;
        for stage_id = 1:6
            expected(row, :) = [row - 1 frame_addr stage_id];
            row = row + 1;
        end
        if debug_enable == 1
            stage_id = 7;
            expected(row, :) = [row - 1 frame_addr stage_id];
            row = row + 1;
        end
    end
end

writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    error('Missing testbench output: %s', out_file);
end

actual = int64(readmatrix(out_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_ctrl output size mismatch');
end

diff = actual - expected;
if any(diff(:) ~= 0)
    disp([expected actual diff]);
    error('tb_ctrl mismatch');
end

figure('Name', 'tb_ctrl', 'Position', [100 100 1600 900]);
set(gcf, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
subplot(3, 1, 1);
stairs(double(0:(size(ref, 1) - 1)), double(ref(:, 1)), '-o'); hold on;
stairs(double(0:(size(ref, 1) - 1)), double(ref(:, 2)), '--x');
grid on; legend('frames to check', 'debug enable'); title('CTRL input scenarios');
subplot(3, 1, 2);
stairs(double(expected(:, 1)), double(expected(:, 3)), '-o'); hold on;
stairs(double(actual(:, 1)), double(actual(:, 3)), '--x');
grid on; legend('expected', 'testbench'); title('stage event sequence');
subplot(3, 1, 3);
stem(double(expected(:, 1)), double(diff(:, 2)));
grid on; title('frame address error');
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);

disp('tb_ctrl PASS');
