`ifndef FIFO_TRANSACTION
`define FIFO_TRANSACTION
class fifo_transaction extends svm_component;
    rand data_t data;
    rand op_t   op;
    
    bit         empty;
    bit         full;

    function new (string name, svm_component parent);
        super.new(name, parent);
    endfunction


    function void display();
        $display("[%s] op=%s, data=%b | full=%b, empty=%b", 
                 name, op.name(), data, full, empty);
    endfunction
endclass
`endif