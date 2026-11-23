module tdl_tinylfu_policy_test #(
    parameter int DICT_SIZE = 5
) (
    output bit done
);
    timeunit 1ns;
    timeprecision 1ps;

    import tdl_tab_hash_pkg::TABLE_SEED;
    import tdl_tab_hash_pkg::mix32;

    localparam int KEY_WIDTH = $clog2(DICT_SIZE);
    localparam time CLK_PERIOD = 20ns;
    typedef logic [31:0] word_t;
    typedef logic [KEY_WIDTH-1:0] key_t;
    typedef struct packed {
        bit cu_disable;
        bit aging_disable;
        bit bf_en;
        logic [15:0] period;
    } config_t;
    typedef struct packed {
        bit hit, admit, bf_filtered, update_bf, update_cms;
        key_t key;
        logic [11:0] bf0, bf1;
        logic [7:0] cms0, cms1;
        logic [3:0] next_c0, next_c1;
    } decision_t;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic req_valid, req_ready, req_hit;
    key_t req_hit_key, next_free_key, rsp_key;
    word_t req_word;
    logic req_cu_disable, req_aging_disable, req_bf_en;
    logic [15:0] req_aging_period;
    logic [DICT_SIZE-1:0] valid_bits;
    logic dict_full;
    logic rsp_valid, rsp_ready, rsp_admit, rsp_bf_filtered, commit, aging_done;

    word_t resident [0:DICT_SIZE-1];
    int local_counts [0:DICT_SIZE-1];
    int cms_row0 [0:255], cms_row1 [0:255];
    bit [4095:0] bf_active, bf_old;
    int period_words, last_period;
    int words_checked = 0;
    int services_checked = 0;

    tdl_tinylfu_policy #(.DICT_SIZE(DICT_SIZE)) dut (.*);

    always #(CLK_PERIOD / 2) clk = ~clk;

    assign dict_full = &valid_bits;
    always_comb begin
        next_free_key = '0;
        for (int row = DICT_SIZE - 1; row >= 0; row--)
            if (!valid_bits[row])
                next_free_key = key_t'(row);
    end

    function automatic config_t settings(input bit cu_disable, input bit aging_disable,
                                         input bit bf_en, input int period);
        return {cu_disable, aging_disable, bf_en, 16'(period)};
    endfunction

    function automatic logic [11:0] ref_hash(input word_t word, input int hash_index);
        word_t mixed;
        logic [11:0] result;
        result = '0;
        for (int byte_index = 0; byte_index < 4; byte_index++) begin
            mixed = mix32(TABLE_SEED ^ ((hash_index + 1) * 32'h9E37_79B9)
                          ^ ((byte_index + 1) * 32'h85EB_CA6B)
                          ^ ((int'(word[8*byte_index +: 8]) + 1) * 32'hC2B2_AE35));
            result ^= mixed[11:0];
        end
        return result;
    endfunction

    function automatic decision_t predict(input word_t word, input config_t cfg);
        decision_t decision;
        int free_row, victim, min_count, c0, c1, old_min, estimate;

        decision = '0;
        free_row = -1;
        victim = -1;
        min_count = 16;
        for (int row = 0; row < DICT_SIZE; row++) begin
            if (valid_bits[row]) begin
                if (resident[row] == word) begin
                    decision.hit = 1'b1;
                    decision.key = key_t'(row);
                    return decision;
                end
                if (local_counts[row] < min_count) begin
                    min_count = local_counts[row];
                    victim = row;
                end
            end else if (free_row == -1) begin
                free_row = row;
            end
        end

        if (cfg.bf_en) begin
            decision.update_bf = 1'b1;
            decision.bf0 = ref_hash(word, 0);
            decision.bf1 = ref_hash(word, 1);
            decision.bf_filtered = !(bf_active[decision.bf0] || bf_old[decision.bf0]) ||
                                   !(bf_active[decision.bf1] || bf_old[decision.bf1]);
            if (decision.bf_filtered)
                return decision;
        end

        decision.update_cms = 1'b1;
        decision.cms0 = 8'(ref_hash(word, 2));
        decision.cms1 = 8'(ref_hash(word, 3));
        c0 = cms_row0[decision.cms0];
        c1 = cms_row1[decision.cms1];
        old_min = (c0 < c1) ? c0 : c1;
        if (c0 < 15 && (cfg.cu_disable || c0 == old_min))
            c0++;
        if (c1 < 15 && (cfg.cu_disable || c1 == old_min))
            c1++;
        decision.next_c0 = 4'(c0);
        decision.next_c1 = 4'(c1);
        estimate = (c0 < c1) ? c0 : c1;
        decision.admit = free_row >= 0 || estimate > min_count;
        if (decision.admit)
            decision.key = key_t'(free_row >= 0 ? free_row : victim);
        return decision;
    endfunction

    task automatic tick();
        @(posedge clk);
        #1ns;
    endtask

    task automatic check_statistics(input string phase);
        logic [31:0] active_word, old_word;
        for (int row = 0; row < DICT_SIZE; row++)
            if (dut.local_cnt[row] !== 4'(local_counts[row]))
                $fatal(1, "N=%0d %s: resident count at key %0d got %0d expected %0d",
                       DICT_SIZE, phase, row, dut.local_cnt[row], local_counts[row]);
        for (int row = 0; row < 256; row++)
            if (dut.u_cms.gen_bank[0].memory[row] !== 4'(cms_row0[row]) ||
                dut.u_cms.gen_bank[1].memory[row] !== 4'(cms_row1[row]))
                $fatal(1, "N=%0d %s: CMS row0/row1[%0d]=%0d/%0d expected %0d/%0d",
                       DICT_SIZE, phase, row, dut.u_cms.gen_bank[0].memory[row],
                       dut.u_cms.gen_bank[1].memory[row], cms_row0[row], cms_row1[row]);
        for (int row = 0; row < 128; row++) begin
            if (dut.u_bf.active_bank) begin
                active_word = dut.u_bf.gen_bank[1].memory[row];
                old_word    = dut.u_bf.gen_bank[0].memory[row];
            end else begin
                active_word = dut.u_bf.gen_bank[0].memory[row];
                old_word    = dut.u_bf.gen_bank[1].memory[row];
            end
            if (active_word !== bf_active[row*32 +: 32] || old_word !== bf_old[row*32 +: 32])
                $fatal(1, "N=%0d %s: Bloom Filter bank mismatch at RAM word %0d",
                       DICT_SIZE, phase, row);
        end
    endtask

    task automatic wait_for_idle(output int aging_pulses);
        int cycles;
        cycles = 0;
        aging_pulses = 0;
        while (req_ready !== 1'b1 && cycles < 550) begin
            if (rsp_valid !== 1'b0)
                $fatal(1, "N=%0d unexpected response while waiting for idle", DICT_SIZE);
            if (aging_done === 1'b1)
                aging_pulses++;
            tick();
            cycles++;
        end
        if ({req_ready, rsp_valid} !== 2'b10)
            $fatal(1, "N=%0d timeout or unexpected response at idle", DICT_SIZE);
        if (aging_done === 1'b1)
            aging_pulses++;
    endtask

    task automatic reset_dut();
        int aging_pulses;
        @(negedge clk);
        rst_n             = 1'b0;
        req_valid         = 1'b0;
        req_hit           = 1'b0;
        req_hit_key       = '0;
        req_word          = '0;
        req_cu_disable    = 1'b0;
        req_aging_disable = 1'b0;
        req_bf_en         = 1'b0;
        req_aging_period  = '0;
        rsp_ready         = 1'b0;
        commit            = 1'b0;
        valid_bits        = '0;
        bf_active         = '0;
        bf_old            = '0;
        period_words      = 0;
        last_period       = 0;
        foreach (local_counts[row]) local_counts[row] = 0;
        foreach (cms_row0[row]) begin
            cms_row0[row] = 0;
            cms_row1[row] = 0;
        end
        #1ns;
        if ({req_ready, rsp_valid, aging_done} !== 3'b000)
            $fatal(1, "N=%0d outputs active during reset", DICT_SIZE);
        tick();
        @(negedge clk);
        rst_n = 1'b1;
        #1ns;
        if (req_ready !== 1'b0)
            $fatal(1, "N=%0d ready before bank initialization", DICT_SIZE);
        wait_for_idle(aging_pulses);
        if (aging_pulses != 0)
            $fatal(1, "N=%0d unexpected aging_done during initialization", DICT_SIZE);
        check_statistics("reset");
    endtask

    task automatic request_word(input word_t word, input config_t cfg, input decision_t decision);
        int cycles;
        if ({req_ready, rsp_valid} !== 2'b10)
            $fatal(1, "N=%0d policy not idle before request", DICT_SIZE);
        @(negedge clk);
        req_valid         = 1'b1;
        req_hit           = decision.hit;
        req_hit_key       = decision.key;
        req_word          = word;
        {req_cu_disable, req_aging_disable, req_bf_en, req_aging_period} = cfg;
        tick();
        req_valid         = 1'b0;
        req_hit           = !decision.hit;
        req_hit_key       = ~decision.key;
        req_word          = ~word;
        {req_cu_disable, req_aging_disable, req_bf_en, req_aging_period} = ~cfg;
        cycles = 0;
        while (rsp_valid === 1'b0 && cycles < 24) begin
            if ({req_ready, aging_done} !== 2'b00)
                $fatal(1, "N=%0d unexpected ready or aging_done before response", DICT_SIZE);
            tick();
            cycles++;
        end
        if (rsp_valid !== 1'b1)
            $fatal(1, "N=%0d response timed out for %h", DICT_SIZE, word);
    endtask

    task automatic check_response(input word_t word, input decision_t decision);
        key_t expected_key;
        expected_key = decision.admit ? decision.key : '0;
        if ({req_ready, aging_done, rsp_valid, rsp_admit, rsp_bf_filtered, rsp_key} !==
            {1'b0, 1'b0, 1'b1, decision.admit, decision.bf_filtered, expected_key})
            $fatal(1, "N=%0d word=%h response admit/bf/key=%b/%b/%0d expected=%b/%b/%0d or invalid handshake",
                   DICT_SIZE, word, rsp_admit, rsp_bf_filtered, rsp_key,
                   decision.admit, decision.bf_filtered, expected_key);
    endtask

    task automatic accept_response();
        @(negedge clk);
        rsp_ready = 1'b1;
        tick();
        rsp_ready = 1'b0;
        if ({req_ready, rsp_valid, aging_done} !== 3'b000)
            $fatal(1, "N=%0d unexpected handshake while waiting for commit", DICT_SIZE);
    endtask

    task automatic commit_model(input word_t word, input config_t cfg, input decision_t decision,
                                output bit expect_aging);
        if (decision.hit && local_counts[decision.key] < 15)
            local_counts[decision.key]++;
        if (decision.admit) begin
            resident[decision.key] = word;
            valid_bits[decision.key] = 1'b1;
            local_counts[decision.key] = 1;
        end
        if (decision.update_bf) begin
            bf_active[decision.bf0] = 1'b1;
            bf_active[decision.bf1] = 1'b1;
        end
        if (decision.update_cms) begin
            cms_row0[decision.cms0] = int'(decision.next_c0);
            cms_row1[decision.cms1] = int'(decision.next_c1);
        end

        expect_aging = 1'b0;
        if (last_period != int'(cfg.period) || cfg.period == 0 || (cfg.aging_disable && !cfg.bf_en))
            period_words = 0;
        last_period = int'(cfg.period);
        if (cfg.period != 0 && (!cfg.aging_disable || cfg.bf_en)) begin
            period_words++;
            expect_aging = period_words == last_period;
        end
        if (expect_aging) begin
            period_words = 0;
            if (cfg.bf_en) begin
                bf_old = bf_active;
                bf_active = '0;
            end
            if (!cfg.aging_disable) begin
                foreach (local_counts[row]) local_counts[row] /= 2;
                foreach (cms_row0[row]) begin
                    cms_row0[row] /= 2;
                    cms_row1[row] /= 2;
                end
            end
        end
    endtask

    task automatic transact(input word_t word, input config_t cfg,
                            input int response_stall = 0, input int commit_stall = 0);
        decision_t expected;
        bit expect_aging;
        int aging_pulses;
        expected = predict(word, cfg);
        request_word(word, cfg, expected);
        check_response(word, expected);
        repeat (response_stall) begin
            tick();
            check_response(word, expected);
        end
        accept_response();
        repeat (commit_stall) begin
            tick();
            if ({req_ready, rsp_valid, aging_done} !== 3'b000)
                $fatal(1, "N=%0d left commit wait without commit", DICT_SIZE);
        end
        check_statistics("before commit");

        @(negedge clk);
        commit = 1'b1;
        tick();
        commit = 1'b0;
        commit_model(word, cfg, expected, expect_aging);
        wait_for_idle(aging_pulses);
        if (aging_pulses != int'(expect_aging))
            $fatal(1, "N=%0d word=%h aging_done pulses=%0d expected=%0d",
                   DICT_SIZE, word, aging_pulses, expect_aging);
        check_statistics("after commit and service");
        words_checked++;
        services_checked += aging_pulses;
    endtask

    task automatic test_admission();
        config_t cfg;
        word_t candidate;
        decision_t expected;
        bit found_candidate;

        cfg = settings(0, 1, 0, 0);
        for (int row = 0; row < DICT_SIZE; row++)
            transact(32'h1220_0000 + word_t'(row), cfg);
        // Find a candidate whose first CMS estimate is one, tying the resident minimum.
        found_candidate = 1'b0;
        for (int offset = 0; offset < 4096 && !found_candidate; offset++) begin
            candidate = 32'h81b0_0000 + word_t'(offset);
            expected = predict(candidate, cfg);
            found_candidate = !expected.hit && !expected.admit;
        end
        if (!found_candidate)
            $fatal(1, "N=%0d no candidate found for equality case", DICT_SIZE);

        // First match the candidate via old BF bits while its CMS estimate still ties.
        transact(candidate, settings(0, 1, 1, 1));
        transact(candidate, settings(0, 1, 1, 0), 2, 3);
        expected = predict(candidate, settings(0, 1, 1, 0));
        if (!expected.admit || expected.key != '0)
            $fatal(1, "N=%0d expected admission to the lowest-key victim after frequency reject", DICT_SIZE);
        transact(candidate, settings(0, 1, 1, 0), 3, 2);
        repeat (20) transact(resident[DICT_SIZE-1], cfg);
        transact(candidate, cfg);

        if (DICT_SIZE == 5) begin
            for (int row = 0; row < DICT_SIZE; row++)
                repeat (15 - local_counts[row]) transact(resident[row], cfg);
            // Even a saturated CMS estimate ties the resident minimum.
            repeat (16) transact(32'hdeaf_beef, cfg);
        end
    endtask

    task automatic test_filter_and_aging();
        word_t word_a, word_b;
        word_a = 32'h1234_5678;
        word_b = 32'h9abc_def0;
        // Freeze BF while running CMS aging, then use the saved history to admit word_a.
        transact(word_a, settings(0, 1, 1, 0), 2, 4);
        transact(word_b, settings(1, 0, 0, 1));
        transact(word_a, settings(0, 1, 1, 0));
        transact(word_a, settings(0, 0, 1, 1), 2, 3);

        reset_dut();
        // A negative BF decision stores the word's bits before rotation.
        transact(word_a, settings(0, 0, 1, 1), 1, 4);
        transact(word_a, settings(1, 0, 1, 1));
        transact(word_a, settings(0, 1, 1, 1)); // Exact hit, BF-only aging.
        transact(word_b, settings(0, 0, 1, 2));
        transact(word_a, settings(0, 0, 1, 2)); // Second word reaches the new period.
    endtask

    task automatic test_reset_in_flight();
        config_t cfg;
        decision_t expected;
        word_t word;
        cfg = settings(0, 0, 1, 1);
        word = 32'h2143_6587;
        expected = predict(word, cfg);
        request_word(word, cfg, expected);
        check_response(word, expected);
        accept_response();
        reset_dut();

        expected = predict(word, cfg);
        request_word(word, cfg, expected);
        check_response(word, expected);
        accept_response();
        @(negedge clk);
        commit = 1'b1;
        tick();
        commit = 1'b0;
        repeat (12) tick();
        if ({req_ready, rsp_valid, aging_done} !== 3'b000 || dut.aging_busy !== 1'b1)
            $fatal(1, "N=%0d expected in-flight aging before reset", DICT_SIZE);
        reset_dut();
        transact(word, cfg);
    endtask

    task automatic test_random_words();
        word_t word;
        config_t cfg;
        int row;
        repeat (12) begin
            cfg = settings(bit'($urandom_range(1, 0)), bit'($urandom_range(1, 0)),
                           bit'($urandom_range(1, 0)), int'($urandom_range(15, 0)));
            repeat (30) begin
                row = int'($urandom_range(DICT_SIZE - 1, 0));
                if (valid_bits[row] && $urandom_range(1, 0) == 1)
                    word = resident[row];
                else
                    word = 32'hbad0_0000 + word_t'($urandom_range(48, 0));
                transact(word, cfg, int'($urandom_range(3, 0)), int'($urandom_range(3, 0)));
            end
        end
    endtask

    initial begin
        done = 1'b0;
        reset_dut();
        test_admission();
        reset_dut();
        test_filter_and_aging();
        test_reset_in_flight();
        test_random_words();
        $display("PASS DICT_SIZE=%0d (%0d commits, %0d aging services)",
                 DICT_SIZE, words_checked, services_checked);
        done = 1'b1;
    end
endmodule

module tdl_tinylfu_policy_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    logic [1:0] done;
    bit test_passed = 1'b0;
    tdl_tinylfu_policy_test #(.DICT_SIZE(5))   test_small (.done(done[0]));
    tdl_tinylfu_policy_test #(.DICT_SIZE(256)) test_full  (.done(done[1]));

    initial begin
        wait (&done);
        test_passed = 1'b1;
        $display("All TinyLFU policy tests passed.");
        $finish;
    end

    initial begin
        #5ms;
        $fatal(1, "TinyLFU policy test timed out. Done mask=%b", done);
    end
endmodule
