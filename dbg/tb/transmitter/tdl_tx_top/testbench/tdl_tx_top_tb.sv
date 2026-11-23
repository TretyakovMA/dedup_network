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

    import clock_uvc_pkg::*;
    import reset_uvc_pkg::*;
    import tx_pkg::*;
    
    clock_uvc_if                    clk_if();
    reset_uvc_if                    rst_if();

    sdr_interface                   sdr_if(clk_if.clk, rst_if.rst);
    spi_interface                   spi_if(clk_if.clk, rst_if.rst);
    axis_interface#(DATA_WIDTH)     axis_if(clk_if.clk, rst_if.rst);

    tdl_tx_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk   (clk_if.clk),
        .rst_n (rst_if.rst),

        .s_axis_tdata (axis_if.tdata),
        .s_axis_tvalid(axis_if.tvalid),
        .s_axis_tready(axis_if.tready),
        .s_axis_tlast (axis_if.tlast),

        .sdr_data (sdr_if.sdr_data),
        .sdr_clk  (sdr_if.sdr_clk),
        .sdr_ready(sdr_if.sdr_ready),

        .spi_sclk(spi_if.sclk),
        .spi_cs_n(spi_if.cs_n),
        .spi_mosi(spi_if.mosi),
        .spi_miso(spi_if.miso)
    );


    initial begin
        automatic clock_uvc_config clk_config = clock_uvc_config::type_id::create("clk_config");
        clk_config.set_period(10, CLOCK_UVC_TIME_NS);
		clk_config.vif = clk_if;
        uvm_config_db#(clock_uvc_config)::set(null, "", "clk_config", clk_config);
    end

    initial begin
        automatic reset_uvc_config rst_config = reset_uvc_config::type_id::create("rst_config");
        rst_config.vif = rst_if;
        rst_config.active_level = 0;
        uvm_config_db#(reset_uvc_config)::set(null, "", "rst_config", rst_config);
    end

    initial begin
        $timeformat(-9, 0, " ns", 5);

        uvm_config_db #(virtual interface spi_interface.driver)::set(null, "uvm_test_top.env.spi_agent_h.driver", "vif", spi_if);
        uvm_config_db #(virtual interface spi_interface.monitor)::set(null, "uvm_test_top.env.spi_agent_h.write_monitor", "vif", spi_if);
        uvm_config_db #(virtual interface spi_interface.monitor)::set(null, "uvm_test_top.env.spi_agent_h.read_monitor", "vif", spi_if);

        uvm_config_db #(virtual interface sdr_interface.monitor)::set(null, "uvm_test_top.env.sdr_agent_h.monitor", "vif", sdr_if);
        uvm_config_db #(virtual interface sdr_interface.driver)::set(null, "uvm_test_top.env.sdr_agent_h.driver", "vif", sdr_if);
        uvm_config_db #(virtual interface axis_interface.monitor)::set(null, "uvm_test_top.env.axis_agent_h.monitor", "vif", axis_if);
        uvm_config_db #(virtual interface axis_interface.driver)::set(null, "uvm_test_top.env.axis_agent_h.driver", "vif", axis_if);

        run_test();
    end

endmodule
`endif