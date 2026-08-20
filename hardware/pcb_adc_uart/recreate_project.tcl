# Recreate the standalone ADC/UART project in a fresh external directory.

proc path_is_within {child parent} {
    set child_parts [file split [file normalize $child]]
    set parent_parts [file split [file normalize $parent]]
    if {[llength $child_parts] < [llength $parent_parts]} {
        return 0
    }
    set last_parent_index [expr {[llength $parent_parts] - 1}]
    return [expr {[lrange $child_parts 0 $last_parent_index] eq $parent_parts}]
}

if {[llength $argv] < 1 || [llength $argv] > 2} {
    error "Usage: vivado -mode batch -source recreate_project.tcl -tclargs BUILD_DIR ?RTL_SOURCE?"
}

set script_dir [file dirname [file normalize [info script]]]
set build_dir [file normalize [lindex $argv 0]]
set rtl_source [file join $script_dir src PCB.vhd]
if {[llength $argv] == 2} {
    set rtl_source [file normalize [lindex $argv 1]]
}

if {[path_is_within $build_dir $script_dir]} {
    error "BUILD_DIR must be outside the public source tree: $build_dir"
}
if {[file exists $build_dir]} {
    error "BUILD_DIR already exists; choose a fresh path: $build_dir"
}
if {![file exists $rtl_source]} {
    error "RTL source is missing: $rtl_source"
}

set project_dir [file join $build_dir project]
file mkdir [file join $project_dir src]
file mkdir [file join $project_dir constraints]
file mkdir [file join $project_dir ip clk_wiz_0]
file copy -- $rtl_source [file join $project_dir src PCB.vhd]
file copy -- [file join $script_dir constraints pcb_adc_uart_basys3.xdc] \
    [file join $project_dir constraints pcb_adc_uart_basys3.xdc]
file copy -- [file join $script_dir ip clk_wiz_0 clk_wiz_0.xci] \
    [file join $project_dir ip clk_wiz_0 clk_wiz_0.xci]

create_project pcb_adc_uart $project_dir -part xc7a35tcpg236-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]
set_property IP_OUTPUT_REPO [file join $build_dir generated ip] [current_project]

add_files -fileset sources_1 -norecurse [list [file join $project_dir src PCB.vhd]]
add_files -fileset sources_1 -norecurse \
    [list [file join $project_dir ip clk_wiz_0 clk_wiz_0.xci]]
add_files -fileset constrs_1 -norecurse \
    [list [file join $project_dir constraints pcb_adc_uart_basys3.xdc]]
set_property file_type {VHDL 2008} [get_files -quiet *.vhd]
set_property top PCB [get_filesets sources_1]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]

set clk_ip [get_ips -quiet clk_wiz_0]
if {[llength $clk_ip] != 1} {
    error "Expected exactly one clk_wiz_0 IP object, found [llength $clk_ip]"
}
generate_target all $clk_ip
update_compile_order -fileset sources_1

puts "RECREATE_RESULT=PASS"
puts "PROJECT_FILE=[file join $project_dir pcb_adc_uart.xpr]"
puts "RTL_SOURCE=$rtl_source"
puts "TOP=PCB"
puts "PART=xc7a35tcpg236-1"
close_project
