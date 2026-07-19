
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

    fifo_if #(WIDTH) vif(clk, rst_n);

    import svm_pkg::*;

    import fifo_pkg::*;

    fifo_environment  env;

    
    


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



    





    initial begin: run_test
        string cli_test_name;
        $timeformat(-9, 0, " ns", 5);

        svm_config_db#(virtual fifo_if #(WIDTH))::set("vif", vif);

        //env = new(vif);
        initialize();

        svm_factory::run_test();
        #100;
    
        //env.run();
        //test_factory::run_test(vif);

        $finish;
    end: run_test

endmodule