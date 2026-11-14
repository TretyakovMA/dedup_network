// ============================================================================
// Объединенный модуль словаря дедупликации (Поиск + Хранение)
// ============================================================================
module tdl_dict_unit #(
    parameter int DATA_WIDTH = 32,
    parameter int DICT_SIZE  = 256,
    localparam int KEY_WIDTH  = $clog2(DICT_SIZE)
) (
    input  logic                                clk,
    input  logic                                rst_n,
    input  logic                                flush_dict,

    // Слово для поиска (например, с выхода FIFO)
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
    output logic [KEY_WIDTH:0]                  occupied_count
);

    logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict_words;
    logic [DICT_SIZE-1:0]                valid_bits;

    logic [KEY_WIDTH-1:0] target_wr_index;

    // Выбор индекса для записи (авто-свободный или переданный от внешнего алгоритма)
    assign target_wr_index = use_custom_index ? wr_key : next_free_key;

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
        .wr_en           (add_en),
        .wr_index        (target_wr_index),
        .wr_data         (wr_data),
        .dict_words      (dict_words),
        .valid_bits      (valid_bits),
        .occupied_count  (occupied_count),
        .dict_full       (dict_full),
        .next_free_index (next_free_key)
    );

endmodule