function session = run_live_accuracy_session(trialsPerDigit, port, ...
    targetSerial, bitPath, expectedBitSha256, programmingLogPath, evidenceRoot)
%RUN_LIVE_ACCURACY_SESSION Measure labeled FPGA recognition accuracy.
%
% Example (all machine/hardware values must be provided explicitly):
%   run_live_accuracy_session(10, uartPort, jtagTarget, bitPath, ...
%       bitSha256, programmingLogPath, evidenceOutputDirectory)
%
% Ten randomized balanced cycles produce 100 predeclared trials.
% Every declared trial counts in the primary correct/planned result. There is
% intentionally no option to retry or discard a trial after it is captured.

if nargin == 1 && (ischar(trialsPerDigit) || isstring(trialsPerDigit))
    if strcmpi(strtrim(string(trialsPerDigit)), "selftest")
        session = runEvidenceSelfTest();
        return;
    end
    error("String input must be 'selftest'.");
end

if nargin ~= 7
    error(["Normal capture requires seven explicit inputs: trialsPerDigit, " ...
        "port, targetSerial, bitPath, expectedBitSha256, " ...
        "programmingLogPath, and evidenceRoot."]);
end
if ~isscalar(trialsPerDigit) || trialsPerDigit < 1 || ...
        fix(trialsPerDigit) ~= trialsPerDigit
    error("trialsPerDigit must be a positive integer.");
end

BAUD = 1000000;
PORT = strtrim(string(port));
TARGET_SERIAL = strtrim(string(targetSerial));
bitPath = strtrim(string(bitPath));
BIT_SHA256 = lower(strtrim(string(expectedBitSha256)));
programmingLogPath = strtrim(string(programmingLogPath));
evidenceRoot = strtrim(string(evidenceRoot));
TRIAL_DEADLINE_SECONDS = 240;
MAX_PROGRAM_AGE_MINUTES = 60;

if any(strlength([PORT, TARGET_SERIAL, bitPath, programmingLogPath, evidenceRoot]) == 0)
    error("Port, target, bitstream, programming-log and evidence paths must be nonempty.");
end
if isempty(regexp(BIT_SHA256, "^[0-9a-f]{64}$", "once"))
    error("expectedBitSha256 must be exactly 64 hexadecimal characters.");
end

hardwareDir = fileparts(mfilename("fullpath"));
sessionIndexPath = fullfile(evidenceRoot, "session_index.jsonl");

if ~isfile(PORT)
    error("Stable Digilent UART endpoint is missing: %s", PORT);
end
if ~isfile(bitPath)
    error("Required full-MFCC JC bitstream is missing: %s", bitPath);
end
actualBitSha = sha256_file(bitPath);
if actualBitSha ~= BIT_SHA256
    error("Bitstream SHA-256 mismatch. Expected %s, received %s.", ...
        BIT_SHA256, actualBitSha);
end

validationTime = datetime("now", "TimeZone", "Europe/Istanbul");
programRecord = validateProgrammingRecord(programmingLogPath, BIT_SHA256, ...
    TARGET_SERIAL, validationTime, MAX_PROGRAM_AGE_MINUTES);

% Validate all operator-entered conditions before declaring an evidence run.
speakerTag = strtrim(string(input("Speaker tag [author]: ", "s")));
if speakerTag == ""
    speakerTag = "author";
end
distanceText = strtrim(string(input( ...
    "Approximate mouth-to-microphone distance in cm [15]: ", "s")));
if distanceText == ""
    distanceCm = 15;
else
    distanceCm = str2double(distanceText);
    if ~isfinite(distanceCm) || distanceCm <= 0
        error("Microphone distance must be a positive number.");
    end
end
environmentNote = strtrim(string(input( ...
    "Environment note [quiet indoor desk]: ", "s")));
if environmentNote == ""
    environmentNote = "quiet indoor desk";
end

fprintf("\nLIVE MFCC ACCURACY SESSION\n");
fprintf("  Planned trials: %d (%d per digit)\n", trialsPerDigit * 10, trialsPerDigit);
fprintf("  UART: %s at %d baud\n", PORT, BAUD);
fprintf("  Bitstream SHA-256: %s\n", BIT_SHA256);
fprintf("  Programming log SHA-256: %s\n", programRecord.logSha256);
fprintf("  Programming time recorded in log: %s\n", programRecord.programTimeText);
fprintf("\nBefore declaring the session:\n");
fprintf("  1. Set SW0=0 (compare) and SW1=1 (debug enabled).\n");
fprintf("  2. Keep SW1 high for the complete session.\n");
fprintf("  3. Press and release BTNC once now.\n");
fprintf("  4. Do not repeat or discard a declared trial after seeing its result.\n");
confirmation = strtrim(string(input( ...
    "Type READY after those four conditions are satisfied: ", "s")));
if ~strcmpi(confirmation, "READY")
    error("Session was not declared because READY was not entered.");
end

% Revalidate after operator setup so an old or replaced log cannot slip in.
programRecord = validateProgrammingRecord(programmingLogPath, BIT_SHA256, ...
    TARGET_SERIAL, datetime("now", "TimeZone", "Europe/Istanbul"), ...
    MAX_PROGRAM_AGE_MINUTES);

if ~isfolder(evidenceRoot)
    [madeRoot, message] = mkdir(evidenceRoot);
    if ~madeRoot
        error("MFCC:EvidenceStorage", ...
            "Cannot create accuracy evidence root %s: %s", evidenceRoot, message);
    end
end

sessionTime = datetime("now", "TimeZone", "Europe/Istanbul");
sessionId = "live_accuracy_" + string(sessionTime, "yyyyMMdd_HHmmss_SSS");
sessionDir = fullfile(evidenceRoot, sessionId);
if isfolder(sessionDir) || isfile(sessionDir)
    error("MFCC:EvidenceStorage", "Session path already exists: %s", sessionDir);
end

rngSeed = mod(floor(posixtime(sessionTime) * 1000), 2^32 - 1);
rng(rngSeed, "twister");
schedule = zeros(trialsPerDigit * 10, 1);
scheduleCycle = zeros(size(schedule));
k = 0;
for cycle = 1:trialsPerDigit
    order = randperm(10) - 1;
    schedule(k + (1:10)) = order;
    scheduleCycle(k + (1:10)) = cycle;
    k = k + 10;
end
scheduleTable = table((1:numel(schedule)).', scheduleCycle, schedule, ...
    'VariableNames', ["trial_index", "cycle", "expected_digit"]);

createSessionDirectories(sessionDir);
sourceSnapshotDir = fullfile(sessionDir, "logger_source");
provenanceDir = fullfile(sessionDir, "provenance");

phasePath = fullfile(sessionDir, ".session_phase");
setSessionPhase(phasePath, "declaring");
declaredEvent = baseLifecycleEvent("declared", sessionId, height(scheduleTable));
declaredEvent.bitstream_sha256 = BIT_SHA256;
declaredEvent.programming_log_sha256 = programRecord.logSha256;
appendLifecycleEvent(sessionIndexPath, declaredEvent);
lifecycleCleanup = onCleanup(@() appendAbortedUnlessCompleted( ...
    sessionIndexPath, sessionId, height(scheduleTable), phasePath));

schedulePath = fullfile(sessionDir, "predeclared_schedule.csv");
writeTableAtomic(scheduleTable, schedulePath);
scheduleSha256 = sha256_file(schedulePath);

copyLoggerSnapshot(hardwareDir, sourceSnapshotDir);
programmingLogCopy = fullfile(provenanceDir, ...
    "program_full_mfcc_jc_20260819.log");
copyFileVerified(programmingLogPath, programmingLogCopy, programRecord.logSha256);
writeBitstreamIdentity(fullfile(provenanceDir, "bitstream_identity.txt"), ...
    bitPath, BIT_SHA256, TARGET_SERIAL);
writeSessionMetadata(fullfile(sessionDir, "session_metadata.txt"), ...
    sessionId, height(scheduleTable), trialsPerDigit, rngSeed, speakerTag, ...
    distanceCm, environmentNote, BIT_SHA256, TARGET_SERIAL, PORT, BAUD, ...
    programRecord, scheduleSha256);

runningEvent = baseLifecycleEvent("running", sessionId, height(scheduleTable));
runningEvent.schedule_sha256 = scheduleSha256;
runningEvent.programming_log_sha256 = programRecord.logSha256;
appendLifecycleEvent(sessionIndexPath, runningEvent);
setSessionPhase(phasePath, "opening_uart");

s = serialport(PORT, BAUD, "Timeout", 1);
serialCleanup = onCleanup(@() cleanupSerial(s));
flush(s);

results = emptyResultsTable();
resultsPath = fullfile(sessionDir, "accuracy_trials.csv");

for trialIndex = 1:numel(schedule)
    expected = schedule(trialIndex);
    cycle = scheduleCycle(trialIndex);
    setSessionPhase(phasePath, "awaiting_trial_" + string(trialIndex));
    fprintf("\nTrial %d/%d, cycle %d/%d: digit %d\n", ...
        trialIndex, numel(schedule), cycle, trialsPerDigit, expected);
    input("Prepare to say that digit, then press Enter to arm: ", "s");
    flush(s);
    pause(0.05);
    fprintf("ARMED: press and release BTNU, then say digit %d.\n", expected);

    stem = sprintf("trial_%03d_truth_%d", trialIndex, expected);
    rawRelative = fullfile("raw", stem + ".bin");
    decodedRelative = fullfile("decoded", stem + ".mat");
    rawPath = fullfile(sessionDir, rawRelative);
    decodedPath = fullfile(sessionDir, decodedRelative);
    startedAt = string(datetime("now", "Format", ...
        "yyyy-MM-dd HH:mm:ss.SSS Z", "TimeZone", "Europe/Istanbul"));

    protocolOk = false;
    prediction = -1;
    correct = false;
    finalStatusHex = "";
    byteCount = 0;
    rawSha = "";
    errorId = "";
    errorMessage = "";
    attemptTimer = tic;
    trial = struct();

    setSessionPhase(phasePath, "capturing_trial_" + string(trialIndex));
    try
        trial = capture_mfcc_debug_trial(s, rawPath, TRIAL_DEADLINE_SECONDS);
        protocolOk = true;
    catch ME
        if isEvidenceIntegrityFailure(ME)
            rethrow(ME);
        end
        errorId = string(ME.identifier);
        errorMessage = string(ME.message);
    end
    captureSeconds = toc(attemptTimer);

    setSessionPhase(phasePath, "persisting_trial_" + string(trialIndex));
    if protocolOk
        trial.expectedDigit = expected;
        trial.trialIndex = trialIndex;
        trial.cycle = cycle;
        trial.speakerTag = speakerTag;
        trial.distanceCm = distanceCm;
        trial.environmentNote = environmentNote;
        trial.bitstreamSha256 = BIT_SHA256;
        trial.jtagTargetSerial = TARGET_SERIAL;
        trial.programmingLogSha256 = programRecord.logSha256;
        trial.referenceState = programRecord.referenceStatement;
        trial.rawRelativePath = string(rawRelative);
        prediction = trial.finalPrediction;
        correct = prediction == expected;
        finalStatusHex = trial.finalCompInfoHex;
        byteCount = trial.transportByteCount;
        rawSha = trial.rawSha256;
        captureSeconds = trial.captureSeconds;
        saveStructAtomic(decodedPath, struct("trial", trial));
        fprintf("CAPTURED: trial %d retained. Result is hidden until session completion.\n", ...
            trialIndex);
    else
        if isfile(rawPath)
            info = dir(rawPath);
            byteCount = info.bytes;
            rawSha = sha256_file(rawPath);
        end
        failure = struct( ...
            "trialIndex", trialIndex, ...
            "cycle", cycle, ...
            "expectedDigit", expected, ...
            "startedAt", startedAt, ...
            "captureSeconds", captureSeconds, ...
            "errorId", errorId, ...
            "errorMessage", errorMessage, ...
            "rawRelativePath", string(rawRelative), ...
            "rawSha256", rawSha, ...
            "rawByteCount", byteCount);
        saveStructAtomic(decodedPath, struct("failure", failure));
        fprintf(2, "CAPTURE RETAINED: protocol failure recorded for trial %d.\n", ...
            trialIndex);
    end

    row = table(trialIndex, cycle, expected, prediction, protocolOk, correct, ...
        startedAt, captureSeconds, string(finalStatusHex), byteCount, string(rawSha), ...
        string(rawRelative), string(decodedRelative), string(errorId), ...
        string(errorMessage), 'VariableNames', results.Properties.VariableNames);
    results = [results; row]; %#ok<AGROW>
    writeTableAtomic(results, resultsPath);
end

setSessionPhase(phasePath, "finalizing");
session = finalizeSession(results, scheduleTable, sessionDir, trialsPerDigit, ...
    rngSeed, speakerTag, distanceCm, environmentNote, bitPath, BIT_SHA256, ...
    TARGET_SERIAL, PORT, BAUD, programRecord, scheduleSha256);
saveStructAtomic(fullfile(sessionDir, "session_summary.mat"), ...
    struct("session", session, "results", results, "scheduleTable", scheduleTable));

manifestSha256 = buildEvidenceManifest(sessionDir);
session.manifestSha256 = manifestSha256;

completedEvent = baseLifecycleEvent("completed", sessionId, height(scheduleTable));
completedEvent.protocol_complete_trials = session.protocolCompleteTrials;
completedEvent.correct_trials = session.correctTrials;
completedEvent.end_to_end_accuracy_percent = session.endToEndAccuracyPercent;
completedEvent.conditional_accuracy_percent = session.conditionalAccuracyPercent;
completedEvent.protocol_completion_percent = session.protocolCompletionPercent;
completedEvent.manifest_sha256 = manifestSha256;
setSessionPhase(phasePath, "completed");
appendLifecycleEvent(sessionIndexPath, completedEvent);
clear lifecycleCleanup;
deleteIfPresent(phasePath);

fprintf("\nSESSION COMPLETE\n");
fprintf("  Primary end-to-end result: %d/%d (%.2f%%)\n", ...
    session.correctTrials, session.plannedTrials, session.endToEndAccuracyPercent);
fprintf("  Conditional classification accuracy: %d/%d (%.2f%%)\n", ...
    session.correctTrials, session.protocolCompleteTrials, ...
    session.conditionalAccuracyPercent);
fprintf("  Protocol completion: %d/%d (%.2f%%)\n", ...
    session.protocolCompleteTrials, session.plannedTrials, ...
    session.protocolCompletionPercent);
fprintf("  Evidence directory: %s\n", sessionDir);

end

function result = runEvidenceSelfTest()
testRoot = string(tempname);
[ok, message] = mkdir(testRoot);
if ~ok
    error("MFCC:SelfTest", "Cannot create self-test directory: %s", message);
end
cleanup = onCleanup(@() rmdir(testRoot, "s"));
sessionDir = fullfile(testRoot, "session");
createSessionDirectories(sessionDir);

bitSha = "2f1a6697f5937033b59397478b328e61b7bad764fd204695cf9bb3adea60b3ac";
targetSerial = "SELFTEST_TARGET";
programTime = datetime("now", "TimeZone", "Europe/Istanbul");
programTimePlain = string(programTime, "yyyy-MM-dd HH:mm:ss");
syntheticLog = join([ ...
    "PROGRAM_TIME=" + programTimePlain + " +03"; ...
    "BIT_SHA256=" + bitSha; ...
    "OPENED_TARGET=127.0.0.1:3121/xilinx_tcf/Digilent/" + targetSerial; ...
    "REGISTER.IR.BIT5_DONE=1"; ...
    "REFERENCE_STATE=configuration-time COE baseline restored by this programming operation"; ...
    "PROGRAM_RESULT=PASS"], newline) + newline;
syntheticLogPath = fullfile(sessionDir, "synthetic_programming.log");
writeTextAtomic(syntheticLogPath, syntheticLog);
programRecord = validateProgrammingRecord(syntheticLogPath, bitSha, ...
    targetSerial, programTime, 1);

schedule = (0:9).';
scheduleTable = table((1:10).', ones(10,1), schedule, ...
    'VariableNames', ["trial_index", "cycle", "expected_digit"]);
schedulePath = fullfile(sessionDir, "predeclared_schedule.csv");
writeTableAtomic(scheduleTable, schedulePath);
scheduleSha = sha256_file(schedulePath);

results = emptyResultsTable();
for i = 1:10
    protocolOk = i < 10;
    prediction = schedule(i);
    if ~protocolOk
        prediction = -1;
    end
    correct = protocolOk;
    row = table(i, 1, schedule(i), prediction, protocolOk, correct, ...
        "2026-08-19 00:00:00.000 +03", 1, "00000040", 343224, ...
        "rawsha", "raw/trial.bin", "decoded/trial.mat", "", "", ...
        'VariableNames', results.Properties.VariableNames);
    results = [results; row]; %#ok<AGROW>
end

writeSessionMetadata(fullfile(sessionDir, "session_metadata.txt"), ...
    "selftest", 10, 1, 1, "test", 15, "quiet", bitSha, ...
    targetSerial, "SELFTEST_UART", 1000000, programRecord, scheduleSha);
writeBitstreamIdentity(fullfile(sessionDir, "bitstream_identity.txt"), ...
    "selftest.bit", bitSha, targetSerial);
copyLoggerSnapshot(fileparts(mfilename("fullpath")), ...
    fullfile(sessionDir, "logger_source"));

session = finalizeSession(results, scheduleTable, sessionDir, 1, 1, ...
    "test", 15, "quiet", "selftest.bit", bitSha, targetSerial, ...
    "SELFTEST_UART", 1000000, programRecord, scheduleSha);
assert(session.plannedTrials == 10);
assert(session.correctTrials == 9);
assert(session.protocolCompleteTrials == 9);
assert(abs(session.endToEndAccuracyPercent - 90) < 1e-9);
assert(abs(session.conditionalAccuracyPercent - 100) < 1e-9);
assert(abs(session.protocolCompletionPercent - 90) < 1e-9);
saveStructAtomic(fullfile(sessionDir, "session_summary.mat"), ...
    struct("session", session, "results", results, "scheduleTable", scheduleTable));

indexPath = fullfile(testRoot, "session_index.jsonl");
phasePath = fullfile(sessionDir, ".session_phase");
setSessionPhase(phasePath, "dry_run");
appendLifecycleEvent(indexPath, baseLifecycleEvent("declared", "dry_run", 10));
appendAbortedUnlessCompleted(indexPath, "dry_run", 10, phasePath);
assert(contains(string(fileread(indexPath)), '"event":"aborted"'));
appendLifecycleEvent(indexPath, baseLifecycleEvent("completed", "done_run", 10));
before = string(fileread(indexPath));
appendAbortedUnlessCompleted(indexPath, "done_run", 10, phasePath);
after = string(fileread(indexPath));
assert(before == after);

manifestSha = buildEvidenceManifest(sessionDir);
assert(strlength(manifestSha) == 64);
assert(isfile(fullfile(sessionDir, "MANIFEST.csv")));
assert(isfile(fullfile(sessionDir, "MANIFEST.sha256")));

result = struct("pass", true, "endToEndAccuracyPercent", ...
    session.endToEndAccuracyPercent, "manifestSha256", manifestSha);
fprintf("run_live_accuracy_session selftest PASS\n");
end

function results = emptyResultsTable()
results = table('Size', [0 15], ...
    'VariableTypes', ["double", "double", "double", "double", "logical", ...
    "logical", "string", "double", "string", "double", "string", ...
    "string", "string", "string", "string"], ...
    'VariableNames', ["trial_index", "cycle", "expected_digit", ...
    "predicted_digit", "protocol_ok", "correct", "started_at", ...
    "capture_seconds", "final_status_hex", "transport_byte_count", ...
    "raw_sha256", "raw_file", "decoded_file", "error_id", "error_message"]);
end

function session = finalizeSession(results, scheduleTable, sessionDir, trialsPerDigit, ...
        rngSeed, speakerTag, distanceCm, environmentNote, bitPath, bitSha, ...
        targetSerial, port, baud, programRecord, scheduleSha256)
plannedTrials = height(scheduleTable);
complete = results.protocol_ok;

% Columns 1:10 are predictions 0:9; column 11 is a protocol failure.
confusion = zeros(10, 11);
for i = 1:height(results)
    truth = results.expected_digit(i);
    if results.protocol_ok(i)
        prediction = results.predicted_digit(i);
        confusion(truth + 1, prediction + 1) = ...
            confusion(truth + 1, prediction + 1) + 1;
    else
        confusion(truth + 1, 11) = confusion(truth + 1, 11) + 1;
    end
end

confusionNames = [compose("pred_%d", 0:9), "protocol_failure"];
confusionTable = array2table(confusion, ...
    'VariableNames', confusionNames, 'RowNames', compose("true_%d", 0:9));
writeTableAtomic(confusionTable, fullfile(sessionDir, "confusion_matrix.csv"), ...
    "WriteRowNames", true);

perDigit = table((0:9).', zeros(10,1), zeros(10,1), zeros(10,1), ...
    zeros(10,1), zeros(10,1), zeros(10,1), ...
    'VariableNames', ["digit", "planned", "protocol_complete", ...
    "protocol_failures", "correct", "end_to_end_success_percent", ...
    "conditional_classification_accuracy_percent"]);
for d = 0:9
    plannedMask = results.expected_digit == d;
    completeMask = complete & plannedMask;
    perDigit.planned(d + 1) = sum(plannedMask);
    perDigit.protocol_complete(d + 1) = sum(completeMask);
    perDigit.protocol_failures(d + 1) = ...
        perDigit.planned(d + 1) - perDigit.protocol_complete(d + 1);
    perDigit.correct(d + 1) = sum(results.correct(plannedMask));
    perDigit.end_to_end_success_percent(d + 1) = ...
        100 * perDigit.correct(d + 1) / perDigit.planned(d + 1);
    if perDigit.protocol_complete(d + 1) > 0
        perDigit.conditional_classification_accuracy_percent(d + 1) = ...
            100 * perDigit.correct(d + 1) / perDigit.protocol_complete(d + 1);
    else
        perDigit.conditional_classification_accuracy_percent(d + 1) = NaN;
    end
end
writeTableAtomic(perDigit, fullfile(sessionDir, "per_digit_accuracy.csv"));

correctTrials = sum(results.correct);
completeTrials = sum(complete);
endToEndAccuracyPercent = 100 * correctTrials / plannedTrials;
protocolCompletionPercent = 100 * completeTrials / plannedTrials;
if completeTrials > 0
    conditionalAccuracyPercent = 100 * correctTrials / completeTrials;
else
    conditionalAccuracyPercent = NaN;
end

fig = figure("Name", "Live FPGA recognition confusion matrix", ...
    "Color", "w", "Visible", "off");
imagesc(confusion);
axis image;
colormap(parula);
colorbar;
xticks(1:11); xticklabels([string(0:9), "protocol fail"]);
yticks(1:10); yticklabels(string(0:9));
xlabel("FPGA predicted digit / transport outcome");
ylabel("Spoken ground-truth digit");
title(sprintf("Live FPGA session: %d/%d end-to-end successes (%.2f%%)", ...
    correctTrials, plannedTrials, endToEndAccuracyPercent));
maximumCount = max(confusion, [], "all");
for row = 1:10
    for col = 1:11
        if maximumCount > 0 && confusion(row, col) > maximumCount / 2
            textColor = "black";
        else
            textColor = "white";
        end
        text(col, row, string(confusion(row, col)), ...
            "HorizontalAlignment", "center", "Color", textColor, ...
            "FontWeight", "bold");
    end
end
exportgraphics(fig, fullfile(sessionDir, "confusion_matrix.png"), ...
    "Resolution", 220);
close(fig);

session = struct();
session.sessionId = string(getLastPathPart(sessionDir));
session.createdAt = string(datetime("now", "Format", ...
    "yyyy-MM-dd HH:mm:ss Z", "TimeZone", "Europe/Istanbul"));
session.plannedTrials = plannedTrials;
session.trialsPerDigit = trialsPerDigit;
session.rngSeed = rngSeed;
session.protocolCompleteTrials = completeTrials;
session.protocolFailureTrials = plannedTrials - completeTrials;
session.correctTrials = correctTrials;
session.endToEndAccuracyPercent = endToEndAccuracyPercent;
session.conditionalAccuracyPercent = conditionalAccuracyPercent;
session.protocolCompletionPercent = protocolCompletionPercent;
session.confusionMatrixWithProtocolFailure = confusion;
session.perDigit = perDigit;
session.speakerTag = speakerTag;
session.distanceCm = distanceCm;
session.environmentNote = environmentNote;
session.bitstreamPath = string(bitPath);
session.bitstreamSha256 = bitSha;
session.jtagTargetSerial = targetSerial;
session.programmingLogSha256 = programRecord.logSha256;
session.programmingTime = programRecord.programTimeText;
session.referenceState = programRecord.referenceStatement;
session.scheduleSha256 = scheduleSha256;
session.uartPort = port;
session.uartBaud = baud;

summaryLines = [ ...
    "# Live FPGA spoken-digit accuracy session"; ...
    ""; ...
    "- Session: `" + session.sessionId + "`"; ...
    compose("- Planned labeled trials: %d (%d per digit)", ...
        plannedTrials, trialsPerDigit); ...
    compose("- Primary end-to-end result: %d/%d (%.2f%%)", ...
        correctTrials, plannedTrials, endToEndAccuracyPercent); ...
    compose("- Protocol completion: %d/%d (%.2f%%)", ...
        completeTrials, plannedTrials, protocolCompletionPercent); ...
    compose("- Conditional classification accuracy: %d/%d (%.2f%%)", ...
        correctTrials, completeTrials, conditionalAccuracyPercent); ...
    compose("- Protocol failures retained: %d", plannedTrials - completeTrials); ...
    "- Speaker tag: `" + speakerTag + "`"; ...
    compose("- Approximate microphone distance: %.1f cm", distanceCm); ...
    "- Environment: " + environmentNote; ...
    "- FPGA target: `" + targetSerial + "`"; ...
    "- Bitstream SHA-256: `" + bitSha + "`"; ...
    "- Programming-log SHA-256: `" + programRecord.logSha256 + "`"; ...
    "- Programming time recorded in retained log: `" + ...
        programRecord.programTimeText + "`"; ...
    "- Reference state: " + programRecord.referenceStatement; ...
    compose("- UART: `%s` at %d baud", port, baud); ...
    ""; ...
    "Every result was pre-labeled and retained. Individual predictions were hidden until the session ended; incorrect classifications were not retried or removed."; ...
    ""; ...
    "This is a single-speaker, operator-labeled, controlled bench session. It is speaker/reference-set dependent and is not a population-level speech-recognition accuracy claim. The UART packet format has structural marker/address checks but no CRC."];
writeTextAtomic(fullfile(sessionDir, "SUMMARY.md"), ...
    join(summaryLines, newline) + newline);
end

function programRecord = validateProgrammingRecord(path, bitSha, targetSerial, ...
        validationTime, maxAgeMinutes)
if ~isfile(path)
    error("MFCC:ProgrammingRecord", ...
        "Required programming log is missing: %s", path);
end
logText = string(fileread(path));
required = [ ...
    "BIT_SHA256=" + bitSha, ...
    "OPENED_TARGET=127.0.0.1:3121/xilinx_tcf/Digilent/" + targetSerial, ...
    "REGISTER.IR.BIT5_DONE=1", ...
    "REFERENCE_STATE=configuration-time COE baseline restored by this programming operation", ...
    "PROGRAM_RESULT=PASS"];
for item = required
    if ~contains(logText, item)
        error("MFCC:ProgrammingRecord", ...
            "Programming log does not contain required record: %s", item);
    end
end

token = regexp(char(logText), ...
    '(?m)^PROGRAM_TIME=(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \+03$', ...
    'tokens', 'once');
if isempty(token)
    error("MFCC:ProgrammingRecord", ...
        "Programming log has no parseable PROGRAM_TIME in +03.");
end
programTime = datetime(token{1}, "InputFormat", "yyyy-MM-dd HH:mm:ss", ...
    "TimeZone", "Europe/Istanbul");
ageMinutes = minutes(validationTime - programTime);
if ageMinutes < 0 || ageMinutes > maxAgeMinutes
    error("MFCC:ProgrammingRecord", ...
        "Programming record age is %.1f minutes; required range is 0 to %.1f.", ...
        ageMinutes, maxAgeMinutes);
end

programRecord = struct();
programRecord.logSha256 = sha256_file(path);
programRecord.programTime = programTime;
programRecord.programTimeText = string(programTime, "yyyy-MM-dd HH:mm:ss Z");
programRecord.ageMinutesAtValidation = ageMinutes;
programRecord.referenceStatement = ...
    "the retained programming log records a configuration-time COE baseline restore";
end

function createSessionDirectories(sessionDir)
[ok, message] = mkdir(sessionDir);
if ~ok
    error("MFCC:EvidenceStorage", ...
        "Cannot create session directory %s: %s", sessionDir, message);
end
for name = ["raw", "decoded", "logger_source", "provenance"]
    [ok, message] = mkdir(fullfile(sessionDir, name));
    if ~ok
        error("MFCC:EvidenceStorage", ...
            "Cannot create session subdirectory %s: %s", name, message);
    end
end
end

function copyLoggerSnapshot(hardwareDir, destinationDir)
names = ["run_live_accuracy_session.m", "capture_mfcc_debug_trial.m", ...
    "parse_mfcc_debug_bytes.m", "sha256_file.m", ...
    "test_live_accuracy_logger_offline.m", "README.md"];
for name = names
    source = fullfile(hardwareDir, name);
    destination = fullfile(destinationDir, name);
    if ~isfile(source)
        error("MFCC:EvidenceStorage", "Logger snapshot source is missing: %s", source);
    end
    copyFileVerified(source, destination, sha256_file(source));
end
end

function copyFileVerified(source, destination, expectedSha)
[ok, message] = copyfile(source, destination, "f");
if ~ok
    error("MFCC:EvidenceStorage", ...
        "Cannot copy %s to %s: %s", source, destination, message);
end
actualSha = sha256_file(destination);
if actualSha ~= expectedSha
    error("MFCC:EvidenceStorage", ...
        "Copied-file SHA-256 mismatch for %s.", destination);
end
end

function writeBitstreamIdentity(path, bitPath, bitSha, targetSerial)
lines = [ ...
    "bitstream_path=" + string(bitPath); ...
    "bitstream_sha256=" + bitSha; ...
    "jtag_target_serial=" + targetSerial; ...
    "adc_mapping=JC3/N17 spi_clk; JC4/P18 spi_miso; JC9/P17 cs_out"];
writeTextAtomic(path, join(lines, newline) + newline);
end

function writeSessionMetadata(path, sessionId, plannedTrials, trialsPerDigit, ...
        rngSeed, speakerTag, distanceCm, environmentNote, bitSha, ...
        targetSerial, port, baud, programRecord, scheduleSha256)
lines = [ ...
    "created_before_capture=" + string(datetime("now", "Format", ...
        "yyyy-MM-dd HH:mm:ss.SSS Z", "TimeZone", "Europe/Istanbul")); ...
    "session_id=" + sessionId; ...
    "protocol=mfcc-debug-63x1362-v1"; ...
    "planned_trials=" + string(plannedTrials); ...
    "trials_per_digit=" + string(trialsPerDigit); ...
    "rng_seed=" + string(rngSeed); ...
    "schedule_sha256=" + scheduleSha256; ...
    "primary_metric=correct/planned-prelabeled-trials"; ...
    "conditional_metric=correct/protocol-complete-trials"; ...
    "transport_metric=protocol-complete/planned-trials"; ...
    "post-result-retries=not-permitted"; ...
    "per-trial-results=hidden-until-session-completion"; ...
    "speaker_tag=" + speakerTag; ...
    "distance_cm=" + string(distanceCm); ...
    "environment=" + environmentNote; ...
    "bitstream_sha256=" + bitSha; ...
    "jtag_target_serial=" + targetSerial; ...
    "programming_log_sha256=" + programRecord.logSha256; ...
    "programming_time=" + programRecord.programTimeText; ...
    "reference_state=" + programRecord.referenceStatement; ...
    "uart_port=" + string(port); ...
    "uart_baud=" + string(baud)];
writeTextAtomic(path, join(lines, newline) + newline);
end

function event = baseLifecycleEvent(name, sessionId, plannedTrials)
event = struct();
event.event = name;
event.session_id = sessionId;
event.timestamp = string(datetime("now", "Format", ...
    "yyyy-MM-dd HH:mm:ss.SSS Z", "TimeZone", "Europe/Istanbul"));
event.planned_trials = plannedTrials;
end

function appendLifecycleEvent(path, event)
parent = fileparts(path);
if ~isfolder(parent)
    [ok, message] = mkdir(parent);
    if ~ok
        error("MFCC:EvidenceStorage", ...
            "Cannot create lifecycle directory %s: %s", parent, message);
    end
end
[fid, message] = fopen(path, "a");
if fid < 0
    error("MFCC:EvidenceStorage", ...
        "Cannot append lifecycle index %s: %s", path, message);
end
cleanup = onCleanup(@() fclose(fid));
count = fprintf(fid, "%s\n", jsonencode(event));
if count <= 1
    error("MFCC:EvidenceStorage", ...
        "Could not append lifecycle event to %s.", path);
end
end

function tf = isEvidenceIntegrityFailure(ME)
id = string(ME.identifier);
tf = any(id == ["MFCC:RawFile", "MFCC:RawFileWrite", ...
    "MFCC:SHA256File", "MFCC:EvidenceStorage"]);
end

function setSessionPhase(path, phase)
writeTextAtomic(path, string(phase) + newline);
end

function appendAbortedUnlessCompleted(indexPath, sessionId, plannedTrials, phasePath)
try
    if sessionHasCompletedEvent(indexPath, sessionId)
        return;
    end
    lastPhase = "unknown";
    if isfile(phasePath)
        lastPhase = strtrim(string(fileread(phasePath)));
    end
    abortedEvent = baseLifecycleEvent("aborted", sessionId, plannedTrials);
    abortedEvent.last_phase = lastPhase;
    appendLifecycleEvent(indexPath, abortedEvent);
catch cleanupError
    warning("MFCC:Lifecycle", ...
        "Could not append aborted-session record: %s", cleanupError.message);
end
end

function tf = sessionHasCompletedEvent(indexPath, sessionId)
tf = false;
if ~isfile(indexPath)
    return;
end
lines = readlines(indexPath);
for line = lines.'
    if strlength(strtrim(line)) == 0
        continue;
    end
    try
        event = jsondecode(line);
    catch
        continue;
    end
    if isfield(event, "event") && isfield(event, "session_id") && ...
            string(event.event) == "completed" && ...
            string(event.session_id) == string(sessionId)
        tf = true;
        return;
    end
end
end

function writeTableAtomic(value, path, varargin)
parent = fileparts(path);
tempPath = string(tempname(parent)) + ".csv";
cleanup = onCleanup(@() deleteIfPresent(tempPath));
try
    writetable(value, tempPath, "FileType", "text", "Delimiter", ",", ...
        varargin{:});
catch ME
    error("MFCC:EvidenceStorage", ...
        "Cannot write temporary table for %s: %s", path, ME.message);
end
moveFileOrError(tempPath, path);
clear cleanup;
end

function saveStructAtomic(path, payload)
parent = fileparts(path);
tempPath = string(tempname(parent)) + ".mat";
cleanup = onCleanup(@() deleteIfPresent(tempPath));
try
    save(tempPath, "-struct", "payload", "-v7");
catch ME
    error("MFCC:EvidenceStorage", ...
        "Cannot write temporary MAT file for %s: %s", path, ME.message);
end
moveFileOrError(tempPath, path);
clear cleanup;
end

function writeTextAtomic(path, content)
parent = fileparts(path);
tempPath = string(tempname(parent)) + ".txt";
cleanup = onCleanup(@() deleteIfPresent(tempPath));
[fid, message] = fopen(tempPath, "w");
if fid < 0
    error("MFCC:EvidenceStorage", ...
        "Cannot create temporary text file for %s: %s", path, message);
end
closeCleanup = onCleanup(@() fclose(fid));
count = fprintf(fid, "%s", content);
if count < strlength(content)
    error("MFCC:EvidenceStorage", "Short text write for %s.", path);
end
clear closeCleanup;
moveFileOrError(tempPath, path);
clear cleanup;
end

function moveFileOrError(source, destination)
[ok, message] = movefile(source, destination, "f");
if ~ok
    error("MFCC:EvidenceStorage", ...
        "Cannot move %s to %s: %s", source, destination, message);
end
end

function manifestSha256 = buildEvidenceManifest(sessionDir)
manifestPath = fullfile(sessionDir, "MANIFEST.csv");
manifestHashPath = fullfile(sessionDir, "MANIFEST.sha256");
entries = dir(fullfile(sessionDir, "**", "*"));
entries = entries(~[entries.isdir]);
relativePaths = strings(0, 1);
byteCounts = zeros(0, 1);
hashes = strings(0, 1);
prefix = string(sessionDir) + filesep;
for i = 1:numel(entries)
    absolutePath = fullfile(entries(i).folder, entries(i).name);
    relativePath = erase(string(absolutePath), prefix);
    if relativePath == "MANIFEST.csv" || relativePath == "MANIFEST.sha256" || ...
            relativePath == ".session_phase"
        continue;
    end
    relativePaths(end + 1, 1) = relativePath; %#ok<AGROW>
    byteCounts(end + 1, 1) = entries(i).bytes; %#ok<AGROW>
    hashes(end + 1, 1) = sha256_file(absolutePath); %#ok<AGROW>
end
manifest = table(relativePaths, byteCounts, hashes, ...
    'VariableNames', ["relative_path", "byte_count", "sha256"]);
manifest = sortrows(manifest, "relative_path");
writeTableAtomic(manifest, manifestPath);
manifestSha256 = sha256_file(manifestPath);
writeTextAtomic(manifestHashPath, ...
    manifestSha256 + "  MANIFEST.csv" + newline);
end

function cleanupSerial(s)
if ~isempty(s) && isvalid(s)
    flush(s);
end
end

function part = getLastPathPart(path)
[~, name, ext] = fileparts(path);
part = string(name) + string(ext);
end

function deleteIfPresent(path)
if isfile(path)
    delete(path);
end
end
