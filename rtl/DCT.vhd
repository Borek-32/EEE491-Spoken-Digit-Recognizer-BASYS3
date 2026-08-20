library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity DCT is
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
end entity;

architecture Behavioral of DCT is

	component blk_mem_gen_dct_cos is
		port (
			clka : in std_logic;
			addra : in std_logic_vector(7 downto 0);
			douta : out std_logic_vector(15 downto 0)
		);
	end component;

	component mult_gen_dct is
		port (
			CLK : in std_logic;
			A : in std_logic_vector(31 downto 0);
			B : in std_logic_vector(15 downto 0);
			P : out std_logic_vector(47 downto 0)
		);
	end component;

	component blk_mem_gen_dct_ram is
		port (
			clka : in std_logic;
			wea : in std_logic_vector(0 downto 0);
			addra : in std_logic_vector(2 downto 0);
			dina : in std_logic_vector(15 downto 0);
			clkb : in std_logic;
			addrb : in std_logic_vector(2 downto 0);
			doutb : out std_logic_vector(15 downto 0)
		);
	end component;

	type fsm is (idle,set_addr,load_mult,add,write_ram,write_wait,next_dct,done);
	signal state : fsm := idle;

	signal dct_idx : integer range 0 to 7 := 0;
	signal mel_idx : integer range 0 to 31 := 0;
	signal cnt1 	: integer range 0 to 7 := 0;

	signal mel_addr : std_logic_vector(4 downto 0) := (others => '0');
	signal cos_addr : std_logic_vector(7 downto 0) := (others => '0');
	signal cos_data : std_logic_vector(15 downto 0);

	signal mult_a : std_logic_vector(31 downto 0) := (others => '0');
	signal mult_b : std_logic_vector(15 downto 0) := (others => '0');
	signal product : std_logic_vector(47 downto 0);
	signal accumulator : signed(63 downto 0) := (others => '0');

	signal ram_we : std_logic_vector(0 downto 0) := "0";
	signal ram_addr : std_logic_vector(2 downto 0) := (others => '0');
	signal ram_data : std_logic_vector(15 downto 0) := (others => '0');

begin

	logmel_addr_out <= mel_addr;

	cos_rom : blk_mem_gen_dct_cos
		port map (
			clka => clock_in,
			addra => cos_addr,
			douta => cos_data
		);

	multiplier : mult_gen_dct
		port map (
			CLK => clock_in,
			A => mult_a,
			B => mult_b,
			P => product
		);

	ram_inst : blk_mem_gen_dct_ram
		port map (
			clka => clock_in,
			wea => ram_we,
			addra => ram_addr,
			dina => ram_data,
			clkb => clock_in,
			addrb => mem_addr_in,
			doutb => mem_data_out
		);

	process(clock_in)
		variable scaled_v : signed(63 downto 0);
	begin
		if rising_edge(clock_in) then
			if reset_in = '1' then
				state <= idle;
				ready_out <= '1';
				dct_idx <= 0;
				cnt1 <= 0;
				mel_idx <= 0;
				mel_addr <= (others => '0');
				cos_addr <= (others => '0');
				mult_a <= (others => '0');
				mult_b <= (others => '0');
				accumulator <= (others => '0');
				ram_we <= "0";
				ram_addr <= (others => '0');
				ram_data <= (others => '0');
			else
				case state is

					when idle =>
						ram_we <= "0";
						if start_in = '1' then
							ready_out <= '0';
							dct_idx <= 0;
							mel_idx <= 0;
							accumulator <= (others => '0');
							state <= set_addr;
						else
							ready_out <= '1';
							dct_idx <= 0;
							mel_idx <= 0;
							accumulator <= (others => '0');
						end if;

					when set_addr =>
						ram_we <= "0";
						mel_addr <= std_logic_vector(to_unsigned((mel_idx + 31) mod 32, 5));
						cos_addr <= std_logic_vector(to_unsigned((dct_idx * 32) + mel_idx, 8));
						state <= load_mult;

					when load_mult =>
						if cnt1 = 4 then
							state <= add;
							cnt1 <= 0;
						else 
							mult_a <= logmel_data_in;
							mult_b <= cos_data;
							cnt1 <= cnt1 + 1;
						end if;

					when add =>
						accumulator <= accumulator + resize(signed(product), accumulator'length);

						if mel_idx = 31 then
							state <= write_ram;
						else
							mel_idx <= mel_idx + 1;
							state <= set_addr;
						end if;

					when write_ram =>
						ram_addr <= std_logic_vector(to_unsigned(dct_idx, 3));
						if accumulator(accumulator'high) = '1' then
							scaled_v := shift_right(accumulator - to_signed(2**29, accumulator'length), 30);
						else
							scaled_v := shift_right(accumulator + to_signed(2**29, accumulator'length), 30);
						end if;
						ram_data <= std_logic_vector(resize(scaled_v, 16));
						ram_we <= "1";
						state <= write_wait;

					when write_wait =>
						ram_we <= "0";
						state <= next_dct;

					when next_dct =>
						if dct_idx = 7 then
							state <= done;
						else
							dct_idx <= dct_idx + 1;
							mel_idx <= 0;
							accumulator <= (others => '0');
							state <= set_addr;
						end if;

					when done =>
						ram_we <= "0";
						ready_out <= '1';
						state <= idle;

				end case;
			end if;
		end if;
	end process;

end architecture;
