# ==============================================================================
# BITSTREAM CONFIGURATION
# ==============================================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# ==============================================================================
# CLOCK SIGNAL (100 MHz)
# ==============================================================================
set_property PACKAGE_PIN W5 [get_ports clock_in]
set_property IOSTANDARD LVCMOS33 [get_ports clock_in]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clock_in]

# This file constrains the internal 100 MHz processing clock. External SPI and
# board-interface input/output delays are not yet characterized or constrained.

# ==============================================================================
# BUTTONS
# ==============================================================================
# Center Button (Reset)
set_property PACKAGE_PIN U18 [get_ports reset_in]
set_property IOSTANDARD LVCMOS33 [get_ports reset_in]

# Up Button (Start ADC)
set_property PACKAGE_PIN T18 [get_ports start_in]
set_property IOSTANDARD LVCMOS33 [get_ports start_in]

# Right Button (Increment selected trial)
set_property PACKAGE_PIN T17 [get_ports trial_inc_in]
set_property IOSTANDARD LVCMOS33 [get_ports trial_inc_in]

# Left Button (Decrement selected trial)
set_property PACKAGE_PIN W19 [get_ports trial_dec_in]
set_property IOSTANDARD LVCMOS33 [get_ports trial_dec_in]

# Down Button (Flush compare reference RAM)
set_property PACKAGE_PIN U17 [get_ports flush]
set_property IOSTANDARD LVCMOS33 [get_ports flush]


# ==============================================================================
# LEDs (Status Indicators)
# ==============================================================================
set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports {debug_led_out}];# LD1, debug enabled
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports {ready_out}];# LD6
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports {adcbusy}];# LD7
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports {adcdone}];# LD8
set_property -dict { PACKAGE_PIN V3    IOSTANDARD LVCMOS33 } [get_ports {flush_done}];# LD9

# ==============================================================================
# SPI INTERFACE - NEW ADC PCB ON PMOD JC
# ==============================================================================
# This is the complete alternate constraint file for the new ADC PCB. Use it
# instead of xdc.xdc; never enable both complete files in one constraint set.
# JC10/R18 remains driven by the separate pmod output below and must be left
# electrically unconnected by the ADC PCB unless that connection is intended.

set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports {cs_out}];# JC9
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports {spi_miso}];# JC4
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports {spi_clk}];# JC3
# JC1, JC2, JC7, and JC8 are unused by the ADC interface.



set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports {switch}];# SW0, 1=record, 0=compare
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports {debug_enable_in}];# SW1, 1=debug UART enabled
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports {pmod}];#Sch name = JC10

# USB UART TX to PC
set_property PACKAGE_PIN A18 [get_ports txd_out]
set_property IOSTANDARD LVCMOS33 [get_ports txd_out]

# ==============================================================================
# DIGIT SELECTION SWITCHES
# ==============================================================================
# Basys3 LD0..LD15 are LED outputs, not switch inputs. Digit selection uses the
# adjacent onboard switches SW6..SW15. digit_sw_in(0) selects digit 0, ...
# digit_sw_in(9) selects digit 9.
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[0]}];# SW6
set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[1]}];# SW7
set_property -dict { PACKAGE_PIN V2    IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[2]}];# SW8
set_property -dict { PACKAGE_PIN T3    IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[3]}];# SW9
set_property -dict { PACKAGE_PIN T2    IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[4]}];# SW10
set_property -dict { PACKAGE_PIN R3    IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[5]}];# SW11
set_property -dict { PACKAGE_PIN W2    IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[6]}];# SW12
set_property -dict { PACKAGE_PIN U1    IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[7]}];# SW13
set_property -dict { PACKAGE_PIN T1    IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[8]}];# SW14
set_property -dict { PACKAGE_PIN R2    IOSTANDARD LVCMOS33 } [get_ports {digit_sw_in[9]}];# SW15

# ==============================================================================
# SEVEN-SEGMENT DISPLAY
# ==============================================================================
set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
set_property -dict { PACKAGE_PIN V4   IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
set_property -dict { PACKAGE_PIN W4   IOSTANDARD LVCMOS33 } [get_ports {an[3]}]

set_property -dict { PACKAGE_PIN W7   IOSTANDARD LVCMOS33 } [get_ports {a_to_g[0]}]
set_property -dict { PACKAGE_PIN W6   IOSTANDARD LVCMOS33 } [get_ports {a_to_g[1]}]
set_property -dict { PACKAGE_PIN U8   IOSTANDARD LVCMOS33 } [get_ports {a_to_g[2]}]
set_property -dict { PACKAGE_PIN V8   IOSTANDARD LVCMOS33 } [get_ports {a_to_g[3]}]
set_property -dict { PACKAGE_PIN U5   IOSTANDARD LVCMOS33 } [get_ports {a_to_g[4]}]
set_property -dict { PACKAGE_PIN V5   IOSTANDARD LVCMOS33 } [get_ports {a_to_g[5]}]
set_property -dict { PACKAGE_PIN U7   IOSTANDARD LVCMOS33 } [get_ports {a_to_g[6]}]
