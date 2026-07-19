class fifo_overflow_underflow_seq extends svm_sequence #(fifo_transaction);

    function new(string name = "");
        super.new(name);
    endfunction

    virtual task body();
        repeat(`FIFO_DEPTH + 2) begin
            fifo_transaction tx = new("tr");
            assert(tx.randomize() with { op == WRITE; });
            
            // Кладём транзакцию в параметризованный mailbox секвенсера
            p_sequencer.seq_item_mailbox.put(tx);
        end

        repeat(`FIFO_DEPTH + 2) begin
            fifo_transaction tx = new("tr");
            assert(tx.randomize() with { op == READ; });
            
            // Кладём транзакцию в параметризованный mailbox секвенсера
            p_sequencer.seq_item_mailbox.put(tx);
        end
    endtask
endclass