`ifndef CLOCK_UVC_AGENT
`define CLOCK_UVC_AGENT
class clock_uvc_agent extends uvm_agent;
    `uvm_component_utils(clock_uvc_agent)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    typedef uvm_sequencer clock_uvc_sequencer;

    clock_uvc_driver     driver;
    clock_uvc_sequencer  sequencer;

    clock_uvc_config     cfg;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        driver    = clock_uvc_driver::type_id::create("driver", this);
        sequencer = clock_uvc_sequencer::type_id::create("sequencer", this);
    endfunction: build_phase

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.vif = cfg.vif;
        driver.cfg = cfg;
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass
`endif