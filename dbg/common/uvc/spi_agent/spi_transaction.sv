`ifndef SPI_TRANSACTION
`define SPI_TRANSACTION

class spi_transaction extends uvm_sequence_item;
    `uvm_object_utils(spi_transaction)

    function new(string name = "spi_transaction");
        super.new(name);
    endfunction: new

    typedef enum bit {
        WRITE = 0,
        READ  = 1
    } spi_command_t;

    rand bit[7:0]      data; 
    rand bit[6:0]      addr;
    rand spi_command_t op;


    function string convert2string();
        return $sformatf("op = %s, addr = %h, data = %b", op.name(), addr, data);
    endfunction: convert2string



    function void do_copy(uvm_object rhs);
        spi_transaction copied;
        if(!$cast(copied, rhs))
            `uvm_fatal(get_type_name(), "Cast failed")
        super.do_copy(rhs);

        this.data         = copied.data;
        this.addr         = copied.addr;
        this.op           = copied.op;
    endfunction: do_copy

    function spi_transaction clone_me();
        spi_transaction clone;
        uvm_object      tmp;
        
        tmp = this.clone();
        $cast(clone, tmp);
        return clone;
    endfunction: clone_me

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        spi_transaction compared_tr;
        bit same = 1;
        if (rhs == null)
            `uvm_fatal(get_type_name(), "Tried to do comparsion to a null pointer")

        if(!$cast(compared_tr, rhs))
            same = 0;
        
        same &= super.do_compare(rhs, comparer);
        same &= comparer.compare_field_int("data", this.data, compared_tr.data, $bits(data));
        same &= comparer.compare_field_int("addr", this.addr, compared_tr.addr, $bits(addr));
        same &= comparer.compare_field_int("op", this.op, compared_tr.op, $bits(op));
        
        

        
        return same;
    endfunction: do_compare

endclass
`endif
