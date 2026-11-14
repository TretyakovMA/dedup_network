`ifndef TX_SCOREBOARD
`define TX_SCOREBOARD

class tx_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(tx_scoreboard)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    `uvm_analysis_imp_decl(_SPI)
    uvm_analysis_imp_SPI #(spi_transaction, tx_scoreboard) spi_ap;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        spi_ap = new("spi_ap", this);
    endfunction: build_phase

    function void write_SPI(spi_transaction tr);
        `uvm_info(get_name(), {"Get tr: ", tr.convert2string()}, UVM_LOW)
    endfunction
endclass

`endif