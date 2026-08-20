# Build and validate a recreated standalone ADC/UART project out of tree.

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
    error "Usage: vivado -mode batch -source build_and_verify.tcl -tclargs BUILD_DIR RESULTS_DIR ?JOBS?"
}

set script_dir [file dirname [file normalize [info script]]]
set build_dir [file normalize [lindex $argv 0]]
set results_dir [file normalize [lindex $argv 1]]
set jobs 4
if {[llength $argv] == 3} {
    set jobs [lindex $argv 2]
}
if {![string is integer -strict $jobs] || $jobs < 1} {
    error "JOBS must be a positive integer: $jobs"
}
if {[path_is_within $build_dir $script_dir] ||
    [path_is_within $results_dir $script_dir]} {
    error "Build and results directories must be outside the public source tree"
}
if {[file exists $results_dir]} {
    error "RESULTS_DIR already exists; choose a fresh path: $results_dir"
}

set project_file [file join $build_dir project pcb_adc_uart.xpr]
if {![file exists $project_file]} {
    error "Project is missing; run recreate_project.tcl first: $project_file"
}

open_project $project_file
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
    -check_timing_verbose -max_paths 10 \
    -file [file join $results_dir PCB_timing_summary_routed.rpt]
report_route_status -file [file join $results_dir PCB_route_status.rpt]
report_drc -file [file join $results_dir PCB_drc_routed.rpt]
report_methodology -file [file join $results_dir PCB_methodology_routed.rpt]
report_utilization -file [file join $results_dir PCB_utilization_routed.rpt]
report_io -file [file join $results_dir PCB_io.rpt]
report_clocks -file [file join $results_dir PCB_clocks.rpt]
report_cdc -details -file [file join $results_dir PCB_cdc.rpt]

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
if {[llength [get_drc_violations -quiet]] != 0} {
    error "DRC contains [llength [get_drc_violations -quiet]] findings"
}
if {[llength [get_methodology_violations -quiet]] != 0} {
    error "Methodology contains [llength [get_methodology_violations -quiet]] findings"
}

set expected_pin_by_port [dict create \
    clock_in W5 reset_in U18 start_in T18 ready_out U16 \
    txd_out A18 cs_out P17 spi_miso P18 spi_clk N17]
set expected_ports [lsort [dict keys $expected_pin_by_port]]
set actual_ports [lsort [get_property NAME [get_ports]]]
if {$actual_ports ne $expected_ports} {
    error "Top-level port set differs from the standalone pin map: $actual_ports"
}
dict for {port_name expected_pin} $expected_pin_by_port {
    set actual_pin [get_property PACKAGE_PIN [get_ports $port_name]]
    if {$actual_pin ne $expected_pin} {
        error "Port $port_name is on $actual_pin; expected $expected_pin"
    }
}

set sys_clock [get_clocks -quiet sys_clk_pin]
set adc_clock [get_clocks -quiet clk_out1_clk_wiz_0]
if {[llength $sys_clock] != 1 || [llength $adc_clock] != 1} {
    error "Expected exactly one 100 MHz system clock and one 36 MHz ADC clock"
}
set sys_period [get_property PERIOD $sys_clock]
set adc_period [get_property PERIOD $adc_clock]
if {abs(double($sys_period) - 10.000) > 0.001 ||
    abs(double($adc_period) - 27.778) > 0.001} {
    error "Unexpected clock periods: system=$sys_period ns, ADC=$adc_period ns"
}

set run_dir [get_property DIRECTORY [get_runs impl_1]]
set run_bit [file join $run_dir PCB.bit]
if {![file exists $run_bit]} {
    error "Implementation completed without the expected bitstream: $run_bit"
}
file copy -- $run_bit [file join $results_dir PCB.bit]

puts "BUILD_RESULT=PASS"
puts "SYNTHESIS=$synth_status"
puts "IMPLEMENTATION=$impl_status"
puts "SETUP_SLACK_NS=$setup_slack"
puts "HOLD_SLACK_NS=$hold_slack"
puts "RESULTS_DIR=$results_dir"
close_project
