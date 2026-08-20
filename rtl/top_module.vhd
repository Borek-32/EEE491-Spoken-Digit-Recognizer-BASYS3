----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Module Name: top_module - Behavioral
-- Project Name: EEE491
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top_module is
	Port (
		adcdone   : out std_logic;
		adcbusy   : out std_logic;
		reset_in  : in  std_logic;
		clock_in  : in  std_logic;
		spi_clk   : out std_logic;
		spi_miso  : in  std_logic;
		cs_out    : out std_logic;
			start_in  : in  std_logic;
			ready_out : out std_logic;
			flush     : in  std_logic;
			flush_done : out std_logic;
			pmod      : out std_logic;
			txd_out   : out std_logic;
			debug_enable_in : in  std_logic;
			debug_led_out   : out std_logic;
			switch    : in  std_logic; -- 1 = record, 0 = compare
			digit_sw_in  : in  std_logic_vector(9 downto 0);
		trial_inc_in : in  std_logic;
		trial_dec_in : in  std_logic;
		an        : out std_logic_vector(3 downto 0);
		a_to_g    : out std_logic_vector(6 downto 0)
	);
end top_module;

architecture Behavioral of top_module is

	constant no_detect : std_logic := '0';

	component ADC is
		Generic (
			n_on      : integer := 10;
			n_off     : integer := 4096;
			min_rec   : integer := 4096;
			thr_on    : integer := 3000;
			thr_off   : integer := 80;
			no_detect : std_logic := '0'
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
	end component;

	component CTRL is
		Port (
			adcdone             : out std_logic;
			adcbusy             : out std_logic;
			reset_in            : in  std_logic;
			clock_in            : in  std_logic;
			start_adc_out       : out std_logic;
			ready_adc_in        : in  std_logic;
			frame_addr_out      : out std_logic_vector(13 downto 0);
			start_window_out    : out std_logic;
			ready_window_in     : in  std_logic;
			start_fft_out       : out std_logic;
			ready_fft_in        : in  std_logic;
			start_mel_out       : out std_logic;
			ready_mel_in        : in  std_logic;
				start_logmel_out    : out std_logic;
				ready_logmel_in     : in  std_logic;
				start_dct_out       : out std_logic;
				ready_dct_in        : in  std_logic;
				start_comp_out      : out std_logic;
				ready_comp_in       : in  std_logic;
				start_debug_out     : out std_logic;
				ready_debug_in      : in  std_logic;
				debug_enable_in     : in  std_logic;
				start_in            : in  std_logic;
				ready_out           : out std_logic;
			digit_sw_in         : in  std_logic_vector(9 downto 0);
			trial_inc_in        : in  std_logic;
			trial_dec_in        : in  std_logic;
			selected_digit_out  : out std_logic_vector(4 downto 0);
			selected_trial_out  : out std_logic_vector(2 downto 0)
		);
	end component;

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

	component FFT is
		Port (
			clock_in        : in  std_logic;
			reset_in        : in  std_logic;
			ready_out       : out std_logic;
			start_in        : in  std_logic;
			mem_addr_in     : in  std_logic_vector(7 downto 0);
			mem_data_out    : out std_logic_vector(31 downto 0);
			window_addr_out : out std_logic_vector(8 downto 0);
			window_data_in  : in  std_logic_vector(19 downto 0)
		);
	end component;

	component MEL is
		Port (
			reset_in     : in  std_logic;
			clock_in     : in  std_logic;
			start_in     : in  std_logic;
			ready_out    : out std_logic;
			fft_addr_out : out std_logic_vector(7 downto 0);
			fft_data_in  : in  std_logic_vector(31 downto 0);
			mem_addr_in  : in  std_logic_vector(4 downto 0);
			mem_data_out : out std_logic_vector(31 downto 0)
		);
	end component;

	component LOGMEL is
		Port (
			reset_in      : in  std_logic;
			clock_in      : in  std_logic;
			start_in      : in  std_logic;
			ready_out     : out std_logic;
			mel_addr_out  : out std_logic_vector(4 downto 0);
			mel_data_in   : in  std_logic_vector(31 downto 0);
			mem_addr_in   : in  std_logic_vector(4 downto 0);
			mem_data_out  : out std_logic_vector(31 downto 0)
		);
	end component;

	component DCT is
		Port (
			reset_in        : in  std_logic;
			clock_in        : in  std_logic;
			start_in        : in  std_logic;
			ready_out       : out std_logic;
			logmel_addr_out : out std_logic_vector(4 downto 0);
			logmel_data_in  : in  std_logic_vector(31 downto 0);
			mem_addr_in     : in  std_logic_vector(2 downto 0);
			mem_data_out    : out std_logic_vector(15 downto 0)
		);
	end component;

		component COMP is
		Port (
			reset_in         : in  std_logic;
			clock_in         : in  std_logic;
			clear_in         : in  std_logic;
			start_in         : in  std_logic;
			ready_out        : out std_logic;
			selected_digit_in : in  std_logic_vector(4 downto 0);
			selected_trial_in : in  std_logic_vector(2 downto 0);
			mode_record_in    : in  std_logic;
			record_out        : out std_logic;
			flush             : in  std_logic;
			flush_done        : out std_logic;
			dct_addr_out     : out std_logic_vector(2 downto 0);
			dct_data_in      : in  std_logic_vector(15 downto 0);
			mel_addr_out     : out std_logic_vector(4 downto 0);
			mel_data_in      : in  std_logic_vector(31 downto 0);
			digit_out        : out std_logic_vector(3 downto 0);
			valid_out        : out std_logic;
			digit_idx3_patch : out std_logic
		);
		end component;

		component debug is
			Generic (
				CLK_HZ           : natural := 100000000;
				BAUD_RATE        : natural := 1000000;
				READ_WAIT_CYCLES : natural := 4
			);
			Port (
				reset_in                 : in  std_logic;
				clock_in                 : in  std_logic;
				start_in                 : in  std_logic;
				frame_addr_in            : in  std_logic_vector(13 downto 0);
				mode_record_in           : in  std_logic;
				comp_digit_in            : in  std_logic_vector(3 downto 0);
				comp_valid_in            : in  std_logic;
				comp_record_in           : in  std_logic;
				comp_digit_idx3_patch_in : in  std_logic;
				adc_data_in              : in  std_logic_vector(11 downto 0);
				window_data_in           : in  std_logic_vector(19 downto 0);
				fft_data_in              : in  std_logic_vector(31 downto 0);
				mel_data_in              : in  std_logic_vector(31 downto 0);
				logmel_data_in           : in  std_logic_vector(31 downto 0);
				dct_data_in              : in  std_logic_vector(15 downto 0);
				txd_out                  : out std_logic;
				ready_out                : out std_logic;
				active_out               : out std_logic;
				adc_addr_out             : out std_logic_vector(13 downto 0);
				window_addr_out          : out std_logic_vector(8 downto 0);
				fft_addr_out             : out std_logic_vector(7 downto 0);
				mel_addr_out             : out std_logic_vector(4 downto 0);
				logmel_addr_out          : out std_logic_vector(4 downto 0);
				dct_addr_out             : out std_logic_vector(2 downto 0)
			);
		end component;

	component seven_segment is
		Port (
			in1    : in  std_logic_vector(3 downto 0);
			in2    : in  std_logic_vector(3 downto 0);
			in3    : in  std_logic_vector(3 downto 0);
			in4    : in  std_logic_vector(3 downto 0);
			an     : out std_logic_vector(3 downto 0);
			a_to_g : out std_logic_vector(6 downto 0);
			clk    : in  std_logic
		);
	end component;

	signal start_adc    : std_logic := '0';
	signal ready_adc    : std_logic := '0';
	signal start_window : std_logic := '0';
	signal ready_window : std_logic := '0';
	signal start_fft    : std_logic := '0';
	signal ready_fft    : std_logic := '0';
	signal start_mel    : std_logic := '0';
	signal ready_mel    : std_logic := '0';
	signal start_logmel : std_logic := '0';
	signal ready_logmel : std_logic := '0';
		signal start_dct    : std_logic := '0';
		signal ready_dct    : std_logic := '0';
		signal start_comp   : std_logic := '0';
		signal ready_comp   : std_logic := '0';
		signal start_debug  : std_logic := '0';
		signal ready_debug  : std_logic := '1';
		signal debug_active : std_logic := '0';

		signal adc_addr             : std_logic_vector(13 downto 0) := (others => '0');
		signal adc_addr_from_window : std_logic_vector(13 downto 0) := (others => '0');
		signal adc_addr_from_debug  : std_logic_vector(13 downto 0) := (others => '0');
		signal adc_data             : std_logic_vector(11 downto 0) := (others => '0');

		signal window_addr            : std_logic_vector(8 downto 0) := (others => '0');
		signal window_addr_from_fft   : std_logic_vector(8 downto 0) := (others => '0');
		signal window_addr_from_debug : std_logic_vector(8 downto 0) := (others => '0');
		signal window_data            : std_logic_vector(19 downto 0) := (others => '0');

		signal fft_addr            : std_logic_vector(7 downto 0) := (others => '0');
		signal fft_addr_from_mel   : std_logic_vector(7 downto 0) := (others => '0');
		signal fft_addr_from_debug : std_logic_vector(7 downto 0) := (others => '0');
		signal fft_data            : std_logic_vector(31 downto 0) := (others => '0');

		signal mel_addr             : std_logic_vector(4 downto 0) := (others => '0');
		signal mel_addr_from_logmel : std_logic_vector(4 downto 0) := (others => '0');
		signal mel_addr_from_comp   : std_logic_vector(4 downto 0) := (others => '0');
		signal mel_addr_from_debug  : std_logic_vector(4 downto 0) := (others => '0');
		signal mel_data             : std_logic_vector(31 downto 0) := (others => '0');

		signal logmel_addr            : std_logic_vector(4 downto 0) := (others => '0');
		signal logmel_addr_from_dct   : std_logic_vector(4 downto 0) := (others => '0');
		signal logmel_addr_from_debug : std_logic_vector(4 downto 0) := (others => '0');
		signal logmel_data            : std_logic_vector(31 downto 0) := (others => '0');

		signal dct_addr            : std_logic_vector(2 downto 0) := (others => '0');
		signal dct_addr_from_comp  : std_logic_vector(2 downto 0) := (others => '0');
		signal dct_addr_from_debug : std_logic_vector(2 downto 0) := (others => '0');
		signal dct_data            : std_logic_vector(15 downto 0) := (others => '0');

	signal comp_digit            : std_logic_vector(3 downto 0) := x"F";
	signal comp_digit_fixed      : std_logic_vector(3 downto 0) := x"F";
	signal comp_valid            : std_logic := '0';
	signal comp_digit_idx3_patch : std_logic := '0';
	signal comp_record           : std_logic := '0';
	signal comp_clear            : std_logic := '0';
	signal comp_active           : std_logic := '0';
		signal selected_digit        : std_logic_vector(4 downto 0) := (others => '0');
		signal selected_trial        : std_logic_vector(2 downto 0) := (others => '0');
		signal selected_digit_run    : std_logic_vector(4 downto 0) := (others => '0');
		signal selected_trial_run    : std_logic_vector(2 downto 0) := (others => '0');
		signal mode_record_run       : std_logic := '0';
		signal ready_ctrl            : std_logic := '1';
		signal flush_comp            : std_logic := '0';
	signal seg_in1               : std_logic_vector(3 downto 0) := x"F";
	signal seg_in2               : std_logic_vector(3 downto 0) := x"F";
	signal seg_in3               : std_logic_vector(3 downto 0) := x"F";
	signal seg_in4               : std_logic_vector(3 downto 0) := x"F";

	signal frame_addr       : std_logic_vector(13 downto 0) := (others => '0');
	signal adc_done_unused  : std_logic;
	signal start_meta       : std_logic := '0';
	signal start_sync       : std_logic := '0';
	signal start_sync_prev  : std_logic := '0';
	signal ctrl_start_pulse : std_logic := '0';

begin

	pmod <= switch;
	debug_led_out <= debug_enable_in;
	ctrl_start_pulse <= start_sync and not start_sync_prev;
	comp_clear <= ctrl_start_pulse;
	comp_active <= start_comp or not ready_comp;
	comp_digit_fixed <= comp_digit_idx3_patch & comp_digit(2 downto 0);
	ready_out <= ready_ctrl;
	-- BTND is asynchronous and is synchronized inside COMP.  Gating it with
	-- the complete-controller ready state prevents a late press during ADC or
	-- feature extraction from stealing the reference-RAM port before COMP's
	-- first frame transaction.
	flush_comp <= flush and ready_ctrl;

		adc_addr <= adc_addr_from_debug when debug_active = '1' else adc_addr_from_window;
		window_addr <= window_addr_from_debug when debug_active = '1' else window_addr_from_fft;
		fft_addr <= fft_addr_from_debug when debug_active = '1' else fft_addr_from_mel;
		mel_addr <= mel_addr_from_debug when debug_active = '1' else
		            mel_addr_from_comp when comp_active = '1' else mel_addr_from_logmel;
		logmel_addr <= logmel_addr_from_debug when debug_active = '1' else logmel_addr_from_dct;
		dct_addr <= dct_addr_from_debug when debug_active = '1' else dct_addr_from_comp;

	seg_mux : process(switch, comp_valid, comp_digit_fixed, selected_digit, selected_trial)
	begin
		-- Seven-segment order is in1=in leftmost digit and in4=rightmost digit.
		-- Record mode:  r d <selected digit> <selected trial>
		-- Compare mode: C d d <recognized digit>
		-- A single mux process drives all seg_in signals, so there are no
		-- multiple-driven display nets.
		case switch is
			when '1' =>
				seg_in1 <= x"A"; -- custom seven-segment code: r
				seg_in2 <= x"D"; -- d = digit label
				seg_in3 <= selected_digit(3 downto 0);
				seg_in4 <= '0' & selected_trial;

			when others =>
				seg_in1 <= x"C"; -- compare mode
				seg_in2 <= x"D";
				seg_in3 <= x"D";
				if comp_valid = '1' then
					seg_in4 <= comp_digit_fixed;
				else
					seg_in4 <= x"0";
				end if;
		end case;
	end process;

	start_sync_proc : process(clock_in)
	begin
		if rising_edge(clock_in) then
			if reset_in = '1' then
				start_meta <= '0';
				start_sync <= '0';
				start_sync_prev <= '0';
				mode_record_run <= '0';
				selected_digit_run <= (others => '0');
				selected_trial_run <= (others => '0');
			else
				start_meta <= start_in;
				start_sync <= start_meta;
				start_sync_prev <= start_sync;

				-- Capture one coherent enrollment/compare command at the
				-- synchronized start edge.  Physical controls may change while
				-- the 63-frame run is executing without relabeling the template
				-- or changing the requested COMP mode mid-transaction.
				if ctrl_start_pulse = '1' then
					mode_record_run <= switch;
					selected_digit_run <= selected_digit;
					selected_trial_run <= selected_trial;
				end if;
			end if;
		end if;
	end process;

	fftc : FFT
		port map (
			clock_in        => clock_in,
			reset_in        => reset_in,
			window_addr_out => window_addr_from_fft,
			window_data_in  => window_data,
			mem_addr_in     => fft_addr,
			mem_data_out    => fft_data,
			start_in        => start_fft,
			ready_out       => ready_fft
		);

	melc : MEL
		port map (
			clock_in     => clock_in,
			reset_in     => reset_in,
			start_in     => start_mel,
			ready_out    => ready_mel,
			fft_addr_out => fft_addr_from_mel,
			fft_data_in  => fft_data,
			mem_addr_in  => mel_addr,
			mem_data_out => mel_data
		);

	logmelc : LOGMEL
		port map (
			clock_in     => clock_in,
			reset_in     => reset_in,
			start_in     => start_logmel,
			ready_out    => ready_logmel,
			mel_addr_out => mel_addr_from_logmel,
			mel_data_in  => mel_data,
			mem_addr_in  => logmel_addr,
			mem_data_out => logmel_data
		);

	dctc : DCT
		port map (
			clock_in        => clock_in,
			reset_in        => reset_in,
			start_in        => start_dct,
			ready_out       => ready_dct,
			logmel_addr_out => logmel_addr_from_dct,
			logmel_data_in  => logmel_data,
			mem_addr_in     => dct_addr,
			mem_data_out    => dct_data
		);

	compc : COMP
		port map (
			clock_in         => clock_in,
			reset_in         => reset_in,
			clear_in         => comp_clear,
			start_in         => start_comp,
			ready_out        => ready_comp,
			selected_digit_in => selected_digit_run,
			selected_trial_in => selected_trial_run,
			mode_record_in    => mode_record_run,
			record_out        => comp_record,
				flush             => flush_comp,
			flush_done        => flush_done,
			dct_addr_out     => dct_addr_from_comp,
			dct_data_in      => dct_data,
			mel_addr_out     => mel_addr_from_comp,
			mel_data_in      => mel_data,
			digit_out        => comp_digit,
			valid_out        => comp_valid,
			digit_idx3_patch => comp_digit_idx3_patch
		);

	sevenseg : seven_segment
		port map (
			in1    => seg_in1,
			in2    => seg_in2,
			in3    => seg_in3,
			in4    => seg_in4,
			an     => an,
			a_to_g => a_to_g,
			clk    => clock_in
		);

	win : WINDOW
		port map (
			clock_in      => clock_in,
			reset_in      => reset_in,
			frame_addr_in => frame_addr,
			adc_addr_out  => adc_addr_from_window,
			adc_data_in   => adc_data,
			mem_addr_in   => window_addr,
			mem_data_out  => window_data,
			start_in      => start_window,
			ready_out     => ready_window
		);

	ctl : CTRL
		port map (
			adcdone          => adcdone,
			adcbusy          => adcbusy,
			reset_in         => reset_in,
			clock_in         => clock_in,
			start_adc_out    => start_adc,
			ready_adc_in     => ready_adc,
			frame_addr_out   => frame_addr,
			start_window_out => start_window,
			ready_window_in  => ready_window,
			start_fft_out    => start_fft,
			ready_fft_in     => ready_fft,
			start_mel_out    => start_mel,
			ready_mel_in     => ready_mel,
			start_logmel_out => start_logmel,
			ready_logmel_in  => ready_logmel,
			start_dct_out    => start_dct,
				ready_dct_in     => ready_dct,
				start_comp_out   => start_comp,
				ready_comp_in    => ready_comp,
				start_debug_out  => start_debug,
				ready_debug_in   => ready_debug,
				debug_enable_in  => debug_enable_in,
				start_in         => ctrl_start_pulse,
					ready_out        => ready_ctrl,
			digit_sw_in      => digit_sw_in,
			trial_inc_in     => trial_inc_in,
			trial_dec_in     => trial_dec_in,
			selected_digit_out => selected_digit,
				selected_trial_out => selected_trial
			);

		debugc : debug
			generic map (
				CLK_HZ           => 100000000,
				BAUD_RATE        => 1000000,
				READ_WAIT_CYCLES => 4
			)
			port map (
				reset_in                 => reset_in,
				clock_in                 => clock_in,
				start_in                 => start_debug,
				frame_addr_in            => frame_addr,
				mode_record_in           => mode_record_run,
				comp_digit_in            => comp_digit_fixed,
				comp_valid_in            => comp_valid,
				comp_record_in           => comp_record,
				comp_digit_idx3_patch_in => comp_digit_idx3_patch,
				adc_data_in              => adc_data,
				window_data_in           => window_data,
				fft_data_in              => fft_data,
				mel_data_in              => mel_data,
				logmel_data_in           => logmel_data,
				dct_data_in              => dct_data,
				txd_out                  => txd_out,
				ready_out                => ready_debug,
				active_out               => debug_active,
				adc_addr_out             => adc_addr_from_debug,
				window_addr_out          => window_addr_from_debug,
				fft_addr_out             => fft_addr_from_debug,
				mel_addr_out             => mel_addr_from_debug,
				logmel_addr_out          => logmel_addr_from_debug,
				dct_addr_out             => dct_addr_from_debug
			);

		ac : ADC
		generic map (
			n_on      => 10,
			n_off     => 1024,
			min_rec   => 4096,
			thr_on    => 1000,
			thr_off   => 80,
			no_detect => no_detect
		)
		port map (
			reset_in  => reset_in,
			clock_in  => clock_in,
			start_in  => start_adc,
			addr_in   => adc_addr,
			spi_miso  => spi_miso,
			spi_clk   => spi_clk,
			CS_out    => cs_out,
			data_out  => adc_data,
			ready_out => ready_adc,
			done      => adc_done_unused
		);

end Behavioral;
