library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MEL is
    Port (
        reset_in      : in  std_logic;
        clock_in      : in  std_logic;
        start_in      : in  std_logic;
        ready_out     : out std_logic;
        fft_addr_out  : out std_logic_vector(7 downto 0);
        fft_data_in   : in  std_logic_vector(31 downto 0);
        mem_addr_in   : in  std_logic_vector(4 downto 0);
        mem_data_out  : out std_logic_vector(31 downto 0)
    );
end entity;

architecture Behavioral of MEL is

    component blk_mem_gen_6 is
        port (
            clka  : in  std_logic;
            addra : in  std_logic_vector(12 downto 0);
            douta : out std_logic_vector(15 downto 0)
        );
    end component;
    component mult_gen_3 is
        port (
            CLK : in  std_logic;
            A   : in  std_logic_vector(31 downto 0);
            B   : in  std_logic_vector(15 downto 0);
            P   : out std_logic_vector(47 downto 0)
        );
    end component;
    component blk_mem_gen_5 is
        port (
            clka  : in  std_logic;
            wea   : in  std_logic_vector(0 downto 0);
            addra : in  std_logic_vector(4 downto 0);
            dina  : in  std_logic_vector(31 downto 0);
            clkb  : in  std_logic;
            addrb : in  std_logic_vector(4 downto 0);
            doutb : out std_logic_vector(31 downto 0)
        );
    end component;
    type fsm is (idle,start_filter,set_addr,load_mult,add,write_ram,write_wait,done);
    signal state : fsm := idle;

    signal filter_idx 	: integer range 0 to 31 := 0;
    signal bin_idx   	: integer range 0 to 255 := 0;
	signal cnt1 		: integer range 0 to 7 := 0;
    signal accumulator  : unsigned(63 downto 0) := (others => '0');
    signal ready        : std_logic := '1';
    signal fft_addr_reg   : std_logic_vector(7 downto 0) := (others => '0');
    signal coeff_addr     : std_logic_vector(12 downto 0) := (others => '0');
    signal coeff_data     : std_logic_vector(15 downto 0);
    signal mult_a         : std_logic_vector(31 downto 0) := (others => '0');
    signal mult_b         : std_logic_vector(15 downto 0) := (others => '0');
    signal product        : std_logic_vector(47 downto 0);
    signal ram_we         : std_logic_vector(0 downto 0) := "0";
    signal ram_write_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal ram_read_addr  : std_logic_vector(4 downto 0) := (others => '0');
    signal ram_data_in    : std_logic_vector(31 downto 0) := (others => '0');

begin

    ready_out <= ready;
    fft_addr_out <= fft_addr_reg;
    ram_read_addr <= mem_addr_in when (state = idle or state = done) else
                     std_logic_vector(to_unsigned((filter_idx + 1) mod 32, 5));

    coeff_rom : blk_mem_gen_6
        port map (
            clka  => clock_in,
            addra => coeff_addr,
            douta => coeff_data);
    multiplier : mult_gen_3
        port map (
            CLK => clock_in,
            A   => mult_a,
            B   => mult_b,
            P   => product);
    mel_ram : blk_mem_gen_5
        port map (
            clka  => clock_in,
            wea   => ram_we,
            addra => ram_write_addr,
            dina  => ram_data_in,
            clkb  => clock_in,
            addrb => ram_read_addr,
            doutb => mem_data_out);

    process(clock_in) begin
        if rising_edge(clock_in) then
            if reset_in = '1' then
                state          <= idle;
                ready          <= '1';
                filter_idx     <= 0;
                bin_idx        <= 0;
                fft_addr_reg   <= (others => '0');
                coeff_addr     <= (others => '0');
                mult_a         <= (others => '0');
                mult_b         <= (others => '0');
                accumulator    <= (others => '0');
                cnt1           <= 0;
                ram_we         <= "0";
                ram_write_addr <= (others => '0');
                ram_data_in    <= (others => '0');
            else
                case state is
                    when idle =>
                        ram_we <= "0";
                        if start_in = '1' then
                            ready       <= '0';
                            filter_idx  <= 0;
                            bin_idx     <= 0;
                            accumulator <= (others => '0');
                            cnt1        <= 0;
                            state       <= start_filter;
                        else
                            ready <= '1';
                        end if;

                    when start_filter =>
                        ram_we      <= "0";
                        bin_idx     <= 0;
                        accumulator <= (others => '0');
                        cnt1        <= 0;
                        state       <= set_addr;

					when set_addr =>
							if cnt1 = 4 then -- bram latency + top_module mux 
								cnt1 <= 0;
								state <= load_mult;
							else
								-- FFT bin k is stored at FFT RAM address k.  Hold that
									-- address through the combinational top-level mux and the
									-- registered BRAM response so P[k] is multiplied by H[filter_idx,k].
								fft_addr_reg <= std_logic_vector(to_unsigned(bin_idx, 8));
								coeff_addr   <= std_logic_vector(to_unsigned(filter_idx, 5)) &
														std_logic_vector(to_unsigned(bin_idx, 8));
								cnt1 <= cnt1 + 1;
						end if;
	
                    when load_mult =>
						if cnt1 = 4 then -- mult latency
							state <= add;
							cnt1 <= 0;
						else
							mult_a <= fft_data_in;
							mult_b <= coeff_data;
							cnt1 <= cnt1 + 1; 
						end if;


                    when add =>
                        accumulator <= accumulator + resize(unsigned(product), accumulator'length);
                        if bin_idx = 255 then -- bin check
                            state <= write_ram;
                        else
                            bin_idx <= bin_idx + 1;
                            state   <= set_addr;
                        end if;

                    when write_ram =>
                        ram_write_addr <= std_logic_vector(to_unsigned(filter_idx, 5));
                        ram_data_in    <= std_logic_vector(accumulator(47 downto 16));
                        ram_we         <= "1";
                        state          <= write_wait;

                    when write_wait =>
                        -- One logical MEL word is written in write_ram.  Drop
                        -- the enable here so the BRAM receives one write edge.
                        ram_we <= "0";
                        if filter_idx = 31 then -- mel filter
                            state <= done;
                        else
                            filter_idx  <= filter_idx + 1;
                            accumulator <= (others => '0');
                            bin_idx     <= 0;
                            state       <= start_filter;
                        end if;

                    when done =>
                        ram_we <= "0";
                        ready  <= '1';
                        if start_in = '0' then
                            state <= idle;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
