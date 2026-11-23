`ifndef AXIS_TRANSACTION
`define AXIS_TRANSACTION
class axis_transaction extends uvm_sequence_item;
    `uvm_object_utils(axis_transaction)

    function new(string name = "axis_transaction");
        super.new(name);
    endfunction

    rand bit[31:0] data;

    function void do_copy(uvm_object rhs);
        axis_transaction copied;
        if(!$cast(copied, rhs))
            `uvm_fatal(get_name(), "Failed to cast rhs to axis_transaction")
        super.do_copy(rhs);

        this.data = copied.data;
    endfunction

    function axis_transaction clone_me();
        axis_transaction clone;
        uvm_object       tmp;
        
        tmp = this.clone();
        $cast(clone, tmp);
        return clone;
    endfunction

    function string convert2string();
        return $sformatf("axis_data = %b", data);
    endfunction: convert2string
endclass
`endif