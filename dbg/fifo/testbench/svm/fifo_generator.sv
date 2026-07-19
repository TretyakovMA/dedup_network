// fifo_generator.sv
class fifo_generator extends svm_component;
    mailbox_t gen2drv;
    int num_transactions = 200; 
    event done;                 

    function new(string name, svm_component parent, mailbox_t gen2drv);
        super.new(name, parent);
        this.gen2drv = gen2drv;
    endfunction

    // ВАЖНО: Добавляем virtual
    virtual task run();
        repeat(num_transactions) begin
            fifo_transaction tx = new("tr", this);
            assert (tx.randomize());
            gen2drv.put(tx);
        end
        -> done; 
    endtask
endclass