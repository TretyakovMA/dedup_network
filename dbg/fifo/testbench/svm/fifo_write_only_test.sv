// Кастомный тест
class fifo_write_only_test extends fifo_base_test;
    function new(vif_t vif);
        super.new(vif);
        begin
            fifo_write_only_generator custom_gen = new(env.gen2drv);
            env.gen = custom_gen;
        end
    endfunction

    // МАГИЧЕСКАЯ СТРОКА: регистрируем этот класс под именем "fifo_write_only_test"
    static test_proxy#(fifo_write_only_test) p = new("fifo_write_only_test");
endclass