`ifndef TDL_TX_POLICY
`define TDL_TX_POLICY
// Выбирает политику дедупликации и маршрутизирует запрос, ответ и commit.
module tdl_tx_policy #(
    parameter int DICT_SIZE = 256,
    localparam int KEY_WIDTH = $clog2(DICT_SIZE)
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [31:0]          policy_cfg,

    input  logic                 policy_req_valid,
    output logic                 policy_req_ready,
    input  logic [31:0]          policy_word,
    input  logic                 policy_hit,
    input  logic [KEY_WIDTH-1:0] policy_hit_key,
    input  logic [31:0]          policy_req_cfg,
    input  logic [DICT_SIZE-1:0] valid_bits,
    input  logic                 dict_full,
    input  logic [KEY_WIDTH-1:0] next_free_key,

    output logic                 policy_rsp_valid,
    input  logic                 policy_rsp_ready,
    output logic                 policy_admit,
    output logic [KEY_WIDTH-1:0] policy_key,
    output logic                 policy_bf_filtered,
    input  logic                 policy_commit,
    output logic                 aging_done
);
    import tdl_tx_pkg::*;

    typedef enum logic [1:0] {
        ST_IDLE, ST_RESPONSE, ST_WAIT_COMMIT, ST_WAIT_BACKEND
    } state_t;

    state_t state;
    policy_algo_t owner_q;
    policy_cfg_t active_cfg, request_cfg;
    logic cfg_valid, request_cfg_valid, snapshot_matches;
    logic [3:0] backend_req_valid, backend_req_ready;
    logic [3:0] backend_rsp_valid, backend_rsp_ready, backend_admit, backend_commit;
    wire [KEY_WIDTH-1:0] backend_key [0:3];
    logic tiny_bf_filtered, tiny_aging_done;

    function automatic logic configuration_valid(input policy_cfg_t cfg);
        configuration_valid = 1'b0;
        if (cfg.reserved == 0) begin
            case (cfg.algo_sel)
                POLICY_TINYLFU, POLICY_CLOCK, POLICY_LFU:
                    configuration_valid = 1'b1;
                POLICY_SLRU:
                    if (cfg.n_prob >= 1 && int'(cfg.n_prob) < DICT_SIZE)
                        configuration_valid = 1'b1;
                default: ;
            endcase
        end
    endfunction

    assign active_cfg = policy_cfg;
    assign request_cfg = policy_req_cfg;
    assign cfg_valid = configuration_valid(active_cfg);
    assign request_cfg_valid = configuration_valid(request_cfg);
    // Mutable TinyLFU fields come from the saved word snapshot, not the live CSR.
    assign snapshot_matches = request_cfg_valid &&
                              request_cfg.algo_sel == active_cfg.algo_sel &&
                              request_cfg.n_prob == active_cfg.n_prob;

    always_comb begin
        backend_req_valid = '0;
        backend_rsp_ready = '0;
        backend_commit = '0;
        policy_req_ready = 1'b0;
        policy_rsp_valid = 1'b0;
        policy_admit = 1'b0;
        policy_key = '0;
        policy_bf_filtered = 1'b0;

        if (rst_n) begin
            // Ready is meaningful before the controller has captured a word.
            if (state == ST_IDLE && cfg_valid && (!policy_req_valid || snapshot_matches)) begin
                policy_req_ready = backend_req_ready[active_cfg.algo_sel];
                backend_req_valid[active_cfg.algo_sel] = policy_req_valid;
            end
            // Ответ и commit маршрутизируются по владельцу принятого запроса, а не по новым CSR.
            if (state == ST_RESPONSE) begin
                backend_rsp_ready[owner_q] = policy_rsp_ready;
                policy_rsp_valid = backend_rsp_valid[owner_q];
                if (backend_rsp_valid[owner_q]) begin
                    policy_admit = backend_admit[owner_q];
                    policy_key = backend_key[owner_q];
                    if (owner_q == POLICY_TINYLFU)
                        policy_bf_filtered = tiny_bf_filtered;
                end
            end
            if (state == ST_WAIT_COMMIT)
                backend_commit[owner_q] = policy_commit;
        end
    end

    // The owner remains latched throughout post-commit TinyLFU maintenance.
    assign aging_done = rst_n && owner_q == POLICY_TINYLFU && tiny_aging_done;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            owner_q <= POLICY_TINYLFU;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (policy_req_valid && policy_req_ready) begin
                        owner_q <= request_cfg.algo_sel;
                        state <= ST_RESPONSE;
                    end
                end
                ST_RESPONSE: begin
                    if (policy_rsp_valid && policy_rsp_ready)
                        state <= ST_WAIT_COMMIT;
                end
                ST_WAIT_COMMIT: begin
                    if (policy_commit)
                        state <= ST_WAIT_BACKEND;
                end
                // Даже после commit backend может быть занят записью, затуханием или ротацией.
                ST_WAIT_BACKEND: begin
                    if (backend_req_ready[owner_q])
                        state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    tdl_tinylfu_policy #(.DICT_SIZE(DICT_SIZE)) u_tinylfu (
        .clk(clk), .rst_n(rst_n),
        .req_valid(backend_req_valid[POLICY_TINYLFU]), .req_ready(backend_req_ready[POLICY_TINYLFU]),
        .req_hit(policy_hit), .req_hit_key(policy_hit_key), .req_word(policy_word),
        .req_cu_disable(request_cfg.cu_disable), .req_aging_disable(request_cfg.aging_disable),
        .req_bf_en(request_cfg.bf_en), .req_aging_period(request_cfg.aging_period),
        .valid_bits(valid_bits), .dict_full(dict_full), .next_free_key(next_free_key),
        .rsp_valid(backend_rsp_valid[POLICY_TINYLFU]), .rsp_ready(backend_rsp_ready[POLICY_TINYLFU]),
        .rsp_admit(backend_admit[POLICY_TINYLFU]), .rsp_key(backend_key[POLICY_TINYLFU]),
        .rsp_bf_filtered(tiny_bf_filtered), .commit(backend_commit[POLICY_TINYLFU]),
        .aging_done(tiny_aging_done)
    );

    tdl_slru_policy #(.DICT_SIZE(DICT_SIZE)) u_slru (
        .clk(clk), .rst_n(rst_n),
        .req_valid(backend_req_valid[POLICY_SLRU]), .req_ready(backend_req_ready[POLICY_SLRU]),
        .req_hit(policy_hit), .req_hit_key(policy_hit_key), .req_n_prob(request_cfg.n_prob),
        .valid_bits(valid_bits), .dict_full(dict_full), .next_free_key(next_free_key),
        .rsp_valid(backend_rsp_valid[POLICY_SLRU]), .rsp_ready(backend_rsp_ready[POLICY_SLRU]),
        .rsp_admit(backend_admit[POLICY_SLRU]), .rsp_key(backend_key[POLICY_SLRU]),
        .commit(backend_commit[POLICY_SLRU])
    );

    tdl_clock_policy #(.DICT_SIZE(DICT_SIZE)) u_clock (
        .clk(clk), .rst_n(rst_n),
        .req_valid(backend_req_valid[POLICY_CLOCK]), .req_ready(backend_req_ready[POLICY_CLOCK]),
        .req_hit(policy_hit), .req_hit_key(policy_hit_key),
        .valid_bits(valid_bits), .dict_full(dict_full), .next_free_key(next_free_key),
        .rsp_valid(backend_rsp_valid[POLICY_CLOCK]), .rsp_ready(backend_rsp_ready[POLICY_CLOCK]),
        .rsp_admit(backend_admit[POLICY_CLOCK]), .rsp_key(backend_key[POLICY_CLOCK]),
        .commit(backend_commit[POLICY_CLOCK])
    );

    tdl_lfu_policy #(.DICT_SIZE(DICT_SIZE)) u_lfu (
        .clk(clk), .rst_n(rst_n),
        .req_valid(backend_req_valid[POLICY_LFU]), .req_ready(backend_req_ready[POLICY_LFU]),
        .req_hit(policy_hit), .req_hit_key(policy_hit_key),
        .valid_bits(valid_bits), .dict_full(dict_full), .next_free_key(next_free_key),
        .rsp_valid(backend_rsp_valid[POLICY_LFU]), .rsp_ready(backend_rsp_ready[POLICY_LFU]),
        .rsp_admit(backend_admit[POLICY_LFU]), .rsp_key(backend_key[POLICY_LFU]),
        .commit(backend_commit[POLICY_LFU])
    );

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert ((DICT_SIZE >= 2) && (DICT_SIZE <= 256))
            else $error("tdl_tx_policy requires 2 <= DICT_SIZE <= 256");
    end

    always @(posedge clk) begin
        if (rst_n) begin
            assert (!policy_commit || state == ST_WAIT_COMMIT)
                else $error("tdl_tx_policy commit without an accepted response");
            if (state == ST_IDLE && policy_req_valid) begin
                assert (cfg_valid && request_cfg_valid && snapshot_matches)
                    else $error("tdl_tx_policy invalid configuration or mismatched snapshot");
            end
        end
    end
`endif

endmodule
`endif
