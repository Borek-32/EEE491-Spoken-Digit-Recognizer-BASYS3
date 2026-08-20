library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CTRL is
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
end entity;

architecture Behavioral of CTRL is

	type fsm is (idle, ADC, WINDOW, FFT, MEL, LOGMEL, DCT, COMP, DEBUG, done);
	signal state : fsm := idle;

	signal cnt            : integer range 0 to 2 := 0;
	signal frame_addr_idx : integer range 0 to 16383 := 0;

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
	signal ready_debug  : std_logic := '0';
	signal start_in_d   : std_logic := '0';

	constant DEBOUNCE_MAX : integer := 500000;

	signal selected_digit : std_logic_vector(4 downto 0) := (others => '0');
	signal selected_trial : unsigned(2 downto 0) := (others => '0');

	signal inc_meta  : std_logic := '0';
	signal inc_sync  : std_logic := '0';
	signal inc_level : std_logic := '0';
	signal inc_count : integer range 0 to DEBOUNCE_MAX := 0;

	signal dec_meta  : std_logic := '0';
	signal dec_sync  : std_logic := '0';
	signal dec_level : std_logic := '0';
	signal dec_count : integer range 0 to DEBOUNCE_MAX := 0;

begin

	frame_addr_out   <= std_logic_vector(to_unsigned(frame_addr_idx, 14));
	start_adc_out    <= start_adc;
	ready_adc        <= ready_adc_in;
	start_window_out <= start_window;
	ready_window     <= ready_window_in;
	start_fft_out    <= start_fft;
	ready_fft        <= ready_fft_in;
	start_mel_out    <= start_mel;
	ready_mel        <= ready_mel_in;
	start_logmel_out <= start_logmel;
	ready_logmel     <= ready_logmel_in;
	start_dct_out    <= start_dct;
	ready_dct        <= ready_dct_in;
	start_comp_out   <= start_comp;
	ready_comp       <= ready_comp_in;
	start_debug_out  <= start_debug;
	ready_debug      <= ready_debug_in;
	selected_digit_out <= selected_digit;
	selected_trial_out <= std_logic_vector(selected_trial);

	process(clock_in)
		variable inc_press : std_logic;
		variable dec_press : std_logic;
	begin
		if rising_edge(clock_in) then
			inc_press := '0';
			dec_press := '0';

			if reset_in = '1' then
				selected_digit <= (others => '0');
				selected_trial <= (others => '0');
				inc_meta <= '0';
				inc_sync <= '0';
				inc_level <= '0';
				inc_count <= 0;
				dec_meta <= '0';
				dec_sync <= '0';
				dec_level <= '0';
				dec_count <= 0;
			else
				-- Two flip-flop button synchronizers.
				inc_meta <= trial_inc_in;
				inc_sync <= inc_meta;
				dec_meta <= trial_dec_in;
				dec_sync <= dec_meta;

				-- Simple debounce: the synchronized level must stay different
				-- for DEBOUNCE_MAX clocks before the stable level changes.
				if inc_sync = inc_level then
					inc_count <= 0;
				elsif inc_count = DEBOUNCE_MAX then
					inc_level <= inc_sync;
					inc_count <= 0;
					if inc_sync = '1' then
						inc_press := '1';
					end if;
				else
					inc_count <= inc_count + 1;
				end if;

				if dec_sync = dec_level then
					dec_count <= 0;
				elsif dec_count = DEBOUNCE_MAX then
					dec_level <= dec_sync;
					dec_count <= 0;
					if dec_sync = '1' then
						dec_press := '1';
					end if;
				else
					dec_count <= dec_count + 1;
				end if;

				-- COMP digit/trial inputs are allowed to update only while CTRL
				-- is idle or while the ADC stage is running. Other states hold
				-- the previous selected_digit and selected_trial values.
				if state = idle or state = ADC then
					case digit_sw_in is
						when "0000000001" => selected_digit <= "00000";
						when "0000000010" => selected_digit <= "00001";
						when "0000000100" => selected_digit <= "00010";
						when "0000001000" => selected_digit <= "00011";
						when "0000010000" => selected_digit <= "00100";
						when "0000100000" => selected_digit <= "00101";
						when "0001000000" => selected_digit <= "00110";
						when "0010000000" => selected_digit <= "00111";
						when "0100000000" => selected_digit <= "01000";
						when "1000000000" => selected_digit <= "01001";
						when others       => selected_digit <= "00000";
					end case;

					if inc_press = '1' and dec_press = '0' then
						if selected_trial = to_unsigned(2, 3) then
							selected_trial <= (others => '0');
						else
							selected_trial <= selected_trial + 1;
						end if;
					elsif dec_press = '1' and inc_press = '0' then
						if selected_trial = to_unsigned(0, 3) then
							selected_trial <= to_unsigned(2, 3);
						else
							selected_trial <= selected_trial - 1;
						end if;
					end if;
				end if;
			end if;
		end if;
	end process;

	process(clock_in)
	begin
		if rising_edge(clock_in) then
			if reset_in = '1' then
				state <= idle;
				cnt <= 0;
				frame_addr_idx <= 0;
				start_adc <= '0';
				start_window <= '0';
				start_fft <= '0';
				start_mel <= '0';
					start_logmel <= '0';
					start_dct <= '0';
					start_comp <= '0';
					start_debug <= '0';
					start_in_d <= '0';
					ready_out <= '1';
				adcbusy <= '0';
				adcdone <= '0';
			else
				start_in_d <= start_in;
				start_adc <= '0';
				start_window <= '0';
				start_fft <= '0';
				start_mel <= '0';
					start_logmel <= '0';
					start_dct <= '0';
					start_comp <= '0';
					start_debug <= '0';

				case state is
					when idle =>
						ready_out <= '1';
						if start_in = '1' and start_in_d = '0' and ready_adc = '1' then
							ready_out <= '0';
							adcdone <= '0';
							adcbusy <= '1';
							start_adc <= '1';
							cnt <= 0;
							frame_addr_idx <= 0;
							state <= ADC;
						end if;

					when ADC =>
						if cnt = 0 then
							cnt <= 1;
						elsif cnt = 1 then
							if ready_adc = '0' then
								cnt <= 2;
							end if;
						elsif ready_adc = '1' then
							cnt <= 0;
							adcbusy <= '0';
							adcdone <= '1';
							start_window <= '1';
							state <= WINDOW;
						end if;

					when WINDOW =>
						if cnt = 0 then
							cnt <= 1;
						elsif cnt = 1 then
							if ready_window = '0' then
								cnt <= 2;
							end if;
						elsif ready_window = '1' then
							cnt <= 0;
							start_fft <= '1';
							state <= FFT;
						end if;

					when FFT =>
						if cnt = 0 then
							cnt <= 1;
						elsif cnt = 1 then
							if ready_fft = '0' then
								cnt <= 2;
							end if;
						elsif ready_fft = '1' then
							cnt <= 0;
							start_mel <= '1';
							state <= MEL;
						end if;

					when MEL =>
						if cnt = 0 then
							cnt <= 1;
						elsif cnt = 1 then
							if ready_mel = '0' then
								cnt <= 2;
							end if;
						elsif ready_mel = '1' then
							cnt <= 0;
							start_logmel <= '1';
							state <= LOGMEL;
						end if;

					when LOGMEL =>
						if cnt = 0 then
							cnt <= 1;
						elsif cnt = 1 then
							if ready_logmel = '0' then
								cnt <= 2;
							end if;
						elsif ready_logmel = '1' then
							cnt <= 0;
							start_dct <= '1';
							state <= DCT;
						end if;

					when DCT =>
						if cnt = 0 then
							cnt <= 1;
						elsif cnt = 1 then
							if ready_dct = '0' then
								cnt <= 2;
							end if;
						elsif ready_dct = '1' then
							cnt <= 0;
							start_comp <= '1';
							state <= COMP;
						end if;

						when COMP =>
							if cnt = 0 then
								cnt <= 1;
							elsif cnt = 1 then
								if ready_comp = '0' then
									cnt <= 2;
								end if;
							elsif ready_comp = '1' then
								cnt <= 0;
								case debug_enable_in is
									when '1' =>
										start_debug <= '1';
										state <= DEBUG;

									when others =>
										if frame_addr_idx = 15872 then
											ready_out <= '1';
											state <= done;
										else
											frame_addr_idx <= frame_addr_idx + 256;
											start_window <= '1';
											state <= WINDOW;
										end if;
								end case;
							end if;

						when DEBUG =>
							if cnt = 0 then
								cnt <= 1;
							elsif cnt = 1 then
								if ready_debug = '0' then
									cnt <= 2;
								end if;
							elsif ready_debug = '1' then
								cnt <= 0;
								if frame_addr_idx = 15872 then
									ready_out <= '1';
									state <= done;
								else
									frame_addr_idx <= frame_addr_idx + 256;
									start_window <= '1';
									state <= WINDOW;
								end if;
								end if;

						when done =>
							ready_out <= '1';
						state <= idle;
				end case;
			end if;
		end if;
	end process;

end architecture;
