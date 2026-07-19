`ifndef FIFO_ENVIRONMENT
`define FIFO_ENVIRONMENT

class fifo_environment;
    // Компоненты тестбенча
    fifo_generator          gen;
    fifo_driver             drv;
    fifo_monitor            mon;
    fifo_scoreboard         scb;

    // Почтовые ящики для связи
    mailbox_t gen2drv;
    mailbox_t mon2scb;

    vif_t vif;

    function new(vif_t vif);
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
        fork
            // ПОТОК 1: Запуск и выполнение всех компонентов тестбенча
            begin
                fork
                    gen.run();
                    drv.run();
                    mon.run();
                    scb.run();
                join
            end

            // ПОТОК 2: Интеллектуальное ожидание окончания всех воздействий
            begin
                wait_for_end();
            end

            // ПОТОК 3: Контроль таймаута (Watchdog)
            begin
                #10000;
                $fatal("\033[31;1m[TIMEOUT] Time: %t Test exceeded maximum execution time limit!\033[0m", $time);
            end
        join_any
        
        // Как только ПОТОК 2 (успешный финиш) или ПОТОК 3 (таймаут) завершатся,
        // снимаем все остальные параллельные процессы (включая forever-циклы компонентов)
        disable fork;

        // Вызов финального отчета
        report_results();
    endtask

    // Вспомогательный таск для красивого и надежного ожидания окончания теста
    task wait_for_end();
        // 1. Ждем, пока генератор создаст заданное число транзакций
        @(gen.done);
        
        // 2. Ждем, пока драйвер заберет последнюю транзакцию из mailbox
        wait(gen2drv.num() == 0);
        
        // 3. Даем драйверу завершить обработку на интерфейсе и монитору её захватить
        // Используем события тактового сигнала вместо жесткого #100
        repeat(2) @(vif.cb);
        
        // 4. Ждем, пока scoreboard разберет все пришедшие от монитора транзакции
        wait(mon2scb.num() == 0);
    endtask

    // Вынос логики отчета в отдельную функцию для чистоты кода
    function void report_results();
        if (scb.error_count == 0) begin
            $display("\033[32m[TEST PASSED] All operations verified successfully!\033[0m");
        end 
        else begin
            $display("\033[31;1m[TEST FAILED] Verification finished with %0d errors\033[0m", 
                     scb.error_count);
        end
    endfunction

endclass
`endif