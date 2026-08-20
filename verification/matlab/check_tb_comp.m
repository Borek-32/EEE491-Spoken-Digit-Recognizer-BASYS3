close all; clc;

script_dir = fileparts(mfilename('fullpath'));
spec_file = fullfile(script_dir, '..', 'ref_data', 'tb_comp_ref.txt');
dct_file = fullfile(script_dir, '..', 'ref_data', 'tb_comp_dct_ref.txt');
mel_file = fullfile(script_dir, '..', 'ref_data', 'tb_comp_mel_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_comp_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_comp_output.txt');
ref_ram_file = fullfile(script_dir, '..', 'mem_init_files', 'blk_mem_gen_comp_ref_ram.mif');

spec = int64(readmatrix(spec_file));
selected_digit = spec(1, 1);
selected_trial = spec(1, 2);

dct_frames = int64(readmatrix(dct_file));
mel_frames = int64(readmatrix(mel_file));

ref_lines = strip(readlines(ref_ram_file));
ref_lines = ref_lines(strlength(ref_lines) > 0);
ref_depth = length(ref_lines);
ref_frames = int64(zeros(ref_depth, 8));

for line_idx = 1:ref_depth
    line_text = char(ref_lines(line_idx));
    for coeff_idx = 1:8
        first_bit = (coeff_idx - 1) * 16 + 1;
        last_bit = first_bit + 15;
        coeff_bits = line_text(first_bit:last_bit);
        coeff_value = int64(bin2dec(coeff_bits));
        if coeff_value >= 32768
            coeff_value = coeff_value - 65536;
        end
        ref_frames(line_idx, coeff_idx) = coeff_value;
    end
end

safe_digit = int64(zeros(48, 1));
safe_idx3 = int64(zeros(48, 1));
best_ref_by_window = int64(zeros(48, 1));

for window_start = 0:47
    best_dist = int64(9223372036854775807);
    best_ref = int64(0);
    for ref_idx = 0:29
        ref_dist = int64(0);
        for frame_idx = 0:15
            for coeff_idx = 1:8
                diff_value = dct_frames(window_start + frame_idx + 1, coeff_idx) - ref_frames(ref_idx * 16 + frame_idx + 1, coeff_idx);
                if diff_value < 0
                    diff_value = -diff_value;
                end
                ref_dist = ref_dist + diff_value;
            end
        end
        if ref_dist < best_dist
            best_dist = ref_dist;
            best_ref = int64(ref_idx);
        end
    end

    best_ref_by_window(window_start + 1) = best_ref;
    safe_digit(window_start + 1) = idivide(best_ref, int64(3), 'floor');
    if best_ref >= 24
        safe_idx3(window_start + 1) = 1;
    end
end

energy = int64(zeros(63, 1));
for frame_idx = 1:63
    total = int64(0);
    for mel_idx = 1:32
        total = total + mel_frames(frame_idx, mel_idx);
    end
    energy(frame_idx) = total;
end

max_energy = max(energy);
threshold = idivide(max_energy, int64(8), 'floor');
chosen_start = int64(0);
found_start = int64(0);

for frame_idx = 0:62
    if found_start == 0 && energy(frame_idx + 1) > threshold
        chosen_start = frame_idx;
        if chosen_start > 47
            chosen_start = 47;
        end
        found_start = 1;
    end
end

expected = int64([1 safe_digit(chosen_start + 1) safe_idx3(chosen_start + 1) 0]);
writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    error('Missing testbench output: %s', out_file);
end

actual = int64(readmatrix(out_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_comp output size mismatch');
end

diff = actual - expected;
if any(diff(:) ~= 0)
    disp([expected actual diff]);
    error('tb_comp mismatch');
end

figure('Name', 'tb_comp', 'Position', [100 100 1600 900]);
set(gcf, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
subplot(3, 1, 1);
plot(double(0:(size(dct_frames, 1) - 1)), double(dct_frames(:, 1)));
grid on; title('DCT input coefficient 0 waveform');
subplot(3, 1, 2);
plot(double(0:47), double(safe_digit), '-o'); hold on;
plot(double(0:47), double(best_ref_by_window), '--x');
grid on; legend('digit', 'best ref'); title('COMP integer SAD result by window');
subplot(3, 1, 3);
bar(double(0:62), double(energy)); hold on;
plot(double([0 62]), double([threshold threshold]), '--');
plot(double(chosen_start), double(energy(chosen_start + 1)), 'rx', 'MarkerSize', 10);
grid on; title(['MEL energy, selected digit ', num2str(selected_digit), ', trial ', num2str(selected_trial)]);
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);

disp('tb_comp PASS');
