library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

entity tb_debug is
end entity;

architecture Behavioral of tb_debug is

	constant CLK_PERIOD : time := 10 ns;
	constant BIT_PERIOD : time := 100 ns;

	signal reset_in                 : std_logic := '1';
	signal clock_in                 : std_logic := '0';
	signal start_in                 : std_logic := '0';
	signal frame_addr_in            : std_logic_vector(13 downto 0) := std_logic_vector(to_unsigned(64, 14));
	signal mode_record_in           : std_logic := '1';
	signal comp_digit_in            : std_logic_vector(3 downto 0) := x"5";
	signal comp_valid_in            : std_logic := '1';
	signal comp_record_in           : std_logic := '1';
	signal comp_digit_idx3_patch_in : std_logic := '0';

	signal adc_data_in    : std_logic_vector(11 downto 0);
	signal window_data_in : std_logic_vector(19 downto 0);
	signal fft_data_in    : std_logic_vector(31 downto 0);
	signal mel_data_in    : std_logic_vector(31 downto 0);
	signal logmel_data_in : std_logic_vector(31 downto 0);
	signal dct_data_in    : std_logic_vector(15 downto 0);

	signal txd_out         : std_logic;
	signal ready_out       : std_logic;
	signal active_out      : std_logic;
	signal adc_addr_out    : std_logic_vector(13 downto 0);
	signal window_addr_out : std_logic_vector(8 downto 0);
	signal fft_addr_out    : std_logic_vector(7 downto 0);
	signal mel_addr_out    : std_logic_vector(4 downto 0);
	signal logmel_addr_out : std_logic_vector(4 downto 0);
	signal dct_addr_out    : std_logic_vector(2 downto 0);

begin

	clock_in <= not clock_in after CLK_PERIOD / 2;

	adc_data_in <= std_logic_vector(to_unsigned(to_integer(unsigned(adc_addr_out(8 downto 0))), 12));
	window_data_in <= std_logic_vector(to_unsigned(16#20000# + to_integer(unsigned(window_addr_out)), 20));
	fft_data_in <= std_logic_vector(to_unsigned(16#30000000# + to_integer(unsigned(fft_addr_out)), 32));
	mel_data_in <= std_logic_vector(to_unsigned(16#40000000# + to_integer(unsigned(mel_addr_out)), 32));
	logmel_data_in <= std_logic_vector(to_unsigned(16#50000000# + to_integer(unsigned(logmel_addr_out)), 32));
	dct_data_in <= std_logic_vector(to_unsigned(16#6000# + to_integer(unsigned(dct_addr_out)), 16));

	dut : entity work.debug
		generic map (
			CLK_HZ           => 100000000,
			BAUD_RATE        => 10000000,
			READ_WAIT_CYCLES => 1
		)
		port map (
			reset_in                 => reset_in,
			clock_in                 => clock_in,
			start_in                 => start_in,
			frame_addr_in            => frame_addr_in,
			mode_record_in           => mode_record_in,
			comp_digit_in            => comp_digit_in,
			comp_valid_in            => comp_valid_in,
			comp_record_in           => comp_record_in,
			comp_digit_idx3_patch_in => comp_digit_idx3_patch_in,
			adc_data_in              => adc_data_in,
			window_data_in           => window_data_in,
			fft_data_in              => fft_data_in,
			mel_data_in              => mel_data_in,
			logmel_data_in           => logmel_data_in,
			dct_data_in              => dct_data_in,
			txd_out                  => txd_out,
			ready_out                => ready_out,
			active_out               => active_out,
			adc_addr_out             => adc_addr_out,
			window_addr_out          => window_addr_out,
			fft_addr_out             => fft_addr_out,
			mel_addr_out             => mel_addr_out,
			logmel_addr_out          => logmel_addr_out,
			dct_addr_out             => dct_addr_out
		);

	stimulus : process
		file ref_file : text open read_mode is "../../../../verification/ref_data/tb_debug_ref.txt";
		file uart_file : text open write_mode is "../../../../verification/tb_output/tb_debug_output.txt";
		variable word_v : std_logic_vector(31 downto 0);
		variable line_v : line;
		variable frame_addr_v : integer;
		variable mode_record_v : integer;
		variable comp_digit_v : integer;
		variable comp_valid_v : integer;
		variable comp_record_v : integer;
		variable comp_idx3_v : integer;
		constant WORD_COUNT : integer := 1362;

		procedure read_byte(variable byte_v : out std_logic_vector(7 downto 0)) is
		begin
			wait until txd_out = '0';
			wait for BIT_PERIOD + BIT_PERIOD / 2;
			for bit_i in 0 to 7 loop
				byte_v(bit_i) := txd_out;
				wait for BIT_PERIOD;
			end loop;
		end procedure;

		procedure read_word(variable word_out : inout std_logic_vector(31 downto 0)) is
			variable byte_v : std_logic_vector(7 downto 0);
			variable line_v : line;
		begin
			read_byte(byte_v);
			word_out(31 downto 24) := byte_v;
			read_byte(byte_v);
			word_out(23 downto 16) := byte_v;
			read_byte(byte_v);
			word_out(15 downto 8) := byte_v;
			read_byte(byte_v);
			word_out(7 downto 0) := byte_v;

			hwrite(line_v, word_out);
			writeline(uart_file, line_v);
		end procedure;

	begin
		readline(ref_file, line_v);
		read(line_v, frame_addr_v);
		read(line_v, mode_record_v);
		read(line_v, comp_digit_v);
		read(line_v, comp_valid_v);
		read(line_v, comp_record_v);
		read(line_v, comp_idx3_v);

		frame_addr_in <= std_logic_vector(to_unsigned(frame_addr_v, 14));
		if mode_record_v = 1 then
			mode_record_in <= '1';
		else
			mode_record_in <= '0';
		end if;
		comp_digit_in <= std_logic_vector(to_unsigned(comp_digit_v, 4));
		if comp_valid_v = 1 then
			comp_valid_in <= '1';
		else
			comp_valid_in <= '0';
		end if;
		if comp_record_v = 1 then
			comp_record_in <= '1';
		else
			comp_record_in <= '0';
		end if;
		if comp_idx3_v = 1 then
			comp_digit_idx3_patch_in <= '1';
		else
			comp_digit_idx3_patch_in <= '0';
		end if;

		wait for 100 ns;
		wait until rising_edge(clock_in);
		reset_in <= '0';
		wait until rising_edge(clock_in);

		start_in <= '1';
		wait until rising_edge(clock_in);
		start_in <= '0';

		for i in 1 to WORD_COUNT loop
			read_word(word_v);
		end loop;

		if ready_out /= '1' then
			wait until ready_out = '1';
		end if;
		wait for 1 us;

		finish;
	end process;

end Behavioral;
