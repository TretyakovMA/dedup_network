`ifndef SPI_AGENT_PKG
`define SPI_AGENT_PKG
package spi_agent_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "spi_config.sv"
    `include "spi_transaction.sv"
    `include "spi_driver.sv"
    `include "spi_monitor.sv"
    `include "spi_adapter.sv"
    `include "spi_agent.sv"
endpackage
`endif