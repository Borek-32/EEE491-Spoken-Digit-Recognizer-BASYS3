# Recreate the MFCC project from public source inputs in a fresh external tree.
# Reference tool: Vivado 2025.2.

proc path_is_within {child parent} {
    set child_parts [file split [file normalize $child]]
    set parent_parts [file split [file normalize $parent]]
    if {[llength $child_parts] < [llength $parent_parts]} {
        return 0
    }
    set last_parent_index [expr {[llength $parent_parts] - 1}]
    return [expr {[lrange $child_parts 0 $last_parent_index] eq $parent_parts}]
}

if {[llength $argv] != 1} {
    error "Usage: vivado -mode batch -source recreate_project.tcl -tclargs BUILD_DIR"
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file dirname $script_dir]
set build_dir [file normalize [lindex $argv 0]]

if {[path_is_within $build_dir $repo_root]} {
    error "BUILD_DIR must be outside the source repository: $build_dir"
}
if {[file exists $build_dir]} {
    error "BUILD_DIR already exists; choose a fresh path: $build_dir"
}

set project_dir $build_dir
file mkdir $project_dir
create_project {mfcc-recog 1.4} $project_dir -part xc7a35tcpg236-1

foreach directory {rtl testbench constraints verification} {
    set source [file join $repo_root $directory]
    if {![file isdirectory $source]} {
        error "Required source directory is missing: $source"
    }
    file copy -- $source $project_dir
}
# Preserve the vendor-authored XCI relative layout and original source-tree
# directory name in the external snapshot. Vivado validates this customization
# context; raw XCI JSON must not be rewritten or relocated arbitrarily.
set vendor_sources [file join $build_dir {mfcc-recog 1.4.srcs} sources_1]
file mkdir [file join $vendor_sources imports]
file copy -- [file join $repo_root ip] $vendor_sources
file copy -- [file join $repo_root data] \
    [file join $vendor_sources imports coe_files]
file mkdir [file join $project_dir scripts]
file copy -- [file join $repo_root scripts expected_pinmap.tcl] \
    [file join $project_dir scripts expected_pinmap.tcl]

set rtl_files [lsort [glob -types f -directory [file join $project_dir rtl] *.vhd]]
set tb_files [lsort [glob -types f -directory [file join $project_dir testbench] *.vhd]]
set data_files [lsort [glob -types f -directory \
    [file join $vendor_sources imports coe_files] *.coe]]
set xci_files {}
foreach core_dir [lsort [glob -types d -directory \
    [file join $vendor_sources ip] *]] {
    foreach xci [lsort [glob -nocomplain -types f -directory $core_dir *.xci]] {
        lappend xci_files $xci
    }
}

if {[llength $rtl_files] != 11} {
    error "Expected 11 RTL VHDL files, found [llength $rtl_files]"
}
if {[llength $tb_files] != 11} {
    error "Expected 11 testbench VHDL files, found [llength $tb_files]"
}
if {[llength $data_files] != 5} {
    error "Expected 5 COE files, found [llength $data_files]"
}
if {[llength $xci_files] != 20} {
    error "Expected 20 XCI files, found [llength $xci_files]"
}

set constraint_file [file join $project_dir constraints jc_homefab.xdc]
if {![file exists $constraint_file]} {
    error "Canonical JC constraint file is missing: $constraint_file"
}

set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]
add_files -fileset sources_1 -norecurse $rtl_files
add_files -fileset sources_1 -norecurse $data_files
add_files -fileset sources_1 -norecurse $xci_files
add_files -fileset constrs_1 -norecurse [list $constraint_file]
add_files -fileset sim_1 -norecurse $tb_files

set_property file_type {VHDL 2008} [get_files -quiet *.vhd]
set_property top top_module [get_filesets sources_1]
set_property top tb_top_module [get_filesets sim_1]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set configured_ips [get_ips -quiet]
if {[llength $configured_ips] != 20} {
    error "Expected 20 configured IP objects, found [llength $configured_ips]"
}
# A fresh project does not inherit all of the IP customization state held by
# the legacy XPR. Reapply one defining customization through Vivado's IP API
# for each affected core family. The stored values remain unchanged, while
# Vivado initializes the model parameters needed by generate_target.
foreach configured_ip $configured_ips {
    if {[lsearch -exact [list_property $configured_ip] CONFIG.Coe_File] >= 0} {
        set coe_value [get_property CONFIG.Coe_File $configured_ip]
        if {$coe_value ne "no_coe_file_loaded"} {
            set resolved_coe [file normalize \
                [file join [get_property IP_DIR $configured_ip] $coe_value]]
            if {![file exists $resolved_coe]} {
                error "IP [get_property NAME $configured_ip] references missing COE: $resolved_coe"
            }
            set_property CONFIG.Coe_File $resolved_coe $configured_ip
        }
    }
    if {[lsearch -exact [list_property $configured_ip] CONFIG.MultType] >= 0} {
        set mult_type [get_property CONFIG.MultType $configured_ip]
        set_property CONFIG.MultType $mult_type $configured_ip
    }
    if {[lsearch -exact [list_property $configured_ip] CONFIG.transform_length] >= 0} {
        set transform_length [get_property CONFIG.transform_length $configured_ip]
        set_property CONFIG.transform_length $transform_length $configured_ip
    }
}
generate_target all $configured_ips

puts "RECREATE_RESULT=PASS"
puts "PROJECT_FILE=[file join $project_dir {mfcc-recog 1.4.xpr}]"
puts "PART=xc7a35tcpg236-1"
puts "TOP=top_module"
puts "CONSTRAINT=constraints/jc_homefab.xdc"
puts "RTL_COUNT=[llength $rtl_files]"
puts "TESTBENCH_COUNT=[llength $tb_files]"
puts "XCI_COUNT=[llength $xci_files]"
puts "COE_COUNT=[llength $data_files]"
close_project
