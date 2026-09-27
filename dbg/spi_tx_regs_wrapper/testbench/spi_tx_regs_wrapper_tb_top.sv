`ifndef SPI_TX_REGS_WRAPPER_TB_TOP
`define SPI_TX_REGS_WRAPPER_TB_TOP
`timescale 1ns/1ns
module spi_tx_regs_wrapper_tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import spi_pkg::*;
    import clock_uvc_pkg::*;
    import reset_uvc_pkg::*;

    clock_uvc_if clk_if();
    reset_uvc_if rst_if();

    tx_regs_pkg::tx_regs__in_t  hwif_in = '{default: '0};
    tx_regs_pkg::tx_regs__out_t hwif_out;

    spi_if spi_vif(clk_if.clk, rst_if.rst);

    spi_tx_regs_wrapper dut(
        .clk(clk_if.clk),
        .rst_n(rst_if.rst),
        .hwif_in(hwif_in),
        .hwif_out(hwif_out),
        .s_spi(spi_vif)
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
        rst_config.active_level = 0; // Указываем, что у нас активный низкий уровень (rst_n)
        uvm_config_db#(reset_uvc_config)::set(null, "", "rst_config", rst_config);
    end

    initial begin
        $timeformat(-9, 0, " ns", 5);

        uvm_config_db #(virtual interface spi_if.master)::set(null, "uvm_test_top.env.spi_agent.driver", "vif", spi_vif);
        uvm_config_db #(virtual interface spi_if.slave)::set(null, "uvm_test_top.env.spi_agent.write_monitor", "vif", spi_vif);
        uvm_config_db #(virtual interface spi_if.slave)::set(null, "uvm_test_top.env.spi_agent.read_monitor", "vif", spi_vif);

        run_test();
    end

endmodule: spi_tx_regs_wrapper_tb_top
`endif