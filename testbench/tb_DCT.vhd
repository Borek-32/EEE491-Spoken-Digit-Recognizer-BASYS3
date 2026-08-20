library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

entity tb_DCT is
end tb_DCT;

architecture Behavioral of tb_DCT is

	constant CLK_PERIOD : time := 10 ns;

	component DCT is
		Port (
		reset_in : in std_logic;
		clock_in : in std_logic;
		start_in : in std_logic;
		ready_out : out std_logic;
		logmel_addr_out : out std_logic_vector(4 downto 0);
		logmel_data_in : in std_logic_vector(31 downto 0);
		mem_addr_in : in std_logic_vector(2 downto 0);
		mem_data_out : out std_logic_vector(15 downto 0)
		);
	end component;

	type mel_mem_t is array (0 to 31) of std_logic_vector(31 downto 0);

	function init_mel_mem return mel_mem_t is
		variable mem : mel_mem_t;
		variable val : integer;
	begin
		for i in 0 to 31 loop
			val := ((i + 1) * 100) + ((i * i + 7) mod 23);
			mem(i) := std_logic_vector(to_unsigned(val, 32));
		end loop;
		return mem;
	end function;

	signal clock_in : std_logic := '0';
	signal reset_in : std_logic := '1';
	signal start_in : std_logic := '0';
	signal ready_out : std_logic;

	signal mel_addr_out : std_logic_vector(4 downto 0);
	signal mel_data_in : std_logic_vector(31 downto 0) := (others => '0');
	signal mem_addr_in : std_logic_vector(2 downto 0) := (others => '0');
	signal mem_data_out : std_logic_vector(15 downto 0);

	signal mel_mem : mel_mem_t := (others => (others => '0'));
	signal mel_addr_mux : std_logic_vector(4 downto 0) := (others => '0');
	signal mel_addr_ram : std_logic_vector(4 downto 0) := (others => '0');
	signal dct_addr_req : std_logic_vector(2 downto 0) := (others => '0');

begin

	uut : DCT
		port map (
			reset_in => reset_in,
			clock_in => clock_in,
			start_in => start_in,
			ready_out => ready_out,
			logmel_addr_out => mel_addr_out,
			logmel_data_in => mel_data_in,
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

	-- Model the real path: DCT address -> registered top mux -> two RAM clocks.
	mel_ram_model : process(clock_in)
	begin
		if rising_edge(clock_in) then
			mel_addr_mux <= mel_addr_out;
			mel_addr_ram <= mel_addr_mux;
			mel_data_in <= mel_mem(to_integer(unsigned(mel_addr_ram)));
		end if;
	end process;

	-- Model the registered top-level mux before the DCT RAM read port.
	dct_addr_model : process(clock_in)
	begin
		if rising_edge(clock_in) then
			mem_addr_in <= dct_addr_req;
		end if;
	end process;

	stim_proc : process
		file ref_file : text open read_mode is "../../../../verification/ref_data/tb_dct_ref.txt";
		file dump_file : text open write_mode is "../../../../verification/tb_output/tb_dct_output.txt";
		variable L : line;
		variable val_i : integer;
	begin
		reset_in <= '1';
		start_in <= '0';
		dct_addr_req <= (others => '0');

		for i in 0 to 31 loop
			readline(ref_file, L);
			read(L, val_i);
			mel_mem(i) <= std_logic_vector(to_unsigned(val_i, 32));
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

		for i in 0 to 7 loop
			dct_addr_req <= std_logic_vector(to_unsigned(i, 3));

			wait until rising_edge(clock_in);
			wait until rising_edge(clock_in);
			wait until rising_edge(clock_in);
			wait until rising_edge(clock_in);
			wait for 1 ns;

			val_i := to_integer(signed(mem_data_out));
			write(L, i);
			write(L, string'(" "));
			write(L, val_i);
			writeline(dump_file, L);
		end loop;

		wait for 100 ns;
		finish;
	end process;

end Behavioral;
