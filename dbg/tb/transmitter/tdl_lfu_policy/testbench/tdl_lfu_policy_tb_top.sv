module tdl_lfu_policy_test #(
    parameter int DICT_SIZE = 5
) (
    output logic done
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam int KEY_WIDTH = $clog2(DICT_SIZE);
    localparam time CLK_PERIOD = 20ns;
    typedef logic [KEY_WIDTH-1:0] key_t;
    typedef logic [3:0] count_t;

    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic req_valid, req_ready, req_hit;
    logic rsp_valid, rsp_ready, rsp_admit, commit;
    key_t req_hit_key, next_free_key, rsp_key;
    logic [DICT_SIZE-1:0] valid_bits;
    logic dict_full;

    logic [DICT_SIZE-1:0] model_valid;
    count_t model_count [0:DICT_SIZE-1];
    int checked_transactions = 0;

    tdl_lfu_policy #(
        .DICT_SIZE(DICT_SIZE)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .req_valid    (req_valid),
        .req_ready    (req_ready),
        .req_hit      (req_hit),
        .req_hit_key  (req_hit_key),
        .valid_bits   (valid_bits),
        .dict_full    (dict_full),
        .next_free_key(next_free_key),
        .rsp_valid    (rsp_valid),
        .rsp_ready    (rsp_ready),
        .rsp_admit    (rsp_admit),
        .rsp_key      (rsp_key),
        .commit       (commit)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    assign valid_bits = model_valid;
    assign dict_full = &valid_bits;

    always_comb begin
        next_free_key = '0;
        for (int key = DICT_SIZE - 1; key >= 0; key--)
            if (!valid_bits[key])
                next_free_key = key_t'(key);
    end

    task automatic tick();
        @(posedge clk);
        #1ns;
    endtask

    task automatic check_counts(input string phase);
        for (int key = 0; key < DICT_SIZE; key++) begin
            if (dut.local_cnt[key] !== model_count[key])
                $fatal(1, "DICT_SIZE=%0d %s: count[%0d]=%0d, expected %0d",
                       DICT_SIZE, phase, key, dut.local_cnt[key], model_count[key]);
        end
    endtask

    task automatic reset_dut();
        @(negedge clk);
        req_valid   = 1'b0;
        req_hit     = 1'b0;
        req_hit_key = '0;
        rsp_ready   = 1'b0;
        commit      = 1'b0;
        model_valid = '0;
        for (int key = 0; key < DICT_SIZE; key++)
            model_count[key] = '0;
        rst_n = 1'b0;
        #1ns;
        if ({req_ready, rsp_valid} !== 2'b00)
            $fatal(1, "DICT_SIZE=%0d outputs active during reset", DICT_SIZE);
        check_counts("asynchronous reset");
        tick();
        check_counts("reset clock");

        @(negedge clk);
        rst_n = 1'b1;
        #1ns;
        if ({req_ready, rsp_valid} !== 2'b10)
            $fatal(1, "DICT_SIZE=%0d did not return to idle after reset", DICT_SIZE);
    endtask

    task automatic transact(
        input bit hit,
        input key_t hit_key,
        input int response_stall = 0,
        input int commit_stall = 0
    );
        int selected_key;
        int min_count;
        key_t expected_key;
        bit expected_admit;

        if ({req_ready, rsp_valid} !== 2'b10)
            $fatal(1, "DICT_SIZE=%0d policy not idle before request", DICT_SIZE);

        expected_admit = !hit;
        if (hit) begin
            selected_key = int'(hit_key);
            if (selected_key >= DICT_SIZE || !model_valid[selected_key])
                $fatal(1, "DICT_SIZE=%0d test generated invalid hit key %0d",
                       DICT_SIZE, selected_key);
        end else if (!dict_full) begin
            selected_key = -1;
            for (int key = 0; key < DICT_SIZE; key++)
                if (!model_valid[key] && selected_key == -1)
                    selected_key = key;
            if (selected_key == -1)
                $fatal(1, "DICT_SIZE=%0d reference model found no free key", DICT_SIZE);
        end else begin
            selected_key = -1;
            min_count = 16;
            for (int key = 0; key < DICT_SIZE; key++) begin
                if (model_valid[key] && int'(model_count[key]) < min_count) begin
                    selected_key = key;
                    min_count = int'(model_count[key]);
                end
            end
            if (selected_key == -1)
                $fatal(1, "DICT_SIZE=%0d reference model found no LFU victim", DICT_SIZE);
        end
        expected_key = expected_admit ? key_t'(selected_key) : '0;

        @(negedge clk);
        req_hit     = hit;
        req_hit_key = hit_key;
        req_valid   = 1'b1;
        @(posedge clk);
        #1ns;
        req_valid = 1'b0;
        req_hit = !hit;
        req_hit_key = ~hit_key;

        if (req_ready !== 1'b0 || rsp_valid !== 1'b1)
            $fatal(1, "DICT_SIZE=%0d incorrect response timing", DICT_SIZE);
        if (rsp_admit !== expected_admit || rsp_key !== expected_key)
            $fatal(1, "DICT_SIZE=%0d response admit=%b key=%0d, expected admit=%b key=%0d",
                   DICT_SIZE, rsp_admit, rsp_key, expected_admit, expected_key);
        check_counts("response");

        repeat (response_stall) begin
            tick();
            if (rsp_valid !== 1'b1 || rsp_admit !== expected_admit || rsp_key !== expected_key)
                $fatal(1, "DICT_SIZE=%0d response changed while stalled", DICT_SIZE);
            check_counts("response stall");
        end

        @(negedge clk);
        rsp_ready = 1'b1;
        tick();
        rsp_ready = 1'b0;
        if ({req_ready, rsp_valid} !== 2'b00)
            $fatal(1, "DICT_SIZE=%0d did not wait for commit after response", DICT_SIZE);
        check_counts("waiting for commit");

        repeat (commit_stall) begin
            tick();
            if ({req_ready, rsp_valid} !== 2'b00)
                $fatal(1, "DICT_SIZE=%0d left commit wait without commit", DICT_SIZE);
            check_counts("commit stall");
        end

        @(negedge clk);
        commit = 1'b1;
        tick();
        commit = 1'b0;

        if (hit) begin
            if (model_count[selected_key] != 4'hf)
                model_count[selected_key] = model_count[selected_key] + 1'b1;
        end else begin
            model_valid[selected_key] = 1'b1;
            model_count[selected_key] = 4'd1;
        end
        check_counts("commit");
        if ({req_ready, rsp_valid} !== 2'b10)
            $fatal(1, "DICT_SIZE=%0d did not return to idle after commit", DICT_SIZE);
        checked_transactions++;
    endtask

    task automatic test_reset_during_transaction();
        @(negedge clk);
        req_hit = 1'b0;
        req_hit_key = '0;
        req_valid = 1'b1;
        @(posedge clk);
        #1ns;
        req_valid = 1'b0;
        if (rsp_valid !== 1'b1 || rsp_admit !== 1'b1 || rsp_key !== '0)
            $fatal(1, "DICT_SIZE=%0d unexpected response before reset", DICT_SIZE);
        reset_dut();

        @(negedge clk);
        req_hit = 1'b0;
        req_hit_key = '0;
        req_valid = 1'b1;
        @(posedge clk);
        #1ns;
        req_valid = 1'b0;
        @(negedge clk);
        rsp_ready = 1'b1;
        tick();
        rsp_ready = 1'b0;
        if ({req_ready, rsp_valid} !== 2'b00)
            $fatal(1, "DICT_SIZE=%0d expected commit wait before reset", DICT_SIZE);
        reset_dut();
    endtask

    task automatic test_random_operations();
        int valid_count;
        int selected_rank;
        int hit_key;
        bit do_hit;
        bit found_key;

        repeat (300) begin
            valid_count = 0;
            for (int key = 0; key < DICT_SIZE; key++)
                if (model_valid[key])
                    valid_count++;

            do_hit = valid_count != 0 && $urandom_range(0, 2) != 0;
            hit_key = 0;
            if (do_hit) begin
                selected_rank = $urandom_range(valid_count - 1, 0);
                found_key = 1'b0;
                for (int key = 0; key < DICT_SIZE; key++) begin
                    if (model_valid[key] && !found_key) begin
                        if (selected_rank == 0) begin
                            hit_key = key;
                            found_key = 1'b1;
                        end else begin
                            selected_rank--;
                        end
                    end
                end
            end
            transact(do_hit, key_t'(hit_key),
                     int'($urandom_range(3, 0)), int'($urandom_range(3, 0)));
        end
    endtask

    initial begin
        done = 1'b0;
        reset_dut();
        test_reset_during_transaction();

        transact(1'b0, '0, 3, 2);
        repeat (DICT_SIZE - 1)
            transact(1'b0, '0);
        for (int key = 0; key < DICT_SIZE; key++)
            transact(1'b1, key_t'(key), 1, 1);

        repeat (20)
            transact(1'b1, '0);

        // All nonzero rows tie for the minimum; the lowest key must win.
        transact(1'b0, '0, 2, 3);
        transact(1'b0, '0);
        test_random_operations();

        $display("PASS DICT_SIZE=%0d (%0d committed transactions)",
                 DICT_SIZE, checked_transactions);
        done = 1'b1;
    end
endmodule

module tdl_lfu_policy_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    logic [5:0] done;
    bit test_passed = 1'b0;

    tdl_lfu_policy_test #(.DICT_SIZE(2))   test_size_2   (.done(done[0]));
    tdl_lfu_policy_test #(.DICT_SIZE(3))   test_size_3   (.done(done[1]));
    tdl_lfu_policy_test #(.DICT_SIZE(5))   test_size_5   (.done(done[2]));
    tdl_lfu_policy_test #(.DICT_SIZE(17))  test_size_17  (.done(done[3]));
    tdl_lfu_policy_test #(.DICT_SIZE(255)) test_size_255 (.done(done[4]));
    tdl_lfu_policy_test #(.DICT_SIZE(256)) test_size_256 (.done(done[5]));

    initial begin
        wait (&done);
        test_passed = 1'b1;
        $display("All LFU policy tests passed.");
        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "LFU policy test timed out. Done mask=%b", done);
    end
endmodule
