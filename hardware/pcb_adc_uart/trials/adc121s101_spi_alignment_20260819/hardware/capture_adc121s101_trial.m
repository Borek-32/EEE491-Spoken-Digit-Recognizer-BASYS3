function result = capture_adc121s101_trial(label, vin_v, va_v, port, ...
    output_directory, word_count)
%CAPTURE_ADC121S101_TRIAL Retain and decode one PCB ADC/UART trial capture.
%
% Example, after measuring the rails with a DMM:
%   capture_adc121s101_trial("midscale", 1.650, 3.300, uartPort, outputDir)
%
% Keep BTNU released until this function flushes the UART and prompts for
% capture. The FPGA sends each signed 16-bit word low byte first.

    arguments
        label (1,1) string
        vin_v (1,1) double {mustBeNonnegative}
        va_v (1,1) double {mustBePositive}
        port (1,1) string
        output_directory (1,1) string
        word_count (1,1) double {mustBeInteger,mustBePositive} = 4096
    end

    port = strtrim(port);
    output_directory = strtrim(output_directory);
    if port == "" || output_directory == ""
        error("UART port and external output directory must be provided explicitly.");
    end
    if vin_v > va_v
        error("Vin %.6f V exceeds measured VA %.6f V.", vin_v, va_v);
    end

    fprintf("ADC121S101 alignment trial: %s\n", label);
    fprintf("Measured Vin = %.6f V, measured VA = %.6f V\n", vin_v, va_v);
    fprintf("Keep BTNU RELEASED. Confirm the candidate bitstream is loaded,\n");
    fprintf("BTNC has been pressed/released, and LD0 is high.\n");
    input("Press Enter to open and flush the UART: ", "s");

    s = serialport(port, 921600, "Timeout", 15);
    flush(s);

    fprintf("UART flushed with BTNU released. Press and HOLD BTNU now.\n");
    input("While holding BTNU, press Enter to capture: ", "s");

    byte_count = 2 * word_count;
    raw_bytes = read(s, byte_count, "uint8");
    fprintf("Capture complete. RELEASE BTNU now.\n");
    clear s;

    raw_bytes = reshape(uint8(raw_bytes), [], 1);
    if mod(numel(raw_bytes), 2) ~= 0
        error("Odd UART byte count; the capture cannot be word-aligned.");
    end

    low_bytes = uint16(raw_bytes(1:2:end));
    high_bytes = uint16(raw_bytes(2:2:end));
    unsigned_words = low_bytes + bitshift(high_bytes, 8);
    signed_values = int32(unsigned_words);
    signed_values(signed_values >= 32768) = ...
        signed_values(signed_values >= 32768) - 65536;

    capture_dir = output_directory;
    if ~isfolder(capture_dir)
        mkdir(capture_dir);
    end

    safe_label = regexprep(char(label), "[^A-Za-z0-9_-]", "_");
    stamp = char(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    stem = string(fullfile(capture_dir, ...
        sprintf("%s_%s", safe_label, stamp)));

    raw_path = stem + "_raw.bin";
    raw_file = fopen(raw_path, "wb");
    if raw_file < 0
        error("Could not create raw UART evidence file.");
    end
    bytes_written = fwrite(raw_file, raw_bytes, "uint8");
    close_status = fclose(raw_file);
    if bytes_written ~= numel(raw_bytes) || close_status ~= 0
        error("Raw UART evidence file was not written completely.");
    end

    if any(signed_values < -2048 | signed_values > 2047)
        error(["Decoded value outside -2048..+2047. Treat the run as " ...
               "byte-misaligned or corrupt; retain the raw bytes but do not " ...
               "claim an ADC result. Raw evidence was retained at " + raw_path]);
    end

    ideal_code = min(4095, floor(4096 * vin_v / va_v));
    ideal_centered = ideal_code - 2048;
    settle_words = min(128, floor(word_count / 4));
    stable_values = signed_values(settle_words + 1:end);

    first_count = min(16, numel(unsigned_words));
    first_hex = compose("%04X", unsigned_words(1:first_count));

    result = struct();
    result.label = label;
    result.capture_time = datetime("now", "TimeZone", "Europe/Istanbul");
    result.port = port;
    result.baud = 921600;
    result.vin_v = vin_v;
    result.va_v = va_v;
    result.ideal_code = ideal_code;
    result.ideal_centered = ideal_centered;
    result.word_count = word_count;
    result.settle_words_excluded_from_summary = settle_words;
    result.first_words_hex = first_hex;
    result.median = median(double(stable_values));
    result.minimum = min(stable_values);
    result.maximum = max(stable_values);
    result.mean = mean(double(stable_values));
    result.raw_bytes = raw_bytes;
    result.unsigned_words = unsigned_words;
    result.signed_values = signed_values;

    fprintf("First words: %s\n", strjoin(first_hex, " "));
    fprintf("Ideal centered value: %d\n", ideal_centered);
    fprintf("Stable median %.3f, mean %.3f, minimum %d, maximum %d\n", ...
        result.median, result.mean, result.minimum, result.maximum);

    save(stem + ".mat", "result");
    decoded = table((0:word_count-1)', double(unsigned_words), ...
        double(signed_values), "VariableNames", ...
        {"index", "uart_word_unsigned", "centered_signed"});
    writetable(decoded, stem + ".csv");

    fprintf("Evidence written under %s\n", capture_dir);
end
