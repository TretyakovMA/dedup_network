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

    logic [7:0] hash1;

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

    gf2_xor_hash #(
        .DATA_WIDTH(DATA_WIDTH),
        .HASH_WIDTH(8),
        .SEED(32'hF00D_C0DE)
    ) hash_1 (
        .data_in   (fifo_r_data),
        .hash_out  (hash1)
    );
    
    
endmodule