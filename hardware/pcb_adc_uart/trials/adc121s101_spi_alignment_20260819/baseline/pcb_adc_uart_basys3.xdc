# Standalone constraints for the recovered PCB ADC-to-UART diagnostic.
# Target board: Digilent Basys 3 (xc7a35tcpg236-1)

# Configuration-bank voltage.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# 100 MHz Basys 3 oscillator.
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports {clock_in}]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports {clock_in}]

# Pushbuttons: BTNC resets the diagnostic and BTNU enables acquisition.
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {reset_in}]
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports {start_in}]

# LD0: high when the capture/UART path is ready.
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {ready_out}]

# USB-UART transmit path from the FPGA to the FT2232H interface.
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports {txd_out}]

# Pmod JC: ADC121S101-style three-wire SPI connection. This mirrors the live
# JB3/JB4/JB9 connector-position mapping on JC3/JC4/JC9.
#set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports {JC[0]}] ;# JC1
#set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports {JC[1]}] ;# JC2
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports {spi_clk}] ;# JC3
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports {spi_miso}];# JC4
#set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports {JC[4]}] ;# JC7
#set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports {JC[5]}] ;# JC8
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports {cs_out}]   ;# JC9
#set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {JC[7]}] ;# JC10

# Previous Pmod JB wiring retained as a disabled fallback.
#set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports {spi_clk}] ;# JB3
#set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports {spi_miso}];# JB4
#set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports {cs_out}]   ;# JB9

# Pmod power/ground positions are fixed board connections, not FPGA package
# pins, so they have no XDC entries.

# Clock-domain crossing intent.
# PCB.vhd uses two-stage toggle synchronizers in each direction. The 16-bit
# sample bus is held stable by that request/acknowledge protocol while tx_word
# captures it. These deliberate inter-clock crossings are excluded below;
# separate asynchronous board-control/output exceptions follow afterward.
set cdc_sync_regs [get_cells -quiet -hierarchical [list \
    sample_req_meta_u_reg sample_req_sync_u_reg \
    sample_ack_meta_a_reg sample_ack_sync_a_reg]]
set_property ASYNC_REG TRUE $cdc_sync_regs

set req_meta_d [get_pins -quiet -hierarchical sample_req_meta_u_reg/D]
set ack_meta_d [get_pins -quiet -hierarchical sample_ack_meta_a_reg/D]
set sample_bus_regs [get_cells -quiet -hierarchical *sample_word_adc_reg*]
set tx_word_regs [get_cells -quiet -hierarchical *tx_word_reg*]

set_false_path -to $req_meta_d
set_false_path -to $ack_meta_d
set_false_path -from $sample_bus_regs -to $tx_word_regs

# These are asynchronous physical controls/protocol outputs, not source-
# synchronous interfaces with external timing relationships.
set_false_path -from [get_ports {reset_in start_in}]
set_false_path -to [get_ports {ready_out txd_out}]
