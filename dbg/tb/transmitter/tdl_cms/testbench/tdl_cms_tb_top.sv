module tdl_cms_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    localparam time CLK_PERIOD = 20ns;
    localparam int ROW_DEPTH = 256;
    localparam int MAX_COUNT = 15;
    localparam int AGING_CYCLES = 2 * ROW_DEPTH;
    localparam int RANDOM_TRANSACTIONS = 1600;
    typedef logic [7:0] hash_t;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic req_valid, req_ready, req_cu_disable;
    hash_t req_h0, req_h1;
    logic rsp_valid, rsp_ready;
    logic [3:0] rsp_est;
    logic commit, aging_req, aging_done, busy;

    int model_row0 [0:ROW_DEPTH-1];
    int model_row1 [0:ROW_DEPTH-1];
    int checked_transactions = 0;
    int checked_aging = 0;
    bit test_passed = 1'b0;

    tdl_cms dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .req_valid     (req_valid),
        .req_ready     (req_ready),
        .req_h0        (req_h0),
        .req_h1        (req_h1),
        .req_cu_disable(req_cu_disable),
        .rsp_valid     (rsp_valid),
        .rsp_ready     (rsp_ready),
        .rsp_est       (rsp_est),
        .commit        (commit),
        .aging_req     (aging_req),
        .aging_done    (aging_done),
        .busy          (busy)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    task automatic tick();
        @(posedge clk);
        #1ns;
    endtask

    task automatic check_flags(input logic [3:0] expected, input string phase);
        if ({busy, req_ready, rsp_valid, aging_done} !== expected)
            $fatal(1, "%s at %t: busy/req_ready/rsp_valid/aging_done=%b expected=%b",
                   phase, $time, {busy, req_ready, rsp_valid, aging_done}, expected);
    endtask

    // The estimate alone cannot distinguish CU from standard updates.
    task automatic check_counters(input hash_t h0, input hash_t h1, input string phase);
        if (dut.gen_bank[0].memory[h0] !== 4'(model_row0[h0]) ||
            dut.gen_bank[1].memory[h1] !== 4'(model_row1[h1]))
            $fatal(1, "%s: row0[%0d]=%0d expected=%0d, row1[%0d]=%0d expected=%0d",
                   phase, h0, dut.gen_bank[0].memory[h0], model_row0[h0],
                   h1, dut.gen_bank[1].memory[h1], model_row1[h1]);
    endtask

    task automatic check_table(input string phase);
        for (int address = 0; address < ROW_DEPTH; address++)
            check_counters(hash_t'(address), hash_t'(address), phase);
    endtask

    task automatic reset_dut();
        @(negedge clk);
        rst_n          = 1'b0;
        req_valid      = 1'b0;
        req_h0         = '0;
        req_h1         = '0;
        req_cu_disable = 1'b0;
        rsp_ready      = 1'b0;
        commit         = 1'b0;
        aging_req      = 1'b0;
        #1ns;
        check_flags(4'b0000, "reset");
        tick();

        for (int address = 0; address < ROW_DEPTH; address++) begin
            model_row0[address] = 0;
            model_row1[address] = 0;
        end
        @(negedge clk);
        rst_n = 1'b1;
        repeat (ROW_DEPTH - 1) begin
            tick();
            check_flags(4'b1000, "initialization");
        end
        tick();
        check_flags(4'b0100, "initialization complete");
        check_table("initialization complete");
    endtask

    task automatic send_request(input hash_t h0, input hash_t h1, input bit standard_update);
        if (req_ready !== 1'b1)
            $fatal(1, "Request h0=%0d h1=%0d started while not ready", h0, h1);
        @(negedge clk);
        req_valid      = 1'b1;
        req_h0         = h0;
        req_h1         = h1;
        req_cu_disable = standard_update;
        tick();
        req_valid      = 1'b0;
        req_h0         = ~h0;
        req_h1         = ~h1;
        req_cu_disable = !standard_update;
        check_flags(4'b1000, "RAM read");
        tick();
        check_flags(4'b1010, "estimate ready");
    endtask

    task automatic check_response(input hash_t h0, input hash_t h1, input int estimate);
        check_flags(4'b1010, "response before commit");
        if (rsp_est !== 4'(estimate))
            $fatal(1, "h0=%0d h1=%0d: rsp_est=%0d expected=%0d", h0, h1, rsp_est, estimate);
        check_counters(h0, h1, "response before commit");
    endtask

    task automatic accept_response();
        @(negedge clk);
        rsp_ready = 1'b1;
        tick();
        rsp_ready = 1'b0;
        check_flags(4'b1000, "waiting for commit");
    endtask

    task automatic wait_for_aging();
        repeat (AGING_CYCLES - 1) begin
            tick();
            check_flags(4'b1000, "aging in progress");
        end
        tick();
        check_flags(4'b0101, "aging complete");
        for (int address = 0; address < ROW_DEPTH; address++) begin
            model_row0[address] /= 2;
            model_row1[address] /= 2;
        end
        check_table("aging complete");
        checked_aging++;
    endtask

    task automatic transact(
        input hash_t h0,
        input hash_t h1,
        input bit standard_update,
        input int response_stall = 0,
        input int commit_stall = 0,
        input bit age_with_commit = 1'b0
    );
        int old_c0, old_c1, next_c0, next_c1, estimate;
        old_c0 = model_row0[h0];
        old_c1 = model_row1[h1];
        next_c0 = old_c0;
        next_c1 = old_c1;
        if (old_c0 < MAX_COUNT && (standard_update || old_c0 <= old_c1))
            next_c0++;
        if (old_c1 < MAX_COUNT && (standard_update || old_c1 <= old_c0))
            next_c1++;
        estimate = (next_c0 < next_c1) ? next_c0 : next_c1;

        send_request(h0, h1, standard_update);
        check_response(h0, h1, estimate);
        repeat (response_stall) begin
            tick();
            check_response(h0, h1, estimate);
        end
        accept_response();
        repeat (commit_stall) begin
            tick();
            check_flags(4'b1000, "commit stall");
            check_counters(h0, h1, "commit stall");
        end
        check_counters(h0, h1, "before commit");

        @(negedge clk);
        commit    = 1'b1;
        aging_req = age_with_commit;
        tick();
        commit    = 1'b0;
        aging_req = 1'b0;
        model_row0[h0] = next_c0;
        model_row1[h1] = next_c1;
        check_counters(h0, h1, "commit complete");
        checked_transactions++;

        if (age_with_commit) begin
            check_flags(4'b1000, "aging started by commit");
            wait_for_aging();
            tick();
        end
        check_flags(4'b0100, "ready for next request");
    endtask

    task automatic start_aging(input bit queue_request);
        check_flags(4'b0100, "before aging");
        @(negedge clk);
        if (queue_request) begin
            req_valid      = 1'b1;
            req_h0         = '0;
            req_h1         = 8'hff;
            req_cu_disable = 1'b0;
        end
        aging_req = 1'b1;
        #1ns;
        check_flags(4'b0000, "aging takes priority over request");
        tick();
        aging_req = 1'b0;
        check_flags(4'b1000, "aging started");
    endtask

    task automatic age(input bit queue_request = 1'b0);
        start_aging(queue_request);
        wait_for_aging();
        if (queue_request)
            transact('0, 8'hff, 1'b0);
        else begin
            tick();
            check_flags(4'b0100, "aging_done pulse ended");
        end
    endtask

    task automatic test_update_modes();
        transact(8'h00, 8'h00, 1'b0); // CU tie increments both banks.
        repeat (2)
            transact(8'h00, 8'h01, 1'b1);
        transact(8'h00, 8'h02, 1'b0, 3, 2); // Only row 1 is incremented.
        transact(8'h02, 8'h00, 1'b0);       // Only row 0 is incremented.
        transact(8'h00, 8'h02, 1'b1, 2, 3); // Standard update increments both.
        repeat (20)
            transact(8'hff, 8'hff, 1'b0);
        transact(8'hff, 8'hff, 1'b1);
        transact(8'hff, 8'hfe, 1'b1); // One bank saturated, one still increments.
        transact(8'hfe, 8'hff, 1'b0);
        check_table("update modes complete");
    endtask

    task automatic test_aging();
        // Both addressed counters must follow 3 -> 4 -> 2, including the last address.
        repeat (3)
            transact('0, 8'hff, 1'b1);
        transact('0, 8'hff, 1'b1, 1, 2, 1'b1);

        for (int address = 0; address < ROW_DEPTH; address++)
            repeat (1 + address % 5)
                transact(hash_t'(address), hash_t'(address) ^ 8'ha5, 1'b1);
        age(1'b1); // A queued lookup must observe aged counters.
        age();
    endtask

    task automatic test_reset_in_flight();
        send_request(8'h21, 8'h42, 1'b0);
        tick();
        check_flags(4'b1010, "response before reset");
        reset_dut();
        transact(8'h21, 8'h42, 1'b0);

        send_request(8'h21, 8'h42, 1'b1);
        accept_response();
        tick();
        check_flags(4'b1000, "commit stalled before reset");
        reset_dut();
        transact(8'h21, 8'h42, 1'b1);
        transact(8'ha1, 8'hc2, 1'b1);

        start_aging(1'b0);
        repeat (80) tick();
        check_flags(4'b1000, "reset during aging");
        reset_dut();
        transact(8'h21, 8'h42, 1'b0);
    endtask

    task automatic test_random_operations();
        hash_t h0, h1;
        bit standard_update;
        repeat (RANDOM_TRANSACTIONS) begin
            h0 = hash_t'($urandom_range(ROW_DEPTH - 1, 0));
            h1 = hash_t'($urandom_range(ROW_DEPTH - 1, 0));
            standard_update = bit'($urandom_range(1, 0));
            if ($urandom_range(63, 0) == 0)
                age();
            transact(h0, h1, standard_update, int'($urandom_range(2, 0)),
                     int'($urandom_range(2, 0)), $urandom_range(63, 0) == 0);
        end
        check_table("random operations complete");
    endtask

    initial begin
        reset_dut();
        test_update_modes();
        reset_dut();
        test_aging();
        test_reset_in_flight();
        test_random_operations();
        test_passed = 1'b1;
        $display("All CMS tests passed (%0d committed transactions, %0d aging sweeps).",
                 checked_transactions, checked_aging);
        $finish;
    end

    initial begin
        #4ms;
        $fatal(1, "CMS test timed out");
    end
endmodule
