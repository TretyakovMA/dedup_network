interface apb_if #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 8
)(
    input logic clk,
    input logic rst_n
);
    logic [DATA_WIDTH-1:0] pwdata;
    logic [ADDR_WIDTH-1:0] paddr;
    logic                  psel;
    logic                  pready;
    logic [DATA_WIDTH-1:0] prdata;
    logic                  penable;
    logic                  pwrite;
    logic                  pslverr;
    

    
    modport slave (
        input  pwdata, psel, penable, pwrite, paddr,
        output prdata, pready, pslverr,
        input  clk, rst_n
    );

    
    modport master (
        output pwdata, psel, penable, pwrite, paddr,
        input  prdata, pready, pslverr,
        input  clk, rst_n
    );

    clocking driver_cb @(posedge clk);
        default input #1step output #0; 
        output pwdata, paddr, psel, penable, pwrite;
        input  prdata, pready, pslverr;
    endclocking

    modport tb_driver(
        clocking driver_cb
    );

    
endinterface