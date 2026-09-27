`ifndef RESET_SEQ
`define RESET_SEQ
class reset_seq extends uvm_sequence #(reset_seq_item);
    `uvm_object_utils(reset_seq)

    realtime delay_time;
    realtime duration_time;

    function new(string name = "reset_seq");
        super.new(name);
        // Значения по умолчанию
        delay_time = 20ns;
        duration_time = 100ns;
    endfunction: new

    local task body();
        req = reset_seq_item::type_id::create("req");

        start_item(req);
        req.delay = delay_time;
        req.duration = duration_time;
        finish_item(req);
    endtask: body
endclass
`endif