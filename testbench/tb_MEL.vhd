library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

entity tb_MEL is
end tb_MEL;

architecture Behavioral of tb_MEL is

	constant CLK_PERIOD : time := 10 ns;

	component MEL is
		Port (
		reset_in : in std_logic;
		clock_in : in std_logic;
		start_in : in std_logic;
		ready_out : out std_logic;
		
		fft_addr_out : out std_logic_vector(7 downto 0);
		fft_data_in : in std_logic_vector(31 downto 0);
		
		mem_addr_in : in std_logic_vector(4 downto 0);
		mem_data_out : out std_logic_vector(31 downto 0)
		);
	end component;

	type fft_mem_t is array (0 to 255) of std_logic_vector(31 downto 0);

	function init_fft_mem return fft_mem_t is
		variable mem : fft_mem_t;
		variable val : integer;
	begin
		for i in 0 to 255 loop
			-- Use a scaled ramp so every FFT bin is unique and MEL bin/address
			-- shifts show up clearly in the output dump.
			val := (i + 1) * 65536;
			mem(i) := std_logic_vector(to_unsigned(val, 32));
		end loop;
		return mem;
	end function;

	signal clock_in : std_logic := '0';
	signal reset_in : std_logic := '1';
	signal start_in : std_logic := '0';
	signal ready_out : std_logic;

	signal fft_addr_out : std_logic_vector(7 downto 0);
	signal fft_data_in : std_logic_vector(31 downto 0) := (others => '0');

	signal mem_addr_in : std_logic_vector(4 downto 0) := (others => '0');
	signal mem_data_out : std_logic_vector(31 downto 0);

	signal fft_mem : fft_mem_t := (others => (others => '0'));
	signal fft_addr_pipe : std_logic_vector(7 downto 0) := (others => '0');

begin

	uut : MEL
		port map (
			reset_in => reset_in,
			clock_in => clock_in,
			start_in => start_in,
			ready_out => ready_out,
			fft_addr_out => fft_addr_out,
			fft_data_in => fft_data_in,
			mem_addr_in => mem_addr_in,
			mem_data_out => mem_data_out
		);

	clk_gen : process
	begin
		while true loop
			clock_in <= '0';
			wait for CLK_PERIOD / 2;
			clock_in <= '1';
			wait for CLK_PERIOD / 2;
		end loop;
	end process;

	-- Model the real FFT read path:
	-- MEL address -> registered top-level mux -> registered FFT BRAM output.
	fft_ram_model : process(clock_in)
	begin
		if rising_edge(clock_in) then
			fft_addr_pipe <= fft_addr_out;
			fft_data_in <= fft_mem(to_integer(unsigned(fft_addr_pipe)));
		end if;
	end process;

	stim_proc : process
		file ref_file : text open read_mode is "../../../../verification/ref_data/tb_mel_ref.txt";
		file dump_file : text open write_mode is "../../../../verification/tb_output/tb_mel_output.txt";
		variable L : line;
		variable val_i : integer;
		variable start_bin_v : integer;
		variable bin_step_v : integer;
		variable bin_count_v : integer;
	begin
		reset_in <= '1';
		start_in <= '0';
		mem_addr_in <= (others => '0');

		readline(ref_file, L);
		read(L, start_bin_v);
		read(L, bin_step_v);
		read(L, bin_count_v);

		for i in 0 to bin_count_v - 1 loop
			fft_mem(i) <= std_logic_vector(to_unsigned(start_bin_v + i * bin_step_v, 32));
		end loop;
		wait for 1 ns;

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

		for i in 0 to 31 loop
			mem_addr_in <= std_logic_vector(to_unsigned(i, 5));

			wait until rising_edge(clock_in);
			wait until rising_edge(clock_in);
			wait for 1 ns;

			val_i := to_integer(unsigned(mem_data_out));
			write(L, i);
			write(L, string'(" "));
			write(L, val_i);
			writeline(dump_file, L);
		end loop;

		wait for 100 ns;
		finish;
	end process;

end Behavioral;
