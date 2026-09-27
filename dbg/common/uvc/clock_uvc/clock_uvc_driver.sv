`ifndef CLOCK_UVC_DRIVER
`define CLOCK_UVC_DRIVER
class clock_uvc_driver extends uvm_driver;
    `uvm_component_utils(clock_uvc_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    virtual interface clock_uvc_if vif;
    realtime           period;
    clock_uvc_config     cfg;


    local task run_phase(uvm_phase phase);
        vif.clk <= 0;

        seq_item_port.get_next_item(req);
        seq_item_port.item_done(req);
        period = cfg.get_period();

        forever begin
            #(period/2);
            vif.clk <= ~vif.clk;
        end
    endtask: run_phase
endclass
`endif