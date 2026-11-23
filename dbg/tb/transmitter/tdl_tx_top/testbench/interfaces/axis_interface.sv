`ifndef AXIS_INTERFACE
`define AXIS_INTERFACE
interface axis_interface #(
    parameter int DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);
    logic [DATA_WIDTH-1:0] tdata;
    logic                  tvalid;
    logic                  tready;
    logic                  tlast;
    logic [7:0]            tid;

    
    modport monitor (
        input tdata, tvalid, tlast, tready,
        input clk, rst_n
    );

    
    modport driver (
        output tdata, tvalid, tlast,
        input  tready,
        input clk, rst_n
    );

endinterface
`endif