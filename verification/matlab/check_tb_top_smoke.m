close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_top_smoke_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_top_smoke_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_top_smoke_output.txt');

ref = int64(readmatrix(ref_file));
expected = int64(zeros(size(ref, 1), 5));

for i = 1:size(ref, 1)
    switch_mode = ref(i, 1);
    debug_enable = ref(i, 4);
    expected(i, :) = [i - 1 switch_mode switch_mode debug_enable debug_enable];
end

writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    disp(['Missing testbench output: ' out_file]);
    disp(['Expected table written to: ' expected_file]);
    return;
end

actual = int64(readmatrix(out_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_top_smoke output size mismatch');
end

diff = actual - expected;
if any(diff(:) ~= 0)
    disp([expected actual diff]);
    error('tb_top_smoke mismatch');
end

figure('Name', 'tb_top_smoke');
plot(double(expected(:, 1)), double(expected(:, 2)), '-o'); hold on;
plot(double(actual(:, 1)), double(actual(:, 3)), '--x');
plot(double(actual(:, 1)), double(actual(:, 5)), '--s');
grid on; legend('switch ref', 'pmod output', 'debug LED output'); title('top_module switch and debug LED smoke check');

disp('tb_top_smoke PASS');
