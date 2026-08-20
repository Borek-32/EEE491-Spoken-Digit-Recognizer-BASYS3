----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11.03.2026 15:11:36
-- Design Name: 
-- Module Name: WINDOW - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity WINDOW is
	Port (
	reset_in : in std_logic;
	clock_in : in std_logic;
	frame_addr_in : in std_logic_vector(13 downto 0);
	adc_addr_out : out std_logic_vector(13 downto 0);
	adc_data_in : in std_logic_vector(11 downto 0);
	mem_addr_in : in std_logic_vector(8 downto 0);
	mem_data_out : out std_logic_vector(19 downto 0);
	start_in : in std_logic;
	ready_out : out std_logic
);
end entity;

architecture Behavioral of WINDOW is

	
	component blk_mem_gen_1 is 
		port (
			clka : in std_logic;
			wea : in std_logic_vector(0 downto 0);
			addra : in std_logic_vector(8 downto 0);
			dina : in std_logic_vector(19 downto 0);
			clkb : in std_logic;
			addrb : in std_logic_vector(8 downto 0);
			doutb : out std_logic_vector(19 downto 0)
			);
	end component;
	
	component blk_mem_gen_0 is 
		port ( 
			clka : in std_logic;
			addra : in std_logic_vector(8 downto 0);
			douta : out std_logic_vector(7 downto 0);
			ena : in std_logic
			); 
	end component;
	
	component mult_gen_0 is
		port ( 
			clk : in std_logic;
			A : in std_logic_vector(11 downto 0);
			B : in std_logic_vector(7 downto 0);
			P : out std_logic_vector(19 downto 0)
			);
	end component;
			
	signal idx1 : integer range 0 to 511:= 0; -- window/rom/ram
	signal idx2 : integer range 0 to 16383:= 0; -- adc
	signal caddr : std_logic_vector(8 downto 0);
	signal coeff : std_logic_vector(7 downto 0);
	signal ram_addr : std_logic_vector(8 downto 0);
	signal hann_out1 : std_logic_vector(19 downto 0);
	signal hann_out2 : std_logic_vector(19 downto 0);
	signal enable_write : std_logic_vector(0 downto 0) := "0";
	
	
	type fsm is (idle, readr, wait1, wait2, wait3, wait4, writer, write_ram, flush_last, done);
	signal state : fsm := idle;
	
	
	
begin

mul: mult_gen_0 port map (
		CLK => clock_in,
		A => adc_data_in,
		B => coeff,
		P => hann_out1
		);
		
rom: blk_mem_gen_0 port map (
	clka => clock_in,
	addra => caddr,
	douta => coeff,
	ena => '1'
	);

	ram: blk_mem_gen_1 port map (
	clka => clock_in,
	wea => enable_write,
	addra => ram_addr,
	dina => hann_out2,
	clkb => clock_in,
	addrb => mem_addr_in,
	doutb => mem_data_out
	);

idx2 <= to_integer(unsigned(frame_addr_in));
adc_addr_out <= std_logic_vector(to_unsigned((idx1 + idx2),14));
caddr <= std_logic_vector(to_unsigned(idx1,9));

process(clock_in) begin
	if rising_edge(clock_in) then 
		if reset_in = '1' then
			state <= idle;
			ready_out <= '1';
			enable_write <= "0";
			idx1 <= 0;
			ram_addr <= (others => '0');
			hann_out2 <= (others => '0');
		else
			case state is 
				when idle =>
					if start_in = '1' then
						ready_out <= '0';
						enable_write <= "0";
						idx1 <= 0;
						ram_addr <= (others => '0');
						hann_out2 <= (others => '0');
						state <= readr;
					else
						ready_out <= '1';
						enable_write <= "0";
						idx1 <= 0;
					end if;
					
				when readr =>
					enable_write <= "0";
					state <= wait1;

				when wait1 =>
					state <= wait2;

				when wait2 =>
					state <= wait3;

				when wait3 =>
					state <= wait4;

				when wait4 =>
					state <= writer;
					
					when writer =>
						-- The synchronous coefficient ROM plus the multiplier pipeline
						-- returns sample idx1-1 here.  idx1=0 is the priming pass;
						-- suppress its former wrapped write to address 511.
						if idx1 = 0 then
							enable_write <= "0";
							state <= write_ram;
						else
							ram_addr <= std_logic_vector(to_unsigned(idx1-1, 9));
							hann_out2 <= hann_out1;
							enable_write <= "1";
							if idx1 = 511 then
								state <= flush_last;
							else
								state <= write_ram;
							end if;
						end if;

				when write_ram =>
					enable_write <= "0";
						idx1 <= idx1 + 1;
						state <= readr;

					when flush_last =>
						-- One extra cycle commits the final idx1=511 product to
						-- address 511 instead of relying on the zero Hann endpoint.
						ram_addr <= std_logic_vector(to_unsigned(511, 9));
						hann_out2 <= hann_out1;
						enable_write <= "1";
						state <= done;
					
				when done =>
					enable_write <= "0";
					ready_out <= '1';
					ram_addr <= (others => '0');
					state <= idle;
				
			end case;
		end if;
	end if;
end process;

-- synthesis translate_off
write_contract : process(clock_in)
	variable write_count : integer range 0 to 512 := 0;
begin
	if rising_edge(clock_in) then
		if reset_in = '1' then
			write_count := 0;
		elsif enable_write(0) = '1' then
			assert write_count < 512
				report "WINDOW issued more than 512 writes"
				severity failure;
			assert to_integer(unsigned(ram_addr)) = write_count
				report "WINDOW write address is not sequential"
				severity failure;
			write_count := write_count + 1;
			if state = done then
				assert write_count = 512
					report "WINDOW completed without writing all 512 addresses"
					severity failure;
			end if;
		elsif state = idle then
			write_count := 0;
		end if;
	end if;
end process;
-- synthesis translate_on

end Behavioral;
