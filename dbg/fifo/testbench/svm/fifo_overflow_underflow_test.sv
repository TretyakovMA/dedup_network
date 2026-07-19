class fifo_overflow_underflow_test extends fifo_base_test;
    function new(string name, svm_component parent);
        super.new(name, parent); 
    endfunction

    virtual function void build_phase();
        super.build_phase();
    endfunction

    static svm_pkg::svm_proxy#(fifo_overflow_underflow_test) p = new("fifo_overflow_underflow_test");

    virtual task run_phase();
        // 1. Создаем динамический сценарий
        fifo_overflow_underflow_seq seq = new("seq");
        
        // 2. Тест поднимает возражение: "Я начинаю работу, не закрывайте симуляцию!"
        raise_objection();
        
        // 3. Запускаем сценарий на секвенсере, который живет внутри env
        seq.start(env.seqr);
        
        // 4. Даем драйверу и DUT небольшую паузу, чтобы завершить обработку последней транзакции
        #100; 
        
        // 5. Тест закончил работу
        drop_objection();
    endtask
endclass