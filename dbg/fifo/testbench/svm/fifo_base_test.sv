// Базовый тест
class fifo_base_test extends svm_test;
    `svm_component_utils(fifo_base_test)
    fifo_environment env;

    function new(string name, svm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase();
        env = new("env", this);
    endfunction

endclass