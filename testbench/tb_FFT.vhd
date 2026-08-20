library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

entity tb_FFT is
end entity;

architecture sim of tb_FFT is
	constant CLK_PERIOD : time := 10 ns;
	constant FFT_LENGTH : integer := 512;
	type sample_mem_t is array (0 to FFT_LENGTH - 1) of std_logic_vector(19 downto 0);

	signal clock_in : std_logic := '0';
	signal reset_in : std_logic := '1';
	signal start_in : std_logic := '0';
	signal ready_out : std_logic;
	signal mem_addr_in : std_logic_vector(7 downto 0) := (others => '0');
	signal mem_data_out : std_logic_vector(31 downto 0);
	signal window_addr_out : std_logic_vector(8 downto 0);
	signal window_data_in : std_logic_vector(19 downto 0) := (others => '0');
	signal sample_mem : sample_mem_t := (others => (others => '0'));

begin
	clock_in <= not clock_in after CLK_PERIOD / 2;

	dut : entity work.FFT
		port map (
			clock_in => clock_in,
			reset_in => reset_in,
			ready_out => ready_out,
			start_in => start_in,
			mem_addr_in => mem_addr_in,
			mem_data_out => mem_data_out,
			window_addr_out => window_addr_out,
			window_data_in => window_data_in
		);

	-- Match blk_mem_gen_1 port B: the addressed WINDOW sample appears after a
	-- rising clock edge, rather than changing combinationally with the address.
	window_model : process(clock_in)
	begin
		if rising_edge(clock_in) then
			window_data_in <= sample_mem(to_integer(unsigned(window_addr_out)));
		end if;
	end process;

	stim : process
		file ref_file : text open read_mode is "../../../../verification/ref_data/tb_fft_wrapper_ref.txt";
		file dump_file : text open write_mode is "../../../../verification/tb_output/tb_fft_wrapper_output.txt";
		variable L : line;
		variable sample_period_x10us_v : integer;
		variable tone_hz_v : integer;
		variable amplitude_v : integer;
		variable fft_length_v : integer;
		variable sample_v : integer;
		variable val_i : integer;
		variable expected_peak_addr_v : integer;
		variable peak_addr_v : integer := 0;
		variable peak_value_v : integer := -1;
	begin
		readline(ref_file, L);
		read(L, sample_period_x10us_v);
		read(L, tone_hz_v);
		read(L, amplitude_v);
		read(L, fft_length_v);
		for i in 0 to FFT_LENGTH - 1 loop
			readline(ref_file, L);
			read(L, sample_v);
			sample_mem(i) <= std_logic_vector(to_signed(sample_v, 20));
		end loop;
		wait for 1 ns;

		reset_in <= '1';
		start_in <= '0';
		wait for 100 ns;
		wait until rising_edge(clock_in);
		reset_in <= '0';
		wait until rising_edge(clock_in);

		start_in <= '1';
		wait until rising_edge(clock_in);
		start_in <= '0';

		wait until ready_out = '0';
		wait until ready_out = '1';
		wait until rising_edge(clock_in);

		for i in 0 to 255 loop
			mem_addr_in <= std_logic_vector(to_unsigned(i, 8));
			wait until rising_edge(clock_in);
			wait until rising_edge(clock_in);
			wait for 1 ns;
			val_i := to_integer(unsigned(mem_data_out));
			if val_i > peak_value_v then
				peak_value_v := val_i;
				peak_addr_v := i;
			end if;
			write(L, i);
			write(L, string'(" "));
			write(L, val_i);
			writeline(dump_file, L);
		end loop;

		expected_peak_addr_v := (tone_hz_v * fft_length_v * sample_period_x10us_v) / 10000000;
		assert peak_addr_v = expected_peak_addr_v
			report "FFT peak address mismatch: expected bin " & integer'image(expected_peak_addr_v) &
				", observed address " & integer'image(peak_addr_v)
			severity failure;
		report "tb_FFT PASS: peak at bin " & integer'image(peak_addr_v) &
			", magnitude " & integer'image(peak_value_v)
			severity note;

		finish;
	end process;
end architecture;
