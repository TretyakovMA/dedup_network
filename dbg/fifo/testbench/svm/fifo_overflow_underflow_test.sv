class fifo_overflow_underflow_test extends fifo_base_test;
    `svm_component_utils(fifo_overflow_underflow_test)
    function new(string name, svm_component parent);
        super.new(name, parent); 
    endfunction

    virtual function void build_phase();
        super.build_phase();
    endfunction


    virtual task run_phase();
        
        fifo_overflow_underflow_seq seq = new("seq");
        
        raise_objection();
        seq.start(env.seqr);
        #100; 
        drop_objection();
    endtask
endclass