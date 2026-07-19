// Базовый тест
class fifo_base_test extends svm_pkg::svm_test;
    fifo_environment env;

    function new(string name, svm_pkg::svm_component parent);
        super.new(name, parent);
        env = new("env", this); // Создаем окружение внутри теста
    endfunction

    virtual task run();
        env.run();
    endtask

    // Регистрируем тест на фабрике SVM
    static svm_pkg::svm_proxy#(fifo_base_test) p = new("fifo_base_test");
endclass