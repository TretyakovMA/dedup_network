`ifndef FIFO_MONITOR
`define FIFO_MONITOR
class fifo_monitor extends svm_component;
    vif_t     vif;
    mailbox_t mon2scb;

    function new(string name, svm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase();
        if (!svm_config_db#(vif_t)::get("vif", this.vif)) begin
            $fatal(1, "[MON] ERROR: Virtual interface not found in svm_config_db!");
        end
    endfunction

    task run_phase();
        forever begin
            @(vif.mon_cb);
            
            if (vif.mon_cb.w_en || vif.mon_cb.r_en) begin
                fifo_transaction tx = new("tr");
                if(vif.mon_cb.w_en) begin
                    tx.op   = WRITE;
                    tx.data = vif.w_data; 
                end 
                else begin
                    tx.op = READ;
                end

                
                if(vif.mon_cb.r_en) begin
                    tx.data = vif.mon_cb.r_data;
                end
                
                tx.full   = vif.mon_cb.full;
                tx.empty  = vif.mon_cb.empty;
                mon2scb.put(tx);
            end
        end
    endtask

    static svm_pkg::svm_proxy#(fifo_monitor) p = new("fifo_monitor");
endclass
`endif