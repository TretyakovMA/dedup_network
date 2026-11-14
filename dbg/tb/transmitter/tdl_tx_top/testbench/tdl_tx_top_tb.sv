`ifndef TDL_TX_TOP_TB
`define TDL_TX_TOP_TB
`timescale 1ns/1ns
module tdl_tx_top_tb;
    localparam int DATA_WIDTH  = 32;
    localparam int FIFO_DEPTH  = 16;
    localparam int CLK_PERIOD  = 10;
    localparam int RESET_TIME  = 40;


    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tx_pkg::*;

    logic clk;
    logic rst_n;
    
    sdr_interface sdr_if(clk, rst_n);

    spi_if                   spi_vif(clk, rst_n);
    axis_if#(DATA_WIDTH)     s_axis(clk, rst_n);

    tdl_tx_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),

        .s_axis_tdata (s_axis.tdata),
        .s_axis_tvalid(s_axis.tvalid),
        .s_axis_tready(s_axis.tready),
        .s_axis_tlast (s_axis.tlast),

        .sdr_data (sdr_if.sdr_data),
        .sdr_clk  (sdr_if.sdr_clk),
        .sdr_ready(sdr_if.sdr_ready),

        .spi_sclk(spi_vif.sclk),
        .spi_cs_n(spi_vif.cs_n),
        .spi_mosi(spi_vif.mosi),
        .spi_miso(spi_vif.miso)
    );

    initial begin
        clk = 0;
        forever begin
            #(CLK_PERIOD/2) clk = ~clk;
        end
    end

    initial begin
        rst_n = 0;
        #(RESET_TIME);
        rst_n = 1;
    end

    initial begin
        $timeformat(-9, 0, " ns", 5);

        uvm_config_db #(virtual interface spi_if.master)::set(null, "uvm_test_top.env.spi_agent_h.driver", "vif", spi_vif);
        uvm_config_db #(virtual interface spi_if.slave)::set(null, "uvm_test_top.env.spi_agent_h.monitor", "vif", spi_vif);

        run_test();
    end

endmodule
`endif