// fifo_generator.sv
class fifo_generator extends svm_component;
    mailbox_t gen2drv;
    int num_transactions = 200; 
    event done;                 

    function new(string name, svm_component parent);
        super.new(name, parent);
    endfunction

    // ВАЖНО: Добавляем virtual
    virtual task run_phase();
        repeat(num_transactions) begin
            fifo_transaction tx = new("tr", this);
            assert (tx.randomize());
            gen2drv.put(tx);
        end
        -> done; 
    endtask

    static svm_pkg::svm_proxy#(fifo_generator) p = new("fifo_generator");
endclass