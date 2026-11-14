interface axis_if #(
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

    
    modport slave (
        input  tdata, tvalid, tlast,
        output tready,
        input clk, rst_n
    );

    
    modport master (
        output tdata, tvalid, tlast,
        input  tready,
        input clk, rst_n
    );

    // Приемник будет дополнительно использовать tid
    modport master_rx (
        output tdata, tvalid, tlast, tid,
        input  tready
    );

    
endinterface