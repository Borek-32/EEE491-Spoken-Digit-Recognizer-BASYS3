library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity seven_segment is
PORT(
    in1    : in  std_logic_vector(3 downto 0);
    in2    : in  std_logic_vector(3 downto 0);
    in3    : in  std_logic_vector(3 downto 0);
    in4    : in  std_logic_vector(3 downto 0);
    an     : out std_logic_vector(3 downto 0);
    a_to_g : out std_logic_vector(6 downto 0);
    clk    : in  std_logic
);
end seven_segment;

architecture Behavioral of seven_segment is

signal switch        : std_logic_vector(15 downto 0);
signal clk_div       : unsigned(19 downto 0) := (others => '0');

function hex_to_7seg(digit : std_logic_vector(3 downto 0))
return std_logic_vector is
begin
    -- Output vector is a_to_g(6 downto 0).
    -- According to the XDC: a_to_g(0)=A, a_to_g(1)=B, ..., a_to_g(6)=G.
    -- Therefore the returned string is ordered as G F E D C B A.
    -- Basys-style seven-segment outputs are active-low: 0 = segment ON.
    case digit is
        when "0000" => return "1000000"; -- 0
        when "0001" => return "1111001"; -- 1
        when "0010" => return "0100100"; -- 2
        when "0011" => return "0110000"; -- 3
        when "0100" => return "0011001"; -- 4
        when "0101" => return "0010010"; -- 5
        when "0110" => return "0000010"; -- 6
        when "0111" => return "1111000"; -- 7
        when "1000" => return "0000000"; -- 8
        when "1001" => return "0010000"; -- 9
        when "1010" => return "0101111"; -- r, record mode
        when "1011" => return "0000011"; -- b
        when "1100" => return "1000110"; -- C, compare mode
        when "1101" => return "0100001"; -- d
        when "1110" => return "0000110"; -- E
        when "1111" => return "0001110"; -- F
        when others => return "1111111"; -- all segments off
    end case;
end function;

begin

switch <= in1 & in2 & in3 & in4;

process(clk)
begin
    if rising_edge(clk) then
        clk_div <= clk_div + 1;

        case clk_div(16 downto 15) is
            when "00" =>
                an <= "1110";                    -- AN0, rightmost digit
                a_to_g <= hex_to_7seg(switch(3 downto 0));

            when "01" =>
                an <= "1101";                    -- AN1, middle-right digit
                a_to_g <= hex_to_7seg(switch(7 downto 4));

            when "10" =>
                an <= "1011";                    -- AN2, middle-left digit
                a_to_g <= hex_to_7seg(switch(11 downto 8));

            when others =>
                an <= "0111";                    -- AN3, leftmost digit
                a_to_g <= hex_to_7seg(switch(15 downto 12));
        end case;
    end if;
end process;

end Behavioral;
