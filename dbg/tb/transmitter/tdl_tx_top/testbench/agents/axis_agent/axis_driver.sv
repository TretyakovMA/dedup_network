`ifndef AXIS_DRIVER
`define AXIS_DRIVER
class axis_driver extends uvm_driver #(axis_transaction);
    `uvm_component_utils(axis_driver)

    function new(string name = "axis_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual axis_interface.driver  vif;
    axis_transaction               transaction; 



    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(!uvm_config_db#(virtual axis_interface.driver)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "Failed to get interface")
    endfunction

    task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        vif.tdata  = 'h0;
        vif.tvalid = 0;
        vif.tlast  = 0;
    endtask


    

    task wait_reset_deasserted();
        if(vif.rst_n !== 1'b1)
            @(posedge vif.clk iff vif.rst_n == 1);
    endtask

    task handle_reset();
        @(posedge vif.rst_n);

        vif.tdata  <= 'h0;
        vif.tvalid <= 0;
        vif.tlast  <= 0;

        if(transaction != null) begin
            seq_item_port.item_done();
        end
    endtask



    task drive_transaction();
        seq_item_port.get_next_item(transaction);

        vif.tdata  <= transaction.data;
        vif.tvalid <= 1;
        vif.tlast  <= 1;
        @(posedge vif.clk iff vif.tready);
        
        vif.tvalid <= 0;
        vif.tlast  <= 0;
        vif.tdata  <= 'h0;
        @(posedge vif.clk);

        seq_item_port.item_done();
    endtask

    task run_phase(uvm_phase phase);
        super.run_phase(phase);

        forever begin
            wait_reset_deasserted();

            fork
                drive_transaction();
                handle_reset();
            join_any
            disable fork;
        end
    endtask
endclass
`endif