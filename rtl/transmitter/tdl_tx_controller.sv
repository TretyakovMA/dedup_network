`ifndef TDL_TX_CONTROLLER
`define TDL_TX_CONTROLLER
// Захватывает слова из FWFT FIFO, опрашивает словарь и политику и формирует дескрипторы.
module tdl_tx_controller #(
    parameter int DATA_WIDTH = 32,
    parameter int DICT_SIZE  = 256,
    localparam int KEY_WIDTH = $clog2(DICT_SIZE)
) (
    // Такт контроллера и активный низкий сброс.
    input  logic                    clk,
    input  logic                    rst_n,

    // Управление обработкой новых слов. Bypass пропускает слово как RAW
    // и не требует готовности алгоритмического backend.
    input  logic                    tx_en,
    input  logic                    bypass_en,
    // Снимок активных настроек политики; фиксируется при извлечении слова.
    input  logic [31:0]             policy_cfg,
    input  logic                    backend_ready,
    // busy относится только к текущему слову, обрабатываемому контроллером.
    output logic                    busy,
    // Код текущего состояния для диагностического регистра.
    output logic [2:0]              state_code,

    // FWFT FIFO: fifo_rdata захватывается на том же фронте, что и pop.
    input  logic                    fifo_empty,
    input  logic [DATA_WIDTH-1:0]   fifo_rdata,
    output logic                    fifo_rd_en,

    // Канал поиска: запрос удерживается до valid/ready, ответ принимается
    // только в состоянии ожидания результата.
    output logic                    lookup_req_valid,
    output logic [DATA_WIDTH-1:0]   lookup_word,
    input  logic                    lookup_req_ready,
    input  logic                    lookup_rsp_valid,
    input  logic                    lookup_hit,
    input  logic [KEY_WIDTH-1:0]    lookup_key,
    output logic                    lookup_rsp_ready,

    // Канал политики. Политика вызывается и при hit, чтобы обновить
    // метаданные совпавшей строки.
    output logic                    policy_req_valid,
    output logic [DATA_WIDTH-1:0]   policy_word,
    output logic                    policy_hit,
    output logic [KEY_WIDTH-1:0]    policy_hit_key,
    output logic [31:0]             policy_req_cfg,
    input  logic                    policy_req_ready,
    input  logic                    policy_rsp_valid,
    input  logic                    policy_admit,
    input  logic [KEY_WIDTH-1:0]    policy_key,
    input  logic                    policy_bf_filtered,
    output logic                    policy_rsp_ready,
    // Подтверждает подготовленные изменения только при приеме дескриптора.
    output logic                    policy_commit,

    // Дескриптор удерживается неизменным, пока следующий блок не готов его принять.
    output logic                    desc_valid,
    output logic [1:0]              desc_type,
    output logic [7:0]              desc_key,
    output logic [DATA_WIDTH-1:0]   desc_data,
    input  logic                    desc_ready,

    // Запись словаря выполняется одновременно с commit только для SYNC.
    output logic                    dict_wr_en,
    output logic [KEY_WIDTH-1:0]    dict_wr_key,
    output logic [DATA_WIDTH-1:0]   dict_wr_data,
    // Однотактные события приема дескриптора и отсева Bloom Filter.
    output logic                    word_committed,
    output logic                    bf_filtered_event
);

    import tdl_tx_pkg::*;

    // Числовые коды состояний соответствуют state_code.
    typedef enum logic [2:0] {
        ST_IDLE        = 3'd0,
        ST_LOOKUP_REQ  = 3'd1,
        ST_LOOKUP_WAIT = 3'd2,
        ST_POLICY_REQ  = 3'd3,
        ST_POLICY_WAIT = 3'd4,
        ST_OUTPUT      = 3'd5
    } state_t;

    state_t state, next_state;
    frame_t desc_type_q;

    logic [DATA_WIDTH-1:0] word_data;             // Слово, уже принятое из FIFO.
    logic [31:0]           cfg_q;                 // Настройки политики для этого слова.
    logic                  bypass_q;              // Снимок режима при извлечении слова.
    logic                  hit_q;                 // Сохраненный ответ поиска.
    logic [KEY_WIDTH-1:0]  hit_key_q;             // Ключ из ответа поиска.
    logic [KEY_WIDTH-1:0]  decision_key_q;        // Ключ выбранного дескриптора/записи.
    logic                  decision_key_valid_q;  // Не позволяет выдать ключ вне DICT_SIZE.
    logic                  bf_filtered_q;         // Флаг отсева, подготовленный политикой.
    logic [7:0]            desc_key_q;            // Ключ дескриптора, расширенный до 8 бит.
    logic [DATA_WIDTH-1:0] desc_data_q;           // Данные неизменны до commit.
    logic                  word_take;             // Событие захвата слова и pop FIFO.
    logic                  commit;                // Handshake дескриптора с приемником.

    // В Bypass backend_ready не блокирует захват: дедупликация не используется.
    // fifo_rd_en — комбинационное разрешение pop на фронте захвата слова.
    assign word_take = rst_n && (state == ST_IDLE) && tx_en &&
                       !fifo_empty && (bypass_en || backend_ready);
    assign fifo_rd_en = word_take;

    // Контроллер занят до передачи результата; это не отражает занятость serializer.
    assign busy       = (state != ST_IDLE);
    assign state_code = state;

    // Запросы остаются активными в соответствующем состоянии до handshake.
    assign lookup_req_valid = rst_n && (state == ST_LOOKUP_REQ);
    assign lookup_word      = word_data;
    assign lookup_rsp_ready = rst_n && (state == ST_LOOKUP_WAIT);

    assign policy_req_valid = rst_n && (state == ST_POLICY_REQ);
    assign policy_word      = word_data;
    assign policy_hit       = hit_q;
    assign policy_hit_key   = hit_key_q;
    assign policy_req_cfg   = cfg_q;
    assign policy_rsp_ready = rst_n && (state == ST_POLICY_WAIT);

    // Некорректный ключ блокирует выдачу дескриптора и вызывает assertion,
    // а не подменяется кадром RAW.
    assign desc_valid = rst_n && (state == ST_OUTPUT) &&
                        ((desc_type_q == FRAME_RAW) || decision_key_valid_q);
    assign desc_type = desc_type_q;
    assign desc_key  = desc_key_q;
    assign desc_data = desc_data_q;

    // Все изменения постоянного состояния синхронизированы с приемом дескриптора.
    assign commit = desc_valid && desc_ready;
    assign dict_wr_en   = commit && (desc_type_q == FRAME_SYNC);
    assign dict_wr_key  = decision_key_q;
    assign dict_wr_data = desc_data_q;
    assign policy_commit = commit && !bypass_q;
    assign word_committed = commit;
    assign bf_filtered_event = policy_commit && bf_filtered_q;

    // Последовательность обработки: захват -> поиск -> политика -> выдача.
    // В Bypass этапы поиска и политики пропускаются.
    always_comb begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (word_take) begin
                    if (bypass_en) next_state = ST_OUTPUT;
                    else           next_state = ST_LOOKUP_REQ;
                end
            end

            ST_LOOKUP_REQ: begin
                if (lookup_req_valid && lookup_req_ready)
                    next_state = ST_LOOKUP_WAIT;
            end

            ST_LOOKUP_WAIT: begin
                if (lookup_rsp_valid && lookup_rsp_ready)
                    next_state = ST_POLICY_REQ;
            end

            ST_POLICY_REQ: begin
                if (policy_req_valid && policy_req_ready)
                    next_state = ST_POLICY_WAIT;
            end

            ST_POLICY_WAIT: begin
                if (policy_rsp_valid && policy_rsp_ready)
                    next_state = ST_OUTPUT;
            end

            ST_OUTPUT: begin
                if (commit) next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= ST_IDLE;
            word_data              <= '0;
            cfg_q                  <= '0;
            bypass_q               <= 1'b0;
            hit_q                  <= 1'b0;
            hit_key_q              <= '0;
            decision_key_q         <= '0;
            decision_key_valid_q   <= 1'b1;
            desc_type_q            <= FRAME_RAW;
            desc_key_q             <= '0;
            desc_data_q            <= '0;
            bf_filtered_q          <= 1'b0;
        end
        else begin
            state <= next_state;

            // Слово и настройки фиксируются вместе; дальнейшая обработка
            // не зависит от изменившихся выходов FIFO или регистров конфигурации.
            if (word_take) begin
                word_data <= fifo_rdata;
                cfg_q     <= policy_cfg;
                bypass_q  <= bypass_en;

                if (bypass_en) begin
                    desc_type_q           <= FRAME_RAW;
                    desc_key_q            <= '0;
                    desc_data_q           <= fifo_rdata;
                    decision_key_q        <= '0;
                    decision_key_valid_q  <= 1'b1;
                    bf_filtered_q         <= 1'b0;
                end
            end

            if (lookup_rsp_valid && lookup_rsp_ready) begin
                // Ключ ответа сохраняется для передачи в политику и будущий KEY.
                hit_q     <= lookup_hit;
                hit_key_q <= lookup_key;
`ifndef SYNTHESIS
                assert (!lookup_hit || (lookup_key < DICT_SIZE))
                    else $error("tdl_tx_controller received an out-of-range lookup key");
`endif
            end

            if (policy_rsp_valid && policy_rsp_ready) begin
                bf_filtered_q <= policy_bf_filtered;

                // Hit всегда дает KEY и использует ключ поиска.
                // На miss политика выбирает между SYNC с выделенным ключом и RAW.
                if (hit_q) begin
                    desc_type_q          <= FRAME_KEY;
                    desc_key_q           <= hit_key_q;
                    decision_key_q       <= hit_key_q;
                    decision_key_valid_q <= (hit_key_q < DICT_SIZE);
`ifndef SYNTHESIS
                    assert (hit_key_q < DICT_SIZE)
                        else $error("tdl_tx_controller received an out-of-range hit key");
`endif
                end
                else if (policy_admit) begin
                    desc_type_q          <= FRAME_SYNC;
                    desc_key_q           <= policy_key;
                    decision_key_q       <= policy_key;
                    decision_key_valid_q <= (policy_key < DICT_SIZE);
`ifndef SYNTHESIS
                    assert (policy_key < DICT_SIZE)
                        else $error("tdl_tx_controller received an out-of-range policy key");
`endif
                end
                else begin
                    desc_type_q          <= FRAME_RAW;
                    desc_key_q           <= '0;
                    decision_key_q       <= '0;
                    decision_key_valid_q <= 1'b1;
                end

                desc_data_q <= word_data;
            end
        end
    end

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert (DATA_WIDTH == 32)
            else $error("tdl_tx_controller requires DATA_WIDTH == 32");
        assert ((DICT_SIZE >= 2) && (DICT_SIZE <= 256))
            else $error("tdl_tx_controller requires 2 <= DICT_SIZE <= 256");
    end
`endif

endmodule
`endif
