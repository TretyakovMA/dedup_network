// Кастомный тест
class fifo_write_only_test extends fifo_base_test;
    function new(string name, svm_pkg::svm_component parent);
        super.new(name, parent); 
    endfunction

    virtual function void build_phase();
        svm_pkg::svm_factory::set_type_override("fifo_generator", "fifo_write_only_generator");
        super.build_phase();
    endfunction

    static svm_pkg::svm_proxy#(fifo_write_only_test) p = new("fifo_write_only_test");
endclass