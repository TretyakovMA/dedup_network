
`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module axis_input_fifo_tb_top;

    enum {
        WIDTH      = 8, 
        DEPTH      = 16,
        CLK_PERIOD = 20,
        RESET_TIME = 40
    } param_e;

    

    logic clk;
    logic rst_n;

    logic [WIDTH-1:0] tdata;
    logic             tvalid;
    logic             tready;
    logic             r_en;
    logic [WIDTH-1:0] r_data;
    logic             empty;
    logic             full;


    typedef logic[WIDTH-1:0] data_t;

    int error_count = 0;




    data_t fifo_q[$];

    function bit is_fifo_empty();
        return fifo_q.size() == 0;
    endfunction

    function bit is_fifo_full();
        return fifo_q.size() == DEPTH;
    endfunction

    function void push_fifo(data_t data);
        if(is_fifo_full()) begin
            $display("Time: %0t, FIFO is full. Cannot push data: %b", $time, data);
            return;
        end
        fifo_q.push_back(data);
    endfunction

    function data_t pop_fifo();
        if(is_fifo_empty()) begin
            $display("Time: %0t, FIFO is empty. Cannot pop data.", $time);
            return '0;
        end
        return fifo_q.pop_front();
    endfunction


    axis_input_fifo #(
        .WIDTH(WIDTH),
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

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end



    task initialize();
        rst_n  = 0;
        tvalid = 0;
        tdata  = '0;
        r_en   = 0;

        #(RESET_TIME);
        rst_n = 1;
        @(posedge clk);
    endtask



    task timeout();
        #10000;
    endtask



    task write(input data_t data);
        automatic bit expected_full = is_fifo_full();

        @(negedge clk);
        tdata  = data;
        tvalid = 1;
        $display("Time: %0t, Writing data: %b to FIFO", $time, data);

        @(posedge clk);
        if(full !== expected_full) begin
            $error(`RED_STR("Time: %0t, ERROR: Full flag mismatch. Expected: %b, Got: %b"), 
                    $time, expected_full, full);
            error_count++;
        end

        push_fifo(data);
        @(negedge clk);
        tvalid = 0;
    endtask

    task read();
        automatic bit expected_empty = is_fifo_empty();
        automatic data_t expected_data;

        if (!expected_empty) begin
            expected_data = fifo_q[0];
        end

        @(negedge clk);
        r_en = 1;

        @(posedge clk);
        if(empty !== expected_empty) begin
            $error(`RED_STR("Time: %0t, ERROR: Empty flag mismatch. Expected: %b, Got: %b"), 
                    $time, expected_empty, empty);
            error_count++;
        end

        if(!expected_empty) begin
            if(r_data !== expected_data) begin
                $error(`RED_STR("Time: %0t, ERROR: Read data %b does not match expected data %b"), 
                        $time, r_data, expected_data);
                error_count++;
            end 
            else begin
                $display("Time: %0t, Read data %b matches expected data %b", 
                        $time, r_data, expected_data);
            end
            void'(pop_fifo());
        end

        @(negedge clk);
        r_en = 0;
    endtask


    task rw_test();
        // Тестирование записи и чтения данных
        repeat (10) begin
            write($urandom);
            read();
        end
    endtask

    task test_overflow_underflow();
        // Тестирование переполнения FIFO
        repeat (DEPTH + 2) begin
            write($urandom);
        end

        // Тестирование опустошения FIFO
        repeat (DEPTH) begin
            read();
        end
    endtask

    task rand_op_test();
        // Случайные операции записи и чтения
        repeat (200) begin
            if ($urandom_range(1)) begin
                write($urandom);
            end 
            else begin
                read();
            end
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
            test_top();
            timeout();
        join_any

        $finish;
    end: run_test

    final begin
        if (error_count == 0) begin
            $display(`GREEN_STR("All tests passed successfully."));
        end 
        else begin
            $display(`RED_STR("Test completed with %0d errors."), error_count);
        end
    end
endmodule