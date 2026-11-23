`ifndef SDR_AGENT
`define SDR_AGENT
class sdr_agent extends uvm_agent;
    `uvm_component_utils(sdr_agent)

    function new(string name = "sdr_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    typedef uvm_sequencer #(sdr_ready_item) sdr_sequencer;

    sdr_sequencer sequencer;
    sdr_monitor   monitor;
    sdr_driver    driver;

    agent_config  cfg;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db #(agent_config)::get(this, "", "cfg", cfg) || cfg == null)
            `uvm_fatal(get_name(), "Failed to get agent configuration")

        is_active = cfg.is_active;
        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = sdr_sequencer::type_id::create("sequencer", this);
            driver    = sdr_driver::type_id::create("driver", this);
        end
        monitor = sdr_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE)
            driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass
`endif
