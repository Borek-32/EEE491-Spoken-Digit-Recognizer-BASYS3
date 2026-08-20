library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity comp is
    port (
        reset_in        : in  std_logic;
        clock_in        : in  std_logic;
        clear_in        : in  std_logic;
        start_in        : in  std_logic;
        ready_out       : out std_logic;

        selected_digit_in : in  std_logic_vector(4 downto 0);
        selected_trial_in : in  std_logic_vector(2 downto 0);
        mode_record_in    : in  std_logic;
        record_out        : out std_logic;
        flush             : in  std_logic;
        flush_done        : out std_logic;

        dct_addr_out    : out std_logic_vector(2 downto 0);
        dct_data_in     : in  std_logic_vector(15 downto 0);
        mel_addr_out    : out std_logic_vector(4 downto 0);
        mel_data_in     : in  std_logic_vector(31 downto 0);

        digit_out       : out std_logic_vector(3 downto 0);
        valid_out       : out std_logic;
        digit_idx3_patch : out std_logic
    );
end entity;

architecture behavioral of comp is

    -- Runtime record/compare version of the root COMP algorithm.
    -- The comparison metric is SAD / L1 distance:
    -- D(r,w) = sum_{j=0}^{15} sum_{k=0}^{7} |u[w+j][k] - ref[r][j][k]|.
    -- The selected speech window is still the root rule:
    -- active_start = first i where energy[i] > max(energy) / 8.

    constant TOTAL_FRAMES       : integer := 63;
    constant UTTERANCE_DEPTH    : integer := 64;
    constant WINDOW_FRAMES      : integer := 16;
    constant WINDOW_STARTS      : integer := TOTAL_FRAMES - WINDOW_FRAMES + 1;
    constant REF_COUNT          : integer := 30;
    constant REF_DEPTH          : integer := 512;
    constant COEFF_COUNT        : integer := 8;
    constant MEL_BINS           : integer := 32;
    constant TRIALS_PER_DIGIT   : integer := 3;
    constant BRAM_READ_WAIT     : integer := 6;
    constant DCT_OWNERSHIP_WAIT : integer := 6;
    constant DCT_READ_WAIT      : integer := 8;
    constant MEL_READ_WAIT      : integer := 6;

    subtype coeff16_t is signed(15 downto 0);
    subtype ref5_t is std_logic_vector(4 downto 0);
    subtype digit4_t is std_logic_vector(3 downto 0);
    subtype distance_t is unsigned(63 downto 0);

    type ref5_array_t is array (0 to WINDOW_STARTS - 1) of ref5_t;
    type digit4_array_t is array (0 to WINDOW_STARTS - 1) of digit4_t;
    type idx3_array_t is array (0 to WINDOW_STARTS - 1) of std_logic;
    type energy_array_t is array (0 to TOTAL_FRAMES - 1) of distance_t;

    component blk_mem_gen_comp_utterance_ram is
        port (
            clka  : in  std_logic;
            wea   : in  std_logic_vector(0 downto 0);
            addra : in  std_logic_vector(5 downto 0);
            dina  : in  std_logic_vector(127 downto 0);
            clkb  : in  std_logic;
            addrb : in  std_logic_vector(5 downto 0);
            doutb : out std_logic_vector(127 downto 0)
        );
    end component;

    component blk_mem_gen_comp_ref_ram is
        port (
            clka  : in  std_logic;
            wea   : in  std_logic_vector(0 downto 0);
            addra : in  std_logic_vector(8 downto 0);
            dina  : in  std_logic_vector(127 downto 0);
            clkb  : in  std_logic;
            addrb : in  std_logic_vector(8 downto 0);
            doutb : out std_logic_vector(127 downto 0)
        );
    end component;

    type fsm_t is (
        idle,
        capture_claim,
        mel_set_addr,
        mel_wait,
        mel_add,
        capture_set_addr,
        capture_wait,
        capture_store,
        write_utterance,
        compare_set_addr,
        compare_wait,
        compare_latch,
        coeff_add,
        finish_frame,
        finish_ref,
        store_window,
        finish_utterance,
        select_output,
        record_set_addr,
        record_wait,
        record_write,
        record_next,
        record_done
    );

    type flush_fsm_t is (
        flush_idle,
        flush_write
    );

    signal state : fsm_t := idle;
    signal flush_state : flush_fsm_t := flush_idle;

    signal frame_count       : integer range 0 to TOTAL_FRAMES - 1 := 0;
    signal mel_idx           : integer range 0 to MEL_BINS - 1 := 0;
    signal cap_idx           : integer range 0 to COEFF_COUNT - 1 := 0;
    signal wait_count        : integer range 0 to DCT_READ_WAIT := 0;
    signal current_frame     : std_logic_vector(127 downto 0) := (others => '0');

    signal ref_idx           : integer range 0 to REF_COUNT - 1 := 0;
    signal ref_frame_idx     : integer range 0 to WINDOW_FRAMES - 1 := 0;
    signal coeff_idx         : integer range 0 to COEFF_COUNT - 1 := 0;
    signal frame_in          : std_logic_vector(127 downto 0) := (others => '0');
    signal frame_ref         : std_logic_vector(127 downto 0) := (others => '0');

    signal pair_sum          : distance_t := (others => '0');
    signal ref_dist          : distance_t := (others => '0');
    signal best_dist         : distance_t := (others => '1');
    signal best_ref          : integer range 0 to REF_COUNT - 1 := 0;

    signal mel_energy_sum    : distance_t := (others => '0');
    signal max_mel_energy    : distance_t := (others => '0');
    signal energy_by_frame   : energy_array_t := (others => (others => '0'));

    signal safe_ref          : ref5_array_t := (others => (others => '0'));
    signal safe_digit        : digit4_array_t := (others => (others => '0'));
    signal safe_idx3         : idx3_array_t := (others => '0');
    signal active_start      : integer range 0 to WINDOW_STARTS - 1 := 0;
    signal digit_idx3_reg    : std_logic := '0';

    signal dct_addr          : std_logic_vector(2 downto 0) := (others => '0');
    signal mel_addr          : std_logic_vector(4 downto 0) := (others => '0');

    signal utt_we            : std_logic_vector(0 downto 0) := "0";
    signal utt_wr_addr       : std_logic_vector(5 downto 0) := (others => '0');
    signal utt_rd_addr       : std_logic_vector(5 downto 0) := (others => '0');
    signal utt_din           : std_logic_vector(127 downto 0) := (others => '0');
    signal utt_dout          : std_logic_vector(127 downto 0);

    signal ref_we_main       : std_logic_vector(0 downto 0) := "0";
    signal ref_wr_addr_main  : std_logic_vector(8 downto 0) := (others => '0');
    signal ref_rd_addr       : std_logic_vector(8 downto 0) := (others => '0');
    signal ref_din_main      : std_logic_vector(127 downto 0) := (others => '0');
    signal ref_dout          : std_logic_vector(127 downto 0);
    signal ref_we_to_ram     : std_logic_vector(0 downto 0) := "0";
    signal ref_wr_addr_to_ram : std_logic_vector(8 downto 0) := (others => '0');
    signal ref_din_to_ram    : std_logic_vector(127 downto 0) := (others => '0');

    signal flush_we          : std_logic_vector(0 downto 0) := "0";
    signal flush_addr        : integer range 0 to REF_DEPTH - 1 := 0;
    signal flush_wr_addr     : std_logic_vector(8 downto 0) := (others => '0');
    signal flush_din         : std_logic_vector(127 downto 0) := (others => '0');
    signal flush_meta        : std_logic := '0';
    signal flush_sync        : std_logic := '0';
    signal flush_prev        : std_logic := '0';
    signal flush_done_reg    : std_logic := '0';

    signal record_idx        : integer range 0 to WINDOW_FRAMES - 1 := 0;
    signal selected_ref      : integer range 0 to 127 := 0;

    function coeff_at(frame : std_logic_vector(127 downto 0); idx : integer) return coeff16_t is
        variable hi : integer;
    begin
        hi := 127 - (idx * 16);
        return signed(frame(hi downto hi - 15));
    end function;

begin

    dct_addr_out <= dct_addr;
    mel_addr_out <= mel_addr;
    digit_idx3_patch <= digit_idx3_reg;
    flush_done <= flush_done_reg;
    flush_wr_addr <= std_logic_vector(to_unsigned(flush_addr, 9));
    flush_din <= (others => '0');

    -- Port A has one explicit owner.  top_module admits the flush request only
    -- while the complete controller is ready; the checks below also require
    -- the COMP FSM to be at its run boundary.  A record write therefore never
    -- advances while a maintenance write owns the RAM port.
    ref_we_to_ram <= flush_we when flush_we = "1" else ref_we_main;
    ref_wr_addr_to_ram <= flush_wr_addr when flush_we = "1" else ref_wr_addr_main;
    ref_din_to_ram <= flush_din when flush_we = "1" else ref_din_main;

    -- Reference index format is identical to the old COE/ROM format:
    -- ref = digit * 3 + trial. Therefore recognition still uses digit = best_ref / 3.
    selected_ref <= (to_integer(unsigned(selected_digit_in)) * TRIALS_PER_DIGIT) +
                    to_integer(unsigned(selected_trial_in));

    utterance_ram : blk_mem_gen_comp_utterance_ram
        port map (
            clka  => clock_in,
            wea   => utt_we,
            addra => utt_wr_addr,
            dina  => utt_din,
            clkb  => clock_in,
            addrb => utt_rd_addr,
            doutb => utt_dout
        );

    ref_ram : blk_mem_gen_comp_ref_ram
        port map (
            clka  => clock_in,
            wea   => ref_we_to_ram,
            addra => ref_wr_addr_to_ram,
            dina  => ref_din_to_ram,
            clkb  => clock_in,
            addrb => ref_rd_addr,
            doutb => ref_dout
        );

    process(clock_in)
    begin
        if rising_edge(clock_in) then
            if reset_in = '1' then
                flush_state <= flush_idle;
                flush_we <= "0";
                flush_addr <= 0;
                flush_meta <= '0';
                flush_sync <= '0';
                flush_prev <= '0';
                flush_done_reg <= '0';
            else
                flush_meta <= flush;
                flush_sync <= flush_meta;
                flush_prev <= flush_sync;

                case flush_state is
                    when flush_idle =>
                        flush_we <= "0";

                        if flush_sync = '1' and flush_prev = '0' and
                           state = idle and frame_count = 0 and start_in = '0' then
                            flush_we <= "1";
                            flush_addr <= 0;
                            flush_done_reg <= '0';
                            flush_state <= flush_write;
                        end if;

                    when flush_write =>
                        flush_we <= "1";

                        if flush_addr = REF_DEPTH - 1 then
                            flush_we <= "0";
                            flush_addr <= 0;
                            flush_done_reg <= '1';
                            flush_state <= flush_idle;
                        else
                            flush_addr <= flush_addr + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    process(clock_in)
        variable pair_sum_v     : distance_t;
        variable ref_dist_v     : distance_t;
        variable best_dist_v    : distance_t;
        variable best_ref_v     : integer range 0 to REF_COUNT - 1;
        variable mel_energy_v   : distance_t;
        variable max_mel_v      : distance_t;
        variable threshold_v    : distance_t;
        variable active_v       : integer range 0 to WINDOW_STARTS - 1;
        variable found_v        : boolean;
        variable diff_v         : signed(16 downto 0);
        variable abs_diff_v     : unsigned(16 downto 0);
        variable window_start_v : integer range 0 to WINDOW_STARTS - 1;
        variable abs_frame_v    : integer range 0 to TOTAL_FRAMES - 1;
        variable ref_addr_v     : integer range 0 to REF_DEPTH - 1;
    begin
        if rising_edge(clock_in) then
            if reset_in = '1' or clear_in = '1' then
                state <= idle;
                frame_count <= 0;
                mel_idx <= 0;
                cap_idx <= 0;
                wait_count <= 0;
                current_frame <= (others => '0');
                ref_idx <= 0;
                ref_frame_idx <= 0;
                coeff_idx <= 0;
                frame_in <= (others => '0');
                frame_ref <= (others => '0');
                pair_sum <= (others => '0');
                ref_dist <= (others => '0');
                best_dist <= (others => '1');
                best_ref <= 0;
                mel_energy_sum <= (others => '0');
                max_mel_energy <= (others => '0');
                energy_by_frame <= (others => (others => '0'));
                safe_ref <= (others => (others => '0'));
                safe_digit <= (others => (others => '0'));
                safe_idx3 <= (others => '0');
                active_start <= 0;
                digit_idx3_reg <= '0';
                dct_addr <= (others => '0');
                mel_addr <= (others => '0');
                utt_we <= "0";
                utt_wr_addr <= (others => '0');
                utt_rd_addr <= (others => '0');
                utt_din <= (others => '0');
                ref_we_main <= "0";
                ref_wr_addr_main <= (others => '0');
                ref_rd_addr <= (others => '0');
                ref_din_main <= (others => '0');
                record_idx <= 0;
                ready_out <= '1';
                valid_out <= '0';
                record_out <= '0';
                digit_out <= x"F";
            else
                pair_sum_v := pair_sum;
                ref_dist_v := ref_dist;
                best_dist_v := best_dist;
                best_ref_v := best_ref;
                mel_energy_v := mel_energy_sum;
                max_mel_v := max_mel_energy;

                utt_we <= "0";
                ref_we_main <= "0";
                ref_wr_addr_main <= (others => '0');
                ref_din_main <= (others => '0');

                case state is

                    -- idle: wait for CTRL to start one frame transaction.
                    -- At frame 0, clear the whole 63-frame run state.
                    when idle =>
                        ready_out <= '1';

                        if start_in = '1' and flush_state = flush_idle then
                            ready_out <= '0';
                            mel_idx <= 0;
                            cap_idx <= 0;
                            wait_count <= 0;
                            current_frame <= (others => '0');
                            mel_energy_v := (others => '0');

                            if frame_count = 0 then
                                ref_idx <= 0;
                                ref_frame_idx <= 0;
                                coeff_idx <= 0;
                                pair_sum_v := (others => '0');
                                ref_dist_v := (others => '0');
                                best_dist_v := (others => '1');
                                best_ref_v := 0;
                                max_mel_v := (others => '0');
                                energy_by_frame <= (others => (others => '0'));
                                safe_ref <= (others => (others => '0'));
                                safe_digit <= (others => (others => '0'));
                                safe_idx3 <= (others => '0');
                                active_start <= 0;
                                valid_out <= '0';
                                record_out <= '0';
                                digit_out <= x"F";
                                digit_idx3_reg <= '0';
                            end if;

                            dct_addr <= (others => '0');
                            mel_addr <= (others => '0');
                            state <= capture_claim;
                        end if;

                    -- capture_claim: wait before reading DCT/MEL memories.
                    -- This preserves the original ownership delay before using upstream memories.
                    when capture_claim =>
                        dct_addr <= (others => '0');
                        mel_addr <= (others => '0');

                        if wait_count = DCT_OWNERSHIP_WAIT then
                            wait_count <= 0;
                            state <= mel_set_addr;
                        else
                            wait_count <= wait_count + 1;
                        end if;

                    -- mel_set_addr: choose MEL bin m for the current frame.
                    -- Energy contribution will be e[m] = mel_data[m].
                    when mel_set_addr =>
                        mel_addr <= std_logic_vector(to_unsigned(mel_idx, 5));
                        wait_count <= 0;
                        state <= mel_wait;

                    -- mel_wait: wait for MEL RAM latency.
                    -- No math is done here; address is held stable.
                    when mel_wait =>
                        if wait_count = MEL_READ_WAIT then
                            state <= mel_add;
                        else
                            wait_count <= wait_count + 1;
                        end if;

                    -- mel_add: accumulate frame energy.
                    -- energy[f] = sum_{m=0}^{31} mel[f][m].
                    when mel_add =>
                        mel_energy_v := mel_energy_v + resize(unsigned(mel_data_in), mel_energy_v'length);

                        if mel_idx = MEL_BINS - 1 then
                            energy_by_frame(frame_count) <= mel_energy_v;

                            if mel_energy_v > max_mel_v then
                                max_mel_v := mel_energy_v;
                            end if;

                            mel_idx <= 0;
                            state <= capture_set_addr;
                        else
                            mel_idx <= mel_idx + 1;
                            state <= mel_set_addr;
                        end if;

                    -- capture_set_addr: choose DCT coefficient k for the current frame.
                    -- The frame vector is x[f] = [c0 c1 ... c7].
                    when capture_set_addr =>
                        dct_addr <= std_logic_vector(to_unsigned(cap_idx, 3));
                        wait_count <= 0;
                        state <= capture_wait;

                    -- capture_wait: wait for DCT RAM latency.
                    -- No math is done here; address is held stable.
                    when capture_wait =>
                        if wait_count = DCT_READ_WAIT then
                            state <= capture_store;
                        else
                            wait_count <= wait_count + 1;
                        end if;

                    -- capture_store: pack 8 signed 16-bit DCT coefficients into one 128-bit word.
                    -- current_frame = c0|c1|c2|c3|c4|c5|c6|c7, same style as the COE file.
                    when capture_store =>
                        current_frame(((COEFF_COUNT - cap_idx) * 16) - 1 downto
                                      ((COEFF_COUNT - cap_idx - 1) * 16)) <= dct_data_in;

                        if cap_idx = COEFF_COUNT - 1 then
                            state <= write_utterance;
                        else
                            cap_idx <= cap_idx + 1;
                            state <= capture_set_addr;
                        end if;

                    -- write_utterance: store the complete current frame in utterance RAM.
                    -- U[f] = current_frame, where f = frame_count.
                    when write_utterance =>
                        utt_wr_addr <= std_logic_vector(to_unsigned(frame_count, 6));
                        utt_din <= current_frame;
                        utt_we <= "1";

                        if mode_record_in = '0' and frame_count >= WINDOW_FRAMES - 1 then
                            ref_idx <= 0;
                            ref_frame_idx <= 0;
                            ref_dist_v := (others => '0');
                            pair_sum_v := (others => '0');
                            best_dist_v := (others => '1');
                            best_ref_v := 0;
                            state <= compare_set_addr;
                        else
                            state <= finish_utterance;
                        end if;

                    -- compare_set_addr: read one input frame and one reference frame.
                    -- input address = w + j, where w = frame_count - 15 and j = ref_frame_idx.
                    -- reference address = r*16 + j.
                    when compare_set_addr =>
                        window_start_v := frame_count - (WINDOW_FRAMES - 1);
                        abs_frame_v := window_start_v + ref_frame_idx;
                        ref_addr_v := (ref_idx * WINDOW_FRAMES) + ref_frame_idx;

                        utt_rd_addr <= std_logic_vector(to_unsigned(abs_frame_v, 6));
                        ref_rd_addr <= std_logic_vector(to_unsigned(ref_addr_v, 9));
                        wait_count <= 0;
                        state <= compare_wait;

                    -- compare_wait: wait until utterance RAM and reference RAM outputs are valid.
                    -- This represents the BRAM read latency budget.
                    when compare_wait =>
                        if wait_count = BRAM_READ_WAIT then
                            state <= compare_latch;
                        else
                            wait_count <= wait_count + 1;
                        end if;

                    -- compare_latch: latch U[w+j] and ref[r][j].
                    -- The next state computes sum_k |U[w+j][k] - ref[r][j][k]|.
                    when compare_latch =>
                        frame_in <= utt_dout;
                        frame_ref <= ref_dout;
                        pair_sum_v := (others => '0');
                        coeff_idx <= 0;
                        state <= coeff_add;

                    -- coeff_add: accumulate SAD for one frame pair.
                    -- pair_sum = sum_{k=0}^{7} |frame_in[k] - frame_ref[k]|.
                    when coeff_add =>
                        diff_v := resize(coeff_at(frame_in, coeff_idx), diff_v'length) -
                                  resize(coeff_at(frame_ref, coeff_idx), diff_v'length);

                        if diff_v(diff_v'high) = '1' then
                            abs_diff_v := unsigned(-diff_v);
                        else
                            abs_diff_v := unsigned(diff_v);
                        end if;

                        pair_sum_v := pair_sum_v + resize(abs_diff_v, pair_sum_v'length);

                        if coeff_idx = COEFF_COUNT - 1 then
                            coeff_idx <= 0;
                            state <= finish_frame;
                        else
                            coeff_idx <= coeff_idx + 1;
                            state <= coeff_add;
                        end if;

                    -- finish_frame: add this frame-pair distance into the reference distance.
                    -- ref_dist += pair_sum, so D(r,w) grows over 16 frames.
                    when finish_frame =>
                        ref_dist_v := ref_dist_v + pair_sum_v;
                        pair_sum_v := (others => '0');

                        if ref_frame_idx = WINDOW_FRAMES - 1 then
                            state <= finish_ref;
                        else
                            ref_frame_idx <= ref_frame_idx + 1;
                            state <= compare_set_addr;
                        end if;

                    -- finish_ref: after 16 frames, compare this reference distance with the best.
                    -- best_ref = argmin_r D(r,w).
                    when finish_ref =>
                        if ref_dist_v < best_dist_v then
                            best_dist_v := ref_dist_v;
                            best_ref_v := ref_idx;
                        end if;

                        if ref_idx = REF_COUNT - 1 then
                            state <= store_window;
                        else
                            ref_idx <= ref_idx + 1;
                            ref_frame_idx <= 0;
                            ref_dist_v := (others => '0');
                            state <= compare_set_addr;
                        end if;

                    -- store_window: store the best recognition result for this possible window start.
                    -- safe_digit[w] = best_ref / 3, because every digit has 3 trials.
                    when store_window =>
                        window_start_v := frame_count - (WINDOW_FRAMES - 1);
                        safe_ref(window_start_v) <= std_logic_vector(to_unsigned(best_ref_v, 5));
                        safe_digit(window_start_v) <= std_logic_vector(to_unsigned(best_ref_v / TRIALS_PER_DIGIT, 4));

                        if best_ref_v >= 24 then
                            safe_idx3(window_start_v) <= '1';
                        else
                            safe_idx3(window_start_v) <= '0';
                        end if;

                        state <= finish_utterance;

                    -- finish_utterance: either request the next frame or, after frame 62, select active_start.
                    -- threshold = max_energy / 8 and active_start = first energy[i] > threshold.
                    when finish_utterance =>
                        if frame_count = TOTAL_FRAMES - 1 then
                            threshold_v := shift_right(max_mel_v, 3);
                            active_v := 0;
                            found_v := false;

                            for i in 0 to TOTAL_FRAMES - 1 loop
                                if (not found_v) and (energy_by_frame(i) > threshold_v) then
                                    if i >= WINDOW_STARTS then
                                        active_v := WINDOW_STARTS - 1;
                                    else
                                        active_v := i;
                                    end if;
                                    found_v := true;
                                end if;
                            end loop;

                            active_start <= active_v;

                            if mode_record_in = '1' then
                                record_idx <= 0;
                                state <= record_set_addr;
                            else
                                state <= select_output;
                            end if;
                        else
                            frame_count <= frame_count + 1;
                            state <= idle;
                            ready_out <= '1';
                        end if;

                    -- select_output: compare mode output.
                    -- Output the stored result belonging to the active-start window.
                    when select_output =>
                        valid_out <= '1';
                        record_out <= '0';
                        digit_out <= safe_digit(active_start);
                        digit_idx3_reg <= safe_idx3(active_start);

                        frame_count <= 0;
                        state <= idle;
                        ready_out <= '1';

                    -- record_set_addr: record mode reads U[active_start + i].
                    -- This copies the same 16-frame style used by the MATLAB COE generator.
                    when record_set_addr =>
                        utt_rd_addr <= std_logic_vector(to_unsigned(active_start + record_idx, 6));
                        wait_count <= 0;
                        state <= record_wait;

                    -- record_wait: wait for utterance RAM read latency before writing the reference RAM.
                    -- No math is done here; address is held stable.
                    when record_wait =>
                        if wait_count = BRAM_READ_WAIT then
                            state <= record_write;
                        else
                            wait_count <= wait_count + 1;
                        end if;

                    -- record_write: write one selected active frame into the reference RAM.
                    -- ref[selected_ref][i] = U[active_start + i].
                    when record_write =>
                        ref_wr_addr_main <= std_logic_vector(to_unsigned((selected_ref * WINDOW_FRAMES) + record_idx, 9));
                        ref_din_main <= utt_dout;
                        ref_we_main <= "1";
                        state <= record_next;

                    -- record_next: continue until all 16 frames of the selected trial are written.
                    -- i = 0..15.
                    when record_next =>
                        if record_idx = WINDOW_FRAMES - 1 then
                            state <= record_done;
                        else
                            record_idx <= record_idx + 1;
                            state <= record_set_addr;
                        end if;

                    -- record_done: record mode output.
                    -- valid_out marks completion, record_out tells CTRL this was a write operation.
                    when record_done =>
                        valid_out <= '1';
                        record_out <= '1';
                        digit_out <= selected_digit_in(3 downto 0);
                        digit_idx3_reg <= '0';

                        frame_count <= 0;
                        state <= idle;
                        ready_out <= '1';

                end case;

                pair_sum <= pair_sum_v;
                ref_dist <= ref_dist_v;
                best_dist <= best_dist_v;
                best_ref <= best_ref_v;
                mel_energy_sum <= mel_energy_v;
                max_mel_energy <= max_mel_v;
            end if;
        end if;
    end process;

end architecture;
