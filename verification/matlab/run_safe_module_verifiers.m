% Run the non-ADC, non-top MATLAB verification suite as hard pass/fail gates.
% The matching XSim suite is verification/run_testbenches.tcl in the external
% project snapshot produced by scripts/recreate_project.tcl.

script_dir = fileparts(mfilename('fullpath'));
verification_dir = fileparts(script_dir);
log_dir = fullfile(verification_dir, 'logs', 'fft_alignment_20260713');
if ~exist(log_dir, 'dir'); mkdir(log_dir); end
log_file = fullfile(log_dir, 'matlab_safe_module_verifiers.txt');
fft_figure_dir = fullfile(verification_dir, 'figures', 'fft_alignment_fixed_20260713_final');
if ~exist(fft_figure_dir, 'dir'); mkdir(fft_figure_dir); end

old_dir = pwd;
old_visible = get(0, 'DefaultFigureVisible');
cleanup_state = onCleanup(@() cleanup_verifier_state(old_dir, old_visible));
cd(script_dir);
set(0, 'DefaultFigureVisible', 'off');
if isfile(log_file); delete(log_file); end
diary(log_file);
cleanup_diary = onCleanup(@() diary('off'));

bitaccurate_generator = fullfile(verification_dir, 'tools', 'generate_xfft_bitaccurate_reference.sh');
[generator_status, generator_output] = system(['"' bitaccurate_generator '"']);
fprintf('%s', generator_output);
if generator_status ~= 0
    error('AMD XFFT bit-accurate reference generation failed');
end

suite_checkers = {
    'check_tb_ctrl.m';
    'check_tb_debug.m';
    'check_tb_window.m';
    'check_tb_fft_wrapper.m';
    'check_tb_mel.m';
    'check_tb_logmel.m';
    'check_tb_dct.m';
    'check_tb_comp.m';
    'check_tb_seven_segment.m';
};

for suite_idx = 1:numel(suite_checkers)
    suite_checker = suite_checkers{suite_idx};
    close all;
    fprintf('VERIFIER_START %s\n', suite_checker);
    run(fullfile(script_dir, suite_checker));
    fprintf('VERIFIER_PASS %s\n', suite_checker);
end

fprintf('SAFE_MODULE_VERIFIERS_PASS count=%d\n', numel(suite_checkers));

function cleanup_verifier_state(old_dir, old_visible)
    close all;
    set(0, 'DefaultFigureVisible', old_visible);
    cd(old_dir);
end
