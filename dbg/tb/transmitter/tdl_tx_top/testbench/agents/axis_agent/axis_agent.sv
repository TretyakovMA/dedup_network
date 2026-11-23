`ifndef AXIS_AGENT
`define AXIS_AGENT
class axis_agent extends uvm_agent;
    `uvm_component_utils(axis_agent)

    function new(string name = "axis_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    typedef uvm_sequencer #(axis_transaction) axis_sequencer;

    axis_sequencer sequencer;
    axis_monitor   monitor;
    axis_driver    driver;

    agent_config   cfg;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if(!uvm_config_db#(agent_config)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_name(), "Failed to get agent configuration")
        
        if(cfg.is_active == UVM_ACTIVE) begin
            sequencer = axis_sequencer::type_id::create("sequencer", this);
            driver    = axis_driver::type_id::create("driver", this);
        end
        monitor = axis_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(cfg.is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass
`endif