module tdl_slru_policy_test #(
    parameter int DICT_SIZE = 5,
    parameter int N_PROB = 2
) (
    output logic done
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam int KEY_WIDTH = $clog2(DICT_SIZE);
    localparam int N_PROT = DICT_SIZE - N_PROB;
    localparam int RANDOM_TRANSACTIONS = 1000;
    localparam time CLK_PERIOD = 20ns;
    typedef logic [KEY_WIDTH-1:0] key_t;

    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic req_valid, req_ready, req_hit;
    logic rsp_valid, rsp_ready, rsp_admit, commit;
    key_t req_hit_key, rsp_key, next_free_key;
    logic [7:0] req_n_prob;
    logic [DICT_SIZE-1:0] model_valid;
    logic dict_full;

    // Reference lists are ordered from MRU to LRU and store physical keys.
    key_t prob_order [0:DICT_SIZE-1];
    key_t prot_order [0:DICT_SIZE-1];
    int prob_count, prot_count;
    int checked_transactions = 0;

    tdl_slru_policy #(
        .DICT_SIZE(DICT_SIZE)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .req_valid    (req_valid),
        .req_ready    (req_ready),
        .req_hit      (req_hit),
        .req_hit_key  (req_hit_key),
        .req_n_prob   (req_n_prob),
        .valid_bits   (model_valid),
        .dict_full    (dict_full),
        .next_free_key(next_free_key),
        .rsp_valid    (rsp_valid),
        .rsp_ready    (rsp_ready),
        .rsp_admit    (rsp_admit),
        .rsp_key      (rsp_key),
        .commit       (commit)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    assign dict_full = &model_valid;
    always_comb begin
        next_free_key = '0;
        for (int key = DICT_SIZE - 1; key >= 0; key--)
            if (!model_valid[key])
                next_free_key = key_t'(key);
    end

    task automatic tick();
        @(posedge clk);
        #1ns;
    endtask

    task automatic check_state(input logic [1:0] ready_valid, input string phase);
        logic [DICT_SIZE-1:0] listed_keys;
        key_t key;

        if ({req_ready, rsp_valid} !== ready_valid)
            $fatal(1, "DICT_SIZE=%0d N_PROB=%0d %s: ready/valid=%b expected=%b",
                   DICT_SIZE, N_PROB, phase, {req_ready, rsp_valid}, ready_valid);

        listed_keys = '0;
        for (int pos = 0; pos < prob_count; pos++) begin
            key = prob_order[pos];
            listed_keys[key] = 1'b1;
            if ({dut.segment[key], dut.rank[key]} !== {1'b0, key_t'(pos)})
                $fatal(1, "DICT_SIZE=%0d N_PROB=%0d %s: key=%0d expected Probationary rank=%0d got %b:%0d",
                       DICT_SIZE, N_PROB, phase, key, pos, dut.segment[key], dut.rank[key]);
        end
        for (int pos = 0; pos < prot_count; pos++) begin
            key = prot_order[pos];
            listed_keys[key] = 1'b1;
            if ({dut.segment[key], dut.rank[key]} !== {1'b1, key_t'(pos)})
                $fatal(1, "DICT_SIZE=%0d N_PROB=%0d %s: key=%0d expected Protected rank=%0d got %b:%0d",
                       DICT_SIZE, N_PROB, phase, key, pos, dut.segment[key], dut.rank[key]);
        end
        if (listed_keys !== model_valid)
            $fatal(1, "DICT_SIZE=%0d N_PROB=%0d %s: model lists disagree with valid bits",
                   DICT_SIZE, N_PROB, phase);
        for (int row = 0; row < DICT_SIZE; row++)
            if (!model_valid[row] && {dut.segment[row], dut.rank[row]} !== '0)
                $fatal(1, "DICT_SIZE=%0d N_PROB=%0d %s: unused key=%0d has metadata",
                       DICT_SIZE, N_PROB, phase, row);
    endtask

    task automatic reset_dut();
        @(negedge clk);
        rst_n       = 1'b0;
        req_valid   = 1'b0;
        req_hit     = 1'b0;
        req_hit_key = '0;
        req_n_prob  = 8'(N_PROB);
        rsp_ready   = 1'b0;
        commit      = 1'b0;
        model_valid = '0;
        prob_count  = 0;
        prot_count  = 0;
        #1ns;
        check_state(2'b00, "asynchronous reset");
        tick();
        check_state(2'b00, "reset clock");

        @(negedge clk);
        rst_n = 1'b1;
        #1ns;
        check_state(2'b10, "idle after reset");
    endtask

    task automatic send_request(input bit hit, input key_t key);
        check_state(2'b10, "before request");
        @(negedge clk);
        req_valid   = 1'b1;
        req_hit     = hit;
        req_hit_key = key;
        req_n_prob  = 8'(N_PROB);
        tick();
        req_valid   = 1'b0;
        // The accepted decision must survive changes to unqualified request fields.
        req_hit     = !hit;
        req_hit_key = ~key;
        req_n_prob  = '0;
    endtask

    task automatic check_response(input bit admit, input key_t key);
        check_state(2'b01, "response before commit");
        if (rsp_admit !== admit || rsp_key !== key)
            $fatal(1, "DICT_SIZE=%0d N_PROB=%0d admit/key=%b/%0d expected=%b/%0d",
                   DICT_SIZE, N_PROB, rsp_admit, rsp_key, admit, key);
    endtask

    task automatic accept_response();
        @(negedge clk);
        rsp_ready = 1'b1;
        tick();
        rsp_ready = 1'b0;
        check_state(2'b00, "waiting for commit");
    endtask

    task automatic insert_prob_mru(input key_t key);
        if (prob_count < N_PROB)
            prob_count++;
        for (int pos = prob_count - 1; pos > 0; pos--)
            prob_order[pos] = prob_order[pos-1];
        prob_order[0] = key;
    endtask

    task automatic commit_model(input bit hit, input key_t key);
        int prob_pos, prot_pos;
        if (!hit) begin
            insert_prob_mru(key);
            model_valid[key] = 1'b1;
        end else begin
            prot_pos = -1;
            for (int pos = 0; pos < prot_count; pos++)
                if (prot_order[pos] == key)
                    prot_pos = pos;
            if (prot_pos == -1) begin
                prob_pos = -1;
                for (int pos = 0; pos < prob_count; pos++)
                    if (prob_order[pos] == key)
                        prob_pos = pos;
                if (prob_pos == -1)
                    $fatal(1, "DICT_SIZE=%0d N_PROB=%0d model hit on absent key=%0d",
                           DICT_SIZE, N_PROB, key);
                for (int pos = prob_pos; pos < prob_count - 1; pos++)
                    prob_order[pos] = prob_order[pos+1];
                prob_count--;
                if (prot_count == N_PROT)
                    insert_prob_mru(prot_order[prot_count-1]);
                else
                    prot_count++;
                prot_pos = prot_count - 1;
            end
            for (int pos = prot_pos; pos > 0; pos--)
                prot_order[pos] = prot_order[pos-1];
            prot_order[0] = key;
        end
    endtask

    task automatic transact(
        input bit hit,
        input key_t hit_key,
        input int response_stall = 0,
        input int commit_stall = 0
    );
        key_t selected_key, expected_key;
        int free_key;
        if (hit) begin
            selected_key = hit_key;
        end else if (prob_count == N_PROB) begin
            selected_key = prob_order[prob_count-1];
        end else begin
            free_key = 0;
            while (free_key < DICT_SIZE && model_valid[free_key])
                free_key++;
            if (free_key == DICT_SIZE)
                $fatal(1, "DICT_SIZE=%0d N_PROB=%0d no free key for a miss with free quota",
                       DICT_SIZE, N_PROB);
            selected_key = key_t'(free_key);
        end
        expected_key = hit ? '0 : selected_key;

        send_request(hit, hit_key);
        check_response(!hit, expected_key);
        repeat (response_stall) begin
            tick();
            check_response(!hit, expected_key);
        end
        accept_response();
        repeat (commit_stall) begin
            tick();
            check_state(2'b00, "commit stall");
        end

        @(negedge clk);
        commit = 1'b1;
        tick();
        commit = 1'b0;
        commit_model(hit, selected_key);
        check_state(2'b10, "after commit");
        checked_transactions++;
    endtask

    task automatic test_segment_operations();
        repeat (N_PROB)
            transact(1'b0, '0);
        // Replace the Probationary LRU while Protected still has free capacity.
        transact(1'b0, '0, 3, 2);
        repeat (N_PROT) begin
            if (prob_count == 0)
                transact(1'b0, '0);
            transact(1'b1, prob_order[prob_count-1]);
        end
        while (prob_count < N_PROB)
            transact(1'b0, '0);
        transact(1'b1, prot_order[prot_count-1], 1, 4);
        transact(1'b1, prob_order[prob_count/2], 4, 4);
        transact(1'b0, '0, 2, 1);
    endtask

    task automatic test_random_operations();
        key_t key;
        bit hit;
        repeat (RANDOM_TRANSACTIONS) begin
            key = key_t'($urandom_range(DICT_SIZE - 1, 0));
            hit = model_valid[key] && $urandom_range(2, 0) != 0;
            transact(hit, key, int'($urandom_range(3, 0)), int'($urandom_range(3, 0)));
        end
    endtask

    initial begin
        done = 1'b0;
        reset_dut();

        // Cancel a stalled miss and later a promotion waiting for commit.
        send_request(1'b0, '0);
        tick();
        check_response(1'b1, '0);
        reset_dut();

        test_segment_operations();
        send_request(1'b1, prob_order[0]);
        check_response(1'b0, '0);
        accept_response();
        tick();
        check_state(2'b00, "promotion before reset");
        reset_dut();

        test_segment_operations();
        test_random_operations();
        $display("PASS DICT_SIZE=%0d N_PROB=%0d (%0d committed transactions)",
                 DICT_SIZE, N_PROB, checked_transactions);
        done = 1'b1;
    end
endmodule

module tdl_slru_policy_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    logic [11:0] done;
    bit test_passed = 1'b0;

    tdl_slru_policy_test #(.DICT_SIZE(2),   .N_PROB(1))   size_2_prob_1     (.done(done[0]));
    tdl_slru_policy_test #(.DICT_SIZE(3),   .N_PROB(1))   size_3_prob_1     (.done(done[1]));
    tdl_slru_policy_test #(.DICT_SIZE(3),   .N_PROB(2))   size_3_prob_2     (.done(done[2]));
    tdl_slru_policy_test #(.DICT_SIZE(5),   .N_PROB(2))   size_5_prob_2     (.done(done[3]));
    tdl_slru_policy_test #(.DICT_SIZE(5),   .N_PROB(4))   size_5_prob_4     (.done(done[4]));
    tdl_slru_policy_test #(.DICT_SIZE(17),  .N_PROB(1))   size_17_prob_1    (.done(done[5]));
    tdl_slru_policy_test #(.DICT_SIZE(17),  .N_PROB(8))   size_17_prob_8    (.done(done[6]));
    tdl_slru_policy_test #(.DICT_SIZE(17),  .N_PROB(16))  size_17_prob_16   (.done(done[7]));
    tdl_slru_policy_test #(.DICT_SIZE(255), .N_PROB(127)) size_255_prob_127 (.done(done[8]));
    tdl_slru_policy_test #(.DICT_SIZE(256), .N_PROB(1))   size_256_prob_1   (.done(done[9]));
    tdl_slru_policy_test #(.DICT_SIZE(256), .N_PROB(64))  size_256_prob_64  (.done(done[10]));
    tdl_slru_policy_test #(.DICT_SIZE(256), .N_PROB(255)) size_256_prob_255 (.done(done[11]));

    initial begin
        wait (&done);
        test_passed = 1'b1;
        $display("All SLRU policy tests passed.");
        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "SLRU policy test timed out. Done mask=%b", done);
    end
endmodule
