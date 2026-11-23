`ifndef SDR_READY_ITEM
`define SDR_READY_ITEM
class sdr_ready_item extends uvm_sequence_item;
    `uvm_object_utils(sdr_ready_item)

    function new(string name = "sdr_ready_item");
        super.new(name);
    endfunction

    bit ready;
    int num_cycles;

    function void do_copy(uvm_object rhs);
        sdr_ready_item copied;
        if(!$cast(copied, rhs))
            `uvm_fatal(get_name(), "Failed to cast rhs to sdr_ready_item")
        super.do_copy(rhs);

        this.ready      = copied.ready;
        this.num_cycles = copied.num_cycles;
    endfunction

    function sdr_ready_item clone_me();
        sdr_ready_item clone;
        uvm_object     tmp;
        
        tmp = this.clone();
        $cast(clone, tmp);
        return clone;
    endfunction

    function string convert2string();
        return $sformatf("ready = %0b, num_cycles = %0d", ready, num_cycles);
    endfunction: convert2string
endclass
`endif