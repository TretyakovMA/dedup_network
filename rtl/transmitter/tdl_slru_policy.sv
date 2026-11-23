`ifndef TDL_SLRU_POLICY
`define TDL_SLRU_POLICY
// Политика SLRU с квотами Probationary и Protected и обновлением рангов по commit.
module tdl_slru_policy #(
    parameter int DICT_SIZE = 256,
    localparam int KEY_WIDTH = $clog2(DICT_SIZE)
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic                 req_valid,
    output logic                 req_ready,
    input  logic                 req_hit,
    input  logic [KEY_WIDTH-1:0] req_hit_key,
    input  logic [7:0]           req_n_prob,
    input  logic [DICT_SIZE-1:0] valid_bits,
    input  logic                 dict_full,
    input  logic [KEY_WIDTH-1:0] next_free_key,

    output logic                 rsp_valid,
    input  logic                 rsp_ready,
    output logic                 rsp_admit,
    output logic [KEY_WIDTH-1:0] rsp_key,
    input  logic                 commit
);

    localparam int LEAF_COUNT = 1 << KEY_WIDTH;
    localparam bit PROBATIONARY = 1'b0;
    localparam bit PROTECTED    = 1'b1;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_RESPONSE,
        ST_WAIT_COMMIT
    } state_t;

    typedef enum logic [1:0] {
        INSERT_PROB,
        TOUCH_PROT,
        PROMOTE
    } action_t;

    state_t state;
    action_t pending_action;
    logic [DICT_SIZE-1:0] segment;
    // В каждом сегменте ранг 0 соответствует MRU. Наибольший валидный ранг — LRU.
    logic [DICT_SIZE-1:0][KEY_WIDTH-1:0] rank;
    logic [KEY_WIDTH-1:0] selected_key, selected_rank;
    logic [KEY_WIDTH-1:0] demote_key;
    logic                 demote_pending;

    wire [KEY_WIDTH:0]   node_score [0:1][1:2*LEAF_COUNT-1];
    wire [KEY_WIDTH-1:0] node_key   [0:1][1:2*LEAF_COUNT-1];
    logic [8:0] prob_count, prot_count;
    logic [8:0] prob_quota, prot_quota;

    // Два дерева максимума выбирают LRU по паре {принадлежность сегменту, ранг}.
    for (genvar seg = 0; seg < 2; seg++) begin : gen_segment_lru
        for (genvar row = 0; row < LEAF_COUNT; row++) begin : gen_leaf
            assign node_key[seg][LEAF_COUNT + row] = KEY_WIDTH'(row);
            if (row < DICT_SIZE) begin : gen_row
                assign node_score[seg][LEAF_COUNT + row] =
                    {valid_bits[row] && (segment[row] == 1'(seg)), rank[row]};
            end else begin : gen_padding
                assign node_score[seg][LEAF_COUNT + row] = '0;
            end
        end

        for (genvar node = 1; node < LEAF_COUNT; node++) begin : gen_maximum
            wire select_left;
            // При равных рангах слева находится меньший ключ.
            assign select_left = node_score[seg][2*node] >= node_score[seg][2*node + 1];
            assign node_score[seg][node] =
                select_left ? node_score[seg][2*node] : node_score[seg][2*node + 1];
            assign node_key[seg][node] =
                select_left ? node_key[seg][2*node] : node_key[seg][2*node + 1];
        end
    end

    // В непустом сегменте последний ранг равен числу строк минус один.
    assign prob_count = node_score[PROBATIONARY][1][KEY_WIDTH]
                      ? 9'(node_score[PROBATIONARY][1][KEY_WIDTH-1:0]) + 9'd1 : '0;
    assign prot_count = node_score[PROTECTED][1][KEY_WIDTH]
                      ? 9'(node_score[PROTECTED][1][KEY_WIDTH-1:0]) + 9'd1 : '0;
    assign prob_quota = {1'b0, req_n_prob};
    assign prot_quota = 9'(DICT_SIZE) - prob_quota;

    assign req_ready = rst_n && (state == ST_IDLE);
    assign rsp_valid = rst_n && (state == ST_RESPONSE);
    assign rsp_admit = rsp_valid && (pending_action == INSERT_PROB);
    assign rsp_key   = rsp_admit ? selected_key : '0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            pending_action <= INSERT_PROB;
            selected_key   <= '0;
            selected_rank  <= '0;
            demote_key     <= '0;
            demote_pending <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (req_valid) begin
                        if (req_hit) begin
                            pending_action <= segment[req_hit_key] == PROTECTED ? TOUCH_PROT : PROMOTE;
                            selected_key   <= req_hit_key;
                            selected_rank  <= rank[req_hit_key];
                            demote_key     <= node_key[PROTECTED][1];
                            demote_pending <= (prot_count == prot_quota);
                        end else begin
                            pending_action <= INSERT_PROB;
                            // Квота Probationary ограничивает вставку даже при свободном месте в словаре.
                            selected_key   <= (prob_count == prob_quota)
                                            ? node_key[PROBATIONARY][1] : next_free_key;
                        end
                        state <= ST_RESPONSE;
                    end
                end

                ST_RESPONSE: begin
                    if (rsp_ready)
                        state <= ST_WAIT_COMMIT;
                end

                ST_WAIT_COMMIT: begin
                    if (commit)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            segment <= '0;
            rank    <= '0;
        // Теги и ранги меняются только при commit. Promote и demote сохраняют физические ключи.
        end else if (state == ST_WAIT_COMMIT && commit) begin
            for (int row = 0; row < DICT_SIZE; row++) begin
                if (KEY_WIDTH'(row) == selected_key) begin
                    segment[row] <= (pending_action == INSERT_PROB) ? PROBATIONARY : PROTECTED;
                    rank[row]    <= '0;
                end else if (pending_action == PROMOTE && demote_pending && KEY_WIDTH'(row) == demote_key) begin
                    segment[row] <= PROBATIONARY;
                    rank[row]    <= '0;
                end else if (valid_bits[row]) begin
                    case (pending_action)
                        INSERT_PROB: begin
                            if (segment[row] == PROBATIONARY)
                                rank[row] <= rank[row] + 1'b1;
                        end
                        TOUCH_PROT: begin
                            if (segment[row] == PROTECTED && rank[row] < selected_rank)
                                rank[row] <= rank[row] + 1'b1;
                        end
                        PROMOTE: begin
                            // При demote сжатие и вставка компенсируются для старших рангов Probationary.
                            if (segment[row] == PROTECTED || (demote_pending && rank[row] < selected_rank))
                                rank[row] <= rank[row] + 1'b1;
                            else if (!demote_pending && rank[row] > selected_rank)
                                rank[row] <= rank[row] - 1'b1;
                        end
                        default: ;
                    endcase
                end
            end
        end
    end

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert ((DICT_SIZE >= 2) && (DICT_SIZE <= 256))
            else $error("tdl_slru_policy requires 2 <= DICT_SIZE <= 256");
    end

    always @(posedge clk) begin : check_request
        logic [2*LEAF_COUNT-1:0] seen_rank;
        int prob_rows, prot_rows;

        if (req_valid && req_ready) begin
            assert (req_n_prob != 0 && int'(req_n_prob) < DICT_SIZE)
                else $error("tdl_slru_policy requires 1 <= req_n_prob < DICT_SIZE");
            assert (dict_full == (&valid_bits))
                else $error("tdl_slru_policy dict_full disagrees with valid_bits");
            if (req_hit) begin
                assert (int'(req_hit_key) < DICT_SIZE && valid_bits[req_hit_key])
                    else $error("tdl_slru_policy hit key must refer to a valid row");
            end else if (prob_count < prob_quota) begin
                assert (!dict_full && int'(next_free_key) < DICT_SIZE && !valid_bits[next_free_key])
                    else $error("tdl_slru_policy free key must refer to an empty row");
            end

            seen_rank = '0;
            prob_rows = 0;
            prot_rows = 0;
            for (int row = 0; row < DICT_SIZE; row++) begin
                if (valid_bits[row]) begin
                    assert (!seen_rank[{segment[row], rank[row]}])
                        else $error("tdl_slru_policy duplicate rank in segment %0d", segment[row]);
                    seen_rank[{segment[row], rank[row]}] = 1'b1;
                    if (segment[row] == PROTECTED)
                        prot_rows++;
                    else
                        prob_rows++;
                end
            end
            assert (int'(prob_count) == prob_rows && int'(prot_count) == prot_rows)
                else $error("tdl_slru_policy ranks must be contiguous from MRU to LRU");
            assert (prob_count <= prob_quota && prot_count <= prot_quota)
                else $error("tdl_slru_policy segment exceeds its quota");
        end
    end
`endif

endmodule
`endif
