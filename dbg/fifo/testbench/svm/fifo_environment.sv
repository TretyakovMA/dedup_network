`ifndef FIFO_ENVIRONMENT
`define FIFO_ENVIRONMENT
class fifo_environment #(parameter int WIDTH = 8, parameter int DEPTH = 16);
    // Компоненты тестбенча
    fifo_generator#(WIDTH)        gen;
    fifo_driver#(WIDTH)           drv;
    fifo_monitor#(WIDTH)          mon;
    fifo_scoreboard#(WIDTH,DEPTH) scb;

    // Почтовые ящики для связи
    mailbox #(fifo_transaction#(WIDTH)) gen2drv;
    mailbox #(fifo_transaction#(WIDTH)) mon2scb;

    virtual fifo_if#(WIDTH) vif;

    function new(virtual fifo_if#(WIDTH) vif);
        this.vif = vif;
        gen2drv  = new(1);
        mon2scb  = new(1);
        
        gen = new(gen2drv);
        drv = new(vif, gen2drv);
        mon = new(vif, mon2scb);
        scb = new(mon2scb);
    endfunction

    // Основной таск запуска теста
    task run();
        // Запускаем все процессы параллельно
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_none // Позволяет текущему потоку идти дальше

        // Ждем, пока генератор создаст заданное число транзакций
        @(gen.done);
        
        // Drain time: даем драйверу и монитору завершить обработку последних тактов
        #100;
        
        // Печатаем финальный отчет
        if (scb.error_count == 0) begin
            $display("\033[32m[TEST PASSED] All operations verified successfully!\033[0m");
        end 
        else begin
            $display("\033[31;1m[TEST FAILED] Verification finished with %0d errors.\033[0m", scb.error_count);
        end
    endtask
endclass
`endif