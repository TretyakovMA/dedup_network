`ifndef TDL_TINYLFU_POLICY
`define TDL_TINYLFU_POLICY
// Политика TinyLFU, объединяющая точное попадание, BF, CMS и локальные частоты строк.
module tdl_tinylfu_policy #(
    parameter int DICT_SIZE = 256,
    localparam int KEY_WIDTH = $clog2(DICT_SIZE)
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic                 req_valid,
    output logic                 req_ready,
    input  logic                 req_hit,
    input  logic [KEY_WIDTH-1:0] req_hit_key,
    input  logic [31:0]          req_word,
    input  logic                 req_cu_disable,
    input  logic                 req_aging_disable,
    input  logic                 req_bf_en,
    input  logic [15:0]          req_aging_period,
    input  logic [DICT_SIZE-1:0] valid_bits,
    input  logic                 dict_full,
    input  logic [KEY_WIDTH-1:0] next_free_key,

    output logic                 rsp_valid,
    input  logic                 rsp_ready,
    output logic                 rsp_admit,
    output logic [KEY_WIDTH-1:0] rsp_key,
    output logic                 rsp_bf_filtered,
    input  logic                 commit,
    output logic                 aging_done
);
    localparam int LEAF_COUNT = 1 << KEY_WIDTH;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_HASH_WAIT,
        ST_BF_REQ,
        ST_BF_WAIT,
        ST_CMS_REQ,
        ST_CMS_WAIT,
        ST_RESPONSE,
        ST_WAIT_COMMIT,
        ST_WAIT_WRITES,
        ST_WAIT_AGING
    } state_t;

    state_t state;
    logic [DICT_SIZE-1:0][3:0] local_cnt;
    logic hit_q, cu_disable_q, aging_disable_q, bf_en_q;
    logic [15:0] aging_period_q;
    logic [KEY_WIDTH-1:0] key_q;
    logic admit_q, bf_filtered_q;

    logic hash_in_valid, hash_in_ready, hash_out_valid, hash_out_ready;
    logic [11:0] hash_bf0, hash_bf1, bf_h0_q, bf_h1_q;
    logic [7:0] hash_cms0, hash_cms1, cms_h0_q, cms_h1_q;
    logic bf_req_ready, bf_rsp_valid, bf_rsp_seen, bf_busy, bf_commit;
    logic cms_req_ready, cms_rsp_valid, cms_busy, cms_commit;
    logic [3:0] cms_rsp_est;
    logic bf_rotate_req, bf_rotate_done, cms_aging_req, cms_aging_done;
    logic local_aging_req, local_aging_done, aging_busy;
    logic idle_ready, word_commit, writes_done, word_updates_done;
    logic cms_admit;

    // Валидные строки предшествуют прочим. Равенство отдаётся меньшему ключу.
    wire [4:0] node_score [1:2*LEAF_COUNT-1];
    wire [KEY_WIDTH-1:0] node_key [1:2*LEAF_COUNT-1];

    for (genvar row = 0; row < LEAF_COUNT; row++) begin : gen_leaf
        assign node_key[LEAF_COUNT + row] = KEY_WIDTH'(row);
        if (row < DICT_SIZE) begin : gen_row
            assign node_score[LEAF_COUNT + row] = {!valid_bits[row], local_cnt[row]};
        end else begin : gen_padding
            assign node_score[LEAF_COUNT + row] = '1;
        end
    end

    for (genvar node = 1; node < LEAF_COUNT; node++) begin : gen_minimum
        wire select_left;
        assign select_left = node_score[2*node] <= node_score[2*node + 1];
        assign node_score[node] = select_left ? node_score[2*node] : node_score[2*node + 1];
        assign node_key[node] = select_left ? node_key[2*node] : node_key[2*node + 1];
    end

    assign idle_ready = rst_n && state == ST_IDLE && !bf_busy && !cms_busy && !aging_busy;
    assign req_ready = idle_ready && hash_in_ready;
    // Точное попадание использует локальный счётчик и не обращается к hash, BF или CMS.
    assign hash_in_valid = idle_ready && req_valid && !req_hit;
    assign hash_out_ready = (state == ST_HASH_WAIT);
    assign rsp_valid = rst_n && (state == ST_RESPONSE);
    assign rsp_admit = rsp_valid && admit_q;
    assign rsp_key = rsp_admit ? key_q : '0;
    assign rsp_bf_filtered = rsp_valid && bf_filtered_q;

    // После прохождения BF свободная строка принимается сразу. Замена требует строгого превосходства по частоте.
    assign cms_admit = !dict_full || (cms_rsp_est > node_score[1][3:0]);
    assign word_commit = rst_n && commit && (state == ST_WAIT_COMMIT);
    // Отсев BF всё равно запоминает наблюдение. CMS обновляется только для промахов с полученной оценкой.
    assign bf_commit   = word_commit && !hit_q && bf_en_q;
    assign cms_commit  = word_commit && !hit_q && !bf_filtered_q;
    assign writes_done = !bf_busy && !cms_busy;
    // Планировщик запускает обслуживание после завершения обычных записей текущего слова.
    assign word_updates_done = ((state == ST_WAIT_WRITES) && writes_done) ||
                               (state == ST_WAIT_AGING);

    tdl_tab_hash u_hash (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_valid (hash_in_valid),
        .in_ready (hash_in_ready),
        .data_in  (req_word),
        .out_valid(hash_out_valid),
        .out_ready(hash_out_ready),
        .h_bf1    (hash_bf0),
        .h_bf2    (hash_bf1),
        .h_cms1   (hash_cms0),
        .h_cms2   (hash_cms1)
    );

    tdl_bloom_filter u_bf (
        .clk        (clk),
        .rst_n      (rst_n),
        .req_valid  (state == ST_BF_REQ),
        .req_ready  (bf_req_ready),
        .req_h0     (bf_h0_q),
        .req_h1     (bf_h1_q),
        .rsp_valid  (bf_rsp_valid),
        .rsp_ready  (state == ST_BF_WAIT),
        .rsp_seen   (bf_rsp_seen),
        .commit     (bf_commit),
        .rotate_req (bf_rotate_req),
        .rotate_done(bf_rotate_done),
        .busy       (bf_busy)
    );

    tdl_cms u_cms (
        .clk           (clk),
        .rst_n         (rst_n),
        .req_valid     (state == ST_CMS_REQ),
        .req_ready     (cms_req_ready),
        .req_h0        (cms_h0_q),
        .req_h1        (cms_h1_q),
        .req_cu_disable(cu_disable_q),
        .rsp_valid     (cms_rsp_valid),
        .rsp_ready     (state == ST_CMS_WAIT),
        .rsp_est       (cms_rsp_est),
        .commit        (cms_commit),
        .aging_req     (cms_aging_req),
        .aging_done    (cms_aging_done),
        .busy          (cms_busy)
    );

    tdl_aging_ctrl u_aging_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),
        .word_commit      (word_commit),
        .aging_period     (aging_period_q),
        .aging_disable    (aging_disable_q),
        .bf_en            (bf_en_q),
        .word_updates_done(word_updates_done),
        .cms_aging_req    (cms_aging_req),
        .cms_aging_done   (cms_aging_done),
        .local_aging_req  (local_aging_req),
        .local_aging_done (local_aging_done),
        .bf_rotate_req    (bf_rotate_req),
        .bf_rotate_done   (bf_rotate_done),
        .busy             (aging_busy),
        .aging_done       (aging_done)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            hit_q           <= 1'b0;
            cu_disable_q    <= 1'b0;
            aging_disable_q <= 1'b0;
            bf_en_q         <= 1'b0;
            aging_period_q  <= '0;
            key_q           <= '0;
            admit_q         <= 1'b0;
            bf_filtered_q   <= 1'b0;
            bf_h0_q         <= '0;
            bf_h1_q         <= '0;
            cms_h0_q        <= '0;
            cms_h1_q        <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (req_valid && req_ready) begin
                        hit_q           <= req_hit;
                        cu_disable_q    <= req_cu_disable;
                        aging_disable_q <= req_aging_disable;
                        bf_en_q         <= req_bf_en;
                        aging_period_q  <= req_aging_period;
                        key_q           <= req_hit_key;
                        admit_q         <= 1'b0;
                        bf_filtered_q   <= 1'b0;
                        state           <= req_hit ? ST_RESPONSE : ST_HASH_WAIT;
                    end
                end
                ST_HASH_WAIT: begin
                    if (hash_out_valid) begin
                        bf_h0_q  <= hash_bf0;
                        bf_h1_q  <= hash_bf1;
                        cms_h0_q <= hash_cms0;
                        cms_h1_q <= hash_cms1;
                        state    <= bf_en_q ? ST_BF_REQ : ST_CMS_REQ;
                    end
                end
                ST_BF_REQ: begin
                    if (bf_req_ready)
                        state <= ST_BF_WAIT;
                end
                ST_BF_WAIT: begin
                    // Если BF не нашёл оба отпечатка, политика вернёт RAW и пропустит CMS.
                    if (bf_rsp_valid) begin
                        bf_filtered_q <= !bf_rsp_seen;
                        state         <= bf_rsp_seen ? ST_CMS_REQ : ST_RESPONSE;
                    end
                end
                ST_CMS_REQ: begin
                    if (cms_req_ready)
                        state <= ST_CMS_WAIT;
                end
                ST_CMS_WAIT: begin
                    if (cms_rsp_valid) begin
                        admit_q <= cms_admit;
                        key_q   <= dict_full ? node_key[1] : next_free_key;
                        state   <= ST_RESPONSE;
                    end
                end
                ST_RESPONSE: begin
                    if (rsp_ready)
                        state <= ST_WAIT_COMMIT;
                end
                ST_WAIT_COMMIT: begin
                    if (word_commit)
                        state <= ST_WAIT_WRITES;
                end
                ST_WAIT_WRITES: begin
                    if (writes_done)
                        state <= aging_busy ? ST_WAIT_AGING : ST_IDLE;
                end
                ST_WAIT_AGING: begin
                    if (aging_done)
                        state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            local_cnt        <= '0;
            local_aging_done <= 1'b0;
        end else begin
            // Локальные счётчики делятся параллельно. Подтверждение занимает один такт.
            local_aging_done <= local_aging_req;
            if (local_aging_req) begin
                for (int row = 0; row < DICT_SIZE; row++)
                    local_cnt[row] <= local_cnt[row] >> 1;
            end else if (word_commit) begin
                if (admit_q)
                    local_cnt[key_q] <= 4'd1;
                else if (hit_q && !(&local_cnt[key_q]))
                    local_cnt[key_q] <= local_cnt[key_q] + 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert ((DICT_SIZE >= 2) && (DICT_SIZE <= 256))
            else $error("tdl_tinylfu_policy requires 2 <= DICT_SIZE <= 256");
    end

    always @(posedge clk) begin
        if (rst_n) begin
            assert (!commit || state == ST_WAIT_COMMIT)
                else $error("tdl_tinylfu_policy commit without a pending response");
            if (req_valid && req_ready) begin
                assert (dict_full == (&valid_bits))
                    else $error("tdl_tinylfu_policy dict_full disagrees with valid_bits");
                if (req_hit) begin
                    assert (int'(req_hit_key) < DICT_SIZE && valid_bits[req_hit_key])
                        else $error("tdl_tinylfu_policy hit key must refer to a valid row");
                end else if (!dict_full) begin
                    assert (int'(next_free_key) < DICT_SIZE && !valid_bits[next_free_key])
                        else $error("tdl_tinylfu_policy free key must refer to an empty row");
                end
            end
        end
    end
`endif

endmodule
`endif
