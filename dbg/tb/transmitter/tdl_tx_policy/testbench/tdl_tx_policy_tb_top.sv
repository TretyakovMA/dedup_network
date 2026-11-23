module tdl_tx_policy_test #(
    parameter int DICT_SIZE = 5
) (
    output bit done
);
    timeunit 1ns;
    timeprecision 1ps;

    import tdl_tab_hash_pkg::TABLE_SEED;
    import tdl_tab_hash_pkg::mix32;
    import tdl_tx_pkg::TINYLFU_IDLE_WAIT_CYCLES;

    localparam int KEY_WIDTH = $clog2(DICT_SIZE);
    localparam time CLK_PERIOD = 20ns;
    typedef logic [31:0] word_t;
    typedef logic [KEY_WIDTH-1:0] key_t;
    typedef struct packed {
        bit hit, admit, bf_filtered, update_bf, update_cms;
        key_t key;
        logic [11:0] bf0, bf1;
        logic [7:0] cms0, cms1;
        logic [3:0] next_c0, next_c1;
    } decision_t;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    word_t policy_cfg, policy_req_cfg, policy_word;
    logic policy_req_valid, policy_req_ready, policy_hit;
    key_t policy_hit_key, next_free_key, policy_key;
    logic [DICT_SIZE-1:0] valid_bits;
    logic dict_full;
    logic policy_rsp_valid, policy_rsp_ready, policy_admit, policy_bf_filtered;
    logic policy_commit, aging_done;

    // The model owns the external dictionary and uses sequential software algorithms.
    word_t resident [0:DICT_SIZE-1];
    int local_counts [0:DICT_SIZE-1];
    bit [DICT_SIZE-1:0] model_usage;
    int model_hand;
    int prob_order [0:DICT_SIZE-1], prot_order [0:DICT_SIZE-1];
    int prob_count, prot_count;
    int cms_row0 [0:255], cms_row1 [0:255];
    bit [4095:0] bf_active, bf_old;
    int period_words, last_period, model_algo, quota;
    int words_checked [0:3];
    int services_checked = 0;
    int request_handshakes = 0, response_handshakes = 0, commit_pulses = 0;

    tdl_tx_policy #(.DICT_SIZE(DICT_SIZE)) dut (.*);

    always #(CLK_PERIOD / 2) clk = ~clk;
    assign dict_full = &valid_bits;
    always_comb begin
        next_free_key = '0;
        for (int row = DICT_SIZE - 1; row >= 0; row--)
            if (!valid_bits[row])
                next_free_key = key_t'(row);
    end

    // Each public handshake must reach exactly one backend on the same edge.
    always @(posedge clk) begin
        if (rst_n) begin
            if ((dut.backend_req_valid & dut.backend_req_ready) !==
                ((policy_req_valid && policy_req_ready) ? (4'b0001 << model_algo) : 4'b0000))
                $fatal(1, "N=%0d request routing mismatch", DICT_SIZE);
            if ((dut.backend_rsp_valid & dut.backend_rsp_ready) !==
                ((policy_rsp_valid && policy_rsp_ready) ? (4'b0001 << model_algo) : 4'b0000))
                $fatal(1, "N=%0d response routing mismatch", DICT_SIZE);
            if (dut.backend_commit !== (policy_commit ? (4'b0001 << model_algo) : 4'b0000))
                $fatal(1, "N=%0d commit routing mismatch", DICT_SIZE);
            if (model_algo != 0 && aging_done !== 1'b0)
                $fatal(1, "N=%0d aging in a non-TinyLFU mode", DICT_SIZE);
            if (policy_req_valid && policy_req_ready) request_handshakes++;
            if (policy_rsp_valid && policy_rsp_ready) response_handshakes++;
            if (policy_commit) commit_pulses++;
        end
    end

    // Literal packing also checks the shared package layout used in the RTL.
    function automatic word_t settings(input int algo, input int n_prob,
                                        input bit cu_disable = 0, input bit aging_disable = 1,
                                        input bit bf_en = 0, input int period = 0);
        return {16'(period), 8'(n_prob), 3'b000, bf_en, aging_disable, cu_disable, 2'(algo)};
    endfunction

    function automatic logic [11:0] ref_hash(input word_t word, input int index);
        word_t mixed;
        logic [11:0] result;
        result = '0;
        for (int byte_index = 0; byte_index < 4; byte_index++) begin
            mixed = mix32(TABLE_SEED ^ ((index + 1) * 32'h9E37_79B9)
                          ^ ((byte_index + 1) * 32'h85EB_CA6B)
                          ^ ((int'(word[8*byte_index +: 8]) + 1) * 32'hC2B2_AE35));
            result ^= mixed[11:0];
        end
        return result;
    endfunction

    function automatic decision_t predict(input word_t word, input word_t cfg);
        decision_t d;
        int free_row, victim, min_count, c0, c1, old_min, estimate;
        bit [DICT_SIZE-1:0] usage_copy;
        d = '0;
        free_row = -1;
        victim = -1;
        min_count = 16;
        for (int row = 0; row < DICT_SIZE; row++) begin
            if (valid_bits[row]) begin
                if (resident[row] == word) begin
                    d.hit = 1'b1;
                    d.key = key_t'(row);
                    return d;
                end
                if (local_counts[row] < min_count) begin
                    min_count = local_counts[row];
                    victim = row;
                end
            end else if (free_row == -1) free_row = row;
        end
        if (model_algo != 0) begin
            d.admit = 1'b1;
            case (model_algo)
                1: d.key = key_t'(prob_count == quota ? prob_order[prob_count-1] : free_row);
                2: begin
                    victim = model_hand;
                    usage_copy = model_usage;
                    while (usage_copy[victim]) begin
                        usage_copy[victim] = 1'b0;
                        victim = (victim + 1) % DICT_SIZE;
                    end
                    d.key = key_t'(free_row >= 0 ? free_row : victim);
                end
                3: d.key = key_t'(free_row >= 0 ? free_row : victim);
            endcase
            return d;
        end
        if (cfg[4]) begin
            d.update_bf = 1'b1;
            d.bf0 = ref_hash(word, 0);
            d.bf1 = ref_hash(word, 1);
            d.bf_filtered = !(bf_active[d.bf0] || bf_old[d.bf0]) ||
                            !(bf_active[d.bf1] || bf_old[d.bf1]);
            if (d.bf_filtered) return d;
        end
        d.update_cms = 1'b1;
        d.cms0 = 8'(ref_hash(word, 2));
        d.cms1 = 8'(ref_hash(word, 3));
        c0 = cms_row0[d.cms0];
        c1 = cms_row1[d.cms1];
        old_min = c0 < c1 ? c0 : c1;
        if (c0 < 15 && (cfg[2] || c0 == old_min)) c0++;
        if (c1 < 15 && (cfg[2] || c1 == old_min)) c1++;
        d.next_c0 = 4'(c0);
        d.next_c1 = 4'(c1);
        estimate = c0 < c1 ? c0 : c1;
        d.admit = free_row >= 0 || estimate > min_count;
        if (d.admit) d.key = key_t'(free_row >= 0 ? free_row : victim);
        return d;
    endfunction

    task automatic tick();
        @(posedge clk);
        #1ns;
    endtask

    task automatic check_metadata();
        bit [DICT_SIZE-1:0] expected_segment;
        key_t expected_rank [0:DICT_SIZE-1];
        logic [31:0] active_word, old_word;
        expected_segment = '0;
        foreach (expected_rank[row]) expected_rank[row] = '0;
        for (int pos = 0; pos < prob_count; pos++)
            expected_rank[prob_order[pos]] = key_t'(pos);
        for (int pos = 0; pos < prot_count; pos++) begin
            expected_segment[prot_order[pos]] = 1'b1;
            expected_rank[prot_order[pos]] = key_t'(pos);
        end
        if (dut.u_clock.usage_bit !== model_usage || dut.u_clock.clock_hand !== key_t'(model_hand) ||
            dut.u_slru.segment !== expected_segment)
            $fatal(1, "N=%0d algo=%0d Clock/SLRU metadata mismatch", DICT_SIZE, model_algo);
        for (int row = 0; row < DICT_SIZE; row++) begin
            if (dut.u_slru.rank[row] !== expected_rank[row] ||
                dut.u_lfu.local_cnt[row] !== 4'(model_algo == 3 ? local_counts[row] : 0) ||
                dut.u_tinylfu.local_cnt[row] !== 4'(model_algo == 0 ? local_counts[row] : 0))
                $fatal(1, "N=%0d algo=%0d metadata mismatch at key %0d", DICT_SIZE, model_algo, row);
        end
        // Inactive TinyLFU initializes its RAMs but must receive no transactions.
        if (model_algo == 0 || (!dut.u_tinylfu.u_cms.busy && !dut.u_tinylfu.u_bf.busy)) begin
            for (int row = 0; row < 256; row++)
                if (dut.u_tinylfu.u_cms.gen_bank[0].memory[row] !== 4'(cms_row0[row]) ||
                    dut.u_tinylfu.u_cms.gen_bank[1].memory[row] !== 4'(cms_row1[row]))
                    $fatal(1, "N=%0d CMS mismatch at index %0d", DICT_SIZE, row);
            for (int row = 0; row < 128; row++) begin
                if (dut.u_tinylfu.u_bf.active_bank) begin
                    active_word = dut.u_tinylfu.u_bf.gen_bank[1].memory[row];
                    old_word = dut.u_tinylfu.u_bf.gen_bank[0].memory[row];
                end else begin
                    active_word = dut.u_tinylfu.u_bf.gen_bank[0].memory[row];
                    old_word = dut.u_tinylfu.u_bf.gen_bank[1].memory[row];
                end
                if (active_word !== bf_active[row*32 +: 32] || old_word !== bf_old[row*32 +: 32])
                    $fatal(1, "N=%0d BF mismatch at RAM word %0d", DICT_SIZE, row);
            end
        end
    endtask

    task automatic wait_for_idle(output int pulses);
        int cycles;
        cycles = 0;
        pulses = 0;
        while (policy_req_ready !== 1'b1 && cycles < 550) begin
            if (policy_rsp_valid !== 1'b0)
                $fatal(1, "N=%0d unexpected response after commit", DICT_SIZE);
            if (aging_done === 1'b1) pulses++;
            tick();
            cycles++;
        end
        if ({policy_req_ready, policy_rsp_valid} !== 2'b10)
            $fatal(1, "N=%0d idle timeout", DICT_SIZE);
        if (aging_done === 1'b1) pulses++;
    endtask

    task automatic reset_dut(input int algo, input int n_prob);
        int pulses;
        @(negedge clk);
        rst_n = 1'b0;
        policy_req_valid = 1'b0;
        policy_req_cfg = 'x;
        policy_hit = 1'b0;
        policy_hit_key = '0;
        policy_word = '0;
        policy_rsp_ready = 1'b0;
        policy_commit = 1'b0;
        policy_cfg = settings(algo, n_prob);
        model_algo = algo;
        quota = n_prob;
        valid_bits = '0;
        model_usage = '0;
        model_hand = 0;
        prob_count = 0;
        prot_count = 0;
        bf_active = '0;
        bf_old = '0;
        period_words = 0;
        last_period = 0;
        foreach (local_counts[row]) local_counts[row] = 0;
        foreach (cms_row0[row]) begin
            cms_row0[row] = 0;
            cms_row1[row] = 0;
        end
        #1ns;
        if ({policy_req_ready, policy_rsp_valid, aging_done} !== 3'b000)
            $fatal(1, "N=%0d outputs active in reset", DICT_SIZE);
        tick();
        @(negedge clk);
        rst_n = 1'b1;
        #1ns;
        if (policy_req_ready !== (algo != 0))
            $fatal(1, "N=%0d invalid initialization gating for algo=%0d", DICT_SIZE, algo);
        wait_for_idle(pulses);
        if (pulses != 0) $fatal(1, "Unexpected aging during reset");
        check_metadata();
    endtask

    task automatic check_configuration();
        word_t saved;
        saved = policy_cfg;
        // Software may select any mode before the first word. No snapshot is qualified.
        for (int algo = 1; algo < 4; algo++) begin
            policy_cfg = settings(algo, 1);
            #1ns;
            if (policy_req_ready !== 1'b1) $fatal(1, "Ready depends on an unqualified snapshot");
        end
        policy_cfg = settings(1, 0);
        #1ns;
        if (policy_req_ready !== 1'b0) $fatal(1, "SLRU zero quota accepted");
        if (DICT_SIZE < 256) begin
            policy_cfg = settings(1, DICT_SIZE);
            #1ns;
            if (policy_req_ready !== 1'b0) $fatal(1, "SLRU oversized quota accepted");
        end
        policy_cfg = settings(2, 1) | 32'h20;
        #1ns;
        if (policy_req_ready !== 1'b0) $fatal(1, "Reserved configuration bits accepted");
        policy_cfg[1:0] = 'x;
        #1ns;
        if (policy_req_ready !== 1'b0) $fatal(1, "Unknown algorithm accepted");
        policy_cfg = saved;
        // Check the combinational rejection without sampling an illegal request edge.
        @(negedge clk);
        policy_req_valid = 1'b1;
        policy_req_cfg = saved ^ 32'h1;
        #1ns;
        if (policy_req_ready !== 1'b0 || dut.backend_req_valid !== '0)
            $fatal(1, "Mismatched algorithm snapshot accepted");
        policy_req_cfg = saved ^ 32'h100;
        #1ns;
        if (policy_req_ready !== 1'b0 || dut.backend_req_valid !== '0)
            $fatal(1, "Mismatched quota snapshot accepted");
        policy_req_valid = 1'b0;
        policy_req_cfg = 'x;
        #1ns;
        if (policy_req_ready !== 1'b1) $fatal(1, "Configuration recovery failed");
    endtask

    task automatic request_word(input word_t word, input word_t cfg, input decision_t d);
        int cycles;
        @(negedge clk);
        policy_req_valid = 1'b1;
        policy_req_cfg = cfg;
        // Live mutable fields may differ from the controller's earlier snapshot.
        policy_cfg = cfg ^ 32'hffff_001c;
        policy_word = word;
        policy_hit = d.hit;
        policy_hit_key = d.key;
        tick();
        policy_req_valid = 1'b0;
        policy_req_cfg = 'x;
        policy_word = ~word;
        policy_hit = !d.hit;
        policy_hit_key = ~d.key;
        cycles = 0;
        while (policy_rsp_valid === 1'b0 && cycles < DICT_SIZE + 24) begin
            if (policy_req_ready !== 1'b0 || aging_done !== 1'b0)
                $fatal(1, "N=%0d premature readiness before response", DICT_SIZE);
            tick();
            cycles++;
        end
        if (policy_rsp_valid !== 1'b1) $fatal(1, "N=%0d response timeout", DICT_SIZE);
    endtask

    task automatic check_response(input decision_t d);
        if ({policy_req_ready, policy_rsp_valid, policy_admit, policy_bf_filtered, policy_key} !==
            {1'b0, 1'b1, d.admit, d.bf_filtered, (d.admit ? d.key : key_t'(0))})
            $fatal(1, "N=%0d algo=%0d response=%b/%b/%0d expected=%b/%b/%0d",
                   DICT_SIZE, model_algo, policy_admit, policy_bf_filtered, policy_key,
                   d.admit, d.bf_filtered, d.admit ? d.key : 0);
        check_metadata();
    endtask

    task automatic accept_response();
        @(negedge clk);
        policy_rsp_ready = 1'b1;
        tick();
        policy_rsp_ready = 1'b0;
        if ({policy_req_ready, policy_rsp_valid} !== 2'b00)
            $fatal(1, "N=%0d transaction released before commit", DICT_SIZE);
    endtask

    task automatic slru_update(input decision_t d);
        int pos, demoted;
        if (!d.hit) begin
            if (prob_count < quota) prob_count++;
        end else begin
            pos = -1;
            for (int p = 0; p < prot_count; p++)
                if (prot_order[p] == int'(d.key)) pos = p;
            if (pos >= 0) begin
                for (int p = pos; p > 0; p--) prot_order[p] = prot_order[p-1];
                prot_order[0] = int'(d.key);
                return;
            end
            pos = -1;
            for (int p = 0; p < prob_count; p++)
                if (prob_order[p] == int'(d.key)) pos = p;
            if (pos < 0) $fatal(1, "SLRU model lost resident key");
            for (int p = pos; p < prob_count-1; p++) prob_order[p] = prob_order[p+1];
            prob_count--;
            if (prot_count == DICT_SIZE - quota) begin
                demoted = prot_order[prot_count-1];
                prob_count++;
                for (int p = prob_count-1; p > 0; p--) prob_order[p] = prob_order[p-1];
                prob_order[0] = demoted;
            end else prot_count++;
            for (int p = prot_count-1; p > 0; p--) prot_order[p] = prot_order[p-1];
            prot_order[0] = int'(d.key);
            return;
        end
        for (int p = prob_count-1; p > 0; p--) prob_order[p] = prob_order[p-1];
        prob_order[0] = int'(d.key);
    endtask

    task automatic commit_model(input word_t word, input word_t cfg, input decision_t d,
                                output bit expect_aging);
        int candidate, period;
        expect_aging = 1'b0;
        case (model_algo)
            1: slru_update(d);
            2: begin
                if (!d.hit && dict_full) begin
                    candidate = model_hand;
                    while (model_usage[candidate]) begin
                        model_usage[candidate] = 1'b0;
                        candidate = (candidate + 1) % DICT_SIZE;
                    end
                    model_hand = (candidate + 1) % DICT_SIZE;
                end
                model_usage[d.key] = 1'b1;
            end
            0, 3: begin
                if (d.hit && local_counts[d.key] < 15) local_counts[d.key]++;
                if (d.admit) local_counts[d.key] = 1;
            end
        endcase
        if (d.admit) begin
            resident[d.key] = word;
            valid_bits[d.key] = 1'b1;
        end
        if (model_algo != 0) return;
        if (d.update_bf) begin
            bf_active[d.bf0] = 1'b1;
            bf_active[d.bf1] = 1'b1;
        end
        if (d.update_cms) begin
            cms_row0[d.cms0] = int'(d.next_c0);
            cms_row1[d.cms1] = int'(d.next_c1);
        end
        period = int'(cfg[31:16]);
        if (last_period != period || period == 0 || (cfg[3] && !cfg[4])) period_words = 0;
        last_period = period;
        if (period != 0 && (!cfg[3] || cfg[4])) begin
            period_words++;
            expect_aging = period_words == period;
        end
        if (expect_aging) begin
            period_words = 0;
            if (cfg[4]) begin
                bf_old = bf_active;
                bf_active = '0;
            end
            if (!cfg[3]) begin
                foreach (local_counts[row]) local_counts[row] /= 2;
                foreach (cms_row0[row]) begin
                    cms_row0[row] /= 2;
                    cms_row1[row] /= 2;
                end
            end
        end
    endtask

    task automatic transact(input word_t word, input word_t cfg,
                            input int response_stall = 0, input int commit_stall = 0);
        decision_t d;
        bit expect_aging;
        int pulses, req_before, rsp_before, commit_before;
        req_before = request_handshakes;
        rsp_before = response_handshakes;
        commit_before = commit_pulses;
        d = predict(word, cfg);
        request_word(word, cfg, d);
        check_response(d);
        // Present a competing request while the accepted transaction is stalled.
        policy_req_valid = 1'b1;
        policy_req_cfg = cfg;
        // A live selection change cannot redirect the outstanding response or commit.
        policy_cfg[1:0] = 2'((model_algo + 1) % 4);
        repeat (response_stall) begin
            tick();
            check_response(d);
        end
        accept_response();
        repeat (commit_stall) begin
            tick();
            if ({policy_req_ready, policy_rsp_valid} !== 2'b00)
                $fatal(1, "N=%0d request accepted before commit", DICT_SIZE);
            check_metadata();
        end
        policy_req_valid = 1'b0;
        policy_req_cfg = 'x;
        @(negedge clk);
        policy_commit = 1'b1;
        tick();
        policy_commit = 1'b0;
        commit_model(word, cfg, d, expect_aging);
        // Keep the different live selection during the post-commit busy interval.
        repeat (2) begin
            if (model_algo == 0 && expect_aging && policy_req_ready !== 1'b0)
                $fatal(1, "N=%0d live config bypassed TinyLFU maintenance", DICT_SIZE);
            tick();
        end
        policy_cfg = cfg;
        wait_for_idle(pulses);
        if (pulses != int'(expect_aging))
            $fatal(1, "N=%0d aging pulse count=%0d expected=%0d", DICT_SIZE, pulses, expect_aging);
        if (request_handshakes != req_before+1 || response_handshakes != rsp_before+1 ||
            commit_pulses != commit_before+1)
            $fatal(1, "N=%0d duplicated or lost transaction", DICT_SIZE);
        check_metadata();
        words_checked[model_algo]++;
        services_checked += pulses;
    endtask

    task automatic test_mode(input int algo, input int n_prob);
        word_t cfg, candidate, word;
        decision_t d;
        int row;
        reset_dut(algo, n_prob);
        cfg = settings(algo, n_prob);
        if (algo == 1) begin
            // Probationary eviction is required even while Protected is empty.
            for (int i = 0; i < n_prob+2; i++) transact(32'h1100_0000 + word_t'(i), cfg, 1, 2);
            if (dict_full) $fatal(1, "SLRU filled Protected with misses");
        end
        for (int i = 0; i < DICT_SIZE; i++) begin
            word = 32'h2200_0000 + word_t'(i);
            transact(word, cfg);
            if (algo == 1) transact(word, cfg); // Fill Protected by promotion.
        end
        if (!dict_full) $fatal(1, "N=%0d directed fill did not fill dictionary", DICT_SIZE);
        repeat (20) transact(resident[DICT_SIZE-1], cfg, 2, 3);
        for (int i = 0; i < DICT_SIZE+3; i++)
            transact(32'h3300_0000 + word_t'(i), cfg, 1, 2);
        if (algo == 0) begin
            candidate = 32'h8100_0000;
            d = predict(candidate, cfg);
            while (d.hit || d.admit) begin
                candidate++;
                d = predict(candidate, cfg);
            end
            transact(candidate, cfg, 3, 4); // Equal CMS estimate rejects, but still commits CMS.
            transact(candidate, cfg, 2, 5); // The increased estimate can admit.
            // First BF RAW, then pass from old generation, then exact hit.
            reset_dut(0, n_prob);
            cfg = settings(0, n_prob, 0, 0, 1, 1);
            transact(32'h1234_5678, cfg, 2, 4);
            transact(32'h1234_5678, cfg, 1, 3);
            transact(32'h1234_5678, settings(0, n_prob, 1, 1, 1, 1));
            transact(32'habcd_ef01, settings(0, n_prob, 1, 0, 0, 1));
        end
        repeat (8) begin
            cfg = settings(algo, n_prob, bit'($urandom_range(1, 0)), bit'($urandom_range(1, 0)),
                           bit'($urandom_range(1, 0)), int'($urandom_range(7, 0)));
            repeat (30) begin
                row = int'($urandom_range(DICT_SIZE-1, 0));
                word = valid_bits[row] && $urandom_range(1, 0) ? resident[row] :
                       32'hbad0_0000 + word_t'($urandom_range(48, 0));
                transact(word, cfg, int'($urandom_range(3, 0)), int'($urandom_range(3, 0)));
            end
        end
        // With no new requests (including the controller's Bypass path), metadata stays still.
        policy_rsp_ready = 1'b1;
        repeat (12) tick();
        policy_rsp_ready = 1'b0;
        check_metadata();
        $display("PASS N=%0d algo=%0d quota=%0d", DICT_SIZE, algo, n_prob);
    endtask

    task automatic test_resets();
        decision_t d;
        word_t cfg;
        for (int algo = 0; algo < 4; algo++) begin
            reset_dut(algo, 1);
            cfg = settings(algo, 1);
            d = predict(32'h4321_5678, cfg);
            request_word(32'h4321_5678, cfg, d);
            reset_dut(algo, 1); // Pending response is discarded.
            request_word(32'h4321_5678, cfg, d);
            accept_response();
            reset_dut(algo, 1); // Accepted response still has no committed effect.
            transact(32'h4321_5678, cfg);
        end
        reset_dut(0, 1);
        cfg = settings(0, 1, 0, 0, 1, 1);
        d = predict(32'hdead_beef, cfg);
        request_word(32'hdead_beef, cfg, d);
        accept_response();
        @(negedge clk);
        policy_commit = 1'b1;
        tick();
        policy_commit = 1'b0;
        repeat (12) tick();
        if (policy_req_ready !== 1'b0 || dut.u_tinylfu.aging_busy !== 1'b1)
            $fatal(1, "Expected in-flight service before reset");
        reset_dut(0, 1);
        transact(32'hdead_beef, cfg);
    endtask

    task automatic test_idle_wait_bound();
        word_t cfg, word;
        decision_t d;
        bit expect_aging;
        time committed_at;
        int pulses, elapsed_cycles;

        reset_dut(0, 1);
        cfg = settings(0, 1, 0, 0, 1, 2);
        word = 32'h1234_5678;
        transact(word, cfg); // First miss sets BF bits without admitting the word.

        d = predict(word, cfg);
        if (d.hit || !d.update_bf || !d.update_cms || d.bf0[11:5] == d.bf1[11:5])
            $fatal(1, "Idle wait case must commit two BF writes and a CMS update");
        request_word(word, cfg, d);
        check_response(d);
        accept_response();

        @(negedge clk);
        policy_cfg = cfg;
        policy_commit = 1'b1;
        tick();
        committed_at = $time;
        policy_commit = 1'b0;
        commit_model(word, cfg, d, expect_aging);
        if (!expect_aging || policy_req_ready !== 1'b0)
            $fatal(1, "Expected TinyLFU maintenance after the final commit");

        wait_for_idle(pulses);
        elapsed_cycles = int'(($time - committed_at) / CLK_PERIOD);
        if (pulses != 1 || elapsed_cycles > TINYLFU_IDLE_WAIT_CYCLES)
            $fatal(1, "N=%0d: policy became ready after %0d cycles (%0d aging pulses), limit %0d",
                   DICT_SIZE, elapsed_cycles, pulses, TINYLFU_IDLE_WAIT_CYCLES);
        check_metadata();
        words_checked[0]++;
        services_checked += pulses;
        $display("PASS DICT_SIZE=%0d: TinyLFU ready %0d cycles after commit, limit %0d",
                 DICT_SIZE, elapsed_cycles, TINYLFU_IDLE_WAIT_CYCLES);
    endtask

    initial begin
        done = 1'b0;
        foreach (words_checked[algo]) words_checked[algo] = 0;
        reset_dut(2, 1);
        check_configuration();
        for (int algo = 0; algo < 4; algo++) test_mode(algo, 1);
        if (DICT_SIZE > 2) test_mode(1, DICT_SIZE-1);
        test_resets();
        test_idle_wait_bound();
        $display("PASS DICT_SIZE=%0d commits Tiny/SLRU/Clock/LFU=%0d/%0d/%0d/%0d services=%0d",
                 DICT_SIZE, words_checked[0], words_checked[1], words_checked[2], words_checked[3],
                 services_checked);
        done = 1'b1;
    end
endmodule

module tdl_tx_policy_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    logic [2:0] done;
    bit test_passed = 1'b0;
    tdl_tx_policy_test #(.DICT_SIZE(2)) test_min (.done(done[0]));
    tdl_tx_policy_test #(.DICT_SIZE(5)) test_small (.done(done[1]));
    tdl_tx_policy_test #(.DICT_SIZE(256)) test_full (.done(done[2]));

    initial begin
        wait (&done);
        test_passed = 1'b1;
        $display("All TX policy dispatcher tests passed.");
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "TX policy test timed out. Done mask=%b", done);
    end
endmodule
