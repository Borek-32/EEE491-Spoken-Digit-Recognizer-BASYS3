function test_live_accuracy_logger_offline()
%TEST_LIVE_ACCURACY_LOGGER_OFFLINE Verify parser offsets and failure gates.

hashFixture = string(tempname) + ".bin";
hashCleanup = onCleanup(@() deleteIfPresent(hashFixture));
fid = fopen(hashFixture, "wb");
assert(fid >= 0, "Could not create SHA-256 test fixture.");
fwrite(fid, uint8('abc'), "uint8");
fclose(fid);
assert(sha256_file(hashFixture) == ...
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");

FRAME_COUNT = 63;
WORDS_PER_FRAME = 1362;
frames = zeros(WORDS_PER_FRAME, FRAME_COUNT, "uint32");

frames(1, :) = uint32(hex2dec("AABBCC00"));
frames(2, :) = uint32(0:256:15872);
frames(3, end) = uint32(hex2dec("00000042")); % valid compare result, digit 2
frames(4, :) = uint32(hex2dec("AABBCC01"));
frames(517, :) = uint32(hex2dec("AABBCC02"));
frames(1030, :) = uint32(hex2dec("AABBCC03"));
frames(1287, :) = uint32(hex2dec("AABBCC04"));
frames(1320, :) = uint32(hex2dec("AABBCC05"));
frames(1353, :) = uint32(hex2dec("AABBCC06"));
frames(1362, :) = uint32(hex2dec("AA5503CC"));

bytes = wordsToBigEndianBytes(frames(:));
trial = parse_mfcc_debug_bytes(bytes);
assert(trial.canonicalByteCount == 343224);
assert(trial.frameCount == 63);
assert(trial.finalResultValid);
assert(~trial.finalModeRecord);
assert(~trial.finalRecordCompleted);
assert(trial.finalPrediction == 2);
assert(trial.finalCompInfoHex == "00000042");

markerOffsets = [1 4 517 1030 1287 1320 1353 1362];
for markerOffset = markerOffsets
    badMarker = bytes;
    byteOffset = (markerOffset - 1) * 4 + 1;
    badMarker(byteOffset) = bitxor(badMarker(byteOffset), uint8(1));
    assertThrows(@() parse_mfcc_debug_bytes(badMarker), "MFCC:Marker");
end

assertThrows(@() parse_mfcc_debug_bytes(bytes(1:end - 1)), "MFCC:ByteCount");

badAddressFrames = frames;
badAddressFrames(2, 10) = uint32(1234);
assertThrows(@() parse_mfcc_debug_bytes(wordsToBigEndianBytes(badAddressFrames(:))), ...
    "MFCC:FrameAddress");

invalidFrames = frames;
invalidFrames(3, end) = uint32(2);
assertThrows(@() parse_mfcc_debug_bytes(wordsToBigEndianBytes(invalidFrames(:))), ...
    "MFCC:InvalidResult");

recordModeFrames = frames;
recordModeFrames(3, 5) = uint32(hex2dec("00000080"));
assertThrows(@() parse_mfcc_debug_bytes(wordsToBigEndianBytes(recordModeFrames(:))), ...
    "MFCC:RecordMode");

recordCompleteFrames = frames;
recordCompleteFrames(3, 5) = uint32(hex2dec("00000020"));
assertThrows(@() parse_mfcc_debug_bytes(wordsToBigEndianBytes(recordCompleteFrames(:))), ...
    "MFCC:UnexpectedRecord");

earlyValidFrames = frames;
earlyValidFrames(3, 10) = uint32(hex2dec("00000040"));
assertThrows(@() parse_mfcc_debug_bytes(wordsToBigEndianBytes(earlyValidFrames(:))), ...
    "MFCC:EarlyValid");

reservedFrames = frames;
reservedFrames(3, end) = uint32(hex2dec("00000142"));
assertThrows(@() parse_mfcc_debug_bytes(wordsToBigEndianBytes(reservedFrames(:))), ...
    "MFCC:ReservedStatus");

outOfRangeFrames = frames;
outOfRangeFrames(3, end) = uint32(hex2dec("0000004A"));
assertThrows(@() parse_mfcc_debug_bytes(wordsToBigEndianBytes(outOfRangeFrames(:))), ...
    "MFCC:DigitRange");

digitEightFrames = frames;
digitEightFrames(3, end) = uint32(hex2dec("00000058"));
digitEight = parse_mfcc_debug_bytes(wordsToBigEndianBytes(digitEightFrames(:)));
assert(digitEight.finalPrediction == 8 && digitEight.finalDigitIndexPatch);

digitNineFrames = frames;
digitNineFrames(3, end) = uint32(hex2dec("00000059"));
digitNine = parse_mfcc_debug_bytes(wordsToBigEndianBytes(digitNineFrames(:)));
assert(digitNine.finalPrediction == 9 && digitNine.finalDigitIndexPatch);

badPatchFrames = frames;
badPatchFrames(3, end) = uint32(hex2dec("00000048"));
assertThrows(@() parse_mfcc_debug_bytes(wordsToBigEndianBytes(badPatchFrames(:))), ...
    "MFCC:DigitPatch");

fprintf("test_live_accuracy_logger_offline PASS\n");
end

function bytes = wordsToBigEndianBytes(words)
words = uint32(words(:));
bytes = zeros(numel(words) * 4, 1, "uint8");
bytes(1:4:end) = uint8(bitshift(words, -24));
bytes(2:4:end) = uint8(bitand(bitshift(words, -16), uint32(255)));
bytes(3:4:end) = uint8(bitand(bitshift(words, -8), uint32(255)));
bytes(4:4:end) = uint8(bitand(words, uint32(255)));
end

function assertThrows(f, expectedId)
try
    f();
catch ME
    assert(string(ME.identifier) == string(expectedId), ...
        "Expected %s, received %s.", expectedId, ME.identifier);
    return;
end
error("Expected exception %s was not raised.", expectedId);
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end
