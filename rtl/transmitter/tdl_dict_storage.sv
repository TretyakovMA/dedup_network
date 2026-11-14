// ============================================================================
// Модуль хранения и добавления/обновления слов словаря
// ============================================================================
module tdl_dict_storage #(
    parameter  int DATA_WIDTH = 32,
    parameter  int DICT_SIZE  = 256,
    localparam int KEY_WIDTH  = $clog2(DICT_SIZE)
) (
    input  logic                                clk,
    input  logic                                rst_n,

    // Синхронная очистка словаря (Command / Config Flush)
    input  logic                                flush,

    // Интерфейс записи/добавления слова
    input  logic                                wr_en,
    input  logic [KEY_WIDTH-1:0]                wr_index,
    input  logic [DATA_WIDTH-1:0]               wr_data,

    // Выходные данные массива для поиска
    output logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict_words,
    output logic [DICT_SIZE-1:0]                valid_bits,

    // Статусная информация
    output logic [KEY_WIDTH:0]                  occupied_count,
    output logic                                dict_full,
    output logic [KEY_WIDTH-1:0]                next_free_index
);

    logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] array_reg;
    logic [DICT_SIZE-1:0]                valid_reg;

    // Запись и управление сбросом
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_reg <= '0;
            array_reg <= '0;
        end else if (flush) begin
            valid_reg <= '0;
        end else if (wr_en) begin
            array_reg[wr_index] <= wr_data;
            valid_reg[wr_index] <= 1'b1;
        end
    end

    assign dict_words = array_reg;
    assign valid_bits = valid_reg;

    // Анализ заполненности и поиск первого свободного слота
    always_comb begin
        occupied_count  = '0;
        next_free_index = '0;

        // Подсчет количества активных ячеек
        for (int i = 0; i < DICT_SIZE; i++) begin
            if (valid_reg[i]) begin
                occupied_count++;
            end
        end

        // Поиск ближайшей свободной ячейки для простого добавления
        for (int i = 0; i < DICT_SIZE; i++) begin
            if (!valid_reg[i]) begin
                next_free_index = KEY_WIDTH'(i);
                break;
            end
        end
    end

    assign dict_full = (occupied_count == DICT_SIZE);

endmodule