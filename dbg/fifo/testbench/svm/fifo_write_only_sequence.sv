class fifo_write_only_sequence extends svm_sequence #(fifo_transaction);
    int num_transactions = 200;

    function new(string name = "");
        super.new(name);
    endfunction

    virtual task body();
        repeat(num_transactions) begin
            fifo_transaction tx = new("tr");
            assert(tx.randomize() with { op == WRITE; });
            
            // Кладём транзакцию в параметризованный mailbox секвенсера
            p_sequencer.seq_item_mailbox.put(tx);
        end
    endtask
endclass