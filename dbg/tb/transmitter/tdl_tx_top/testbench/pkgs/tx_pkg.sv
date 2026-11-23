`ifndef TX_PKG
`define TX_PKG

`include "interfaces/axis_interface.sv"
`include "interfaces/sdr_interface.sv"

package tx_pkg;
    import uvm_pkg::*;
    import tx_reg_model::*;
    `include "uvm_macros.svh"

    import clock_uvc_pkg::*;
    import reset_uvc_pkg::*;
    import spi_agent_pkg::*;

    import tdl_tx_pkg::*;

    `include "custom_report_server.sv"
    `include "configs/agent_config.sv"
    `include "configs/tx_config.sv"

    // items
    `include "items/axis_transaction.sv"
    `include "items/sdr_transaction.sv"
    `include "items/sdr_ready_item.sv"
    
    // agents
    `include "agents/axis_agent/axis_driver.sv"
    `include "agents/axis_agent/axis_monitor.sv"
    `include "agents/axis_agent/axis_agent.sv"

    `include "agents/sdr_agent/sdr_driver.sv"
    `include "agents/sdr_agent/sdr_monitor.sv"
    `include "agents/sdr_agent/sdr_agent.sv"


    // scoreboards
    `include "scoreboard/tx_scoreboard.sv"

    // environments
    `include "env/tx_env.sv"

    `include "sequences/spi_sequences/spi_simple_seq.sv"

    `include "tests/tx_base_test.sv"
    `include "tests/spi_simple_test.sv"
endpackage
`endif