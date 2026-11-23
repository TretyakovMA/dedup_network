module tdl_bloom_filter_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    localparam time CLK_PERIOD = 20ns;
    localparam int HASH_WIDTH = 12;
    localparam int BIT_COUNT = 1 << HASH_WIDTH;
    localparam int WORD_WIDTH = 32;
    localparam int BANK_WORDS = BIT_COUNT / WORD_WIDTH;
    localparam int RANDOM_TRANSACTIONS = 1600;
    typedef logic [HASH_WIDTH-1:0] hash_t;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic req_valid, req_ready;
    hash_t req_h0, req_h1;
    logic rsp_valid, rsp_ready, rsp_seen;
    logic commit, rotate_req, rotate_done, busy;

    bit [BIT_COUNT-1:0] model_active, model_old;
    int checked_transactions = 0;
    int checked_rotations = 0;
    bit test_passed = 1'b0;

    tdl_bloom_filter dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .req_valid  (req_valid),
        .req_ready  (req_ready),
        .req_h0     (req_h0),
        .req_h1     (req_h1),
        .rsp_valid  (rsp_valid),
        .rsp_ready  (rsp_ready),
        .rsp_seen   (rsp_seen),
        .commit     (commit),
        .rotate_req (rotate_req),
        .rotate_done(rotate_done),
        .busy       (busy)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    task automatic tick();
        @(posedge clk);
        #1ns;
    endtask

    task automatic check_flags(input logic [3:0] expected, input string phase);
        if ({busy, req_ready, rsp_valid, rotate_done} !== expected)
            $fatal(1, "%s at %t: busy/req_ready/rsp_valid/rotate_done=%b expected=%b",
                   phase, $time, {busy, req_ready, rsp_valid, rotate_done}, expected);
    endtask

    // Compare the touched words to detect writes before commit and to neighboring bits.
    task automatic check_bank_word(input int word_index, input string phase);
        logic [WORD_WIDTH-1:0] active_word, old_word;
        logic [WORD_WIDTH-1:0] expected_active, expected_old;
        if (dut.active_bank) begin
            active_word = dut.gen_bank[1].memory[word_index];
            old_word    = dut.gen_bank[0].memory[word_index];
        end else begin
            active_word = dut.gen_bank[0].memory[word_index];
            old_word    = dut.gen_bank[1].memory[word_index];
        end
        expected_active = model_active[word_index*WORD_WIDTH +: WORD_WIDTH];
        expected_old    = model_old[word_index*WORD_WIDTH +: WORD_WIDTH];
        if (active_word !== expected_active || old_word !== expected_old)
            $fatal(1, "%s: RAM word %0d active/old=%h/%h expected=%h/%h",
                   phase, word_index, active_word, old_word, expected_active, expected_old);
    endtask

    task automatic reset_dut();
        @(negedge clk);
        rst_n        = 1'b0;
        req_valid    = 1'b0;
        req_h0       = '0;
        req_h1       = '0;
        rsp_ready    = 1'b0;
        commit       = 1'b0;
        rotate_req   = 1'b0;
        model_active = '0;
        model_old    = '0;
        #1ns;
        check_flags(4'b1000, "reset");
        tick();

        @(negedge clk);
        rst_n = 1'b1;
        repeat (BANK_WORDS - 1) begin
            tick();
            check_flags(4'b1000, "initialization");
        end
        tick();
        check_flags(4'b0100, "initialization complete");
        for (int word_index = 0; word_index < BANK_WORDS; word_index++)
            check_bank_word(word_index, "initialization complete");
    endtask

    task automatic send_request(input hash_t h0, input hash_t h1);
        if (req_ready !== 1'b1)
            $fatal(1, "Request h0=%0d h1=%0d started while not ready", h0, h1);
        @(negedge clk);
        req_valid = 1'b1;
        req_h0 = h0;
        req_h1 = h1;
        tick();
        req_valid = 1'b0;
        req_h0 = ~h0;
        req_h1 = ~h1;
        check_flags(4'b1000, "first RAM read");
        tick();
        check_flags(4'b1000, "second RAM read");
        tick();
        check_flags(4'b1010, "lookup response");
    endtask

    task automatic check_response(input hash_t h0, input hash_t h1, input bit expected);
        check_flags(4'b1010, "response before commit");
        if (rsp_seen !== expected)
            $fatal(1, "h0=%0d h1=%0d: rsp_seen=%b expected=%b", h0, h1, rsp_seen, expected);
    endtask

    task automatic accept_response();
        @(negedge clk);
        rsp_ready = 1'b1;
        tick();
        rsp_ready = 1'b0;
        check_flags(4'b1000, "waiting for commit");
    endtask

    task automatic transact(
        input hash_t h0,
        input hash_t h1,
        input int response_stall = 0,
        input int commit_stall = 0
    );
        int word_h0, word_h1;
        bit expected;

        word_h0 = int'(h0) / WORD_WIDTH;
        word_h1 = int'(h1) / WORD_WIDTH;
        expected = (model_active[h0] || model_old[h0]) &&
                   (model_active[h1] || model_old[h1]);

        send_request(h0, h1);
        check_response(h0, h1, expected);
        repeat (response_stall) begin
            tick();
            check_response(h0, h1, expected);
        end
        accept_response();
        repeat (commit_stall) begin
            tick();
            check_flags(4'b1000, "commit stall");
        end
        check_bank_word(word_h0, "before commit");
        if (word_h0 != word_h1)
            check_bank_word(word_h1, "before commit");

        @(negedge clk);
        commit = 1'b1;
        tick();
        commit = 1'b0;
        model_active[h0] = 1'b1;
        if (word_h0 != word_h1) begin
            check_flags(4'b1000, "second write pending");
            check_bank_word(word_h0, "first write complete");
            check_bank_word(word_h1, "second write pending");
            tick();
            check_bank_word(word_h0, "both writes complete");
        end
        model_active[h1] = 1'b1;
        check_flags(4'b0100, "commit complete");
        check_bank_word(word_h1, "commit complete");
        checked_transactions++;
    endtask

    task automatic start_rotation(input bit queue_request);
        check_flags(4'b0100, "before rotation");
        @(negedge clk);
        if (queue_request) begin
            req_valid = 1'b1;
            req_h0 = '0;
            req_h1 = hash_t'(BIT_COUNT - 1);
        end
        rotate_req = 1'b1;
        #1ns;
        check_flags(4'b0000, "rotation takes priority over request");
        tick();
        rotate_req = 1'b0;
        check_flags(4'b1000, "rotation started");
    endtask

    task automatic rotate(input bit queue_request = 1'b0);
        start_rotation(queue_request);
        repeat (BANK_WORDS - 1) begin
            tick();
            check_flags(4'b1000, "clearing old bank");
        end
        tick();
        check_flags(4'b0101, "rotation complete");
        model_old = model_active;
        model_active = '0;
        for (int word_index = 0; word_index < BANK_WORDS; word_index++)
            check_bank_word(word_index, "after rotation");
        checked_rotations++;

        if (queue_request)
            transact('0, hash_t'(BIT_COUNT - 1));
        else begin
            tick();
            check_flags(4'b0100, "rotate_done pulse ended");
        end
    endtask

    task automatic test_generations();
        transact(12'd0, 12'd4095, 2, 3);
        transact(12'd0, 12'd4095);
        transact(12'd33, 12'd60);     // Distinct hashes in one RAM word.
        transact(12'd33, 12'd33);     // Identical hashes.
        transact(12'd0, 12'd33);      // A new pair may be seen due to collisions.
        rotate(1'b1);                // A queued request must see the completed rotation.
        transact(12'd1024, 12'd1055);
        transact(12'd33, 12'd1024, 1, 1); // One hash in each generation.
        rotate();
        transact(12'd60, 12'd60);     // An unrefreshed old bit has aged out.
        transact(12'd1055, 12'd1055); // The previous active bit is still seen.
    endtask

    task automatic test_reset_in_flight();
        send_request(12'd7, 12'd700);
        check_response(12'd7, 12'd700, 1'b0);
        reset_dut();
        transact(12'd7, 12'd700);

        send_request(12'd88, 12'd188);
        accept_response();
        tick();
        check_flags(4'b1000, "commit stalled before reset");
        reset_dut();
        transact(12'd88, 12'd188);

        send_request(12'd89, 12'd189);
        accept_response();
        @(negedge clk);
        commit = 1'b1;
        tick();
        commit = 1'b0;
        check_flags(4'b1000, "reset between the two writes");
        reset_dut();
        transact(12'd89, 12'd89);
        transact(12'd189, 12'd189);

        start_rotation(1'b0);
        repeat (12) tick();
        check_flags(4'b1000, "reset during rotation");
        reset_dut();
        transact(12'd89, 12'd189);
    endtask

    task automatic test_address_space();
        for (int address = 0; address < BIT_COUNT; address += 2)
            transact(hash_t'(address), hash_t'(address + 1));
        rotate();
        rotate();
        for (int address = 0; address < BIT_COUNT; address++)
            transact(hash_t'(address), hash_t'(address));
        reset_dut();
    endtask

    task automatic test_random_operations();
        hash_t h0, h1;
        repeat (RANDOM_TRANSACTIONS) begin
            h0 = hash_t'($urandom_range(BIT_COUNT - 1, 0));
            h1 = hash_t'($urandom_range(BIT_COUNT - 1, 0));
            if ($urandom_range(31, 0) == 0)
                rotate();
            transact(h0, h1, int'($urandom_range(2, 0)), int'($urandom_range(2, 0)));
        end
    endtask

    initial begin
        reset_dut();
        test_generations();
        test_reset_in_flight();
        test_address_space();
        test_random_operations();
        test_passed = 1'b1;
        $display("All Bloom Filter tests passed (%0d committed transactions, %0d rotations).",
                 checked_transactions, checked_rotations);
        $finish;
    end

    initial begin
        #4ms;
        $fatal(1, "Bloom Filter test timed out");
    end
endmodule
