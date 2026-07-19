`ifndef FIFO_GENERATOR
`define FIFO_GENERATOR

class fifo_generator #(parameter int WIDTH = 8);
    mailbox #(fifo_transaction#(WIDTH)) gen2drv;
    int num_transactions = 200; // Количество транзакций в тесте
    event done;                 // Событие окончания генерации

    function new(mailbox #(fifo_transaction#(WIDTH)) gen2drv);
        this.gen2drv = gen2drv;
    endfunction

    task run();
        repeat(num_transactions) begin
            fifo_transaction#(WIDTH) tx = new();
            assert (tx.randomize());
            gen2drv.put(tx);
        end
        -> done; // Оповещаем окружение, что генерация завершена
    endtask
endclass
`endif