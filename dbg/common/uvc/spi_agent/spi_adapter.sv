`ifndef SPI_ADAPTER
`define SPI_ADAPTER
class spi_adapter extends uvm_reg_adapter;
    `uvm_object_utils(spi_adapter)

    function new(string name = "spi_adapter");
        super.new(name);
        supports_byte_enable = 0;
        provides_responses   = 1;
    endfunction: new



    function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        spi_transaction tr;
        tr = spi_transaction::type_id::create("tr");

        tr.addr = rw.addr;
        tr.op   = (rw.kind == UVM_WRITE) ? spi_transaction::WRITE : spi_transaction::READ;

        tr.data = rw.data;
        `uvm_info (get_type_name(), {"reg2bus:\n", tr.convert2string()}, UVM_FULL)
        return tr;
    endfunction: reg2bus

    function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
        spi_transaction tr;

        if (!$cast(tr, bus_item)) begin
            `uvm_fatal(get_type_name(), "Invalid transaction type")
        end

        rw.kind = (tr.op == spi_transaction::WRITE) ? UVM_WRITE : UVM_READ;
        rw.addr = tr.addr;

        rw.data = tr.data;
        `uvm_info (get_type_name(), {"Get transaction:\n", tr.convert2string()}, UVM_FULL)
        `uvm_info (get_type_name(), $sformatf("bus2reg: addr=0x%0h data=0x%0h kind=%s status=%s", rw.addr, rw.data, rw.kind.name(), rw.status.name()), UVM_FULL)
        rw.status = UVM_IS_OK;
    endfunction: bus2reg
endclass
`endif