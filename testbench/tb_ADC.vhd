library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_ADC is
end tb_ADC;

architecture sim of tb_ADC is

    -- DUT inputs
    signal reset_in  : std_logic := '1';
    signal clock_in  : std_logic := '0';
    signal start_in  : std_logic := '0';
    signal addr_in   : std_logic_vector(13 downto 0) := (others => '0');
    signal spi_miso  : std_logic := '0';

    -- DUT outputs
    signal spi_clk   : std_logic;
    signal CS_out    : std_logic;
    signal data_out  : std_logic_vector(11 downto 0);
    signal done      : std_logic;
    signal ready_out : std_logic;

    -- TB-controlled "ADC output word" (repeated on SPI)
    signal adc_word_tb : std_logic_vector(11 downto 0) := x"7FF";

    constant CLK_PERIOD : time := 10 ns;   -- 100 MHz main clock (adjust if needed)
    constant MAX_SAMPLES : integer := 512;
    constant READ_BASE_ADDR : integer := 2047;
    type sample_mem_t is array (0 to MAX_SAMPLES - 1) of std_logic_vector(11 downto 0);
    signal sample_mem : sample_mem_t := (others => x"800");
    signal sample_total : integer := 1;
    signal group_total : integer := 1;

begin

    -- DUT
    uut : entity work.ADC
		Generic map ( 
			n_on => 10,
			n_off => 1,
			min_rec => 20,
			thr_on => 1000,
			thr_off => 200,
			no_detect => '1'
		)
        port map (
            reset_in   => reset_in,
            clock_in   => clock_in,
            start_in   => start_in,
            addr_in    => addr_in,
            spi_miso   => spi_miso,
            spi_clk    => spi_clk,
            CS_out     => CS_out,
            data_out   => data_out,
            done       => done,
            ready_out  => ready_out
        );

    -- Main clock
    clk_process : process
    begin
        while true loop
            clock_in <= '0';
            wait for CLK_PERIOD/2;
            clock_in <= '1';
            wait for CLK_PERIOD/2;
        end loop;
    end process;

    -- Basic reset/start stimulus + word switching
    stim_process : process
        file ref_file : text open read_mode is "../../../../verification/ref_data/tb_adc_spi_vad_ref.txt";
        file dump_file : text open write_mode is "../../../../verification/tb_output/tb_adc_spi_vad_output.txt";
        variable ref_line : line;
        variable dump_line : line;
        variable raw_sample : integer;
        variable repeat_count : integer;
        variable total_v : integer := 0;
        variable group_count_v : integer := 0;
        variable val_i : integer;
    begin
        while not endfile(ref_file) loop
            readline(ref_file, ref_line);
            read(ref_line, raw_sample);
            read(ref_line, repeat_count);
            for i in 1 to repeat_count loop
                if total_v < MAX_SAMPLES then
                    sample_mem(total_v) <= std_logic_vector(to_unsigned(raw_sample, 12));
                    total_v := total_v + 1;
                end if;
            end loop;
        end loop;
        group_count_v := total_v / 32;
        sample_total <= total_v;
        group_total <= group_count_v;
        wait for 1 ns;

        -- Defaults
        reset_in   <= '1';
        start_in   <= '0';
        addr_in    <= (others => '0');
        adc_word_tb <= x"7FF"; -- silence baseline (midscale)

        -- Reset
        wait for 200 ns;
        reset_in <= '0';

        -- Start pulse (change if your DUT expects level instead of pulse)
        wait for 200 ns;
        start_in <= '1';
        wait for CLK_PERIOD;
        start_in <= '0';

        wait for 8 ms;

        for i in 0 to group_count_v - 1 loop
            addr_in <= std_logic_vector(to_unsigned(READ_BASE_ADDR + i, 14));
            wait until rising_edge(clock_in);
            wait until rising_edge(clock_in);
            wait until rising_edge(clock_in);
            val_i := to_integer(unsigned(data_out));
            write(dump_line, i);
            write(dump_line, string'(" "));
            write(dump_line, val_i);
            writeline(dump_file, dump_line);
        end loop;

        finish;
    end process;

    -- SPI slave model: repeatedly shifts adc_word_tb (MSB first) while CS is active
    -- Your DUT stores: data_buf(11 - bit_counter) <= spi_miso, so this matches MSB-first.
    spi_slave_model : process
        variable bit_idx : integer range 0 to 11 := 11;
        variable sample_idx : integer := 0;
        variable word_now : std_logic_vector(11 downto 0) := x"800";
        variable shifted_bits : integer := 0;
    begin
        spi_miso <= '0';

        loop
            wait until CS_out = '0';

            if sample_idx < sample_total then
                word_now := sample_mem(sample_idx);
            end if;
            adc_word_tb <= word_now;

            bit_idx := 11;
            shifted_bits := 0;
            spi_miso <= word_now(bit_idx);

            while CS_out = '0' loop
                wait until (falling_edge(spi_clk)) or (CS_out = '1');
                exit when CS_out = '1';

                shifted_bits := shifted_bits + 1;

                if bit_idx = 0 then
                    bit_idx := 11;
                else
                    bit_idx := bit_idx - 1;
                end if;

                spi_miso <= word_now(bit_idx);
            end loop;

            if shifted_bits >= 12 and sample_idx < sample_total - 1 then
                sample_idx := sample_idx + 1;
            end if;
        end loop;
    end process;

end architecture;
