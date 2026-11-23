`ifndef TX_SCOREBOARD
`define TX_SCOREBOARD
class tx_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(tx_scoreboard)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    `uvm_analysis_imp_decl(_spi)
    `uvm_analysis_imp_decl(_sdr)
    `uvm_analysis_imp_decl(_axis)
    uvm_analysis_imp_spi #(spi_transaction, tx_scoreboard)   spi_ap;
    uvm_analysis_imp_sdr #(sdr_transaction, tx_scoreboard)   sdr_ap;
    uvm_analysis_imp_axis #(axis_transaction, tx_scoreboard) axis_ap;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        spi_ap  = new("spi_ap", this);
        sdr_ap  = new("sdr_ap", this);
        axis_ap = new("axis_ap", this);
    endfunction: build_phase

    function void write_spi(spi_transaction tr);
        `uvm_info(get_name(), {"Get tr: ", tr.convert2string()}, UVM_LOW)
    endfunction

    function void write_sdr(sdr_transaction tr);
        `uvm_info(get_name(), {"Get tr: ", tr.convert2string()}, UVM_LOW)
    endfunction

    function void write_axis(axis_transaction tr);
        `uvm_info(get_name(), {"Get tr: ", tr.convert2string()}, UVM_LOW)
    endfunction
endclass
`endif