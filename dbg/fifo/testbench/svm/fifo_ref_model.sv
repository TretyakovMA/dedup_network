`ifndef FIFO_REF_MODEL
`define FIFO_REF_MODEL
class fifo_ref_model #(parameter int DEPTH = 16);
    local data_t fifo_q[$];

    function void clean();
        fifo_q.delete();
    endfunction: clean

    function bit is_empty();
        return (fifo_q.size() == 0);
    endfunction: is_empty

    function bit is_full();
        return (fifo_q.size() == DEPTH);
    endfunction: is_full

    function int current_size();
        return fifo_q.size();
    endfunction: current_size

    function void print_status();
        $display("\nFIFO status: size = %0d; content = %p\n", fifo_q.size(), fifo_q);
    endfunction: print_status



    function void push_data(data_t data);
        if(is_full()) begin
            $display("Time: %0t, FIFO is full. Cannot push data: %b", $time, data);
            return;
        end
        fifo_q.push_back(data);
    endfunction: push_data

    function data_t pop_data ();
        if(is_empty()) begin
            $display("Time: %0t, FIFO is empty. Cannot pop data.", $time);
            return '0;
        end
        return fifo_q.pop_front();
    endfunction: pop_data

    function data_t peek_data ();
        return fifo_q[0];
    endfunction: peek_data

endclass
`endif