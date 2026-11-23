`ifndef SDR_DRIVER
`define SDR_DRIVER
class sdr_driver extends uvm_driver #(sdr_ready_item);
    `uvm_component_utils(sdr_driver)

    function new(string name = "sdr_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual sdr_interface.driver vif;
    sdr_ready_item               transaction;

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (!uvm_config_db #(virtual sdr_interface.driver)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "Failed to get interface")
    endfunction


    task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        vif.sdr_ready <= 1'b1;
    endtask

    task drive_transaction();
        seq_item_port.get_next_item(transaction);

        if (transaction.num_cycles <= 0) begin
            `uvm_fatal(get_name(), "num_cycles must be positive")
        end

        @(negedge vif.clk);
        vif.sdr_ready <= transaction.ready;

        repeat (transaction.num_cycles) @(posedge vif.clk);

        vif.sdr_ready <= 1'b1;
        seq_item_port.item_done();
    endtask

    task wait_reset_deasserted();
        if(vif.rst_n !== 1'b1)
            @(posedge vif.clk iff vif.rst_n == 1);
    endtask

    task handle_reset();
        @(posedge vif.rst_n);

        vif.sdr_ready <= 1'b1;

        if(transaction != null) begin
            seq_item_port.item_done();
        end
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
