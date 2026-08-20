library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

entity tb_seven_segment is
end entity;

architecture sim of tb_seven_segment is
	constant CLK_PERIOD : time := 10 ns;

	signal clk    : std_logic := '0';
	signal in1    : std_logic_vector(3 downto 0) := (others => '0');
	signal in2    : std_logic_vector(3 downto 0) := (others => '0');
	signal in3    : std_logic_vector(3 downto 0) := (others => '0');
	signal in4    : std_logic_vector(3 downto 0) := (others => '0');
	signal an     : std_logic_vector(3 downto 0);
	signal a_to_g : std_logic_vector(6 downto 0);

	function phase_an(phase : integer) return std_logic_vector is
	begin
		case phase is
			when 0      => return "1110";
			when 1      => return "1101";
			when 2      => return "1011";
			when others => return "0111";
		end case;
	end function;

begin

	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.seven_segment
		port map (
			in1    => in1,
			in2    => in2,
			in3    => in3,
			in4    => in4,
			an     => an,
			a_to_g => a_to_g,
			clk    => clk
		);

	stim : process
		file ref_file : text open read_mode is "../../../../verification/ref_data/tb_seven_segment_ref.txt";
		file dump_file : text open write_mode is "../../../../verification/tb_output/tb_seven_segment_output.txt";
		variable L : line;
		variable phase_v : integer;
		variable digit_v : integer;
		variable an_i : integer;
		variable seg_i : integer;
		variable target_an : std_logic_vector(3 downto 0);
	begin
		while not endfile(ref_file) loop
			readline(ref_file, L);
			read(L, phase_v);
			read(L, digit_v);

			in1 <= std_logic_vector(to_unsigned((digit_v + 3) mod 16, 4));
			in2 <= std_logic_vector(to_unsigned((digit_v + 2) mod 16, 4));
			in3 <= std_logic_vector(to_unsigned((digit_v + 1) mod 16, 4));
			in4 <= std_logic_vector(to_unsigned(digit_v mod 16, 4));

			case phase_v is
				when 0 =>
					in4 <= std_logic_vector(to_unsigned(digit_v mod 16, 4));
				when 1 =>
					in3 <= std_logic_vector(to_unsigned(digit_v mod 16, 4));
				when 2 =>
					in2 <= std_logic_vector(to_unsigned(digit_v mod 16, 4));
				when others =>
					in1 <= std_logic_vector(to_unsigned(digit_v mod 16, 4));
			end case;

			target_an := phase_an(phase_v);
			wait until rising_edge(clk) and an = target_an;
			wait for 1 ns;

			an_i := to_integer(unsigned(an));
			seg_i := to_integer(unsigned(a_to_g));
			write(L, phase_v);
			write(L, string'(" "));
			write(L, digit_v);
			write(L, string'(" "));
			write(L, an_i);
			write(L, string'(" "));
			write(L, seg_i);
			writeline(dump_file, L);
		end loop;

		finish;
	end process;

end architecture;
