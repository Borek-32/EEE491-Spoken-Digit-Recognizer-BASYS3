library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_top_module is
end tb_top_module;

architecture sim of tb_top_module is

	constant CLK_PERIOD : time := 10 ns;
	constant SIM_TIME   : time := 40 ms;

	signal reset_in  : std_logic := '1';
	signal clock_in  : std_logic := '0';
	signal start_in  : std_logic := '0';
	signal spi_miso  : std_logic := '0';
	signal spi_clk   : std_logic := '0';
	signal cs_out    : std_logic := '1';
	signal ready_out : std_logic := '0';
	signal adcdone   : std_logic := '0';
	signal adcbusy   : std_logic := '0';
	signal flush     : std_logic := '0';
	signal flush_done : std_logic;
	signal pmod      : std_logic := '0';
	signal txd_out   : std_logic;
	signal debug_enable_in : std_logic := '0';
	signal debug_led_out   : std_logic;
	signal switch    : std_logic := '0';
	signal digit_sw_in  : std_logic_vector(9 downto 0) := "0000000001";
	signal trial_inc_in : std_logic := '0';
	signal trial_dec_in : std_logic := '0';
	signal an        : std_logic_vector(3 downto 0);
	signal a_to_g    : std_logic_vector(6 downto 0);

	signal adc_word_tb   : std_logic_vector(11 downto 0) := x"800";
	signal adc_sample_tb : integer := 2048;
	signal spi_word_cnt  : integer := 0;

	function noise_sample(n : integer) return std_logic_vector is
		variable noise : integer := 0;
		variable sample : integer := 2048;
	begin
		case n mod 32 is
			when 0  => noise := -22;
			when 1  => noise := -16;
			when 2  => noise := -9;
			when 3  => noise := -3;
			when 4  => noise := 4;
			when 5  => noise := 11;
			when 6  => noise := 18;
			when 7  => noise := 25;
			when 8  => noise := 19;
			when 9  => noise := 13;
			when 10 => noise := 6;
			when 11 => noise := 1;
			when 12 => noise := -5;
			when 13 => noise := -12;
			when 14 => noise := -19;
			when 15 => noise := -26;
			when 16 => noise := -17;
			when 17 => noise := -8;
			when 18 => noise := 2;
			when 19 => noise := 10;
			when 20 => noise := 21;
			when 21 => noise := 29;
			when 22 => noise := 15;
			when 23 => noise := 7;
			when 24 => noise := -1;
			when 25 => noise := -10;
			when 26 => noise := -21;
			when 27 => noise := -30;
			when 28 => noise := -14;
			when 29 => noise := -6;
			when 30 => noise := 5;
			when others => noise := 16;
		end case;

		sample := 2048 + noise;
		return std_logic_vector(to_unsigned(sample, 12));
	end function;

begin

	uut : entity work.top_module
		port map (
			adcdone   => adcdone,
			adcbusy   => adcbusy,
			reset_in  => reset_in,
			clock_in  => clock_in,
			spi_clk   => spi_clk,
			spi_miso  => spi_miso,
			cs_out    => cs_out,
			start_in  => start_in,
			ready_out => ready_out,
			flush     => flush,
			flush_done => flush_done,
			pmod      => pmod,
			txd_out   => txd_out,
			debug_enable_in => debug_enable_in,
			debug_led_out   => debug_led_out,
			switch    => switch,
			digit_sw_in  => digit_sw_in,
			trial_inc_in => trial_inc_in,
			trial_dec_in => trial_dec_in,
			an        => an,
			a_to_g    => a_to_g
		);

	clk_process : process
	begin
		while true loop
			clock_in <= '0';
			wait for CLK_PERIOD / 2;
			clock_in <= '1';
			wait for CLK_PERIOD / 2;
		end loop;
	end process;

	stim_process : process
		file ref_file : text open read_mode is "../../../../verification/ref_data/tb_top_smoke_ref.txt";
		file dump_file : text open write_mode is "../../../../verification/tb_output/tb_top_smoke_output.txt";
		variable L : line;
		variable row_idx : integer := 0;
		variable switch_v : integer;
		variable selected_digit_v : integer;
		variable selected_trial_v : integer;
		variable debug_enable_v : integer;
		variable unused_v : integer;
		variable pmod_v : integer;
		variable debug_led_v : integer;
		variable digit_vec_v : std_logic_vector(9 downto 0);
		begin
			reset_in <= '1';
			start_in <= '0';
			flush <= '0';
			switch <= '0';
			debug_enable_in <= '0';
			digit_sw_in <= "0000000001";
			trial_inc_in <= '0';
			trial_dec_in <= '0';

			wait for 200 ns;
			reset_in <= '0';

		while not endfile(ref_file) loop
			readline(ref_file, L);
			read(L, switch_v);
			read(L, selected_digit_v);
			read(L, selected_trial_v);
			read(L, debug_enable_v);
			read(L, unused_v);
			read(L, unused_v);

			if switch_v = 1 then
				switch <= '1';
			else
				switch <= '0';
			end if;

			if debug_enable_v = 1 then
				debug_enable_in <= '1';
			else
				debug_enable_in <= '0';
			end if;

			digit_vec_v := (others => '0');
			if selected_digit_v >= 0 and selected_digit_v <= 9 then
				digit_vec_v(selected_digit_v) := '1';
			end if;
			digit_sw_in <= digit_vec_v;

			wait for 20 * CLK_PERIOD;

			if pmod = '1' then
				pmod_v := 1;
			else
				pmod_v := 0;
			end if;

			if debug_led_out = '1' then
				debug_led_v := 1;
			else
				debug_led_v := 0;
			end if;

			write(L, row_idx);
			write(L, string'(" "));
			write(L, switch_v);
			write(L, string'(" "));
			write(L, pmod_v);
			write(L, string'(" "));
			write(L, debug_enable_v);
			write(L, string'(" "));
			write(L, debug_led_v);
			writeline(dump_file, L);
			row_idx := row_idx + 1;
		end loop;

		finish;
	end process;

	spi_adc_model : process
		variable bit_idx : integer range 0 to 11 := 11;
		variable word_now : std_logic_vector(11 downto 0) := x"800";
		variable word_cnt : integer := 0;
	begin
		spi_miso <= '0';

		wait until cs_out = '0';

		word_now := noise_sample(word_cnt);
		word_cnt := word_cnt + 1;
		spi_word_cnt <= word_cnt;
		adc_word_tb <= word_now;
		adc_sample_tb <= to_integer(unsigned(word_now));

		bit_idx := 11;
		spi_miso <= word_now(bit_idx);

		while cs_out = '0' loop
			wait until falling_edge(spi_clk) or cs_out = '1';
			exit when cs_out = '1';

			if bit_idx > 0 then
				bit_idx := bit_idx - 1;
			end if;

			spi_miso <= word_now(bit_idx);
		end loop;
	end process;

end architecture;
