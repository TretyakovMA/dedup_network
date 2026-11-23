`ifndef AXIS_MONITOR
`define AXIS_MONITOR
class axis_monitor extends uvm_monitor;
    `uvm_component_utils(axis_monitor)

    function new(string name = "axis_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual axis_interface.monitor vif;
    axis_transaction               transaction; 
    uvm_analysis_port #(axis_transaction) ap;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(!uvm_config_db#(virtual axis_interface.monitor)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "Failed to get interface")
    endfunction



    task wait_reset_deasserted();
        if(vif.rst_n !== 1'b1)
            @(posedge vif.clk iff vif.rst_n == 1);
    endtask

    task handle_reset();
        @(posedge vif.rst_n);
    endtask

    task monitor_transaction();
        @(posedge vif.clk iff vif.tvalid && vif.tready);
        transaction = axis_transaction::type_id::create("transaction");

        transaction.data = vif.tdata;
        `uvm_info(get_name(), {"AXIS Transaction: ", transaction.convert2string()}, UVM_MEDIUM)
        ap.write(transaction);
    endtask

    task run_phase(uvm_phase phase);
        super.run_phase(phase);

        wait_reset_deasserted();
        forever begin
            fork
                monitor_transaction();
                handle_reset();
            join_any
            disable fork;
        end
    endtask
endclass
`endif