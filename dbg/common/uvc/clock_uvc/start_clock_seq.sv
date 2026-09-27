`ifndef START_CLOCK_SEQ
`define START_CLOCK_SEQ
class start_clock_seq extends uvm_sequence;
    `uvm_object_utils(start_clock_seq)

    function new(string name = "start_clock_seq");
        super.new(name);
    endfunction: new

    local task body();
        req = uvm_sequence_item::type_id::create("req");

        start_item(req);
        finish_item(req);
    endtask: body
endclass
`endif