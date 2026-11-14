// ============================================================================
// Модуль FSM-контроллера передатчика дедупликатора
// Формирует кадры RAW, KEY и SYNC в зависимости от результатов поиска
// ============================================================================
module tdl_tx_controller #(
    parameter int DATA_WIDTH = 32,
    parameter int KEY_WIDTH  = 8,
    
    // Префиксы/Типы заголовков кадров (1 байт)
    parameter logic [7:0] HDR_RAW  = 8'hA1, // RAW:  [HDR] + [4B DATA]
    parameter logic [7:0] HDR_KEY  = 8'hB2, // KEY:  [HDR] + [1B KEY]
    parameter logic [7:0] HDR_SYNC = 8'hC3  // SYNC: [HDR] + [4B DATA] + [1B KEY]
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // ------------------------------------------------------------------------
    // Интерфейс входного FIFO 
    // ------------------------------------------------------------------------
    input  logic                    fifo_empty,
    input  logic [DATA_WIDTH-1:0]   fifo_rdata,
    output logic                    fifo_rd_en,

    // ------------------------------------------------------------------------
    // Интерфейс от модуля словаря / результата поиска
    // ------------------------------------------------------------------------
    // Флаг нахождения текущего слова в массиве дедупликации
    input  logic                    dict_hit,
    // Индекс (Key) текущего слова в массиве дедупликации
    input  logic [KEY_WIDTH-1:0]    dict_key,
    // Флаг того, что данное слово будет добавлено в массив дедупликации
    input  logic                    force_sync,

    // ------------------------------------------------------------------------
    // Однобитный выходной SDR-интерфейс
    // ------------------------------------------------------------------------
    output logic                    sdr_data,
    output logic                    sdr_clk,
    input  logic                    sdr_ready
);

    // Типы кадров
    typedef enum logic [1:0] {
        FRAME_RAW  = 2'b00,
        FRAME_KEY  = 2'b01,
        FRAME_SYNC = 2'b10
    } frame_t;

    // Состояния автомата (FSM)
    typedef enum logic [2:0] {
        ST_IDLE,       // Ожидание данных в FIFO
        ST_HEADER,     // Передача 1 байта заголовка
        ST_DATA_3,     // Передача 4-го байта слова (MSB [31:24])
        ST_DATA_2,     // Передача 3-го байта слова ([23:16])
        ST_DATA_1,     // Передача 2-го байта слова ([15:8])
        ST_DATA_0,     // Передача 1-го байта слова (LSB [7:0])
        ST_INDEX       // Передача 1 байта индекса словаря
    } state_t;

    state_t state, next_state;

    // Регистры хранения текущего кадра
    logic [DATA_WIDTH-1:0] latched_data;
    logic [KEY_WIDTH-1:0]  latched_key;
    frame_t                frame_type;

    logic [2:0] bit_count;
    logic bit_handshake;
    logic byte_complete;
    logic sdr_clk_enable;

    assign bit_handshake = sdr_ready;
    assign byte_complete = bit_handshake && (bit_count == 3'd7);
    assign sdr_clk = clk && sdr_clk_enable;

    always_latch begin
        if (!rst_n) begin
            sdr_clk_enable <= 1'b0;
        end
        else if (!clk) begin
            sdr_clk_enable <= (state != ST_IDLE) && sdr_ready;
        end
    end

    always_ff @(negedge sdr_clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_rd_en <= 1'b0;
        end
        else begin
            fifo_rd_en <= sdr_ready && (bit_count == 3'd7) &&
                          ((state == ST_INDEX && frame_type == FRAME_KEY) ||
                           state == ST_DATA_0);
        end
    end

    // ------------------------------------------------------------------------
    // 1. Регистр состояния и защелкивание входных данных
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            latched_data <= '0;
            latched_key  <= '0;
            frame_type   <= FRAME_RAW;
            bit_count    <= '0;
        end 
        else begin
            state <= next_state;

            if (state == ST_IDLE) begin
                bit_count <= '0;
            end
            else if (bit_handshake) begin
                if (bit_count == 3'd7) begin
                    bit_count <= '0;
                end
                else begin
                    bit_count <= bit_count + 1'b1;
                end
            end

            // Защелкивание данных и определение типа кадра при старте
            if (state == ST_IDLE && !fifo_empty) begin
                latched_data <= fifo_rdata;
                latched_key  <= dict_key;

                if (dict_hit) begin
                    frame_type <= FRAME_KEY;
                end 
                else if (force_sync) begin
                    frame_type <= FRAME_SYNC;
                end 
                else begin
                    frame_type <= FRAME_RAW;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 2. Логика переходов FSM и управление вычиткой FIFO
    // ------------------------------------------------------------------------
    always_comb begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (!fifo_empty) begin
                    next_state = ST_HEADER;
                end
            end

            ST_HEADER: begin
                if (byte_complete) begin
                    if (frame_type == FRAME_RAW) begin
                        next_state = ST_DATA_3;
                    end 
                    else begin
                        // Для KEY и SYNC кадров Key отправляется сразу после Header
                        next_state = ST_INDEX;
                    end
                end
            end

            ST_INDEX: begin
                if (byte_complete) begin
                    if (frame_type == FRAME_SYNC) begin
                        next_state = ST_DATA_3; // В SYNC кадрах следом передаются данные
                    end 
                    else begin
                        // KEY кадр завершен -> вычитываем слово из FIFO
                        next_state = ST_IDLE;
                    end
                end
            end

            ST_DATA_3: begin
                if (byte_complete) next_state = ST_DATA_2;
            end

            ST_DATA_2: begin
                if (byte_complete) next_state = ST_DATA_1;
            end

            ST_DATA_1: begin
                if (byte_complete) next_state = ST_DATA_0;
            end

            ST_DATA_0: begin
                if (byte_complete) begin
                    // RAW или SYNC кадр завершен -> вычитываем слово из FIFO
                    next_state = ST_IDLE;
                end
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // ------------------------------------------------------------------------
    // 3. Последовательная передача байтов по SDR
    // ------------------------------------------------------------------------
    // Обновление в низкой фазе clk оставляет sdr_data стабильным на posedge sdr_clk.
    always_latch begin
        if (!rst_n) begin
            sdr_data <= 1'b0;
        end
        else if (!clk) begin
            case (state)
                ST_HEADER: begin
                    case (frame_type)
                        FRAME_RAW:  sdr_data <= HDR_RAW[7-bit_count];
                        FRAME_KEY:  sdr_data <= HDR_KEY[7-bit_count];
                        FRAME_SYNC: sdr_data <= HDR_SYNC[7-bit_count];
                        default:    sdr_data <= HDR_RAW[7-bit_count];
                    endcase
                end

                ST_INDEX: begin
                    sdr_data <= latched_key[7-bit_count];
                end

                ST_DATA_3: begin
                    sdr_data <= latched_data[31-bit_count]; // Big-Endian, MSB first
                end

                ST_DATA_2: begin
                    sdr_data <= latched_data[23-bit_count];
                end

                ST_DATA_1: begin
                    sdr_data <= latched_data[15-bit_count];
                end

                ST_DATA_0: begin
                    sdr_data <= latched_data[7-bit_count];
                end

                default: sdr_data <= 1'b0;
            endcase
        end
    end

endmodule