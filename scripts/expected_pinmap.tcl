# Complete Basys 3 package-pin map for top_module and the home-fabricated ADC
# board on Pmod JC. build_jc_homefab.tcl consumes this dictionary after route.
set expected_pin_by_port [dict create \
    clock_in W5 \
    reset_in U18 \
    start_in T18 \
    trial_inc_in T17 \
    trial_dec_in W19 \
    flush U17 \
    debug_led_out E19 \
    ready_out U14 \
    adcbusy V14 \
    adcdone V13 \
    flush_done V3 \
    cs_out P17 \
    spi_miso P18 \
    spi_clk N17 \
    switch V17 \
    debug_enable_in V16 \
    pmod R18 \
    txd_out A18 \
    {digit_sw_in[0]} W14 \
    {digit_sw_in[1]} W13 \
    {digit_sw_in[2]} V2 \
    {digit_sw_in[3]} T3 \
    {digit_sw_in[4]} T2 \
    {digit_sw_in[5]} R3 \
    {digit_sw_in[6]} W2 \
    {digit_sw_in[7]} U1 \
    {digit_sw_in[8]} T1 \
    {digit_sw_in[9]} R2 \
    {an[0]} U2 \
    {an[1]} U4 \
    {an[2]} V4 \
    {an[3]} W4 \
    {a_to_g[0]} W7 \
    {a_to_g[1]} W6 \
    {a_to_g[2]} U8 \
    {a_to_g[3]} V8 \
    {a_to_g[4]} U5 \
    {a_to_g[5]} V5 \
    {a_to_g[6]} U7]
