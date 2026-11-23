`ifndef TDL_TX_PKG
`define TDL_TX_PKG
// Общие типы кадров и политик, формат снимка конфигурации и выдержка TinyLFU.
package tdl_tx_pkg;
    // Software wait after observing both IN_FIFO_EMPTY and controller IDLE.
    localparam int TINYLFU_IDLE_WAIT_CYCLES = 518;

    // Двухбитные типы дескрипторов. Байты заголовков выбирает сериализатор.
    typedef enum logic [1:0] {
        FRAME_RAW  = 2'b00,
        FRAME_KEY  = 2'b01,
        FRAME_SYNC = 2'b10
    } frame_t;

    // Коды алгоритмов совпадают с MODE_REG.ALGO_SEL.
    typedef enum logic [1:0] {
        POLICY_TINYLFU = 2'b00,
        POLICY_SLRU    = 2'b01,
        POLICY_CLOCK   = 2'b10,
        POLICY_LFU     = 2'b11
    } policy_algo_t;

    // Packed layout shared by the CSR bridge, controller snapshot and policy.
    typedef struct packed {
        logic [15:0] aging_period;
        logic [7:0]  n_prob;
        logic [2:0]  reserved;
        logic        bf_en;
        logic        aging_disable;
        logic        cu_disable;
        policy_algo_t algo_sel;
    } policy_cfg_t;
endpackage
`endif
