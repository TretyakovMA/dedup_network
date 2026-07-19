// Базовый тест
class fifo_base_test extends svm_test;
    fifo_environment env;

    function new(string name, svm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase();
        env = new("env", this);
    endfunction


    // Регистрируем тест на фабрике SVM
    static svm_pkg::svm_proxy#(fifo_base_test) p = new("fifo_base_test");
endclass