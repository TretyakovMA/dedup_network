`ifndef TX_ENV
`define TX_ENV
class tx_env extends uvm_env;
    `uvm_component_utils(tx_env)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    typedef uvm_reg_predictor #(spi_transaction) spi_predictor;

    spi_agent          spi_agent_h;
    agent_config       spi_agent_cfg;
    tx_scoreboard      scoreboard;

    tx_regs            reg_block;
    spi_adapter        adapter;
    spi_predictor      predictor;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        spi_agent_cfg = agent_config::type_id::create("spi_agent_cfg", this);

        uvm_config_db #(agent_config)::set(this, "spi_agent_h", "agent_config", spi_agent_cfg);
        spi_agent_h = spi_agent::type_id::create("spi_agent_h", this);

        scoreboard  = tx_scoreboard::type_id::create("scoreboard", this);
        
        predictor   = spi_predictor::type_id::create("predictor", this);
        adapter     = spi_adapter::type_id::create("adapter", this);
        reg_block   = tx_regs::new("reg_block");
        reg_block.build();
        reg_block.lock_model();
        uvm_config_db #(tx_regs)::set(null, "*", "reg_block", reg_block);
    endfunction: build_phase

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        predictor.map     = reg_block.default_map;
        predictor.adapter = adapter;

        spi_agent_h.monitor.ap.connect(predictor.bus_in);

        reg_block.default_map.set_sequencer(
            .sequencer(spi_agent_h.sequencer),
            .adapter(adapter)
        );
        
        spi_agent_h.monitor.ap.connect(scoreboard.spi_ap);

    endfunction: connect_phase
endclass
`endif