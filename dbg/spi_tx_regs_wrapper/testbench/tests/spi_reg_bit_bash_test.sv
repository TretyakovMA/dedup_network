`ifndef SPI_REG_BIT_BASH_TEST
`define SPI_REG_BIT_BASH_TEST
class spi_reg_bit_bash_test extends spi_base_test;
    `uvm_component_utils(spi_reg_bit_bash_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    uvm_reg_bit_bash_seq seq;

    task main_phase(uvm_phase phase);
        super.main_phase(phase);
        phase.raise_objection(this);
        seq = uvm_reg_bit_bash_seq::type_id::create("seq");
        seq.model = env.reg_block;
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass
`endif