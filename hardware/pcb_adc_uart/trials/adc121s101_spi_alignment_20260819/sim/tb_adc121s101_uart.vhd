library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_adc121s101_uart is
end entity;

architecture sim of tb_adc121s101_uart is
    constant C_SYS_PERIOD : time := 10 ns;
    constant C_UART_DIV   : positive := 10;
    constant C_UART_BIT   : time := C_SYS_PERIOD * C_UART_DIV;
    constant C_T_EN       : time := 20 ns;
    constant C_T_ACC      : time := 40 ns;
    constant C_T_DIS      : time := 25 ns;
    constant C_T_SU       : time := 10 ns;

    type raw_code_array_t is array (natural range <>) of natural range 0 to 4095;
    constant C_RAW_CODES : raw_code_array_t := (
        16#000#, 16#001#, 16#7FF#, 16#800#, 16#801#, 16#FFF#
    );

    type signed_array_t is array (natural range <>) of integer range -32768 to 32767;
    constant C_EXPECTED : signed_array_t := (-2048, -2047, -1, 0, 1, 2047);

    signal clock_in  : std_logic := '0';
    signal reset_in  : std_logic := '1';
    signal start_in  : std_logic := '0';
    signal spi_miso  : std_logic := 'Z';
    signal spi_clk   : std_logic;
    signal cs_out    : std_logic;
    signal txd_out   : std_logic;
    signal ready_out : std_logic;

    signal adc_drive         : std_logic := 'Z';
    signal frame_count       : natural := 0;
    signal frame_error_count : natural := 0;
    signal setup_error_count : natural := 0;
    signal uart_error_count  : natural := 0;
    signal uart_word_count   : natural := 0;
begin
    clock_in <= not clock_in after C_SYS_PERIOD / 2;
    spi_miso <= adc_drive;

    dut : entity work.PCB
        generic map (
            clk_hz    => 100_000_000,
            uart_baud => 10_000_000,
            avg_shift => 5
        )
        port map (
            reset_in  => reset_in,
            clock_in  => clock_in,
            start_in  => start_in,
            spi_miso  => spi_miso,
            spi_clk   => spi_clk,
            cs_out    => cs_out,
            txd_out   => txd_out,
            ready_out => ready_out
        );

    stimulus_p : process
    begin
        reset_in <= '1';
        start_in <= '0';
        wait for 200 ns;
        wait until rising_edge(clock_in);
        reset_in <= '0';
        wait for 100 ns;
        wait until rising_edge(clock_in);
        start_in <= '1';
        wait;
    end process;

    -- Behavioral ADC121S101 serial-output model.
    --
    -- At CS assertion, Z2 becomes available after tEN. If CS was asserted
    -- while SCLK was low and a rising edge occurs before the first falling
    -- edge, the receiver can capture the datasheet's optional fourth leading
    -- zero. In that phase relationship the values launched after falling
    -- edges 1..15 are Z2, Z1, Z0, DB11..DB0. With no intervening rising edge,
    -- the normal three-leading-zero stream advances one position earlier.
    -- Output changes use worst-case 3.3 V tACC=40 ns. The output returns to
    -- TRI-STATE after falling edge 16 using worst-case tDIS=25 ns.
    adc_model_p : process(cs_out, spi_clk)
        variable active_v          : boolean := false;
        variable saw_rise_v        : boolean := false;
        variable extra_leading_v   : boolean := false;
        variable edge_count_v      : natural range 0 to 32 := 0;
        variable frame_ordinal_v   : natural := 0;
        variable code_v            : std_logic_vector(11 downto 0) := (others => '0');
        variable cs_fall_time_v    : time := 0 ns;
        variable group_v           : natural := 0;
        variable next_bit_v        : std_logic := '0';
        variable local_frame_err_v : natural := 0;
        variable local_setup_err_v : natural := 0;
    begin
        if cs_out'event then
            if cs_out = '0' then
                active_v        := true;
                saw_rise_v      := false;
                extra_leading_v := false;
                edge_count_v    := 0;
                cs_fall_time_v  := now;

                -- Frame zero is a deliberately conservative, nontrivial dummy
                -- used to test the candidate's discard behavior. This does not
                -- imply that start_in is equivalent to ADC power-up. Each
                -- following raw code occupies exactly 32 frames so avg_shift=5
                -- has an unambiguous result.
                if frame_ordinal_v = 0 then
                    code_v := std_logic_vector(to_unsigned(16#A5A#, 12));
                else
                    group_v := (frame_ordinal_v - 1) / 32;
                    if group_v > C_RAW_CODES'high then
                        group_v := C_RAW_CODES'high;
                    end if;
                    code_v := std_logic_vector(to_unsigned(C_RAW_CODES(group_v), 12));
                end if;
                frame_ordinal_v := frame_ordinal_v + 1;

                -- Z2 leaves TRI-STATE after tEN. 'Z' before tEN makes an
                -- early receiver sample observable rather than silently zero.
                adc_drive <= transport '0' after C_T_EN;
            else
                if active_v then
                    if edge_count_v /= 16 then
                        report "ADC frame " & integer'image(frame_ordinal_v - 1) &
                               " has " & integer'image(edge_count_v) &
                               " falling SCLK edges; expected exactly 16"
                            severity error;
                        local_frame_err_v := local_frame_err_v + 1;
                    end if;
                    frame_count       <= frame_count + 1;
                    frame_error_count <= local_frame_err_v;
                    setup_error_count <= local_setup_err_v;
                end if;
                active_v := false;
                adc_drive <= transport 'Z' after C_T_DIS;
            end if;
        end if;

        if spi_clk'event and active_v and cs_out = '0' then
            if spi_clk = '1' then
                saw_rise_v := true;
            elsif spi_clk = '0' then
                edge_count_v := edge_count_v + 1;

                if edge_count_v = 1 then
                    extra_leading_v := saw_rise_v;
                    if frame_ordinal_v = 1 then
                        report "ADC model first-frame phase: CS setup=" &
                               time'image(now - cs_fall_time_v) &
                               ", optional fourth leading zero=" &
                               boolean'image(extra_leading_v)
                            severity note;
                    end if;
                    if now - cs_fall_time_v < C_T_SU then
                        report "CS-to-first-falling-SCLK setup is " &
                               time'image(now - cs_fall_time_v) &
                               "; ADC121S101 requires at least 10 ns"
                            severity error;
                        local_setup_err_v := local_setup_err_v + 1;
                    end if;
                end if;

                if edge_count_v = 16 then
                    adc_drive <= transport 'Z' after C_T_DIS;
                elsif extra_leading_v then
                    -- After edges 1,2,3: Z2,Z1,Z0. After edges 4..15:
                    -- DB11..DB0. A pre-falling-edge receiver obtains
                    -- [optional-zero,Z2,Z1,Z0,DB11..DB0].
                    if edge_count_v <= 3 then
                        next_bit_v := '0';
                    elsif edge_count_v <= 15 then
                        next_bit_v := code_v(15 - edge_count_v);
                    else
                        next_bit_v := '0';
                    end if;
                    adc_drive <= transport next_bit_v after C_T_ACC;
                else
                    -- No optional fourth zero: Z2 is already present at edge 1;
                    -- advance to Z1/Z0 and then DB11..DB0 one edge earlier.
                    if edge_count_v <= 2 then
                        next_bit_v := '0';
                    elsif edge_count_v <= 14 then
                        next_bit_v := code_v(14 - edge_count_v);
                    else
                        next_bit_v := code_v(0);
                    end if;
                    adc_drive <= transport next_bit_v after C_T_ACC;
                end if;
            end if;
        end if;
    end process;

    uart_checker_p : process
        procedure receive_byte(variable result_v : out natural) is
            variable byte_v : natural := 0;
        begin
            wait until falling_edge(txd_out);
            wait for C_UART_BIT + C_UART_BIT / 2;
            for bit_i in 0 to 7 loop
                assert txd_out = '0' or txd_out = '1'
                    report "UART data bit is not binary" severity error;
                if txd_out = '1' then
                    byte_v := byte_v + (2 ** bit_i);
                end if;
                wait for C_UART_BIT;
            end loop;
            assert txd_out = '1'
                report "UART stop bit is not high" severity error;
            result_v := byte_v;
        end procedure;

        variable low_byte_v     : natural := 0;
        variable high_byte_v    : natural := 0;
        variable unsigned_v     : natural := 0;
        variable signed_v       : integer := 0;
        variable local_errors_v : natural := 0;
    begin
        wait until reset_in = '0' and start_in = '1';

        for sample_i in C_EXPECTED'range loop
            receive_byte(low_byte_v);
            receive_byte(high_byte_v);
            unsigned_v := high_byte_v * 256 + low_byte_v;
            if unsigned_v >= 32768 then
                signed_v := integer(unsigned_v) - 65536;
            else
                signed_v := integer(unsigned_v);
            end if;

            report "UART sample " & integer'image(sample_i) &
                   ": raw ADC=0x" & to_hstring(std_logic_vector(to_unsigned(C_RAW_CODES(sample_i), 12))) &
                   ", word=0x" & to_hstring(std_logic_vector(to_unsigned(unsigned_v, 16))) &
                   ", signed=" & integer'image(signed_v)
                severity note;

            if signed_v /= C_EXPECTED(sample_i) then
                report "UART mismatch at sample " & integer'image(sample_i) &
                       ": expected " & integer'image(C_EXPECTED(sample_i)) &
                       ", received " & integer'image(signed_v)
                    severity error;
                local_errors_v := local_errors_v + 1;
            end if;
            uart_word_count  <= sample_i + 1;
            uart_error_count <= local_errors_v;
        end loop;

        wait for 1 us;
        assert frame_error_count = 0
            report integer'image(frame_error_count) & " malformed ADC frame(s) observed"
            severity failure;
        assert setup_error_count = 0
            report integer'image(setup_error_count) & " CS setup violation(s) observed"
            severity failure;
        assert local_errors_v = 0
            report integer'image(local_errors_v) & " UART value mismatch(es) observed"
            severity failure;

        report "PASS: six 32-frame groups retained DB11..DB0, centered correctly, and used 16 falling edges/frame"
            severity note;
        stop(0);
        wait;
    end process;

    timeout_p : process
    begin
        wait for 5 ms;
        assert uart_word_count = C_EXPECTED'length
            report "TIMEOUT: expected six UART words, received " & integer'image(uart_word_count)
            severity failure;
        stop(1);
        wait;
    end process;
end architecture;
