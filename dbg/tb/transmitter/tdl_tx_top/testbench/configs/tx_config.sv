`ifndef TX_CONFIG
`define TX_CONFIG
class tx_config extends uvm_object;
    `uvm_object_utils(tx_config)

    agent_config       axis_agent_cfg;
    agent_config       sdr_agent_cfg;
    spi_config         spi_agent_cfg;

    clock_uvc_config   clk_cfg;
    reset_uvc_config   rst_cfg;

    function new(string name = "tx_config");
        super.new(name);

        axis_agent_cfg = agent_config::type_id::create("axis_agent_cfg");
        sdr_agent_cfg  = agent_config::type_id::create("sdr_agent_cfg");
        spi_agent_cfg  = spi_config::type_id::create("spi_agent_cfg");
    endfunction
endclass
`endif