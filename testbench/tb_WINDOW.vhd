library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

entity tb_WINDOW is
end tb_WINDOW;

architecture Behavioral of tb_WINDOW is

    component WINDOW is
        Port (
            reset_in      : in  std_logic;
            clock_in      : in  std_logic;
            frame_addr_in : in  std_logic_vector(13 downto 0);
            adc_addr_out  : out std_logic_vector(13 downto 0);
            adc_data_in   : in  std_logic_vector(11 downto 0);
            mem_addr_in   : in  std_logic_vector(8 downto 0);
            mem_data_out  : out std_logic_vector(19 downto 0);
            start_in      : in  std_logic;
            ready_out     : out std_logic
        );
    end component;

    signal reset_in      : std_logic := '1';
    signal clock_in      : std_logic := '0';
    signal frame_addr_in : std_logic_vector(13 downto 0) := (others => '0');
    signal adc_addr_out  : std_logic_vector(13 downto 0);
    signal adc_data_in   : std_logic_vector(11 downto 0) := (others => '0');
    signal mem_addr_in   : std_logic_vector(8 downto 0)  := (others => '0');
    signal mem_data_out  : std_logic_vector(19 downto 0);
    signal start_in      : std_logic := '0';
    signal ready_out     : std_logic;
    signal sample_start  : integer := -256;
    signal sample_step   : integer := 1;
    signal sample_count  : integer := 512;

begin

    uut : WINDOW
        port map (
            reset_in      => reset_in,
            clock_in      => clock_in,
            frame_addr_in => frame_addr_in,
            adc_addr_out  => adc_addr_out,
            adc_data_in   => adc_data_in,
            mem_addr_in   => mem_addr_in,
            mem_data_out  => mem_data_out,
            start_in      => start_in,
            ready_out     => ready_out
        );

    clock_process : process
    begin
        while true loop
            clock_in <= '0';
            wait for 5 ns;
            clock_in <= '1';
            wait for 5 ns;
        end loop;
    end process;

    adc_model : process(adc_addr_out, sample_start, sample_step)
        variable sample_i : integer;
    begin
        sample_i := sample_start + to_integer(unsigned(adc_addr_out)) * sample_step;
        adc_data_in <= std_logic_vector(to_signed(sample_i, 12));
    end process;

    stim_proc : process
        file ref_file  : text open read_mode is "../../../../verification/ref_data/tb_window_ref.txt";
        file dump_file : text open write_mode is "../../../../verification/tb_output/tb_window_output.txt";
        variable L     : line;
        variable val_i : integer;
        variable sample_start_v : integer;
        variable sample_step_v  : integer;
        variable sample_count_v : integer;
    begin
        frame_addr_in <= (others => '0');
        mem_addr_in   <= (others => '0');
        start_in      <= '0';
        reset_in      <= '1';

        readline(ref_file, L);
        read(L, sample_start_v);
        read(L, sample_step_v);
        read(L, sample_count_v);
        sample_start <= sample_start_v;
        sample_step <= sample_step_v;
        sample_count <= sample_count_v;

        wait for 30 ns;
        wait until rising_edge(clock_in);
        reset_in <= '0';

        wait until rising_edge(clock_in);
        start_in <= '1';

        wait until rising_edge(clock_in);
        start_in <= '0';

        wait until ready_out = '1';
        wait until rising_edge(clock_in);

        for i in 0 to sample_count_v - 1 loop
            mem_addr_in <= std_logic_vector(to_unsigned(i, 9));

            wait until rising_edge(clock_in);
            wait until rising_edge(clock_in);

            val_i := to_integer(unsigned(mem_data_out));
            write(L, i);
            write(L, string'(" "));
            write(L, val_i);
            writeline(dump_file, L);
        end loop;

        finish;
    end process;

end Behavioral;
