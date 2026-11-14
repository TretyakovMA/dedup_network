`ifndef TX_PKG
`define TX_PKG
package tx_pkg;
    import uvm_pkg::*;
    import tx_reg_model::*;
    `include "uvm_macros.svh"

    import clock_uvc_pkg::*;
    import reset_uvc_pkg::*;
    import spi_agent_pkg::*;

    `include "custom_report_server.sv"

    //`include "configs/spi_config.sv"
    //`include "configs/agent_config.sv"

    //`include "items/spi_transaction.sv"
    //`include "agents/spi_agent/spi_driver.sv"
    //`include "agents/spi_agent/spi_monitor.sv"
    //`include "agents/spi_agent/spi_agent.sv"

    `include "scoreboard/tx_scoreboard.sv"

    //`include "reg_models/spi_adapter.sv"

    `include "env/tx_env.sv"

    `include "sequences/spi_sequences/spi_simple_seq.sv"

    `include "tests/tx_base_test.sv"
    `include "tests/spi_tests/spi_simple_test.sv"
    `include "tests/spi_tests/spi_regs_hw_reset_test.sv"
endpackage
`endif