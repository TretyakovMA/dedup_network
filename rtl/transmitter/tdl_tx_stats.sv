`ifndef TDL_TX_STATS
`define TDL_TX_STATS
// Считает принятые слова и переданные кадры и формирует аппаратные источники IRQ.
module tdl_tx_stats (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        axis_accept,
    input  logic        frame_done,
    input  logic [1:0]  frame_done_type,
    input  logic        bf_filtered_event,
    input  logic        fifo_full,
    input  logic        aging_done,
    input  logic        spi_addr_err_event,
    input  logic [7:0]  hit_rate_thresh,

    output logic [31:0] cnt_total_words,
    output logic [31:0] cnt_key_frames,
    output logic [31:0] cnt_raw_frames,
    output logic [31:0] cnt_sync_frames,
    output logic [31:0] cnt_bf_filtered,
    output logic        fifo_full_event,
    output logic        aging_event,
    output logic        high_hit_rate,
    output logic        spi_addr_err
);
    import tdl_tx_pkg::*;

    logic        fifo_full_previous;
    logic [39:0] scaled_hits, scaled_threshold;

    function automatic logic [31:0] saturating_increment(input logic [31:0] count);
        return (&count) ? count : count + 32'd1;
    endfunction

    // Заполнение FIFO выдаёт один импульс на переходе в full. Остальные события уже однотактные.
    assign fifo_full_event = rst_n && fifo_full && !fifo_full_previous;
    assign aging_event     = rst_n && aging_done;
    assign spi_addr_err    = rst_n && spi_addr_err_event;

    // Полная ширина обоих произведений сохраняется до сравнения.
    assign scaled_hits      = 40'd255 * cnt_key_frames;
    assign scaled_threshold = {8'b0, cnt_total_words} * hit_rate_thresh;
    assign high_hit_rate    = (cnt_total_words != 0) && (scaled_hits > scaled_threshold);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_total_words    <= '0;
            cnt_key_frames     <= '0;
            cnt_raw_frames     <= '0;
            cnt_sync_frames    <= '0;
            cnt_bf_filtered    <= '0;
            fifo_full_previous <= 1'b0;
        end else begin
            fifo_full_previous <= fifo_full;

            // Принятие слова, отсев BF и окончание SDR-кадра относятся к разным этапам тракта.
            if (axis_accept)
                cnt_total_words <= saturating_increment(cnt_total_words);
            if (bf_filtered_event)
                cnt_bf_filtered <= saturating_increment(cnt_bf_filtered);

            if (frame_done) begin
                case (frame_done_type)
                    FRAME_RAW:  cnt_raw_frames  <= saturating_increment(cnt_raw_frames);
                    FRAME_KEY:  cnt_key_frames  <= saturating_increment(cnt_key_frames);
                    FRAME_SYNC: cnt_sync_frames <= saturating_increment(cnt_sync_frames);
                    default: ; // Зарезервированный тип не учитывается.
                endcase
            end
        end
    end

endmodule
`endif
