# Program an explicitly identified rebuilt candidate on an explicitly selected
# Basys 3 target. No historical bitstream or device ID is embedded here.

if {[llength $argv] != 3} {
    error "Usage: vivado -mode batch -source program_candidate.tcl -tclargs BITSTREAM JTAG_TARGET_SUBSTRING EXPECTED_SHA256"
}

set bit_file [file normalize [lindex $argv 0]]
set target_substring [string trim [lindex $argv 1]]
set expected_sha256 [string tolower [string trim [lindex $argv 2]]]

if {$target_substring eq ""} {
    error "JTAG_TARGET_SUBSTRING must be nonempty"
}
if {![regexp {^[0-9a-f]{64}$} $expected_sha256]} {
    error "EXPECTED_SHA256 must be exactly 64 hexadecimal characters"
}
if {![file exists $bit_file]} {
    error "Candidate bitstream is missing: $bit_file"
}

set actual_sha256 [string tolower [lindex [exec sha256sum -- $bit_file] 0]]
puts "BIT_SHA256=$actual_sha256"
if {$actual_sha256 ne $expected_sha256} {
    error "Candidate SHA-256 mismatch: expected $expected_sha256, received $actual_sha256"
}

open_hw_manager
connect_hw_server -url 127.0.0.1:3121
set targets [get_hw_targets -quiet -filter "NAME =~ *$target_substring*"]
if {[llength $targets] != 1} {
    error "Expected exactly one explicit target match; found [llength $targets]"
}
current_hw_target [lindex $targets 0]
set_property PARAM.FREQUENCY 15000000 [current_hw_target]
open_hw_target
puts "OPENED_TARGET=[get_property NAME [current_hw_target]]"

set devices [get_hw_devices -quiet -filter {PART =~ "xc7a35t*"}]
if {[llength $devices] != 1} {
    error "Expected exactly one xc7a35t device; found [llength $devices]"
}
set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device -update_hw_probes false $device

set done_seen 0
foreach done_property {REGISTER.IR.BIT5_DONE REGISTER.CONFIG_STATUS.BIT14_DONE} {
    if {[lsearch -exact [list_property $device] $done_property] >= 0} {
        set done_value [get_property $done_property $device]
        puts "$done_property=$done_value"
        set done_seen 1
        if {$done_value ne "1"} {
            error "Device DONE property is not asserted: $done_value"
        }
    }
}
if {!$done_seen} {
    error "Vivado did not expose a DONE status property"
}

puts "PROGRAM_RESULT=PASS"
close_hw_target
disconnect_hw_server
close_hw_manager
