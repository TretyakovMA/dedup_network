// Базовый тест
class fifo_base_test;
    fifo_environment env;
    vif_t vif;

    function new(vif_t vif);
        this.vif = vif;
        env = new(vif);
    endfunction

    virtual task run();
        env.run();
    endtask

    // МАГИЧЕСКАЯ СТРОКА: регистрируем этот класс под именем "fifo_base_test"
    static test_proxy#(fifo_base_test) p = new("fifo_base_test");
endclass