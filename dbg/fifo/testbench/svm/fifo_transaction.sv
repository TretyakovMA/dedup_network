`ifndef FIFO_TRANSACTION
`define FIFO_TRANSACTION
class fifo_transaction extends svm_object;
    rand data_t data;
    rand op_t   op;
    
    bit         empty;
    bit         full;

    function new (string name);
        super.new(name);
    endfunction


    function void display();
        $display("[%s] op=%s, data=%b | full=%b, empty=%b", 
                 name, op.name(), data, full, empty);
    endfunction
endclass
`endif