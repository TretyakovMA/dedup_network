`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module dedup_tx_top_tb;

    enum {
        AXIS_DATA_WIDTH = 32, 
        APB_DATA_WIDTH  = 8,
        FIFO_DEPTH      = 16,
        CLK_PERIOD      = 20,
        RESET_TIME      = 40
    } param_e;
    enum {
        AXIS_OUT_DATA_WIDTH = 8
    } axis_param_e;

    enum {
        APB_ADDR_WIDTH  = 8
    } param_apb_e;

    // Тактовый сигнал и сброс
    logic clk;
    logic rst_n;

    // Интерфейсы AXI-Stream и APB
    axis_if #(AXIS_DATA_WIDTH)                in_axis_bus(clk, rst_n);
    axis_if #(AXIS_OUT_DATA_WIDTH)            out_axis_bus(clk, rst_n);
    apb_if  #(APB_DATA_WIDTH, APB_ADDR_WIDTH) apb_bus(clk, rst_n);

    virtual axis_if#(AXIS_DATA_WIDTH)               axis_vif = in_axis_bus;
    virtual axis_if#(AXIS_OUT_DATA_WIDTH)           axis_mon_vif = out_axis_bus;
    virtual apb_if#(APB_DATA_WIDTH, APB_ADDR_WIDTH) apb_vif = apb_bus.tb_driver;

    // Экземпляр тестируемого модуля
    dedup_tx_top #(
        .DATA_WIDTH(AXIS_DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .s_axis(in_axis_bus),
        .s_apb (apb_bus),
        .m_axis(out_axis_bus)
    );

    // Генерация тактового сигнала
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    task initialize();
        rst_n           = 0;

        axis_vif.tvalid = 0;
        axis_vif.tdata  = 0;
        axis_vif.tlast  = 0;
        apb_vif.psel    = 0;
        apb_vif.penable = 0;

        #(RESET_TIME);
        rst_n = 1;
        @(posedge axis_vif.clk); 
    endtask

    task single_write_apb();
        apb_vif.psel    = 1;
        apb_vif.penable = 1;
        apb_vif.pwrite  = 1;
        apb_vif.paddr   = 8'h01;
        apb_vif.pwdata  = 8'b10100101;
        @(apb_vif.driver_cb);
        apb_vif.psel    = 0;
        apb_vif.penable = 0;
        apb_vif.pwrite  = 0;
        apb_vif.pwdata  = '0;
        @(apb_vif.driver_cb);
    endtask

    task single_read_apb();
        apb_vif.psel    = 1;
        apb_vif.penable = 1;
        apb_vif.pwrite  = 0;
        apb_vif.paddr   = 8'h01;
        @(apb_vif.driver_cb);
        apb_vif.psel    = 0;
        apb_vif.penable = 0;
        apb_vif.pwrite  = 0;
        @(apb_vif.driver_cb);
    endtask

    task single_write_axis();
        @(posedge axis_vif.clk); 
        axis_vif.tvalid <= 1;
        axis_vif.tdata  <= 32'h12345678;
        axis_vif.tlast  <= 1;
        axis_mon_vif.tready       <= 1;
        @(posedge axis_vif.clk); 
        axis_vif.tvalid <= 0;
        axis_vif.tdata  <= 0;
        axis_vif.tlast  <= 0;
    endtask

    

    task timeout();
        #10000;
        $fatal(`RED_STR("Simulation timeout reached. Test failed."));
    endtask

    task test_top();
        initialize();
        single_write_apb();
        single_read_apb();
        single_write_axis();
        #1000;
        $finish;
    endtask


    initial begin
        $timeformat(-9, 0, " ns", 5);
        fork
            test_top();
            timeout();
        join
    end
endmodule