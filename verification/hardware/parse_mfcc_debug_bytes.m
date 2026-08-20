function trial = parse_mfcc_debug_bytes(canonicalBytes)
%PARSE_MFCC_DEBUG_BYTES Validate one canonical 63-frame MFCC debug stream.

FRAME_COUNT = 63;
WORDS_PER_FRAME = 1362;
EXPECTED_BYTES = FRAME_COUNT * WORDS_PER_FRAME * 4;

if ~isa(canonicalBytes, "uint8")
    canonicalBytes = uint8(canonicalBytes);
end
canonicalBytes = canonicalBytes(:);
if numel(canonicalBytes) ~= EXPECTED_BYTES
    error("MFCC:ByteCount", ...
        "Canonical stream has %d bytes; expected exactly %d.", ...
        numel(canonicalBytes), EXPECTED_BYTES);
end

b = uint32(canonicalBytes);
b = reshape(b, 4, []).';
words = bitor(bitor(bitshift(b(:, 1), 24), bitshift(b(:, 2), 16)), ...
    bitor(bitshift(b(:, 3), 8), b(:, 4)));
words = reshape(uint32(words), WORDS_PER_FRAME, FRAME_COUNT);

FRAME_MARK = uint32(hex2dec("AABBCC00"));
ADC_MARK = uint32(hex2dec("AABBCC01"));
WINDOW_MARK = uint32(hex2dec("AABBCC02"));
FFT_MARK = uint32(hex2dec("AABBCC03"));
MEL_MARK = uint32(hex2dec("AABBCC04"));
LOGMEL_MARK = uint32(hex2dec("AABBCC05"));
DCT_MARK = uint32(hex2dec("AABBCC06"));
END_MARK = uint32(hex2dec("AA5503CC"));

% Fixed word offsets inside one 1,362-word frame.
IDX_FRAME_MARK = 1;
IDX_FRAME_ADDR = 2;
IDX_COMP_INFO = 3;
IDX_ADC_MARK = 4;
IDX_WINDOW_MARK = 517;
IDX_FFT_MARK = 1030;
IDX_MEL_MARK = 1287;
IDX_LOGMEL_MARK = 1320;
IDX_DCT_MARK = 1353;
IDX_END_MARK = 1362;

requireAll(words(IDX_FRAME_MARK, :) == FRAME_MARK, "FRAME marker");
requireAll(words(IDX_ADC_MARK, :) == ADC_MARK, "ADC marker");
requireAll(words(IDX_WINDOW_MARK, :) == WINDOW_MARK, "WINDOW marker");
requireAll(words(IDX_FFT_MARK, :) == FFT_MARK, "FFT marker");
requireAll(words(IDX_MEL_MARK, :) == MEL_MARK, "MEL marker");
requireAll(words(IDX_LOGMEL_MARK, :) == LOGMEL_MARK, "LOGMEL marker");
requireAll(words(IDX_DCT_MARK, :) == DCT_MARK, "DCT marker");
requireAll(words(IDX_END_MARK, :) == END_MARK, "END marker");

frameAddress = double(words(IDX_FRAME_ADDR, :));
expectedAddress = 0:256:15872;
if ~isequal(frameAddress, expectedAddress)
    error("MFCC:FrameAddress", ...
        "Frame addresses are not the required 0:256:15872 sequence.");
end

compInfo = words(IDX_COMP_INFO, :);
modeRecord = logical(bitget(compInfo, 8));
resultValid = logical(bitget(compInfo, 7));
recordCompleted = logical(bitget(compInfo, 6));
digitIndexPatch = logical(bitget(compInfo, 5));
prediction = double(bitand(compInfo, uint32(15)));

finalInfo = compInfo(end);
trial = struct();
trial.protocolVersion = "mfcc-debug-63x1362-v1";
trial.canonicalByteCount = numel(canonicalBytes);
trial.frameCount = FRAME_COUNT;
trial.wordsPerFrame = WORDS_PER_FRAME;
trial.frameAddress = frameAddress;
trial.compInfo = compInfo;
trial.modeRecordByFrame = modeRecord;
trial.resultValidByFrame = resultValid;
trial.recordCompletedByFrame = recordCompleted;
trial.digitIndexPatchByFrame = digitIndexPatch;
trial.predictionByFrame = prediction;
trial.finalCompInfoHex = upper(string(dec2hex(finalInfo, 8)));
trial.finalModeRecord = modeRecord(end);
trial.finalResultValid = resultValid(end);
trial.finalRecordCompleted = recordCompleted(end);
trial.finalDigitIndexPatch = digitIndexPatch(end);
trial.finalPrediction = prediction(end);

if any(modeRecord)
    error("MFCC:RecordMode", ...
        "A status word reports record mode. SW0 must be 0 for an accuracy trial.");
end
if any(recordCompleted)
    error("MFCC:UnexpectedRecord", ...
        "A status word reports a reference write during a compare trial.");
end
if any(resultValid(1:end - 1))
    error("MFCC:EarlyValid", ...
        "COMP result-valid asserted before the final frame address 15872.");
end
if ~trial.finalResultValid
    error("MFCC:InvalidResult", ...
        "Final frame address 15872 does not contain a valid COMP result.");
end
if trial.finalPrediction < 0 || trial.finalPrediction > 9
    error("MFCC:DigitRange", ...
        "Final COMP digit %d is outside 0 through 9.", trial.finalPrediction);
end
if any(bitand(compInfo, uint32(hex2dec("FFFFFF00"))) ~= 0)
    error("MFCC:ReservedStatus", ...
        "A COMP status word has nonzero reserved bits 31 through 8.");
end
expectedPatch = logical(bitget(uint32(trial.finalPrediction), 4));
if trial.finalDigitIndexPatch ~= expectedPatch
    error("MFCC:DigitPatch", ...
        "Final digit-index patch bit is inconsistent with prediction %d.", ...
        trial.finalPrediction);
end

end

function requireAll(condition, label)
if ~all(condition)
    bad = find(~condition, 1, "first");
    error("MFCC:Marker", "%s mismatch in frame %d.", label, bad);
end
end
