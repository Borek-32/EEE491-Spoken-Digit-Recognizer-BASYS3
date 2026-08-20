library ieee;
use ieee.std_logic_1164.all;

-- Simulation-only replacement for the generated 100 MHz -> 36 MHz clock
-- wizard used by PCB.vhd.
entity clk_wiz_0 is
    port (
        clk_in1  : in  std_logic;
        clk_out1 : out std_logic;
        locked   : out std_logic;
        reset    : in  std_logic
    );
end entity;

architecture sim of clk_wiz_0 is
    constant C_HALF_ADC_PERIOD : time := 13.888889 ns;
    signal adc_clock_i         : std_logic := '0';
begin
    clk_out1 <= adc_clock_i;
    locked   <= not reset;

    adc_clock_p : process
    begin
        wait for C_HALF_ADC_PERIOD;
        if reset = '1' then
            adc_clock_i <= '0';
        else
            adc_clock_i <= not adc_clock_i;
        end if;
    end process;

    assert clk_in1 = clk_in1 severity note;
end architecture;
