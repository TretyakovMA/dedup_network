`ifndef FIFO_DRIVER
`define FIFO_DRIVER
class fifo_driver extends svm_component;

    vif_t     vif;
    mailbox_t gen2drv;
    

    function new(string name, svm_component parent);
        super.new(name, parent);
    endfunction: new


    virtual function void build_phase();
        if (!svm_pkg::svm_config_db#(vif_t)::get("vif", this.vif)) begin
            $fatal(1, "[DRV] ERROR: Virtual interface not found in svm_config_db!");
        end
    endfunction: build_phase

    
    
    

    task run_phase();
        forever begin
            fifo_transaction tx;
            gen2drv.get(tx); // Ждем транзакцию от генератора

            if(tx.op == WRITE) begin
                $display("Time: %0t, Driver received WRITE transaction: data=%b", $time, tx.data);
                vif.cb.w_data <= tx.data;
                vif.cb.w_en   <= 1;
            end 
            else begin
                $display("Time: %0t, Driver received READ transaction", $time);
                vif.cb.r_en   <= 1;
            end
            
            
            @(vif.cb); 
            
            // Снимаем стробы, чтобы не дублировать операцию на следующем такте
            vif.cb.w_en   <= 0;
            vif.cb.r_en   <= 0;
        end
    endtask

    static svm_pkg::svm_proxy#(fifo_driver) p = new("fifo_driver");
endclass
`endif