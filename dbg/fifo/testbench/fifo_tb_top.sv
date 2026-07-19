
`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module fifo_tb_top;

    enum {
        WIDTH      = 8, 
        DEPTH      = 16,
        CLK_PERIOD = 20,
        RESET_TIME = 40
    } param_e;

    

    logic clk;
    logic rst_n;

    fifo_if vif(clk, rst_n);

    import fifo_pkg::*;

    fifo_environment #(.WIDTH(WIDTH), .DEPTH(DEPTH)) env;

    
    


    /*fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(vif.clk),
        .rst_n(vif.rst_n),
        .w_data(vif.w_data),
        .w_en(vif.w_en),
        .full(vif.full),
        .r_data(vif.r_data),
        .r_en(vif.r_en),
        .empty(vif.empty)
    );*/

    fifo #(
        .DEPTH(DEPTH)
    ) dut (
        .io(vif.rtl)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end



    task initialize();
        rst_n      = 0;
        vif.w_en   = 0;
        vif.r_en   = 0;
        vif.w_data = '0;

        #(RESET_TIME);
        rst_n = 1;
        @(vif.cb); 
    endtask



    task timeout();
        #10000;
    endtask





    initial begin: run_test
        $timeformat(-9, 0, " ns", 5);
        env = new(vif);
        initialize();
        fork
            env.run();
            timeout();
        join_any

        $finish;
    end: run_test

endmodule