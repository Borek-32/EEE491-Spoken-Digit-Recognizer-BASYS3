library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ADC is
	Generic (
		n_on        : integer := 10;
		n_off       : integer := 4096;
		min_rec     : integer := 4096;
		thr_on      : integer := 1000;
		thr_off     : integer := 80;
		no_detect   : std_logic := '0'
	);
	Port (
		reset_in  : in  std_logic;
		clock_in  : in  std_logic;
		start_in  : in  std_logic;
		addr_in   : in  std_logic_vector(13 downto 0);
		spi_miso  : in  std_logic;

		spi_clk   : out std_logic;
		CS_out    : out std_logic;
		data_out  : out std_logic_vector(11 downto 0);
		done      : out std_logic;
		ready_out : out std_logic
	);
end ADC;

architecture Behavioral of ADC is

	constant delay       : integer := 37;
	constant avg_count   : integer := 32;
	constant preroll_len : integer := 2048;

	constant sys_clk_hz  : natural := 100000000;
	constant adc_tick_hz : natural := 36000000;

	-- With sys_clk_hz=100 MHz and adc_tick_hz=36 MHz, the rounded integer divider is 3,
	-- so the actual clean tick rate is 100 MHz / 3 = 33.333 MHz.
	-- Exact 36 MHz cannot be produced as a uniform one-clock enable from 100 MHz
	-- without either fractional jitter or a separate PLL/MMCM clock.
	constant adc_divider : natural := (sys_clk_hz + (adc_tick_hz / 2)) / adc_tick_hz;

	subtype mag_t is unsigned(12 downto 0);

	constant th_on_mag  : mag_t := to_unsigned(thr_on, 13);
	constant th_off_mag : mag_t := to_unsigned(thr_off, 13); -- Kept passive until end-of-voice detection is added.

	type fsm0 is (ready, busy);
	signal internal : fsm0 := ready;

	type fsm1 is (idle, init, rec, dec, add, div, mags, buffer_sample, save, fillback, pad, done0);
	signal state : fsm1 := idle;

	signal adc_cnt  : integer range 0 to adc_divider - 1 := 0;
	signal adc_tick : std_logic := '0';

	signal delay_count   : integer := 0;
	signal delay_counter : integer := 0;
	signal bit_counter   : integer range 0 to 11 := 0;
	signal avg_cnt       : integer range 0 to avg_count - 1 := 0;
	signal cnt           : integer range 0 to 1 := 0;
	signal cnt1          : integer := 0;
	signal off_cnt       : integer := 0;
	signal rec_cnt       : integer range 0 to 16383 := 0;

	signal data_buf   : std_logic_vector(11 downto 0) := (others => '0');
	signal sample_acc : integer := 0;
	signal acc        : mag_t := (others => '0');
	signal mag        : mag_t := (others => '0');
	signal sample     : signed(12 downto 0) := (others => '0');
	signal sample_ram : std_logic_vector(11 downto 0) := (others => '0');

	signal flag      : std_logic := '0';
	signal spi_clkb  : std_logic := '1';
	signal cs_buf    : std_logic := '1';
	signal spi_clk_iob : std_logic := '0';
	signal cs_iob    : std_logic := '1';
	signal spi_miso_buf : std_logic := '0';
	signal stop_done : std_logic := '0';
	signal pad_after_save : std_logic := '0';

	attribute IOB : string;
	attribute IOB of spi_clk_iob : signal is "TRUE";
	attribute IOB of cs_iob : signal is "TRUE";
	attribute IOB of spi_miso_buf : signal is "TRUE";

	signal buf_widx  : integer range 0 to preroll_len - 1 := 0;
	signal buf_ridx  : integer range 0 to preroll_len - 1 := 0;
	signal buf_waddr : std_logic_vector(10 downto 0) := (others => '0');
	signal buf_raddr : std_logic_vector(10 downto 0) := (others => '0');
	signal buf_wdata : std_logic_vector(11 downto 0) := (others => '0');
	signal buf_rdata : std_logic_vector(11 downto 0) := (others => '0');
	signal buf_wea   : std_logic_vector(0 downto 0) := "0";
	signal preroll_filled : std_logic := '0';

	signal write_addr    : std_logic_vector(13 downto 0) := (others => '0');
	signal din_ram       : std_logic_vector(11 downto 0) := (others => '0');
	signal write_enable  : std_logic_vector(0 downto 0) := "0";

	component blk_mem_gen_2 is
		Port (
			addra : in  std_logic_vector(13 downto 0);
			clka  : in  std_logic;
			ena   : in  std_logic;
			dina  : in  std_logic_vector(11 downto 0);
			wea   : in  std_logic_vector(0 downto 0);

			addrb : in  std_logic_vector(13 downto 0);
			clkb  : in  std_logic;
			enb   : in  std_logic;
			doutb : out std_logic_vector(11 downto 0)
		);
	end component;

	component vad_buffer is
		Port (
			addra : in  std_logic_vector(10 downto 0);
			clka  : in  std_logic;
			dina  : in  std_logic_vector(11 downto 0);
			wea   : in  std_logic_vector(0 downto 0);

			addrb : in  std_logic_vector(10 downto 0);
			clkb  : in  std_logic;
			doutb : out std_logic_vector(11 downto 0)
		);
	end component;

begin

	spi_clk    <= spi_clk_iob;
	CS_out     <= cs_iob;
	sample_ram <= std_logic_vector(resize(sample, 12));
	buf_raddr  <= std_logic_vector(to_unsigned(buf_ridx, 11));

	preroll_buf: vad_buffer
		port map(
			addra => buf_waddr,
			clka  => clock_in,
			dina  => buf_wdata,
			wea   => buf_wea,

			addrb => buf_raddr,
			clkb  => clock_in,
			doutb => buf_rdata
		);

	ram: blk_mem_gen_2
		port map(
			addra => write_addr,
			clka  => clock_in,
			ena   => '1',
			dina  => din_ram,
			wea   => write_enable,

			addrb => addr_in,
			clkb  => clock_in,
			enb   => '1',
			doutb => data_out
		);

	tick_p: process(clock_in)
	begin
		if rising_edge(clock_in) then
			if reset_in = '1' then
				adc_cnt  <= 0;
				adc_tick <= '0';
			elsif adc_cnt = adc_divider - 1 then
				adc_cnt  <= 0;
				adc_tick <= '1';
			else
				adc_cnt  <= adc_cnt + 1;
				adc_tick <= '0';
			end if;
		end if;
	end process;

	sr: process(clock_in)
	begin
		if rising_edge(clock_in) then
			if reset_in = '1' then
				internal  <= ready;
				ready_out <= '1';
			else
				case internal is
					when ready =>
						if start_in = '1' then
							internal  <= busy;
							ready_out <= '0';
						else
							ready_out <= '1';
						end if;

					when busy =>
						if stop_done = '1' then
							internal  <= ready;
							ready_out <= '1';
						else
							ready_out <= '0';
						end if;
				end case;
			end if;
		end if;
	end process;

	p1: process(clock_in)
		variable acc_next : mag_t;
	begin
		if rising_edge(clock_in) then
			spi_miso_buf <= spi_miso;
			spi_clk_iob <= spi_clkb;
			cs_iob <= cs_buf;

			if reset_in = '1' then
				state <= idle;
				sample        <= (others => '0');
				sample_acc    <= 0;
				acc           <= (others => '0');
				mag           <= (others => '0');
				delay_count   <= 0;
				delay_counter <= 0;
				bit_counter   <= 0;
				avg_cnt       <= 0;
				cnt           <= 0;
				cnt1          <= 0;
				off_cnt       <= 0;
				rec_cnt       <= preroll_len - 1;
				buf_widx      <= 0;
				buf_ridx      <= 0;
				buf_waddr     <= (others => '0');
				buf_wea       <= "0";
				preroll_filled <= '0';
				write_enable  <= "0";
				flag          <= no_detect;
				done          <= '0';
				stop_done     <= '0';
				pad_after_save <= '0';
				data_buf      <= x"000";
				din_ram       <= x"000";
				spi_clkb      <= '0';
				cs_buf        <= '1';
				spi_clk_iob   <= '0';
				cs_iob        <= '1';
			elsif adc_tick = '1' then
				case state is
					when idle =>
						if internal = busy then
							stop_done <= '0';
							done      <= '0';
							state     <= init;
						else
							sample        <= (others => '0');
							sample_acc    <= 0;
							acc           <= (others => '0');
							mag           <= (others => '0');
							delay_count   <= 0;
							delay_counter <= 0;
							bit_counter   <= 0;
							avg_cnt       <= 0;
							cnt           <= 0;
							cnt1          <= 0;
							off_cnt       <= 0;
							rec_cnt       <= preroll_len - 1;
							buf_widx      <= 0;
							buf_ridx      <= 0;
							buf_waddr     <= (others => '0');
							buf_wea       <= "0";
							preroll_filled <= '0';
							write_enable  <= "0";
							flag          <= no_detect;
							done          <= '0';
							stop_done     <= '0';
							pad_after_save <= '0';
							data_buf      <= x"000";
							din_ram       <= x"000";
							spi_clkb      <= '0';
							cs_buf        <= '1';
						end if;

					when init =>
						buf_wea      <= "0";
						write_enable <= "0";
						done         <= '0';
						stop_done    <= '0';

						if delay_counter = delay_count then
							delay_counter <= 0;
							state         <= rec;
							spi_clkb      <= '0';
						elsif delay_counter > delay_count - 9 then
							cs_buf        <= '0';
							spi_clkb      <= not spi_clkb;
							delay_counter <= delay_counter + 1;
						else
							delay_counter <= delay_counter + 1;
							spi_clkb <= '1';
							cs_buf   <= '1';
						end if;

					when rec =>
						-- Drive SCLK first. MISO is sampled one adc_tick later in dec.
						-- This avoids sampling MISO on the same edge that changes SCLK.
						spi_clkb <= '1';
						cs_buf   <= '0';
						state    <= dec;

					when dec =>
						data_buf(11 - bit_counter) <= spi_miso_buf;
						spi_clkb <= '0';
						cs_buf   <= '0';

						if bit_counter = 11 then
							bit_counter <= 0;
							state       <= add;
						else
							bit_counter <= bit_counter + 1;
							state       <= rec;
						end if;

					when add =>
						sample_acc <= sample_acc + to_integer(unsigned(data_buf));

						if avg_cnt = avg_count - 1 then
							state   <= div;
							avg_cnt <= 0;
						else
							avg_cnt     <= avg_cnt + 1;
							state       <= init;
							delay_count <= delay;
						end if;

						spi_clkb <= '1';
						cs_buf   <= '1';

					when div =>
						sample       <= to_signed((sample_acc / avg_count) - 16#800#, sample'length);
						sample_acc   <= 0;
						buf_wea      <= "0";
						write_enable <= "0";
						state        <= mags;

					when mags =>
						mag <= unsigned(abs(sample));
						pad_after_save <= '0';

						if flag = '1' then
							if rec_cnt = 16383 then
								rec_cnt  <= 0;
								buf_ridx <= buf_widx;
								cnt      <= 0;
								state    <= fillback;
							else
								if rec_cnt >= preroll_len + min_rec and unsigned(abs(sample)) < th_off_mag then
									if off_cnt = n_off - 1 then
										off_cnt <= 0;
										pad_after_save <= '1';
									else
										off_cnt <= off_cnt + 1;
									end if;
								else
									off_cnt <= 0;
								end if;

								rec_cnt <= rec_cnt + 1;
								state   <= save;
							end if;
						else
							state <= buffer_sample;
						end if;

					when buffer_sample =>
						buf_waddr <= std_logic_vector(to_unsigned(buf_widx, 11));
						buf_wdata <= sample_ram;
						buf_wea   <= "1";
						acc_next  := acc + mag;

						delay_count <= delay - 2;
						state       <= init;

						if cnt1 = 2 then
							cnt1 <= 0;
							acc  <= (others => '0');

							if preroll_filled = '1' and acc_next > th_on_mag then
								flag <= '1';
							end if;
						else
							cnt1 <= cnt1 + 1;
							acc  <= acc_next;
						end if;

						if buf_widx = preroll_len - 1 then
							buf_widx <= 0;
							preroll_filled <= '1';
						else
							buf_widx <= buf_widx + 1;
						end if;

					when save =>
						write_addr   <= std_logic_vector(to_unsigned(rec_cnt, 14));
						din_ram      <= sample_ram;
						write_enable <= "1";
						delay_count  <= delay - 2;

						if pad_after_save = '1' then
							pad_after_save <= '0';
							if rec_cnt = 16383 then
								rec_cnt  <= 0;
								buf_ridx <= buf_widx;
								cnt      <= 0;
								state    <= fillback;
							else
								rec_cnt <= rec_cnt + 1;
								state   <= pad;
							end if;
						else
							state <= init;
						end if;

					when fillback =>
						buf_wea <= "0";

						if cnt = 0 then
							write_enable <= "0";
							cnt <= 1;
						else
							write_addr   <= std_logic_vector(to_unsigned(rec_cnt, 14));
							din_ram      <= buf_rdata;
							write_enable <= "1";
							cnt <= 0;

							if rec_cnt = preroll_len - 1 then
								rec_cnt <= 0;
								state   <= done0;
							else
								rec_cnt <= rec_cnt + 1;
							end if;

							if buf_ridx = preroll_len - 1 then
								buf_ridx <= 0;
							else
								buf_ridx <= buf_ridx + 1;
							end if;
						end if;

					when pad =>
						write_addr   <= std_logic_vector(to_unsigned(rec_cnt, 14));
						din_ram      <= x"000";
						write_enable <= "1";
						buf_wea      <= "0";

						if rec_cnt = 16383 then
							rec_cnt  <= 0;
							buf_ridx <= buf_widx;
							cnt      <= 0;
							state    <= fillback;
						else
							rec_cnt <= rec_cnt + 1;
						end if;

					when done0 =>
						write_enable <= "0";
						buf_wea      <= "0";
						done         <= '1';
						stop_done    <= '1';
						state        <= idle;
				end case;
			end if;
		end if;
	end process;

end Behavioral;
