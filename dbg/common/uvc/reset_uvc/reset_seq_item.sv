`ifndef RESET_SEQ_ITEM
`define RESET_SEQ_ITEM
class reset_seq_item extends uvm_sequence_item;
    `uvm_object_utils(reset_seq_item)

    realtime delay;
    realtime duration;

    function new(string name = "reset_seq_item");
        super.new(name);
    endfunction: new
endclass
`endif