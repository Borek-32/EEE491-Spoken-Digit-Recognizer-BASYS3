library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

entity tb_LOGMEL is
end entity;

architecture sim of tb_LOGMEL is
	constant CLK_PERIOD : time := 10 ns;
	type mel_mem_t is array (0 to 31) of std_logic_vector(31 downto 0);

	signal clock_in : std_logic := '0';
	signal reset_in : std_logic := '1';
	signal start_in : std_logic := '0';
	signal ready_out : std_logic;
	signal mel_addr_out : std_logic_vector(4 downto 0);
	signal mel_data_in : std_logic_vector(31 downto 0) := (others => '0');
	signal mem_addr_in : std_logic_vector(4 downto 0) := (others => '0');
	signal mem_data_out : std_logic_vector(31 downto 0);
	signal mel_mem : mel_mem_t := (others => (others => '0'));
	signal mel_addr_pipe : std_logic_vector(4 downto 0) := (others => '0');

begin
	clock_in <= not clock_in after CLK_PERIOD / 2;

	dut : entity work.LOGMEL
		port map (
			reset_in => reset_in,
			clock_in => clock_in,
			start_in => start_in,
			ready_out => ready_out,
			mel_addr_out => mel_addr_out,
			mel_data_in => mel_data_in,
			mem_addr_in => mem_addr_in,
			mem_data_out => mem_data_out
		);

	mel_model : process(clock_in)
	begin
		if rising_edge(clock_in) then
			mel_addr_pipe <= mel_addr_out;
			mel_data_in <= mel_mem(to_integer(unsigned(mel_addr_pipe)));
		end if;
	end process;

	stim : process
		file ref_file : text open read_mode is "../../../../verification/ref_data/tb_logmel_ref.txt";
		file dump_file : text open write_mode is "../../../../verification/tb_output/tb_logmel_output.txt";
		variable L : line;
		variable val_i : integer;
	begin
		for i in 0 to 31 loop
			readline(ref_file, L);
			read(L, val_i);
			mel_mem(i) <= std_logic_vector(to_unsigned(val_i, 32));
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

		finish;
	end process;
end architecture;
