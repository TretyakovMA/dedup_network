`ifndef TDL_CLOCK_POLICY
`define TDL_CLOCK_POLICY
// Политика Clock с кольцевым выбором строки и обновлением битов второго шанса по commit.
module tdl_clock_policy #(
    parameter int DICT_SIZE = 256,
    localparam int KEY_WIDTH = $clog2(DICT_SIZE)
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic                 req_valid,
    output logic                 req_ready,
    input  logic                 req_hit,
    input  logic [KEY_WIDTH-1:0] req_hit_key,
    input  logic [DICT_SIZE-1:0] valid_bits,
    input  logic                 dict_full,
    input  logic [KEY_WIDTH-1:0] next_free_key,

    output logic                 rsp_valid,
    input  logic                 rsp_ready,
    output logic                 rsp_admit,
    output logic [KEY_WIDTH-1:0] rsp_key,
    input  logic                 commit
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SCAN,
        ST_RESPONSE,
        ST_WAIT_COMMIT
    } state_t;

    state_t state;
    logic [DICT_SIZE-1:0] usage_bit;
    logic [KEY_WIDTH-1:0] clock_hand;

    // При обходе маска накапливает очистки, а candidate_key движется по кольцу.
    // После обхода candidate_key хранит ключ до подтверждения транзакции.
    logic [DICT_SIZE-1:0] clear_mask;
    logic [KEY_WIDTH-1:0] candidate_key;
    logic [KEY_WIDTH-1:0] next_key;
    logic                 insert_pending;
    logic                 replace_pending;

    assign req_ready = rst_n && (state == ST_IDLE);
    assign rsp_valid = rst_n && (state == ST_RESPONSE);
    assign rsp_admit = rsp_valid && insert_pending;
    assign rsp_key   = rsp_admit ? candidate_key : '0;

    // Явное замыкание кольца сохраняет допустимый индекс и для размеров, отличных от степени двойки.
    assign next_key = (candidate_key == KEY_WIDTH'(DICT_SIZE - 1))
                    ? '0 : candidate_key + 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            usage_bit       <= '0;
            clock_hand      <= '0;
            clear_mask      <= '0;
            candidate_key   <= '0;
            insert_pending  <= 1'b0;
            replace_pending <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (req_valid) begin
                        clear_mask      <= '0;
                        insert_pending  <= !req_hit;
                        replace_pending <= !req_hit && dict_full;

                        if (req_hit) begin
                            candidate_key <= req_hit_key;
                            state         <= ST_RESPONSE;
                        end else if (!dict_full) begin
                            candidate_key <= next_free_key;
                            state         <= ST_RESPONSE;
                        end else begin
                            candidate_key <= clock_hand;
                            state         <= ST_SCAN;
                        end
                    end
                end

                ST_SCAN: begin
                    // Подготовленная очистка учитывается при повторном посещении строки.
                    if (usage_bit[candidate_key] && !clear_mask[candidate_key]) begin
                        clear_mask[candidate_key] <= 1'b1;
                        candidate_key            <= next_key;
                    end else begin
                        state <= ST_RESPONSE;
                    end
                end

                ST_RESPONSE: begin
                    if (rsp_ready)
                        state <= ST_WAIT_COMMIT;
                end

                ST_WAIT_COMMIT: begin
                    if (commit) begin
                        // Выбранная строка получает usage=1 даже после полного круга.
                        usage_bit <= (usage_bit & ~clear_mask) | (DICT_SIZE'(1'b1) << candidate_key);
                        if (replace_pending)
                            clock_hand <= next_key;
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert ((DICT_SIZE >= 2) && (DICT_SIZE <= 256))
            else $error("tdl_clock_policy requires 2 <= DICT_SIZE <= 256");
    end

    // Все три входа состояния словаря относятся к одному снимку storage.
    always @(posedge clk) begin
        if (req_valid && req_ready) begin
            assert (dict_full == (&valid_bits))
                else $error("tdl_clock_policy dict_full disagrees with valid_bits");
            if (req_hit) begin
                assert (int'(req_hit_key) < DICT_SIZE && valid_bits[req_hit_key])
                    else $error("tdl_clock_policy hit key must refer to a valid row");
            end else if (!dict_full) begin
                assert (int'(next_free_key) < DICT_SIZE && !valid_bits[next_free_key])
                    else $error("tdl_clock_policy free key must refer to an empty row");
            end
        end
    end
`endif

endmodule
`endif
