`ifndef SDR_INTERFACE
`define SDR_INTERFACE
interface sdr_interface (
    input logic clk,
    input logic rst_n
);
    logic sdr_clk;
    logic sdr_ready;
    logic sdr_data;
endinterface
`endif