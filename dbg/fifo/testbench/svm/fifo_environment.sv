`ifndef FIFO_ENVIRONMENT
`define FIFO_ENVIRONMENT

class fifo_environment extends svm_component;
    // Компоненты тестбенча
    fifo_generator          gen;
    fifo_driver             drv;
    fifo_monitor            mon;
    fifo_scoreboard         scb;

    // Почтовые ящики для связи
    mailbox_t gen2drv;
    mailbox_t mon2scb;

    

    function new(string name, svm_component parent);
        super.new(name, parent);
        
    endfunction


    function void build_phase();
        gen2drv  = new(1);
        mon2scb  = new(1);

        $cast(gen, svm_pkg::svm_factory::create_component("fifo_generator", "gen", this));
        $cast(drv, svm_pkg::svm_factory::create_component("fifo_driver", "drv", this));
        $cast(mon, svm_pkg::svm_factory::create_component("fifo_monitor", "mon", this));
        $cast(scb, svm_pkg::svm_factory::create_component("fifo_scoreboard", "scb", this));
        
    endfunction


    function void connect_phase();
        // Связываем компоненты через почтовые ящики
        gen.gen2drv = gen2drv;
        drv.gen2drv = gen2drv;
        mon.mon2scb = mon2scb;
        scb.mon2scb = mon2scb;
    endfunction

    // Основной таск запуска теста
    task run_phase();
        raise_objection();
        fork
            // ПОТОК 1: Интеллектуальное ожидание окончания всех воздействий
            wait_for_end();

            // ПОТОК 2: Контроль таймаута (Watchdog)
            timeout();
        join_any
        
        disable fork;

        // Вызов финального отчета
        report_results();
        drop_objection();
    endtask


    task timeout();
        #10000;
        $fatal("\033[31;1m[TIMEOUT] Time: %t Test exceeded maximum execution time limit!\033[0m", $time);
    endtask

    // Вспомогательный таск для красивого и надежного ожидания окончания теста
    task wait_for_end();
        // 1. Ждем, пока генератор создаст заданное число транзакций
        @(gen.done);
        
        // 2. Ждем, пока драйвер заберет последнюю транзакцию из mailbox
        wait(gen2drv.num() == 0);
        
        // 3. Даем драйверу завершить обработку на интерфейсе и монитору её захватить
        #100;
        
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