`ifndef FIFO_DRIVER
`define FIFO_DRIVER
class fifo_driver;

    vif_t     vif;
    mailbox_t gen2drv;
    

    function new(vif_t vif, mailbox_t gen2drv);
        this.vif     = vif;
        this.gen2drv = gen2drv;
    endfunction: new

    
    
    

    task run();
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
endclass
`endif