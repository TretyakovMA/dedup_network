`ifndef TDL_TX_TOP
`define TDL_TX_TOP
module tdl_tx_top # (
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_DEPTH = 16
) (
    input  logic          clk,
    input  logic          rst_n,

    // Входные данные от PHY
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,
    input  logic                  s_axis_tlast,

    // Однобитный SDR-интерфейс приемника
    output logic                  sdr_data,
    output logic                  sdr_clk,
    input  logic                  sdr_ready,

    // Физический интерфейс SPI Slave
    input  logic        spi_sclk,
    input  logic        spi_cs_n,
    input  logic        spi_mosi,
    output logic        spi_miso,
    output logic        spi_irq
);

    // Интерфейс для передачи данных в регистровый модуль
    tx_regs_pkg::tx_regs__in_t  hwif_in;
    tx_regs_pkg::tx_regs__out_t hwif_out;

    // Интерфейс входного FIFO
    logic fifo_empty;
    logic fifo_full;
    logic [DATA_WIDTH-1:0] fifo_r_data;
    logic fifo_r_en;

    logic dict_hit;
    logic [7:0] dict_key;
    logic force_sync;


    // Входное fifo
    axis_input_fifo #(
        .WIDTH(DATA_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_axis_input_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .tdata  (s_axis_tdata),
        .tvalid (s_axis_tvalid),
        .tready (s_axis_tready),
        .r_en   (fifo_r_en),
        .r_data (fifo_r_data),
        .empty  (fifo_empty),
        .full   (fifo_full)
    );

    // Обертка над моделью регистров
    spi_tx_regs_wrapper u_spi_tx_regs_wrapper (
        .clk       (clk),
        .rst_n     (rst_n),
        .spi_sclk  (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso),
        .spi_irq   (spi_irq),
        .hwif_in   (hwif_in),
        .hwif_out  (hwif_out)
    );

    // Устройство управления передачей данных
    tdl_tx_controller #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_tdl_tx_controller (
        .clk        (clk),
        .rst_n      (rst_n),
        .fifo_empty (fifo_empty),
        .fifo_rdata (fifo_r_data),
        .fifo_rd_en (fifo_r_en),
        .dict_hit   (dict_hit),
        .dict_key   (dict_key),
        .force_sync (force_sync),
        .sdr_data   (sdr_data),
        .sdr_clk    (sdr_clk),
        .sdr_ready  (sdr_ready)
    );
    
    
endmodule
`endif