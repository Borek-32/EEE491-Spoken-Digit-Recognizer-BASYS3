library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity PCB is
    Generic (
        clk_hz     : natural := 100000000;
        uart_baud  : natural := 921600;
        avg_shift  : natural := 5
    );
    Port (
        reset_in  : in  std_logic;
        clock_in  : in  std_logic;
        start_in  : in  std_logic;
        spi_miso  : in  std_logic;

        spi_clk   : out std_logic;
        cs_out    : out std_logic;
        txd_out   : out std_logic;
        ready_out : out std_logic
    );
end PCB;

architecture Behavioral of PCB is

    constant delay       : integer := 37;
    constant decimation  : integer := 2 ** avg_shift;
    constant uart_div    : natural := clk_hz / uart_baud;
    constant accum_max   : integer := 4095 * decimation;

    component clk_wiz_0 is
        Port (
            clk_in1  : in  std_logic;
            clk_out1 : out std_logic;
            locked   : out std_logic;
            reset    : in  std_logic
        );
    end component;

    type adc_state_t is (idle, init, rec, dec, add, div, wait1, wait2, emit);
    type uart_state_t is (uart_idle, uart_start, uart_data, uart_stop);

    signal adc_clk : std_logic := '0';

    signal adc_state     : adc_state_t := idle;
    signal spi_clk_r     : std_logic := '0';
    signal cs_r          : std_logic := '1';
    signal delay_count   : integer range 0 to delay := 0;
    signal delay_counter : integer range 0 to delay := 0;
    signal bit_counter   : integer range 0 to 11 := 0;
    signal decim_count   : integer range 0 to decimation - 1 := 0;
    signal accum_sum     : integer range 0 to accum_max := 0;
    signal data_buf      : std_logic_vector(11 downto 0) := (others => '0');
    signal centered      : signed(15 downto 0) := (others => '0');

    signal sample_word_adc   : std_logic_vector(15 downto 0) := (others => '0');
    signal sample_req_adc    : std_logic := '0';
    signal sample_ack_meta_a : std_logic := '0';
    signal sample_ack_sync_a : std_logic := '0';

    signal sample_req_meta_u : std_logic := '0';
    signal sample_req_sync_u : std_logic := '0';
    signal sample_req_seen_u : std_logic := '0';
    signal sample_ack_uart   : std_logic := '0';

    signal tx_word      : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_pending   : std_logic := '0';
    signal tx_byte_sel  : std_logic := '0';
    signal uart_state   : uart_state_t := uart_idle;
    signal uart_div_cnt : natural range 0 to uart_div - 1 := 0;
    signal uart_bit_idx : natural range 0 to 7 := 0;
    signal uart_shift   : std_logic_vector(7 downto 0) := (others => '0');
    signal txd_r        : std_logic := '1';

begin

    spi_clk   <= spi_clk_r;
    cs_out    <= cs_r;
    txd_out   <= txd_r;
    ready_out <= '1' when start_in = '0' and tx_pending = '0' and
                          uart_state = uart_idle and sample_req_sync_u = sample_req_seen_u else '0';

    clkwiz : clk_wiz_0
        port map (
            clk_in1  => clock_in,
            clk_out1 => adc_clk,
            locked   => open,
            reset    => '0'
        );

    adc_p : process(adc_clk)
        variable sum_v      : integer range 0 to accum_max;
        variable centered_v : integer range -2048 to 2047;
    begin
        if rising_edge(adc_clk) then
            sample_ack_meta_a <= sample_ack_uart;
            sample_ack_sync_a <= sample_ack_meta_a;

            if reset_in = '1' then
                adc_state     <= idle;
                spi_clk_r     <= '0';
                cs_r          <= '1';
                delay_count   <= 0;
                delay_counter <= 0;
                bit_counter   <= 0;
                decim_count   <= 0;
                accum_sum     <= 0;
                data_buf      <= (others => '0');
                centered      <= (others => '0');
                sample_word_adc   <= (others => '0');
                sample_req_adc    <= '0';
                sample_ack_meta_a <= '0';
                sample_ack_sync_a <= '0';
            elsif start_in = '0' then
                adc_state     <= idle;
                spi_clk_r     <= '0';
                cs_r          <= '1';
                delay_count   <= 0;
                delay_counter <= 0;
                bit_counter   <= 0;
                decim_count   <= 0;
                accum_sum     <= 0;
                data_buf      <= (others => '0');
                centered      <= (others => '0');
            else
                case adc_state is
                    when idle =>
                        adc_state     <= init;
                        spi_clk_r     <= '0';
                        cs_r          <= '1';
                        delay_count   <= 0;
                        delay_counter <= 0;
                        bit_counter   <= 0;
                        decim_count   <= 0;
                        accum_sum     <= 0;

                    when init =>
                        if delay_counter = delay_count then
                            delay_counter <= 0;
                            adc_state     <= rec;
                            spi_clk_r     <= '0';
                        elsif delay_counter > delay_count - 9 then
                            cs_r          <= '0';
                            spi_clk_r     <= not spi_clk_r;
                            delay_counter <= delay_counter + 1;
                        else
                            delay_counter <= delay_counter + 1;
                            spi_clk_r     <= '1';
                            cs_r          <= '1';
                        end if;

                    when rec =>
                        data_buf(11 - bit_counter) <= spi_miso;
                        spi_clk_r <= '1';
                        cs_r      <= '0';
                        adc_state <= dec;

                    when dec =>
                        if bit_counter = 11 then
                            bit_counter <= 0;
                            adc_state   <= add;
                            spi_clk_r   <= '0';
                        else
                            bit_counter <= bit_counter + 1;
                            adc_state   <= rec;
                            spi_clk_r   <= '0';
                            cs_r        <= '0';
                        end if;

                    when add =>
                        sum_v := accum_sum + to_integer(unsigned(data_buf));
                        spi_clk_r <= '1';
                        cs_r      <= '1';

                        if decim_count = decimation - 1 then
                            accum_sum   <= sum_v;
                            decim_count <= 0;
                            adc_state   <= div;
                        else
                            accum_sum   <= sum_v;
                            decim_count <= decim_count + 1;
                            delay_count <= delay;
                            adc_state   <= init;
                        end if;

                    when div =>
                        centered_v := (accum_sum / decimation) - 16#800#;
                        centered   <= to_signed(centered_v, centered'length);
                        adc_state  <= wait1;

                    when wait1 =>
                        adc_state <= wait2;

                    when wait2 =>
                        adc_state <= emit;

                    when emit =>
                        if sample_req_adc = sample_ack_sync_a then
                            sample_word_adc <= std_logic_vector(centered);
                            sample_req_adc  <= not sample_req_adc;
                        end if;

                        accum_sum   <= 0;
                        delay_count <= delay - 3;
                        adc_state   <= init;
                end case;
            end if;
        end if;
    end process;

    uart_p : process(clock_in)
    begin
        if rising_edge(clock_in) then
            if reset_in = '1' then
                sample_req_meta_u <= '0';
                sample_req_sync_u <= '0';
                sample_req_seen_u <= '0';
                sample_ack_uart   <= '0';
                tx_word           <= (others => '0');
                tx_pending        <= '0';
                tx_byte_sel       <= '0';
                uart_state        <= uart_idle;
                uart_div_cnt      <= 0;
                uart_bit_idx      <= 0;
                uart_shift        <= (others => '0');
                txd_r             <= '1';
            else
                sample_req_meta_u <= sample_req_adc;
                sample_req_sync_u <= sample_req_meta_u;

                if sample_req_sync_u /= sample_req_seen_u and tx_pending = '0' then
                    tx_word           <= sample_word_adc;
                    tx_pending        <= '1';
                    tx_byte_sel       <= '0';
                    sample_req_seen_u <= sample_req_sync_u;
                    sample_ack_uart   <= sample_req_sync_u;
                end if;

                case uart_state is
                    when uart_idle =>
                        txd_r        <= '1';
                        uart_div_cnt <= 0;
                        uart_bit_idx <= 0;

                        if tx_pending = '1' then
                            if tx_byte_sel = '0' then
                                uart_shift  <= tx_word(7 downto 0);
                                tx_byte_sel <= '1';
                            else
                                uart_shift  <= tx_word(15 downto 8);
                                tx_byte_sel <= '0';
                                tx_pending  <= '0';
                            end if;
                            uart_state <= uart_start;
                        end if;

                    when uart_start =>
                        txd_r <= '0';
                        if uart_div_cnt = uart_div - 1 then
                            uart_div_cnt <= 0;
                            uart_state   <= uart_data;
                        else
                            uart_div_cnt <= uart_div_cnt + 1;
                        end if;

                    when uart_data =>
                        txd_r <= uart_shift(uart_bit_idx);
                        if uart_div_cnt = uart_div - 1 then
                            uart_div_cnt <= 0;
                            if uart_bit_idx = 7 then
                                uart_bit_idx <= 0;
                                uart_state   <= uart_stop;
                            else
                                uart_bit_idx <= uart_bit_idx + 1;
                            end if;
                        else
                            uart_div_cnt <= uart_div_cnt + 1;
                        end if;

                    when uart_stop =>
                        txd_r <= '1';
                        if uart_div_cnt = uart_div - 1 then
                            uart_div_cnt <= 0;
                            uart_state   <= uart_idle;
                        else
                            uart_div_cnt <= uart_div_cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
