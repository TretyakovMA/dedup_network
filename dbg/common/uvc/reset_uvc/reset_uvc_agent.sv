`ifndef RESET_UVC_AGENT
`define RESET_UVC_AGENT
class reset_uvc_agent extends uvm_agent;
    `uvm_component_utils(reset_uvc_agent)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    typedef uvm_sequencer #(reset_seq_item) reset_uvc_sequencer;

    reset_uvc_driver     driver;
    reset_uvc_sequencer  sequencer;
    reset_uvc_config     cfg;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        driver    = reset_uvc_driver::type_id::create("driver", this);
        sequencer = reset_uvc_sequencer::type_id::create("sequencer", this);
    endfunction: build_phase

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.vif = cfg.vif;
        driver.cfg = cfg;
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass
`endif