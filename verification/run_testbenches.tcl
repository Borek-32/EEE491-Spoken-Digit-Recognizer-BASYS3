# Run bounded behavioral regressions against an external recreated project.
# The first Tcl argument is BUILD_DIR; remaining arguments are optional benches.

if {[llength $argv] < 1} {
    error "Usage: vivado -mode batch -source run_testbenches.tcl -tclargs BUILD_DIR ?TESTBENCH ...?"
}

set build_dir [file normalize [lindex $argv 0]]
set project_file [file join $build_dir {mfcc-recog 1.4.xpr}]
set requested [lrange $argv 1 end]

set default_testbenches {
    tb_CTRL
    tb_debug
    tb_WINDOW
    tb_FFT
    tb_MEL
    tb_LOGMEL
    tb_DCT
    tb_comp
    tb_seven_segment
}

if {[llength $requested] == 0} {
    set testbenches $default_testbenches
} else {
    set testbenches $requested
}

if {![file exists $project_file]} {
    error "Recreated project is missing: $project_file"
}

open_project $project_file
set simset [get_filesets sim_1]
set original_top [get_property top $simset]
set failures {}
set xsim_log [file join $build_dir {mfcc-recog 1.4.sim} sim_1 behav xsim simulate.log]
set safe_sim_limit [list 20 ms]

foreach tb $testbenches {
    puts "TESTBENCH_START $tb"
    if {[catch {
        if {$tb eq "tb_ADC"} {
            error "tb_ADC is disabled in the safe runner; use an explicitly monitored workflow"
        }

        set_property top $tb $simset
        update_compile_order -fileset sim_1
        launch_simulation -simset sim_1 -mode behavioral
        run {*}$safe_sim_limit

        if {![file exists $xsim_log]} {
            error "XSim transcript is missing: $xsim_log"
        }
        set log_handle [open $xsim_log r]
        set sim_text [read $log_handle]
        close $log_handle
        if {[regexp -line {^(Failure|Fatal|Error):} $sim_text failure_line]} {
            error "XSim reported $failure_line"
        }
        if {![string match {*$finish called*} $sim_text]} {
            error "Simulation did not call std.env.finish before [join $safe_sim_limit { }]"
        }
        close_sim
    } message options]} {
        puts stderr "TESTBENCH_FAIL $tb: $message"
        lappend failures $tb
        catch {close_sim}
    } else {
        puts "TESTBENCH_PASS $tb"
    }
}

set_property top $original_top $simset
close_project

if {[llength $failures] != 0} {
    error "Behavioral regression failed: [join $failures {, }]"
}

puts "TESTBENCH_REGRESSION_PASS [join $testbenches {, }]"
