`ifndef FIFO_TRANSACTION
`define FIFO_TRANSACTION
class fifo_transaction;
    rand data_t data;
    rand op_t   op;
    
    bit         empty;
    bit         full;


    function void display(string name = "");
        $display("[%s] op=%s, data=%b | full=%b, empty=%b", 
                 name, op.name(), data, full, empty);
    endfunction
endclass
`endif