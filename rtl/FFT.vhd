
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity FFT is
	Port (
	clock_in : in std_logic; --100MHz
	reset_in : in std_logic;
	ready_out : out std_logic;
	start_in : in std_logic;
	mem_addr_in : in std_logic_vector(7 downto 0);
	mem_data_out : out std_logic_vector(31 downto 0);
	window_addr_out : out std_logic_vector(8 downto 0);
	window_data_in : in std_logic_vector(19 downto 0)
	);
end FFT;

architecture Behavioral of FFT is

		--- architecture signals ---

		--- fft IP and signals ---
	component xfft_0 is 
		port (
			aclk : in std_logic;
			s_axis_config_tdata : in std_logic_vector(7 downto 0);
			s_axis_config_tvalid : in std_logic;
			s_axis_config_tready : out std_logic;
			s_axis_data_tdata : in std_logic_vector(47 downto 0);
			s_axis_data_tvalid : in std_logic;
			s_axis_data_tready : out std_logic;
			s_axis_data_tlast : in std_logic;
			m_axis_data_tdata : out std_logic_vector(63 downto 0);
			m_axis_data_tvalid : out std_logic;
			m_axis_data_tlast : out std_logic;
			event_frame_started : out std_logic;
			event_tlast_unexpected : out std_logic;
			event_tlast_missing : out std_logic;
			event_data_in_channel_halt : out std_logic
			);
	end component;
	
	signal sc_tdata : std_logic_vector(7 downto 0) := (others => '0');
	signal sc_tvalid : std_logic := '0';
	signal sc_tready : std_logic := '0';
	
	signal sd_tdata : std_logic_vector(47 downto 0) := (others => '0');
	signal sd_tvalid : std_logic := '0';
	signal sd_tready : std_logic := '0';
	signal sd_tlast : std_logic := '0';
	
	signal md_tdata : std_logic_vector(63 downto 0) := (others => '0');
	signal md_tvalid : std_logic;
	signal md_tlast : std_logic := '0';
	
	signal ev_frame : std_logic := '0';
	signal ev_tlast_missing : std_logic := '0';
	signal ev_tlast_unexpected : std_logic := '0';
	signal ev_channel_stuck : std_logic := '0';
	
		--- mult_real IP and signals ---
	component mult_gen_1 is
		port (
			clk : in std_logic;
			A : in std_logic_vector(29 downto 0);
			B : in std_logic_vector(29 downto 0);
			P : out std_logic_vector(59 downto 0)
			);
	end component;
	
	signal real_latch : std_logic_vector(29 downto 0);
	signal real_p: std_logic_vector(59 downto 0);


		--- mult_imag IP and signals ---
	component mult_gen_2 is
		port (
			clk : in std_logic;
			A : in std_logic_vector(29 downto 0);
			B : in std_logic_vector(29 downto 0);
			P : out std_logic_vector(59 downto 0)
			);
	end component;
	
	signal imag_p: std_logic_vector(59 downto 0);
	signal imag_latch : std_logic_vector(29 downto 0);
	
		--- ram IP and signals ---
	component blk_mem_gen_4 is
		port (
			clka : in std_logic;
			wea : in std_logic_vector(0 downto 0);
			addra : in std_logic_vector(7 downto 0);
			dina : in std_logic_vector(31 downto 0);
			clkb : in std_logic;
			addrb : in std_logic_vector(7 downto 0);
			doutb : out std_logic_vector(31 downto 0)
			);
	end component;
	
	signal write_enable: std_logic_vector(0 downto 0) := "0";
	signal widx : integer := 0;
	signal ram_idx: integer := 0;
	signal idx: integer := 0;
	signal cnt: integer := 0;
	signal in_idx: integer := 0;
	signal load_delay: integer range 0 to 2 := 0;
	signal data_final: std_logic_vector(31 downto 0); -- truncated sum
	signal window_data : std_logic_vector(19 downto 0);
	signal window_skid_data : std_logic_vector(19 downto 0) := (others => '0');
	signal window_skid_valid : std_logic := '0';
		signal ram_addr_slv : std_logic_vector(7 downto 0);
		-- The FFT sample first crosses real_latch/imag_latch, then the two
		-- multiplier IPs add six registered stages.  A magnitude observed on
		-- output event k + POWER_RESULT_DELAY therefore belongs to FFT bin k.
		-- The BRAM write happens one clock later, but its registered address and
		-- data advance together and do not add another bin-index offset.
		constant MULTIPLIER_LATENCY : integer := 6;
		constant POWER_RESULT_DELAY : integer := MULTIPLIER_LATENCY + 1;
	
	type fsm is (idle, set_config, load_input, get_output, done);
	signal state : fsm := idle;
	
begin


window_addr_out <= std_logic_vector(to_unsigned(widx, 9));
window_data <= window_data_in;
ram_addr_slv <= std_logic_vector(to_unsigned(ram_idx, 8));



fft : xfft_0
	port map (
		aclk                    => clock_in,
		s_axis_config_tdata     => sc_tdata,
		s_axis_config_tvalid    => sc_tvalid,
		s_axis_config_tready    => sc_tready,
		
		s_axis_data_tdata       => sd_tdata,
		s_axis_data_tvalid      => sd_tvalid,
		s_axis_data_tready      => sd_tready,
		s_axis_data_tlast       => sd_tlast,
		
		m_axis_data_tdata       => md_tdata,
		m_axis_data_tvalid      => md_tvalid,
		m_axis_data_tlast       => md_tlast,
		event_frame_started     => ev_frame,
		event_tlast_unexpected  => ev_tlast_unexpected,
		event_tlast_missing     => ev_tlast_missing,
		event_data_in_channel_halt => ev_channel_stuck
	);

mul_real : mult_gen_1
	port map (
		clk => clock_in,
		A   => real_latch,
		B   => real_latch,
		P   => real_p
	);

mul_imag : mult_gen_2
	port map (
		clk => clock_in,
		A   => imag_latch,
		B   => imag_latch,
		P   => imag_p
	);

ram : blk_mem_gen_4
	port map (
		clka  => clock_in,
		wea   => write_enable,
		addra => ram_addr_slv,
		dina  => data_final,
		clkb  => clock_in,
		addrb => mem_addr_in,
		doutb => mem_data_out
	);

	
	
process(clock_in)
	variable mag_next : unsigned(60 downto 0);
begin
	if rising_edge(clock_in) then
		if reset_in = '1' then
			ready_out <= '1';
			write_enable <= "0";
			sc_tdata <= (others => '0');
			sc_tvalid <= '0';
			sd_tdata <= (others => '0');
			sd_tvalid <= '0';
			sd_tlast <= '0';
			real_latch <= (others => '0');
			imag_latch <= (others => '0');
			widx <= 0;
			ram_idx <= 0;
			idx <= 0;
			in_idx <= 0;
				load_delay <= 0;
				window_skid_data <= (others => '0');
				window_skid_valid <= '0';
				cnt <= 0;
			data_final <= (others => '0');
			state <= idle;
		else
			write_enable <= "0";
			case state is
			when idle =>
				if start_in = '1' then 
					state <= set_config;
					ready_out <= '0';
				else
					ready_out <= '1';
					widx <= 0;
					ram_idx <= 0;
					idx <= 0;
					in_idx <= 0;
						load_delay <= 0;
						window_skid_valid <= '0';
						cnt <= 0;
					sd_tvalid <= '0';
					sd_tlast <= '0';
				end if;
			
			when set_config =>
				sc_tdata(0) <= '1';
				sc_tvalid <= '1';
				sd_tvalid <= '0';
				sd_tlast <= '0';
				if sc_tvalid = '1' and sc_tready = '1' then
					sc_tvalid <= '0';
					sd_tvalid <= '0';
					widx <= 0;
						in_idx <= 0;
						load_delay <= 0;
						window_skid_valid <= '0';
						state <= load_input;
				end if;
					
					when load_input =>
						-- xfft_0 uses the Real-Time throttle scheme, so once TVALID is
						-- asserted the complete frame must be presented on consecutive
						-- clocks.  Port B of the WINDOW BRAM is synchronous.  Prime its
						-- address pipeline with samples 0 and 1, then request sample k+2
						-- while sample k is accepted.  This streams samples 0..511 exactly
						-- once without starving the FFT input channel.
						if load_delay = 0 then
							sd_tvalid <= '0';
							sd_tlast <= '0';
							widx <= 1;
							load_delay <= 1;
						elsif load_delay = 1 then
							sd_tdata(19 downto 0) <= window_data;
							sd_tdata(23 downto 20) <= (others => window_data(19));
							sd_tdata(47 downto 24) <= (others => '0');
							sd_tvalid <= '1';
							sd_tlast <= '0';
							widx <= 2;
							load_delay <= 2;
						elsif sd_tready = '1' then
							if in_idx = 511 then
								sd_tvalid <= '0';
								sd_tlast <= '0';
								window_skid_valid <= '0';
								idx <= 0;
								ram_idx <= 0;
								state <= get_output;
							else
								in_idx <= in_idx + 1;
								if window_skid_valid = '1' then
									sd_tdata(19 downto 0) <= window_skid_data;
									sd_tdata(23 downto 20) <= (others => window_skid_data(19));
									window_skid_valid <= '0';
								else
									sd_tdata(19 downto 0) <= window_data;
									sd_tdata(23 downto 20) <= (others => window_data(19));
								end if;
								sd_tdata(47 downto 24) <= (others => '0');
								if in_idx = 510 then
									sd_tlast <= '1';
								else
									sd_tlast <= '0';
								end if;
								if widx < 511 then
									widx <= widx + 1;
								end if;
							end if;
						elsif window_skid_valid = '0' then
							-- A one-cycle TREADY stall lets the already-issued BRAM read
							-- advance.  Preserve that response here while holding the
							-- address; it is consumed before the held BRAM response when
							-- handshaking resumes.
							window_skid_data <= window_data;
							window_skid_valid <= '1';
						end if;
					
			when get_output =>
				if md_tvalid = '1' then
					if idx < 256 then
						real_latch <= md_tdata(29 downto 0);
						imag_latch <= md_tdata(61 downto 32);
					end if;

					-- Store bins 0..255 at identically numbered RAM addresses.
					-- idx = POWER_RESULT_DELAY is the squared result for FFT bin 0.
					if idx >= POWER_RESULT_DELAY and idx <= POWER_RESULT_DELAY + 255 then
						mag_next := ('0' & unsigned(imag_p)) + ('0' & unsigned(real_p));
						data_final <= std_logic_vector(mag_next(60 downto 29));
						ram_idx <= idx - POWER_RESULT_DELAY;
						write_enable <= "1";
						if idx = POWER_RESULT_DELAY + 255 then
							state <= done;
						end if;
					end if;

					if idx < POWER_RESULT_DELAY + 255 then
						idx <= idx + 1;
					end if;
				end if;
			
			when done =>
				write_enable <= "0";
				if cnt = 3 then
					state <= idle;
				else
					cnt <= cnt + 1;
				end if;
			end case;
		end if;
	end if;
end process;


end Behavioral;
