`ifndef SPI_PKG
`define SPI_PKG
package spi_pkg;
    import uvm_pkg::*;
    import tx_reg_model::*;
    `include "uvm_macros.svh"

    import clock_uvc_pkg::*;
    import reset_uvc_pkg::*;
    import spi_agent_pkg::*;

    `include "custom_report_server.sv"

    //`include "configs/spi_config.sv"

    /*`include "items/spi_transaction.sv"
    `include "agents/spi_driver.sv"
    `include "agents/spi_monitor.sv"
    `include "agents/spi_agent.sv"

    `include "reg_models/spi_adapter.sv"*/

    `include "env/spi_env.sv"

    `include "tests/spi_base_test.sv"
    `include "tests/spi_reg_hw_reset_test.sv"
    `include "tests/spi_reg_bit_bash_test.sv"
endpackage: spi_pkg

`endif