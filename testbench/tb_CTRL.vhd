library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;

entity tb_CTRL is
end entity;

architecture sim of tb_CTRL is
	constant CLK_PERIOD : time := 10 ns;

	signal clock_in : std_logic := '0';
	signal reset_in : std_logic := '1';
	signal start_in : std_logic := '0';

	signal adcdone   : std_logic;
	signal adcbusy   : std_logic;
	signal ready_out : std_logic;

	signal start_adc    : std_logic;
	signal ready_adc    : std_logic := '1';
	signal frame_addr   : std_logic_vector(13 downto 0);
	signal start_window : std_logic;
	signal ready_window : std_logic := '1';
	signal start_fft    : std_logic;
	signal ready_fft    : std_logic := '1';
	signal start_mel    : std_logic;
	signal ready_mel    : std_logic := '1';
	signal start_logmel : std_logic;
	signal ready_logmel : std_logic := '1';
		signal start_dct    : std_logic;
		signal ready_dct    : std_logic := '1';
		signal start_comp   : std_logic;
		signal ready_comp   : std_logic := '1';
		signal start_debug  : std_logic;
		signal ready_debug  : std_logic := '1';
		signal debug_enable_in : std_logic := '1';
		signal digit_sw_in  : std_logic_vector(9 downto 0) := "0000000001";
		signal trial_inc_in : std_logic := '0';
		signal trial_dec_in : std_logic := '0';
		signal selected_digit : std_logic_vector(4 downto 0);
		signal selected_trial : std_logic_vector(2 downto 0);

	procedure pulse_ready(
		signal ready_sig : out std_logic;
		constant clocks  : in natural
	) is
	begin
		wait until rising_edge(clock_in);
		ready_sig <= '0';
		for i in 0 to clocks - 1 loop
			wait until rising_edge(clock_in);
		end loop;
		ready_sig <= '1';
	end procedure;

begin

	clock_gen : process
	begin
		while true loop
			clock_in <= '0';
			wait for CLK_PERIOD / 2;
			clock_in <= '1';
			wait for CLK_PERIOD / 2;
		end loop;
	end process;

	dut : entity work.CTRL
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
				start_in         => start_in,
				ready_out        => ready_out,
				digit_sw_in      => digit_sw_in,
				trial_inc_in     => trial_inc_in,
				trial_dec_in     => trial_dec_in,
				selected_digit_out => selected_digit,
				selected_trial_out => selected_trial
			);

	stage_model : process
	begin
		ready_adc <= '1';
		ready_window <= '1';
		ready_fft <= '1';
		ready_mel <= '1';
		ready_logmel <= '1';
			ready_dct <= '1';
			ready_comp <= '1';
			ready_debug <= '1';
			wait until reset_in = '0';

		loop
			wait until rising_edge(clock_in);
			if start_adc = '1' then
				pulse_ready(ready_adc, 4);
			elsif start_window = '1' then
				pulse_ready(ready_window, 4);
			elsif start_fft = '1' then
				pulse_ready(ready_fft, 4);
			elsif start_mel = '1' then
				pulse_ready(ready_mel, 4);
			elsif start_logmel = '1' then
				pulse_ready(ready_logmel, 4);
			elsif start_dct = '1' then
				pulse_ready(ready_dct, 4);
				elsif start_comp = '1' then
					pulse_ready(ready_comp, 4);
				elsif start_debug = '1' then
					pulse_ready(ready_debug, 4);
				end if;
			end loop;
	end process;

	stim : process
		file ref_file : text open read_mode is "../../../../verification/ref_data/tb_ctrl_ref.txt";
		file dump_file : text open write_mode is "../../../../verification/tb_output/tb_ctrl_output.txt";
		variable L : line;
		variable frames_to_check_v : integer;
		variable debug_enable_v : integer;
		variable event_idx_v : integer := 0;

		procedure write_event(constant stage_id : in integer) is
		begin
			write(L, event_idx_v);
			write(L, string'(" "));
			write(L, to_integer(unsigned(frame_addr)));
			write(L, string'(" "));
			write(L, stage_id);
			writeline(dump_file, L);
			event_idx_v := event_idx_v + 1;
		end procedure;
	begin
		while not endfile(ref_file) loop
			readline(ref_file, L);
			read(L, frames_to_check_v);
			read(L, debug_enable_v);

			if debug_enable_v = 1 then
				debug_enable_in <= '1';
			else
				debug_enable_in <= '0';
			end if;

			reset_in <= '1';
			start_in <= '0';
			wait for 200 ns;
			reset_in <= '0';

			wait until rising_edge(clock_in);
			start_in <= '1';
			wait until rising_edge(clock_in);
			start_in <= '0';

			wait until rising_edge(clock_in) and start_adc = '1';
			write_event(0);

			for f in 0 to frames_to_check_v - 1 loop
				wait until rising_edge(clock_in) and start_window = '1';
				write_event(1);
				wait until rising_edge(clock_in) and start_fft = '1';
				write_event(2);
				wait until rising_edge(clock_in) and start_mel = '1';
				write_event(3);
				wait until rising_edge(clock_in) and start_logmel = '1';
				write_event(4);
				wait until rising_edge(clock_in) and start_dct = '1';
				write_event(5);
				wait until rising_edge(clock_in) and start_comp = '1';
				write_event(6);
				if debug_enable_v = 1 then
					wait until rising_edge(clock_in) and start_debug = '1';
					write_event(7);
				end if;
			end loop;

			if ready_out /= '1' then
				wait until ready_out = '1';
			end if;
			wait for 10 * CLK_PERIOD;
		end loop;

		finish;
	end process;

end architecture;
