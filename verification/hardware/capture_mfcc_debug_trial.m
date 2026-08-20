function trial = capture_mfcc_debug_trial(s, rawPath, deadlineSeconds)
%CAPTURE_MFCC_DEBUG_TRIAL Capture and validate one complete MFCC debug run.
%
% The current FPGA protocol emits 63 frames.  Each frame contains 1,362
% big-endian 32-bit words.  This function writes every transport byte to
% rawPath as it arrives, synchronizes to the first FRAME marker, validates
% the complete packet structure and address sequence, and returns the final
% COMP decision.  A partial raw file remains on disk if capture fails.

if nargin < 3 || isempty(deadlineSeconds)
    deadlineSeconds = 240;
end

FRAME_COUNT = 63;
WORDS_PER_FRAME = 1362;
BYTES_PER_WORD = 4;
TOTAL_CANONICAL_BYTES = FRAME_COUNT * WORDS_PER_FRAME * BYTES_PER_WORD;
MAX_PREFIX_BYTES = 4096;

FRAME_MARK_BYTES = uint8([hex2dec("AA"); hex2dec("BB"); hex2dec("CC"); 0]);

[rawFid, message] = fopen(rawPath, "wb");
if rawFid < 0
    error("MFCC:RawFile", "Cannot open raw evidence file %s: %s", rawPath, message);
end
rawCleanup = onCleanup(@() fclose(rawFid));

captureTimer = tic;
prefix = zeros(0, 1, "uint8");
window = zeros(0, 1, "uint8");

while true
    b = readExactAndRetain(1);
    prefix(end + 1, 1) = b; %#ok<AGROW>
    window(end + 1, 1) = b; %#ok<AGROW>
    if numel(window) > 4
        window = window(end - 3:end);
    end
    if numel(window) == 4 && isequal(window, FRAME_MARK_BYTES)
        break;
    end
    if numel(prefix) >= MAX_PREFIX_BYTES
        error("MFCC:NoFrameSync", ...
            "FRAME marker was not found within %d received bytes.", MAX_PREFIX_BYTES);
    end
end

discardedPrefixBytes = numel(prefix) - 4;
remaining = readExactAndRetain(TOTAL_CANONICAL_BYTES - 4);
canonicalBytes = [FRAME_MARK_BYTES; remaining];

trial = parse_mfcc_debug_bytes(canonicalBytes);
trial.capturedAt = string(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss.SSS Z"));
trial.captureSeconds = toc(captureTimer);
trial.transportByteCount = numel(prefix) + numel(remaining);
trial.discardedPrefixBytes = discardedPrefixBytes;
trial.rawPath = string(rawPath);

clear rawCleanup;
trial.rawSha256 = sha256_file(rawPath);

    function out = readExactAndRetain(count)
        out = zeros(count, 1, "uint8");
        received = 0;
        while received < count
            if toc(captureTimer) > deadlineSeconds
                error("MFCC:SerialDeadline", ...
                    "Trial deadline expired after receiving %d of %d requested bytes.", ...
                    received, count);
            end
            available = s.NumBytesAvailable;
            if available == 0
                pause(0.001);
                continue;
            end
            take = min(double(available), count - received);
            chunk = uint8(read(s, take, "uint8"));
            chunk = chunk(:);
            if isempty(chunk)
                pause(0.001);
                continue;
            end
            written = fwrite(rawFid, chunk, "uint8");
            if written ~= numel(chunk)
                error("MFCC:RawFileWrite", ...
                    "Raw evidence write stopped after %d of %d bytes.", ...
                    written, numel(chunk));
            end
            out(received + 1:received + numel(chunk)) = chunk;
            received = received + numel(chunk);
        end
    end

end
