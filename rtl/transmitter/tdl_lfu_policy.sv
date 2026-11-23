`ifndef TDL_LFU_POLICY
`define TDL_LFU_POLICY
// Политика Pure LFU с выбором валидной строки с минимальным локальным счётчиком.
module tdl_lfu_policy #(
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

    localparam int COUNT_WIDTH = 4;
    localparam int LEAF_COUNT = 1 << KEY_WIDTH;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_RESPONSE,
        ST_WAIT_COMMIT
    } state_t;

    state_t state;
    // Счётчик относится к текущему содержимому строки и сбрасывается для нового слова.
    logic [DICT_SIZE-1:0][COUNT_WIDTH-1:0] local_cnt;
    logic [KEY_WIDTH-1:0] selected_key;
    logic                 insert_pending;

    wire [COUNT_WIDTH:0]   node_score [1:2*LEAF_COUNT-1];
    wire [KEY_WIDTH-1:0]   node_key   [1:2*LEAF_COUNT-1];

    // Старший бит оценки отодвигает невалидные и добавочные листья за валидные.
    for (genvar row = 0; row < LEAF_COUNT; row++) begin : gen_leaf
        assign node_key[LEAF_COUNT + row] = KEY_WIDTH'(row);
        if (row < DICT_SIZE) begin : gen_row
            assign node_score[LEAF_COUNT + row] = {!valid_bits[row], local_cnt[row]};
        end else begin : gen_padding
            assign node_score[LEAF_COUNT + row] = '1;
        end
    end

    // Левое поддерево содержит меньшие ключи, поэтому выигрывает при равенстве.
    for (genvar node = 1; node < LEAF_COUNT; node++) begin : gen_minimum
        wire select_left;

        assign select_left = node_score[2*node] <= node_score[2*node + 1];
        assign node_score[node] = select_left ? node_score[2*node] : node_score[2*node + 1];
        assign node_key[node]   = select_left ? node_key[2*node]   : node_key[2*node + 1];
    end

    assign req_ready = rst_n && (state == ST_IDLE);
    assign rsp_valid = rst_n && (state == ST_RESPONSE);
    assign rsp_admit = rsp_valid && insert_pending;
    assign rsp_key   = rsp_admit ? selected_key : '0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            local_cnt      <= '0;
            selected_key   <= '0;
            insert_pending <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (req_valid) begin
                        insert_pending <= !req_hit;
                        if (req_hit)
                            selected_key <= req_hit_key;
                        else if (dict_full)
                            selected_key <= node_key[1];
                        else
                            selected_key <= next_free_key;
                        state <= ST_RESPONSE;
                    end
                end

                ST_RESPONSE: begin
                    if (rsp_ready)
                        state <= ST_WAIT_COMMIT;
                end

                // Подтверждение увеличивает частоту попадания или задаёт начальную частоту вставки.
                ST_WAIT_COMMIT: begin
                    if (commit) begin
                        if (insert_pending)
                            local_cnt[selected_key] <= COUNT_WIDTH'(1);
                        else if (!(&local_cnt[selected_key]))
                            local_cnt[selected_key] <= local_cnt[selected_key] + 1'b1;
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
            else $error("tdl_lfu_policy requires 2 <= DICT_SIZE <= 256");
    end

    always @(posedge clk) begin
        if (req_valid && req_ready) begin
            assert (dict_full == (&valid_bits))
                else $error("tdl_lfu_policy dict_full disagrees with valid_bits");
            if (req_hit) begin
                assert (int'(req_hit_key) < DICT_SIZE && valid_bits[req_hit_key])
                    else $error("tdl_lfu_policy hit key must refer to a valid row");
            end else if (!dict_full) begin
                assert (int'(next_free_key) < DICT_SIZE && !valid_bits[next_free_key])
                    else $error("tdl_lfu_policy free key must refer to an empty row");
            end
        end
    end
`endif

endmodule
`endif
