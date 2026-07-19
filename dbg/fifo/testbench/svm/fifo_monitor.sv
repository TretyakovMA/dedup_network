`ifndef FIFO_MONITOR
`define FIFO_MONITOR
class fifo_monitor #(parameter int WIDTH = 8);
    virtual fifo_if#(WIDTH) vif;
    mailbox #(fifo_transaction#(WIDTH)) mon2scb;

    function new(virtual fifo_if#(WIDTH) vif, mailbox #(fifo_transaction#(WIDTH)) mon2scb);
        this.vif = vif;
        this.mon2scb = mon2scb;
    endfunction

    task run();
        forever begin
            @(vif.mon_cb);
            
            if (vif.mon_cb.w_en || vif.mon_cb.r_en) begin
                fifo_transaction#(WIDTH) tx = new();
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
endclass
`endif