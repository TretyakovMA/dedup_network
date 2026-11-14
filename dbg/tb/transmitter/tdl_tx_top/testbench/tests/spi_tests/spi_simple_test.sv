class spi_simple_test extends tx_base_test;
    `uvm_component_utils(spi_simple_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    spi_simple_seq seq;

    task main_phase(uvm_phase phase);
        super.main_phase(phase);
        
        seq = spi_simple_seq::type_id::create("seq");

        phase.raise_objection(this);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass