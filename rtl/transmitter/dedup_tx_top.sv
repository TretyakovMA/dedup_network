`ifndef DEDUP_TX_TOP
`define DEDUP_TX_TOP
module dedup_tx_top # (
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_DEPTH = 16,
    parameter int BUS_WIDTH  = 8
) (
    input  logic          clk,
    input  logic          rst_n,

    // Входные данные от PHY
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,
    input  logic                  s_axis_tlast,

    // Выходные данные приемнику
    output logic [BUS_WIDTH-1:0]  m_axis_tdata,
    output logic                  m_axis_tvalid,
    input  logic                  m_axis_tready,
    output logic                  m_axis_tlast,

    // Физический интерфейс SPI Slave
    input  logic        spi_sclk,
    input  logic        spi_cs_n,
    input  logic        spi_mosi,
    output logic        spi_miso
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


    spi_if               s_spi (clk, rst_n);
    axis_if#(DATA_WIDTH) s_axis(clk, rst_n);
    axis_if#(BUS_WIDTH)  m_axis(clk, rst_n);

    assign s_spi.sclk = spi_sclk;
    assign s_spi.cs_n = spi_cs_n;
    assign s_spi.mosi = spi_mosi;
    assign spi_miso   = s_spi.miso;

    assign s_axis.tdata  = s_axis_tdata;
    assign s_axis.tvalid = s_axis_tvalid;
    assign s_axis_tready = s_axis.tready;
    assign s_axis.tlast  = s_axis_tlast;

    assign m_axis_tdata  = m_axis.tdata;
    assign m_axis_tvalid = m_axis.tvalid;
    assign m_axis.tready = m_axis_tready;
    assign m_axis_tlast  = m_axis.tlast;

    // Входное fifo
    axis_input_fifo #(
        .WIDTH(DATA_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_axis_input_fifo (
        .s_axis (s_axis),
        .r_en   (fifo_r_en),
        .r_data (fifo_r_data),
        .empty  (fifo_empty),
        .full   (fifo_full)
    );

    // Обертка над моделью регистров
    spi_tx_regs_wrapper u_spi_tx_regs_wrapper (
        .clk       (clk),
        .rst_n     (rst_n),
        .s_spi     (s_spi),
        .hwif_in   (hwif_in),
        .hwif_out  (hwif_out)
    );

    // Устройство управления передачей данных
    dedup_tx_controller #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dedup_tx_controller (
        .clk        (clk),
        .rst_n      (rst_n),
        .fifo_empty (fifo_empty),
        .fifo_rdata (fifo_r_data),
        .fifo_rd_en (fifo_r_en),
        .dict_hit   (dict_hit),
        .dict_key   (dict_key),
        .force_sync (force_sync),
        .m_axis     (m_axis)
    );
    
    
endmodule
`endif