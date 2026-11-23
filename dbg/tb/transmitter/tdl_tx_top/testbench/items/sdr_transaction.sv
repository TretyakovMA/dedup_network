`ifndef SDR_TRANSACTION
`define SDR_TRANSACTION
class sdr_transaction extends uvm_sequence_item;
    `uvm_object_utils(sdr_transaction)

    function new(string name = "sdr_transaction");
        super.new(name);
    endfunction

    frame_t       frame_type;
    logic [7:0]   key;
    logic [31:0]  data;

    function void do_copy(uvm_object rhs);
        sdr_transaction copied;
        if(!$cast(copied, rhs))
            `uvm_fatal(get_name(), "Failed to cast rhs to sdr_transaction")
        super.do_copy(rhs);

        this.frame_type = copied.frame_type;
        this.key        = copied.key;
        this.data       = copied.data;
    endfunction

    function sdr_transaction clone_me();
        sdr_transaction clone;
        uvm_object      tmp;
        
        tmp = this.clone();
        $cast(clone, tmp);
        return clone;
    endfunction

    function string convert2string();
        case (frame_type)
            FRAME_RAW:  return $sformatf("frame_type = RAW, data = %08h", data);
            FRAME_KEY:  return $sformatf("frame_type = KEY, key = %02h", key);
            FRAME_SYNC: return $sformatf("frame_type = SYNC, key = %02h, data = %08h", key, data);
            default:    return $sformatf("frame_type = %b", frame_type);
        endcase
    endfunction: convert2string

endclass
`endif
