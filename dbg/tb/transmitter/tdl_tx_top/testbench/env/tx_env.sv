`ifndef TX_ENV
`define TX_ENV
class tx_env extends uvm_env;
    `uvm_component_utils(tx_env)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    typedef uvm_reg_predictor #(spi_transaction) spi_predictor;

    spi_agent          spi_agent_h;
    sdr_agent          sdr_agent_h;
    axis_agent         axis_agent_h;
    
    tx_scoreboard      scoreboard;

    tx_regs            reg_block;
    spi_adapter        adapter;
    spi_predictor      predictor;

    tx_config          cfg;

    clock_uvc_agent    clk_agent;
    reset_uvc_agent    rst_agent;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if(!uvm_config_db #(tx_config)::get(this, "", "tx_config", cfg))
            `uvm_fatal(get_name(), "Failed to get tx_config from uvm_config_db")

        uvm_config_db #(spi_config)::set(this, "spi_agent_h",  "spi_config", cfg.spi_agent_cfg);
        uvm_config_db #(agent_config)::set(this, "sdr_agent_h",  "cfg", cfg.sdr_agent_cfg);
        uvm_config_db #(agent_config)::set(this, "axis_agent_h", "cfg", cfg.axis_agent_cfg);
        spi_agent_h   = spi_agent::type_id::create("spi_agent_h", this);
        sdr_agent_h   = sdr_agent::type_id::create("sdr_agent_h", this);
        axis_agent_h  = axis_agent::type_id::create("axis_agent_h", this);

        clk_agent     = clock_uvc_agent::type_id::create("clk_agent", this);
        clk_agent.cfg = cfg.clk_cfg;

        rst_agent     = reset_uvc_agent::type_id::create("rst_agent", this);
        rst_agent.cfg = cfg.rst_cfg;

        scoreboard    = tx_scoreboard::type_id::create("scoreboard", this);
        
        predictor     = spi_predictor::type_id::create("predictor", this);
        adapter       = spi_adapter::type_id::create("adapter", this);
        reg_block     = tx_regs::new("reg_block");
        reg_block.build();
        reg_block.lock_model();
        uvm_config_db #(tx_regs)::set(null, "*", "reg_block", reg_block);
    endfunction: build_phase

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        predictor.map     = reg_block.default_map;
        predictor.adapter = adapter;

        spi_agent_h.write_monitor.ap.connect(predictor.bus_in);
        spi_agent_h.read_monitor.ap.connect(predictor.bus_in);

        reg_block.default_map.set_sequencer(
            .sequencer(spi_agent_h.sequencer),
            .adapter(adapter)
        );
        
        spi_agent_h.write_monitor.ap.connect(scoreboard.spi_ap);
        spi_agent_h.read_monitor.ap.connect(scoreboard.spi_ap);
        sdr_agent_h.monitor.ap.connect(scoreboard.sdr_ap);
        axis_agent_h.monitor.ap.connect(scoreboard.axis_ap);
    endfunction: connect_phase
endclass
`endif