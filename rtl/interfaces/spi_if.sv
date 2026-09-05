`ifndef SPI_IF
`define SPI_IF
interface spi_if (
    input logic clk,
    input logic rst_n
);
    logic        sclk;
    logic        cs_n;
    logic        mosi;
    logic        miso;

    modport slave(
        input  clk,
        input  rst_n,
        input  sclk,
        input  cs_n,
        input  mosi,
        output miso
    );
endinterface
`endif