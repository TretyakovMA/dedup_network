`ifndef SPI_INTERFACE
`define SPI_INTERFACE
interface spi_interface (
    input logic clk,
    input logic rst_n
);
    logic        sclk;
    logic        cs_n;
    logic        mosi;
    logic        miso;

    modport driver(
        input  clk,
        input  rst_n,
        
        output sclk,
        output cs_n,
        output mosi,
        input  miso
    );

    modport monitor(
        input  clk,
        input  rst_n,

        input  sclk,
        input  miso, // Данные, отправленные dut
        input  mosi  // Данные, отправленные driver
    );

endinterface
`endif