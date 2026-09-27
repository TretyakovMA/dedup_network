`ifndef SPI_READ_MONITOR
`define SPI_READ_MONITOR
class spi_read_monitor extends spi_base_monitor;
    `uvm_component_utils(spi_read_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    virtual function bit select_transaction(spi_transaction tr);
        return (tr.op == spi_transaction::READ);
    endfunction

    task collect_transaction_data(spi_transaction tr);
        collect_miso(tr.data);
    endtask
endclass
`endif