
class fifo_write_only_test extends fifo_base_test;
    `svm_component_utils(fifo_write_only_test)
    function new(string name, svm_pkg::svm_component parent);
        super.new(name, parent); 
    endfunction

    virtual function void build_phase();
        svm_pkg::svm_factory::set_type_override("fifo_generator", "fifo_write_only_generator");
        super.build_phase();
    endfunction


    virtual task run_phase();
        
        fifo_write_only_sequence seq = new("seq");
        
        raise_objection();
        seq.start(env.seqr);
        #100; 
        drop_objection();
    endtask
endclass