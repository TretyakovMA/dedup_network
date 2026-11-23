`ifndef TDL_DICT_UNIT
`define TDL_DICT_UNIT
// Объединяет хранилище словаря, точный поиск и зарегистрированный ответ lookup.
module tdl_dict_unit #(
    parameter int DATA_WIDTH = 32,
    parameter int DICT_SIZE  = 256,
    localparam int KEY_WIDTH  = $clog2(DICT_SIZE)
) (
    input  logic                                clk,
    input  logic                                rst_n,
    input  logic                                flush_dict,

    // Захваченное контроллером слово (lookup_word).
    input  logic [DATA_WIDTH-1:0]               search_data,

    // Результаты параллельного поиска
    output logic                                hit,
    output logic [KEY_WIDTH-1:0]                hit_key,

    // Управление записью/добавлением
    input  logic                                add_en,
    input  logic                                use_custom_index, // 0: авто-выбор свободного, 1: целевой wr_key
    input  logic [KEY_WIDTH-1:0]                wr_key,
    input  logic [DATA_WIDTH-1:0]               wr_data,

    // Статусы
    output logic                                dict_full,
    output logic [KEY_WIDTH-1:0]                next_free_key,
    output logic [KEY_WIDTH:0]                  occupied_count,
    output logic [DICT_SIZE-1:0]                 valid_bits,

    // Зарегистрированный канал lookup. Данные запроса поступают на search_data.
    input  logic                                lookup_req_valid,
    output logic                                lookup_req_ready,
    output logic                                lookup_rsp_valid,
    input  logic                                lookup_rsp_ready,
    output logic                                lookup_hit,
    output logic [KEY_WIDTH-1:0]                lookup_key
);

    logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict_words;
    logic [KEY_WIDTH-1:0] target_wr_index;
    logic storage_wr_en, lookup_pending;

    // Автовставка использует только свободную строку. Явный ключ разрешает замещение.
    assign target_wr_index = use_custom_index ? wr_key : next_free_key;
    assign storage_wr_en = add_en && (use_custom_index || !dict_full);

    // Один регистр ответа вмещает новый результат при одновременной выдаче предыдущего.
    assign lookup_req_ready = rst_n && !flush_dict && (!lookup_pending || lookup_rsp_ready);
    assign lookup_rsp_valid = rst_n && !flush_dict && lookup_pending;

    // Снимок поиска отражает содержимое словаря до фронта, в том числе при записи.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lookup_pending <= 1'b0;
            lookup_hit     <= 1'b0;
            lookup_key     <= '0;
        end else if (flush_dict) begin
            lookup_pending <= 1'b0;
        end else if (lookup_req_ready) begin
            lookup_pending <= lookup_req_valid;
            if (lookup_req_valid) begin
                lookup_hit <= hit;
                lookup_key <= hit_key;
            end
        end
    end

    // 1. Модуль параллельного поиска
    tdl_parallel_search #(
        .DATA_WIDTH (DATA_WIDTH),
        .DICT_SIZE  (DICT_SIZE)
    ) u_search (
        .search_word (search_data),
        .dict_words  (dict_words),
        .valid_bits  (valid_bits),
        .hit         (hit),
        .hit_index   (hit_key)
    );

    // 2. Модуль хранения словаря
    tdl_dict_storage #(
        .DATA_WIDTH (DATA_WIDTH),
        .DICT_SIZE  (DICT_SIZE)
    ) u_storage (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (flush_dict),
        .wr_en           (storage_wr_en),
        .wr_index        (target_wr_index),
        .wr_data         (wr_data),
        .dict_words      (dict_words),
        .valid_bits      (valid_bits),
        .occupied_count  (occupied_count),
        .dict_full       (dict_full),
        .next_free_index (next_free_key)
    );

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert (DATA_WIDTH > 0)
            else $error("tdl_dict_unit requires DATA_WIDTH > 0");
        assert (DICT_SIZE >= 2)
            else $error("tdl_dict_unit requires DICT_SIZE >= 2");
    end
`endif

endmodule
`endif
