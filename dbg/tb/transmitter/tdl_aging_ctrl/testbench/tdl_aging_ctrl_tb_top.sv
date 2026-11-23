module tdl_aging_ctrl_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    localparam time CLK_PERIOD = 20ns;
    localparam int MAX_PERIOD = 65535;
    typedef logic [2:0] ops_t;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic word_commit, aging_disable, bf_en, word_updates_done;
    logic [15:0] aging_period;
    logic cms_aging_req, local_aging_req, bf_rotate_req;
    logic cms_aging_done, local_aging_done, bf_rotate_done;
    logic busy, aging_done;

    int model_period, model_words;
    int checked_commits = 0;
    int checked_services = 0;
    bit test_passed = 1'b0;

    tdl_aging_ctrl dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .word_commit      (word_commit),
        .aging_period     (aging_period),
        .aging_disable    (aging_disable),
        .bf_en            (bf_en),
        .word_updates_done(word_updates_done),
        .cms_aging_req    (cms_aging_req),
        .cms_aging_done   (cms_aging_done),
        .local_aging_req  (local_aging_req),
        .local_aging_done (local_aging_done),
        .bf_rotate_req    (bf_rotate_req),
        .bf_rotate_done   (bf_rotate_done),
        .busy             (busy),
        .aging_done       (aging_done)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    task automatic tick();
        @(posedge clk);
        #1ns;
    endtask

    task automatic check_outputs(
        input bit expected_busy,
        input ops_t expected_requests,
        input bit expected_done,
        input string phase
    );
        ops_t requests;
        requests = {cms_aging_req, local_aging_req, bf_rotate_req};
        if (busy !== expected_busy || requests !== expected_requests || aging_done !== expected_done)
            $fatal(1, "%s after commit %0d at %t: busy/requests/done=%b/%b/%b expected=%b/%b/%b",
                   phase, checked_commits, $time, busy, requests, aging_done,
                   expected_busy, expected_requests, expected_done);
    endtask

    task automatic reset_dut();
        @(negedge clk);
        rst_n             = 1'b0;
        word_commit       = 1'b0;
        aging_period      = '0;
        aging_disable     = 1'b0;
        bf_en             = 1'b0;
        word_updates_done = 1'b0;
        {cms_aging_done, local_aging_done, bf_rotate_done} = '0;
        model_period = 0;
        model_words  = 0;
        #1ns;
        check_outputs(0, '0, 0, "asynchronous reset");
        tick();
        @(negedge clk);
        rst_n = 1'b1;
        tick();
        check_outputs(0, '0, 0, "after reset");
    endtask

    task automatic commit_word(
        input int period,
        input bit disable_aging,
        input bit enable_bf,
        output ops_t expected_operations
    );
        expected_operations = '0;
        if (period != model_period || period == 0 || (disable_aging && !enable_bf))
            model_words = 0;
        model_period = period;
        if (period > 0 && (!disable_aging || enable_bf)) begin
            model_words++;
            if (model_words == period) begin
                model_words = 0;
                expected_operations[2:1] = disable_aging ? 2'b00 : 2'b11;
                expected_operations[0]   = enable_bf;
            end
        end

        @(negedge clk);
        word_commit       = 1'b1;
        aging_period      = 16'(period);
        aging_disable     = disable_aging;
        bf_en             = enable_bf;
        word_updates_done = 1'b1; // Completion level from the preceding word.
        tick();
        word_commit       = 1'b0;
        word_updates_done = 1'b0;
        aging_period      = ~16'(period);
        aging_disable     = !disable_aging;
        bf_en             = !enable_bf;
        checked_commits++;
        check_outputs(expected_operations != '0, '0, 0, "commit");
    endtask

    task automatic issue_operations(input ops_t operations, input int update_delay);
        repeat (update_delay) begin
            tick();
            check_outputs(1, '0, 0, "ordinary writes pending");
        end
        @(negedge clk);
        word_updates_done = 1'b1;
        tick();
        check_outputs(1, operations, 0, "service requests");
        tick();
        check_outputs(1, '0, 0, "requests accepted");
    endtask

    task automatic complete_operations(
        input ops_t operations,
        input int cms_delay,
        input int local_delay,
        input int bf_delay
    );
        int last_cycle;
        last_cycle = operations[2] ? cms_delay : 0;
        if (operations[1] && local_delay > last_cycle)
            last_cycle = local_delay;
        if (operations[0] && bf_delay > last_cycle)
            last_cycle = bf_delay;

        for (int cycle = 1; cycle <= last_cycle; cycle++) begin
            @(negedge clk);
            cms_aging_done   = operations[2] && cycle == cms_delay;
            local_aging_done = operations[1] && cycle == local_delay;
            bf_rotate_done   = operations[0] && cycle == bf_delay;
            tick();
            check_outputs(cycle < last_cycle, '0, cycle == last_cycle, "executor completion");
        end
        checked_services++;

        @(negedge clk);
        {cms_aging_done, local_aging_done, bf_rotate_done} = '0;
        tick();
        check_outputs(0, '0, 0, "aging_done pulse ended");
    endtask

    task automatic transact(
        input int period,
        input bit disable_aging,
        input bit enable_bf,
        input int update_delay = 1,
        input int cms_delay = 4,
        input int local_delay = 1,
        input int bf_delay = 2
    );
        ops_t operations;
        commit_word(period, disable_aging, enable_bf, operations);
        if (operations != '0) begin
            issue_operations(operations, update_delay);
            complete_operations(operations, cms_delay, local_delay, bf_delay);
        end
    endtask

    task automatic test_periods();
        repeat (4) transact(0, 0, 1);
        repeat (3) transact(1, 0, 1);

        // Change N in both directions before the current interval expires.
        repeat (2) transact(5, 0, 1);
        repeat (2) transact(2, 0, 1);
        transact(4, 0, 1);
        repeat (8) begin
            tick();
            check_outputs(0, '0, 0, "idle cycles do not count");
        end
        repeat (7) transact(7, 0, 1);
        repeat (MAX_PERIOD) transact(MAX_PERIOD, 1, 1);
    endtask

    task automatic test_enable_modes();
        transact(1, 1, 0);
        transact(1, 1, 1, 12, 4, 3, 1);
        transact(1, 0, 0, 0, 1, 5, 4);
        transact(1, 0, 1, 2, 3, 3, 3);
        transact(1, 0, 1, 2, 1, 2, 6);

        // No enabled operation discards a partial interval.
        transact(2, 0, 1);
        transact(2, 1, 0);
        transact(2, 0, 1);
        transact(2, 1, 1);
    endtask

    task automatic test_reset_in_flight();
        ops_t operations;
        transact(2, 0, 1);
        reset_dut();
        repeat (2) transact(2, 0, 1);

        commit_word(1, 0, 1, operations);
        reset_dut();
        commit_word(1, 0, 1, operations);
        issue_operations(operations, 2);
        @(negedge clk);
        cms_aging_done = 1'b1;
        tick();
        check_outputs(1, '0, 0, "partial completion before reset");
        reset_dut();
        transact(1, 0, 1, 0, 5, 2, 1);
    endtask

    task automatic test_random_intervals();
        int period;
        bit disable_aging, enable_bf;
        repeat (60) begin
            period        = int'($urandom_range(8, 0));
            disable_aging = bit'($urandom_range(1, 0));
            enable_bf     = bit'($urandom_range(1, 0));
            repeat (23)
                transact(period, disable_aging, enable_bf, int'($urandom_range(4, 0)),
                         int'($urandom_range(7, 1)), int'($urandom_range(7, 1)),
                         int'($urandom_range(7, 1)));
        end
    endtask

    initial begin
        reset_dut();
        test_periods();
        test_enable_modes();
        test_reset_in_flight();
        test_random_intervals();
        test_passed = 1'b1;
        $display("All aging controller tests passed (%0d word commits, %0d completed services).",
                 checked_commits, checked_services);
        $finish;
    end

    initial begin
        #4ms;
        $fatal(1, "Aging controller test timed out");
    end
endmodule
