module dedup_tx_top # (
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_DEPTH = 16
) (
    input  logic          clk,
    input  logic          rst_n,

    // Входные данные от PHY
    axis_if.slave         s_axis,

    // Входные данные конфигурации
    apb_if.slave          s_apb,

    // Выходные данные приемнику
    axis_if.master        m_axis
);

    // Интерфейс для передачи данных в регистровый модуль
    tx_regs_pkg::tx_regs__in_t  hwif_in;
    tx_regs_pkg::tx_regs__out_t hwif_out;

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
        .s_axis (s_axis),
        .r_en   (fifo_r_en),
        .r_data (fifo_r_data),
        .empty  (fifo_empty),
        .full   (fifo_full)
    );

    // Инстанцирование обертки регистрового модуля
    tx_regs_wrapper u_tx_regs_wrapper (
        .s_apb     (s_apb),
        .hwif_in   (hwif_in),
        .hwif_out  (hwif_out)
    );

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