`ifndef SPI_WRITE_MONITOR
`define SPI_WRITE_MONITOR
class spi_write_monitor extends spi_base_monitor;
    `uvm_component_utils(spi_write_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    virtual function bit select_transaction(spi_transaction tr);
        return (tr.op == spi_transaction::WRITE);
    endfunction

    task collect_transaction_data(spi_transaction tr);
        collect_mosi(tr.data);
    endtask
endclass
`endif