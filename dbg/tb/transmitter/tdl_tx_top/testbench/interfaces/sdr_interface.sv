`ifndef SDR_INTERFACE
`define SDR_INTERFACE
interface sdr_interface (
    input logic clk,
    input logic rst_n
);
    logic sdr_clk;
    logic sdr_ready;
    logic sdr_data;

    modport driver (
        output sdr_ready,
        input  sdr_data, sdr_clk,
        input  clk, rst_n
    );

    modport monitor (
        input sdr_ready,
        input sdr_data, sdr_clk,
        input clk, rst_n
    );
endinterface
`endif