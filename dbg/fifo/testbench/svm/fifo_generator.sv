// fifo_generator.sv
class fifo_generator;
    mailbox_t gen2drv;
    int num_transactions = 200; 
    event done;                 

    function new(mailbox_t gen2drv);
        this.gen2drv = gen2drv;
    endfunction

    // ВАЖНО: Добавляем virtual
    virtual task run();
        repeat(num_transactions) begin
            fifo_transaction tx = new();
            assert (tx.randomize());
            gen2drv.put(tx);
        end
        -> done; 
    endtask
endclass