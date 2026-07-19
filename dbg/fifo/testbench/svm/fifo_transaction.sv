`ifndef FIFO_TRANSACTION
`define FIFO_TRANSACTION
class fifo_transaction #(parameter int WIDTH = 8);
    rand bit [WIDTH-1:0] data;
    rand op_t            op;
    
    bit             empty;
    bit             full;


    function void display(string name = "");
        $display("[%s] op=%s, data=%b | full=%b, empty=%b", 
                 name, op.name(), data, full, empty);
    endfunction
endclass
`endif