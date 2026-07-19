`ifndef FIFO_GENERATOR
`define FIFO_GENERATOR

class fifo_generator;
    mailbox_t gen2drv;
    int num_transactions = 200; // Количество транзакций в тесте
    event done;                 // Событие окончания генерации

    function new(mailbox_t gen2drv);
        this.gen2drv = gen2drv;
    endfunction

    task run();
        repeat(num_transactions) begin
            fifo_transaction tx = new();
            assert (tx.randomize());
            gen2drv.put(tx);
        end
        -> done; // Оповещаем окружение, что генерация завершена
    endtask
endclass
`endif