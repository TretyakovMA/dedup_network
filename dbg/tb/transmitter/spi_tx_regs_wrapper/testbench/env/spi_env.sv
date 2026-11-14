`ifndef SPI_ENV
`define SPI_ENV
class spi_env extends uvm_env;
    `uvm_component_utils(spi_env)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    typedef uvm_reg_predictor #(spi_transaction) spi_predictor;

    spi_agent          agent;

    tx_regs            reg_block;
    spi_adapter        adapter;
    spi_predictor      predictor;

    clock_uvc_agent      clk_agent;
    clock_uvc_config     clk_cfg;

    reset_uvc_agent      rst_agent;
    reset_uvc_config     rst_cfg;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agent       = spi_agent::type_id::create("spi_agent", this);
        
        predictor   = spi_predictor::type_id::create("predictor", this);
        adapter     = spi_adapter::type_id::create("adapter", this);
        reg_block   = tx_regs::new("reg_block");
        reg_block.build();
        reg_block.lock_model();
        uvm_config_db #(tx_regs)::set(null, "*", "reg_block", reg_block);

        clk_agent     = clock_uvc_agent::type_id::create("clk_agent", this);
        clk_agent.cfg = clk_cfg;

        rst_agent     = reset_uvc_agent::type_id::create("rst_agent", this);
        rst_agent.cfg = rst_cfg;
    endfunction: build_phase

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        predictor.map     = reg_block.default_map;
        predictor.adapter = adapter;

        agent.write_monitor.ap.connect(predictor.bus_in);
        agent.read_monitor.ap.connect(predictor.bus_in);

        reg_block.default_map.set_sequencer(
            .sequencer(agent.sequencer),
            .adapter(adapter)
        );

    endfunction: connect_phase
endclass: spi_env
`endif