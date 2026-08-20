close all; clc;

script_dir = fileparts(mfilename('fullpath'));
ref_file = fullfile(script_dir, '..', 'ref_data', 'tb_adc_spi_vad_ref.txt');
out_file = fullfile(script_dir, '..', 'tb_output', 'tb_adc_spi_vad_output.txt');
expected_file = fullfile(script_dir, '..', 'tb_output', 'expected_tb_adc_spi_vad_output.txt');

ref = int64(readmatrix(ref_file));
samples = int64([]);
explicit_expected = size(ref, 2) >= 3;

for i = 1:size(ref, 1)
    raw_sample = ref(i, 1);
    repeat_count = ref(i, 2);
    for j = 1:repeat_count
        samples = [samples; raw_sample];
    end
end

group_count = idivide(int64(length(samples)), int64(32), 'floor');
expected = int64(zeros(group_count, 2));

if explicit_expected && size(ref, 1) == group_count
    for g = 1:group_count
        expected(g, :) = [g - 1 ref(g, 3)];
    end
else
    for g = 1:group_count
        first_idx = (g - 1) * 32 + 1;
        last_idx = first_idx + 31;
        sample_sum = int64(0);
        for sample_idx = first_idx:last_idx
            sample_sum = sample_sum + samples(sample_idx);
        end
        avg_sample = idivide(sample_sum, int64(32), 'floor');
        signed_sample = avg_sample - 2048;
        stored_word = signed_sample;
        while stored_word < 0
            stored_word = stored_word + 4096;
        end
        while stored_word > 4095
            stored_word = stored_word - 4096;
        end
        expected(g, :) = [g - 1 stored_word];
    end
end

writematrix(expected, expected_file, 'Delimiter', ' ');

if ~isfile(out_file)
    disp(['Missing testbench output: ' out_file]);
    disp(['Expected table written to: ' expected_file]);
    return;
end

actual = int64(readmatrix(out_file));

if size(actual, 1) ~= size(expected, 1) || size(actual, 2) ~= size(expected, 2)
    error('tb_adc_spi_vad output size mismatch');
end

diff = actual - expected;
if any(diff(:) ~= 0)
    disp([expected actual diff]);
    error('tb_adc_spi_vad mismatch');
end

figure('Name', 'tb_adc_spi_vad');
subplot(2, 1, 1);
plot(double(expected(:, 1)), double(expected(:, 2)), '-o'); hold on;
plot(double(actual(:, 1)), double(actual(:, 2)), '--x');
grid on; legend('expected', 'testbench'); title('stored ADC words');
subplot(2, 1, 2);
stem(double(expected(:, 1)), double(diff(:, 2)));
grid on; title('stored word error');

disp('tb_adc_spi_vad PASS');
