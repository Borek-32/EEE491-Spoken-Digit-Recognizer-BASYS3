library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity LOGMEL is
	Port (
	reset_in		: in  std_logic;
	clock_in	: in  std_logic;
	start_in	: in  std_logic;
	ready_out	: out std_logic;
	mel_addr_out: out std_logic_vector(4 downto 0);
	mel_data_in	: in  std_logic_vector(31 downto 0);
	mem_addr_in	: in  std_logic_vector(4 downto 0);
	mem_data_out: out std_logic_vector(31 downto 0)
	);
end entity;

architecture Behavioral of LOGMEL is

	component blk_mem_gen_log2_piecewise_rom is
		port (
			clka	: in  std_logic;
			addra	: in  std_logic_vector(11 downto 0);
			douta	: out std_logic_vector(31 downto 0)
		);
	end component;

	component mult_gen_4 is
		port (
			CLK	: in  std_logic;
			A	: in  std_logic_vector(11 downto 0);
			B	: in  std_logic_vector(7 downto 0);
			P	: out std_logic_vector(19 downto 0)
		);
	end component;

	component blk_mem_gen_logmel_buf is
		port (
			clka	: in  std_logic;
			wea		: in  std_logic_vector(0 downto 0);
			addra	: in  std_logic_vector(4 downto 0);
			dina	: in  std_logic_vector(31 downto 0);
			clkb	: in  std_logic;
			addrb	: in  std_logic_vector(4 downto 0);
			doutb	: out std_logic_vector(31 downto 0)
		);
	end component;

	constant MEL_READ_DELAY	: integer := 4;
	constant ROM_READ_DELAY	: integer := 2;
	constant MULT_WAIT		: integer := 4;

	type fsm is (idle, set_mel_addr, wait_mel, set_rom_addr, wait_rom, load_mult, wait_mult, write_ram, write_wait, done);
	signal state : fsm := idle;

	signal bin_idx		: integer range 0 to 31 := 0;
	signal cnt			: integer range 0 to 7 := 0;
	signal mel_addr		: std_logic_vector(4 downto 0) := (others => '0');

	signal rom_addr		: std_logic_vector(11 downto 0) := (others => '0');
	signal rom_data		: std_logic_vector(31 downto 0) := (others => '0');
	signal residual_reg	: std_logic_vector(7 downto 0) := (others => '0');
	signal exponent_reg	: unsigned(4 downto 0) := (others => '0');
	signal base_reg		: unsigned(19 downto 0) := (others => '0');

	signal mult_a		: std_logic_vector(11 downto 0) := (others => '0');
	signal mult_b		: std_logic_vector(7 downto 0) := (others => '0');
	signal product		: std_logic_vector(19 downto 0) := (others => '0');

	signal ram_we		: std_logic_vector(0 downto 0) := "0";
	signal ram_addr		: std_logic_vector(4 downto 0) := (others => '0');
	signal ram_data		: std_logic_vector(31 downto 0) := (others => '0');

begin

	mel_addr_out <= mel_addr;

	log2_rom : blk_mem_gen_log2_piecewise_rom
		port map (
			clka  => clock_in,
			addra => rom_addr,
			douta => rom_data
		);

	interp_mult : mult_gen_4
		port map (
			CLK => clock_in,
			A   => mult_a,
			B   => mult_b,
			P   => product
		);

	logmel_ram : blk_mem_gen_logmel_buf
		port map (
			clka  => clock_in,
			wea   => ram_we,
			addra => ram_addr,
			dina  => ram_data,
			clkb  => clock_in,
			addrb => mem_addr_in,
			doutb => mem_data_out
		);

	process(clock_in)
		variable x_v		: unsigned(31 downto 0);
		variable norm_v		: unsigned(63 downto 0);
		variable exp_v		: integer range 0 to 31;
		variable interp_v	: unsigned(31 downto 0);
		variable log_v		: unsigned(31 downto 0);
	begin
		if rising_edge(clock_in) then
			if reset_in = '1' then
				state <= idle;
				ready_out <= '1';
				bin_idx <= 0;
				cnt <= 0;
				mel_addr <= (others => '0');
				rom_addr <= (others => '0');
				residual_reg <= (others => '0');
				exponent_reg <= (others => '0');
				base_reg <= (others => '0');
				mult_a <= (others => '0');
				mult_b <= (others => '0');
				ram_we <= "0";
				ram_addr <= (others => '0');
				ram_data <= (others => '0');
			else
				case state is

					when idle =>
						ram_we <= "0";
						if start_in = '1' then
							ready_out <= '0';
							bin_idx <= 0;
							cnt <= 0;
							state <= set_mel_addr;
						else
							ready_out <= '1';
						end if;

					when set_mel_addr =>
						ram_we <= "0";
						mel_addr <= std_logic_vector(to_unsigned(bin_idx, 5));
						cnt <= 0;
						state <= wait_mel;

					when wait_mel =>
						if cnt = MEL_READ_DELAY then
							cnt <= 0;
							state <= set_rom_addr;
						else
							cnt <= cnt + 1;
						end if;

					when set_rom_addr =>
						x_v := unsigned(mel_data_in);
						if x_v = to_unsigned(0, 32) then
							x_v := to_unsigned(1, 32);
						end if;

						exp_v := 0;
						for i in 31 downto 0 loop
							if x_v(i) = '1' then
								exp_v := i;
								exit;
							end if;
						end loop;

						norm_v := shift_left(resize(x_v, 64), 31 - exp_v);
						rom_addr <= std_logic_vector(norm_v(30 downto 19));
						residual_reg <= std_logic_vector(norm_v(18 downto 11));
						exponent_reg <= to_unsigned(exp_v, 5);
						cnt <= 0;
						state <= wait_rom;

					when wait_rom =>
						if cnt = ROM_READ_DELAY then
							cnt <= 0;
							state <= load_mult;
						else
							cnt <= cnt + 1;
						end if;

					when load_mult =>
						base_reg <= unsigned(rom_data(31 downto 12));
						mult_a <= rom_data(11 downto 0);
						mult_b <= residual_reg;
						cnt <= 0;
						state <= wait_mult;

					when wait_mult =>
						if cnt = MULT_WAIT then
							cnt <= 0;
							state <= write_ram;
						else
							cnt <= cnt + 1;
						end if;

					when write_ram =>
						interp_v := resize(base_reg, 32) + resize(shift_right(unsigned(product), 8), 32);
						log_v := shift_left(resize(exponent_reg, 32), 20) + interp_v;
						ram_addr <= std_logic_vector(to_unsigned(bin_idx, 5));
						ram_data <= std_logic_vector(log_v);
						ram_we <= "1";
						state <= write_wait;

					when write_wait =>
						ram_we <= "0";
						if bin_idx = 31 then
							state <= done;
						else
							bin_idx <= bin_idx + 1;
							state <= set_mel_addr;
						end if;

					when done =>
						ready_out <= '1';
						state <= idle;

				end case;
			end if;
		end if;
	end process;

end architecture;
