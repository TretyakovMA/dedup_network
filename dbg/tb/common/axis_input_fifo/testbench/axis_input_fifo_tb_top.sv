module axis_input_fifo_test #(
    parameter int DEPTH = 16
) (
    output bit done
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam time CLK_PERIOD = 20ns;
    typedef logic [31:0] data_t;

    logic clk = 0, rst_n = 1;
    logic tvalid = 0, tready, r_en = 0, empty, full;
    data_t tdata = '0, r_data;

    data_t expected_words[$];
    data_t next_data = 32'h1357_9bdf;
    bit stalled;
    data_t stalled_data;

    int accepted_words = 0, popped_words = 0, reset_words = 0;
    int empty_push_pop = 0, full_push_pop = 0, interior_push_pop = 0;
    int stall_cycles = 0, longest_stall = 0, current_stall = 0, resumed_writes = 0;

    axis_input_fifo #(
        .WIDTH($bits(data_t)),
        .DEPTH(DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .tdata (tdata),
        .tvalid(tvalid),
        .tready(tready),
        .r_en  (r_en),
        .r_data(r_data),
        .empty (empty),
        .full  (full)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    task automatic check_outputs(input string phase);
        bit expected_empty, expected_full;
        expected_empty = expected_words.size() == 0;
        expected_full  = expected_words.size() == DEPTH;

        if ({empty, full, tready} !== {expected_empty, expected_full, !expected_full})
            $fatal(1, "DEPTH=%0d %s at %t: count=%0d empty/full/tready=%b%b%b expected=%b%b%b",
                   DEPTH, phase, $time, expected_words.size(), empty, full, tready,
                   expected_empty, expected_full, !expected_full);

        if (!expected_empty && r_data !== expected_words[0])
            $fatal(1, "DEPTH=%0d %s at %t: FWFT head=%h expected=%h",
                   DEPTH, phase, $time, r_data, expected_words[0]);
    endtask

    task automatic reset_fifo();
        @(negedge clk);
        rst_n  = 0;
        tvalid = 0;
        tdata  = '0;
        r_en   = 0;

        reset_words += expected_words.size();
        expected_words.delete();
        stalled = 0;
        current_stall = 0;
        #1ns;
        check_outputs("asynchronous reset");
        repeat (2) @(posedge clk);
        #1ns;
        check_outputs("reset held");
        @(negedge clk);
        rst_n = 1;
    endtask

    task automatic step(input bit offer_word, input bit request_pop);
        bit push, pop;

        @(negedge clk);
        if (!stalled) begin
            tvalid = offer_word;
            if (offer_word) begin
                tdata = next_data;
                next_data += 32'h9e37_79b9;
            end
        end
        r_en = request_pop;

        @(posedge clk);
        check_outputs("before edge");
        if (stalled && (tvalid !== 1'b1 || tdata !== stalled_data))
            $fatal(1, "DEPTH=%0d at %t: source changed tvalid/tdata during stall", DEPTH, $time);

        push = tvalid && tready;
        pop  = r_en && !empty;
        if (tvalid && r_en) begin
            if (empty)
                empty_push_pop++;
            else if (full)
                full_push_pop++;
            else
                interior_push_pop++;
        end

        if (pop) begin
            void'(expected_words.pop_front());
            popped_words++;
        end
        if (push) begin
            expected_words.push_back(tdata);
            accepted_words++;
            if (stalled)
                resumed_writes++;
        end

        stalled = tvalid && !tready;
        if (stalled) begin
            stalled_data = tdata;
            stall_cycles++;
            current_stall++;
            if (current_stall > longest_stall)
                longest_stall = current_stall;
        end else begin
            current_stall = 0;
        end

        #1ns;
        check_outputs("after edge");
    endtask

    task automatic drain();
        while (expected_words.size() != 0 || stalled)
            step(0, 1);
        step(0, 1);
    endtask

    initial begin
        reset_fifo();
        step(0, 1);
        step(1, 1); // Empty accepts the write and exposes its head after the edge.
        step(0, 1);

        repeat (DEPTH) step(1, 0);
        repeat (5) step(1, 0);
        step(1, 1); // Full accepts only the pop. Keep the same input pending.
        step(0, 1); // The pending word is now accepted with another pop.
        repeat (3 * DEPTH) step(1, 1); // Wrap both pointers with concurrent push/pop.
        drain();

        repeat (DEPTH) step(1, 0);
        step(1, 0);
        reset_fifo(); // Discard a full FIFO and the source's unaccepted word.
        step(0, 1);
        step(1, 0);
        step(0, 1);

        repeat (1000)
            step($urandom_range(3, 0) != 0, $urandom_range(1, 0) != 0);
        drain();

        if (empty_push_pop == 0 || full_push_pop == 0 || interior_push_pop == 0 ||
            longest_stall < 5 || resumed_writes == 0 || reset_words != DEPTH)
            $fatal(1, "DEPTH=%0d: missing boundary, backpressure or reset coverage", DEPTH);
        if (accepted_words != popped_words + reset_words)
            $fatal(1, "DEPTH=%0d: accepted=%0d popped=%0d discarded on reset=%0d",
                   DEPTH, accepted_words, popped_words, reset_words);

        $display("PASS DEPTH=%0d: accepted=%0d popped=%0d reset=%0d stalled cycles=%0d longest=%0d",
                 DEPTH, accepted_words, popped_words, reset_words, stall_cycles, longest_stall);
        $display("  Concurrent requests at empty/full/partial=%0d/%0d/%0d, resumed writes=%0d",
                 empty_push_pop, full_push_pop, interior_push_pop, resumed_writes);
        done = 1;
    end
endmodule

module axis_input_fifo_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    wire [3:0] done;
    bit test_passed = 0;

    axis_input_fifo_test #(.DEPTH(8))  test_8  (.done(done[0]));
    axis_input_fifo_test #(.DEPTH(16)) test_16 (.done(done[1]));
    axis_input_fifo_test #(.DEPTH(32)) test_32 (.done(done[2]));
    axis_input_fifo_test #(.DEPTH(64)) test_64 (.done(done[3]));

    initial begin
        wait (&done);
        test_passed = 1;
        $display("PASS axis_input_fifo (DEPTH=8, 16, 32, 64)");
        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "axis_input_fifo timeout, completed tests mask=%b", done);
    end
endmodule
