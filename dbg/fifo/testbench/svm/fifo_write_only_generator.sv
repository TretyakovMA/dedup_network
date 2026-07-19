class fifo_write_only_generator extends fifo_generator;

    function new(mailbox_t gen2drv);
        super.new(gen2drv);
    endfunction

    // Переопределяем логику генерации
    virtual task run();
        repeat(num_transactions) begin
            fifo_transaction tx = new();
            // Кастомизируем рандомизацию: только запись
            assert (tx.randomize() with { op == WRITE; }); 
            gen2drv.put(tx);
        end
        -> done;
    endtask
endclass