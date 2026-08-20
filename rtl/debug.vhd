library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity debug is
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
end entity;

architecture Behavioral of debug is

	constant BAUD_DIV   : natural := CLK_HZ / BAUD_RATE;
	constant ADC_LEN    : integer := 512;
	constant WINDOW_LEN : integer := 512;
	constant FFT_LEN    : integer := 256;
	constant MEL_LEN    : integer := 32;
	constant LOGMEL_LEN : integer := 32;
	constant DCT_LEN    : integer := 8;

	type state_t is (
		IDLE,
		WAIT_DATA,
		LOAD_BYTE,
		UART_START,
		UART_DATA,
		UART_STOP,
		AFTER_WORD
	);

	type item_t is (
		FRAME_MARK_WORD,
		FRAME_ADDR_WORD,
		COMP_INFO_WORD,
		ADC_MARK_WORD,
		ADC_DATA_WORD,
		WINDOW_MARK_WORD,
		WINDOW_DATA_WORD,
		FFT_MARK_WORD,
		FFT_DATA_WORD,
		MEL_MARK_WORD,
		MEL_DATA_WORD,
		LOGMEL_MARK_WORD,
		LOGMEL_DATA_WORD,
		DCT_MARK_WORD,
		DCT_DATA_WORD,
		END_MARK_WORD
	);

	signal state      : state_t := IDLE;
	signal item       : item_t := FRAME_MARK_WORD;
	signal data_idx   : integer range 0 to 511 := 0;
	signal read_wait  : natural range 0 to READ_WAIT_CYCLES := 0;
	signal baud_count : natural range 0 to BAUD_DIV - 1 := 0;
	signal bit_idx    : integer range 0 to 7 := 0;
	signal byte_idx   : integer range 0 to 3 := 0;
	signal word_reg   : std_logic_vector(31 downto 0) := (others => '0');
	signal byte_reg   : std_logic_vector(7 downto 0) := (others => '0');
	signal txd_reg    : std_logic := '1';

begin

	txd_out <= txd_reg;
	ready_out <= '1' when state = IDLE else '0';
	active_out <= '0' when state = IDLE else '1';

	adc_addr_out <= std_logic_vector(unsigned(frame_addr_in) + to_unsigned(data_idx, 14))
		when item = ADC_DATA_WORD else (others => '0');

	window_addr_out <= std_logic_vector(to_unsigned(data_idx, 9))
		when item = WINDOW_DATA_WORD else (others => '0');

	fft_addr_out <= std_logic_vector(to_unsigned(data_idx, 8))
		when item = FFT_DATA_WORD else (others => '0');

	mel_addr_out <= std_logic_vector(to_unsigned(data_idx, 5))
		when item = MEL_DATA_WORD else (others => '0');

	logmel_addr_out <= std_logic_vector(to_unsigned(data_idx, 5))
		when item = LOGMEL_DATA_WORD else (others => '0');

	dct_addr_out <= std_logic_vector(to_unsigned(data_idx, 3))
		when item = DCT_DATA_WORD else (others => '0');

	process(clock_in)
	begin
		if rising_edge(clock_in) then
			if reset_in = '1' then
				state <= IDLE;
				item <= FRAME_MARK_WORD;
				data_idx <= 0;
				read_wait <= 0;
				baud_count <= 0;
				bit_idx <= 0;
				byte_idx <= 0;
				word_reg <= (others => '0');
				byte_reg <= (others => '0');
				txd_reg <= '1';
			else
				case state is
					when IDLE =>
						txd_reg <= '1';
						baud_count <= 0;
						read_wait <= 0;
						data_idx <= 0;
						byte_idx <= 0;
						if start_in = '1' then
							item <= FRAME_MARK_WORD;
							state <= WAIT_DATA;
						end if;

					when WAIT_DATA =>
						if read_wait < READ_WAIT_CYCLES then
							read_wait <= read_wait + 1;
						else
							case item is
								when FRAME_MARK_WORD  => word_reg <= x"AABBCC00";
								when FRAME_ADDR_WORD  => word_reg <= std_logic_vector(resize(unsigned(frame_addr_in), 32));
								when COMP_INFO_WORD   => word_reg <= x"000000" & mode_record_in & comp_valid_in & comp_record_in & comp_digit_idx3_patch_in & comp_digit_in;
								when ADC_MARK_WORD    => word_reg <= x"AABBCC01";
								when ADC_DATA_WORD    => word_reg <= x"00000" & adc_data_in;
								when WINDOW_MARK_WORD => word_reg <= x"AABBCC02";
								when WINDOW_DATA_WORD => word_reg <= x"000" & window_data_in;
								when FFT_MARK_WORD    => word_reg <= x"AABBCC03";
								when FFT_DATA_WORD    => word_reg <= fft_data_in;
								when MEL_MARK_WORD    => word_reg <= x"AABBCC04";
								when MEL_DATA_WORD    => word_reg <= mel_data_in;
								when LOGMEL_MARK_WORD => word_reg <= x"AABBCC05";
								when LOGMEL_DATA_WORD => word_reg <= logmel_data_in;
								when DCT_MARK_WORD    => word_reg <= x"AABBCC06";
								when DCT_DATA_WORD    => word_reg <= x"0000" & dct_data_in;
								when END_MARK_WORD    => word_reg <= x"AA5503CC";
							end case;
							byte_idx <= 0;
							state <= LOAD_BYTE;
						end if;

					when LOAD_BYTE =>
						case byte_idx is
							when 0      => byte_reg <= word_reg(31 downto 24);
							when 1      => byte_reg <= word_reg(23 downto 16);
							when 2      => byte_reg <= word_reg(15 downto 8);
							when others => byte_reg <= word_reg(7 downto 0);
						end case;
						bit_idx <= 0;
						baud_count <= 0;
						txd_reg <= '0';
						state <= UART_START;

					when UART_START =>
						if baud_count = BAUD_DIV - 1 then
							baud_count <= 0;
							txd_reg <= byte_reg(0);
							bit_idx <= 0;
							state <= UART_DATA;
						else
							baud_count <= baud_count + 1;
						end if;

					when UART_DATA =>
						if baud_count = BAUD_DIV - 1 then
							baud_count <= 0;
							if bit_idx = 7 then
								txd_reg <= '1';
								state <= UART_STOP;
							else
								bit_idx <= bit_idx + 1;
								txd_reg <= byte_reg(bit_idx + 1);
							end if;
						else
							baud_count <= baud_count + 1;
						end if;

					when UART_STOP =>
						if baud_count = BAUD_DIV - 1 then
							baud_count <= 0;
							txd_reg <= '1';
							if byte_idx = 3 then
								state <= AFTER_WORD;
							else
								byte_idx <= byte_idx + 1;
								state <= LOAD_BYTE;
							end if;
						else
							baud_count <= baud_count + 1;
						end if;

					when AFTER_WORD =>
						read_wait <= 0;
						case item is
							when FRAME_MARK_WORD =>
								item <= FRAME_ADDR_WORD;
								state <= WAIT_DATA;

							when FRAME_ADDR_WORD =>
								item <= COMP_INFO_WORD;
								state <= WAIT_DATA;

							when COMP_INFO_WORD =>
								item <= ADC_MARK_WORD;
								state <= WAIT_DATA;

							when ADC_MARK_WORD =>
								data_idx <= 0;
								item <= ADC_DATA_WORD;
								state <= WAIT_DATA;

							when ADC_DATA_WORD =>
								if data_idx = ADC_LEN - 1 then
									data_idx <= 0;
									item <= WINDOW_MARK_WORD;
								else
									data_idx <= data_idx + 1;
								end if;
								state <= WAIT_DATA;

							when WINDOW_MARK_WORD =>
								data_idx <= 0;
								item <= WINDOW_DATA_WORD;
								state <= WAIT_DATA;

							when WINDOW_DATA_WORD =>
								if data_idx = WINDOW_LEN - 1 then
									data_idx <= 0;
									item <= FFT_MARK_WORD;
								else
									data_idx <= data_idx + 1;
								end if;
								state <= WAIT_DATA;

							when FFT_MARK_WORD =>
								data_idx <= 0;
								item <= FFT_DATA_WORD;
								state <= WAIT_DATA;

							when FFT_DATA_WORD =>
								if data_idx = FFT_LEN - 1 then
									data_idx <= 0;
									item <= MEL_MARK_WORD;
								else
									data_idx <= data_idx + 1;
								end if;
								state <= WAIT_DATA;

							when MEL_MARK_WORD =>
								data_idx <= 0;
								item <= MEL_DATA_WORD;
								state <= WAIT_DATA;

							when MEL_DATA_WORD =>
								if data_idx = MEL_LEN - 1 then
									data_idx <= 0;
									item <= LOGMEL_MARK_WORD;
								else
									data_idx <= data_idx + 1;
								end if;
								state <= WAIT_DATA;

							when LOGMEL_MARK_WORD =>
								data_idx <= 0;
								item <= LOGMEL_DATA_WORD;
								state <= WAIT_DATA;

							when LOGMEL_DATA_WORD =>
								if data_idx = LOGMEL_LEN - 1 then
									data_idx <= 0;
									item <= DCT_MARK_WORD;
								else
									data_idx <= data_idx + 1;
								end if;
								state <= WAIT_DATA;

							when DCT_MARK_WORD =>
								data_idx <= 0;
								item <= DCT_DATA_WORD;
								state <= WAIT_DATA;

							when DCT_DATA_WORD =>
								if data_idx = DCT_LEN - 1 then
									data_idx <= 0;
									item <= END_MARK_WORD;
								else
									data_idx <= data_idx + 1;
								end if;
								state <= WAIT_DATA;

							when END_MARK_WORD =>
								state <= IDLE;
						end case;
				end case;
			end if;
		end if;
	end process;

end Behavioral;
