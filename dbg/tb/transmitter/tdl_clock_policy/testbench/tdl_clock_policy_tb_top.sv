module tdl_clock_policy_test #(
    parameter int DICT_SIZE = 5
) (
    output logic done
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam int KEY_WIDTH = $clog2(DICT_SIZE);
    localparam time CLK_PERIOD = 20ns;
    localparam int RANDOM_TRANSACTIONS = 400;
    typedef logic [KEY_WIDTH-1:0] key_t;

    logic clk = 1'b0;
    logic rst_n;
    logic req_valid, req_ready, req_hit;
    logic rsp_valid, rsp_ready, rsp_admit, commit;
    key_t req_hit_key, next_free_key, rsp_key;
    logic [DICT_SIZE-1:0] valid_bits;
    logic dict_full;

    logic [DICT_SIZE-1:0] model_usage;
    int model_hand;
    int checked_transactions = 0;

    tdl_clock_policy #(
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

    // The testbench models the storage status seen by the policy.
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

    task automatic check_metadata(input string phase);
        if (dut.usage_bit !== model_usage || dut.clock_hand !== key_t'(model_hand))
            $fatal(1, "DICT_SIZE=%0d %s: usage=%h hand=%0d, expected usage=%h hand=%0d",
                   DICT_SIZE, phase, dut.usage_bit, dut.clock_hand, model_usage, model_hand);
    endtask

    task automatic initialize();
        rst_n       = 1'b0;
        req_valid   = 1'b0;
        req_hit     = 1'b0;
        req_hit_key = '0;
        rsp_ready   = 1'b0;
        commit      = 1'b0;
        valid_bits  = '0;
        model_usage = '0;
        model_hand  = 0;

        tick();
        if ({req_ready, rsp_valid} !== 2'b00)
            $fatal(1, "DICT_SIZE=%0d handshake active during reset", DICT_SIZE);
        check_metadata("reset");

        rst_n = 1'b1;
        #1ns;
        if ({req_ready, rsp_valid} !== 2'b10)
            $fatal(1, "DICT_SIZE=%0d policy did not return to idle after reset", DICT_SIZE);
    endtask

    task automatic send_request(input bit hit, input key_t hit_key);
        if ({req_ready, rsp_valid} !== 2'b10)
            $fatal(1, "DICT_SIZE=%0d policy unavailable before request", DICT_SIZE);

        req_hit     = hit;
        req_hit_key = hit_key;
        req_valid   = 1'b1;
        tick();
        req_valid   = 1'b0;
        // Payload may change after acceptance, even while the policy is busy.
        req_hit     = !hit;
        req_hit_key = key_t'(DICT_SIZE - 1) ^ hit_key;

        if (req_ready !== 1'b0)
            $fatal(1, "DICT_SIZE=%0d policy ready with a request outstanding", DICT_SIZE);
        if (rsp_valid !== (hit || !dict_full))
            $fatal(1, "DICT_SIZE=%0d unexpected initial response timing", DICT_SIZE);
        check_metadata("request acceptance");
    endtask

    task automatic wait_for_response();
        int scan_cycles;
        scan_cycles = 0;
        while (rsp_valid === 1'b0 && scan_cycles < DICT_SIZE + 1) begin
            tick();
            if (req_ready !== 1'b0)
                $fatal(1, "DICT_SIZE=%0d policy ready during scan", DICT_SIZE);
            check_metadata("scan");
            scan_cycles++;
        end
        if (rsp_valid !== 1'b1)
            $fatal(1, "DICT_SIZE=%0d response missing after %0d scan cycles",
                   DICT_SIZE, scan_cycles);
    endtask

    task automatic check_response(input bit admit, input key_t key);
        if ({req_ready, rsp_valid} !== 2'b01 || rsp_admit !== admit || rsp_key !== key)
            $fatal(1, "DICT_SIZE=%0d response ready=%b valid=%b admit=%b key=%0d, expected admit=%b key=%0d",
                   DICT_SIZE, req_ready, rsp_valid, rsp_admit, rsp_key, admit, key);
        check_metadata("response before commit");
    endtask

    task automatic check_wait_for_commit();
        if ({req_ready, rsp_valid} !== 2'b00)
            $fatal(1, "DICT_SIZE=%0d unexpected handshake while waiting for commit", DICT_SIZE);
        check_metadata("waiting for commit");
    endtask

    task automatic accept_response();
        rsp_ready = 1'b1;
        tick();
        rsp_ready = 1'b0;
        check_wait_for_commit();
    endtask

    task automatic transact(
        input bit hit,
        input key_t hit_key,
        input int response_stall = 0,
        input int commit_stall = 0
    );
        logic [DICT_SIZE-1:0] next_usage;
        int next_hand;
        int selected_key;
        key_t expected_key;

        // Compute the complete next state in software order, independent of scan timing.
        next_usage = model_usage;
        next_hand = model_hand;
        if (hit) begin
            selected_key = int'(hit_key);
        end else if (!dict_full) begin
            selected_key = int'(next_free_key);
        end else begin
            selected_key = model_hand;
            while (next_usage[selected_key]) begin
                next_usage[selected_key] = 1'b0;
                selected_key = (selected_key + 1) % DICT_SIZE;
            end
            next_hand = (selected_key + 1) % DICT_SIZE;
        end
        next_usage[selected_key] = 1'b1;
        expected_key = hit ? '0 : key_t'(selected_key);

        send_request(hit, hit_key);
        wait_for_response();
        check_response(!hit, expected_key);
        repeat (response_stall) begin
            tick();
            check_response(!hit, expected_key);
        end
        accept_response();
        repeat (commit_stall) begin
            tick();
            check_wait_for_commit();
        end

        commit = 1'b1;
        tick();
        commit = 1'b0;
        if (!hit)
            valid_bits[selected_key] = 1'b1;
        model_usage = next_usage;
        model_hand = next_hand;
        check_metadata("commit");
        if ({req_ready, rsp_valid} !== 2'b10)
            $fatal(1, "DICT_SIZE=%0d policy did not return to idle after commit", DICT_SIZE);
        checked_transactions++;
        #1ns; // Let dict_full and next_free_key settle before the next request.
    endtask

    task automatic fill_dictionary();
        repeat (DICT_SIZE)
            transact(1'b0, '0);
    endtask

    task automatic test_reset_in_flight();
        fill_dictionary();
        // Start clearing usage bits, then reset while the full scan is underway.
        send_request(1'b0, '0);
        tick();
        if ({req_ready, rsp_valid} !== 2'b00)
            $fatal(1, "DICT_SIZE=%0d scan ended before reset test", DICT_SIZE);
        check_metadata("scan before reset");
        initialize();

        send_request(1'b0, '0);
        tick();
        check_response(1'b1, '0);
        initialize();

        send_request(1'b0, '0);
        check_response(1'b1, '0);
        accept_response();
        initialize();
    endtask

    task automatic test_replacement();
        fill_dictionary();
        // All usage bits are set. The miss must complete a full sweep.
        transact(1'b0, '0, 3, 4);
        // A hit at the next candidate gives that row a second chance.
        transact(1'b1, key_t'(1), 2, 3);
        repeat (DICT_SIZE + 1)
            transact(1'b0, '0);
    endtask

    task automatic test_random_operations();
        repeat (RANDOM_TRANSACTIONS)
            transact(bit'($urandom_range(1, 0)), key_t'($urandom_range(DICT_SIZE - 1, 0)),
                     int'($urandom_range(4, 0)), int'($urandom_range(4, 0)));
    endtask

    initial begin
        done = 1'b0;
        initialize();
        test_reset_in_flight();
        test_replacement();
        test_random_operations();
        $display("PASS DICT_SIZE=%0d (%0d committed transactions)", DICT_SIZE, checked_transactions);
        done = 1'b1;
    end
endmodule

module tdl_clock_policy_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    logic [3:0] done;
    bit test_passed = 1'b0;

    tdl_clock_policy_test #(.DICT_SIZE(2))   test_size_2   (.done(done[0]));
    tdl_clock_policy_test #(.DICT_SIZE(5))   test_size_5   (.done(done[1]));
    tdl_clock_policy_test #(.DICT_SIZE(255)) test_size_255 (.done(done[2]));
    tdl_clock_policy_test #(.DICT_SIZE(256)) test_size_256 (.done(done[3]));

    initial begin
        wait (&done);
        test_passed = 1'b1;
        $display("All Clock policy tests passed.");
        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "Clock policy test timed out. Done mask=%b", done);
    end
endmodule
