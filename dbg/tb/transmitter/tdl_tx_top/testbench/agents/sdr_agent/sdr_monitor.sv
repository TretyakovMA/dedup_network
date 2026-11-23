`ifndef SDR_MONITOR
`define SDR_MONITOR
class sdr_monitor extends uvm_monitor;
    `uvm_component_utils(sdr_monitor)

    function new(string name = "sdr_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual sdr_interface.monitor vif;
    sdr_transaction               transaction;
    uvm_analysis_port #(sdr_transaction) ap;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (!uvm_config_db #(virtual sdr_interface.monitor)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "Failed to get interface")
    endfunction

    task collect_byte(output logic [7:0] data);
        for (int bit_index = 7; bit_index >= 0; bit_index--) begin
            @(posedge vif.sdr_clk);
            data[bit_index] = vif.sdr_data;
        end
    endtask

    task collect_word(output logic [31:0] data);
        for (int byte_index = 3; byte_index >= 0; byte_index--) begin
            collect_byte(data[8 * byte_index +: 8]);
        end
    endtask

    task monitor_transaction();
        logic [7:0] header;

        collect_byte(header);
        transaction = sdr_transaction::type_id::create("transaction");

        case (header)
            8'hA1: begin
                transaction.frame_type = FRAME_RAW;
                collect_word(transaction.data);
            end 
            8'hB2: begin
                transaction.frame_type = FRAME_KEY;
                collect_byte(transaction.key);
            end 
            8'hC3: begin
                transaction.frame_type = FRAME_SYNC;
                collect_byte(transaction.key);
                collect_word(transaction.data);
            end
            default: begin
                `uvm_fatal(get_name(), $sformatf("Invalid SDR header: %0h", header))
            end
        endcase

        `uvm_info(get_name(), {"SDR Transaction: ", transaction.convert2string()}, UVM_MEDIUM)
        ap.write(transaction);
    endtask

    task wait_reset_deasserted();
        if(vif.rst_n !== 1'b1)
            @(posedge vif.clk iff vif.rst_n == 1);
    endtask

    task handle_reset();
        @(posedge vif.rst_n);
    endtask

    task run_phase(uvm_phase phase);
        super.run_phase(phase);

        forever begin
            wait_reset_deasserted();
            fork
                monitor_transaction();
                handle_reset();
            join_any
            disable fork;
        end
    endtask
endclass
`endif
