`ifndef TDL_AGING_CTRL
`define TDL_AGING_CTRL
// Считает подтверждённые слова TinyLFU и планирует затухание счётчиков и ротацию BF.
module tdl_aging_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        word_commit,
    input  logic [15:0] aging_period,
    input  logic        aging_disable,
    input  logic        bf_en,
    input  logic        word_updates_done,

    output logic        cms_aging_req,
    input  logic        cms_aging_done,
    output logic        local_aging_req,
    input  logic        local_aging_done,
    output logic        bf_rotate_req,
    input  logic        bf_rotate_done,

    output logic        busy,
    output logic        aging_done
);
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_UPDATES,
        ST_ISSUE,
        ST_WAIT_DONE
    } state_t;

    state_t state;
    logic [15:0] previous_period, words_in_period;
    logic [16:0] next_word_count;
    logic [2:0] enabled_ops, pending_ops, remaining_ops;

    assign busy = rst_n && (state != ST_IDLE);
    // Первое слово с новым периодом начинает новый отсчёт. Сумма на один бит шире периода.
    assign next_word_count = (aging_period == previous_period)
                           ? {1'b0, words_in_period} + 17'd1 : 17'd1;

    // Порядок битов маски: CMS, локальные счётчики, Bloom Filter.
    assign enabled_ops   = {!aging_disable, !aging_disable, bf_en};
    assign remaining_ops = pending_ops & ~{cms_aging_done, local_aging_done, bf_rotate_done};
    assign {cms_aging_req, local_aging_req, bf_rotate_req} =
        (rst_n && state == ST_ISSUE) ? pending_ops : 3'b000;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            previous_period <= '0;
            words_in_period <= '0;
            pending_ops     <= '0;
            aging_done      <= 1'b0;
        end else begin
            aging_done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (word_commit) begin
                        previous_period <= aging_period;
                        if (aging_period == 0 || enabled_ops == 0) begin
                            words_in_period <= '0;
                        end else if (next_word_count == {1'b0, aging_period}) begin
                            words_in_period <= '0;
                            pending_ops     <= enabled_ops;
                            state           <= ST_WAIT_UPDATES;
                        end else begin
                            words_in_period <= next_word_count[15:0];
                        end
                    end
                end
                // Обслуживание ждёт завершения обычных записей граничного слова.
                ST_WAIT_UPDATES: begin
                    if (word_updates_done)
                        state <= ST_ISSUE;
                end
                ST_ISSUE: state <= ST_WAIT_DONE;
                ST_WAIT_DONE: begin
                    // Подтверждения могут прийти в разных тактах. Погашенная операция больше не ожидается.
                    pending_ops <= remaining_ops;
                    if (remaining_ops == 0) begin
                        aging_done <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n)
            assert (!word_commit || !busy)
                else $error("tdl_aging_ctrl word_commit while busy");
    end
`endif

endmodule
`endif
