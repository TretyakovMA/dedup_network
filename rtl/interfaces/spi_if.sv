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

    modport master(
        input  clk,
        input  rst_n,
        output sclk,
        output cs_n,
        output mosi,
        input  miso
    );

    modport rx_monitor(
        input  clk,
        input  rst_n,

        input  sclk,
        input  miso // Фиксирует данные, отправленные dut
    );

    modport tx_monitor(
        input  clk,
        input  rst_n,

        input  sclk,
        input  mosi // Фиксирует данные, отправленные driver
    );
endinterface
`endif