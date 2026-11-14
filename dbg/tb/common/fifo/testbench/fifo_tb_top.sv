`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module fifo_tb_top;

    localparam int WIDTH      = 8;
    localparam int DEPTH      = 16;
    localparam int CLK_PERIOD = 20;
    localparam int RESET_TIME = 40;

    typedef logic [WIDTH-1:0] data_t;

    logic clk;
    logic rst_n;
    logic w_en;
    logic r_en;
    data_t w_data;
    data_t r_data;
    logic full;
    logic empty;

    data_t fifo_q[$];
    int error_count = 0;

    fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .w_en  (w_en),
        .w_data(w_data),
        .r_en  (r_en),
        .r_data(r_data),
        .full  (full),
        .empty (empty)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    function bit is_fifo_empty();
        return fifo_q.size() == 0;
    endfunction

    function bit is_fifo_full();
        return fifo_q.size() == DEPTH;
    endfunction

    task initialize();
        rst_n = 0;
        w_en = 0;
        r_en = 0;
        w_data = '0;
        fifo_q.delete();

        #(RESET_TIME);
        rst_n = 1;
        @(posedge clk);
    endtask

    task timeout();
        #1000000;
        $fatal(1, "Time: %0t, Timeout occurred.", $time);
    endtask

    task write(input data_t data);
        automatic bit expected_full = is_fifo_full();

        @(negedge clk);
        w_data = data;
        w_en = 1;
        $display("Time: %0t, Writing data: %b to FIFO", $time, data);

        @(posedge clk);
        if (full !== expected_full) begin
            $error(`RED_STR("Time: %0t, ERROR: Full flag mismatch. Expected: %b, Got: %b"),
                    $time, expected_full, full);
            error_count++;
        end

        if (!expected_full)
            fifo_q.push_back(data);

        @(negedge clk);
        w_en = 0;
    endtask

    task read();
        automatic bit expected_empty = is_fifo_empty();
        automatic data_t expected_data;

        if (!expected_empty)
            expected_data = fifo_q[0];

        @(negedge clk);
        r_en = 1;

        @(posedge clk);
        if (empty !== expected_empty) begin
            $error(`RED_STR("Time: %0t, ERROR: Empty flag mismatch. Expected: %b, Got: %b"),
                    $time, expected_empty, empty);
            error_count++;
        end

        if (!expected_empty) begin
            if (r_data !== expected_data) begin
                $error(`RED_STR("Time: %0t, ERROR: Read data %b does not match expected data %b"),
                        $time, r_data, expected_data);
                error_count++;
            end
            else begin
                $display("Time: %0t, Read data %b matches expected data",
                        $time, r_data);
            end
            void'(fifo_q.pop_front());
        end

        @(negedge clk);
        r_en = 0;
    endtask

    task rw_test();
        repeat (10) begin
            write($urandom);
            read();
        end
    endtask

    task test_overflow_underflow();
        repeat (DEPTH + 2)
            write($urandom);

        repeat (DEPTH + 2)
            read();
    endtask

    task rand_op_test();
        repeat (200) begin
            if ($urandom_range(1))
                write($urandom);
            else
                read();
        end
    endtask

    task test_top();
        initialize();
        rw_test();
        test_overflow_underflow();
        rand_op_test();
    endtask

    initial begin: run_test
        $timeformat(-9, 0, " ns", 5);
        fork
            begin
                test_top();
                if (error_count != 0)
                    $fatal(1, "Test completed with %0d errors.", error_count);
                $display(`GREEN_STR("All tests passed successfully."));
                $finish;
            end
            timeout();
        join_any
    end: run_test

endmodule
