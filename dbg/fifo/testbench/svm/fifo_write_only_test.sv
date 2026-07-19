// Кастомный тест
class fifo_write_only_test extends fifo_base_test;
    function new(string name, svm_pkg::svm_component parent);
        // 1. Первым делом конструируем базовый класс.
        // Он вызовет свой new(), который создаст объект env!
        super.new(name, parent); 
        
        // 2. Теперь env существует, и env.gen2drv абсолютно валиден.
        // Создаем наш кастомный генератор и подменяем его в окружении.
        begin
            fifo_write_only_generator custom_gen = new("custom_gen", this, env.gen2drv);
            env.gen = custom_gen;
        end
    endfunction

    static svm_pkg::svm_proxy#(fifo_write_only_test) p = new("fifo_write_only_test");
endclass