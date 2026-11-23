`timescale 1ns/1ns

module tdl_dict_storage_test #(
    parameter int DATA_WIDTH = 32,
    parameter int DICT_SIZE = 256,
    localparam int KEY_WIDTH = $clog2(DICT_SIZE)
) (
    output logic done
);
    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic flush = 1'b0;
    logic wr_en = 1'b0;
    logic [KEY_WIDTH-1:0] wr_index = '0;
    logic [DATA_WIDTH-1:0] wr_data = '0;
    logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict_words;
    logic [DICT_SIZE-1:0] valid_bits;
    logic [KEY_WIDTH:0] occupied_count;
    logic dict_full;
    logic [KEY_WIDTH-1:0] next_free_index;

    logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] expected_words = '0;
    logic [DICT_SIZE-1:0] expected_valid = '0;

    tdl_dict_storage #(
        .DATA_WIDTH (DATA_WIDTH),
        .DICT_SIZE  (DICT_SIZE)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (flush),
        .wr_en           (wr_en),
        .wr_index        (wr_index),
        .wr_data         (wr_data),
        .dict_words      (dict_words),
        .valid_bits      (valid_bits),
        .occupied_count  (occupied_count),
        .dict_full       (dict_full),
        .next_free_index (next_free_index)
    );

    always #10 clk = ~clk;

    task automatic check_state(input string phase);
        int count;
        int first_free;

        count = 0;
        first_free = -1;
        for (int i = 0; i < DICT_SIZE; i++) begin
            if (expected_valid[i])
                count++;
            else if (first_free == -1)
                first_free = i;
            if (dict_words[i] !== expected_words[i])
                $fatal(1, "DICT_SIZE=%0d %s: word[%0d]=%h, expected %h",
                       DICT_SIZE, phase, i, dict_words[i], expected_words[i]);
        end
        if (first_free == -1)
            first_free = 0;

        if (valid_bits !== expected_valid)
            $fatal(1, "DICT_SIZE=%0d %s: valid=%h, expected %h",
                   DICT_SIZE, phase, valid_bits, expected_valid);
        if (occupied_count !== (KEY_WIDTH+1)'(count))
            $fatal(1, "DICT_SIZE=%0d %s: count=%0d, expected %0d",
                   DICT_SIZE, phase, occupied_count, count);
        if (dict_full !== (count == DICT_SIZE))
            $fatal(1, "DICT_SIZE=%0d %s: full=%b, expected %b",
                   DICT_SIZE, phase, dict_full, count == DICT_SIZE);
        if (next_free_index !== KEY_WIDTH'(first_free))
            $fatal(1, "DICT_SIZE=%0d %s: next free=%0d, expected %0d",
                   DICT_SIZE, phase, next_free_index, first_free);
    endtask

    task automatic drive_cycle(
        input logic do_flush,
        input logic do_write,
        input int index,
        input logic [DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        flush = do_flush;
        wr_en = do_write;
        wr_index = KEY_WIDTH'(index);
        wr_data = data;
        #1;
        check_state("before clock");

        @(posedge clk);
        if (do_flush)
            expected_valid = '0;
        else if (do_write && index < DICT_SIZE) begin
            expected_words[index] = data;
            expected_valid[index] = 1'b1;
        end
        #1;
        check_state("after clock");
    endtask

    task automatic reset_storage;
        @(negedge clk);
        wr_en = 1'b1;
        flush = 1'b1;
        #1;
        rst_n = 1'b0;
        expected_words = '0;
        expected_valid = '0;
        #1;
        check_state("asynchronous reset");
        @(posedge clk);
        #1;
        check_state("reset at clock");
        @(negedge clk);
        flush = 1'b0;
        wr_en = 1'b0;
        rst_n = 1'b1;
        #1;
        check_state("reset released");
    endtask

    initial begin
        done = 1'b0;
        reset_storage();

        // Fill in reverse order to exercise the lowest-free-index selection.
        for (int i = DICT_SIZE - 1; i >= 0; i--)
            drive_cycle(1'b0, 1'b1, i, DATA_WIDTH'(i + 1));

        // Reject every representable out-of-range index without changing any row.
        for (int i = DICT_SIZE; i < (1 << KEY_WIDTH); i++)
            drive_cycle(1'b0, 1'b1, i, DATA_WIDTH'('hff));

        drive_cycle(1'b0, 1'b1, 0, DATA_WIDTH'('h5a));
        drive_cycle(1'b0, 1'b1, DICT_SIZE - 1, DATA_WIDTH'('ha5));
        drive_cycle(1'b0, 1'b0, 0, DATA_WIDTH'('hff));

        // Flush takes priority over a write and retains the old payload.
        drive_cycle(1'b1, 1'b1, 0, DATA_WIDTH'('hde));
        drive_cycle(1'b1, 1'b1, DICT_SIZE - 1, DATA_WIDTH'('had));
        drive_cycle(1'b0, 1'b0, 0, '0);
        drive_cycle(1'b0, 1'b1, DICT_SIZE - 1, DATA_WIDTH'('h12));
        drive_cycle(1'b0, 1'b1, 0, DATA_WIDTH'('h34));

        // Reset also overrides an active write and flush.
        reset_storage();

        for (int i = 0; i < 128; i++) begin
            logic random_flush;
            logic random_write;
            int random_index;
            logic [DATA_WIDTH-1:0] random_data;

            random_flush = ($urandom_range(0, 15) == 0);
            random_write = ($urandom_range(0, 3) != 0);
            random_index = $urandom_range(DICT_SIZE - 1, 0);
            random_data = DATA_WIDTH'($urandom);
            drive_cycle(random_flush, random_write, random_index, random_data);
        end

        done = 1'b1;
    end
endmodule

module tdl_dict_storage_tb_top;
    wire [3:0] done;
    bit test_passed = 1'b0;

    tdl_dict_storage_test #(.DATA_WIDTH(8),  .DICT_SIZE(2))   test_2   (.done(done[0]));
    tdl_dict_storage_test #(.DATA_WIDTH(16), .DICT_SIZE(3))   test_3   (.done(done[1]));
    tdl_dict_storage_test #(.DATA_WIDTH(32), .DICT_SIZE(5))   test_5   (.done(done[2]));
    tdl_dict_storage_test #(.DATA_WIDTH(32), .DICT_SIZE(256)) test_256 (.done(done[3]));

    initial begin
        wait (&done);
        test_passed = 1'b1;
        $display("All dictionary storage tests passed (DICT_SIZE=2, 3, 5, 256).");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Dictionary storage test timed out.");
    end
endmodule
