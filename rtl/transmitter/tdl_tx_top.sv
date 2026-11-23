`ifndef TDL_TX_TOP
`define TDL_TX_TOP
// Соединяет тракт AXI-Stream → дедупликация → SDR с управлением и статистикой SPI/CSR.
module tdl_tx_top #(
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_DEPTH = 16,
    parameter int DICT_SIZE  = 256,
    localparam int KEY_WIDTH = $clog2(DICT_SIZE)
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Входные данные от PHY
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,
    input  logic                  s_axis_tlast, // Зарезервирован для границ пакетов

    // Однобитный SDR-интерфейс приемника
    output logic                  sdr_data,
    output logic                  sdr_clk,
    input  logic                  sdr_ready,

    // Физический интерфейс SPI Slave
    input  logic                  spi_sclk,
    input  logic                  spi_cs_n,
    input  logic                  spi_mosi,
    output logic                  spi_miso,
    output logic                  spi_irq
);

    // Регистровый интерфейс и активные настройки тракта.
    tx_regs_pkg::tx_regs__in_t  hwif_in;
    tx_regs_pkg::tx_regs__out_t hwif_out;
    logic                      tx_en;
    logic                      bypass_en;
    logic [31:0]               policy_cfg;
    logic [15:0]               sdr_clk_div;
    logic [7:0]                hit_rate_thresh;

    // Входное FIFO и состояние контроллера.
    logic                  fifo_empty;
    logic                  fifo_full;
    logic [DATA_WIDTH-1:0] fifo_r_data;
    logic                  fifo_r_en;
    logic                  axis_accept;
    logic                  backend_ready;
    logic                  controller_busy;
    logic [2:0]            controller_state;

    // Поиск и обновление словаря.
    logic                  lookup_req_valid;
    logic                  lookup_req_ready;
    logic [DATA_WIDTH-1:0] lookup_word;
    logic                  lookup_rsp_valid;
    logic                  lookup_rsp_ready;
    logic                  lookup_hit;
    logic [KEY_WIDTH-1:0]  lookup_key;
    logic                  dict_wr_en;
    logic [KEY_WIDTH-1:0]  dict_wr_key;
    logic [DATA_WIDTH-1:0] dict_wr_data;
    logic [DICT_SIZE-1:0]  dict_valid_bits;
    logic                  dict_full;
    logic [KEY_WIDTH-1:0]  dict_next_free_key;

    // Запрос к политике со снимком настроек и подтверждение результата.
    logic                  policy_req_valid;
    logic                  policy_req_ready;
    logic [DATA_WIDTH-1:0] policy_word;
    logic                  policy_hit;
    logic [KEY_WIDTH-1:0]  policy_hit_key;
    logic [31:0]           policy_req_cfg;
    logic                  policy_rsp_valid;
    logic                  policy_rsp_ready;
    logic                  policy_admit;
    logic [KEY_WIDTH-1:0]  policy_key;
    logic                  policy_bf_filtered;
    logic                  policy_commit;
    logic                  aging_done;
    logic                  bf_filtered_event;

    // Дескрипторы до и после буфера кадров.
    logic                  ctrl_desc_valid;
    logic                  ctrl_desc_ready;
    logic [1:0]            ctrl_desc_type;
    logic [7:0]            ctrl_desc_key;
    logic [DATA_WIDTH-1:0] ctrl_desc_data;
    logic                  sdr_desc_valid;
    logic                  sdr_desc_ready;
    logic [1:0]            sdr_desc_type;
    logic [7:0]            sdr_desc_key;
    logic [DATA_WIDTH-1:0] sdr_desc_data;
    logic                  frame_done;
    logic [1:0]            frame_done_type;

    // Счётчики и события для CSR.
    logic [31:0] cnt_total_words;
    logic [31:0] cnt_key_frames;
    logic [31:0] cnt_raw_frames;
    logic [31:0] cnt_sync_frames;
    logic [31:0] cnt_bf_filtered;
    logic        fifo_full_event;
    logic        aging_event;
    logic        high_hit_rate;
    logic        spi_addr_err_event;
    logic        spi_addr_err;

    assign axis_accept   = rst_n && s_axis_tvalid && s_axis_tready;
    // При дедупликации новый захват ждёт готовности поиска и политики. Bypass обходит это условие.
    assign backend_ready = lookup_req_ready && policy_req_ready;

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

    tdl_tx_controller #(
        .DATA_WIDTH(DATA_WIDTH),
        .DICT_SIZE (DICT_SIZE)
    ) u_tdl_tx_controller (
        .clk                (clk),
        .rst_n              (rst_n),
        .tx_en              (tx_en),
        .bypass_en          (bypass_en),
        .policy_cfg         (policy_cfg),
        .backend_ready      (backend_ready),
        .busy               (controller_busy),
        .state_code         (controller_state),
        .fifo_empty         (fifo_empty),
        .fifo_rdata         (fifo_r_data),
        .fifo_rd_en         (fifo_r_en),
        .lookup_req_valid   (lookup_req_valid),
        .lookup_req_ready   (lookup_req_ready),
        .lookup_word        (lookup_word),
        .lookup_rsp_valid   (lookup_rsp_valid),
        .lookup_rsp_ready   (lookup_rsp_ready),
        .lookup_hit         (lookup_hit),
        .lookup_key         (lookup_key),
        .policy_req_valid   (policy_req_valid),
        .policy_req_ready   (policy_req_ready),
        .policy_word        (policy_word),
        .policy_hit         (policy_hit),
        .policy_hit_key     (policy_hit_key),
        .policy_req_cfg     (policy_req_cfg),
        .policy_rsp_valid   (policy_rsp_valid),
        .policy_rsp_ready   (policy_rsp_ready),
        .policy_admit       (policy_admit),
        .policy_key         (policy_key),
        .policy_bf_filtered (policy_bf_filtered),
        .policy_commit      (policy_commit),
        .desc_valid         (ctrl_desc_valid),
        .desc_ready         (ctrl_desc_ready),
        .desc_type          (ctrl_desc_type),
        .desc_key           (ctrl_desc_key),
        .desc_data          (ctrl_desc_data),
        .dict_wr_en         (dict_wr_en),
        .dict_wr_key        (dict_wr_key),
        .dict_wr_data       (dict_wr_data),
        .word_committed     (),
        .bf_filtered_event  (bf_filtered_event)
    );

    tdl_dict_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .DICT_SIZE (DICT_SIZE)
    ) u_tdl_dict_unit (
        .clk              (clk),
        .rst_n            (rst_n),
        .flush_dict       (1'b0),
        .search_data      (lookup_word),
        .hit              (),
        .hit_key          (),
        .add_en           (dict_wr_en),
        .use_custom_index (1'b1),
        .wr_key           (dict_wr_key),
        .wr_data          (dict_wr_data),
        .dict_full        (dict_full),
        .next_free_key    (dict_next_free_key),
        .occupied_count   (),
        .valid_bits       (dict_valid_bits),
        .lookup_req_valid (lookup_req_valid),
        .lookup_req_ready (lookup_req_ready),
        .lookup_rsp_valid (lookup_rsp_valid),
        .lookup_rsp_ready (lookup_rsp_ready),
        .lookup_hit       (lookup_hit),
        .lookup_key       (lookup_key)
    );

    tdl_tx_policy #(
        .DICT_SIZE(DICT_SIZE)
    ) u_tdl_tx_policy (
        .clk                (clk),
        .rst_n              (rst_n),
        .policy_cfg         (policy_cfg),
        .policy_req_valid   (policy_req_valid),
        .policy_req_ready   (policy_req_ready),
        .policy_word        (policy_word),
        .policy_hit         (policy_hit),
        .policy_hit_key     (policy_hit_key),
        .policy_req_cfg     (policy_req_cfg),
        .valid_bits         (dict_valid_bits),
        .dict_full          (dict_full),
        .next_free_key      (dict_next_free_key),
        .policy_rsp_valid   (policy_rsp_valid),
        .policy_rsp_ready   (policy_rsp_ready),
        .policy_admit       (policy_admit),
        .policy_key         (policy_key),
        .policy_bf_filtered (policy_bf_filtered),
        .policy_commit      (policy_commit),
        .aging_done         (aging_done)
    );

    tdl_tx_frame_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DICT_SIZE (DICT_SIZE)
    ) u_tdl_tx_frame_buffer (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_desc_valid (ctrl_desc_valid),
        .s_desc_ready (ctrl_desc_ready),
        .s_desc_type  (ctrl_desc_type),
        .s_desc_key   (ctrl_desc_key),
        .s_desc_data  (ctrl_desc_data),
        .m_desc_valid (sdr_desc_valid),
        .m_desc_ready (sdr_desc_ready),
        .m_desc_type  (sdr_desc_type),
        .m_desc_key   (sdr_desc_key),
        .m_desc_data  (sdr_desc_data)
    );

    tdl_tx_serializer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DICT_SIZE (DICT_SIZE)
    ) u_tdl_tx_serializer (
        .clk             (clk),
        .rst_n           (rst_n),
        .tx_en           (tx_en),
        .sdr_clk_div     (sdr_clk_div),
        .busy            (),
        .frame_done      (frame_done),
        .frame_done_type (frame_done_type),
        .desc_valid      (sdr_desc_valid),
        .desc_ready      (sdr_desc_ready),
        .desc_type       (sdr_desc_type),
        .desc_key        (sdr_desc_key),
        .desc_data       (sdr_desc_data),
        .sdr_data        (sdr_data),
        .sdr_clk         (sdr_clk),
        .sdr_ready       (sdr_ready)
    );

    tdl_tx_stats u_tdl_tx_stats (
        .clk                (clk),
        .rst_n              (rst_n),
        .axis_accept        (axis_accept),
        .frame_done         (frame_done),
        .frame_done_type    (frame_done_type),
        .bf_filtered_event  (bf_filtered_event),
        .fifo_full          (fifo_full),
        .aging_done         (aging_done),
        .spi_addr_err_event (spi_addr_err_event),
        .hit_rate_thresh    (hit_rate_thresh),
        .cnt_total_words    (cnt_total_words),
        .cnt_key_frames     (cnt_key_frames),
        .cnt_raw_frames     (cnt_raw_frames),
        .cnt_sync_frames    (cnt_sync_frames),
        .cnt_bf_filtered    (cnt_bf_filtered),
        .fifo_full_event    (fifo_full_event),
        .aging_event        (aging_event),
        .high_hit_rate      (high_hit_rate),
        .spi_addr_err       (spi_addr_err)
    );

    tdl_tx_reg_bridge u_tdl_tx_reg_bridge (
        .clk              (clk),
        .rst_n            (rst_n),
        .hwif_out         (hwif_out),
        .hwif_in          (hwif_in),
        .word_take        (fifo_r_en),
        .fifo_empty       (fifo_empty),
        .fifo_full        (fifo_full),
        .controller_busy  (controller_busy),
        .controller_state (controller_state),
        .policy_ready     (policy_req_ready),
        .cnt_total_words  (cnt_total_words),
        .cnt_key_frames   (cnt_key_frames),
        .cnt_raw_frames   (cnt_raw_frames),
        .cnt_sync_frames  (cnt_sync_frames),
        .cnt_bf_filtered  (cnt_bf_filtered),
        .fifo_full_event  (fifo_full_event),
        .aging_event      (aging_event),
        .high_hit_rate    (high_hit_rate),
        .spi_addr_err     (spi_addr_err),
        .tx_en            (tx_en),
        .bypass_en        (bypass_en),
        .policy_cfg       (policy_cfg),
        .sdr_clk_div      (sdr_clk_div),
        .hit_rate_thresh  (hit_rate_thresh)
    );

    spi_tx_regs_wrapper u_spi_tx_regs_wrapper (
        .clk                (clk),
        .rst_n              (rst_n),
        .spi_sclk           (spi_sclk),
        .spi_cs_n           (spi_cs_n),
        .spi_mosi           (spi_mosi),
        .spi_miso           (spi_miso),
        .spi_irq            (spi_irq),
        .spi_addr_err_event (spi_addr_err_event),
        .hwif_in            (hwif_in),
        .hwif_out           (hwif_out)
    );

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert (DATA_WIDTH == 32)
            else $error("tdl_tx_top requires DATA_WIDTH == 32");
        assert ((DICT_SIZE >= 2) && (DICT_SIZE <= 256))
            else $error("tdl_tx_top requires 2 <= DICT_SIZE <= 256");
        assert ((FIFO_DEPTH >= 2) && ((FIFO_DEPTH & (FIFO_DEPTH - 1)) == 0))
            else $error("tdl_tx_top requires FIFO_DEPTH to be a power of two >= 2");
    end
`endif

endmodule
`endif
