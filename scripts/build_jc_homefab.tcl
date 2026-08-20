# Synthesize, implement and validate the clean JC/home-fabricated-board profile.
# All generated artifacts are written outside the public source repository.

proc path_is_within {child parent} {
    set child_parts [file split [file normalize $child]]
    set parent_parts [file split [file normalize $parent]]
    if {[llength $child_parts] < [llength $parent_parts]} {
        return 0
    }
    set last_parent_index [expr {[llength $parent_parts] - 1}]
    return [expr {[lrange $child_parts 0 $last_parent_index] eq $parent_parts}]
}

if {[llength $argv] < 2 || [llength $argv] > 3} {
    error "Usage: vivado -mode batch -source build_jc_homefab.tcl -tclargs BUILD_DIR RESULTS_DIR ?JOBS?"
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file dirname $script_dir]
set build_dir [file normalize [lindex $argv 0]]
set results_dir [file normalize [lindex $argv 1]]
set jobs 4
if {[llength $argv] == 3} {
    set jobs [lindex $argv 2]
}
if {![string is integer -strict $jobs] || $jobs < 1} {
    error "JOBS must be a positive integer: $jobs"
}

if {[path_is_within $build_dir $repo_root] || [path_is_within $results_dir $repo_root]} {
    error "BUILD_DIR and RESULTS_DIR must both be outside the source repository"
}
if {[file exists $results_dir]} {
    error "RESULTS_DIR already exists; choose a fresh path: $results_dir"
}

set project_dir $build_dir
set project_file [file join $project_dir {mfcc-recog 1.4.xpr}]
if {![file exists $project_file]} {
    error "Project is missing; run recreate_project.tcl first: $project_file"
}

open_project $project_file
if {[get_property PART [current_project]] ne "xc7a35tcpg236-1"} {
    error "Unexpected FPGA part: [get_property PART [current_project]]"
}
if {[get_property top [get_filesets sources_1]] ne "top_module"} {
    error "Unexpected synthesis top: [get_property top [get_filesets sources_1]]"
}

set top_constraints [get_files -quiet -of_objects [get_filesets constrs_1]]
if {[llength $top_constraints] != 1 ||
    [file tail [lindex $top_constraints 0]] ne "jc_homefab.xdc"} {
    error "Expected the sole top-level constraint file to be jc_homefab.xdc: $top_constraints"
}

file mkdir $results_dir
reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis did not complete: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "Implementation did not complete: $impl_status"
}

open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $results_dir top_module_jc_homefab_timing_summary.rpt]
report_route_status -file [file join $results_dir top_module_jc_homefab_route_status.rpt]
report_drc -file [file join $results_dir top_module_jc_homefab_drc.rpt]
report_methodology -file [file join $results_dir top_module_jc_homefab_methodology.rpt]
report_utilization -file [file join $results_dir top_module_jc_homefab_utilization.rpt]
report_io -file [file join $results_dir top_module_jc_homefab_io.rpt]
report_clocks -file [file join $results_dir top_module_jc_homefab_clocks.rpt]
report_cdc -details -file [file join $results_dir top_module_jc_homefab_cdc.rpt]
check_timing -verbose -file [file join $results_dir top_module_jc_homefab_check_timing.rpt]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
    error "Could not obtain routed setup and hold paths"
}
set setup_slack [get_property SLACK [lindex $setup_path 0]]
set hold_slack [get_property SLACK [lindex $hold_path 0]]
if {$setup_slack < 0.0 || $hold_slack < 0.0} {
    error "Routed timing failed: setup=$setup_slack ns, hold=$hold_slack ns"
}

set bad_route_nets [get_nets -quiet -hierarchical -filter {
    ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE
}]
if {[llength $bad_route_nets] != 0} {
    error "Routing is incomplete for [llength $bad_route_nets] nets"
}

set severe_drc {}
foreach violation [get_drc_violations -quiet] {
    set severity [string tolower [get_property SEVERITY $violation]]
    if {$severity eq "error" || $severity eq "critical warning" ||
        $severity eq "warning"} {
        lappend severe_drc $violation
    }
}
if {[llength $severe_drc] != 0} {
    error "DRC contains [llength $severe_drc] error/critical-warning/warning findings"
}

source [file join $project_dir scripts expected_pinmap.tcl]
set expected_ports [lsort [dict keys $expected_pin_by_port]]
set actual_ports [lsort [get_property NAME [get_ports]]]
if {$actual_ports ne $expected_ports} {
    error "Top-level port set differs from the 39-port canonical map: $actual_ports"
}
set actual_pins {}
dict for {port_name expected_pin} $expected_pin_by_port {
    set actual_pin [get_property PACKAGE_PIN [get_ports $port_name]]
    if {$actual_pin ne $expected_pin} {
        error "Port $port_name is on $actual_pin; expected $expected_pin"
    }
    lappend actual_pins $actual_pin
}
if {[llength [lsort -unique $actual_pins]] != [llength $actual_pins]} {
    error "Two top-level ports share a package pin in the canonical map"
}

set sys_clock [get_clocks -quiet sys_clk_pin]
if {[llength $sys_clock] != 1} {
    error "Expected exactly one sys_clk_pin clock"
}
set sys_period [get_property PERIOD $sys_clock]
if {abs(double($sys_period) - 10.000) > 0.001} {
    error "Unexpected system-clock period: $sys_period ns"
}

set run_dir [get_property DIRECTORY [get_runs impl_1]]
set run_bit [file join $run_dir top_module.bit]
if {![file exists $run_bit]} {
    error "Implementation completed without the expected bitstream: $run_bit"
}
set result_bit [file join $results_dir top_module_jc_homefab.bit]
file copy -- $run_bit $result_bit

set status_path [file join $results_dir build_status.txt]
set status_handle [open $status_path w]
puts $status_handle "RESULT=PASS"
puts $status_handle "SYNTHESIS=$synth_status"
puts $status_handle "IMPLEMENTATION=$impl_status"
puts $status_handle "SETUP_SLACK_NS=$setup_slack"
puts $status_handle "HOLD_SLACK_NS=$hold_slack"
puts $status_handle "TOP=top_module"
puts $status_handle "PART=xc7a35tcpg236-1"
puts $status_handle "CONSTRAINT=jc_homefab.xdc"
puts $status_handle "PORT_COUNT=[llength $actual_ports]"
close $status_handle

puts "BUILD_RESULT=PASS"
puts "SYNTHESIS=$synth_status"
puts "IMPLEMENTATION=$impl_status"
puts "SETUP_SLACK_NS=$setup_slack"
puts "HOLD_SLACK_NS=$hold_slack"
puts "RESULTS_DIR=$results_dir"
close_project
