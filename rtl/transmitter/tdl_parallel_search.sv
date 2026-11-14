// ============================================================================
// Модуль параллельного поиска слова в несортированном массиве
// ============================================================================
module tdl_parallel_search #(
    parameter  int DATA_WIDTH = 32,
    parameter  int DICT_SIZE  = 256,
    localparam int KEY_WIDTH  = $clog2(DICT_SIZE)
) (
    // Входное слово из FIFO
    input  logic [DATA_WIDTH-1:0]                search_word,
    
    // Текущее состояние массива и маска валидности
    input  logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict_words,
    input  logic [DICT_SIZE-1:0]                 valid_bits,

    // Результат поиска
    output logic                                 hit,
    output logic [KEY_WIDTH-1:0]                 hit_index
);

    logic [DICT_SIZE-1:0] match_vector;

    // 1. Параллельное сравнение искомого слова со всеми ячейками словаря
    always_comb begin
        for (int i = 0; i < DICT_SIZE; i++) begin
            match_vector[i] = valid_bits[i] && (dict_words[i] == search_word);
        end
    end

    // 2. Флаг совпадения (Hit)
    assign hit = |match_vector;

    // 3. Приоритетный кодер (Priority Encoder) для определения индекса совпадения (Key)
    always_comb begin
        hit_index = '0;
        for (int i = 0; i < DICT_SIZE; i++) begin
            if (match_vector[i]) begin
                hit_index = KEY_WIDTH'(i);
                break; // Возвращаем наименьший индекс при дубликатах
            end
        end
    end

endmodule