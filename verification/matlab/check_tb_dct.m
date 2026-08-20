close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_dct_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_dct_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_dct_output.txt');
cos_file = fullfile(script_dir, '..', 'mem_init_files', 'blk_mem_gen_dct_cos.mif');

logmel_data = int64(readmatrix(ref_file));

cos_lines = strip(readlines(cos_file));
cos_lines = cos_lines(strlength(cos_lines) > 0);
cos_data = int64(zeros(256, 1));
for i = 1:256
    v = int64(bin2dec(cos_lines(i)));
    if v >= 32768
        v = v - 65536;
    end
    cos_data(i) = v;
end

expected = int64(zeros(8, 2));

state = 0;
reset_value = 1;
start_value = 0;
dct_idx = int64(0);
mel_idx = int64(0);
cnt1 = int64(0);
accumulator = int64(0);
mel_addr = int64(0);
cos_addr = int64(0);
mult_a = int64(0);
mult_b = int64(0);
log_pipe = int64(0);
cos_pipe = int64(0);
mult_pipe = int64(zeros(4, 1));

for cycle = 0:10000
    if cycle == 5
        reset_value = 0;
    end
    if cycle == 6
        start_value = 1;
    end
    if cycle == 7
        start_value = 0;
    end

    logmel_data_in = log_pipe(end);
    cos_data_in = cos_pipe(end);
    product_value = mult_pipe(end);

    next_log_pipe = [logmel_data(double(mel_addr) + 1); log_pipe(1:end-1)];
    next_cos_pipe = [cos_data(double(cos_addr) + 1); cos_pipe(1:end-1)];
    next_mult_pipe = [mult_a * mult_b; mult_pipe(1:end-1)];

    if reset_value == 1
        state = 0;
        dct_idx = int64(0);
        mel_idx = int64(0);
        cnt1 = int64(0);
        accumulator = int64(0);
        mel_addr = int64(0);
        cos_addr = int64(0);
        mult_a = int64(0);
        mult_b = int64(0);
    else
        if state == 0
            if start_value == 1
                dct_idx = int64(0);
                mel_idx = int64(0);
                accumulator = int64(0);
                state = 1;
            else
                dct_idx = int64(0);
                mel_idx = int64(0);
                accumulator = int64(0);
            end
        elseif state == 1
            mel_addr = mod(mel_idx + 31, 32);
            cos_addr = dct_idx * 32 + mel_idx;
            state = 2;
        elseif state == 2
            if cnt1 == 4
                cnt1 = int64(0);
                state = 3;
            else
                mult_a = logmel_data_in;
                mult_b = cos_data_in;
                cnt1 = cnt1 + 1;
            end
        elseif state == 3
            accumulator = accumulator + product_value;
            if mel_idx == 31
                state = 4;
            else
                mel_idx = mel_idx + 1;
                state = 1;
            end
        elseif state == 4
            if accumulator < 0
                scaled_value = bitshift(accumulator - int64(536870912), -30);
            else
                scaled_value = bitshift(accumulator + int64(536870912), -30);
            end

            signed16_value = mod(scaled_value, int64(65536));
            if signed16_value >= 32768
                signed16_value = signed16_value - 65536;
            end

            expected(double(dct_idx) + 1, :) = [dct_idx signed16_value];
            state = 5;
        elseif state == 5
            state = 6;
        elseif state == 6
            if dct_idx == 7
                state = 7;
            else
                dct_idx = dct_idx + 1;
                mel_idx = int64(0);
                accumulator = int64(0);
                state = 1;
            end
        elseif state == 7
            break;
        end
    end

    log_pipe = next_log_pipe;
    cos_pipe = next_cos_pipe;
    mult_pipe = next_mult_pipe;
end

writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    error('Missing testbench output: %s', out_file);
end

actual = int64(readmatrix(out_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_dct output size mismatch');
end

diff = actual - expected;
if any(diff(:) ~= 0)
    disp([expected actual diff]);
    disp(['tb_dct max abs error = ' num2str(max(abs(diff(:))))]);
else
    disp('tb_dct PASS');
end

figure('Name', 'tb_dct', 'Position', [100 100 1600 900]);
set(gcf, 'Color', [0.12 0.12 0.12], 'InvertHardcopy', 'off');
subplot(3, 1, 1);
plot(double(0:(length(logmel_data) - 1)), double(logmel_data), '-o');
grid on; title('input LOGMEL waveform');
subplot(3, 1, 2);
plot(double(expected(:, 1)), double(expected(:, 2)), '-o'); hold on;
plot(double(actual(:, 1)), double(actual(:, 2)), '--x');
grid on; legend('expected', 'testbench'); title('DCT output');
subplot(3, 1, 3);
stem(double(expected(:, 1)), double(diff(:, 2)));
grid on; title('DCT error');
set(findall(gcf, 'Type', 'axes'), 'Color', [0.08 0.08 0.08], 'XColor', [0.85 0.85 0.85], 'YColor', [0.85 0.85 0.85], 'GridColor', [0.55 0.55 0.55]);
set(findall(gcf, 'Type', 'text'), 'Color', [0.85 0.85 0.85]);
set(findall(gcf, 'Type', 'legend'), 'TextColor', [0.85 0.85 0.85], 'Color', [0.08 0.08 0.08], 'EdgeColor', [0.85 0.85 0.85]);
